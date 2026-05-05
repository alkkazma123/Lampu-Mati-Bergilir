--[[
	MainServer.server.lua
	=====================
	Full server-side logic for "Lampu Mati Bergilir":
	  • Procedural city map generation (buildings, streets, lights, switches)
	  • Multi-lobby system (4 independent lobbies per server)
	  • Waiting area, countdown, spectate
	  • Round management (light cycle, entity AI, switch activation)
	  • Coin / XP / Level economy + DataStore persistence
	  • Leaderboard broadcast
	  • Overhead BillboardGui (name + level)
	  • All RemoteEvents auto-created
]]

---------------------------------------------------------------------
-- Services
---------------------------------------------------------------------
local Players            = game:GetService("Players")
local RS                 = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local DataStoreService   = game:GetService("DataStoreService")
local Lighting           = game:GetService("Lighting")

local Config = require(RS:WaitForChild("GameConfig"))

---------------------------------------------------------------------
-- Remote Events / Functions  (auto-create)
---------------------------------------------------------------------
local Remotes = {}
for _, name in ipairs(Config.Remotes) do
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = RS
	Remotes[name] = re
end

---------------------------------------------------------------------
-- DataStore (coins, xp, level)
---------------------------------------------------------------------
local PlayerStore = DataStoreService:GetDataStore("LMB_PlayerData_v1")

local playerData = {} -- [Player] = {Coins, XP, Level}

local function defaultData()
	return { Coins = 0, XP = 0, Level = 1 }
end

local function loadData(player)
	local ok, data = pcall(function()
		return PlayerStore:GetAsync("player_" .. player.UserId)
	end)
	if ok and data then
		playerData[player] = data
	else
		playerData[player] = defaultData()
	end
end

local function saveData(player)
	local data = playerData[player]
	if not data then return end
	pcall(function()
		PlayerStore:SetAsync("player_" .. player.UserId, data)
	end)
end

local function addCoinXP(player, coins, xp)
	local d = playerData[player]
	if not d then return end
	d.Coins = d.Coins + coins
	d.XP    = d.XP + xp
	-- level-up check
	while d.XP >= Config.XP_PER_LEVEL do
		d.XP = d.XP - Config.XP_PER_LEVEL
		d.Level = d.Level + 1
	end
	Remotes.CoinXPUpdate:FireClient(player, d)
	updateOverhead(player)
end

---------------------------------------------------------------------
-- Overhead BillboardGui
---------------------------------------------------------------------
function updateOverhead(player)
	local char = player.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	if not head then return end

	local d = playerData[player] or defaultData()

	local bbg = head:FindFirstChild("OverheadUI")
	if not bbg then
		bbg = Instance.new("BillboardGui")
		bbg.Name = "OverheadUI"
		bbg.Adornee = head
		bbg.Size = UDim2.new(0, 200, 0, 50)
		bbg.StudsOffset = Vector3.new(0, 2.5, 0)
		bbg.AlwaysOnTop = true
		bbg.Parent = head

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
		nameLabel.Position = UDim2.new(0, 0, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextColor3 = Config.UI.TextPrimary
		nameLabel.TextStrokeTransparency = 0.5
		nameLabel.TextScaled = true
		nameLabel.Parent = bbg

		local lvlLabel = Instance.new("TextLabel")
		lvlLabel.Name = "LevelLabel"
		lvlLabel.Size = UDim2.new(1, 0, 0.40, 0)
		lvlLabel.Position = UDim2.new(0, 0, 0.58, 0)
		lvlLabel.BackgroundTransparency = 1
		lvlLabel.Font = Enum.Font.Gotham
		lvlLabel.TextColor3 = Config.UI.Accent
		lvlLabel.TextStrokeTransparency = 0.6
		lvlLabel.TextScaled = true
		lvlLabel.Parent = bbg
	end

	bbg.NameLabel.Text  = player.DisplayName
	bbg.LevelLabel.Text = "Lv." .. tostring(d.Level)
end

---------------------------------------------------------------------
-- MAP GENERATION  (procedural city)
---------------------------------------------------------------------
local cityFolder       -- Folder in Workspace per lobby
local arenaOffsets = {
	Vector3.new(0,    0, 0),
	Vector3.new(500,  0, 0),
	Vector3.new(0,    0, 500),
	Vector3.new(500,  0, 500),
}

local function makePart(parent, size, cframe, color, mat, anchored, name)
	local p = Instance.new("Part")
	p.Name = name or "MapPart"
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = anchored == nil and true or anchored
	p.CanCollide = true
	p.Parent = parent
	return p
end

local function generateArena(lobbyIndex)
	local offset = arenaOffsets[lobbyIndex]
	local folder = Instance.new("Folder")
	folder.Name = "Arena_" .. lobbyIndex
	folder.Parent = workspace

	-- Ground (transparent to avoid z-fighting flicker)
	local ground = makePart(folder,
		Vector3.new(Config.CITY_SIZE, 1, Config.CITY_SIZE),
		CFrame.new(offset + Vector3.new(0, -0.5, 0)),
		Color3.fromRGB(40, 40, 40), Enum.Material.Concrete, true, "Ground"
	)
	ground.Transparency = 1
	ground.CanCollide = true

	-- Roads (cross pattern)
	local roadColor = Color3.fromRGB(55, 55, 55)
	makePart(folder,
		Vector3.new(14, 0.15, Config.CITY_SIZE),
		CFrame.new(offset + Vector3.new(0, 0.1, 0)),
		roadColor, Enum.Material.Concrete, true, "RoadNS"
	)
	makePart(folder,
		Vector3.new(Config.CITY_SIZE, 0.15, 14),
		CFrame.new(offset + Vector3.new(0, 0.1, 0)),
		roadColor, Enum.Material.Concrete, true, "RoadEW"
	)

	-- Buildings
	local rng = Random.new(lobbyIndex * 1234)
	local halfCity = Config.CITY_SIZE / 2
	for i = 1, Config.BUILDING_COUNT do
		local w = rng:NextInteger(10, 28)
		local h = rng:NextInteger(12, 40)
		local d = rng:NextInteger(10, 28)
		local x = rng:NextInteger(-halfCity + w, halfCity - w)
		local z = rng:NextInteger(-halfCity + d, halfCity - d)
		-- skip if too close to roads
		if math.abs(x) > 10 and math.abs(z) > 10 then
			local bColor = Color3.fromRGB(
				rng:NextInteger(25, 50),
				rng:NextInteger(25, 50),
				rng:NextInteger(30, 55)
			)
			makePart(folder,
				Vector3.new(w, h, d),
				CFrame.new(offset + Vector3.new(x, h / 2, z)),
				bColor, Enum.Material.Concrete, true, "Building_" .. i
			)
		end
	end

	-- Street Lights
	local lights = {}
	for i = 1, Config.STREETLIGHT_COUNT do
		local angle = (i / Config.STREETLIGHT_COUNT) * math.pi * 2
		local radius = rng:NextInteger(20, halfCity - 10)
		local lx = math.cos(angle) * radius
		local lz = math.sin(angle) * radius

		-- pole
		local pole = makePart(folder,
			Vector3.new(0.6, 14, 0.6),
			CFrame.new(offset + Vector3.new(lx, 7, lz)),
			Color3.fromRGB(60, 60, 60), Enum.Material.Metal, true, "LightPole_" .. i
		)

		-- lamp head
		local lamp = Instance.new("Part")
		lamp.Name = "Lamp_" .. i
		lamp.Size = Vector3.new(2.5, 1.2, 2.5)
		lamp.CFrame = CFrame.new(offset + Vector3.new(lx, 14.5, lz))
		lamp.Color = Color3.fromRGB(255, 240, 200)
		lamp.Material = Enum.Material.Neon
		lamp.Anchored = true
		lamp.CanCollide = false
		lamp.Parent = folder

		local pl = Instance.new("PointLight")
		pl.Name = "PL"
		pl.Brightness = 1.5
		pl.Range = 35
		pl.Color = Color3.fromRGB(255, 230, 180)
		pl.Parent = lamp

		table.insert(lights, lamp)
	end

	-- Switches
	local switches = {}
	for i = 1, Config.SWITCH_COUNT do
		local sx = rng:NextInteger(-halfCity + 15, halfCity - 15)
		local sz = rng:NextInteger(-halfCity + 15, halfCity - 15)
		local sw = makePart(folder,
			Vector3.new(1.5, 3, 0.5),
			CFrame.new(offset + Vector3.new(sx, 1.5, sz)),
			Color3.fromRGB(200, 60, 60), Enum.Material.SmoothPlastic, true, "Switch_" .. i
		)
		-- ClickDetector for PC, ProximityPrompt for mobile
		local prox = Instance.new("ProximityPrompt")
		prox.Name = "SwitchPrompt"
		prox.ObjectText = "Saklar"
		prox.ActionText = "Nyalakan Lampu"
		prox.MaxActivationDistance = 8
		prox.HoldDuration = 0.5
		prox.Parent = sw
		sw:SetAttribute("Activated", false)
		table.insert(switches, sw)
	end

	-- Spawn points (ring around center)
	local spawns = {}
	for i = 1, Config.MAX_PLAYERS do
		local a = (i / Config.MAX_PLAYERS) * math.pi * 2
		local sp = Instance.new("SpawnLocation")
		sp.Name = "Spawn_" .. i
		sp.Size = Vector3.new(4, 1, 4)
		sp.CFrame = CFrame.new(offset + Vector3.new(math.cos(a) * 15, 0.5, math.sin(a) * 15))
		sp.Anchored = true
		sp.CanCollide = true
		sp.Neutral = false
		sp.Enabled = false       -- we teleport manually
		sp.Transparency = 1
		sp.Parent = folder
		table.insert(spawns, sp)
	end

	-- Waiting area (elevated platform off to the side)
	local waitOffset = offset + Vector3.new(-halfCity - 30, 10, 0)
	local waitPlatform = makePart(folder,
		Vector3.new(30, 1, 30),
		CFrame.new(waitOffset),
		Color3.fromRGB(30, 30, 45), Enum.Material.SmoothPlastic, true, "WaitPlatform"
	)

	-- invisible walls around waiting area
	for _, dir in ipairs({Vector3.new(15,5,0), Vector3.new(-15,5,0), Vector3.new(0,5,15), Vector3.new(0,5,-15)}) do
		local wall = makePart(folder,
			Vector3.new(dir.X == 0 and 30 or 1, 10, dir.Z == 0 and 30 or 1),
			CFrame.new(waitOffset + dir),
			Color3.fromRGB(30, 30, 45), Enum.Material.ForceField, true, "WaitWall"
		)
		wall.Transparency = 0.85
	end

	local waitSpawns = {}
	for i = 1, Config.MAX_PLAYERS do
		local a2 = (i / Config.MAX_PLAYERS) * math.pi * 2
		local ws = Instance.new("SpawnLocation")
		ws.Name = "WaitSpawn_" .. i
		ws.Size = Vector3.new(4, 1, 4)
		ws.CFrame = CFrame.new(waitOffset + Vector3.new(math.cos(a2) * 8, 0.5, math.sin(a2) * 8))
		ws.Anchored = true
		ws.Neutral = false
		ws.Enabled = false
		ws.Transparency = 1
		ws.Parent = folder
		table.insert(waitSpawns, ws)
	end

	return {
		folder      = folder,
		lights      = lights,
		switches    = switches,
		spawns      = spawns,
		waitSpawns  = waitSpawns,
		waitCenter  = waitOffset,
		offset      = offset,
	}
end

---------------------------------------------------------------------
-- LOBBY SYSTEM
---------------------------------------------------------------------
--[[
	lobby = {
		index       : number (1-4),
		host        : Player | nil,
		maxPlayers  : number,
		players     : {Player},
		spectators  : {Player},
		state       : "waiting" | "countdown" | "playing" | "ended",
		arena       : arenaData,
		countdown   : number,
		roundTimer  : number,
		lightsOn    : bool,
		entities    : {Model},
	}
]]

---------------------------------------------------------------------
-- LOBBY HUB (physical spawn area at world origin)
---------------------------------------------------------------------
local function createLobbyHub()
	local hub = Instance.new("Folder")
	hub.Name = "LobbyHub"
	hub.Parent = workspace

	-- Main platform
	local platform = makePart(hub,
		Vector3.new(80, 2, 80),
		CFrame.new(0, -1, -250),
		Color3.fromRGB(22, 22, 32), Enum.Material.SmoothPlastic, true, "LobbyFloor"
	)

	-- Decorative edge glow
	for _, edgePos in ipairs({
		CFrame.new(40, 0.5, -250),
		CFrame.new(-40, 0.5, -250),
		CFrame.new(0, 0.5, -210),
		CFrame.new(0, 0.5, -290),
	}) do
		local edgeSize = edgePos.Position.X == 0
			and Vector3.new(80, 0.3, 1)
			or Vector3.new(1, 0.3, 80)
		local edge = makePart(hub, edgeSize, edgePos,
			Color3.fromRGB(120, 80, 255), Enum.Material.Neon, true, "Edge")
		edge.CanCollide = false
	end

	-- Title sign
	local signPart = makePart(hub,
		Vector3.new(30, 8, 1),
		CFrame.new(0, 8, -290),
		Color3.fromRGB(18, 18, 24), Enum.Material.SmoothPlastic, true, "TitleSign"
	)
	local signGui = Instance.new("SurfaceGui")
	signGui.Name = "SignGui"
	signGui.Adornee = signPart
	signGui.Face = Enum.NormalId.Front
	signGui.Parent = signPart
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.new(1, 0, 1, 0)
	signLabel.BackgroundTransparency = 1
	signLabel.Text = "LAMPU MATI BERGILIR"
	signLabel.Font = Enum.Font.GothamBlack
	signLabel.TextColor3 = Color3.fromRGB(120, 80, 255)
	signLabel.TextScaled = true
	signLabel.Parent = signGui

	-- Lobby selector pillars (4 pillars for 4 lobbies)
	local pillarPositions = {
		Vector3.new(-24, 3, -250),
		Vector3.new(-8, 3, -250),
		Vector3.new(8, 3, -250),
		Vector3.new(24, 3, -250),
	}
	for i, pos in ipairs(pillarPositions) do
		local pillar = makePart(hub,
			Vector3.new(10, 6, 10),
			CFrame.new(pos),
			Color3.fromRGB(32, 32, 44), Enum.Material.SmoothPlastic, true, "LobbyPillar_" .. i
		)
		local corner = Instance.new("UICorner") -- won't work on Part, use mesh instead

		-- Pillar top glow
		local glow = makePart(hub,
			Vector3.new(10, 0.4, 10),
			CFrame.new(pos + Vector3.new(0, 3.2, 0)),
			Color3.fromRGB(120, 80, 255), Enum.Material.Neon, true, "PillarGlow_" .. i
		)
		glow.CanCollide = false

		-- Lobby number sign
		local numSign = Instance.new("SurfaceGui")
		numSign.Name = "LobbyNum"
		numSign.Adornee = pillar
		numSign.Face = Enum.NormalId.Front
		numSign.Parent = pillar
		local numLabel = Instance.new("TextLabel")
		numLabel.Size = UDim2.new(1, 0, 1, 0)
		numLabel.BackgroundTransparency = 1
		numLabel.Text = "LOBBY " .. i
		numLabel.Font = Enum.Font.GothamBlack
		numLabel.TextColor3 = Color3.fromRGB(230, 230, 240)
		numLabel.TextScaled = true
		numLabel.Parent = numSign
	end

	-- Spawn location (center of lobby hub)
	local mainSpawn = Instance.new("SpawnLocation")
	mainSpawn.Name = "LobbySpawn"
	mainSpawn.Size = Vector3.new(12, 1, 12)
	mainSpawn.CFrame = CFrame.new(0, 0, -250)
	mainSpawn.Anchored = true
	mainSpawn.CanCollide = true
	mainSpawn.Neutral = true
	mainSpawn.Enabled = true
	mainSpawn.Transparency = 1
	mainSpawn.Parent = hub

	-- Ambient lights for lobby
	for _, lpos in ipairs({
		Vector3.new(-20, 12, -240), Vector3.new(20, 12, -240),
		Vector3.new(-20, 12, -260), Vector3.new(20, 12, -260),
	}) do
		local lPart = makePart(hub,
			Vector3.new(2, 1, 2),
			CFrame.new(lpos),
			Color3.fromRGB(160, 120, 255), Enum.Material.Neon, true, "LobbyLight"
		)
		lPart.CanCollide = false
		local pl = Instance.new("PointLight")
		pl.Brightness = 1
		pl.Range = 30
		pl.Color = Color3.fromRGB(160, 120, 255)
		pl.Parent = lPart
	end

	return hub
end

local lobbyHub = createLobbyHub()

local lobbies = {}

for i = 1, Config.MAX_LOBBIES do
	local arena = generateArena(i)
	lobbies[i] = {
		index      = i,
		host       = nil,
		maxPlayers = Config.MAX_PLAYERS,
		players    = {},
		spectators = {},
		state      = "waiting",
		arena      = arena,
		countdown  = 0,
		roundTimer = 0,
		lightsOn   = true,
		entities   = {},
	}
end

local playerLobby = {} -- Player → lobbyIndex

local function lobbySnapshot(lobby)
	local pNames = {}
	for _, p in ipairs(lobby.players) do
		local d = playerData[p] or defaultData()
		table.insert(pNames, { Name = p.DisplayName, Level = d.Level, UserId = p.UserId })
	end
	return {
		index      = lobby.index,
		hostName   = lobby.host and lobby.host.DisplayName or "",
		hostId     = lobby.host and lobby.host.UserId or 0,
		maxPlayers = lobby.maxPlayers,
		players    = pNames,
		state      = lobby.state,
		countdown  = lobby.countdown,
		roundTimer = lobby.roundTimer,
	}
end

local function broadcastLobbies()
	local snapshots = {}
	for i, l in ipairs(lobbies) do
		snapshots[i] = lobbySnapshot(l)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		Remotes.LobbyUpdate:FireClient(player, snapshots)
	end
end

local function teleportPlayer(player, cframe)
	local char = player.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.CFrame = cframe + Vector3.new(0, 3, 0)
		end
	end
end

local function removePlayerFromLobby(player)
	local li = playerLobby[player]
	if not li then return end
	local lobby = lobbies[li]

	-- remove from players list
	for idx, p in ipairs(lobby.players) do
		if p == player then
			table.remove(lobby.players, idx)
			break
		end
	end
	-- remove from spectators
	for idx, p in ipairs(lobby.spectators) do
		if p == player then
			table.remove(lobby.spectators, idx)
			break
		end
	end

	-- if host left, reassign
	if lobby.host == player then
		lobby.host = lobby.players[1] or nil
	end

	-- if no players left, reset
	if #lobby.players == 0 then
		lobby.state = "waiting"
		lobby.countdown = 0
		lobby.roundTimer = 0
		cleanupEntities(lobby)
	end

	playerLobby[player] = nil
	broadcastLobbies()
end

---------------------------------------------------------------------
-- ENTITY AI
---------------------------------------------------------------------
local function createEntity(lobby)
	local arena = lobby.arena
	local offset = arena.offset
	local rng = Random.new(tick())

	local model = Instance.new("Model")
	model.Name = "Entity"

	-- body (shadowy humanoid shape)
	local torso = Instance.new("Part")
	torso.Name = "HumanoidRootPart"
	torso.Size = Vector3.new(2.5, 5, 1.5)
	torso.Color = Color3.fromRGB(10, 0, 15)
	torso.Material = Enum.Material.SmoothPlastic
	torso.Transparency = 0.3
	torso.Anchored = true
	torso.CanCollide = false
	torso.Parent = model

	-- glowing eyes
	local eyeL = Instance.new("Part")
	eyeL.Name = "EyeL"
	eyeL.Size = Vector3.new(0.3, 0.3, 0.2)
	eyeL.Color = Color3.fromRGB(255, 0, 0)
	eyeL.Material = Enum.Material.Neon
	eyeL.Anchored = true
	eyeL.CanCollide = false
	eyeL.Parent = model

	local eyeR = eyeL:Clone()
	eyeR.Name = "EyeR"
	eyeR.Parent = model

	-- head
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.8, 1.8, 1.8)
	head.Shape = Enum.PartType.Ball
	head.Color = Color3.fromRGB(8, 0, 12)
	head.Material = Enum.Material.SmoothPlastic
	head.Transparency = 0.25
	head.Anchored = true
	head.CanCollide = false
	head.Parent = model

	-- smoke effect
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(20, 0, 30))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 3),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.5, 1.5)
	smoke.Rate = 30
	smoke.Speed = NumberRange.new(1, 3)
	smoke.Parent = torso

	model.PrimaryPart = torso

	-- spawn far from players
	local sx = rng:NextInteger(-80, 80) + offset.X
	local sz = rng:NextInteger(-80, 80) + offset.Z
	torso.CFrame = CFrame.new(sx, 3, sz)
	head.CFrame  = CFrame.new(sx, 6.2, sz)
	eyeL.CFrame  = CFrame.new(sx - 0.35, 6.3, sz - 0.75)
	eyeR.CFrame  = CFrame.new(sx + 0.35, 6.3, sz - 0.75)

	model.Parent = lobby.arena.folder

	return model
end

local function moveEntityToward(entity, targetPos, dt)
	local hrp = entity:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local current = hrp.Position
	local dir = (targetPos - current) * Vector3.new(1, 0, 1)
	if dir.Magnitude < 1 then return end
	dir = dir.Unit

	local speed = Config.ENTITY_SPEED * dt
	local newPos = current + dir * speed

	local look = CFrame.lookAt(newPos, newPos + dir)
	hrp.CFrame = look + Vector3.new(0, 3 - newPos.Y + current.Y, 0) -- keep height

	-- move other parts relative
	local head = entity:FindFirstChild("Head")
	if head then head.CFrame = hrp.CFrame * CFrame.new(0, 3.2, 0) end
	local el = entity:FindFirstChild("EyeL")
	if el then el.CFrame = hrp.CFrame * CFrame.new(-0.35, 3.3, -0.75) end
	local er = entity:FindFirstChild("EyeR")
	if er then er.CFrame = hrp.CFrame * CFrame.new(0.35, 3.3, -0.75) end
end

local function cleanupEntities(lobby)
	for _, e in ipairs(lobby.entities) do
		if e and e.Parent then e:Destroy() end
	end
	lobby.entities = {}
end

local function getNearestAlivePlayer(lobby, pos)
	local nearest, dist = nil, math.huge
	for _, p in ipairs(lobby.players) do
		local char = p.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			local hum = char:FindFirstChild("Humanoid")
			if hrp and hum and hum.Health > 0 then
				local d = (hrp.Position - pos).Magnitude
				if d < dist then
					nearest = hrp
					dist = d
				end
			end
		end
	end
	return nearest, dist
end

---------------------------------------------------------------------
-- SWITCH ACTIVATION
---------------------------------------------------------------------
local function setupSwitchListeners(lobby)
	for _, sw in ipairs(lobby.arena.switches) do
		local prox = sw:FindFirstChild("SwitchPrompt")
		if prox then
			prox.Triggered:Connect(function(player)
				if lobby.state ~= "playing" then return end
				if sw:GetAttribute("Activated") then return end
				sw:SetAttribute("Activated", true)
				sw.Color = Color3.fromRGB(60, 200, 80)
				prox.Enabled = false

				-- reward
				addCoinXP(player, Config.COIN_SWITCH, Config.XP_SWITCH)
				Remotes.NotifyClient:FireClient(player, "Saklar dinyalakan! +5 Coin, +10 XP")

				-- force lights on briefly
				lobby.lightsOn = true
				setArenaLights(lobby, true)
				Remotes.LightToggle:FireAllClients(lobby.index, true)
			end)
		end
	end
end

local function resetSwitches(lobby)
	for _, sw in ipairs(lobby.arena.switches) do
		sw:SetAttribute("Activated", false)
		sw.Color = Color3.fromRGB(200, 60, 60)
		local prox = sw:FindFirstChild("SwitchPrompt")
		if prox then prox.Enabled = true end
	end
end

---------------------------------------------------------------------
-- LIGHT SYSTEM
---------------------------------------------------------------------
local function setArenaLights(lobby, on)
	for _, lamp in ipairs(lobby.arena.lights) do
		local pl = lamp:FindFirstChild("PL")
		if on then
			lamp.Material = Enum.Material.Neon
			lamp.Color = Color3.fromRGB(255, 240, 200)
			if pl then pl.Enabled = true end
		else
			lamp.Material = Enum.Material.SmoothPlastic
			lamp.Color = Color3.fromRGB(30, 25, 25)
			if pl then pl.Enabled = false end
		end
	end
end

---------------------------------------------------------------------
-- GAME ROUND LOGIC
---------------------------------------------------------------------
local function startRound(lobby)
	lobby.state = "playing"
	lobby.roundTimer = Config.ROUND_DURATION
	lobby.lightsOn = true
	setArenaLights(lobby, true)
	resetSwitches(lobby)
	cleanupEntities(lobby)
	setupSwitchListeners(lobby)

	-- teleport players to arena spawns
	for idx, p in ipairs(lobby.players) do
		local sp = lobby.arena.spawns[idx]
		if sp then
			teleportPlayer(p, sp.CFrame)
		end
	end

	-- notify clients
	for _, p in ipairs(lobby.players) do
		Remotes.GameStart:FireClient(p, lobby.index)
	end
	broadcastLobbies()
end

local function endRound(lobby, won)
	lobby.state = "ended"
	cleanupEntities(lobby)

	-- rewards
	for _, p in ipairs(lobby.players) do
		if won then
			addCoinXP(p, Config.COIN_SURVIVE, Config.XP_SURVIVE)
		end
		Remotes.GameEnd:FireClient(p, lobby.index, won)
	end

	-- after 5 seconds, return to waiting
	task.delay(5, function()
		-- teleport back to waiting area
		for _, p in ipairs(lobby.players) do
			local ws = lobby.arena.waitSpawns[1]
			if ws then teleportPlayer(p, ws.CFrame) end
		end
		lobby.state = "waiting"
		lobby.countdown = 0
		setArenaLights(lobby, true)
		resetSwitches(lobby)
		broadcastLobbies()
	end)

	broadcastLobbies()
end

---------------------------------------------------------------------
-- ROUND UPDATE (RunService)
---------------------------------------------------------------------
local lightTimers = {} -- per lobby

RunService.Heartbeat:Connect(function(dt)
	for i, lobby in ipairs(lobbies) do
		------------------------------------------------------------
		-- COUNTDOWN
		------------------------------------------------------------
		if lobby.state == "countdown" then
			lobby.countdown = lobby.countdown - dt
			if lobby.countdown <= 0 then
				startRound(lobby)
			else
				-- broadcast countdown tick every ~1s
				local sec = math.ceil(lobby.countdown)
				for _, p in ipairs(lobby.players) do
					Remotes.CountdownTick:FireClient(p, lobby.index, sec)
				end
			end
		end

		------------------------------------------------------------
		-- PLAYING
		------------------------------------------------------------
		if lobby.state == "playing" then
			lobby.roundTimer = lobby.roundTimer - dt

			-- check win
			if lobby.roundTimer <= 0 then
				endRound(lobby, true)
			else
				-- check all dead → lose
				local anyAlive = false
				for _, p in ipairs(lobby.players) do
					local char = p.Character
					if char then
						local hum = char:FindFirstChild("Humanoid")
						if hum and hum.Health > 0 then
							anyAlive = true
							break
						end
					end
				end
				if not anyAlive and #lobby.players > 0 then
					endRound(lobby, false)
				end
			end

			-- LIGHT CYCLE
			if not lightTimers[i] then
				lightTimers[i] = { timer = 0, phase = "on" }
			end
			local lt = lightTimers[i]
			lt.timer = lt.timer - dt
			if lt.timer <= 0 then
				if lt.phase == "on" then
					-- turn off
					lt.phase = "off"
					lt.timer = Random.new():NextNumber(Config.DARK_DURATION_MIN, Config.DARK_DURATION_MAX)
					lobby.lightsOn = false
					setArenaLights(lobby, false)
					for _, p in ipairs(lobby.players) do
						Remotes.LightToggle:FireClient(p, lobby.index, false)
					end
					for _, p in ipairs(lobby.spectators) do
						Remotes.LightToggle:FireClient(p, lobby.index, false)
					end
					-- spawn entities
					local count = Random.new():NextInteger(1, 3)
					for _ = 1, count do
						local ent = createEntity(lobby)
						table.insert(lobby.entities, ent)
					end
					-- entity alert
					for _, p in ipairs(lobby.players) do
						Remotes.EntityAlert:FireClient(p, lobby.index)
					end
				else
					-- turn on
					lt.phase = "on"
					lt.timer = Random.new():NextNumber(Config.LIGHT_CYCLE_MIN, Config.LIGHT_CYCLE_MAX)
					lobby.lightsOn = true
					setArenaLights(lobby, true)
					for _, p in ipairs(lobby.players) do
						Remotes.LightToggle:FireClient(p, lobby.index, true)
					end
					for _, p in ipairs(lobby.spectators) do
						Remotes.LightToggle:FireClient(p, lobby.index, true)
					end
					-- remove entities when lights on
					cleanupEntities(lobby)
				end
			end

			-- ENTITY AI – chase nearest player
			if not lobby.lightsOn then
				for _, ent in ipairs(lobby.entities) do
					local hrp = ent:FindFirstChild("HumanoidRootPart")
					if hrp then
						local target, dist = getNearestAlivePlayer(lobby, hrp.Position)
						if target then
							moveEntityToward(ent, target.Position, dt)
							-- jumpscare check (close range)
							if dist < 5 then
								-- damage player
								local char = target.Parent
								local hum = char and char:FindFirstChild("Humanoid")
								if hum and hum.Health > 0 then
									hum.Health = 0
									-- fire jumpscare to that player
									local targetPlayer = Players:GetPlayerFromCharacter(char)
									if targetPlayer then
										Remotes.JumpscareEvent:FireClient(targetPlayer, lobby.index)
									end
								end
							end
						end
					end
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- REMOTE HANDLERS
---------------------------------------------------------------------

-- Request lobby list
Remotes.RequestLobbies.OnServerEvent:Connect(function(player)
	local snapshots = {}
	for i, l in ipairs(lobbies) do
		snapshots[i] = lobbySnapshot(l)
	end
	Remotes.LobbyUpdate:FireClient(player, snapshots)
end)

-- Join lobby
Remotes.JoinLobby.OnServerEvent:Connect(function(player, lobbyIndex, asSpectator)
	if typeof(lobbyIndex) ~= "number" then return end
	lobbyIndex = math.clamp(math.floor(lobbyIndex), 1, Config.MAX_LOBBIES)

	-- remove from current lobby first
	removePlayerFromLobby(player)

	local lobby = lobbies[lobbyIndex]

	if asSpectator then
		table.insert(lobby.spectators, player)
		playerLobby[player] = lobbyIndex
		Remotes.SpectateStart:FireClient(player, lobbyIndex)
		-- teleport to arena center but high up
		teleportPlayer(player, CFrame.new(lobby.arena.offset + Vector3.new(0, 50, 0)))
		broadcastLobbies()
		return
	end

	-- normal join
	if lobby.state == "playing" or lobby.state == "countdown" then
		Remotes.NotifyClient:FireClient(player, "Game sedang berlangsung! Kamu bisa spectate.")
		return
	end
	if #lobby.players >= lobby.maxPlayers then
		Remotes.NotifyClient:FireClient(player, "Lobby penuh!")
		return
	end

	table.insert(lobby.players, player)
	playerLobby[player] = lobbyIndex

	-- first player becomes host
	if not lobby.host then
		lobby.host = player
	end

	-- teleport to waiting area
	local ws = lobby.arena.waitSpawns[math.min(#lobby.players, #lobby.arena.waitSpawns)]
	if ws then
		teleportPlayer(player, ws.CFrame)
	end

	broadcastLobbies()
end)

-- Leave lobby
Remotes.LeaveLobby.OnServerEvent:Connect(function(player)
	removePlayerFromLobby(player)
	-- teleport to world origin (main spawn)
	teleportPlayer(player, CFrame.new(0, 50, -250))
end)

-- Start lobby (host only)
Remotes.StartLobby.OnServerEvent:Connect(function(player, maxPlayers)
	local li = playerLobby[player]
	if not li then return end
	local lobby = lobbies[li]
	if lobby.host ~= player then
		Remotes.NotifyClient:FireClient(player, "Hanya host yang bisa memulai!")
		return
	end
	if lobby.state ~= "waiting" then return end
	if #lobby.players < Config.MIN_PLAYERS then
		Remotes.NotifyClient:FireClient(player, "Minimal " .. Config.MIN_PLAYERS .. " player untuk mulai!")
		return
	end

	-- update max players from host setting
	if typeof(maxPlayers) == "number" then
		lobby.maxPlayers = math.clamp(math.floor(maxPlayers), Config.MIN_PLAYERS, Config.MAX_PLAYERS)
	end

	lobby.state = "countdown"
	lobby.countdown = Config.COUNTDOWN_SECONDS
	broadcastLobbies()
end)

-- Spectate request
Remotes.RequestSpectate.OnServerEvent:Connect(function(player, lobbyIndex)
	if typeof(lobbyIndex) ~= "number" then return end
	lobbyIndex = math.clamp(math.floor(lobbyIndex), 1, Config.MAX_LOBBIES)
	removePlayerFromLobby(player)
	local lobby = lobbies[lobbyIndex]
	table.insert(lobby.spectators, player)
	playerLobby[player] = lobbyIndex
	Remotes.SpectateStart:FireClient(player, lobbyIndex)
	teleportPlayer(player, CFrame.new(lobby.arena.offset + Vector3.new(0, 50, 0)))
	broadcastLobbies()
end)

-- Switch activation (also handled via ProximityPrompt, this is backup for mobile)
Remotes.ActivateSwitch.OnServerEvent:Connect(function(player, switchName)
	local li = playerLobby[player]
	if not li then return end
	local lobby = lobbies[li]
	if lobby.state ~= "playing" then return end

	for _, sw in ipairs(lobby.arena.switches) do
		if sw.Name == switchName and not sw:GetAttribute("Activated") then
			sw:SetAttribute("Activated", true)
			sw.Color = Color3.fromRGB(60, 200, 80)
			local prox = sw:FindFirstChild("SwitchPrompt")
			if prox then prox.Enabled = false end
			addCoinXP(player, Config.COIN_SWITCH, Config.XP_SWITCH)
			Remotes.NotifyClient:FireClient(player, "Saklar dinyalakan! +5 Coin, +10 XP")
			lobby.lightsOn = true
			setArenaLights(lobby, true)
			Remotes.LightToggle:FireAllClients(lobby.index, true)
			break
		end
	end
end)

---------------------------------------------------------------------
-- LEADERBOARD (broadcast every 10s)
---------------------------------------------------------------------
local function buildLeaderboard()
	local lb = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local d = playerData[player]
		if d then
			table.insert(lb, {
				Name  = player.DisplayName,
				Level = d.Level,
				Coins = d.Coins,
				XP    = d.XP,
			})
		end
	end
	table.sort(lb, function(a, b)
		if a.Level ~= b.Level then return a.Level > b.Level end
		return a.Coins > b.Coins
	end)
	return lb
end

task.spawn(function()
	while true do
		task.wait(10)
		local lb = buildLeaderboard()
		for _, player in ipairs(Players:GetPlayers()) do
			Remotes.LeaderboardData:FireClient(player, lb)
		end
	end
end)

---------------------------------------------------------------------
-- PLAYER JOIN / LEAVE
---------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	loadData(player)

	-- send initial data
	task.delay(2, function()
		if player.Parent then
			Remotes.CoinXPUpdate:FireClient(player, playerData[player] or defaultData())
			broadcastLobbies()
			Remotes.LeaderboardData:FireClient(player, buildLeaderboard())
		end
	end)

	player.CharacterAdded:Connect(function(char)
		task.defer(function()
			updateOverhead(player)
		end)
		-- respawn handling
		local hum = char:WaitForChild("Humanoid", 5)
		if hum then
			hum.Died:Connect(function()
				-- auto respawn after 4s
				task.delay(4, function()
					if player.Parent then
						player:LoadCharacter()
					end
				end)
			end)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	removePlayerFromLobby(player)
	saveData(player)
	playerData[player] = nil
end)

-- Periodic save (every 120s)
task.spawn(function()
	while true do
		task.wait(120)
		for _, player in ipairs(Players:GetPlayers()) do
			saveData(player)
		end
	end
end)

---------------------------------------------------------------------
-- LIGHTING SETUP (horror atmosphere)
---------------------------------------------------------------------
Lighting.Ambient = Color3.fromRGB(15, 10, 20)
Lighting.OutdoorAmbient = Color3.fromRGB(10, 8, 15)
Lighting.Brightness = 0.2
Lighting.ClockTime = 0.5   -- midnight
Lighting.FogEnd = 250
Lighting.FogStart = 10
Lighting.FogColor = Color3.fromRGB(5, 3, 8)

-- Atmosphere
local atm = Instance.new("Atmosphere")
atm.Density = 0.4
atm.Offset = 0.1
atm.Color = Color3.fromRGB(8, 5, 12)
atm.Decay = Color3.fromRGB(10, 8, 15)
atm.Glare = 0
atm.Haze = 8
atm.Parent = Lighting

-- Bloom
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.8
bloom.Size = 30
bloom.Threshold = 1.5
bloom.Parent = Lighting

-- ColorCorrection (dark tint)
local cc = Instance.new("ColorCorrectionEffect")
cc.Brightness = -0.05
cc.Contrast = 0.15
cc.Saturation = -0.2
cc.TintColor = Color3.fromRGB(200, 180, 255)
cc.Parent = Lighting

print("[LMB Server] Lampu Mati Bergilir server loaded successfully!")
