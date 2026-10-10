local _, DR = ...

-- Where in the dungeon the player is, as close as the game allows. Inside dungeons addons get no
-- position, but the game names the room the player is in (the subzone text, from its building
-- data). Data/Rooms.lua knows where these rooms lie on the floor maps; it is generated from the
-- game's own building files. Not every dungeon has named rooms, and between them nothing is known.

local Room = {}
DR.Room = Room

local current, currentKey -- room of Data/Rooms.lua the player is in, and its dungeon

-- The room of the current instance with this name: in the current wing, else in the one other
-- wing that has it. A name that several other wings share tells nothing.
local function roomNamed(text)
	if type(text) ~= "string" or text == "" or not DR.currentInstanceID then return nil end
	local found, foundKey, count = nil, nil, 0
	for _, dungeon in ipairs(DR:GetDungeonsForInstance(DR.currentInstanceID)) do
		for _, room in ipairs(DR.Rooms[dungeon.key] or {}) do
			if room.name == text or room.nameDE == text then
				if dungeon.key == DR.currentKey then return room, dungeon.key end
				found, foundKey, count = room, dungeon.key, count + 1
				break
			end
		end
	end
	if count == 1 then return found, foundKey end
	return nil
end

-- The room the player is in, while it belongs to the current dungeon.
function Room:Get()
	if current and currentKey == DR.currentKey then return current end
	return nil
end

function Room:OnFloor(room, floor)
	for _, box in ipairs(room.boxes) do
		if box[1] == floor then return true end
	end
	return false
end

-- The floor that shows most of the room.
function Room:MainFloor(room)
	local area, best, bestArea = {}, nil, nil
	for _, box in ipairs(room.boxes) do
		area[box[1]] = (area[box[1]] or 0) + box[4] * box[5]
	end
	for floor, a in pairs(area) do
		if not bestArea or a > bestArea or (a == bestArea and floor < best) then
			best, bestArea = floor, a
		end
	end
	return best
end

-- Middle of the room on a floor (weighted by the size of its parts), in map coordinates.
function Room:Center(room, floor)
	local su, sv, sum = 0, 0, 0
	for _, box in ipairs(room.boxes) do
		if box[1] == floor then
			local a = box[4] * box[5]
			su, sv, sum = su + box[2] * a, sv + box[3] * a, sum + a
		end
	end
	if sum == 0 then return nil end
	return su / sum, sv / sum
end

-- Reads the subzone. A room of another wing of the instance tells the wing.
function Room:Update()
	local room, key
	if DR.currentKey then
		room, key = roomNamed(DR.Safe(GetSubZoneText()))
	end
	if room and key ~= DR.currentKey then
		DR.currentKey = key
		DR.db.wings[DR.currentInstanceID] = key
		DR:Fire("DUNGEON_CHANGED", key)
	end
	if room ~= current or key ~= currentKey then
		current, currentKey = room, key
		DR:Fire("ROOM_CHANGED", room)
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ZONE_CHANGED_INDOORS")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event)
	if not DR.db then return end
	if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
		-- after Core has found the dungeon for the new zone
		C_Timer.After(0, function() Room:Update() end)
	else
		Room:Update()
	end
end)

DR:On("DUNGEON_CHANGED", function() Room:Update() end)
