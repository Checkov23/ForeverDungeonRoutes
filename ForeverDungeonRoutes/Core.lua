local ADDON, DR = ...
_G.ForeverDungeonRoutes = DR

local L = DR.L

DR.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

local DB_DEFAULTS = {
	showArrows = true,
	showPlayer = true,  -- own position and group on the map, where the game reveals it
	showStops = true,   -- stop list beside the map
	autoOpen = false,   -- open the map when entering a dungeon
	autoCheck = true,   -- tick bosses off when the game reports the kill
	lineWidth = 4,
	alpha = 1,
	window = {},        -- point, relativePoint, x, y, width, height
	active = {},        -- [dungeonKey] = routeId ("default" or a user route id)
	routes = {},        -- [dungeonKey] = { [routeId] = route }
	wings = {},         -- [instanceID] = dungeonKey last seen, for instances with several wings
	nextRouteId = 1,
}

local CHAR_DEFAULTS = {
	progress = {},      -- [dungeonKey] = { routeId = id, done = { [stopIndex] = true }, time = epoch }
}

-- Settings of 0.3.0 that are gone since the addon draws its own map.
local OBSOLETE = { "showOnMap", "showPanel", "panelCollapsed", "learnedFloors" }

-- Progress older than this is considered a finished run and is cleared on the next visit.
DR.PROGRESS_MAX_AGE = 3 * 60 * 60

local function applyDefaults(target, defaults)
	for k, v in pairs(defaults) do
		if target[k] == nil then
			if type(v) == "table" then
				target[k] = {}
				applyDefaults(target[k], v)
			else
				target[k] = v
			end
		end
	end
end

function DR:Print(msg, ...)
	if select("#", ...) > 0 then
		msg = msg:format(...)
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cffc2a878" .. L["Forever Dungeon Routes"] .. ":|r " .. msg)
end

function DR.DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = DR.DeepCopy(v)
	end
	return copy
end

function DR.Clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

-- In restricted instances WoW: Forever (Midnight rules) returns secret values for unit and
-- instance data. They cannot be compared, used as table keys or turned into text, so every such
-- value goes through Safe() first and is treated as unknown when it is secret.
local issecret = issecretvalue or function() return false end

function DR.Safe(value)
	if issecret(value) then return nil end
	return value
end

function DR.CurrentInstance()
	local inInstance, instanceType = IsInInstance()
	inInstance, instanceType = DR.Safe(inInstance), DR.Safe(instanceType)
	local instanceID = DR.Safe((select(8, GetInstanceInfo())))
	return inInstance, instanceType, instanceID
end

-- Simple callback list so map, window and editor stay in sync.
local listeners = {}

function DR:On(event, fn)
	listeners[event] = listeners[event] or {}
	table.insert(listeners[event], fn)
end

function DR:Fire(event, ...)
	local list = listeners[event]
	if not list then return end
	for _, fn in ipairs(list) do
		local ok, err = pcall(fn, ...)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("BOSS_KILL")
frame:SetScript("OnEvent", function(_, event, arg1, arg2, _, _, arg5)
	if event == "ENCOUNTER_END" or event == "BOSS_KILL" then
		-- ENCOUNTER_END: encounterID, name, difficulty, group size, success (1 = kill)
		-- BOSS_KILL: encounterID, name
		if DR.db and (event == "BOSS_KILL" or DR.Safe(arg5) == 1) then
			DR:OnBossKilled(arg1, arg2)
		end
		return
	end
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		ForeverDungeonRoutesDB = ForeverDungeonRoutesDB or {}
		ForeverDungeonRoutesCharDB = ForeverDungeonRoutesCharDB or {}
		applyDefaults(ForeverDungeonRoutesDB, DB_DEFAULTS)
		applyDefaults(ForeverDungeonRoutesCharDB, CHAR_DEFAULTS)
		for _, key in ipairs(OBSOLETE) do
			ForeverDungeonRoutesDB[key] = nil
		end
		DR.db = ForeverDungeonRoutesDB
		DR.cdb = ForeverDungeonRoutesCharDB
		DR:BuildIndex()
		DR:InitEditor()
		frame:UnregisterEvent("ADDON_LOADED")
	elseif DR.db then
		DR:OnZoneChanged()
	end
end)

-- Called on login, reload and zone changes: find the dungeon the player is in, start a fresh run
-- when the last one is old, and open the map if wanted.
function DR:OnZoneChanged()
	local inInstance, instanceType, instanceID = DR.CurrentInstance()
	local key
	if inInstance and (instanceType == "party" or instanceType == "raid") then
		key = DR:FindCurrentDungeon(instanceID)
	end
	local previous = DR.currentKey
	DR.currentKey = key
	DR.currentInstanceID = key and DR:GetDungeon(key).instanceID or nil
	if key ~= previous then
		DR:Fire("DUNGEON_CHANGED", key)
	end
	if not key then return end
	local progress = DR.cdb.progress[key]
	if progress and progress.time and (time() - progress.time) > DR.PROGRESS_MAX_AGE then
		DR.cdb.progress[key] = nil
		DR:Fire("PROGRESS_CHANGED", key)
	end
	if key == previous then return end
	if DR.db.autoOpen then
		DR.Window:Open(key)
	elseif not DR.hinted and not DR.Window:IsShown() then
		DR.hinted = true
		DR:Print(L["Route map for %s: type /fdr or use the key binding."], DR:GetKeyName(key))
	end
end

-- A boss died: tick it off in the route, unless the setting is off or the game keeps it secret.
function DR:OnBossKilled(encounterID, encounterName)
	encounterID, encounterName = DR.Safe(encounterID), DR.Safe(encounterName)
	if not DR.db.autoCheck or type(encounterID) ~= "number" then return end
	if type(encounterName) ~= "string" then encounterName = nil end
	DR:MarkEncounterKilled(encounterID, encounterName)
end

function DR:ToggleWindow()
	DR.Window:Toggle()
end

SLASH_FOREVERDUNGEONROUTES1 = "/fdr"
SLASH_FOREVERDUNGEONROUTES2 = "/foreverdungeonroutes"
SlashCmdList.FOREVERDUNGEONROUTES = function(input)
	local cmd = strtrim(input or ""):lower()
	if cmd == "" or cmd == "toggle" then
		DR.Window:Toggle()
	elseif cmd == "reset" then
		local key = DR.Window:GetShownKey() or DR.currentKey
		if key then
			DR:ResetProgress(key)
			DR:Print(L["Progress reset."])
		end
	elseif cmd == "pos" then
		local _, _, instanceID = DR.CurrentInstance()
		local x, y, mapInstance = DR:GetUnitWorldPosition("player")
		local z = DR.Safe((select(3, UnitPosition("player"))))
		local key, floor, u, v = DR:LocatePlayer()
		DR:Print("instance %s/%s, world %s %s %s, dungeon %s, floor %s, map %s %s", tostring(instanceID),
			tostring(mapInstance), x and ("%.1f"):format(x) or "-", y and ("%.1f"):format(y) or "-",
			type(z) == "number" and ("%.1f"):format(z) or "-",
			tostring(key), tostring(floor), u and ("%.3f"):format(u) or "-", v and ("%.3f"):format(v) or "-")
	else
		DR:Print(L["Commands: /fdr (show or hide the map), /fdr reset (new run), /fdr pos (position check)"])
	end
end

-- Key binding (Bindings.xml) and the addon list beside the minimap.
BINDING_HEADER_FOREVERDUNGEONROUTES = L["Forever Dungeon Routes"]
BINDING_NAME_FOREVERDUNGEONROUTES_TOGGLE = L["Show or hide the route map"]

function ForeverDungeonRoutes_OnAddonCompartmentClick()
	DR.Window:Toggle()
end
