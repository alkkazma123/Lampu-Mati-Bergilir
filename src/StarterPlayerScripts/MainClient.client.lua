--[[
	MainClient.client.lua
	=====================
	Full client-side logic for "Lampu Mati Bergilir":
	  • Loading Screen (real asset load)
	  • Rules / How-To-Play overlay (first join, closeable)
	  • Lobby Picker UI (4 lobbies, host settings, join/spectate)
	  • Waiting Room HUD + Countdown
	  • In-Game HUD (timer, notifications bar)
	  • Win / Lose screen
	  • Jumpscare overlay
	  • Camera shake on lights-off
	  • Sound manager (ambient, SFX)
	  • Leaderboard panel
	  • Coin / XP / Level HUD
	  • Mobile-friendly (touch buttons, scaled UI)
	  • Spectate camera
	  • Top notification banner
	  • All UI auto-created via script (no StarterGui assets needed)
]]

---------------------------------------------------------------------
-- Services
---------------------------------------------------------------------
local Players           = game:GetService("Players")
local RS                = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ContentProvider   = game:GetService("ContentProvider")
local SoundService      = game:GetService("SoundService")
local StarterGui        = game:GetService("StarterGui")

local Config = require(RS:WaitForChild("GameConfig"))

local player   = Players.LocalPlayer
local camera   = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- Wait for remotes
---------------------------------------------------------------------
local Remotes = {}
for _, name in ipairs(Config.Remotes) do
	Remotes[name] = RS:WaitForChild(name, 30)
end

---------------------------------------------------------------------
-- Disable default Roblox UI
---------------------------------------------------------------------
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

---------------------------------------------------------------------
-- HELPER: create UI elements
---------------------------------------------------------------------
local UI = Config.UI

local function newFrame(props)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = props.Color or UI.BgPrimary
	f.BackgroundTransparency = props.Transparency or 0
	f.BorderSizePixel = 0
	f.Size = props.Size or UDim2.new(1, 0, 1, 0)
	f.Position = props.Position or UDim2.new(0, 0, 0, 0)
	f.AnchorPoint = props.Anchor or Vector2.new(0, 0)
	f.Name = props.Name or "Frame"
	f.ClipsDescendants = props.Clip or false
	f.Visible = props.Visible == nil and true or props.Visible
	if props.Corner then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, props.Corner)
		c.Parent = f
	end
	if props.Parent then f.Parent = props.Parent end
	return f
end

local function newLabel(props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = props.Size or UDim2.new(1, 0, 0, 30)
	l.Position = props.Position or UDim2.new(0, 0, 0, 0)
	l.AnchorPoint = props.Anchor or Vector2.new(0, 0)
	l.Font = props.Font or Enum.Font.GothamBold
	l.TextColor3 = props.Color or UI.TextPrimary
	l.TextSize = props.TextSize or 18
	l.Text = props.Text or ""
	l.TextScaled = props.Scaled or false
	l.TextXAlignment = props.XAlign or Enum.TextXAlignment.Center
	l.TextYAlignment = props.YAlign or Enum.TextYAlignment.Center
	l.Name = props.Name or "Label"
	l.RichText = props.Rich or false
	l.TextWrapped = props.Wrap or false
	if props.Parent then l.Parent = props.Parent end
	return l
end

local function newButton(props)
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = props.Color or UI.Accent
	b.BorderSizePixel = 0
	b.Size = props.Size or UDim2.new(0, 160, 0, 42)
	b.Position = props.Position or UDim2.new(0.5, 0, 0.5, 0)
	b.AnchorPoint = props.Anchor or Vector2.new(0.5, 0.5)
	b.Font = props.Font or Enum.Font.GothamBold
	b.TextColor3 = props.TextColor or UI.TextPrimary
	b.TextSize = props.TextSize or 16
	b.Text = props.Text or "Button"
	b.Name = props.Name or "Button"
	b.AutoButtonColor = true
	if props.Corner then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, props.Corner)
		c.Parent = b
	end
	if props.Parent then b.Parent = props.Parent end
	return b
end

local function newScroll(props)
	local s = Instance.new("ScrollingFrame")
	s.BackgroundTransparency = 1
	s.Size = props.Size or UDim2.new(1, 0, 1, 0)
	s.Position = props.Position or UDim2.new(0, 0, 0, 0)
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 4
	s.ScrollBarImageColor3 = UI.Accent
	s.CanvasSize = props.CanvasSize or UDim2.new(0, 0, 0, 0)
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.Name = props.Name or "Scroll"
	if props.Parent then s.Parent = props.Parent end
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, props.Padding or 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = s
	return s
end

---------------------------------------------------------------------
-- SCREEN GUI container
---------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LMB_UI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

---------------------------------------------------------------------
-- AUTO-SCALE: adapts all UI to any screen size / device
---------------------------------------------------------------------
local function getScale()
	local viewport = camera.ViewportSize
	local baseWidth = 1920
	local baseHeight = 1080
	local scaleX = viewport.X / baseWidth
	local scaleY = viewport.Y / baseHeight
	return math.min(scaleX, scaleY, 1.2)  -- cap at 1.2x for large screens
end

local uiScale = Instance.new("UIScale")
uiScale.Scale = math.max(getScale(), 0.45)  -- min 0.45x for very small screens
uiScale.Parent = screenGui

camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	uiScale.Scale = math.clamp(getScale(), 0.45, 1.2)
end)

---------------------------------------------------------------------
-- 1. LOADING SCREEN
---------------------------------------------------------------------
local loadingFrame = newFrame({
	Name = "LoadingScreen",
	Size = UDim2.new(1, 0, 1, 0),
	Color = Color3.fromRGB(8, 6, 14),
	Parent = screenGui,
})
loadingFrame.ZIndex = 100

local loadTitle = newLabel({
	Text = "LAMPU MATI BERGILIR",
	Size = UDim2.new(0.8, 0, 0, 50),
	Position = UDim2.new(0.5, 0, 0.35, 0),
	Anchor = Vector2.new(0.5, 0.5),
	TextSize = 36,
	Font = Enum.Font.GothamBlack,
	Color = UI.Accent,
	Parent = loadingFrame,
})
loadTitle.ZIndex = 101

local loadSubtitle = newLabel({
	Text = "Memuat aset...",
	Size = UDim2.new(0.6, 0, 0, 30),
	Position = UDim2.new(0.5, 0, 0.45, 0),
	Anchor = Vector2.new(0.5, 0.5),
	TextSize = 16,
	Font = Enum.Font.Gotham,
	Color = UI.TextSecondary,
	Parent = loadingFrame,
})
loadSubtitle.ZIndex = 101

-- progress bar
local loadBarBg = newFrame({
	Name = "LoadBarBg",
	Size = UDim2.new(0.4, 0, 0, 8),
	Position = UDim2.new(0.5, 0, 0.52, 0),
	Anchor = Vector2.new(0.5, 0.5),
	Color = UI.BgSecondary,
	Corner = 4,
	Parent = loadingFrame,
})
loadBarBg.ZIndex = 101

local loadBarFill = newFrame({
	Name = "Fill",
	Size = UDim2.new(0, 0, 1, 0),
	Color = UI.Accent,
	Corner = 4,
	Parent = loadBarBg,
})
loadBarFill.ZIndex = 102

-- actual loading
task.spawn(function()
	-- gather assets to preload
	local assets = {}
	for _, id in pairs(Config.Sounds) do
		table.insert(assets, id)
	end
	-- preload
	local total = math.max(#assets, 1)
	local loaded = 0
	for _, asset in ipairs(assets) do
		pcall(function()
			ContentProvider:PreloadAsync({asset})
		end)
		loaded = loaded + 1
		local pct = loaded / total
		loadBarFill.Size = UDim2.new(pct, 0, 1, 0)
		loadSubtitle.Text = string.format("Memuat aset... %d%%", math.floor(pct * 100))
	end
	loadBarFill.Size = UDim2.new(1, 0, 1, 0)
	loadSubtitle.Text = "Selesai!"
	task.wait(0.8)
	-- fade out
	TweenService:Create(loadingFrame, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(loadTitle, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
	TweenService:Create(loadSubtitle, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
	TweenService:Create(loadBarBg, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(loadBarFill, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	task.wait(0.7)
	loadingFrame.Visible = false
	showRulesIfFirst()
end)

---------------------------------------------------------------------
-- 2. RULES / HOW-TO-PLAY
---------------------------------------------------------------------
local rulesFrame = newFrame({
	Name = "Rules",
	Size = UDim2.new(0.7, 0, 0.75, 0),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Anchor = Vector2.new(0.5, 0.5),
	Color = UI.BgPrimary,
	Corner = 12,
	Visible = false,
	Parent = screenGui,
})
rulesFrame.ZIndex = 90

-- title bar
local rulesTitle = newLabel({
	Text = "CARA BERMAIN",
	Size = UDim2.new(1, 0, 0, 45),
	TextSize = 24,
	Font = Enum.Font.GothamBlack,
	Color = UI.Accent,
	Parent = rulesFrame,
})
rulesTitle.ZIndex = 91

local rulesBody = newLabel({
	Text = [[
<b>LAMPU MATI BERGILIR</b> — Game Horror Ringan

<b>Tujuan:</b> Bertahan hidup sampai waktu habis!

<b>Aturan:</b>
• Pilih salah satu dari 4 lobby yang tersedia
• Host bisa mengatur jumlah pemain (1-8) dan memulai game
• Setelah countdown 15 detik, kamu akan di-teleport ke kota gelap
• Lampu kota akan mati dan nyala secara acak
• Saat lampu MATI, entitas misterius akan muncul dan mengejarmu!
• Cari SAKLAR (kotak merah) untuk menyalakan lampu kembali
• Setiap saklar yang kamu nyalakan memberi Coin dan XP

<b>Tips:</b>
• Jangan diam di tempat gelap terlalu lama
• Perhatikan suara — entitas mendekat terdengar lebih keras
• Kerja sama dengan teman untuk cari saklar lebih cepat

<b>Kontrol:</b>
• PC: WASD + Mouse, E untuk saklar
• Mobile: Virtual joystick + tap saklar

<b>Reward:</b>
• Survive = 25 Coin + 50 XP
• Setiap saklar = 5 Coin + 10 XP
• Level up setiap 100 XP

Selamat bermain! 🔦
]],
	Size = UDim2.new(0.9, 0, 0, 380),
	Position = UDim2.new(0.05, 0, 0, 50),
	TextSize = 14,
	Font = Enum.Font.Gotham,
	Color = UI.TextPrimary,
	XAlign = Enum.TextXAlignment.Left,
	YAlign = Enum.TextYAlignment.Top,
	Rich = true,
	Wrap = true,
	Scaled = false,
	Parent = rulesFrame,
})
rulesBody.ZIndex = 91

local rulesClose = newButton({
	Text = "MENGERTI!",
	Size = UDim2.new(0.4, 0, 0, 42),
	Position = UDim2.new(0.5, 0, 1, -30),
	Anchor = Vector2.new(0.5, 1),
	Corner = 8,
	Parent = rulesFrame,
})
rulesClose.ZIndex = 92
rulesClose.MouseButton1Click:Connect(function()
	rulesFrame.Visible = false
	lobbyFrame.Visible = true
end)

function showRulesIfFirst()
	-- always show rules on first join
	rulesFrame.Visible = true
end

---------------------------------------------------------------------
-- 3. LOBBY PICKER UI
---------------------------------------------------------------------
local lobbyFrame = newFrame({
	Name = "LobbyPicker",
	Size = UDim2.new(0.85, 0, 0.8, 0),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Anchor = Vector2.new(0.5, 0.5),
	Color = UI.BgPrimary,
	Corner = 12,
	Visible = false,
	Parent = screenGui,
})
lobbyFrame.ZIndex = 80

local lobbyTitle = newLabel({
	Text = "PILIH LOBBY",
	Size = UDim2.new(1, 0, 0, 45),
	TextSize = 26,
	Font = Enum.Font.GothamBlack,
	Color = UI.Accent,
	Parent = lobbyFrame,
})
lobbyTitle.ZIndex = 81

-- lobby cards container
local lobbyCardsFrame = newFrame({
	Name = "Cards",
	Size = UDim2.new(0.95, 0, 0, 0),
	Position = UDim2.new(0.025, 0, 0, 55),
	Transparency = 1,
	Parent = lobbyFrame,
})
lobbyCardsFrame.AutomaticSize = Enum.AutomaticSize.Y
lobbyCardsFrame.ZIndex = 81
local cardsLayout = Instance.new("UIGridLayout")
cardsLayout.CellSize = UDim2.new(0.48, 0, 0, 220)
cardsLayout.CellPadding = UDim2.new(0.02, 0, 0, 10)
cardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardsLayout.Parent = lobbyCardsFrame

local lobbyCards = {}  -- lobby index → card frame

for i = 1, Config.MAX_LOBBIES do
	local card = newFrame({
		Name = "LobbyCard_" .. i,
		Size = UDim2.new(0, 0, 0, 0), -- managed by grid
		Color = UI.CardBg,
		Corner = 10,
		Parent = lobbyCardsFrame,
	})
	card.LayoutOrder = i
	card.ZIndex = 82

	local cardTitle = newLabel({
		Name = "Title",
		Text = "LOBBY " .. i,
		Size = UDim2.new(1, 0, 0, 32),
		TextSize = 18,
		Font = Enum.Font.GothamBlack,
		Color = UI.AccentGlow,
		Parent = card,
	})
	cardTitle.ZIndex = 83

	local cardStatus = newLabel({
		Name = "Status",
		Text = "Menunggu...",
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, 32),
		TextSize = 13,
		Font = Enum.Font.Gotham,
		Color = UI.TextSecondary,
		Parent = card,
	})
	cardStatus.ZIndex = 83

	local cardPlayers = newLabel({
		Name = "Players",
		Text = "0/8 Pemain",
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, 54),
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		Color = UI.TextPrimary,
		Parent = card,
	})
	cardPlayers.ZIndex = 83

	-- player list scroll
	local pList = newScroll({
		Name = "PlayerList",
		Size = UDim2.new(0.9, 0, 0, 60),
		Position = UDim2.new(0.05, 0, 0, 78),
		Padding = 2,
		Parent = card,
	})
	pList.ZIndex = 83

	-- Max players slider label
	local maxLabel = newLabel({
		Name = "MaxLabel",
		Text = "Max: 8",
		Size = UDim2.new(0.5, 0, 0, 20),
		Position = UDim2.new(0.05, 0, 0, 142),
		TextSize = 12,
		Font = Enum.Font.Gotham,
		Color = UI.TextSecondary,
		XAlign = Enum.TextXAlignment.Left,
		Parent = card,
	})
	maxLabel.ZIndex = 83

	-- buttons
	local joinBtn = newButton({
		Name = "JoinBtn",
		Text = "GABUNG",
		Size = UDim2.new(0.42, 0, 0, 34),
		Position = UDim2.new(0.28, 0, 0, 170),
		Anchor = Vector2.new(0.5, 0),
		Corner = 6,
		TextSize = 13,
		Parent = card,
	})
	joinBtn.ZIndex = 84

	local spectBtn = newButton({
		Name = "SpectBtn",
		Text = "TONTON",
		Size = UDim2.new(0.42, 0, 0, 34),
		Position = UDim2.new(0.72, 0, 0, 170),
		Anchor = Vector2.new(0.5, 0),
		Color = UI.BgSecondary,
		Corner = 6,
		TextSize = 13,
		Parent = card,
	})
	spectBtn.ZIndex = 84

	-- event handlers
	joinBtn.MouseButton1Click:Connect(function()
		Remotes.JoinLobby:FireServer(i, false)
		lobbyFrame.Visible = false
		waitingFrame.Visible = true
	end)

	spectBtn.MouseButton1Click:Connect(function()
		Remotes.RequestSpectate:FireServer(i)
		lobbyFrame.Visible = false
	end)

	lobbyCards[i] = card
end

-- Lobby refresh
local function updateLobbyUI(snapshots)
	if not snapshots then return end
	for i, snap in ipairs(snapshots) do
		local card = lobbyCards[i]
		if card then
			local status = card:FindFirstChild("Status")
			local pLabel = card:FindFirstChild("Players")
			local pList  = card:FindFirstChild("PlayerList")
			local maxLbl = card:FindFirstChild("MaxLabel")
			local joinB  = card:FindFirstChild("JoinBtn")

			if status then
				local stateText = {
					waiting   = "Menunggu pemain...",
					countdown = "Countdown: " .. tostring(snap.countdown or 0) .. "s",
					playing   = "Sedang bermain",
					ended     = "Selesai",
				}
				status.Text = stateText[snap.state] or snap.state
				status.TextColor3 = snap.state == "playing" and UI.Danger or UI.TextSecondary
			end
			if pLabel then
				pLabel.Text = tostring(#snap.players) .. "/" .. tostring(snap.maxPlayers) .. " Pemain"
			end
			if maxLbl then
				maxLbl.Text = "Max: " .. tostring(snap.maxPlayers)
			end
			if joinB then
				if snap.state == "playing" or snap.state == "countdown" then
					joinB.Text = "PENUH"
					joinB.BackgroundColor3 = UI.BgSecondary
				else
					joinB.Text = "GABUNG"
					joinB.BackgroundColor3 = UI.Accent
				end
			end
			-- player list
			if pList then
				for _, child in ipairs(pList:GetChildren()) do
					if child:IsA("TextLabel") then child:Destroy() end
				end
				for idx, pInfo in ipairs(snap.players) do
					local pEntry = newLabel({
						Name = "P_" .. idx,
						Text = pInfo.Name .. " (Lv." .. pInfo.Level .. ")",
						Size = UDim2.new(1, 0, 0, 16),
						TextSize = 11,
						Font = Enum.Font.Gotham,
						Color = UI.TextPrimary,
						XAlign = Enum.TextXAlignment.Left,
						Parent = pList,
					})
					pEntry.LayoutOrder = idx
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- 4. WAITING ROOM HUD
---------------------------------------------------------------------
local waitingFrame = newFrame({
	Name = "WaitingHUD",
	Size = UDim2.new(0.4, 0, 0, 200),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Anchor = Vector2.new(0.5, 0.5),
	Color = UI.BgPrimary,
	Corner = 12,
	Visible = false,
	Parent = screenGui,
})
waitingFrame.ZIndex = 75

local waitTitle = newLabel({
	Text = "MENUNGGU PEMAIN",
	Size = UDim2.new(1, 0, 0, 35),
	TextSize = 20,
	Font = Enum.Font.GothamBlack,
	Color = UI.Accent,
	Parent = waitingFrame,
})
waitTitle.ZIndex = 76

local waitCountdown = newLabel({
	Name = "Countdown",
	Text = "",
	Size = UDim2.new(1, 0, 0, 50),
	Position = UDim2.new(0, 0, 0, 40),
	TextSize = 40,
	Font = Enum.Font.GothamBlack,
	Color = UI.TextPrimary,
	Parent = waitingFrame,
})
waitCountdown.ZIndex = 76

-- max player setting (host only)
local maxSliderLabel = newLabel({
	Name = "MaxSliderLabel",
	Text = "Jumlah Max Pemain: 8",
	Size = UDim2.new(0.9, 0, 0, 22),
	Position = UDim2.new(0.05, 0, 0, 95),
	TextSize = 13,
	Font = Enum.Font.Gotham,
	Color = UI.TextSecondary,
	XAlign = Enum.TextXAlignment.Left,
	Parent = waitingFrame,
})
maxSliderLabel.ZIndex = 76

local maxMinusBtn = newButton({
	Name = "MaxMinus",
	Text = "-",
	Size = UDim2.new(0, 34, 0, 28),
	Position = UDim2.new(0.55, 0, 0, 93),
	Anchor = Vector2.new(0, 0),
	Corner = 6,
	Color = UI.BgSecondary,
	TextSize = 18,
	Parent = waitingFrame,
})
maxMinusBtn.ZIndex = 77

local maxPlusBtn = newButton({
	Name = "MaxPlus",
	Text = "+",
	Size = UDim2.new(0, 34, 0, 28),
	Position = UDim2.new(0.72, 0, 0, 93),
	Anchor = Vector2.new(0, 0),
	Corner = 6,
	Color = UI.BgSecondary,
	TextSize = 18,
	Parent = waitingFrame,
})
maxPlusBtn.ZIndex = 77

local currentMaxPlayers = 8

maxMinusBtn.MouseButton1Click:Connect(function()
	currentMaxPlayers = math.max(1, currentMaxPlayers - 1)
	maxSliderLabel.Text = "Jumlah Max Pemain: " .. currentMaxPlayers
end)

maxPlusBtn.MouseButton1Click:Connect(function()
	currentMaxPlayers = math.min(8, currentMaxPlayers + 1)
	maxSliderLabel.Text = "Jumlah Max Pemain: " .. currentMaxPlayers
end)

local startBtn = newButton({
	Name = "StartBtn",
	Text = "MULAI GAME",
	Size = UDim2.new(0.5, 0, 0, 38),
	Position = UDim2.new(0.25, 0, 0, 130),
	Anchor = Vector2.new(0, 0),
	Corner = 8,
	Parent = waitingFrame,
})
startBtn.ZIndex = 77

local leaveBtn = newButton({
	Name = "LeaveBtn",
	Text = "KELUAR",
	Size = UDim2.new(0.3, 0, 0, 38),
	Position = UDim2.new(0.78, 0, 0, 130),
	Anchor = Vector2.new(0, 0),
	Color = UI.Danger,
	Corner = 8,
	TextSize = 14,
	Parent = waitingFrame,
})
leaveBtn.ZIndex = 77

startBtn.MouseButton1Click:Connect(function()
	Remotes.StartLobby:FireServer(currentMaxPlayers)
end)

leaveBtn.MouseButton1Click:Connect(function()
	Remotes.LeaveLobby:FireServer()
	waitingFrame.Visible = false
	lobbyFrame.Visible = true
end)

---------------------------------------------------------------------
-- 5. IN-GAME HUD
---------------------------------------------------------------------
local gameHud = newFrame({
	Name = "GameHUD",
	Size = UDim2.new(1, 0, 1, 0),
	Transparency = 1,
	Visible = false,
	Parent = screenGui,
})
gameHud.ZIndex = 50

-- Timer display (top center)
local timerLabel = newLabel({
	Name = "Timer",
	Text = "02:00",
	Size = UDim2.new(0, 140, 0, 45),
	Position = UDim2.new(0.5, 0, 0, 10),
	Anchor = Vector2.new(0.5, 0),
	TextSize = 30,
	Font = Enum.Font.GothamBlack,
	Color = UI.TextPrimary,
	Parent = gameHud,
})
timerLabel.ZIndex = 51

-- Timer background
local timerBg = newFrame({
	Name = "TimerBg",
	Size = UDim2.new(0, 160, 0, 50),
	Position = UDim2.new(0.5, 0, 0, 8),
	Anchor = Vector2.new(0.5, 0),
	Color = UI.BgPrimary,
	Corner = 10,
	Parent = gameHud,
})
timerBg.ZIndex = 50
timerBg.BackgroundTransparency = 0.3

-- Coin/XP display (top left)
local coinXpFrame = newFrame({
	Name = "CoinXP",
	Size = UDim2.new(0, 200, 0, 55),
	Position = UDim2.new(0, 15, 0, 10),
	Color = UI.BgPrimary,
	Corner = 8,
	Parent = gameHud,
})
coinXpFrame.ZIndex = 51
coinXpFrame.BackgroundTransparency = 0.3

local coinLabel = newLabel({
	Name = "CoinLabel",
	Text = "🪙 0",
	Size = UDim2.new(1, 0, 0.5, 0),
	TextSize = 15,
	Font = Enum.Font.GothamBold,
	Color = Color3.fromRGB(255, 215, 0),
	XAlign = Enum.TextXAlignment.Left,
	Parent = coinXpFrame,
})
coinLabel.ZIndex = 52

local xpLabel = newLabel({
	Name = "XPLabel",
	Text = "Lv.1 | XP: 0/100",
	Size = UDim2.new(1, -10, 0.5, 0),
	Position = UDim2.new(0, 5, 0.5, 0),
	TextSize = 12,
	Font = Enum.Font.Gotham,
	Color = UI.Accent,
	XAlign = Enum.TextXAlignment.Left,
	Parent = coinXpFrame,
})
xpLabel.ZIndex = 52

-- Warning label (center, flashes when lights off)
local warningLabel = newLabel({
	Name = "Warning",
	Text = "⚠ LAMPU MATI! CARI SAKLAR!",
	Size = UDim2.new(0.6, 0, 0, 40),
	Position = UDim2.new(0.5, 0, 0.15, 0),
	Anchor = Vector2.new(0.5, 0.5),
	TextSize = 22,
	Font = Enum.Font.GothamBlack,
	Color = UI.Danger,
	Visible = false,
	Parent = gameHud,
})
warningLabel.ZIndex = 55

---------------------------------------------------------------------
-- 6. NOTIFICATION BANNER (top)
---------------------------------------------------------------------
local notifFrame = newFrame({
	Name = "NotifBanner",
	Size = UDim2.new(0.5, 0, 0, 40),
	Position = UDim2.new(0.5, 0, 0, -50),
	Anchor = Vector2.new(0.5, 0),
	Color = UI.Accent,
	Corner = 8,
	Parent = screenGui,
})
notifFrame.ZIndex = 95

local notifLabel = newLabel({
	Text = "",
	Size = UDim2.new(0.9, 0, 1, 0),
	Position = UDim2.new(0.05, 0, 0, 0),
	TextSize = 14,
	Font = Enum.Font.GothamBold,
	Color = UI.TextPrimary,
	Parent = notifFrame,
})
notifLabel.ZIndex = 96

local function showNotification(text, duration)
	notifLabel.Text = text
	TweenService:Create(notifFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Position = UDim2.new(0.5, 0, 0, 10)
	}):Play()
	task.delay(duration or 3, function()
		TweenService:Create(notifFrame, TweenInfo.new(0.3), {
			Position = UDim2.new(0.5, 0, 0, -50)
		}):Play()
	end)
end

---------------------------------------------------------------------
-- 7. WIN / LOSE SCREEN
---------------------------------------------------------------------
local resultFrame = newFrame({
	Name = "ResultScreen",
	Size = UDim2.new(1, 0, 1, 0),
	Color = Color3.fromRGB(0, 0, 0),
	Transparency = 0.5,
	Visible = false,
	Parent = screenGui,
})
resultFrame.ZIndex = 85

local resultTitle = newLabel({
	Name = "ResultTitle",
	Text = "KAMU MENANG!",
	Size = UDim2.new(0.8, 0, 0, 70),
	Position = UDim2.new(0.5, 0, 0.35, 0),
	Anchor = Vector2.new(0.5, 0.5),
	TextSize = 48,
	Font = Enum.Font.GothamBlack,
	Color = UI.Success,
	Parent = resultFrame,
})
resultTitle.ZIndex = 86

local resultSub = newLabel({
	Name = "ResultSub",
	Text = "Kembali ke lobby dalam 5 detik...",
	Size = UDim2.new(0.6, 0, 0, 30),
	Position = UDim2.new(0.5, 0, 0.45, 0),
	Anchor = Vector2.new(0.5, 0.5),
	TextSize = 16,
	Font = Enum.Font.Gotham,
	Color = UI.TextSecondary,
	Parent = resultFrame,
})
resultSub.ZIndex = 86

---------------------------------------------------------------------
-- 8. JUMPSCARE OVERLAY
---------------------------------------------------------------------
local jumpscareFrame = newFrame({
	Name = "Jumpscare",
	Size = UDim2.new(1, 0, 1, 0),
	Color = Color3.fromRGB(0, 0, 0),
	Visible = false,
	Parent = screenGui,
})
jumpscareFrame.ZIndex = 99

local jumpscareEyes = newLabel({
	Text = "👁  👁",
	Size = UDim2.new(0.5, 0, 0, 120),
	Position = UDim2.new(0.5, 0, 0.4, 0),
	Anchor = Vector2.new(0.5, 0.5),
	TextSize = 80,
	Font = Enum.Font.GothamBlack,
	Color = Color3.fromRGB(255, 0, 0),
	Parent = jumpscareFrame,
})
jumpscareEyes.ZIndex = 100

local jumpscareText = newLabel({
	Text = "KAMU TERTANGKAP!",
	Size = UDim2.new(0.8, 0, 0, 50),
	Position = UDim2.new(0.5, 0, 0.55, 0),
	Anchor = Vector2.new(0.5, 0.5),
	TextSize = 36,
	Font = Enum.Font.GothamBlack,
	Color = UI.Danger,
	Parent = jumpscareFrame,
})
jumpscareText.ZIndex = 100

local function playJumpscare()
	jumpscareFrame.Visible = true
	jumpscareFrame.BackgroundTransparency = 0
	-- camera shake
	intenseCameraShake(0.8)
	-- play sound
	playSound("Jumpscare", 1.2)
	task.wait(1.5)
	TweenService:Create(jumpscareFrame, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	task.wait(0.6)
	jumpscareFrame.Visible = false
end

---------------------------------------------------------------------
-- 9. LEADERBOARD PANEL
---------------------------------------------------------------------
local lbButton = newButton({
	Name = "LBToggle",
	Text = "🏆",
	Size = UDim2.new(0, 44, 0, 44),
	Position = UDim2.new(1, -55, 0, 10),
	Anchor = Vector2.new(0, 0),
	Color = UI.BgPrimary,
	Corner = 22,
	TextSize = 22,
	Parent = screenGui,
})
lbButton.ZIndex = 80
lbButton.BackgroundTransparency = 0.3

local lbFrame = newFrame({
	Name = "Leaderboard",
	Size = UDim2.new(0, 260, 0, 320),
	Position = UDim2.new(1, -15, 0, 60),
	Anchor = Vector2.new(1, 0),
	Color = UI.BgPrimary,
	Corner = 10,
	Visible = false,
	Parent = screenGui,
})
lbFrame.ZIndex = 80
lbFrame.BackgroundTransparency = 0.1

local lbTitle = newLabel({
	Text = "LEADERBOARD",
	Size = UDim2.new(1, 0, 0, 35),
	TextSize = 16,
	Font = Enum.Font.GothamBlack,
	Color = UI.Accent,
	Parent = lbFrame,
})
lbTitle.ZIndex = 81

local lbScroll = newScroll({
	Name = "LBList",
	Size = UDim2.new(0.92, 0, 1, -40),
	Position = UDim2.new(0.04, 0, 0, 38),
	Padding = 3,
	Parent = lbFrame,
})
lbScroll.ZIndex = 81

lbButton.MouseButton1Click:Connect(function()
	lbFrame.Visible = not lbFrame.Visible
end)

local function updateLeaderboardUI(data)
	if not data then return end
	for _, child in ipairs(lbScroll:GetChildren()) do
		if child:IsA("TextLabel") then child:Destroy() end
	end
	for idx, entry in ipairs(data) do
		local lbEntry = newLabel({
			Name = "LB_" .. idx,
			Text = "#" .. idx .. "  " .. entry.Name .. "  Lv." .. entry.Level .. "  🪙" .. entry.Coins,
			Size = UDim2.new(1, 0, 0, 22),
			TextSize = 12,
			Font = idx <= 3 and Enum.Font.GothamBold or Enum.Font.Gotham,
			Color = idx == 1 and Color3.fromRGB(255, 215, 0) or (idx == 2 and Color3.fromRGB(200, 200, 220) or (idx == 3 and Color3.fromRGB(205, 127, 50) or UI.TextPrimary)),
			XAlign = Enum.TextXAlignment.Left,
			Parent = lbScroll,
		})
		lbEntry.LayoutOrder = idx
		lbEntry.ZIndex = 82
	end
end

---------------------------------------------------------------------
-- 10. LOBBY OPEN BUTTON (shown when not in lobby/game)
---------------------------------------------------------------------
local openLobbyBtn = newButton({
	Name = "OpenLobby",
	Text = "LOBBY",
	Size = UDim2.new(0, 120, 0, 44),
	Position = UDim2.new(0.5, 0, 1, -20),
	Anchor = Vector2.new(0.5, 1),
	Corner = 10,
	Parent = screenGui,
})
openLobbyBtn.ZIndex = 70

openLobbyBtn.MouseButton1Click:Connect(function()
	Remotes.RequestLobbies:FireServer()
	lobbyFrame.Visible = not lobbyFrame.Visible
	waitingFrame.Visible = false
end)

---------------------------------------------------------------------
-- 11. SOUND MANAGER
---------------------------------------------------------------------
local sounds = {}

local function createSound(name, id, loop, volume)
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Looped = loop or false
	s.Volume = volume or 0.5
	s.Parent = SoundService
	sounds[name] = s
	return s
end

-- Create all sounds
createSound("Ambient",     Config.Sounds.Ambient,     true,  0.35)
createSound("LightOff",    Config.Sounds.LightOff,    false, 0.7)
createSound("LightOn",     Config.Sounds.LightOn,     false, 0.5)
createSound("Footstep",    Config.Sounds.Footstep,    true,  0.3)
createSound("Jumpscare",   Config.Sounds.Jumpscare,   false, 1.0)
createSound("EntityChase", Config.Sounds.EntityChase, true,  0.4)
createSound("Win",         Config.Sounds.Win,         false, 0.6)
createSound("Lose",        Config.Sounds.Lose,        false, 0.6)

function playSound(name, volume)
	local s = sounds[name]
	if s then
		if volume then s.Volume = volume end
		s:Play()
	end
end

local function stopSound(name)
	local s = sounds[name]
	if s then s:Stop() end
end

local function stopAllSounds()
	for _, s in pairs(sounds) do
		s:Stop()
	end
end

---------------------------------------------------------------------
-- 12. CAMERA EFFECTS
---------------------------------------------------------------------
local shaking = false
local shakeIntensity = 0

local function startCameraShake(intensity)
	shakeIntensity = intensity or 0.5
	shaking = true
end

local function stopCameraShake()
	shaking = false
	shakeIntensity = 0
end

function intenseCameraShake(duration)
	startCameraShake(2.0)
	task.delay(duration, function()
		stopCameraShake()
	end)
end

RunService.RenderStepped:Connect(function()
	if shaking and shakeIntensity > 0 then
		local offset = CFrame.new(
			(math.random() - 0.5) * shakeIntensity,
			(math.random() - 0.5) * shakeIntensity,
			0
		)
		camera.CFrame = camera.CFrame * offset
	end
end)

---------------------------------------------------------------------
-- DARK OVERLAY (when lights off)
---------------------------------------------------------------------
local darkOverlay = newFrame({
	Name = "DarkOverlay",
	Size = UDim2.new(1, 0, 1, 0),
	Color = Color3.fromRGB(0, 0, 0),
	Transparency = 1,
	Visible = true,
	Parent = screenGui,
})
darkOverlay.ZIndex = 40

---------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------
local currentState = "lobby"   -- "lobby" | "waiting" | "playing" | "spectating"
local currentLobby = 0
local myData = { Coins = 0, XP = 0, Level = 1 }

---------------------------------------------------------------------
-- REMOTE EVENT LISTENERS
---------------------------------------------------------------------

-- Lobby updates
Remotes.LobbyUpdate.OnClientEvent:Connect(function(snapshots)
	updateLobbyUI(snapshots)
end)

-- Countdown tick
Remotes.CountdownTick.OnClientEvent:Connect(function(lobbyIndex, sec)
	waitCountdown.Text = tostring(sec)
	if sec <= 5 then
		waitCountdown.TextColor3 = UI.Danger
	else
		waitCountdown.TextColor3 = UI.TextPrimary
	end
end)

-- Game start
Remotes.GameStart.OnClientEvent:Connect(function(lobbyIndex)
	currentState = "playing"
	currentLobby = lobbyIndex
	lobbyFrame.Visible = false
	waitingFrame.Visible = false
	gameHud.Visible = true
	openLobbyBtn.Visible = false
	resultFrame.Visible = false

	-- start ambient sound
	playSound("Ambient")
	showNotification("Game dimulai! Bertahan selama 2 menit!", 4)
end)

-- Game end
Remotes.GameEnd.OnClientEvent:Connect(function(lobbyIndex, won)
	currentState = "lobby"
	gameHud.Visible = false
	stopAllSounds()
	stopCameraShake()
	darkOverlay.BackgroundTransparency = 1
	warningLabel.Visible = false

	resultFrame.Visible = true
	if won then
		resultTitle.Text = "KAMU MENANG!"
		resultTitle.TextColor3 = UI.Success
		resultSub.Text = "+25 Coin, +50 XP | Kembali ke lobby..."
		playSound("Win")
	else
		resultTitle.Text = "KAMU KALAH!"
		resultTitle.TextColor3 = UI.Danger
		resultSub.Text = "Kembali ke lobby dalam 5 detik..."
		playSound("Lose")
	end

	task.delay(5, function()
		resultFrame.Visible = false
		openLobbyBtn.Visible = true
		lobbyFrame.Visible = true
		Remotes.RequestLobbies:FireServer()
	end)
end)

-- Light toggle
Remotes.LightToggle.OnClientEvent:Connect(function(lobbyIndex, lightsOn)
	if lightsOn then
		-- lights on
		TweenService:Create(darkOverlay, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		warningLabel.Visible = false
		stopCameraShake()
		stopSound("EntityChase")
		playSound("LightOn")
	else
		-- lights off
		TweenService:Create(darkOverlay, TweenInfo.new(0.3), { BackgroundTransparency = 0.6 }):Play()
		warningLabel.Visible = true
		startCameraShake(0.4)
		playSound("LightOff")
		playSound("EntityChase")
		-- flash warning
		task.spawn(function()
			while warningLabel.Visible do
				warningLabel.TextTransparency = 0
				task.wait(0.5)
				warningLabel.TextTransparency = 0.5
				task.wait(0.5)
			end
		end)
	end
end)

-- Entity alert
Remotes.EntityAlert.OnClientEvent:Connect(function(lobbyIndex)
	showNotification("⚠ Entitas muncul di kegelapan!", 3)
end)

-- Jumpscare
Remotes.JumpscareEvent.OnClientEvent:Connect(function(lobbyIndex)
	playJumpscare()
end)

-- Notification
Remotes.NotifyClient.OnClientEvent:Connect(function(text)
	showNotification(text, 3)
end)

-- Coin/XP update
Remotes.CoinXPUpdate.OnClientEvent:Connect(function(data)
	myData = data
	coinLabel.Text = "Coin: " .. tostring(data.Coins)
	xpLabel.Text = "Lv." .. tostring(data.Level) .. " | XP: " .. tostring(data.XP) .. "/" .. tostring(Config.XP_PER_LEVEL)
end)

-- Leaderboard data
Remotes.LeaderboardData.OnClientEvent:Connect(function(data)
	updateLeaderboardUI(data)
end)

-- Spectate start
Remotes.SpectateStart.OnClientEvent:Connect(function(lobbyIndex)
	currentState = "spectating"
	lobbyFrame.Visible = false
	waitingFrame.Visible = false
	openLobbyBtn.Visible = true
	showNotification("Kamu menonton Lobby " .. lobbyIndex, 3)
end)

---------------------------------------------------------------------
-- GAME TIMER (client-side display)
---------------------------------------------------------------------
local roundTimeLeft = Config.ROUND_DURATION

Remotes.GameStart.OnClientEvent:Connect(function()
	roundTimeLeft = Config.ROUND_DURATION
end)

RunService.Heartbeat:Connect(function(dt)
	if currentState == "playing" then
		roundTimeLeft = math.max(0, roundTimeLeft - dt)
		local mins = math.floor(roundTimeLeft / 60)
		local secs = math.floor(roundTimeLeft % 60)
		timerLabel.Text = string.format("%02d:%02d", mins, secs)
		if roundTimeLeft <= 30 then
			timerLabel.TextColor3 = UI.Danger
		else
			timerLabel.TextColor3 = UI.TextPrimary
		end
	end
end)

---------------------------------------------------------------------
-- MOBILE SUPPORT
---------------------------------------------------------------------
if UserInputService.TouchEnabled then
	-- bigger buttons for mobile
	openLobbyBtn.Size = UDim2.new(0, 150, 0, 56)
	lbButton.Size = UDim2.new(0, 52, 0, 52)
end

---------------------------------------------------------------------
-- REQUEST INITIAL DATA
---------------------------------------------------------------------
task.delay(3, function()
	Remotes.RequestLobbies:FireServer()
end)

print("[LMB Client] Lampu Mati Bergilir client loaded successfully!")
