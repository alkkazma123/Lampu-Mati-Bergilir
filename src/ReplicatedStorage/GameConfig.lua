--[[
	GameConfig  –  shared constants for Lampu Mati Bergilir
	Required by both server and client.
]]

local GameConfig = {}

------------------------------------------------------------------------
-- LOBBY
------------------------------------------------------------------------
GameConfig.MAX_LOBBIES        = 4
GameConfig.MIN_PLAYERS        = 1
GameConfig.MAX_PLAYERS        = 8
GameConfig.COUNTDOWN_SECONDS  = 15

------------------------------------------------------------------------
-- MAP  (procedural city)
------------------------------------------------------------------------
GameConfig.CITY_SIZE          = 200        -- studs, square
GameConfig.BUILDING_COUNT     = 18
GameConfig.STREETLIGHT_COUNT  = 24
GameConfig.SWITCH_COUNT       = 6          -- switches scattered

------------------------------------------------------------------------
-- GAME ROUND
------------------------------------------------------------------------
GameConfig.ROUND_DURATION     = 120        -- seconds to survive
GameConfig.LIGHT_CYCLE_MIN    = 8          -- min seconds light stays on
GameConfig.LIGHT_CYCLE_MAX    = 20
GameConfig.DARK_DURATION_MIN  = 6
GameConfig.DARK_DURATION_MAX  = 14
GameConfig.ENTITY_SPEED       = 28         -- studs/sec
GameConfig.ENTITY_SPAWN_DIST  = 60         -- min dist from nearest player

------------------------------------------------------------------------
-- ECONOMY
------------------------------------------------------------------------
GameConfig.COIN_SURVIVE       = 25
GameConfig.COIN_SWITCH        = 5
GameConfig.XP_SURVIVE         = 50
GameConfig.XP_SWITCH          = 10
GameConfig.XP_PER_LEVEL       = 100

------------------------------------------------------------------------
-- SOUNDS  (asset IDs – royalty-free placeholders)
------------------------------------------------------------------------
GameConfig.Sounds = {
	Ambient       = "rbxassetid://9112854440",   -- horror ambient loop
	LightOff      = "rbxassetid://4898676078",   -- electric buzz off
	LightOn       = "rbxassetid://4898676078",   -- click on
	Footstep      = "rbxassetid://9114256148",   -- footstep loop
	Jumpscare     = "rbxassetid://9114217032",   -- short scare sting
	EntityChase   = "rbxassetid://9112854440",   -- heartbeat / tension
	Win           = "rbxassetid://9114256148",   -- victory jingle
	Lose          = "rbxassetid://9114217032",   -- defeat sting
}

------------------------------------------------------------------------
-- UI COLOURS (dark theme)
------------------------------------------------------------------------
GameConfig.UI = {
	BgPrimary     = Color3.fromRGB(18, 18, 24),
	BgSecondary   = Color3.fromRGB(28, 28, 38),
	Accent        = Color3.fromRGB(120, 80, 255),
	AccentGlow    = Color3.fromRGB(160, 120, 255),
	TextPrimary   = Color3.fromRGB(230, 230, 240),
	TextSecondary = Color3.fromRGB(160, 160, 175),
	Danger        = Color3.fromRGB(255, 60, 60),
	Success       = Color3.fromRGB(60, 220, 120),
	CardBg        = Color3.fromRGB(32, 32, 44),
}

------------------------------------------------------------------------
-- REMOTE EVENT / FUNCTION NAMES
------------------------------------------------------------------------
GameConfig.Remotes = {
	-- Client → Server
	"RequestLobbies",
	"JoinLobby",
	"LeaveLobby",
	"StartLobby",
	"ActivateSwitch",
	"RequestSpectate",
	-- Server → Client
	"LobbyUpdate",
	"GameStart",
	"GameEnd",
	"LightToggle",
	"EntityAlert",
	"JumpscareEvent",
	"NotifyClient",
	"CoinXPUpdate",
	"LeaderboardData",
	"CountdownTick",
	"SpectateStart",
}

return GameConfig
