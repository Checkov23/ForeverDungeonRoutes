local _, DR = ...
local L = DR.L

-- The way to a dungeon: a map pin on the zone map at its entrance (Data/Entrances.lua), tracked by
-- the game like any waypoint, so the arrow on the screen leads there.

function DR:GetEntrance(key)
	return key and self.Entrances[key] or nil
end

-- Name of the entrance's zone in the language of the game client.
function DR:GetEntranceZone(key)
	local entrance = self:GetEntrance(key)
	local info = entrance and C_Map.GetMapInfo(entrance.map)
	return info and DR.Safe(info.name) or nil
end

function DR:SetEntranceWaypoint(key)
	local entrance = self:GetEntrance(key)
	if not entrance then return false end
	if not DR.Safe(C_Map.CanSetUserWaypointOnMap(entrance.map)) then
		DR:Print(L["The game allows no waypoint on this map."])
		return false
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(entrance.map, entrance.x, entrance.y))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	DR:Print(L["Waypoint to %s set: %s %.1f, %.1f"], DR:GetKeyName(key), DR:GetEntranceZone(key) or "",
		entrance.x * 100, entrance.y * 100)
	return true
end
