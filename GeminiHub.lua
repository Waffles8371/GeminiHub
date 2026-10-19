-- 💎 GEMINI HUB V14.5 - LIQUID GLASS 6 REDESIGN (XENO PORT) 💎
-- Xeno-compatible build: executor GUI parent (gethui/CoreGui), getgenv state, executor filesystem persistence,
-- and the original metatable hooks, combined with the Liquid Glass 3 UI redesign. 'LiquidGlass' tags are kept
-- on the shell/tab bar/notification cards, and the LiquidGlassHandler module (by @7eoeb / @UNIVERSECORNUCOPIA)
-- is embedded near the bottom of this file, ported for Xeno. The same goes for the Objectual UI Blur module
-- (by Tavikron), which blurs the card frames on every tab page.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local LocalPlayer = Players.LocalPlayer

-- 🛡️ Safe GUI Parent Finder
local function getSafeParent()
	if type(gethui) == "function" then
		local success, result = pcall(gethui)
		if success and result then return result end
	end
	local success, result = pcall(function() return CoreGui end)
	if success and result then return result end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local safeParent = getSafeParent()

-- 🧹 Cleanup previous GUI instances & connections
if safeParent:FindFirstChild("GeminiHub") then
	safeParent.GeminiHub:Destroy()
end

if getgenv().GeminiKeybindConn then
	getgenv().GeminiKeybindConn:Disconnect()
	getgenv().GeminiKeybindConn = nil
end

-- 🫧 Remove the previous run's Liquid Glass layer (overlays, render steps, tag listeners)
if getgenv().GeminiLiquidGlass then
	pcall(function()
		getgenv().GeminiLiquidGlass.Destroy()
	end)
	getgenv().GeminiLiquidGlass = nil
end

-- 🧊 Remove the previous run's UI Blur layer (meshes, render hooks, DepthOfField)
if getgenv().GeminiUIBlur then
	pcall(function()
		getgenv().GeminiUIBlur.Destroy()
	end)
	getgenv().GeminiUIBlur = nil
end

-- 🛑 Put the previous run's systems to sleep. Re-executing the hub destroys the old GUI, but the old
-- run's render loop and metatable hooks stay alive in the game. If its Speed Engine was ON, they would
-- keep forcing WalkSpeed even though the new window says OFF. Turning the old flags off makes them
-- pass-through only, and the speed the old run was forcing is put back first.
do
	local previousState = getgenv().GeminiHubState
	if previousState then
		pcall(function()
			if previousState.SpeedEngineToggled then
				local char = LocalPlayer.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if hum then hum.WalkSpeed = previousState.OriginalSpeed end
			end
		end)
		previousState.SpeedEngineToggled = false
		previousState.BreakVelocityToggled = false

		if previousState.ShiftLockToggled then
			previousState.ShiftLockToggled = false
			pcall(function()
				if previousState.ShiftLockConn then previousState.ShiftLockConn:Disconnect() end
				LocalPlayer.DevEnableMouseLock = (previousState.ShiftLockPrev == true)
			end)
		end
		getgenv().GeminiHubState = nil
	end
end

-- 📂 Waypoint Folder Setup
-- The waypoint objects themselves are client-side visuals. Rebuild this folder
-- from the saved waypoint data each time the hub is loaded so old visual copies
-- do not stack on top of the restored ones.
local oldWaypointFolder = Workspace:FindFirstChild("GeminiHub_Waypoints")
if oldWaypointFolder then
	oldWaypointFolder:Destroy()
end

local WaypointFolder = Instance.new("Folder")
WaypointFolder.Name = "GeminiHub_Waypoints"
WaypointFolder.Parent = Workspace

-- 🎨 Hub State Engine
local HubState = {
	-- ESP Settings
	NPCToggled = false,
	NPCFill = 0.5,
	NPCOutline = 0,
	PlayerToggled = false,
	PlayerFill = 0.5,
	PlayerOutline = 0,
	PlayerColor = Color3.fromRGB(66, 133, 244),
	
	-- Waypoint Settings
	-- Built-in Roblox waypoint texture, so this does not depend on an external image asset.
	WaypointColor = Color3.fromRGB(66, 133, 244), -- Blue waypoint pin! 💧
	WaypointAssetId = "rbxasset://textures/ui/waypoint.png",
	Waypoints = {},
	
	-- ⚡ Speed & Velocity Engine State
	SpeedEngineToggled = false,
	BreakVelocityToggled = false,   
	MatchBaseSpeedToggled = true,   
	AddedSpeed = 10,                
	SpeedCap = 25,                  
	OriginalSpeed = 16,             
	ViewBaselineSpeed = 16,         -- UI-only baseline for the Server View / velocity-cap readout
	ToggleKeybind = Enum.KeyCode.G,
	OpenMenuKeybind = Enum.KeyCode.K,
	IsRebinding = false,
	IsRebindingOpenMenu = false,
	LastToggleTick = 0,

	-- 💡 Others / Light Engine State
	LightToggled = false,
	LightRange = 16,
	LightBrightness = 2,
	LightColor = Color3.fromRGB(255, 255, 255),
	LightShadows = false,
	
	-- Others State
	DaytimeToggled = false,
	DaytimeValue = 12,
	FOVToggled = false,
	HoverToggled = false,
	PlayerWarnings = {},

	-- UI Controls
	UISoundsEnabled = true,
}

-- Lets the next execution of the hub find this run's state (see the 🛑 block near the top).
getgenv().GeminiHubState = HubState

-- 🫧 Liquid Glass hook: tags a GuiObject and, once the handler has loaded, builds its glass overlay.
-- Works before the handler exists too (the tag alone is picked up when the handler starts).
HubState.LiquidGlass = nil
function HubState.ApplyGlass(guiObject)
	pcall(function()
		if not CollectionService:HasTag(guiObject, "LiquidGlass") then
			CollectionService:AddTag(guiObject, "LiquidGlass")
		end
		if HubState.LiquidGlass then
			HubState.LiquidGlass.new(guiObject)
		end
	end)
end

-- 🧊 UI Blur hook: gives a GuiObject a BlurEffect child (that is how the module is told what to blur)
-- and, once the module has loaded, builds the blur right away. Works before the module exists too.
HubState.UIBlur = nil
function HubState.ApplyBlur(guiObject)
	pcall(function()
		local effect = guiObject:FindFirstChildWhichIsA("BlurEffect")
		if not effect then
			effect = Instance.new("BlurEffect")
			effect.Name = "UIBlur"
			effect.Parent = guiObject
		end
		if HubState.UIBlur then
			HubState.UIBlur.new(guiObject, {
				Fragmented = effect:GetAttribute("Fragmented"),
				Inverted = effect:GetAttribute("Inverted"),
				StrokeSize = effect:GetAttribute("StrokeSize"),
			})
		end
	end)
end

-- ==========================================
-- 💾 WAYPOINT PERSISTENCE
-- ==========================================
-- V12 only kept waypoints inside HubState.Waypoints, so they disappeared when
-- the script restarted. V13 stores a small JSON file per PlaceId using the
-- executor filesystem when available, with a same-session getgenv fallback.

local WaypointSaveFolder = "GeminiHub"
local WaypointSaveFile = WaypointSaveFolder .. "/Waypoints_" .. tostring(game.PlaceId) .. ".json"
local WaypointPersistenceMode = "Unavailable"

local function ensureWaypointSaveFolder()
	if type(makefolder) ~= "function" then
		return true
	end

	local ok = pcall(function()
		makefolder(WaypointSaveFolder)
	end)
	return ok
end

local function waypointFileExists(path)
	if type(isfile) == "function" then
		local ok, result = pcall(isfile, path)
		if ok then
			return result == true
		end
	end

	if type(readfile) == "function" then
		local ok, content = pcall(readfile, path)
		return ok and type(content) == "string" and #content > 0
	end

	return false
end

local function encodeColor3(color)
	return {
		R = color.R,
		G = color.G,
		B = color.B,
	}
end

local function decodeColor3(data, fallback)
	if type(data) ~= "table" then
		return fallback
	end

	local r = tonumber(data.R) or tonumber(data.r)
	local g = tonumber(data.G) or tonumber(data.g)
	local b = tonumber(data.B) or tonumber(data.b)
	if not r or not g or not b then
		return fallback
	end

	return Color3.new(
		math.clamp(r, 0, 1),
		math.clamp(g, 0, 1),
		math.clamp(b, 0, 1)
	)
end

local function serializeWaypointData()
	local payload = {
		Version = 1,
		WaypointColor = encodeColor3(HubState.WaypointColor),
		Waypoints = {},
	}

	for _, wp in ipairs(HubState.Waypoints) do
		if wp and typeof(wp.Position) == "Vector3" and type(wp.Name) == "string" then
			table.insert(payload.Waypoints, {
				Name = wp.Name,
				Position = {
					X = wp.Position.X,
					Y = wp.Position.Y,
					Z = wp.Position.Z,
				},
				Color = encodeColor3(wp.Color or HubState.WaypointColor),
			})
		end
	end

	return payload
end

local function deserializeWaypointData(payload)
	if type(payload) ~= "table" then
		return false
	end

	local restored = {}
	if type(payload.Waypoints) == "table" then
		for _, data in ipairs(payload.Waypoints) do
			if type(data) == "table" and type(data.Name) == "string" and type(data.Position) == "table" then
				local x = tonumber(data.Position.X or data.Position.x)
				local y = tonumber(data.Position.Y or data.Position.y)
				local z = tonumber(data.Position.Z or data.Position.z)
				if x and y and z then
					table.insert(restored, {
						Name = data.Name,
						Position = Vector3.new(x, y, z),
						Color = decodeColor3(data.Color, HubState.WaypointColor),
					})
				end
			end
		end
	end

	HubState.Waypoints = restored
	HubState.WaypointColor = decodeColor3(payload.WaypointColor, HubState.WaypointColor)
	return true
end

local function saveWaypoints()
	local payload = serializeWaypointData()
	local cacheUpdated = pcall(function()
		getgenv().GeminiHubWaypointCache = payload
	end)

	local canUseFilesystem = type(writefile) == "function" and type(readfile) == "function"
	if canUseFilesystem then
		ensureWaypointSaveFolder()
		local encodedOk, encoded = pcall(function()
			return HttpService:JSONEncode(payload)
		end)

		if encodedOk and type(encoded) == "string" then
			local writeOk = pcall(function()
				writefile(WaypointSaveFile, encoded)
			end)
			if writeOk then
				WaypointPersistenceMode = "Filesystem"
				return true
			end
		end
	end

	WaypointPersistenceMode = cacheUpdated and "Session Cache" or "Unavailable"
	return cacheUpdated
end

local function loadWaypoints()
	local canUseFilesystem = type(readfile) == "function"
	if canUseFilesystem and waypointFileExists(WaypointSaveFile) then
		local readOk, raw = pcall(function()
			return readfile(WaypointSaveFile)
		end)
		if readOk and type(raw) == "string" and #raw > 0 then
			local decodeOk, payload = pcall(function()
				return HttpService:JSONDecode(raw)
			end)
			if decodeOk and deserializeWaypointData(payload) then
				WaypointPersistenceMode = "Filesystem"
				return true
			end
		end
	end

	local cacheOk, cachedPayload = pcall(function()
		return getgenv().GeminiHubWaypointCache
	end)
	if cacheOk and cachedPayload and deserializeWaypointData(cachedPayload) then
		WaypointPersistenceMode = "Session Cache"
		return true
	end

	WaypointPersistenceMode = canUseFilesystem and "Filesystem Ready" or "Unavailable"
	return false
end

-- ==========================================
-- ⚠️ PLAYER WARNING PERSISTENCE
-- ==========================================
-- Like waypoints, warnings are stored locally through the executor filesystem
-- when available, with a same-session getgenv fallback.
local WarningSaveFolder = "GeminiHub"
local WarningSaveFile = WarningSaveFolder .. "/PlayerWarnings.json"
local WarningPersistenceMode = "Unavailable"

local function serializeWarnings()
	local payload = { Version = 1, Players = {} }
	for _, name in ipairs(HubState.PlayerWarnings) do
		if type(name) == "string" and name ~= "" then
			table.insert(payload.Players, name)
		end
	end
	return payload
end

local function deserializeWarnings(payload)
	if type(payload) ~= "table" or type(payload.Players) ~= "table" then
		return false
	end
	local restored, seen = {}, {}
	for _, name in ipairs(payload.Players) do
		if type(name) == "string" and name ~= "" and not seen[string.lower(name)] then
			seen[string.lower(name)] = true
			table.insert(restored, name)
		end
	end
	HubState.PlayerWarnings = restored
	return true
end

local function savePlayerWarnings()
	local payload = serializeWarnings()
	local cacheUpdated = pcall(function()
		getgenv().GeminiHubPlayerWarningCache = payload
	end)

	if type(writefile) == "function" and type(readfile) == "function" then
		ensureWaypointSaveFolder()
		local encodedOk, encoded = pcall(function()
			return HttpService:JSONEncode(payload)
		end)
		if encodedOk and type(encoded) == "string" then
			local writeOk = pcall(function()
				writefile(WarningSaveFile, encoded)
			end)
			if writeOk then
				WarningPersistenceMode = "Filesystem"
				return true
			end
		end
	end

	WarningPersistenceMode = cacheUpdated and "Session Cache" or "Unavailable"
	return cacheUpdated
end

local function loadPlayerWarnings()
	if type(readfile) == "function" and waypointFileExists(WarningSaveFile) then
		local readOk, raw = pcall(function()
			return readfile(WarningSaveFile)
		end)
		if readOk and type(raw) == "string" and #raw > 0 then
			local decodeOk, payload = pcall(function()
				return HttpService:JSONDecode(raw)
			end)
			if decodeOk and deserializeWarnings(payload) then
				WarningPersistenceMode = "Filesystem"
				return true
			end
		end
	end

	local cacheOk, cachedPayload = pcall(function()
		return getgenv().GeminiHubPlayerWarningCache
	end)
	if cacheOk and cachedPayload and deserializeWarnings(cachedPayload) then
		WarningPersistenceMode = "Session Cache"
		return true
	end

	WarningPersistenceMode = type(readfile) == "function" and "Filesystem Ready" or "Unavailable"
	return false
end

loadPlayerWarnings()

-- 🧊 Main Window Frame / Liquid Glass UI
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "GeminiHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local pCallScreenInsets = pcall(function()
	ScreenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
end)
ScreenGui.Parent = safeParent

-- ==========================================
-- 💎 GEMINI HUB 14.0 - LIQUID GLASS THEME
-- ==========================================

local Theme = {
	-- ==========================================
	-- 🎛️ LIQUID GLASS 6 KNOBS (the easy-to-edit values)
	-- ==========================================
	-- Transparency: higher = clearer. The reference screenshot is about 0.94 for the window.
	PanelTransparency = 0.90,         -- window fill
	SurfaceTransparency = 0.84,       -- card fill (a hair darker than the window)
	StrokeTransparency = 0.88,        -- soft outline on cards and the tab bar
	NotificationTransparency = 0.55,  -- notification bubbles need more body to stay readable

	-- Shapes (pixels). Controls are true capsules (radius = half their height).
	RadiusWindow = 32,                -- main window
	RadiusPanel = 22,                 -- large panels = window radius minus the 10px page padding
	RadiusCard = 18,                  -- multi-line frames that would clip text as capsules

	-- Floating minimize circle
	OrbSize = 58,                     -- same height as the minimized pill
	OrbGap = 12,                      -- distance from the window

	-- ==========================================
	-- 🎨 Colors: neutral smoke instead of blue graphite
	-- ==========================================
	Panel = Color3.fromRGB(22, 24, 28),
	PanelBottom = Color3.fromRGB(20, 22, 26),

	-- Cards: a hair darker than the window, so they read as inset wells.
	Surface = Color3.fromRGB(14, 16, 19),
	SurfaceHover = Color3.fromRGB(92, 98, 108),
	SurfacePressed = Color3.fromRGB(62, 68, 78),

	-- iOS-inspired accents: blue for navigation/sliders, green for enabled switches.
	Accent = Color3.fromRGB(10, 132, 255),
	AccentSoft = Color3.fromRGB(104, 184, 255),
	ToggleOn = Color3.fromRGB(48, 209, 88),
	Danger = Color3.fromRGB(255, 105, 97),

	-- Pure white primary text, a touch softer for secondary text.
	Text = Color3.fromRGB(255, 255, 255),
	TextSecondary = Color3.fromRGB(226, 231, 239),

	-- Utility
	White = Color3.fromRGB(248, 250, 255),
	Track = Color3.fromRGB(120, 127, 138),
}

-- Derived values: hover and press are always relative to the base fills above.
Theme.SurfaceHoverTransparency = math.max(0, Theme.SurfaceTransparency - 0.08)
Theme.SurfacePressedTransparency = math.max(0, Theme.SurfaceTransparency - 0.16)
Theme.OrbTransparency = Theme.PanelTransparency
Theme.OrbHoverTransparency = math.max(0, Theme.PanelTransparency - 0.08)
Theme.OrbPressedTransparency = math.max(0, Theme.PanelTransparency - 0.18)

-- User-exported Figma switch tracks. I/O indicators are already part of these images.
local ON_SWITCH_IMAGE = "rbxassetid://73774684489893"
local OFF_SWITCH_IMAGE = "rbxassetid://84077478919224"
local SLIDER_KNOB_IMAGE = "rbxassetid://97296360165887"

-- Built-in Roblox font family; no externally downloaded font is required.
local ROBOTO_REGULAR = Font.new("rbxasset://fonts/families/Roboto.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local ROBOTO_MEDIUM = Font.new("rbxasset://fonts/families/Roboto.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal)
local ROBOTO_BOLD = Font.new("rbxasset://fonts/families/Roboto.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)

local TweenFast = TweenInfo.new(
	0.16,
	Enum.EasingStyle.Quint,
	Enum.EasingDirection.Out
)

local TweenSoft = TweenInfo.new(
	0.25,
	Enum.EasingStyle.Quint,
	Enum.EasingDirection.Out
)

-- ==========================================
-- 🔊 UI SOUND SYSTEM
-- ==========================================
-- Short 2D UI sounds are parented to SoundService so they are not positional.
local oldAudio = SoundService:FindFirstChild("GeminiHub_UIAudio")
if oldAudio then oldAudio:Destroy() end
local GeminiHubAudio = Instance.new("Folder")
GeminiHubAudio.Name = "GeminiHub_UIAudio"
GeminiHubAudio.Parent = SoundService

local function makeUISound(name, assetId, volume)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. tostring(assetId)
	sound.Volume = volume
	sound.Parent = GeminiHubAudio
	return sound
end

-- Suggested defaults for short UI feedback. IDs/volumes are centralized so
-- they can be swapped later without touching the button logic.
local ButtonSFX = makeUISound("Button", 10066931761, 0.12)
local ToggleSFX = makeUISound("Toggle", 1006693176, 0.16)

local NotificationSFX1 = makeUISound("Notification_1", 115916891254154, 0.5)
local NotificationSFX2 = makeUISound("Notification_2", 15675085146, 0.2)

local ResetSFX1 = makeUISound("Reset_1", 12222140, 0.5)
local ResetSFX2 = makeUISound("Reset_2", 12222005, 0.5)

local function playUISound(sound)
	if not HubState.UISoundsEnabled then return end
	if not sound then return end
	pcall(function()
		sound.TimePosition = 0
		sound:Play()
	end)
end

local function playUISoundPair(a, b)
	playUISound(a)
	playUISound(b)
end

-- Subtle visual "haptic" feedback for touch/click interactions.
local function hapticPulse(guiObject, scaleObject, strength)
	if not guiObject or not guiObject.Parent then return end
	strength = strength or 1.0
	local targetScale = 1 + (0.075 * strength)
	if scaleObject then
		-- A clearer springy pop, with a tiny tilt on the switch thumb.
		local startRotation = guiObject.Rotation
		TweenService:Create(scaleObject, TweenInfo.new(0.075, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = targetScale}):Play()
		TweenService:Create(guiObject, TweenInfo.new(0.075, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = startRotation + (guiObject.Name == "Knob" and 5 * strength or 0)}):Play()
		task.delay(0.075, function()
			if scaleObject and scaleObject.Parent then
				TweenService:Create(scaleObject, TweenInfo.new(0.16, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {Scale = 1}):Play()
			end
			if guiObject and guiObject.Parent then
				TweenService:Create(guiObject, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Rotation = startRotation}):Play()
			end
		end)
	else
		local original = guiObject.BackgroundTransparency
		TweenService:Create(guiObject, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = math.max(0, original - 0.08)}):Play()
		task.delay(0.07, function()
			if guiObject and guiObject.Parent then
				TweenService:Create(guiObject, TweenInfo.new(0.13, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundTransparency = original}):Play()
			end
		end)
	end
end


-- ==========================================
-- 🪟 MAIN GLASS CARD
-- ==========================================

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.BackgroundColor3 = Theme.Panel
MainFrame.BackgroundTransparency = Theme.PanelTransparency
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

-- 📱 Responsive shell: desktop keeps the original compact size, while touch
-- devices use a percentage-based footprint so the hub does not swallow the screen.
local isTouchDevice = UserInputService.TouchEnabled
local function updateResponsiveShell()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)

	if isTouchDevice then
		local width = math.clamp(viewport.X * 0.90, 300, 360)
		local height = math.clamp(viewport.Y * 0.80, 430, 585)
		MainFrame.Size = UDim2.fromOffset(width, height)
	else
		MainFrame.Size = UDim2.fromOffset(360, 585)
	end

	MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
end

updateResponsiveShell()

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, Theme.RadiusWindow)
MainCorner.Parent = MainFrame

local HubGradient = Instance.new("UIGradient")
HubGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Theme.Panel),
	ColorSequenceKeypoint.new(0.55, Theme.Panel),
	ColorSequenceKeypoint.new(1, Theme.PanelBottom),
})
HubGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(1, 0.04),
})
HubGradient.Rotation = 90
HubGradient.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Theme.White
MainStroke.Transparency = 0.55
MainStroke.Thickness = 1
MainStroke.Parent = MainFrame

-- ✨ Gradient glass highlight on the border itself. Roblox supports UIGradient
-- as a child of UIStroke, so the highlight follows the rounded border instead
-- of tinting the whole panel.
local MainStrokeGradient = Instance.new("UIGradient")
MainStrokeGradient.Name = "GlassHighlightGradient"
MainStrokeGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(205, 212, 224)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
})
MainStrokeGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.15),
	NumberSequenceKeypoint.new(0.5, 0.85),
	NumberSequenceKeypoint.new(1, 0.15),
})
MainStrokeGradient.Rotation = 48
MainStrokeGradient.Parent = MainStroke

-- Real UI shadow. Some third-party Roblox environments may not expose
-- UIShadow yet, so this is deliberately guarded instead of hard-failing.
local shadowOk, MainShadow = pcall(function()
	return Instance.new("UIShadow")
end)

if shadowOk and MainShadow then
	local configured = pcall(function()
		MainShadow.Color = Color3.fromRGB(0, 0, 0)
		MainShadow.Transparency = 0.80
		MainShadow.BlurRadius = UDim.new(0, 18)
		MainShadow.Offset = UDim2.new(0, 0, 0, 7)
		MainShadow.Spread = UDim2.new(0, 3)
		MainShadow.Parent = MainFrame
	end)

	if not configured then
		MainShadow:Destroy()
		MainShadow = nil
	end
else
	MainShadow = nil
	warn("Gemini Hub: UIShadow is unavailable in this Roblox environment; continuing without the UI shadow.")
end

-- Very subtle top-edge shine to sell the glass material.
local TopShine = Instance.new("Frame")
TopShine.Name = "TopShine"
TopShine.Size = UDim2.new(1, -38, 0, 1)
TopShine.Position = UDim2.new(0, 19, 0, 2)
TopShine.BackgroundColor3 = Theme.White
TopShine.BackgroundTransparency = 0.80
TopShine.BorderSizePixel = 0
TopShine.ZIndex = 2
TopShine.Parent = MainFrame

local TopShineCorner = Instance.new("UICorner")
TopShineCorner.CornerRadius = UDim.new(1, 0)
TopShineCorner.Parent = TopShine

-- ==========================================
-- 🫧 CLIENT VISUAL BLUR
-- ==========================================
-- Roblox's BlurEffect affects the 3D world view, not just one GUI card.
-- It remains client-side when parented to the local player's CurrentCamera.

local existingCamera = Workspace.CurrentCamera
if existingCamera then
    local oldBlur = existingCamera:FindFirstChild("GeminiHub_ClientBlur")
    if oldBlur then
        oldBlur:Destroy()
    end
end

local blurOk, CameraBlur = pcall(function()
	return Instance.new("BlurEffect")
end)

local blurActive = false

local function attachCameraBlur()
	if not blurOk or not CameraBlur then
		return
	end

	local camera = Workspace.CurrentCamera
	if camera then
		CameraBlur.Parent = camera
		CameraBlur.Size = blurActive and 3 or 0
	end
end

if blurOk and CameraBlur then
	CameraBlur.Name = "GeminiHub_ClientBlur"
	CameraBlur.Size = 0
	CameraBlur.Enabled = true
	attachCameraBlur()

	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		task.defer(attachCameraBlur)
	end)
else
	CameraBlur = nil
	warn("Gemini Hub: BlurEffect is unavailable in this Roblox environment; continuing without camera blur.")
end

local function setMenuBlur(enabled)
	-- Reserved for a future true backdrop-blur implementation. Roblox
	-- BlurEffect blurs the 3D camera, not the pixels behind a GuiObject.
	blurActive = false
	attachCameraBlur()
end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	task.defer(function()
		updateResponsiveShell()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveShell)
		end
	end)
end)

local initialCamera = Workspace.CurrentCamera
if initialCamera then
	initialCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveShell)
end

-- ==========================================
-- 🖱️ TOP HEADER & DRAGGING
-- ==========================================

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 58)
TopBar.BackgroundTransparency = 1
TopBar.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -80, 0, 22)
Title.Position = UDim2.new(0, 18, 0, 10)
Title.BackgroundTransparency = 1
Title.Text = "💎  GEMINI HUB"
Title.TextColor3 = Theme.Text
Title.FontFace = ROBOTO_BOLD
Title.TextSize = 15
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TopBar

local Version = Instance.new("TextLabel")
Version.Size = UDim2.new(1, -80, 0, 16)
Version.Position = UDim2.new(0, 20, 0, 31)
Version.BackgroundTransparency = 1
Version.Text = "v14.5 XENO"
Version.TextColor3 = Theme.TextSecondary
Version.FontFace = ROBOTO_REGULAR
Version.TextSize = 10
Version.TextXAlignment = Enum.TextXAlignment.Left
Version.Parent = TopBar

local MinMaxBtn = Instance.new("TextButton")
MinMaxBtn.Name = "MinimizeOrb"
MinMaxBtn.AnchorPoint = Vector2.new(0.5, 0.5)
MinMaxBtn.Size = UDim2.fromOffset(Theme.OrbSize, Theme.OrbSize)
MinMaxBtn.Position = UDim2.new(0.5, 0, 0.5, 0) -- placed next to the window every frame (see below)
MinMaxBtn.BackgroundColor3 = Theme.Panel
MinMaxBtn.BackgroundTransparency = Theme.OrbTransparency
MinMaxBtn.BorderSizePixel = 0
MinMaxBtn.Text = "−"
MinMaxBtn.TextColor3 = Theme.Text
MinMaxBtn.FontFace = ROBOTO_MEDIUM
MinMaxBtn.TextSize = 32
MinMaxBtn.AutoButtonColor = false
MinMaxBtn.ZIndex = 10
-- Detached from the window: a child of the ScreenGui, not of the clipped MainFrame.
MinMaxBtn.Parent = ScreenGui

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(1, 0)
MinCorner.Parent = MinMaxBtn

local MinStroke = Instance.new("UIStroke")
MinStroke.Color = Theme.White
MinStroke.Transparency = 0.55
MinStroke.Thickness = 1
MinStroke.Parent = MinMaxBtn

-- Same soft specular rim as the window: bright top-left / bottom-right, almost nothing between.
local MinStrokeGradient = Instance.new("UIGradient")
MinStrokeGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(205, 212, 224)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
})
MinStrokeGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.15),
	NumberSequenceKeypoint.new(0.5, 0.85),
	NumberSequenceKeypoint.new(1, 0.15),
})
MinStrokeGradient.Rotation = 48
MinStrokeGradient.Parent = MinStroke

local minimized = false

local MinMaxScale = Instance.new("UIScale")
MinMaxScale.Scale = 1
MinMaxScale.Parent = MinMaxBtn

local function pressMinMaxButton()
	TweenService:Create(MinMaxScale, TweenFast, {Scale = 1.035}):Play()
	TweenService:Create(MinMaxBtn, TweenFast, {
		BackgroundTransparency = Theme.OrbPressedTransparency,
		BackgroundColor3 = Theme.SurfaceHover,
		TextColor3 = Theme.Text,
	}):Play()
end

local function releaseMinMaxButton()
	TweenService:Create(MinMaxScale, TweenFast, {Scale = 1}):Play()
	TweenService:Create(MinMaxBtn, TweenFast, {
		BackgroundTransparency = Theme.OrbTransparency,
		BackgroundColor3 = Theme.Panel,
		TextColor3 = Theme.Text,
	}):Play()
end

MinMaxBtn.MouseButton1Down:Connect(pressMinMaxButton)
MinMaxBtn.MouseButton1Up:Connect(releaseMinMaxButton)
MinMaxBtn.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch then pressMinMaxButton() end
end)
MinMaxBtn.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch then releaseMinMaxButton() end
end)

MinMaxBtn.MouseButton1Click:Connect(function()
	playUISound(ButtonSFX)
	local currentSize = MainFrame.AbsoluteSize
	local currentPos = MainFrame.Position
	minimized = not minimized
	MinMaxBtn.Text = minimized and "+" or "−"

	local targetSize
	if minimized then
		targetSize = UDim2.fromOffset(currentSize.X, 58)
	else
		local camera = Workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
		if isTouchDevice then
			targetSize = UDim2.fromOffset(
				math.clamp(viewport.X * 0.90, 300, 360),
				math.clamp(viewport.Y * 0.80, 430, 585)
			)
		else
			targetSize = UDim2.fromOffset(360, 585)
		end
	end

	-- MainFrame is center-anchored. Move its center by half the height
	-- difference so the TOP EDGE stays in the same place while collapsing.
	-- This keeps the pill attached to the header instead of teleporting to
	-- the middle of the old panel.
	local targetHeight = targetSize.Y.Offset
	local heightDelta = targetHeight - currentSize.Y
	local targetPosition = UDim2.new(
		currentPos.X.Scale,
		currentPos.X.Offset,
		currentPos.Y.Scale,
		currentPos.Y.Offset + (heightDelta / 2)
	)

	MainFrame:TweenSizeAndPosition(targetSize, targetPosition, "Out", "Quint", 0.3, true)

	setMenuBlur(not minimized)
end)

MinMaxBtn.MouseEnter:Connect(function()
	TweenService:Create(
		MinMaxBtn,
		TweenFast,
		{
			BackgroundTransparency = Theme.OrbHoverTransparency,
			TextColor3 = Theme.Text,
		}
	):Play()
end)

MinMaxBtn.MouseLeave:Connect(function()
	TweenService:Create(
		MinMaxBtn,
		TweenFast,
		{
			BackgroundTransparency = Theme.OrbTransparency,
			TextColor3 = Theme.Text,
		}
	):Play()
end)

-- ⭕ Floating minimize circle: sits next to the window like the search circle in the reference.
-- It is the same height as the minimized pill, stays glued to the window while it moves, resizes or is
-- dragged, and flips to the left side (or back inside the header) when the screen has no room on the right.
local function updateOrbLayout()
	if not MinMaxBtn.Parent then return end

	local half = Theme.OrbSize / 2
	local framePos = MainFrame.Position -- center-anchored, same coordinate space as the circle
	local frameSize = MainFrame.AbsoluteSize
	local frameAbsX = MainFrame.AbsolutePosition.X
	local screenWidth = ScreenGui.AbsoluteSize.X

	local offsetX
	if frameAbsX + frameSize.X + Theme.OrbGap + Theme.OrbSize <= screenWidth then
		offsetX = frameSize.X / 2 + Theme.OrbGap + half -- right of the window
	elseif frameAbsX - Theme.OrbGap - Theme.OrbSize >= 0 then
		offsetX = -(frameSize.X / 2 + Theme.OrbGap + half) -- no room on the right: left of the window
	else
		offsetX = frameSize.X / 2 - 8 - half -- no room at all: back inside the header
	end
	local offsetY = -frameSize.Y / 2 + 29 -- vertically centered on the 58px header / minimized pill

	MinMaxBtn.Position = UDim2.new(
		framePos.X.Scale, framePos.X.Offset + offsetX,
		framePos.Y.Scale, framePos.Y.Offset + offsetY
	)
	MinMaxBtn.Visible = MainFrame.Visible
end

local orbLayoutConnection
orbLayoutConnection = RunService.RenderStepped:Connect(function()
	if not MinMaxBtn.Parent then
		orbLayoutConnection:Disconnect() -- the hub was re-executed and this window is gone
		return
	end
	updateOrbLayout()
end)
updateOrbLayout()

-- 🖐️ Desktop + mobile dragging. TouchPan is specifically supported by GuiObject
-- and avoids relying on mouse-only events on phones/tablets.
local dragging = false
local dragStart
local startPos

local function beginDrag(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = MainFrame.Position
	end
end

local function endDrag(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end

TopBar.InputBegan:Connect(beginDrag)
TopBar.InputEnded:Connect(endDrag)

TopBar.TouchPan:Connect(function(_touchPositions, totalTranslation, _velocity, state)
	if state == Enum.UserInputState.Begin then
		dragging = true
		startPos = MainFrame.Position
	elseif state == Enum.UserInputState.Change and dragging then
		MainFrame.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + totalTranslation.X,
			startPos.Y.Scale,
			startPos.Y.Offset + totalTranslation.Y
		)
	elseif state == Enum.UserInputState.End then
		dragging = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = input.Position - dragStart
		MainFrame.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + delta.X,
			startPos.Y.Scale,
			startPos.Y.Offset + delta.Y
		)
	end
end)

-- ==========================================
-- 🔔 REUSABLE LIQUID GLASS NOTIFICATION SYSTEM
-- ==========================================
local NotificationContainer = Instance.new("Frame")
NotificationContainer.Name = "NotificationContainer"
NotificationContainer.AnchorPoint = Vector2.new(0.5, 0)
NotificationContainer.Size = UDim2.new(0, 300, 0, 0)
NotificationContainer.AutomaticSize = Enum.AutomaticSize.Y
NotificationContainer.BackgroundTransparency = 1
NotificationContainer.BorderSizePixel = 0
NotificationContainer.ZIndex = 50
NotificationContainer.Parent = ScreenGui

local NotificationLayout = Instance.new("UIListLayout")
NotificationLayout.FillDirection = Enum.FillDirection.Vertical
NotificationLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
NotificationLayout.SortOrder = Enum.SortOrder.LayoutOrder
NotificationLayout.Padding = UDim.new(0, 7)
NotificationLayout.Parent = NotificationContainer

local NOTIFICATION_GAP = 36
local function updateNotificationPosition()
	local pos = MainFrame.AbsolutePosition
	local size = MainFrame.AbsoluteSize
	NotificationContainer.Position = UDim2.fromOffset(pos.X + (size.X / 2), pos.Y + size.Y + NOTIFICATION_GAP)
end

MainFrame:GetPropertyChangedSignal("Position"):Connect(updateNotificationPosition)
MainFrame:GetPropertyChangedSignal("Size"):Connect(updateNotificationPosition)
MainFrame:GetPropertyChangedSignal("AbsolutePosition"):Connect(updateNotificationPosition)
MainFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateNotificationPosition)
updateNotificationPosition()

local function showNotification(titleText, messageText, duration)
	playUISoundPair(NotificationSFX1, NotificationSFX2)
	duration = duration or 3.5

	local card = Instance.new("Frame")
	card.Name = "Notification"
	card.Size = UDim2.new(1, 0, 0, 58)
	card.BackgroundColor3 = Color3.fromRGB(24, 26, 30)
	card.BackgroundTransparency = Theme.NotificationTransparency
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.ZIndex = 51
	card.Parent = NotificationContainer
	-- Each notification bubble is a distinct transient panel, so apply LiquidGlass
	-- to the card itself rather than the transparent stack container.
	HubState.ApplyGlass(card)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.RadiusPanel)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.White
	stroke.Transparency = 0.78
	stroke.Thickness = 1
	stroke.Parent = card

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 43, 48)),
		ColorSequenceKeypoint.new(0.62, Color3.fromRGB(28, 30, 35)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 22, 26)),
	})
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.65, 0.10),
		NumberSequenceKeypoint.new(1, 0.32),
	})
	gradient.Rotation = 90
	gradient.Parent = card

	local accent = Instance.new("Frame")
	accent.Size = UDim2.new(0, 4, 1, -28)
	accent.Position = UDim2.new(0, 10, 0, 14)
	accent.BackgroundColor3 = Theme.ToggleOn
	accent.BorderSizePixel = 0
	accent.ZIndex = 52
	accent.Parent = card
	Instance.new("UICorner", accent).CornerRadius = UDim.new(1, 0)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -28, 0, 19)
	title.Position = UDim2.new(0, 19, 0, 7)
	title.BackgroundTransparency = 1
	title.Text = titleText
	title.TextColor3 = Theme.Text
	title.FontFace = ROBOTO_BOLD
	title.TextSize = 11
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 52
	title.Parent = card

	local message = Instance.new("TextLabel")
	message.Size = UDim2.new(1, -28, 0, 23)
	message.Position = UDim2.new(0, 19, 0, 27)
	message.BackgroundTransparency = 1
	message.Text = messageText
	message.TextColor3 = Theme.Text
	message.FontFace = ROBOTO_MEDIUM
	message.TextSize = 9.5
	message.TextXAlignment = Enum.TextXAlignment.Left
	message.TextTruncate = Enum.TextTruncate.AtEnd
	message.ZIndex = 52
	message.Parent = card

	card.BackgroundTransparency = 1
	stroke.Transparency = 1
	accent.BackgroundTransparency = 1
	title.TextTransparency = 1
	message.TextTransparency = 1

	TweenService:Create(card, TweenSoft, {BackgroundTransparency = Theme.NotificationTransparency}):Play()
	TweenService:Create(stroke, TweenSoft, {Transparency = 0.78}):Play()
	TweenService:Create(accent, TweenSoft, {BackgroundTransparency = 0}):Play()
	TweenService:Create(title, TweenSoft, {TextTransparency = 0}):Play()
	TweenService:Create(message, TweenSoft, {TextTransparency = 0}):Play()

	task.delay(duration, function()
		if not card.Parent then return end
		TweenService:Create(card, TweenSoft, {BackgroundTransparency = 1}):Play()
		TweenService:Create(stroke, TweenSoft, {Transparency = 1}):Play()
		TweenService:Create(accent, TweenSoft, {BackgroundTransparency = 1}):Play()
		TweenService:Create(title, TweenSoft, {TextTransparency = 1}):Play()
		TweenService:Create(message, TweenSoft, {TextTransparency = 1}):Play()
		task.wait(TweenSoft.Time)
		if card then card:Destroy() end
	end)
end

getgenv().GeminiHubNotify = showNotification

-- ==========================================
-- 🏷️ LIQUID GLASS TAB STRIP
-- ==========================================

local TabBar = Instance.new("Frame")
TabBar.Name = "TabBar"
TabBar.Size = UDim2.new(1, -20, 0, 40)
TabBar.Position = UDim2.new(0, 10, 0, 64)
TabBar.BackgroundColor3 = Theme.Surface
TabBar.BackgroundTransparency = Theme.SurfaceTransparency
TabBar.BorderSizePixel = 0
TabBar.ZIndex = 5
TabBar.Parent = MainFrame

local TabCorner = Instance.new("UICorner")
TabCorner.CornerRadius = UDim.new(0.5, 0)
TabCorner.Parent = TabBar

local TabStroke = Instance.new("UIStroke")
TabStroke.Color = Theme.White
TabStroke.Transparency = Theme.StrokeTransparency
TabStroke.Thickness = 1
TabStroke.Parent = TabBar

local TabPadding = Instance.new("UIPadding")
TabPadding.PaddingLeft = UDim.new(0, 5)
TabPadding.PaddingRight = UDim.new(0, 5)
TabPadding.PaddingTop = UDim.new(0, 4)
TabPadding.PaddingBottom = UDim.new(0, 4)
TabPadding.Parent = TabBar

local TabListLayout = Instance.new("UIListLayout")
TabListLayout.FillDirection = Enum.FillDirection.Horizontal
TabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
TabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
TabListLayout.Padding = UDim.new(0, 4)
TabListLayout.Parent = TabBar

local Containers = {}
local ActiveTabName = "ESP"

-- Moving liquid-glass pill. It lives on a separate layer so the TabBar's
-- UIListLayout never tries to lay the indicator out as another tab.
local TabIndicatorLayer = Instance.new("Frame")
TabIndicatorLayer.Name = "TabIndicatorLayer"
TabIndicatorLayer.Size = UDim2.new(1, 0, 1, 0)
TabIndicatorLayer.Position = UDim2.new(0, 0, 0, 0)
TabIndicatorLayer.BackgroundTransparency = 1
TabIndicatorLayer.BorderSizePixel = 0
TabIndicatorLayer.ZIndex = 6
TabIndicatorLayer.Parent = MainFrame

local TabIndicator = Instance.new("Frame")
TabIndicator.Name = "ActiveTabPill"
TabIndicator.Size = UDim2.fromOffset(0, 0)
TabIndicator.Position = UDim2.fromOffset(0, 0)
TabIndicator.BackgroundColor3 = Theme.Accent
TabIndicator.BackgroundTransparency = 0.56
TabIndicator.BorderSizePixel = 0
TabIndicator.ZIndex = 6
TabIndicator.Parent = TabIndicatorLayer

local TabIndicatorCorner = Instance.new("UICorner")
TabIndicatorCorner.CornerRadius = UDim.new(0.5, 0)
TabIndicatorCorner.Parent = TabIndicator

local TabIndicatorStroke = Instance.new("UIStroke")
TabIndicatorStroke.Color = Theme.AccentSoft
TabIndicatorStroke.Transparency = 0.48
TabIndicatorStroke.Thickness = 1
TabIndicatorStroke.Parent = TabIndicator

local TabIndicatorScale = Instance.new("UIScale")
TabIndicatorScale.Scale = 1
TabIndicatorScale.Parent = TabIndicator

local TabIndicatorGradient = Instance.new("UIGradient")
TabIndicatorGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Theme.AccentSoft),
	ColorSequenceKeypoint.new(0.55, Theme.White),
	ColorSequenceKeypoint.new(1, Theme.Accent),
})
TabIndicatorGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.30),
	NumberSequenceKeypoint.new(0.55, 0.46),
	NumberSequenceKeypoint.new(1, 0.30),
})
TabIndicatorGradient.Rotation = 90
TabIndicatorGradient.Parent = TabIndicator

local function moveTabIndicator(btn, instant)
	task.defer(function()
		if not btn or not btn.Parent or not MainFrame.Parent then return end
		-- The tabs are laid out by UIPadding + UIListLayout, so their actual
		-- pixel positions are more reliable than reconstructing the math from
		-- UDim2. Convert the pressed tab's absolute rectangle into MainFrame
		-- coordinates so the glass pill lands exactly over that tab.
		local layerPos = TabIndicatorLayer.AbsolutePosition
		local btnPos = btn.AbsolutePosition
		local targetSize = UDim2.fromOffset(btn.AbsoluteSize.X, btn.AbsoluteSize.Y)
		local targetPosition = UDim2.fromOffset(
			btnPos.X - layerPos.X,
			btnPos.Y - layerPos.Y
		)

		if instant then
			TabIndicator.Size = targetSize
			TabIndicator.Position = targetPosition
			TabIndicatorScale.Scale = 1
		else
			TweenService:Create(TabIndicator, TweenSoft, {
				Size = targetSize,
				Position = targetPosition,
			}):Play()
			TweenService:Create(TabIndicatorScale, TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.025}):Play()
			task.delay(0.075, function()
				if TabIndicator.Parent then
					TweenService:Create(TabIndicatorScale, TweenInfo.new(0.17, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Scale = 1}):Play()
				end
			end)
		end
	end)
end

local function setTabVisual(btn, active, instant)
	local targetBackground = active and 1 or 0.92
	local targetText = active and Theme.Text or Theme.TextSecondary

	if instant then
		btn.BackgroundTransparency = targetBackground
		btn.TextColor3 = targetText
	else
		TweenService:Create(btn, TweenFast, {
			BackgroundTransparency = targetBackground,
			TextColor3 = targetText,
		}):Play()
	end

	local stroke = btn:FindFirstChild("TabStroke")
	if stroke then
		if instant then
			stroke.Transparency = active and 0.55 or 1
		else
			TweenService:Create(stroke, TweenFast, {Transparency = active and 0.55 or 1}):Play()
		end
	end

	if active then
		moveTabIndicator(btn, instant)
	end
end

MainFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if ActiveTabName and Containers[ActiveTabName] then
		moveTabIndicator(Containers[ActiveTabName].Button, true)
	end
end)

local function activateTab(name)
	if ActiveTabName ~= name then
		playUISound(ButtonSFX)
	end
	ActiveTabName = name

	for tabName, tab in pairs(Containers) do
		local active = tabName == name
		tab.Page.Visible = active
		setTabVisual(tab.Button, active, false)
	end
end

local function createTab(name, _pastelBaseColor)
	local btn = Instance.new("TextButton")
	btn.Name = name .. "Tab"
	btn.Size = UDim2.new(1/6, -4, 0, 32)
	btn.BackgroundColor3 = Theme.Surface
	btn.BackgroundTransparency = 0.92
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = name
	btn.TextColor3 = Theme.TextSecondary
	btn.FontFace = ROBOTO_MEDIUM
	btn.TextSize = 10
	btn.ZIndex = 7
	btn.Parent = TabBar

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = btn

	local btnStroke = Instance.new("UIStroke")
	btnStroke.Name = "TabStroke"
	btnStroke.Color = Theme.AccentSoft
	btnStroke.Transparency = 1
	btnStroke.Thickness = 1
	btnStroke.Parent = btn

	local page = Instance.new("ScrollingFrame")
	page.Name = name .. "Page"
	page.Size = UDim2.new(1, -20, 1, -122)
	page.Position = UDim2.new(0, 10, 0, 114)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 2
	page.ScrollBarImageColor3 = Theme.Accent
	page.ScrollBarImageTransparency = 0.55
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.ScrollingDirection = Enum.ScrollingDirection.Y
	page.Visible = false
	page.ZIndex = 3
	page.Parent = MainFrame

	local PagePadding = Instance.new("UIPadding")
	PagePadding.PaddingLeft = UDim.new(0, 2)
	PagePadding.PaddingRight = UDim.new(0, 5)
	PagePadding.PaddingTop = UDim.new(0, 3)
	PagePadding.PaddingBottom = UDim.new(0, 8)
	PagePadding.Parent = page

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 9)
	layout.Parent = page

	local pageData = {
		Button = btn,
		Page = page,
	}

	Containers[name] = pageData

	btn.MouseButton1Click:Connect(function()
		activateTab(name)
	end)

	btn.MouseEnter:Connect(function()
		if ActiveTabName ~= name then
			TweenService:Create(
				btn,
				TweenFast,
				{
					BackgroundTransparency = 0.82,
					TextColor3 = Theme.Text,
				}
			):Play()
		end
	end)

	btn.MouseLeave:Connect(function()
		if ActiveTabName ~= name then
			TweenService:Create(btn, TweenFast, {
				BackgroundTransparency = 0.92,
				TextColor3 = Theme.TextSecondary,
			}):Play()
		end
	end)

	btn.MouseButton1Down:Connect(function()
		TweenService:Create(TabIndicator, TweenFast, {BackgroundTransparency = 0.42}):Play()
		hapticPulse(TabIndicator, TabIndicatorScale, 0.7)
	end)

	btn.MouseButton1Up:Connect(function()
		TweenService:Create(TabIndicator, TweenFast, {BackgroundTransparency = 0.56}):Play()
	end)

	btn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(TabIndicator, TweenFast, {BackgroundTransparency = 0.42}):Play()
			hapticPulse(TabIndicator, TabIndicatorScale, 0.7)
		end
	end)

	btn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(TabIndicator, TweenFast, {BackgroundTransparency = 0.56}):Play()
		end
	end)

	return page
end

-- ==========================================
-- 🧩 SECTION / COMPONENT BUILDERS
-- ==========================================

local function createSectionHeader(titleText, parent)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, 28)
	container.BackgroundTransparency = 1
	container.ZIndex = 4
	container.Parent = parent

	local dot = Instance.new("Frame")
	dot.Size = UDim2.new(0, 6, 0, 6)
	dot.Position = UDim2.new(0, 2, 0.5, -3)
	dot.BackgroundColor3 = Theme.Accent
	dot.BorderSizePixel = 0
	dot.Parent = container

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0, 120, 1, 0)
	title.Position = UDim2.new(0, 14, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = titleText
	title.TextColor3 = Theme.Text
	title.FontFace = ROBOTO_BOLD
	title.TextSize = 11
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = container

	local line = Instance.new("Frame")
	line.Size = UDim2.new(1, -145, 0, 1)
	line.Position = UDim2.new(0, 139, 0.5, 0)
	line.BackgroundColor3 = Theme.White
	line.BackgroundTransparency = 0.80
	line.BorderSizePixel = 0
	line.Parent = container

	return container
end

local function createButton(text, parent, _pastelColor)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 42)
	btn.BackgroundColor3 = Theme.Surface
	btn.BackgroundTransparency = Theme.SurfaceTransparency
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = Theme.Text
	btn.FontFace = ROBOTO_MEDIUM
	btn.TextSize = 11
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.AutoButtonColor = false
	btn.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = btn

	local buttonScale = Instance.new("UIScale")
	buttonScale.Scale = 1
	buttonScale.Parent = btn

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	-- Reserve room for the wider Apple-style switch track.
	padding.PaddingRight = UDim.new(0, 98)
	padding.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.White
	stroke.Transparency = Theme.StrokeTransparency
	stroke.Thickness = 1
	stroke.Parent = btn

	-- The existing TextButton remains the click target and keeps all feature callbacks.
	-- This transparent holder contains only visual layers and mirrors btn.Text's ON/OFF suffix.
	local status = Instance.new("Frame")
	status.Name = "StatusPill" -- Preserve this name for existing lookups elsewhere in the script.
	status.Size = UDim2.new(0, 70, 0, 29)
	status.Position = UDim2.new(1, -78, 0.5, -14.5)
	status.BackgroundTransparency = 1
	status.BorderSizePixel = 0
	status.Visible = false
	status.Active = false
	status.Selectable = false
	status.ZIndex = btn.ZIndex + 1
	status.Parent = btn


	local function makeSwitchTrack(name, imageId)
		local image = Instance.new("ImageLabel")
		image.Name = name
		image.Size = UDim2.fromScale(1, 1)
		image.Position = UDim2.fromScale(0, 0)
		image.BackgroundTransparency = 1
		image.BorderSizePixel = 0
		image.Image = imageId
		image.ImageTransparency = 0
		image.ScaleType = Enum.ScaleType.Stretch
		image.Active = false
		image.Selectable = false
		image.ZIndex = status.ZIndex
		image.Parent = status
		return image
	end

	-- Homemade fallback remains behind the exported artwork. If Roblox cannot
	-- display an uploaded image (permissions/moderation/asset-type issues), the
	-- toggle remains legible and functional rather than showing only the knob.
	local fallbackTrack = Instance.new("Frame")
	fallbackTrack.Name = "FallbackTrack"
	fallbackTrack.Size = UDim2.fromScale(1, 1)
	fallbackTrack.BackgroundColor3 = Theme.Track
	fallbackTrack.BackgroundTransparency = 0
	fallbackTrack.BorderSizePixel = 0
	fallbackTrack.ZIndex = status.ZIndex
	fallbackTrack.Parent = status
	local fallbackCorner = Instance.new("UICorner")
	fallbackCorner.CornerRadius = UDim.new(1, 0)
	fallbackCorner.Parent = fallbackTrack
	-- Minimal geometric I/O indicators instead of literal letters: a slim bar for I,
	-- and a thin ring for O. They sit on the side opposite the thumb.
	local onIndicator = Instance.new("Frame")
	onIndicator.Name = "OnIndicator"
	onIndicator.AnchorPoint = Vector2.new(0, 0.5)
	onIndicator.Size = UDim2.new(0, 1.8, 0, 9)
	onIndicator.Position = UDim2.new(0, 12, 0.5, 0)
	onIndicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	onIndicator.BackgroundTransparency = 0.08
	onIndicator.BorderSizePixel = 0
	onIndicator.ZIndex = status.ZIndex + 1
	onIndicator.Visible = false
	onIndicator.Parent = fallbackTrack

	local offIndicator = Instance.new("Frame")
	offIndicator.Name = "OffIndicator"
	offIndicator.AnchorPoint = Vector2.new(0.5, 0.5)
	offIndicator.Size = UDim2.new(0, 7, 0, 7)
	offIndicator.Position = UDim2.new(1, -12, 0.5, 0)
	offIndicator.BackgroundTransparency = 1
	offIndicator.BorderSizePixel = 0
	offIndicator.ZIndex = status.ZIndex + 1
	offIndicator.Visible = true
	offIndicator.Parent = fallbackTrack
	local offIndicatorCorner = Instance.new("UICorner")
	offIndicatorCorner.CornerRadius = UDim.new(1, 0)
	offIndicatorCorner.Parent = offIndicator
	local offIndicatorStroke = Instance.new("UIStroke")
	offIndicatorStroke.Color = Color3.fromRGB(255, 255, 255)
	offIndicatorStroke.Thickness = 1.08
	offIndicatorStroke.Transparency = 0.12
	offIndicatorStroke.Parent = offIndicator

	-- These assets already contain the I/O marks and the track's colour/shape.
	-- Do not add another indicator on the knob. They sit above the fallback.
	local offTrackImage = makeSwitchTrack("OffTrackImage", OFF_SWITCH_IMAGE)
	local onTrackImage = makeSwitchTrack("OnTrackImage", ON_SWITCH_IMAGE)
	onTrackImage.Visible = false

	-- One independent white pill-shaped thumb, with no external decal required.
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.new(0, 30, 0, 23)
	knob.Position = UDim2.new(0, 3, 0.5, -11.5)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BackgroundTransparency = 0
	knob.BorderSizePixel = 0
	knob.Active = false
	knob.Selectable = false
	knob.ZIndex = status.ZIndex + 1
	knob.Parent = status

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	local knobScale = Instance.new("UIScale")
	knobScale.Name = "KnobWobbleScale"
	knobScale.Scale = 1
	knobScale.Parent = knob

	local lastStatus = nil
	local function updateStatusVisual()
		local upper = string.upper(btn.Text)
		-- Only treat an explicit trailing ON/OFF state as a toggle.
		-- This preserves the original behaviour for ordinary action buttons.
		local isOn = string.match(upper, "ON%s*$") ~= nil
		local isOff = string.match(upper, "OFF%s*$") ~= nil

		status.Visible = isOn or isOff
		onTrackImage.Visible = isOn
		offTrackImage.Visible = isOff
		fallbackTrack.BackgroundColor3 = isOn and Theme.ToggleOn or Theme.Track
		onIndicator.Visible = isOn
		offIndicator.Visible = isOff

		local currentStatus = isOn and "ON" or (isOff and "OFF" or nil)
		if currentStatus and lastStatus and currentStatus ~= lastStatus then
			playUISound(ToggleSFX)
			hapticPulse(knob, knobScale, 1.0)
		end
		lastStatus = currentStatus

		if not status.Visible then
			return
		end

		-- Track images switch instantly; the thumb glides to the opposite side of I/O.
		local targetPosition = isOn
			and UDim2.new(1, -33, 0.5, -11.5)
			or UDim2.new(0, 3, 0.5, -11.5)
		TweenService:Create(knob, TweenFast, {Position = targetPosition}):Play()
	end

	btn:GetPropertyChangedSignal("Text"):Connect(updateStatusVisual)
	updateStatusVisual()

	btn.MouseEnter:Connect(function()
		TweenService:Create(
			btn,
			TweenFast,
			{
				BackgroundTransparency = Theme.SurfaceHoverTransparency,
				BackgroundColor3 = Theme.SurfaceHover,
			}
		):Play()
	end)

	btn.MouseLeave:Connect(function()
		TweenService:Create(
			btn,
			TweenFast,
			{
				BackgroundTransparency = Theme.SurfaceTransparency,
				BackgroundColor3 = Theme.Surface,
			}
		):Play()
	end)

	local function pressButton()
		-- Toggle rows use their moving thumb instead of the action-button press scale.
		if status.Visible then return end
		playUISound(ButtonSFX)
		hapticPulse(btn, buttonScale, 1.0)
		TweenService:Create(btn, TweenFast, {
			BackgroundTransparency = Theme.SurfacePressedTransparency,
			BackgroundColor3 = Theme.SurfacePressed,
		}):Play()
		TweenService:Create(buttonScale, TweenFast, {Scale = 0.97}):Play()
	end

	local function releaseButton()
		if status.Visible then return end
		TweenService:Create(btn, TweenFast, {
			BackgroundTransparency = Theme.SurfaceHoverTransparency,
			BackgroundColor3 = Theme.SurfaceHover,
		}):Play()
		TweenService:Create(buttonScale, TweenFast, {Scale = 1}):Play()
	end

	btn.MouseButton1Down:Connect(pressButton)
	btn.MouseButton1Up:Connect(releaseButton)
	btn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then pressButton() end
	end)
	btn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then releaseButton() end
	end)

	return btn
end

local function createSlider(name, default, minVal, maxVal, parent, callback)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, 52)
	container.BackgroundTransparency = 1
	container.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.70, 0, 0, 18)
	label.Position = UDim2.new(0, 1, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = name
	label.TextColor3 = Theme.Text
	label.FontFace = ROBOTO_MEDIUM
	label.TextSize = 10.5
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = container

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(0.30, -1, 0, 18)
	valueLabel.Position = UDim2.new(0.70, 0, 0, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.TextColor3 = Theme.TextSecondary
	valueLabel.FontFace = ROBOTO_MEDIUM
	valueLabel.TextSize = 10
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Parent = container

	local track = Instance.new("TextButton")
	track.Size = UDim2.new(1, 0, 0, 7)
	track.Position = UDim2.new(0, 0, 0, 31)
	track.BackgroundColor3 = Theme.Track
	track.BackgroundTransparency = 0.12
	track.BorderSizePixel = 0
	track.Text = ""
	track.AutoButtonColor = false
	track.Parent = container

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local initialAlpha = math.clamp((default - minVal) / (maxVal - minVal), 0, 1)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(initialAlpha, 0, 1, 0)
	fill.BackgroundColor3 = Theme.Accent
	fill.BackgroundTransparency = 0
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	-- Keep the slider thumb horizontal, matching the compact iOS-style control.
	-- A Roblox Frame remains underneath as a fallback if the image asset does not load.
	local knobFallback = Instance.new("Frame")
	knobFallback.Name = "KnobFallback"
	knobFallback.Size = UDim2.new(0, 22, 0, 14)
	knobFallback.AnchorPoint = Vector2.new(0.5, 0.5)
	knobFallback.Position = UDim2.new(initialAlpha, 0, 0.5, 0)
	knobFallback.BackgroundColor3 = Theme.White
	knobFallback.BorderSizePixel = 0
	knobFallback.ZIndex = track.ZIndex + 1
	knobFallback.Parent = track
	local fallbackCorner = Instance.new("UICorner")
	fallbackCorner.CornerRadius = UDim.new(1, 0)
	fallbackCorner.Parent = knobFallback

	local knob = Instance.new("ImageLabel")
	knob.Name = "Knob"
	knob.Size = UDim2.new(0, 22, 0, 14)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new(initialAlpha, 0, 0.5, 0)
	knob.BackgroundTransparency = 1
	knob.Image = SLIDER_KNOB_IMAGE
	knob.ImageColor3 = Theme.White
	knob.ScaleType = Enum.ScaleType.Stretch
	knob.ZIndex = track.ZIndex + 2
	knob.Parent = track
	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob


	local knobStroke = Instance.new("UIStroke")
	knobStroke.Color = Color3.fromRGB(228, 234, 242)
	knobStroke.Transparency = 0.48
	knobStroke.Thickness = 1
	knobStroke.Parent = knob

	local sliding = false

	local function setValueFromX(pointerX)
		local relX = math.clamp(
			(pointerX - track.AbsolutePosition.X) / track.AbsoluteSize.X,
			0,
			1
		)

		fill.Size = UDim2.new(relX, 0, 1, 0)
		local trackWidth = math.max(track.AbsoluteSize.X, 1)
		local edgeAlpha = (knob.AbsoluteSize.X / 2) / trackWidth
		local thumbAlpha = math.clamp(relX, edgeAlpha, 1 - edgeAlpha)
		local thumbPosition = UDim2.new(thumbAlpha, 0, 0.5, 0)
		knob.Position = thumbPosition
		knobFallback.Position = thumbPosition

		local val = minVal + (relX * (maxVal - minVal))
		val = math.floor(val * 10) / 10
		valueLabel.Text = tostring(val)
		callback(val)
	end

	local function beginSlider(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			sliding = true
			setValueFromX(input.Position.X)
		end
	end

	track.InputBegan:Connect(beginSlider)

	track.MouseEnter:Connect(function()
		TweenService:Create(knobStroke, TweenFast, {Transparency = 0.18}):Play()
	end)

	track.MouseLeave:Connect(function()
		if not sliding then
			TweenService:Create(knobStroke, TweenFast, {Transparency = 0.48}):Play()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			sliding = false
			TweenService:Create(knobStroke, TweenFast, {Transparency = 0.48}):Play()
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			setValueFromX(input.Position.X)
		end
	end)

	track.TouchPan:Connect(function(touchPositions, _totalTranslation, _velocity, state)
		if state == Enum.UserInputState.Begin then
			sliding = true
			local touch = touchPositions and touchPositions[1]
			if touch then
				setValueFromX(touch.X)
			end
		elseif state == Enum.UserInputState.Change and sliding then
			local touch = touchPositions and touchPositions[1]
			if touch then
				setValueFromX(touch.X)
			end
		elseif state == Enum.UserInputState.End then
			sliding = false
		end
	end)

	valueLabel.Text = tostring(math.floor(default * 10) / 10)
end

local function create2DColorPicker(titleText, defaultColor, parent, callback)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, 114)
	container.BackgroundColor3 = Theme.Surface
	container.BackgroundTransparency = Theme.SurfaceTransparency
	container.BorderSizePixel = 0
	container.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.RadiusPanel)
	corner.Parent = container

	local border = Instance.new("UIStroke")
	border.Color = Theme.White
	border.Transparency = 0.78
	border.Thickness = 1
	border.Parent = container

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, -16, 0, 18)
	header.Position = UDim2.new(0, 8, 0, 7)
	header.BackgroundTransparency = 1
	header.Parent = container

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -30, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = titleText
	label.TextColor3 = Theme.Text
	label.FontFace = ROBOTO_MEDIUM
	label.TextSize = 10.5
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = header

	local preview = Instance.new("Frame")
	preview.Size = UDim2.new(0, 16, 0, 16)
	preview.AnchorPoint = Vector2.new(1, 0)
	preview.Position = UDim2.new(1, 0, 0, 1)
	preview.BackgroundColor3 = defaultColor
	preview.BorderSizePixel = 0
	preview.Parent = header

	local previewCorner = Instance.new("UICorner")
	previewCorner.CornerRadius = UDim.new(1, 0)
	previewCorner.Parent = preview

	local previewStroke = Instance.new("UIStroke")
	previewStroke.Color = Theme.White
	previewStroke.Transparency = 0.35
	previewStroke.Parent = preview

	local canvas = Instance.new("TextButton")
	canvas.Size = UDim2.new(1, -16, 0, 76)
	canvas.Position = UDim2.new(0, 8, 0, 31)
	canvas.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	canvas.BackgroundTransparency = 0.03
	canvas.BorderSizePixel = 0
	canvas.AutoButtonColor = false
	canvas.Text = ""
	canvas.Parent = container

	local canvasCorner = Instance.new("UICorner")
	canvasCorner.CornerRadius = UDim.new(0, 10)
	canvasCorner.Parent = canvas

	local hueGrad = Instance.new("UIGradient")
	hueGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
		ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
		ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
		ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
		ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
	})
	hueGrad.Parent = canvas

	-- Subtle vertical light-to-dark value overlay.
	local valueOverlay = Instance.new("Frame")
	valueOverlay.Size = UDim2.new(1, 0, 1, 0)
	valueOverlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	valueOverlay.BackgroundTransparency = 1
	valueOverlay.BorderSizePixel = 0
	valueOverlay.Parent = canvas

	local valueGradient = Instance.new("UIGradient")
	valueGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
	})
	valueGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.78),
		NumberSequenceKeypoint.new(0.55, 0.84),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	valueGradient.Rotation = 90
	valueGradient.Parent = valueOverlay

	local dot = Instance.new("Frame")
	dot.Size = UDim2.new(0, 11, 0, 11)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3 = Theme.White
	dot.BorderSizePixel = 0
	dot.ZIndex = canvas.ZIndex + 3
	dot.Parent = canvas

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	local dotStroke = Instance.new("UIStroke")
	dotStroke.Color = Color3.fromRGB(25, 35, 45)
	dotStroke.Transparency = 0.10
	dotStroke.Thickness = 1.5
	dotStroke.Parent = dot

	local h = Color3.toHSV(defaultColor)
	local defaultHue, _, defaultValue = Color3.toHSV(defaultColor)
	local defaultY = math.clamp((1 - defaultValue) * 2, 0, 1)
	dot.Position = UDim2.new(defaultHue, 0, defaultY, 0)

	local draggingColor = false

	local function updateColor(input)
		local relX = math.clamp(
			(input.Position.X - canvas.AbsolutePosition.X) / canvas.AbsoluteSize.X,
			0,
			1
		)

		local relY = math.clamp(
			(input.Position.Y - canvas.AbsolutePosition.Y) / canvas.AbsoluteSize.Y,
			0,
			1
		)

		dot.Position = UDim2.new(relX, 0, relY, 0)

		local newCol = Color3.fromHSV(
			relX,
			1,
			1 - (relY * 0.5)
		)

		preview.BackgroundColor3 = newCol
		callback(newCol)
	end

	canvas.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			draggingColor = true
			updateColor(input)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			draggingColor = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if draggingColor and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			updateColor(input)
		end
	end)

	canvas.TouchPan:Connect(function(touchPositions, _totalTranslation, _velocity, state)
		if state == Enum.UserInputState.Begin then
			draggingColor = true
			local touch = touchPositions and touchPositions[1]
			if touch then
				updateColor({Position = touch})
			end
		elseif state == Enum.UserInputState.Change and draggingColor then
			local touch = touchPositions and touchPositions[1]
			if touch then
				updateColor({Position = touch})
			end
		elseif state == Enum.UserInputState.End then
			draggingColor = false
		end
	end)
end

-- ==========================================
-- 💠 CREATE TABS
-- ==========================================

HubState.ESPPage = createTab("ESP", Theme.AccentSoft)
HubState.WaypointPage = createTab("Pins", Theme.AccentSoft)
HubState.WarningPage = createTab("Warnings", Theme.AccentSoft)
HubState.SpeedPage = createTab("Speed", Theme.AccentSoft)
HubState.OthersPage = createTab("Others", Theme.AccentSoft)
HubState.SettingsPage = createTab("Config", Theme.AccentSoft)

Containers["ESP"].Page.Visible = true
setTabVisual(Containers["ESP"].Button, true, true)

-- ==========================================
-- ⚠️ PLAYER WARNING UI & JOIN DETECTION
-- ==========================================
createSectionHeader("Watched Players", HubState.WarningPage)

HubState.WarningNameBox = Instance.new("TextBox")
HubState.WarningNameBox.Size = UDim2.new(1, 0, 0, 36)
HubState.WarningNameBox.BackgroundColor3 = Theme.Surface
HubState.WarningNameBox.BackgroundTransparency = Theme.SurfaceTransparency
HubState.WarningNameBox.PlaceholderText = "Enter Roblox username..."
HubState.WarningNameBox.PlaceholderColor3 = Theme.TextSecondary
HubState.WarningNameBox.Text = ""
HubState.WarningNameBox.TextColor3 = Theme.Text
HubState.WarningNameBox.FontFace = ROBOTO_REGULAR
HubState.WarningNameBox.TextSize = 11
HubState.WarningNameBox.ClearTextOnFocus = false
HubState.WarningNameBox.Parent = HubState.WarningPage
Instance.new("UICorner", HubState.WarningNameBox).CornerRadius = UDim.new(0.5, 0)
HubState.warningBoxPadding = Instance.new("UIPadding")
HubState.warningBoxPadding.PaddingLeft = UDim.new(0, 12)
HubState.warningBoxPadding.PaddingRight = UDim.new(0, 12)
HubState.warningBoxPadding.Parent = HubState.WarningNameBox
HubState.warningBoxStroke = Instance.new("UIStroke")
HubState.warningBoxStroke.Color = Theme.White
HubState.warningBoxStroke.Transparency = Theme.StrokeTransparency
HubState.warningBoxStroke.Thickness = 1
HubState.warningBoxStroke.Parent = HubState.WarningNameBox

HubState.AddWarningBtn = createButton("Add Player Warning", HubState.WarningPage, Theme.Surface)
HubState.WarningStatusLabel = Instance.new("TextLabel")
HubState.WarningStatusLabel.Size = UDim2.new(1, 0, 0, 18)
HubState.WarningStatusLabel.BackgroundTransparency = 1
HubState.WarningStatusLabel.Text = "Saved warnings: 0  •  " .. WarningPersistenceMode
HubState.WarningStatusLabel.TextColor3 = Theme.TextSecondary
HubState.WarningStatusLabel.FontFace = ROBOTO_REGULAR
HubState.WarningStatusLabel.TextSize = 9
HubState.WarningStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
HubState.WarningStatusLabel.Parent = HubState.WarningPage

HubState.CheckServerWarningsBtn = createButton("Check Watched Players In Server", HubState.WarningPage, Theme.Surface)

HubState.WarningListFrame = Instance.new("ScrollingFrame")
HubState.WarningListFrame.Size = UDim2.new(1, 0, 0, 170)
HubState.WarningListFrame.BackgroundTransparency = 1
HubState.WarningListFrame.BorderSizePixel = 0
HubState.WarningListFrame.ScrollBarThickness = 2
HubState.WarningListFrame.ScrollBarImageColor3 = Theme.Accent
HubState.WarningListFrame.ScrollBarImageTransparency = 0.55
HubState.WarningListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
HubState.WarningListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
HubState.WarningListFrame.Parent = HubState.WarningPage

HubState.WarningListLayout = Instance.new("UIListLayout")
HubState.WarningListLayout.SortOrder = Enum.SortOrder.LayoutOrder
HubState.WarningListLayout.Padding = UDim.new(0, 5)
HubState.WarningListLayout.Parent = HubState.WarningListFrame

local function refreshWarningList()
	for _, child in ipairs(HubState.WarningListFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	for index, username in ipairs(HubState.PlayerWarnings) do
		local row = Instance.new("Frame")
			row.Name = "WarningRow"
			row.Size = UDim2.new(1, -4, 0, 30)
			row.BackgroundColor3 = Theme.Surface
			row.BackgroundTransparency = Theme.SurfaceTransparency
			row.BorderSizePixel = 0
			row.LayoutOrder = index
			row.Parent = HubState.WarningListFrame
			Instance.new("UICorner", row).CornerRadius = UDim.new(0.5, 0)
			local dot = Instance.new("Frame")
			dot.Size = UDim2.fromOffset(7,7)
			dot.Position = UDim2.new(0,9,0.5,-3.5)
			local currentlyInServer = false
			for _, onlinePlayer in ipairs(Players:GetPlayers()) do
				if string.lower(onlinePlayer.Name) == string.lower(username) then
					currentlyInServer = true
					break
				end
			end
			dot.BackgroundColor3 = currentlyInServer and Color3.fromRGB(90,220,135) or Theme.TextSecondary
			dot.BorderSizePixel = 0
			dot.Parent = row
			Instance.new("UICorner", dot).CornerRadius = UDim.new(1,0)
			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1,-52,1,0)
			label.Position = UDim2.new(0,23,0,0)
			label.BackgroundTransparency = 1
			label.Text = username
			label.TextColor3 = Theme.Text
			label.FontFace = ROBOTO_MEDIUM
			label.TextSize = 10
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.Parent = row
			local remove = Instance.new("TextButton")
			remove.Size = UDim2.fromOffset(28,24)
			remove.Position = UDim2.new(1,-32,0.5,-12)
			remove.BackgroundTransparency = 1
			remove.Text = "×"
			remove.TextColor3 = Theme.TextSecondary
			remove.FontFace = ROBOTO_BOLD
			remove.TextSize = 16
			remove.Parent = row
			remove.MouseButton1Click:Connect(function()
				local currentIndex = table.find(HubState.PlayerWarnings, username)
				if currentIndex then
					table.remove(HubState.PlayerWarnings, currentIndex)
					savePlayerWarnings()
					refreshWarningList()
				end
			end)
	end
	HubState.WarningStatusLabel.Text = "Saved warnings: " .. tostring(#HubState.PlayerWarnings) .. "  •  " .. WarningPersistenceMode
end

local function checkWatchedPlayersInServer()
	local found = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			for _, watchedName in ipairs(HubState.PlayerWarnings) do
				if string.lower(watchedName) == string.lower(player.Name) then
					table.insert(found, player.Name)
					break
				end
			end
		end
	end

	if #found == 0 then
		showNotification("Player Warning", "None of your watched players are currently in this server.", 3.5)
		HubState.WarningStatusLabel.Text = "Saved warnings: " .. tostring(#HubState.PlayerWarnings) .. "  •  " .. WarningPersistenceMode .. "  •  None found in server"
	else
		local shown = table.concat(found, ", ")
		showNotification("⚠ Watched Player Found", "In this server: " .. shown, 6)
		HubState.WarningStatusLabel.Text = "Saved warnings: " .. tostring(#HubState.PlayerWarnings) .. "  •  " .. WarningPersistenceMode .. "  •  Found: " .. shown
	end
end

HubState.CheckServerWarningsBtn.MouseButton1Click:Connect(checkWatchedPlayersInServer)
Players.PlayerAdded:Connect(function()
	task.defer(refreshWarningList)
end)
Players.PlayerRemoving:Connect(function()
	task.defer(refreshWarningList)
end)

local function addPlayerWarning(username)
	username = tostring(username or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if username == "" then
		showNotification("Player Warning", "Enter a username first.", 2.5)
		return
	end

	for _, existing in ipairs(HubState.PlayerWarnings) do
		if string.lower(existing) == string.lower(username) then
			showNotification("Player Warning", username .. " is already being watched.", 2.5)
			return
		end
	end

	table.insert(HubState.PlayerWarnings, username)
	savePlayerWarnings()
	refreshWarningList()
	HubState.WarningNameBox.Text = ""
	showNotification("Player Warning", "Now watching " .. username .. ".", 2.5)
end

HubState.AddWarningBtn.MouseButton1Click:Connect(function()
	addPlayerWarning(HubState.WarningNameBox.Text)
end)

HubState.WarningNameBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		addPlayerWarning(HubState.WarningNameBox.Text)
	end
end)

local function checkPlayerWarning(player)
	if not player or player == LocalPlayer then return end
	for _, watchedName in ipairs(HubState.PlayerWarnings) do
		if string.lower(watchedName) == string.lower(player.Name) then
			showNotification("⚠ Player Warning", player.Name .. " joined the server.", 6)
			return
		end
	end
end

Players.PlayerAdded:Connect(checkPlayerWarning)
refreshWarningList()

-- ==========================================
-- 💊 HEALTH BAR ENGINE
-- ==========================================
local function applyHealthBar(character, humanoid, tagPrefix, alwaysOnTop)
	local rootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head") or character:FindFirstChildWhichIsA("BasePart")
	if not rootPart then return end

	if rootPart:FindFirstChild(tagPrefix.."_HEALTH_BAR") then
		rootPart[tagPrefix.."_HEALTH_BAR"]:Destroy()
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = tagPrefix.."_HEALTH_BAR"
	bb.Adornee = rootPart
	bb.Size = UDim2.new(0, 78, 0, 15)
	bb.StudsOffset = Vector3.new(0, 3.25, 0)
	bb.AlwaysOnTop = alwaysOnTop
	bb.LightInfluence = 0
	bb.Parent = rootPart

	local bg = Instance.new("Frame")
	bg.Name = "HealthBackground"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(34, 42, 52)
	bg.BackgroundTransparency = 0.18
	bg.BorderSizePixel = 0
	bg.Parent = bb

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(1, 0)
	bgCorner.Parent = bg

	local bgGradient = Instance.new("UIGradient")
	bgGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(61, 72, 85)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(38, 47, 59)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(27, 34, 44)),
	})
	bgGradient.Rotation = 90
	bgGradient.Parent = bg

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.White
	stroke.Transparency = 0.72
	stroke.Thickness = 1
	stroke.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "HealthFill"
	fill.Size = UDim2.new(math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1), 0, 1, 0)
	fill.BackgroundColor3 = (tagPrefix == "PLAYER") and HubState.PlayerColor or Theme.Accent
	fill.BackgroundTransparency = 0.02
	fill.BorderSizePixel = 0
	fill.ClipsDescendants = true
	fill.Parent = bg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local fillGradient = Instance.new("UIGradient")
	local baseColor = fill.BackgroundColor3
	fillGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, baseColor:Lerp(Color3.new(1, 1, 1), 0.28)),
		ColorSequenceKeypoint.new(0.45, baseColor),
		ColorSequenceKeypoint.new(1, baseColor:Lerp(Color3.new(0, 0, 0), 0.18)),
	})
	fill:SetAttribute("GeminiBaseColor", baseColor)
	fillGradient.Rotation = 90
	fillGradient.Parent = fill

	local hpText = Instance.new("TextLabel")
	hpText.Size = UDim2.new(1, -6, 1, 0)
	hpText.Position = UDim2.new(0, 3, 0, 0)
	hpText.BackgroundTransparency = 1
	hpText.Text = math.floor(humanoid.Health) .. " / " .. math.floor(humanoid.MaxHealth)
	hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpText.FontFace = ROBOTO_BOLD
	hpText.TextSize = 8
	hpText.TextStrokeTransparency = 1
	hpText.ZIndex = 2
	hpText.Parent = bg

	local shadowOk, shadow = pcall(function() return Instance.new("UIShadow") end)
	if shadowOk and shadow then
		pcall(function()
			shadow.Transparency = 0.82
			shadow.BlurRadius = UDim.new(0, 5)
			shadow.Offset = UDim2.new(0, 0, 0, 2)
			shadow.Parent = bg
		end)
	end

	local conn
	conn = humanoid.HealthChanged:Connect(function(health)
		if not bb or not bb.Parent then
			if conn then conn:Disconnect() end
			return
		end
		fill.Size = UDim2.new(math.clamp(health / humanoid.MaxHealth, 0, 1), 0, 1, 0)
		hpText.Text = math.floor(health) .. " / " .. math.floor(humanoid.MaxHealth)
	end)
end

-- ==========================================
-- 🤖 SECTION 1: NPC & PLAYER ESP LOGIC
-- ==========================================
createSectionHeader("NPCs", HubState.ESPPage)
HubState.NPCToggleBtn = createButton("Toggle NPC ESP: OFF", HubState.ESPPage, Theme.Surface)
HubState.NPCUpdateBtn = createButton("Refresh Scan NPCs", HubState.ESPPage, Color3.fromRGB(215, 235, 255))

HubState.NPCHighlights = {}
HubState.NPCHealthBars = {}
local NPCDescendantConnection

local function clearNPCESP()
	for model, highlight in pairs(HubState.NPCHighlights) do
		if highlight and highlight.Parent then highlight:Destroy() end
		HubState.NPCHighlights[model] = nil
	end
	for model, bar in pairs(HubState.NPCHealthBars) do
		if bar and bar.Parent then bar:Destroy() end
		HubState.NPCHealthBars[model] = nil
	end
	-- Clean up legacy instances that may have been created by an older run.
	for _, v in pairs(Workspace:GetDescendants()) do
		if v:IsA("Highlight") and v.Name == "NPC_HIGHLIGHT" then v:Destroy() end
		if v:IsA("BillboardGui") and string.find(v.Name, "NPC_HEALTH_BAR") then v:Destroy() end
	end
end

createSlider("NPC Fill Transparency", HubState.NPCFill, 0, 1, HubState.ESPPage, function(val)
	HubState.NPCFill = val
	for _, highlight in pairs(HubState.NPCHighlights) do
		if highlight and highlight.Parent then highlight.FillTransparency = val end
	end
end)

createSlider("NPC Outline Transparency", HubState.NPCOutline, 0, 1, HubState.ESPPage, function(val)
	HubState.NPCOutline = val
	for _, highlight in pairs(HubState.NPCHighlights) do
		if highlight and highlight.Parent then highlight.OutlineTransparency = val end
	end
end)

local function applyNPC(model)
	if not HubState.NPCToggled or not model or not model:IsA("Model") then return end
	if Players:GetPlayerFromCharacter(model) then return end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local existing = model:FindFirstChild("NPC_HIGHLIGHT")
	if existing and existing:IsA("Highlight") then
		existing.FillTransparency = HubState.NPCFill
		existing.OutlineTransparency = HubState.NPCOutline
		HubState.NPCHighlights[model] = existing
	else
		local h = Instance.new("Highlight")
		h.Name = "NPC_HIGHLIGHT"
		h.FillColor = Color3.fromRGB(255, 255, 255)
		h.FillTransparency = HubState.NPCFill
		h.OutlineColor = Color3.fromRGB(150, 200, 240)
		h.OutlineTransparency = HubState.NPCOutline
		h.Parent = model
		HubState.NPCHighlights[model] = h
	end

	local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head") or model:FindFirstChildWhichIsA("BasePart")
	local oldBar = root and root:FindFirstChild("NPC_HEALTH_BAR")
	if oldBar then oldBar:Destroy() end
	applyHealthBar(model, humanoid, "NPC", false)
	if root then HubState.NPCHealthBars[model] = root:FindFirstChild("NPC_HEALTH_BAR") end
end

local function scanNPCsOnce()
	clearNPCESP()
	if not HubState.NPCToggled then return end
	for _, descendant in pairs(Workspace:GetDescendants()) do
		if descendant:IsA("Humanoid") then
			local model = descendant.Parent
			if model and model:IsA("Model") then
				applyNPC(model)
			end
		end
	end
end

local function startNPCWatcher()
	if NPCDescendantConnection then return end
	NPCDescendantConnection = Workspace.DescendantAdded:Connect(function(descendant)
		if not HubState.NPCToggled or not descendant:IsA("Humanoid") then return end
		task.defer(function()
			local model = descendant.Parent
			if model and model:IsA("Model") then applyNPC(model) end
		end)
	end)
end

local function stopNPCWatcher()
	if NPCDescendantConnection then
		NPCDescendantConnection:Disconnect()
		NPCDescendantConnection = nil
	end
end

HubState.NPCToggleBtn.MouseButton1Click:Connect(function()
	HubState.NPCToggled = not HubState.NPCToggled
	HubState.NPCToggleBtn.Text = "Toggle NPC ESP: " .. (HubState.NPCToggled and "ON" or "OFF")
	if HubState.NPCToggled then
		scanNPCsOnce()
		startNPCWatcher()
	else
		stopNPCWatcher()
		clearNPCESP()
	end
end)

HubState.NPCUpdateBtn.MouseButton1Click:Connect(function()
	-- Refresh is now the expensive Workspace scan. Normal runtime is event-driven.
	scanNPCsOnce()
	if HubState.NPCToggled then startNPCWatcher() end
end)

createSectionHeader("Players", HubState.ESPPage)
HubState.PlayerToggleBtn = createButton("Toggle Player ESP: OFF", HubState.ESPPage, Theme.Surface)

createSlider("Player Fill Transparency", HubState.PlayerFill, 0, 1, HubState.ESPPage, function(val) 
	HubState.PlayerFill = val 
	for _, v in pairs(Players:GetPlayers()) do
		if v.Character and v.Character:FindFirstChild("PLAYER_HIGHLIGHT") then
			v.Character.PLAYER_HIGHLIGHT.FillTransparency = val
		end
	end
end)

createSlider("Player Outline", HubState.PlayerOutline, 0, 1, HubState.ESPPage, function(val) 
	HubState.PlayerOutline = val 
	for _, v in pairs(Players:GetPlayers()) do
		if v.Character and v.Character:FindFirstChild("PLAYER_HIGHLIGHT") then
			v.Character.PLAYER_HIGHLIGHT.OutlineTransparency = val
		end
	end
end)

createSectionHeader("Highlight", HubState.ESPPage)
create2DColorPicker("Player Highlight Color", HubState.PlayerColor, HubState.ESPPage, function(newColor)
	HubState.PlayerColor = newColor
	for _, plr in pairs(Players:GetPlayers()) do
		if plr.Character then
			local highlight = plr.Character:FindFirstChild("PLAYER_HIGHLIGHT")
			if highlight then
				highlight.FillColor = newColor
				highlight.OutlineColor = newColor
			end

			local root = plr.Character:FindFirstChild("HumanoidRootPart") or plr.Character:FindFirstChild("Head")
			local healthBar = root and root:FindFirstChild("PLAYER_HEALTH_BAR")
			local healthBg = healthBar and healthBar:FindFirstChild("HealthBackground")
			local healthFill = healthBg and healthBg:FindFirstChild("HealthFill")
			if healthFill then
				healthFill.BackgroundColor3 = newColor
				local healthGradient = healthFill:FindFirstChildOfClass("UIGradient")
				if healthGradient then
					healthGradient.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, newColor:Lerp(Color3.new(1, 1, 1), 0.28)),
						ColorSequenceKeypoint.new(0.45, newColor),
						ColorSequenceKeypoint.new(1, newColor:Lerp(Color3.new(0, 0, 0), 0.18)),
					})
				end
			end
		end
	end
end)

local function updateSinglePlayer(plr)
	if plr == LocalPlayer then return end
	local char = plr.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	
	if char:FindFirstChild("PLAYER_HIGHLIGHT") then char.PLAYER_HIGHLIGHT:Destroy() end
	local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
	if root and root:FindFirstChild("PLAYER_HEALTH_BAR") then root.PLAYER_HEALTH_BAR:Destroy() end
	
	if HubState.PlayerToggled then
		local h = Instance.new("Highlight")
		h.Name = "PLAYER_HIGHLIGHT"
		h.FillColor = HubState.PlayerColor
		h.FillTransparency = HubState.PlayerFill
		h.OutlineColor = HubState.PlayerColor
		h.OutlineTransparency = HubState.PlayerOutline
		h.Parent = char
		applyHealthBar(char, humanoid, "PLAYER", true)
	end
end

local function setupPlayerListeners(plr)
	plr.CharacterAdded:Connect(function(char)
		task.wait(1) 
		if HubState.PlayerToggled then updateSinglePlayer(plr) end
	end)
end
for _, plr in pairs(Players:GetPlayers()) do setupPlayerListeners(plr) end
Players.PlayerAdded:Connect(setupPlayerListeners)

HubState.PlayerToggleBtn.MouseButton1Click:Connect(function()
	HubState.PlayerToggled = not HubState.PlayerToggled
	HubState.PlayerToggleBtn.Text = "Toggle Player ESP: " .. (HubState.PlayerToggled and "ON" or "OFF")
	for _, plr in pairs(Players:GetPlayers()) do updateSinglePlayer(plr) end
end)

-- ==========================================
-- 🧹 ESP CLEANUP MANAGER
-- ==========================================
createSectionHeader("ESP Cleanup", HubState.ESPPage)
HubState.ESPCleanupStatus = Instance.new("TextLabel")
HubState.ESPCleanupStatus.Size = UDim2.new(1, 0, 0, 18)
HubState.ESPCleanupStatus.BackgroundTransparency = 1
HubState.ESPCleanupStatus.Text = "Scans for stale Gemini ESP instances only."
HubState.ESPCleanupStatus.TextColor3 = Theme.TextSecondary
HubState.ESPCleanupStatus.FontFace = ROBOTO_REGULAR
HubState.ESPCleanupStatus.TextSize = 9
HubState.ESPCleanupStatus.TextXAlignment = Enum.TextXAlignment.Left
HubState.ESPCleanupStatus.Parent = HubState.ESPPage

local function cleanupESPInstances()
	local removed = 0
	for _, v in ipairs(Workspace:GetDescendants()) do
		local stale = false
		if v:IsA("Highlight") and v.Name == "NPC_HIGHLIGHT" then
			local model = v.Parent
			stale = (not HubState.NPCToggled) or (not model) or (HubState.NPCHighlights[model] ~= v) or (not model:IsDescendantOf(Workspace))
		elseif v:IsA("Highlight") and v.Name == "PLAYER_HIGHLIGHT" then
			local owner = v.Parent and Players:GetPlayerFromCharacter(v.Parent)
			stale = (not HubState.PlayerToggled) or (not owner) or owner == LocalPlayer or owner.Character ~= v.Parent
		elseif v:IsA("Highlight") and v.Name == "Gemini_Hover_HL" then
			stale = not HubState.HoverToggled
		elseif v:IsA("SelectionBox") and v.Name == "Gemini_Hover_Outline" then
			stale = (not HubState.HoverToggled) or (not v.Adornee) or (not v.Adornee:IsDescendantOf(Workspace))
		elseif v:IsA("BillboardGui") and string.find(v.Name, "NPC_HEALTH_BAR") then
			local model = v.Adornee and v.Adornee:FindFirstAncestorOfClass("Model")
			stale = (not HubState.NPCToggled) or (not model) or (HubState.NPCHealthBars[model] ~= v)
		elseif v:IsA("BillboardGui") and string.find(v.Name, "PLAYER_HEALTH_BAR") then
			local model = v.Adornee and v.Adornee:FindFirstAncestorOfClass("Model")
			local owner = model and Players:GetPlayerFromCharacter(model)
			stale = (not HubState.PlayerToggled) or (not owner) or owner == LocalPlayer or owner.Character ~= model
		elseif v:IsA("BillboardGui") and v.Name == "Gemini_Hover_Name" then
			stale = not HubState.HoverToggled
		end
		if stale then
			v:Destroy()
			removed += 1
		end
	end
	HubState.ESPCleanupStatus.Text = "Cleaned " .. tostring(removed) .. " stale ESP instance" .. (removed == 1 and "" or "s") .. "."
	return removed
end

HubState.ESPCleanupBtn = createButton("Clean Stale ESP Instances", HubState.ESPPage, Theme.Surface)
HubState.ESPCleanupBtn.MouseButton1Click:Connect(cleanupESPInstances)

-- ==========================================
-- 📍 SECTION 2: WAYPOINT MANAGEMENT
-- ==========================================
loadWaypoints()

createSectionHeader("Waypoint Manager", HubState.WaypointPage)
create2DColorPicker("Waypoint Pin Color", HubState.WaypointColor, HubState.WaypointPage, function(newColor)
	HubState.WaypointColor = newColor
	saveWaypoints()
end)

HubState.WaypointNameBox = Instance.new("TextBox", HubState.WaypointPage)
HubState.WaypointNameBox.Size = UDim2.new(1, 0, 0, 36)
HubState.WaypointNameBox.BackgroundColor3 = Theme.Surface
HubState.WaypointNameBox.BackgroundTransparency = Theme.SurfaceTransparency
HubState.WaypointNameBox.PlaceholderText = "Enter Waypoint Name..."
HubState.WaypointNameBox.PlaceholderColor3 = Theme.TextSecondary
HubState.WaypointNameBox.Text = ""
HubState.WaypointNameBox.TextColor3 = Theme.Text
HubState.WaypointNameBox.FontFace = ROBOTO_REGULAR
HubState.WaypointNameBox.TextSize = 11
Instance.new("UICorner", HubState.WaypointNameBox).CornerRadius = UDim.new(0.5, 0)
HubState.wpBoxStroke = Instance.new("UIStroke", HubState.WaypointNameBox)
HubState.wpBoxStroke.Color = Theme.White
HubState.wpBoxStroke.Transparency = Theme.StrokeTransparency
HubState.wpBoxStroke.Thickness = 1

HubState.CreateWaypointBtn = createButton("Create Waypoint Here", HubState.WaypointPage, Color3.fromRGB(210, 235, 255))

HubState.WaypointListFrame = Instance.new("ScrollingFrame", HubState.WaypointPage)
HubState.WaypointListFrame.Size = UDim2.new(1, 0, 0, 140)
HubState.WaypointListFrame.BackgroundTransparency = 1
HubState.WaypointListFrame.ScrollBarThickness = 2

HubState.WaypointListLayout = Instance.new("UIListLayout", HubState.WaypointListFrame)
HubState.WaypointListLayout.SortOrder = Enum.SortOrder.LayoutOrder
HubState.WaypointListLayout.Padding = UDim.new(0, 4)

local function refreshWaypointList()
	for _, child in pairs(HubState.WaypointListFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	
	for idx, wpData in ipairs(HubState.Waypoints) do
		local row = Instance.new("Frame", HubState.WaypointListFrame)
		row.Size = UDim2.new(1, 0, 0, 32)
		row.BackgroundColor3 = Theme.Surface
		row.BackgroundTransparency = Theme.SurfaceTransparency
		Instance.new("UICorner", row).CornerRadius = UDim.new(0.5, 0)
		
		local rowIcon = Instance.new("ImageLabel", row)
		rowIcon.Size = UDim2.new(0, 16, 0, 16)
		rowIcon.Position = UDim2.new(0, 8, 0.5, -8)
		rowIcon.BackgroundTransparency = 1
		rowIcon.Image = HubState.WaypointAssetId
		rowIcon.ImageColor3 = wpData.Color
		
		local nameLabel = Instance.new("TextLabel", row)
		nameLabel.Size = UDim2.new(0.52, -5, 1, 0)
		nameLabel.Position = UDim2.new(0, 30, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = wpData.Name
		nameLabel.TextColor3 = Theme.Text
		nameLabel.FontFace = ROBOTO_BOLD
		nameLabel.TextSize = 10
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		
		local tpBtn = Instance.new("TextButton", row)
		tpBtn.Size = UDim2.new(0.18, 0, 0.76, 0)
		tpBtn.Position = UDim2.new(0.61, 0, 0.12, 0)
		tpBtn.BackgroundColor3 = Theme.Accent
		tpBtn.BackgroundTransparency = 0.12
		tpBtn.Text = "TP"
		tpBtn.TextColor3 = Theme.White
		tpBtn.FontFace = ROBOTO_BOLD
		tpBtn.TextSize = 10
		Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(0.5, 0)
		
		tpBtn.MouseButton1Click:Connect(function()
			local char = LocalPlayer.Character
			if char and char:FindFirstChild("HumanoidRootPart") then
				char:PivotTo(CFrame.new(wpData.Position + Vector3.new(0, 3, 0)))
				char.HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
				char.HumanoidRootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
			end
		end)
		
		local delBtn = Instance.new("TextButton", row)
		delBtn.Size = UDim2.new(0.16, 0, 0.76, 0)
		delBtn.Position = UDim2.new(0.81, 0, 0.12, 0)
		delBtn.BackgroundColor3 = Theme.SurfacePressed
		delBtn.Text = "X"
		delBtn.TextColor3 = Theme.Text
		delBtn.FontFace = ROBOTO_BOLD
		delBtn.TextSize = 10
		Instance.new("UICorner", delBtn).CornerRadius = UDim.new(0.5, 0)
		
		delBtn.MouseButton1Click:Connect(function()
			if wpData.Part then wpData.Part:Destroy() end
			table.remove(HubState.Waypoints, idx)
			refreshWaypointList()
			saveWaypoints()
		end)
	end
end

local function spawnWaypointWorldUI(wpData)
	local part = Instance.new("Part")
	part.Name = "Waypoint_" .. wpData.Name
	part.Size = Vector3.new(1, 1, 1)
	part.Position = wpData.Position
	part.Anchored = true; part.CanCollide = false; part.Transparency = 1
	part.Parent = WaypointFolder
	wpData.Part = part
	
	local bb = Instance.new("BillboardGui")
	bb.Name = "Waypoint_BB"
	bb.Adornee = part
	bb.AlwaysOnTop = true
	bb.Size = UDim2.new(0, 50, 0, 65)
	bb.Parent = part
	
	local img = Instance.new("ImageLabel", bb)
	img.Size = UDim2.new(0, 30, 0, 30)
	img.Position = UDim2.new(0.5, -15, 0, 0)
	img.BackgroundTransparency = 1
	img.Image = HubState.WaypointAssetId
	img.ImageColor3 = wpData.Color
	img.ZIndex = 5 
	
	local label = Instance.new("TextLabel", bb)
	label.Size = UDim2.new(1, 40, 0, 15)
	label.Position = UDim2.new(0.5, -20, 0, 32)
	label.BackgroundTransparency = 1
	label.Text = wpData.Name
	label.TextColor3 = Theme.Text
	label.FontFace = ROBOTO_BOLD
	label.TextSize = 11
	label.ZIndex = 4
	
	local distLabel = Instance.new("TextLabel", bb)
	distLabel.Size = UDim2.new(1, 40, 0, 12)
	distLabel.Position = UDim2.new(0.5, -20, 0, 47)
	distLabel.BackgroundTransparency = 1
	distLabel.Text = "0m"
	distLabel.TextColor3 = Theme.TextSecondary
	distLabel.FontFace = ROBOTO_REGULAR
	distLabel.TextSize = 10
	distLabel.ZIndex = 4
	
	RunService.RenderStepped:Connect(function()
		if not part or not part.Parent or not bb or not bb.Parent then return end
		local camera = Workspace.CurrentCamera
		if camera then
			local dist = (camera.CFrame.Position - wpData.Position).Magnitude
			distLabel.Text = math.floor(dist) .. "m"
			local alpha = math.clamp((dist - 15) / 300, 0, 1)
			local dynamicSize = math.floor(35 + (alpha * 35))
			bb.Size = UDim2.new(0, dynamicSize, 0, dynamicSize + 15)
			img.Size = UDim2.new(0, dynamicSize * 0.6, 0, dynamicSize * 0.6)
			img.Position = UDim2.new(0.5, -(dynamicSize * 0.3), 0, 0)
		end
	end)
end

-- Rebuild all saved waypoint world markers after the UI helper is defined.
for _, wpData in ipairs(HubState.Waypoints) do
	spawnWaypointWorldUI(wpData)
end
refreshWaypointList()

HubState.CreateWaypointBtn.MouseButton1Click:Connect(function()
	local char = LocalPlayer.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		local pos = char.HumanoidRootPart.Position
		local wpData = {
			Name = (HubState.WaypointNameBox.Text ~= "") and HubState.WaypointNameBox.Text or ("Pin " .. (#HubState.Waypoints + 1)),
			Position = pos,
			Color = HubState.WaypointColor
		}
		table.insert(HubState.Waypoints, wpData)
		spawnWaypointWorldUI(wpData)
		refreshWaypointList()
		saveWaypoints()
		HubState.WaypointNameBox.Text = ""
	end
end)

-- ==========================================
-- ⚡ SECTION 3: SPEED ENGINE & TELEMETRY
-- ==========================================
createSectionHeader("Speed Engine", HubState.SpeedPage)
HubState.SpeedToggleBtn = createButton("Speed Engine: OFF", HubState.SpeedPage, Theme.Surface)
HubState.BreakVelToggleBtn = createButton("Break Velocity (Spoof): OFF", HubState.SpeedPage, Color3.fromRGB(210, 235, 255))
HubState.MatchBaseBtn = createButton("Match Base Speed Spoof: ON", HubState.SpeedPage, Color3.fromRGB(210, 235, 255))

createSectionHeader("View Baseline", HubState.SpeedPage)
HubState.ViewBaselineFrame = Instance.new("Frame", HubState.SpeedPage)
HubState.ViewBaselineFrame.Size = UDim2.new(1, 0, 0, 70)
HubState.ViewBaselineFrame.BackgroundColor3 = Theme.Surface
HubState.ViewBaselineFrame.BackgroundTransparency = Theme.SurfaceTransparency
HubState.ViewBaselineFrame.BorderSizePixel = 0
HubState.viewBaseCorner = Instance.new("UICorner", HubState.ViewBaselineFrame)
HubState.viewBaseCorner.CornerRadius = UDim.new(0, Theme.RadiusCard)
HubState.viewBaseStroke = Instance.new("UIStroke", HubState.ViewBaselineFrame)
HubState.viewBaseStroke.Color = Theme.White
HubState.viewBaseStroke.Transparency = Theme.StrokeTransparency

HubState.ViewBaselineInfo = Instance.new("TextLabel", HubState.ViewBaselineFrame)
HubState.ViewBaselineInfo.Size = UDim2.new(0.56, -8, 0, 38)
HubState.ViewBaselineInfo.Position = UDim2.new(0, 10, 0, 5)
HubState.ViewBaselineInfo.BackgroundTransparency = 1
HubState.ViewBaselineInfo.Text = "Server WalkSpeed / Velocity Cap View\nCurrent: " .. tostring(HubState.ViewBaselineSpeed)
HubState.ViewBaselineInfo.TextColor3 = Theme.TextSecondary
HubState.ViewBaselineInfo.FontFace = ROBOTO_BOLD
HubState.ViewBaselineInfo.TextSize = 10
HubState.ViewBaselineInfo.TextXAlignment = Enum.TextXAlignment.Left
HubState.ViewBaselineInfo.TextYAlignment = Enum.TextYAlignment.Center

HubState.ViewBaselineBox = Instance.new("TextBox", HubState.ViewBaselineFrame)
HubState.ViewBaselineBox.Size = UDim2.new(0.28, 0, 0, 30)
HubState.ViewBaselineBox.Position = UDim2.new(0.59, 0, 0, 8)
HubState.ViewBaselineBox.BackgroundColor3 = Theme.Surface
HubState.ViewBaselineBox.BackgroundTransparency = Theme.SurfaceTransparency
HubState.ViewBaselineBox.Text = tostring(HubState.ViewBaselineSpeed)
HubState.ViewBaselineBox.PlaceholderText = "Speed"
HubState.ViewBaselineBox.TextColor3 = Theme.Text
HubState.ViewBaselineBox.FontFace = ROBOTO_BOLD
HubState.ViewBaselineBox.TextSize = 12
HubState.ViewBaselineBox.ClearTextOnFocus = false
Instance.new("UICorner", HubState.ViewBaselineBox).CornerRadius = UDim.new(0.5, 0)

HubState.ApplyViewBaselineBtn = createButton("Apply", HubState.ViewBaselineFrame, Theme.Surface)
HubState.ApplyViewBaselineBtn.Size = UDim2.new(0.12, 0, 0, 30)
HubState.ApplyViewBaselineBtn.Position = UDim2.new(0.87, 0, 0, 8)
HubState.ApplyViewBaselineBtn.TextSize = 10
HubState.ApplyViewBaselineStatus = HubState.ApplyViewBaselineBtn:FindFirstChild("StatusPill")
if HubState.ApplyViewBaselineStatus then HubState.ApplyViewBaselineStatus.Visible = false end

HubState.DisplayFrame = Instance.new("Frame", HubState.SpeedPage)
HubState.DisplayFrame.Size = UDim2.new(1, 0, 0, 110)
HubState.DisplayFrame.BackgroundColor3 = Theme.Surface
HubState.DisplayFrame.BackgroundTransparency = Theme.SurfaceTransparency
HubState.DisplayFrame.BorderSizePixel = 0
HubState.displayCorner = Instance.new("UICorner", HubState.DisplayFrame)
HubState.displayCorner.CornerRadius = UDim.new(0, Theme.RadiusCard)
HubState.dispStroke = Instance.new("UIStroke", HubState.DisplayFrame)
HubState.dispStroke.Color = Theme.White
HubState.dispStroke.Transparency = Theme.StrokeTransparency
HubState.dispStroke.Thickness = 1

HubState.ActualSpeedLabel = Instance.new("TextLabel", HubState.DisplayFrame)
HubState.ActualSpeedLabel.Size = UDim2.new(1, -12, 0, 18)
HubState.ActualSpeedLabel.Position = UDim2.new(0, 10, 0, 6)
HubState.ActualSpeedLabel.BackgroundTransparency = 1
HubState.ActualSpeedLabel.Text = "Real-Time WalkSpeed: 16"
HubState.ActualSpeedLabel.TextColor3 = Theme.Text
HubState.ActualSpeedLabel.FontFace = ROBOTO_BOLD
HubState.ActualSpeedLabel.TextSize = 11
HubState.ActualSpeedLabel.TextXAlignment = Enum.TextXAlignment.Left

HubState.VelocityLabel = Instance.new("TextLabel", HubState.DisplayFrame)
HubState.VelocityLabel.Size = UDim2.new(1, -12, 0, 18)
HubState.VelocityLabel.Position = UDim2.new(0, 10, 0, 26)
HubState.VelocityLabel.BackgroundTransparency = 1
HubState.VelocityLabel.Text = "Physical Velocity: 0.00 studs/s"
HubState.VelocityLabel.TextColor3 = Theme.TextSecondary
HubState.VelocityLabel.FontFace = ROBOTO_BOLD
HubState.VelocityLabel.TextSize = 11
HubState.VelocityLabel.TextXAlignment = Enum.TextXAlignment.Left

HubState.SpoofedVelLabel = Instance.new("TextLabel", HubState.DisplayFrame)
HubState.SpoofedVelLabel.Size = UDim2.new(1, -12, 0, 18)
HubState.SpoofedVelLabel.Position = UDim2.new(0, 10, 0, 46)
HubState.SpoofedVelLabel.BackgroundTransparency = 1
HubState.SpoofedVelLabel.Text = "Spoofed Velocity (Server View): OFF"
HubState.SpoofedVelLabel.TextColor3 = Theme.Text
HubState.SpoofedVelLabel.FontFace = ROBOTO_BOLD
HubState.SpoofedVelLabel.TextSize = 11
HubState.SpoofedVelLabel.TextXAlignment = Enum.TextXAlignment.Left

HubState.ServerSpeedLabel = Instance.new("TextLabel", HubState.DisplayFrame)
HubState.ServerSpeedLabel.Size = UDim2.new(1, -12, 0, 18)
HubState.ServerSpeedLabel.Position = UDim2.new(0, 10, 0, 66)
HubState.ServerSpeedLabel.BackgroundTransparency = 1
HubState.ServerSpeedLabel.Text = "Server View WalkSpeed: " .. tostring(HubState.ViewBaselineSpeed)
HubState.ServerSpeedLabel.TextColor3 = Theme.TextSecondary
HubState.ServerSpeedLabel.FontFace = ROBOTO_BOLD
HubState.ServerSpeedLabel.TextSize = 11
HubState.ServerSpeedLabel.TextXAlignment = Enum.TextXAlignment.Left

HubState.TargetSpeedLabel = Instance.new("TextLabel", HubState.DisplayFrame)
HubState.TargetSpeedLabel.Size = UDim2.new(1, -12, 0, 18)
HubState.TargetSpeedLabel.Position = UDim2.new(0, 10, 0, 86)
HubState.TargetSpeedLabel.BackgroundTransparency = 1
HubState.TargetSpeedLabel.Text = "Capped Target Speed: OFF"
HubState.TargetSpeedLabel.TextColor3 = Theme.Text
HubState.TargetSpeedLabel.FontFace = ROBOTO_BOLD
HubState.TargetSpeedLabel.TextSize = 11
HubState.TargetSpeedLabel.TextXAlignment = Enum.TextXAlignment.Left

createSectionHeader("Speed Values", HubState.SpeedPage)
HubState.AddedSpeedContainer = Instance.new("Frame", HubState.SpeedPage)
HubState.AddedSpeedContainer.Size = UDim2.new(1, 0, 0, 36)
HubState.AddedSpeedContainer.BackgroundTransparency = 1

HubState.AddedLabel = Instance.new("TextLabel", HubState.AddedSpeedContainer)
HubState.AddedLabel.Size = UDim2.new(0.6, 0, 1, 0)
HubState.AddedLabel.BackgroundTransparency = 1
HubState.AddedLabel.Text = "Added Speed Value:"
HubState.AddedLabel.TextColor3 = Theme.Text
HubState.AddedLabel.FontFace = ROBOTO_BOLD
HubState.AddedLabel.TextSize = 11
HubState.AddedLabel.TextXAlignment = Enum.TextXAlignment.Left

HubState.AddedBox = Instance.new("TextBox", HubState.AddedSpeedContainer)
HubState.AddedBox.Size = UDim2.new(0.38, 0, 1, 0)
HubState.AddedBox.Position = UDim2.new(0.62, 0, 0, 0)
HubState.AddedBox.BackgroundColor3 = Theme.Surface
HubState.AddedBox.BackgroundTransparency = Theme.SurfaceTransparency
HubState.AddedBox.Text = tostring(HubState.AddedSpeed)
HubState.AddedBox.TextColor3 = Theme.Text
HubState.AddedBox.FontFace = ROBOTO_BOLD
HubState.AddedBox.TextSize = 12
Instance.new("UICorner", HubState.AddedBox).CornerRadius = UDim.new(0.5, 0)

HubState.CapContainer = Instance.new("Frame", HubState.SpeedPage)
HubState.CapContainer.Size = UDim2.new(1, 0, 0, 36)
HubState.CapContainer.BackgroundTransparency = 1

HubState.CapLabel = Instance.new("TextLabel", HubState.CapContainer)
HubState.CapLabel.Size = UDim2.new(0.6, 0, 1, 0)
HubState.CapLabel.BackgroundTransparency = 1
HubState.CapLabel.Text = "Hard Speed Safety Cap:"
HubState.CapLabel.TextColor3 = Theme.Text
HubState.CapLabel.FontFace = ROBOTO_BOLD
HubState.CapLabel.TextSize = 11
HubState.CapLabel.TextXAlignment = Enum.TextXAlignment.Left

HubState.CapBox = Instance.new("TextBox", HubState.CapContainer)
HubState.CapBox.Size = UDim2.new(0.38, 0, 1, 0)
HubState.CapBox.Position = UDim2.new(0.62, 0, 0, 0)
HubState.CapBox.BackgroundColor3 = Theme.Surface
HubState.CapBox.BackgroundTransparency = Theme.SurfaceTransparency
HubState.CapBox.Text = tostring(HubState.SpeedCap)
HubState.CapBox.TextColor3 = Theme.Text
HubState.CapBox.FontFace = ROBOTO_BOLD
HubState.CapBox.TextSize = 12
Instance.new("UICorner", HubState.CapBox).CornerRadius = UDim.new(0.5, 0)

HubState.ApplySpeedBtn = createButton("Apply Speed Modifications", HubState.SpeedPage, Color3.fromRGB(210, 235, 255))
HubState.ApplySpeedStatus = HubState.ApplySpeedBtn:FindFirstChild("StatusPill")
if HubState.ApplySpeedStatus then HubState.ApplySpeedStatus.Visible = false end

local function applySpeedPhysics()
	local char = LocalPlayer.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	
	if HubState.SpeedEngineToggled then
		local rawTarget = HubState.OriginalSpeed + HubState.AddedSpeed
		local finalCappedSpeed = math.min(rawTarget, HubState.SpeedCap)
		hum.WalkSpeed = finalCappedSpeed
		HubState.TargetSpeedLabel.Text = "Capped Target Speed: " .. tostring(finalCappedSpeed)
	else
		hum.WalkSpeed = HubState.OriginalSpeed
		HubState.TargetSpeedLabel.Text = "Capped Target Speed: OFF"
	end
end

local function toggleSpeedEngine()
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	
	if not HubState.SpeedEngineToggled then
		if hum then HubState.OriginalSpeed = hum.WalkSpeed end
		HubState.SpeedEngineToggled = true
	else
		HubState.SpeedEngineToggled = false
	end
	
	HubState.SpeedToggleBtn.Text = "Speed Engine: " .. (HubState.SpeedEngineToggled and "ON" or "OFF")
	applySpeedPhysics()
end

HubState.SpeedToggleBtn.MouseButton1Click:Connect(toggleSpeedEngine)

HubState.BreakVelToggleBtn.MouseButton1Click:Connect(function()
	HubState.BreakVelocityToggled = not HubState.BreakVelocityToggled
	HubState.BreakVelToggleBtn.Text = "Break Velocity (Spoof): " .. (HubState.BreakVelocityToggled and "ON" or "OFF")
end)

HubState.MatchBaseBtn.MouseButton1Click:Connect(function()
	HubState.MatchBaseSpeedToggled = not HubState.MatchBaseSpeedToggled
	HubState.MatchBaseBtn.Text = "Match Base Speed Spoof: " .. (HubState.MatchBaseSpeedToggled and "ON" or "OFF (Static 0)")
end)

HubState.ApplySpeedBtn.MouseButton1Click:Connect(function()
	if not HubState.SpeedEngineToggled then return end
	local newAdded = tonumber(HubState.AddedBox.Text)
	local newCap = tonumber(HubState.CapBox.Text)
	if newAdded then HubState.AddedSpeed = newAdded end
	if newCap then HubState.SpeedCap = newCap end
	applySpeedPhysics()
end)

local function applyViewBaseline()
	local value = tonumber(HubState.ViewBaselineBox.Text)
	if not value then
		HubState.ViewBaselineBox.Text = tostring(HubState.ViewBaselineSpeed)
		return
	end

	value = math.clamp(value, 0, 1000)
	HubState.ViewBaselineSpeed = value
	HubState.ViewBaselineBox.Text = tostring(value)
	HubState.ViewBaselineInfo.Text = "Server WalkSpeed / Velocity Cap View\nCurrent: " .. tostring(value)
	HubState.ServerSpeedLabel.Text = "Server View WalkSpeed: " .. tostring(value)
end

HubState.ApplyViewBaselineBtn.MouseButton1Click:Connect(applyViewBaseline)
HubState.ViewBaselineBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then applyViewBaseline() end
end)

local rawMT = getrawmetatable and getrawmetatable(game)
if rawMT and setreadonly then
	setreadonly(rawMT, false)
	local oldIndex = rawMT.__index
	local oldNewIndex = rawMT.__newindex
	
	rawMT.__index = newcclosure(function(self, key)
		if not checkcaller() then
			if self:IsA("Humanoid") and key == "WalkSpeed" then
				if HubState.SpeedEngineToggled then return HubState.OriginalSpeed end
			elseif (key == "AssemblyLinearVelocity" or key == "Velocity") and self:IsA("BasePart") then
				if HubState.BreakVelocityToggled then
					if HubState.MatchBaseSpeedToggled then
						local realVel = oldIndex(self, key)
						if realVel.Magnitude > 0.1 then
							return realVel.Unit * math.min(realVel.Magnitude, HubState.OriginalSpeed)
						else
							return Vector3.new(0, 0, 0)
						end
					else
						return Vector3.new(0, 0, 0)
					end
				end
			end
		end
		return oldIndex(self, key)
	end)
	
	rawMT.__newindex = newcclosure(function(self, key, value)
		if not checkcaller() and self:IsA("Humanoid") and key == "WalkSpeed" then
			HubState.OriginalSpeed = value
			if HubState.SpeedEngineToggled then
				local capped = math.min(value + HubState.AddedSpeed, HubState.SpeedCap)
				return oldNewIndex(self, key, capped)
			end
		end
		return oldNewIndex(self, key, value)
	end)
	setreadonly(rawMT, true)
end

-- ==========================================
-- 🌌 SECTION 4: OTHERS TAB
-- ==========================================
createSectionHeader("Player", HubState.OthersPage)
HubState.ResetPlayerBtn = createButton("Reset Character", HubState.OthersPage, Theme.Surface)
HubState.ResetPlayerBtn.MouseButton1Click:Connect(function()
	playUISoundPair(ResetSFX1, ResetSFX2)
	local char = LocalPlayer.Character
	if not char then return end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local resetOk = false

	if humanoid then
		resetOk = pcall(function()
			humanoid.Health = 0
		end)
	end

	if not resetOk then
		pcall(function()
			char:BreakJoints()
		end)
	end
end)

-- 🔒 Shift Lock: same idea as Infinite Yield's "enableshiftlock". Roblox only lets players use Shift Lock
-- when the game allows it (Player.DevEnableMouseLock). This switches that permission on for this player;
-- the game's own camera script then does the rest, so Shift (or the mobile button) toggles the lock.
HubState.ShiftLockToggled = false
HubState.ShiftLockPrev = nil
HubState.ShiftLockConn = nil
HubState.ShiftLockBtn = createButton("Enable Shift Lock: OFF", HubState.OthersPage, Theme.Surface)

local function setShiftLockAllowed(state)
	-- pcall: the property is deprecated by Roblox, so a failure must never break the hub
	return pcall(function()
		LocalPlayer.DevEnableMouseLock = state
	end)
end

HubState.ShiftLockBtn.MouseButton1Click:Connect(function()
	if not HubState.ShiftLockToggled then
		local okRead, previous = pcall(function()
			return LocalPlayer.DevEnableMouseLock
		end)
		if not okRead then
			pcall(showNotification, "Shift Lock", "This game does not expose the Shift Lock setting.", 4)
			return
		end

		HubState.ShiftLockPrev = previous
		HubState.ShiftLockToggled = true
		setShiftLockAllowed(true)

		-- If the game switches the permission off again while this toggle is ON, switch it back on.
		HubState.ShiftLockConn = LocalPlayer:GetPropertyChangedSignal("DevEnableMouseLock"):Connect(function()
			if HubState.ShiftLockToggled and LocalPlayer.DevEnableMouseLock ~= true then
				setShiftLockAllowed(true)
			end
		end)

		pcall(showNotification, "Shift Lock", "Enabled. Press Shift to lock/unlock (on mobile, use the lock button if it appears).", 5)
	else
		HubState.ShiftLockToggled = false
		if HubState.ShiftLockConn then
			HubState.ShiftLockConn:Disconnect()
			HubState.ShiftLockConn = nil
		end
		setShiftLockAllowed(HubState.ShiftLockPrev == true)
	end

	HubState.ShiftLockBtn.Text = "Enable Shift Lock: " .. (HubState.ShiftLockToggled and "ON" or "OFF")
end)

createSectionHeader("Lighting", HubState.OthersPage)
HubState.LightToggleBtn = createButton("Infinite Yield Light: OFF", HubState.OthersPage, Theme.Surface)

createSlider("Light Range", HubState.LightRange, 4, 64, HubState.OthersPage, function(val)
	HubState.LightRange = val
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local pointLight = root and root:FindFirstChild("GeminiHub_PlayerLight")
	if pointLight then pointLight.Range = val end
end)

createSlider("Light Brightness", HubState.LightBrightness, 0.1, 10, HubState.OthersPage, function(val)
	HubState.LightBrightness = val
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local pointLight = root and root:FindFirstChild("GeminiHub_PlayerLight")
	if pointLight then pointLight.Brightness = val end
end)

create2DColorPicker("Light Color", HubState.LightColor, HubState.OthersPage, function(newColor)
	HubState.LightColor = newColor
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local pointLight = root and root:FindFirstChild("GeminiHub_PlayerLight")
	if pointLight then pointLight.Color = newColor end
end)

HubState.ShadowToggleBtn = createButton("Cast Shadows: OFF", HubState.OthersPage, Color3.fromRGB(210, 235, 255))
HubState.ShadowToggleBtn.MouseButton1Click:Connect(function()
	HubState.LightShadows = not HubState.LightShadows
	HubState.ShadowToggleBtn.Text = "Cast Shadows: " .. (HubState.LightShadows and "ON" or "OFF")
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local pointLight = root and root:FindFirstChild("GeminiHub_PlayerLight")
	if pointLight then pointLight.Shadows = HubState.LightShadows end
end)

local function updatePlayerLight()
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local existingLight = root:FindFirstChild("GeminiHub_PlayerLight")
	if existingLight then existingLight:Destroy() end

	if HubState.LightToggled then
		local pl = Instance.new("PointLight")
		pl.Name = "GeminiHub_PlayerLight"
		pl.Range = HubState.LightRange
		pl.Brightness = HubState.LightBrightness
		pl.Color = HubState.LightColor
		pl.Shadows = HubState.LightShadows
		pl.Parent = root
	end
end

HubState.LightToggleBtn.MouseButton1Click:Connect(function()
	HubState.LightToggled = not HubState.LightToggled
	HubState.LightToggleBtn.Text = "Infinite Yield Light: " .. (HubState.LightToggled and "ON" or "OFF")
	updatePlayerLight()
end)

createSectionHeader("Environment", HubState.OthersPage)
HubState.TimeOverrideBtn = createButton("Override Time of Day: OFF", HubState.OthersPage, Theme.Surface)
local timeLoopConnection

createSlider("Daytime Slider", HubState.DaytimeValue, 0, 24, HubState.OthersPage, function(val)
	HubState.DaytimeValue = val
end)

HubState.TimeOverrideBtn.MouseButton1Click:Connect(function()
	HubState.DaytimeToggled = not HubState.DaytimeToggled
	HubState.TimeOverrideBtn.Text = "Override Time of Day: " .. (HubState.DaytimeToggled and "ON" or "OFF")
	
	if HubState.DaytimeToggled then
		timeLoopConnection = RunService.RenderStepped:Connect(function()
			game.Lighting.ClockTime = HubState.DaytimeValue
		end)
	else
		if timeLoopConnection then 
			timeLoopConnection:Disconnect() 
			timeLoopConnection = nil
		end
	end
end)

createSlider("Tactical FOV", 70, 70, 120, HubState.OthersPage, function(val)
	Workspace.CurrentCamera.FieldOfView = val
end)

HubState.HoverToggleBtn = createButton("Hover Name ESP: OFF", HubState.OthersPage, Color3.fromRGB(210, 235, 255))
HubState.PlayerMouse = LocalPlayer:GetMouse()

-- Hover Name ESP uses the same lightweight SelectionBox-style outline approach
-- used by Infinite Yield's hovername ESP instead of a Highlight instance.
HubState.oldHoverOutline = safeParent:FindFirstChild("Gemini_Hover_Outline")
if HubState.oldHoverOutline then HubState.oldHoverOutline:Destroy() end

HubState.oldHoverName = safeParent:FindFirstChild("Gemini_Hover_Name")
if HubState.oldHoverName then HubState.oldHoverName:Destroy() end

HubState.HoverOutline = Instance.new("SelectionBox")
HubState.HoverOutline.Name = "Gemini_Hover_Outline"
HubState.HoverOutline.Color3 = Color3.fromRGB(255, 255, 255)
HubState.HoverOutline.SurfaceColor3 = Color3.fromRGB(255, 255, 255)
HubState.HoverOutline.SurfaceTransparency = 1
HubState.HoverOutline.Transparency = 0
HubState.HoverOutline.LineThickness = 0.03
HubState.HoverOutline.Adornee = nil
HubState.HoverOutline.Parent = safeParent

HubState.HoverBB = Instance.new("BillboardGui")
HubState.HoverBB.Name = "Gemini_Hover_Name"
HubState.HoverBB.Size = UDim2.new(0, 140, 0, 24)
HubState.HoverBB.StudsOffset = Vector3.new(0, 3.5, 0)
HubState.HoverBB.AlwaysOnTop = true

HubState.HoverText = Instance.new("TextLabel", HubState.HoverBB)
HubState.HoverText.Size = UDim2.new(1, 0, 1, 0)
HubState.HoverText.BackgroundTransparency = 1
HubState.HoverText.TextColor3 = Color3.fromRGB(255, 255, 255)
HubState.HoverText.FontFace = ROBOTO_BOLD
HubState.HoverText.TextSize = 14
HubState.HoverText.TextStrokeTransparency = 1
HubState.HoverText.TextXAlignment = Enum.TextXAlignment.Center

HubState.HoverToggleBtn.MouseButton1Click:Connect(function()
	HubState.HoverToggled = not HubState.HoverToggled
	HubState.HoverToggleBtn.Text = "Hover Name ESP: " .. (HubState.HoverToggled and "ON" or "OFF")
	
	if not HubState.HoverToggled then
		HubState.HoverOutline.Adornee = nil
		HubState.HoverBB.Parent = nil
	end
end)

RunService.RenderStepped:Connect(function()
	if HubState.HoverToggled then
		local target = HubState.PlayerMouse.Target
		if target and target.Parent then
			local model = target.Parent
			local hum = model:FindFirstChildOfClass("Humanoid")
			
			if hum then
				HubState.HoverOutline.Adornee = target
				HubState.HoverBB.Parent = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
				HubState.HoverText.Text = model.Name
			else
				HubState.HoverOutline.Adornee = nil
				HubState.HoverBB.Parent = nil
			end
		else
			HubState.HoverOutline.Adornee = nil
			HubState.HoverBB.Parent = nil
		end
	end
end)

LocalPlayer.CharacterAdded:Connect(function(newChar)
	task.spawn(function()
		newChar:WaitForChild("HumanoidRootPart", 5)
		local newHumanoid = newChar:FindFirstChildOfClass("Humanoid")
		if newHumanoid then
			HubState.OriginalSpeed = newHumanoid.WalkSpeed
			HubState.ViewBaselineSpeed = newHumanoid.WalkSpeed
			if HubState.ViewBaselineBox then HubState.ViewBaselineBox.Text = tostring(HubState.ViewBaselineSpeed) end
			if HubState.ViewBaselineInfo then HubState.ViewBaselineInfo.Text = "Server WalkSpeed / Velocity Cap View\nCurrent: " .. tostring(HubState.ViewBaselineSpeed) end
		end
		if HubState.LightToggled then updatePlayerLight() end
		if HubState.SpeedEngineToggled then applySpeedPhysics() end
	end)
end)

-- ==========================================
-- ⚙️ SECTION 5: SETTINGS & SECURE KEYBINDS
-- ==========================================
createSectionHeader("Keybinds", HubState.SettingsPage)
HubState.KeybindContainer = Instance.new("Frame", HubState.SettingsPage)
HubState.KeybindContainer.Size = UDim2.new(1, 0, 0, 36)
HubState.KeybindContainer.BackgroundTransparency = 1

HubState.KeybindText = Instance.new("TextLabel", HubState.KeybindContainer)
HubState.KeybindText.Size = UDim2.new(0.6, 0, 1, 0)
HubState.KeybindText.BackgroundTransparency = 1
HubState.KeybindText.Text = "Speed Toggle Keybind:"
HubState.KeybindText.TextColor3 = Theme.Text
HubState.KeybindText.FontFace = ROBOTO_BOLD
HubState.KeybindText.TextSize = 11
HubState.KeybindText.TextXAlignment = Enum.TextXAlignment.Left

HubState.KeybindBtn = Instance.new("TextButton", HubState.KeybindContainer)
HubState.KeybindBtn.Size = UDim2.new(0.38, 0, 1, 0)
HubState.KeybindBtn.Position = UDim2.new(0.62, 0, 0, 0)
HubState.KeybindBtn.BackgroundColor3 = Theme.Surface
HubState.KeybindBtn.BackgroundTransparency = Theme.SurfaceTransparency
HubState.KeybindBtn.BorderSizePixel = 0
HubState.KeybindBtn.Text = HubState.ToggleKeybind.Name
HubState.KeybindBtn.TextColor3 = Theme.Text
HubState.KeybindBtn.FontFace = ROBOTO_BOLD
HubState.KeybindBtn.TextSize = 11
Instance.new("UICorner", HubState.KeybindBtn).CornerRadius = UDim.new(0.5, 0)

HubState.KeybindBtn.MouseButton1Click:Connect(function()
	HubState.IsRebinding = true
	HubState.KeybindBtn.Text = "...Press Any Key..."
end)

getgenv().GeminiKeybindConn = UserInputService.InputBegan:Connect(function(input, gpe)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if HubState.IsRebinding then
		HubState.ToggleKeybind = input.KeyCode
		HubState.KeybindBtn.Text = input.KeyCode.Name
		HubState.IsRebinding = false
		return
	end

	if HubState.IsRebindingOpenMenu then
		HubState.OpenMenuKeybind = input.KeyCode
		HubState.OpenMenuBtn.Text = input.KeyCode.Name
		HubState.IsRebindingOpenMenu = false
		return
	end

	if gpe then return end

	if input.KeyCode == HubState.ToggleKeybind then
		local now = tick()
		if now - HubState.LastToggleTick > 0.2 then
			HubState.LastToggleTick = now
			toggleSpeedEngine()
		end
	elseif input.KeyCode == HubState.OpenMenuKeybind then
		MainFrame.Visible = not MainFrame.Visible
		if MainFrame.Visible then updateNotificationPosition() end
	end
end)

HubState.OpenMenuContainer = Instance.new("Frame", HubState.SettingsPage)
HubState.OpenMenuContainer.Size = UDim2.new(1, 0, 0, 36)
HubState.OpenMenuContainer.BackgroundTransparency = 1

HubState.OpenMenuText = Instance.new("TextLabel", HubState.OpenMenuContainer)
HubState.OpenMenuText.Size = UDim2.new(0.6, 0, 1, 0)
HubState.OpenMenuText.BackgroundTransparency = 1
HubState.OpenMenuText.Text = "Menu Toggle Keybind:"
HubState.OpenMenuText.TextColor3 = Theme.Text
HubState.OpenMenuText.FontFace = ROBOTO_BOLD
HubState.OpenMenuText.TextSize = 11
HubState.OpenMenuText.TextXAlignment = Enum.TextXAlignment.Left

HubState.OpenMenuBtn = Instance.new("TextButton", HubState.OpenMenuContainer)
HubState.OpenMenuBtn.Size = UDim2.new(0.38, 0, 1, 0)
HubState.OpenMenuBtn.Position = UDim2.new(0.62, 0, 0, 0)
HubState.OpenMenuBtn.BackgroundColor3 = Theme.Surface
HubState.OpenMenuBtn.BackgroundTransparency = Theme.SurfaceTransparency
HubState.OpenMenuBtn.BorderSizePixel = 0
HubState.OpenMenuBtn.Text = HubState.OpenMenuKeybind.Name
HubState.OpenMenuBtn.TextColor3 = Theme.Text
HubState.OpenMenuBtn.FontFace = ROBOTO_BOLD
HubState.OpenMenuBtn.TextSize = 11
HubState.OpenMenuBtn.AutoButtonColor = false
Instance.new("UICorner", HubState.OpenMenuBtn).CornerRadius = UDim.new(0.5, 0)

HubState.OpenMenuBtn.MouseButton1Click:Connect(function()
	HubState.IsRebindingOpenMenu = true
	HubState.OpenMenuBtn.Text = "...Press Any Key..."
end)

local function setMenuVisible(visible)
	if visible then
		MainFrame.Visible = true
		if minimized then
			-- Keep the user's minimized state if they explicitly chose it.
			return
		end
	else
		MainFrame.Visible = false
	end
end

createSectionHeader("Interface", HubState.SettingsPage)
HubState.UISoundToggleBtn = createButton("Interface Sounds: " .. (HubState.UISoundsEnabled and "ON" or "OFF"), HubState.SettingsPage, Theme.Surface)
HubState.UISoundToggleBtn.MouseButton1Click:Connect(function()
	HubState.UISoundsEnabled = not HubState.UISoundsEnabled
	HubState.UISoundToggleBtn.Text = "Interface Sounds: " .. (HubState.UISoundsEnabled and "ON" or "OFF")
	refreshStatusIndicator()
end)

HubState.StatusLabel = Instance.new("TextLabel")
HubState.StatusLabel.Size = UDim2.new(1, 0, 0, 64)
HubState.StatusLabel.BackgroundColor3 = Theme.Surface
HubState.StatusLabel.BackgroundTransparency = Theme.SurfaceTransparency
HubState.StatusLabel.BorderSizePixel = 0
HubState.StatusLabel.TextColor3 = Theme.Text
HubState.StatusLabel.FontFace = ROBOTO_MEDIUM
HubState.StatusLabel.TextSize = 9
HubState.StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
HubState.StatusLabel.TextYAlignment = Enum.TextYAlignment.Center
HubState.StatusLabel.TextWrapped = true
HubState.StatusLabel.Text = ""
HubState.StatusLabel.Parent = HubState.SettingsPage
Instance.new("UICorner", HubState.StatusLabel).CornerRadius = UDim.new(0.5, 0)
HubState.statusPad = Instance.new("UIPadding")
HubState.statusPad.PaddingLeft = UDim.new(0, 12)
HubState.statusPad.PaddingRight = UDim.new(0, 12)
HubState.statusPad.Parent = HubState.StatusLabel

local function refreshStatusIndicator()
	local waypointMode = WaypointPersistenceMode or "Unavailable"
	local warningMode = WarningPersistenceMode or "Unavailable"
	local npcState = HubState.NPCToggled and "ON" or "OFF"
	local playerState = HubState.PlayerToggled and "ON" or "OFF"
	HubState.StatusLabel.Text = "● Gemini Hub Ready\nUI Sounds: " .. (HubState.UISoundsEnabled and "ON" or "OFF") .. "  •  Waypoints: " .. waypointMode .. "  •  Warnings: " .. warningMode .. "\nNPC ESP: " .. npcState .. "  •  Player ESP: " .. playerState .. "  •  Client-side UI"
	HubState.StatusLabel.TextColor3 = Theme.Text
end
refreshStatusIndicator()

createSectionHeader("Maintenance", HubState.SettingsPage)
HubState.PurgeBtn = createButton("Reset & Purge All ESP Instances", HubState.SettingsPage, Theme.Surface)
HubState.PurgeBtn.MouseButton1Click:Connect(function()
	for _, v in pairs(Workspace:GetDescendants()) do
		if v:IsA("Highlight") and (v.Name == "NPC_HIGHLIGHT" or v.Name == "PLAYER_HIGHLIGHT" or v.Name == "Gemini_Hover_HL") then v:Destroy() end
		if v:IsA("SelectionBox") and v.Name == "Gemini_Hover_Outline" then v:Destroy() end
		if v:IsA("BillboardGui") and (string.find(v.Name, "NPC_HEALTH_BAR") or string.find(v.Name, "PLAYER_HEALTH_BAR") or v.Name == "Gemini_Hover_Name") then v:Destroy() end
	end
	print("All ESP Instances Successfully Purged!")
end)

-- Global Render Loop Monitor
RunService.Stepped:Connect(function()
	local char = LocalPlayer.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart")
		
		if hum then
			HubState.ActualSpeedLabel.Text = "Real-Time WalkSpeed: " .. tostring(math.floor(hum.WalkSpeed * 10) / 10)
			if HubState.SpeedEngineToggled then
				local target = math.min(HubState.OriginalSpeed + HubState.AddedSpeed, HubState.SpeedCap)
				if hum.WalkSpeed ~= target then hum.WalkSpeed = target end
			end
		end
		
		if root then
			local realVel = root.AssemblyLinearVelocity.Magnitude
			HubState.VelocityLabel.Text = string.format("Physical Velocity: %.2f studs/s", realVel)
			
			if HubState.BreakVelocityToggled then
				if HubState.MatchBaseSpeedToggled then
					local spoofedMag = math.min(realVel, HubState.ViewBaselineSpeed)
					HubState.SpoofedVelLabel.Text = string.format("Spoofed Vel: %.2f studs/s (View Cap %.1f)", spoofedMag, HubState.ViewBaselineSpeed)
				else
					HubState.SpoofedVelLabel.Text = "Spoofed Vel: 0.00 studs/s (Static Zero)"
				end
			else
				HubState.SpoofedVelLabel.Text = "Spoofed Velocity (Server View): OFF"
			end
		else
			HubState.VelocityLabel.Text = "Physical Velocity: 0.00 studs/s"
			HubState.SpoofedVelLabel.Text = "Spoofed Velocity (Server View): OFF"
		end
		
		HubState.ServerSpeedLabel.Text = "Server View WalkSpeed: " .. tostring(HubState.ViewBaselineSpeed)
	end
end)



-- ==========================================
-- 🫧 LIQUID GLASS HANDLER (embedded, Xeno port)
-- ==========================================
-- LiquidGlassHandler 1.0 by @7eoeb (scripting) and @UNIVERSECORNUCOPIA (idea/meshes).
-- Copyright (c) 2026 @7eoeb, @UNIVERSECORNUCOPIA. All rights reserved.
-- Original resource: https://devforum.roblox.com/t/4416219
--
-- This is the author's module, flattened into one function so an executor can run it
-- (no Explorer, no ModuleScripts, no `script` object). Everything the executor needs
-- that Studio did for free is marked [XENO PORT]. The rendering logic is the original.

local function buildLiquidGlass()
	local RunService = game:GetService("RunService")
	local CollectionService = game:GetService("CollectionService")
	local Players = game:GetService("Players")
	local GuiService = game:GetService("GuiService")
	local HttpService = game:GetService("HttpService")
	local AssetService = game:GetService("AssetService")

	-- ---------- Settings module (original values) ----------
	local Settings = {
		Highlight = {
			FillColor = Color3.fromRGB(0, 0, 0),
			OutlineTransparency = 1,
			FillTransparency = 0.9
		},
		Mesh = {
			Material = Enum.Material.Glass,
			Color = Color3.fromRGB(0, 0, 0),
			Transparency = 3,
			Anchored = true,
			CastShadow = false,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			AudioCanCollide = false
		},
		Tag = "LiquidGlass",
		Padding = 0.001,
		-- [XENO PORT] Nudge (in pixels) added to every glass position. If the glass sits a few
		-- pixels off from your UI, tweak this, e.g. Vector2.new(0, -58) or Vector2.new(0, 58).
		ExtraOffset = Vector2.new(0, 0),
	}

	-- ---------- VisibilityChecker module (original logic) ----------
	local VisibilityChecker = {}

	local function areAncestorsVisible(guiObject)
		local current = guiObject
		while current do
			if current:IsA("GuiObject") and not current.Visible then
				return false
			elseif current:IsA("ScreenGui") and not current.Enabled then
				return false
			end
			current = current.Parent
		end
		return true
	end

	function VisibilityChecker.isPotentiallyVisible(guiObject)
		if not guiObject or not guiObject.Parent then
			return false
		end
		return areAncestorsVisible(guiObject)
	end

	function VisibilityChecker.getAbsoluteTransparency(guiObject)
		local current = guiObject
		local combinedOpacity = 1

		while current do
			if current:IsA("CanvasGroup") then
				combinedOpacity = combinedOpacity * (1 - current.GroupTransparency)
			end
			current = current.Parent
		end

		return math.round((1 - combinedOpacity) * 1000) / 1000
	end

	function VisibilityChecker.getTrueRenderBounds(guiObject)
		local absPos = guiObject.AbsolutePosition
		local absSize = guiObject.AbsoluteSize
		local absRot = guiObject.AbsoluteRotation

		local minX, minY = absPos.X, absPos.Y
		local maxX, maxY = absPos.X + absSize.X, absPos.Y + absSize.Y

		if absRot == 0 then
			local current = guiObject.Parent
			while current and current:IsA("GuiObject") do
				if current.AbsoluteRotation ~= 0 then
					break
				end

				if current.ClipsDescendants then
					local cPos = current.AbsolutePosition
					local cSize = current.AbsoluteSize

					minX = math.max(minX, cPos.X)
					minY = math.max(minY, cPos.Y)
					maxX = math.min(maxX, cPos.X + cSize.X)
					maxY = math.min(maxY, cPos.Y + cSize.Y)
				end
				current = current.Parent
			end
		end

		local width = math.max(0, maxX - minX)
		local height = math.max(0, maxY - minY)

		return {
			Min = Vector2.new(minX, minY),
			Max = Vector2.new(maxX, maxY),
			Width = width,
			Height = height,
			IsFullyClipped = (width <= 0 or height <= 0)
		}
	end

	-- ---------- [XENO PORT] Template meshes ----------
	-- In Studio these 3 MeshParts sit inside the model (script.Overlay). A Lua file can't carry
	-- MeshParts, so they are rebuilt here from the same mesh asset IDs.
	local MESH_IDS = {
		Edge = 71901416013578,
		Corner = 87705720216841,
		Center = 124254578783606,
	}

	local function createMeshPart(assetId)
		local part = nil

		-- 1) Official API (newer Content signature)
		pcall(function()
			part = AssetService:CreateMeshPartAsync(Content.fromAssetId(assetId))
		end)
		-- 2) Official API (older string signature)
		if not part then
			pcall(function()
				part = AssetService:CreateMeshPartAsync("rbxassetid://" .. tostring(assetId))
			end)
		end
		-- 3) Executor fallback: write MeshId directly
		if not part then
			local p = Instance.new("MeshPart")
			local okSet = pcall(function()
				p.MeshId = "rbxassetid://" .. tostring(assetId)
			end)
			if okSet and p.MeshId ~= "" then
				part = p
			else
				p:Destroy()
			end
		end

		return part
	end

	local templates = {}
	for name, assetId in pairs(MESH_IDS) do
		local part = createMeshPart(assetId)
		if not part then
			error("Could not create the '" .. name .. "' glass mesh (asset " .. tostring(assetId) .. "). The asset may be unavailable.")
		end
		part.Name = name
		for key, value in pairs(Settings.Mesh) do
			pcall(function()
				part[key] = value
			end)
		end
		templates[name] = part
	end

	-- ---------- LiquidGlassHandler (original logic) ----------
	local LiquidGlassHandler = {}

	local tag = Settings.Tag
	local padding = Settings.Padding

	local parentFolder = Instance.new("Folder")
	parentFolder.Name = "LiquidGlassObjects"
	parentFolder.Parent = workspace

	local rotationOffset = CFrame.Angles(0, math.rad(-90), 0)

	-- [XENO PORT] bookkeeping so the whole handler can be torn down cleanly
	local active = {}
	local connections = {}

	-- [XENO PORT] The original only accepted UI inside the LocalPlayer (PlayerGui). An executor UI
	-- lives in gethui()/CoreGui, so those are accepted too.
	local function isOwnedGui(guiObject)
		if guiObject:IsDescendantOf(Players.LocalPlayer) then
			return true
		end
		local okCore, inCore = pcall(function()
			return guiObject:IsDescendantOf(game:GetService("CoreGui"))
		end)
		if okCore and inCore then
			return true
		end
		if type(gethui) == "function" then
			local okHui, host = pcall(gethui)
			if okHui and typeof(host) == "Instance" and guiObject:IsDescendantOf(host) then
				return true
			end
		end
		return false
	end

	local function createHighlight()
		local h = Instance.new("Highlight")
		for k, v in pairs(Settings.Highlight) do
			h[k] = v
		end
		return h
	end

	function LiquidGlassHandler.new(guiObject)
		if not guiObject or not guiObject:IsA("GuiObject") then return end
		if active[guiObject] then return active[guiObject] end -- [XENO PORT] never build two overlays for one object
		if not isOwnedGui(guiObject) then return end

		local renderName = "LiquidGlass_" .. HttpService:GenerateGUID(false)

		local container = Instance.new("Model")
		container.Name = renderName
		container.Parent = parentFolder

		local highlight = createHighlight()
		highlight.Parent = container

		local pixels = {}
		local lastSize = Vector2.zero
		local lastRadius = -1
		local currentLayoutMode = "None"
		local depth = 2

		local function getCornerRadius()
			local currentSize = guiObject.AbsoluteSize
			local uiCorner = guiObject:FindFirstChildWhichIsA("UICorner")
			local radius = uiCorner and (uiCorner.CornerRadius.Offset + (uiCorner.CornerRadius.Scale * math.min(currentSize.X, currentSize.Y))) or 0
			local maxPossibleRadius = math.min(currentSize.X, currentSize.Y) / 2
			radius = math.clamp(radius, 0, maxPossibleRadius)
			return radius
		end

		local function rebuildGrid()
			local currentSize = guiObject.AbsoluteSize
			if currentSize.X < 1 or currentSize.Y < 1 then return end

			local radius = getCornerRadius()

			if currentSize == lastSize and radius == lastRadius then return end
			lastSize = currentSize
			lastRadius = radius

			local targetMode = (radius <= 0) and "Flat" or "Rounded"
			local needsRebuild = (targetMode ~= currentLayoutMode)

			if needsRebuild then
				for _, data in pairs(pixels) do
					data.Part:Destroy()
				end
				table.clear(pixels)
				currentLayoutMode = targetMode
			end

			local partIndex = 1
			local function updateOrAddPart(templateName, relX, relY, relSizeX, relSizeY, localRot, swapAxes)
				if needsRebuild then
					local p = templates[templateName]:Clone() -- [XENO PORT] was script.Overlay:FindFirstChild(name)
					p.Parent = container
					table.insert(pixels, {
						Part = p,
						RelX = relX,
						RelY = relY,
						RelSizeX = relSizeX,
						RelSizeY = relSizeY,
						LocalRot = localRot or CFrame.new(),
						SwapAxes = swapAxes or false,
					})
				else
					local data = pixels[partIndex]
					data.RelX = relX
					data.RelY = relY
					data.RelSizeX = relSizeX
					data.RelSizeY = relSizeY
					data.LocalRot = localRot or CFrame.new()
					data.SwapAxes = swapAxes or false
				end
				partIndex += 1
			end

			if radius <= 0 then
				updateOrAddPart("Center", 0, 0, 1, 1)
			else
				local relRadX = radius / currentSize.X
				local relRadY = radius / currentSize.Y
				local innerW = (currentSize.X - 2 * radius) / currentSize.X
				local innerH = (currentSize.Y - 2 * radius) / currentSize.Y
				local diamX = relRadX
				local diamY = relRadY

				updateOrAddPart("Center", 0, 0, innerW, innerH)

				updateOrAddPart("Edge", 0, -0.5 + (relRadY / 2), innerW, relRadY, CFrame.Angles(0, 0, 0))
				updateOrAddPart("Edge", 0, 0.5 - (relRadY / 2), innerW, relRadY, CFrame.Angles(0, 0, math.rad(180)))

				updateOrAddPart("Edge", -0.5 + (relRadX / 2), 0, relRadX, innerH, CFrame.Angles(0, 0, math.rad(90)), true)
				updateOrAddPart("Edge", 0.5 - (relRadX / 2), 0, relRadX, innerH, CFrame.Angles(0, 0, math.rad(-90)), true)

				local halfDiamX = diamX / 2
				local halfDiamY = diamY / 2

				updateOrAddPart("Corner", -0.5 + halfDiamX, -0.5 + halfDiamY, diamX, diamY, CFrame.Angles(0, 0, math.rad(90)), true)
				updateOrAddPart("Corner", 0.5 - halfDiamX, -0.5 + halfDiamY, diamX, diamY, CFrame.Angles(0, 0, 0))
				updateOrAddPart("Corner", -0.5 + halfDiamX, 0.5 - halfDiamY, diamX, diamY, CFrame.Angles(0, 0, math.rad(180)))
				updateOrAddPart("Corner", 0.5 - halfDiamX, 0.5 - halfDiamY, diamX, diamY, CFrame.Angles(0, 0, math.rad(-90)), true)
			end
		end

		rebuildGrid()

		RunService:BindToRenderStep(renderName, Enum.RenderPriority.Camera.Value + 1, function()
			local camera = workspace.CurrentCamera
			if not camera then return end

			if guiObject.AbsoluteSize ~= lastSize or getCornerRadius() ~= lastRadius then
				rebuildGrid()
			end

			local isVisible = VisibilityChecker.isPotentiallyVisible(guiObject)
			container.Parent = isVisible and parentFolder or nil
			if not isVisible then return end

			local visibleRect = VisibilityChecker.getTrueRenderBounds(guiObject)
			local visibleSize = Vector2.new(visibleRect.Width, visibleRect.Height)

			if visibleSize.X <= 0 or visibleSize.Y <= 0 then
				container.Parent = nil
				return
			else
				container.Parent = parentFolder
			end

			local inset, _ = GuiService:GetGuiInset()
			local centerScreenPos = visibleRect.Min + (visibleSize / 2) + inset + Settings.ExtraOffset

			local function getPlanePos(pixelX, pixelY)
				local ray = camera:ViewportPointToRay(pixelX, pixelY)
				local dist = depth / ray.Direction:Dot(camera:GetRenderCFrame().LookVector)
				return ray.Origin + ray.Direction * dist
			end

			local centerWorldPos = getPlanePos(centerScreenPos.X, centerScreenPos.Y)
			local rightEdge = getPlanePos(centerScreenPos.X + (visibleSize.X / 2), centerScreenPos.Y)
			local leftEdge = getPlanePos(centerScreenPos.X - (visibleSize.X / 2), centerScreenPos.Y)
			local topEdge = getPlanePos(centerScreenPos.X, centerScreenPos.Y - (visibleSize.Y / 2))
			local bottomEdge = getPlanePos(centerScreenPos.X, centerScreenPos.Y + (visibleSize.Y / 2))

			local worldW = (rightEdge - leftEdge).Magnitude
			local worldH = (topEdge - bottomEdge).Magnitude

			local camCF = camera:GetRenderCFrame()
			local guiRotCF = CFrame.Angles(0, 0, math.rad(-guiObject.AbsoluteRotation))

			local absTransparency = VisibilityChecker.getAbsoluteTransparency(guiObject)

			for _, data in ipairs(pixels) do
				local localOffset = Vector3.new(data.RelX * worldW, -data.RelY * worldH, 0)
				local rotatedOffset = guiRotCF * localOffset

				local worldOffset = (camCF.RightVector * rotatedOffset.X) + (camCF.UpVector * rotatedOffset.Y)

				if data.SwapAxes then
					data.Part.Size = Vector3.new(0.01, data.RelSizeX * worldW + padding, data.RelSizeY * worldH + padding)
				else
					data.Part.Size = Vector3.new(0.01, data.RelSizeY * worldH + padding, data.RelSizeX * worldW + padding)
				end

				highlight.FillTransparency = Settings.Highlight.FillTransparency + (1 - Settings.Highlight.FillTransparency) * absTransparency
				data.Part.Transparency = Settings.Mesh.Transparency + (1 - Settings.Mesh.Transparency) * absTransparency

				data.Part.CFrame = CFrame.new(centerWorldPos + worldOffset) * camCF.Rotation * guiRotCF * data.LocalRot * rotationOffset
			end
		end)

		-- [XENO PORT] cleanup now also disconnects its own signals and guards against running twice
		local cleaned = false
		local ownConnections = {}
		local handle = {}

		local function cleanup()
			if cleaned then return 1 end
			cleaned = true
			active[guiObject] = nil
			for _, c in ipairs(ownConnections) do
				pcall(function() c:Disconnect() end)
			end
			table.clear(ownConnections)
			pcall(function() container:Destroy() end)
			pcall(function() RunService:UnbindFromRenderStep(renderName) end)
			return 1
		end

		handle.destroy = cleanup
		active[guiObject] = handle

		table.insert(ownConnections, guiObject.AncestryChanged:Connect(function(_, n)
			if n then return end
			cleanup()
		end))

		table.insert(ownConnections, CollectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
			if v ~= guiObject then return end
			cleanup()
		end))

		return handle
	end

	-- [XENO PORT] Tear everything down (used when the hub is executed again).
	function LiquidGlassHandler.Destroy()
		for _, c in ipairs(connections) do
			pcall(function() c:Disconnect() end)
		end
		table.clear(connections)
		for _, handle in pairs(active) do
			pcall(handle.destroy)
		end
		pcall(function() parentFolder:Destroy() end)
		for _, part in pairs(templates) do
			pcall(function() part:Destroy() end)
		end
	end

	table.insert(connections, CollectionService:GetInstanceAddedSignal(tag):Connect(LiquidGlassHandler.new))
	for _, v in ipairs(CollectionService:GetTagged(tag)) do
		LiquidGlassHandler.new(v)
	end

	-- Attribution print (the original prints this whenever it runs outside Studio).
	if not RunService:IsStudio() then
		print(game.Name .. " is using LiquidGlassHandler by @7eoeb and @UNIVERSECORNUCOPIA. Learn more on the Developer Forum at https://devforum.roblox.com/t/4416219")
	end

	return LiquidGlassHandler
end

-- ==========================================
-- 🫧 LIQUID GLASS LOADER
-- ==========================================
-- If anything goes wrong here (mesh assets unavailable, API missing...), the hub keeps working
-- exactly as before, just without the glass layer.
do
	local okGlass, glassOrErr = pcall(buildLiquidGlass)
	if okGlass and type(glassOrErr) == "table" then
		HubState.LiquidGlass = glassOrErr
		getgenv().GeminiLiquidGlass = glassOrErr
		-- The main window gets glass; the tab bar gets blur (see the UI Blur loader); notification cards are
		-- handled in showNotification.
		HubState.ApplyGlass(MainFrame)
		HubState.ApplyGlass(MinMaxBtn) -- the floating minimize circle gets the same glass as the window
	else
		warn("Gemini Hub Liquid Glass: could not start (" .. tostring(glassOrErr) .. "). The hub works normally without it.")
	end
end

-- ==========================================
-- 🧊 UI BLUR (embedded, Xeno port)
-- ==========================================
-- Objectual UI Blur [1.2 / REVISION 2] by Tavikron (Octav) / SomeFedoraGuy.
-- Original resource: https://devforum.roblox.com/t/3626057
-- Creator Store: https://create.roblox.com/store/asset/85845405321888
--
-- The author's module (UIBlur + Utilities), flattened into one function so an executor can run it
-- (no Explorer, no ModuleScripts, no `script` object). Changes for the executor are marked [XENO PORT].
--
-- How it works: a near-invisible Glass-material mesh is laid over a GuiObject and a DepthOfField
-- effect blurs what is behind it. Add a BlurEffect instance inside any GuiObject to blur it.
-- Optional attributes on that BlurEffect: Fragmented (bool), Inverted (bool), StrokeSize (number).
-- Setting the BlurEffect's Enabled to false switches that blur off.

-- ==========================================
-- ⚙️ UI BLUR SETTINGS  (edit the values below)
-- ==========================================
local UIBlurSettings = {
	-- Transparency of the blur meshes. Very close to 1 on purpose (0.98 is the author's value).
	Transparency = 0.98,

	-- Distance (studs) of the blur layer from the camera. Leave as is unless the blur looks wrong.
	Depth = 0.02,

	-- Defaults for BlurEffects that do not set these attributes themselves.
	DefaultFragmented = false,  -- true = little "sunlight" shimmer using displaced geometry
	DefaultInverted = false,    -- true = inverts the colours behind the frame (best on square frames)
	StrokeSize = 0,             -- grows the blur beyond the frame edge; 1 = same size as the frame

	-- The author's blur only works at Roblox graphics quality 8 or higher (Esc > Settings > Graphics).
	RequireQuality = true,
	MinQualityLevel = 8,
	-- "Automatic" graphics counts as quality 0, which the original would reject. true = allow it.
	AllowAutomaticQuality = true,

	-- [XENO PORT] The blur is a 3D mesh, so it cannot be cropped like UI is. true = a blur is
	-- hidden whenever its frame is not fully visible (scrolled partly out, window minimised...).
	HideWhenClipped = true,

	-- [XENO PORT] Pixel nudge added to every blur position. If blurs sit slightly off from their
	-- frames, try Vector2.new(0, 58) or Vector2.new(0, -58).
	ExtraOffset = Vector2.new(0, 0),
}

local function buildUIBlur()
	local RunService = game:GetService("RunService")
	local Lighting = game:GetService("Lighting")
	local GuiService = game:GetService("GuiService")
	local AssetService = game:GetService("AssetService")

	local Settings = UIBlurSettings
	local Camera = workspace.CurrentCamera
	local Offset = Settings.Depth

	-- [XENO PORT] bookkeeping so the whole module can be torn down cleanly
	local active = {}
	local connections = {}
	local Container = nil
	local InvertedInstances = 0
	local warned = {}

	local function warnOnce(message)
		message = tostring(message)
		if warned[message] then return end
		warned[message] = true
		warn("Gemini Hub UI Blur: " .. message)
	end

	-- [XENO PORT] Our own names ("GeminiUIBlur") so a game's own UIBlur objects are never touched.
	pcall(function()
		local old = Lighting:FindFirstChild("GeminiUIBlur")
		if old then old:Destroy() end
	end)
	pcall(function()
		local old = Camera and Camera:FindFirstChild("GeminiUIBlur")
		if old then old:Destroy() end
	end)

	local InvertedContainer = Instance.new("Model")
	InvertedContainer.Name = "Inverted"

	local DepthOfField = Instance.new("DepthOfFieldEffect")
	DepthOfField.Name = "GeminiUIBlur"
	DepthOfField.FarIntensity = 0
	DepthOfField.FocusDistance = 0
	DepthOfField.InFocusRadius = 0
	DepthOfField.NearIntensity = 1
	DepthOfField.Parent = Lighting

	-- [XENO PORT] PreRender is preferred, RenderStepped is the fallback on older clients.
	local renderEvent = RunService.RenderStepped
	pcall(function()
		if RunService.PreRender then
			renderEvent = RunService.PreRender
		end
	end)

	-- ---------- [XENO PORT] graphics quality (original: UserSettings().GameSettings) ----------
	local qualityPass = true
	local GameSettings = nil
	pcall(function()
		GameSettings = UserSettings().GameSettings
	end)

	local function refreshQuality()
		qualityPass = true
		if not Settings.RequireQuality or not GameSettings then return end
		local ok, level = pcall(function()
			return GameSettings.SavedQualityLevel.Value
		end)
		if not ok then return end
		if level == 0 then
			qualityPass = Settings.AllowAutomaticQuality
		else
			qualityPass = level >= Settings.MinQualityLevel
		end
	end
	refreshQuality()
	if GameSettings then
		pcall(function()
			table.insert(connections, GameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(refreshQuality))
		end)
	end

	table.insert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		Camera = workspace.CurrentCamera
		if Container and Camera then
			Container.Parent = Camera
		end
	end))

	-- ---------- [XENO PORT] template meshes ----------
	-- In Studio these 4 MeshParts sit inside the model (script.Normal / script.Fragmented).
	-- A Lua file can't carry MeshParts, so they are rebuilt from the same mesh asset IDs.
	local MESH_IDS = {
		Normal = { Corner = 99074379768397, Plane = 71290362392750 },
		Fragmented = { Corner = 116663952860129, Plane = 91153403946406 },
	}

	local function createMeshPart(assetId)
		local part = nil

		-- 1) Official API (newer Content signature)
		pcall(function()
			part = AssetService:CreateMeshPartAsync(Content.fromAssetId(assetId))
		end)
		-- 2) Official API (older string signature)
		if not part then
			pcall(function()
				part = AssetService:CreateMeshPartAsync("rbxassetid://" .. tostring(assetId))
			end)
		end
		-- 3) Executor fallback: write MeshId directly
		if not part then
			local p = Instance.new("MeshPart")
			local okSet = pcall(function()
				p.MeshId = "rbxassetid://" .. tostring(assetId)
			end)
			if okSet and p.MeshId ~= "" then
				part = p
			else
				p:Destroy()
			end
		end

		return part
	end

	local templates = { Normal = {}, Fragmented = {} }

	local function getTemplate(kind, name)
		local existing = templates[kind][name]
		if existing then return existing end

		local part = createMeshPart(MESH_IDS[kind][name])
		if not part then
			error("Could not create the " .. kind .. " '" .. name .. "' blur mesh (asset " .. tostring(MESH_IDS[kind][name]) .. "). The asset may be unavailable.")
		end
		part.Name = name
		local props = {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Reflectance = 0,
			Color = Color3.fromRGB(163, 162, 165),
		}
		for key, value in pairs(props) do
			pcall(function()
				part[key] = value
			end)
		end
		templates[kind][name] = part
		return part
	end

	local function cloneMesh(kind, name)
		local mesh = getTemplate(kind, name):Clone()
		mesh.Material = Enum.Material.Glass
		return mesh
	end

	-- The default (non-fragmented) meshes are needed right away; fragmented ones load on first use.
	getTemplate("Normal", "Plane")
	getTemplate("Normal", "Corner")

	-- ---------- Utilities module ----------
	local Utilities = {}

	-- [XENO PORT] Same projection the LiquidGlass layer uses in this hub (viewport ray + GUI inset),
	-- so blur and glass line up with the UI in exactly the same way.
	function Utilities.ProjectIn3D(camera, vector, depth)
		local inset = GuiService:GetGuiInset()
		local ray = camera:ViewportPointToRay(
			vector.X + inset.X + Settings.ExtraOffset.X,
			vector.Y + inset.Y + Settings.ExtraOffset.Y,
			depth
		)
		return ray.Origin + ray.Direction * depth
	end

	function Utilities.MapStrokeSize(stroke)
		return stroke * 0.2
	end

	-- [XENO PORT] Returns the corner DIAMETER in pixels (the original's convention). The original
	-- only read CornerRadius.Scale and ignored .Offset, so UICorners set in pixels (like this hub's)
	-- came out square. It also honours the object's own UIScale (the hub's hover animation).
	function Utilities.GetCornerRadius(uiCorner)
		local parent = uiCorner.Parent
		local size = parent.AbsoluteSize
		local minSide = math.min(size.X, size.Y)
		local cornerRadius = uiCorner.CornerRadius
		local scale = 1
		local uiScale = parent:FindFirstChildWhichIsA("UIScale")
		if uiScale then
			scale = uiScale.Scale
		end
		local radius = math.clamp(cornerRadius.Scale * minSide + cornerRadius.Offset * scale, 0, minSide / 2)
		return radius * 2
	end

	local function findScreenGui(object)
		local current = object.Parent
		for _ = 1, 100 do
			if not current or current == game then return nil end
			if current:IsA("ScreenGui") then
				return current
			end
			current = current.Parent
		end
		return nil
	end

	-- [XENO PORT] The original only checked the object's own .Visible. This also walks the ancestors
	-- (hidden tab pages, disabled ScreenGui) and, optionally, hides the blur while the frame is
	-- clipped, because a 3D mesh can't be cropped by a ScrollingFrame / ClipsDescendants.
	local function isShown(guiObject, screenGui)
		if not guiObject.Visible or not screenGui.Enabled then
			return false
		end

		local pos = guiObject.AbsolutePosition
		local size = guiObject.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			return false
		end

		local minX, minY = pos.X, pos.Y
		local maxX, maxY = pos.X + size.X, pos.Y + size.Y

		local current = guiObject.Parent
		while current and current ~= screenGui do
			if current:IsA("GuiObject") then
				if not current.Visible then
					return false
				end
				if Settings.HideWhenClipped and (current.ClipsDescendants or current:IsA("ScrollingFrame")) then
					local cPos = current.AbsolutePosition
					local cSize = current.AbsoluteSize
					if minX < cPos.X - 1 or minY < cPos.Y - 1 or maxX > cPos.X + cSize.X + 1 or maxY > cPos.Y + cSize.Y + 1 then
						return false
					end
				end
			end
			current = current.Parent
		end

		return true
	end

	local function getContainer()
		if not Container or not Container.Parent then
			Container = Instance.new("Folder")
			Container.Name = "GeminiUIBlur"
			Container.Parent = Camera
			InvertedContainer.Parent = Container
		end
		return Container
	end

	local function generateInverter()
		if not InvertedContainer:FindFirstChild("Inverter") then
			local highlight = Instance.new("Highlight")
			highlight.Name = "Inverter"
			highlight.Adornee = InvertedContainer
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.FillColor = Color3.new(0.5, 0.5, 0.5)
			highlight.FillTransparency = -1
			highlight.OutlineColor = Color3.new(0, 0, 0)
			highlight.OutlineTransparency = 1
			highlight.Parent = InvertedContainer
		end
	end

	-- ---------- UIBlur class (original logic) ----------
	local UIBlur = {}
	UIBlur.__index = UIBlur

	local function pick(value, default)
		if value == nil then
			return default
		end
		return value
	end

	function UIBlur.new(guiObject, arguments)
		if not guiObject or not guiObject:IsA("GuiObject") then return nil end
		if active[guiObject] then return active[guiObject] end -- [XENO PORT] never two blurs on one object

		local screenGui = findScreenGui(guiObject)
		if not screenGui then return nil end -- original: assert(...) must be inside a ScreenGui

		arguments = arguments or {}
		local args = {
			Fragmented = pick(arguments.Fragmented, Settings.DefaultFragmented) and true or false,
			Inverted = pick(arguments.Inverted, Settings.DefaultInverted) and true or false,
			StrokeSize = Utilities.MapStrokeSize(pick(arguments.StrokeSize, Settings.StrokeSize)),
		}
		local kind = args.Fragmented and "Fragmented" or "Normal"

		local self = setmetatable({}, UIBlur)
		self._GuiObject = guiObject
		self._Arguments = args
		self._Kind = kind
		self._Transparency = Settings.Transparency
		self._IsRendering = true
		self._Shown = nil
		self._UICorner = guiObject:FindFirstChildWhichIsA("UICorner")
		self._BlurEffect = guiObject:FindFirstChildWhichIsA("BlurEffect")
		self._ScreenGui = screenGui
		self._Connections = {}
		self._Planes = {}  -- up, right, down, left
		self._Corners = {} -- top left, top right, bottom right, bottom left
		self._MainPlane = cloneMesh(kind, "Plane")
		self._Model = Instance.new("Model")

		table.insert(self._Connections, guiObject.ChildAdded:Connect(function(object)
			if object:IsA("UICorner") then
				self._UICorner = object
				self:SetCornered(true) -- [XENO PORT] build the corner meshes if the UICorner shows up later
			end
		end))
		table.insert(self._Connections, guiObject.ChildRemoved:Connect(function(object)
			if object:IsA("UICorner") and object == self._UICorner then
				self._UICorner = nil
				self:SetCornered(false)
			end
		end))
		table.insert(self._Connections, renderEvent:Connect(function()
			-- [XENO PORT] a failing update disables only this blur instead of erroring every frame
			local ok, err = pcall(self._Update, self)
			if not ok then
				self._IsRendering = false
				warnOnce(err)
			end
		end))
		table.insert(self._Connections, guiObject.AncestryChanged:Connect(function(_, parent)
			if not parent then
				self:Destroy()
			end
		end))

		if args.Inverted then
			InvertedInstances += 1
			if InvertedInstances == 1 then
				generateInverter()
			end
		end

		self._MainPlane.Parent = self._Model
		self._Model.Name = guiObject.Name
		self._Model.PrimaryPart = self._MainPlane
		self:SetCornered(self._UICorner ~= nil)

		active[guiObject] = self
		return self
	end

	function UIBlur.SetCornered(self, cornered)
		if cornered then
			if #self._Planes > 0 then return end -- [XENO PORT] already built
			for _ = 1, 4 do
				local mesh = cloneMesh(self._Kind, "Plane")
				table.insert(self._Planes, mesh)
				mesh.Parent = self._Model
			end
			for _ = 1, 4 do
				local mesh = cloneMesh(self._Kind, "Corner")
				table.insert(self._Corners, mesh)
				mesh.Parent = self._Model
			end
		else
			for _, group in ipairs({ self._Planes, self._Corners }) do
				for _, mesh in ipairs(group) do
					mesh:Destroy()
				end
			end
			table.clear(self._Planes)
			table.clear(self._Corners)
		end
	end

	function UIBlur.SetStrokeSize(self, strokeSize)
		self._Arguments.StrokeSize = Utilities.MapStrokeSize(strokeSize)
	end

	function UIBlur.Destroy(self)
		if self._Destroyed then return end -- [XENO PORT] safe to call twice
		self._Destroyed = true
		active[self._GuiObject] = nil

		for _, connection in ipairs(self._Connections) do
			connection:Disconnect()
		end
		self._Model:Destroy()

		-- [XENO PORT] the original tested self._Inverted, which is never set, so the counter never dropped.
		if self._Arguments.Inverted then
			InvertedInstances -= 1
		end
		if InvertedInstances <= 0 then
			InvertedInstances = 0
			InvertedContainer:ClearAllChildren()
		end
	end

	function UIBlur._UpdateCorners(self, cornerOffset, size3D)
		cornerOffset /= 2
		for _, corner in ipairs(self._Corners) do
			corner.Size = Vector3.new(cornerOffset, cornerOffset)
			corner.PivotOffset = CFrame.new(cornerOffset / 2, cornerOffset / 2, 0)
		end

		local rightVector = self._MainPlane.CFrame.RightVector
		local upVector = self._MainPlane.CFrame.UpVector

		self._Corners[1]:PivotTo(self._MainPlane.CFrame + rightVector * size3D.X / 2 + upVector * size3D.Y / 2)
		self._Corners[2]:PivotTo((self._MainPlane.CFrame - rightVector * size3D.X / 2 + upVector * size3D.Y / 2) * CFrame.Angles(0, 0, math.pi / 2))
		self._Corners[3]:PivotTo((self._MainPlane.CFrame - rightVector * size3D.X / 2 - upVector * size3D.Y / 2) * CFrame.Angles(0, 0, math.pi))
		self._Corners[4]:PivotTo((self._MainPlane.CFrame + rightVector * size3D.X / 2 - upVector * size3D.Y / 2) * CFrame.Angles(0, 0, -math.pi / 2))
	end

	function UIBlur._UpdateSidePlanes(self, cornerOffset, size3D)
		local rightVector = self._MainPlane.CFrame.RightVector
		local upVector = self._MainPlane.CFrame.UpVector

		cornerOffset /= 2

		self._Planes[1].Size = Vector3.new(cornerOffset, size3D.Y - cornerOffset * 2)
		self._Planes[2].Size = Vector3.new(size3D.X - cornerOffset * 2, cornerOffset)
		self._Planes[3].Size = self._Planes[1].Size
		self._Planes[4].Size = self._Planes[2].Size

		self._Planes[1].CFrame = self._MainPlane.CFrame + rightVector * (size3D.X / 2 - cornerOffset / 2)
		self._Planes[2].CFrame = self._MainPlane.CFrame + upVector * (size3D.Y / 2 - cornerOffset / 2)
		self._Planes[3].CFrame = self._MainPlane.CFrame - rightVector * (size3D.X / 2 - cornerOffset / 2)
		self._Planes[4].CFrame = self._MainPlane.CFrame - upVector * (size3D.Y / 2 - cornerOffset / 2)
	end

	function UIBlur._Update(self)
		local guiObject = self._GuiObject
		local effect = self._BlurEffect
		if effect and not effect.Parent then
			effect = nil
			self._BlurEffect = nil
		end

		local wanted = self._IsRendering and qualityPass and Camera ~= nil and (not effect or effect.Enabled)
		local shown = wanted and isShown(guiObject, self._ScreenGui)

		-- [XENO PORT] hidden blurs are parked outside the workspace instead of being updated every frame
		if not shown then
			if self._Shown ~= false then
				self._Shown = false
				self._Model.Parent = nil
			end
			return
		end
		if self._Shown ~= true then
			self._Shown = true
			self._Model.Parent = self._Arguments.Inverted and InvertedContainer or getContainer()
		end

		local guiPos, guiSize = guiObject.AbsolutePosition, guiObject.AbsoluteSize
		local center = Utilities.ProjectIn3D(Camera, guiPos + guiSize / 2, Offset)
		local scaleFactor = (6.8 + self._Arguments.StrokeSize) * Offset * math.tan(math.rad(Camera.FieldOfView / 2)) * 2 / Camera.ViewportSize.Y

		self._MainPlane.Transparency = self._Transparency

		local planeCFrame = CFrame.new(center, center - Camera.CFrame.LookVector) * CFrame.Angles(0, 0, math.rad(guiObject.AbsoluteRotation))

		if not self._UICorner or #self._Corners ~= 4 then
			self._MainPlane.CFrame = planeCFrame
			self._MainPlane.Size = Vector3.new(guiSize.X * scaleFactor, guiSize.Y * scaleFactor)
		else
			local cornerOffset = Utilities.GetCornerRadius(self._UICorner) * scaleFactor
			local size3D = Vector2.new(guiSize.X * scaleFactor, guiSize.Y * scaleFactor)
			local mainPlaneSizes = {
				X = size3D.X - cornerOffset,
				Y = size3D.Y - cornerOffset,
			}

			self._MainPlane.CFrame = planeCFrame
			if mainPlaneSizes.X <= scaleFactor or mainPlaneSizes.Y <= scaleFactor then
				self._MainPlane.Transparency = 1
			else
				self._MainPlane.Size = Vector3.new(mainPlaneSizes.X, mainPlaneSizes.Y)
			end

			for _, group in ipairs({ self._Planes, self._Corners }) do
				for _, mesh in ipairs(group) do
					mesh.Transparency = self._Transparency
				end
			end

			self:_UpdateCorners(cornerOffset, size3D)
			self:_UpdateSidePlanes(cornerOffset, size3D)
		end
	end

	-- ---------- Objectual creation: BlurEffect inside a GuiObject ----------
	local function generateForBlurEffect(object)
		if object:IsA("BlurEffect") and object.Parent and object.Parent:IsA("GuiObject") then
			local ok, err = pcall(UIBlur.new, object.Parent, {
				Fragmented = object:GetAttribute("Fragmented"),
				Inverted = object:GetAttribute("Inverted"),
				StrokeSize = object:GetAttribute("StrokeSize"),
			})
			if not ok then
				warnOnce(err)
			end
		end
	end

	-- ---------- Public module ----------
	local Module = {}

	Module.new = UIBlur.new

	-- [XENO PORT] The original scanned Players.LocalPlayer.PlayerGui. An executor UI lives in
	-- gethui()/CoreGui, so the ScreenGui to watch is passed in instead.
	function Module.Watch(root)
		for _, object in ipairs(root:GetDescendants()) do
			generateForBlurEffect(object)
		end
		table.insert(connections, root.DescendantAdded:Connect(function(object)
			task.defer(generateForBlurEffect, object) -- deferred so attributes set after parenting are seen
		end))
	end

	-- [XENO PORT] Tear everything down (used when the hub is executed again).
	function Module.Destroy()
		for _, connection in ipairs(connections) do
			pcall(function() connection:Disconnect() end)
		end
		table.clear(connections)
		for _, blur in pairs(active) do
			pcall(function() blur:Destroy() end)
		end
		pcall(function() DepthOfField:Destroy() end)
		pcall(function() if Container then Container:Destroy() end end)
		pcall(function() InvertedContainer:Destroy() end)
		for _, group in pairs(templates) do
			for _, part in pairs(group) do
				pcall(function() part:Destroy() end)
			end
		end
	end

	return Module
end

-- ==========================================
-- 🧊 UI BLUR LOADER
-- ==========================================
-- If anything goes wrong here (mesh assets unavailable, API missing...), the hub keeps working
-- exactly as before, just without the blur layer.
do
	local BLUR_CARDS = true -- set to false to turn the blur off for the tab pages entirely

	local okBlur, blurOrErr = pcall(buildUIBlur)
	if okBlur and type(blurOrErr) == "table" then
		HubState.UIBlur = blurOrErr
		getgenv().GeminiUIBlur = blurOrErr

		-- Any GuiObject in the hub that contains a BlurEffect gets blurred (the module's "objectual" mode).
		blurOrErr.Watch(ScreenGui)

		-- The tab bar uses blur instead of glass (both modules use Glass material, so they cancel each other).
		HubState.ApplyBlur(TabBar)

		-- Which frames get a blur: the cards on every tab page (toggle rows, buttons, text box, color
		-- pickers...), meaning direct children of a page that have a visible background and rounded
		-- corners. MainFrame keeps the LiquidGlass look; the tab bar is blurred separately above.
		-- Edit this one function to choose different frames.
		local function isBlurCard(object)
			return object:IsA("GuiObject")
				and object.BackgroundTransparency < 0.99
				and object:FindFirstChildWhichIsA("UICorner") ~= nil
		end

		if BLUR_CARDS then
			for _, pageData in pairs(Containers) do
				local page = pageData.Page
				for _, child in ipairs(page:GetChildren()) do
					if isBlurCard(child) then
						HubState.ApplyBlur(child)
					end
				end
				-- controls added to a page later (for example new Pins entries) are covered too
				page.ChildAdded:Connect(function(child)
					task.defer(function()
						if isBlurCard(child) then
							HubState.ApplyBlur(child)
						end
					end)
				end)
			end
		end
	else
		warn("Gemini Hub UI Blur: could not start (" .. tostring(blurOrErr) .. "). The hub works normally without it.")
	end
end

-- Consistent typography: Roboto family, pure white, no text strokes.
-- Keep a little hierarchy: larger labels use Roboto Bold, ordinary labels use Regular,
-- clickable controls use Medium, and editable text uses Regular.
local function applyCleanTypography(instance)
	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		instance.TextStrokeTransparency = 1
		instance.TextStrokeColor3 = instance.TextColor3
		if instance:IsA("TextButton") then
			instance.FontFace = ROBOTO_MEDIUM
		elseif instance:IsA("TextBox") then
			instance.FontFace = ROBOTO_REGULAR
		elseif instance.TextSize >= 15 then
			instance.FontFace = ROBOTO_BOLD
		else
			instance.FontFace = ROBOTO_REGULAR
		end
	end
end
for _, descendant in ipairs(ScreenGui:GetDescendants()) do
	applyCleanTypography(descendant)
end
ScreenGui.DescendantAdded:Connect(function(descendant)
	applyCleanTypography(descendant)
end)

print("💎 Gemini Hub V14.5 Liquid Glass 3 UI (Xeno build + glass + blur layers) active ❄️💎")
