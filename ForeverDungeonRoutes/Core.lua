local ADDON, DR = ...
_G.ForeverDungeonRoutes = DR

local L = DR.L

DR.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

local DB_DEFAULTS = {
	showOnMap = true,
	showPanel = true,
	panelCollapsed = false,
	showArrows = true,
	lineWidth = 4,
	active = {},        -- [dungeonKey] = routeId ("default" or a user route id)
	routes = {},        -- [dungeonKey] = { [routeId] = route }
	learnedFloors = {}, -- [uiMapID] = dungeonKey, for dungeons without a built-in entry
	nextRouteId = 1,
}

local CHAR_DEFAULTS = {
	progress = {},      -- [dungeonKey] = { routeId = id, done = { [stopIndex] = true }, time = epoch }
}

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

-- Simple callback list so map overlay, panel and editor stay in sync.
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
frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		ForeverDungeonRoutesDB = ForeverDungeonRoutesDB or {}
		ForeverDungeonRoutesCharDB = ForeverDungeonRoutesCharDB or {}
		applyDefaults(ForeverDungeonRoutesDB, DB_DEFAULTS)
		applyDefaults(ForeverDungeonRoutesCharDB, CHAR_DEFAULTS)
		DR.db = ForeverDungeonRoutesDB
		DR.cdb = ForeverDungeonRoutesCharDB
		DR:BuildIndex()
		DR:InitMapOverlay()
		DR:InitPanel()
		DR:InitEditor()
		frame:UnregisterEvent("ADDON_LOADED")
	elseif DR.db then
		DR:OnZoneChanged()
	end
end)

-- Called on login, reload and zone changes: remember which floors belong to the current
-- dungeon and start a fresh run when the last one is old.
function DR:OnZoneChanged()
	local inInstance, instanceType = IsInInstance()
	if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then
		return
	end
	local instanceID = select(8, GetInstanceInfo())
	local mapID = C_Map.GetBestMapForUnit("player")
	local key = DR:GetKeyForInstance(instanceID, mapID)
	if not key then return end
	if mapID and not DR:GetDungeonForMap(mapID) then
		DR.db.learnedFloors[mapID] = key
	end
	local progress = DR.cdb.progress[key]
	if progress and progress.time and (time() - progress.time) > DR.PROGRESS_MAX_AGE then
		DR.cdb.progress[key] = nil
		DR:Fire("PROGRESS_CHANGED", key)
	end
	DR.currentKey = key
	-- WoW Forever has no dungeon map art of its own. Without an addon that adds it, the
	-- world map never shows the dungeon floor, so say once where the routes went.
	if mapID and not DR.MapHasArt(mapID) and not DR.warnedNoArt then
		DR.warnedNoArt = true
		DR:Print(L["This dungeon has no map in the game. Install an addon with dungeon maps (for example MapUtils) to see the routes."])
	end
end

SLASH_FOREVERDUNGEONROUTES1 = "/fdr"
SLASH_FOREVERDUNGEONROUTES2 = "/foreverdungeonroutes"
SlashCmdList.FOREVERDUNGEONROUTES = function(input)
	local cmd = strtrim(input or ""):lower()
	if cmd == "" or cmd == "toggle" then
		DR.db.showOnMap = not DR.db.showOnMap
		DR:Print(DR.db.showOnMap and L["Routes on the map: on"] or L["Routes on the map: off"])
		DR:Fire("ROUTE_CHANGED")
	elseif cmd == "panel" then
		DR.db.showPanel = not DR.db.showPanel
		DR:Fire("ROUTE_CHANGED")
	elseif cmd == "reset" then
		local key = DR:GetShownKey()
		if key then
			DR:ResetProgress(key)
			DR:Print(L["Progress reset."])
		end
	elseif cmd == "map" then
		local mapID = C_Map.GetBestMapForUnit("player")
		local instanceID = select(8, GetInstanceInfo())
		DR:Print("uiMapID %s, instanceID %s, shown %s", tostring(mapID), tostring(instanceID),
			tostring(WorldMapFrame and WorldMapFrame:GetMapID()))
	else
		DR:Print(L["Commands: /fdr (map routes on/off), /fdr panel, /fdr reset, /fdr map"])
	end
end
