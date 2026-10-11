local _, DR = ...
local L = DR.L

-- Playing together: where the others in the group are (the room the game names for each of
-- them, as close as the game allows), checkmarks set by hand for the whole group, and a stop one
-- player shows to all. Addon messages to the group (prefix FDRGroup); during boss fights the
-- game holds them back until the fight is over.
--   P <key> <room>                   I am in this dungeon, in this room (English name; empty: none)
--   W                                where are you? (answered with P)
--   D <key> <stop> <0|1>             I ticked this stop by hand (English name of the stop)
--   S <key> <floor> <x> <y> <stop>   look at this stop

local PREFIX = "FDRGroup"
local SHOW_SECONDS = 30   -- how long a shown stop stays marked on the map
local STATE_GAP = 2       -- seconds between two room messages of the player
local ASK_GAP = 10        -- seconds between two "where are you?"

local Group = {}
DR.Group = Group

local members = {}        -- [player] = { key, room }
local shownStop           -- { key, floor, x, y, name, from, untilTime }
local lastState, lastStateTime, stateTimer = nil, 0, false
local lastAsk = 0

local function clean(s)
	return (tostring(s or ""):gsub("[\t\r\n|]", " ")):sub(1, 80)
end

local function send(text)
	local channel = DR.Share:Channel()
	if channel then
		DR.Share:Queue(PREFIX, channel, { text })
	end
end

-- Where the player is ---------------------------------------------------------------------------

local function myState()
	local key = DR.currentKey
	if not key then return "P\t\t" end
	local room = DR.Room:Get()
	return "P\t" .. key .. "\t" .. (room and clean(room.name) or "")
end

-- Tells the group the player's dungeon and room when they change (at most every STATE_GAP seconds).
local function sendState(force)
	if not DR.Share:Channel() then
		lastState = nil
		return
	end
	local state = myState()
	if not force and state == lastState then return end
	local wait = STATE_GAP - (time() - lastStateTime)
	if not force and wait > 0 then
		if not stateTimer then
			stateTimer = true
			C_Timer.After(wait, function()
				stateTimer = false
				sendState()
			end)
		end
		return
	end
	lastState, lastStateTime = state, time()
	send(state)
end

-- Rooms of the others on a floor: { { room, names = { name, ... } }, ... }.
function Group:RoomsOn(key, floor)
	local out, byRoom = {}, {}
	for player, m in pairs(members) do
		if m.key == key and m.room then
			for _, room in ipairs(DR.Rooms[key] or {}) do
				if room.name == m.room then
					if DR.Room:OnFloor(room, floor) then
						local entry = byRoom[room]
						if not entry then
							entry = { room = room, names = {} }
							byRoom[room] = entry
							out[#out + 1] = entry
						end
						table.insert(entry.names, DR.Share.SenderName(player))
					end
					break
				end
			end
		end
	end
	for _, entry in ipairs(out) do
		table.sort(entry.names)
	end
	return out
end

-- Group members in a dungeon (for the tooltip of the map): { name = room or false }.
function Group:Members(key)
	local out = {}
	for player, m in pairs(members) do
		if m.key == key then out[DR.Share.SenderName(player)] = m.room or false end
	end
	return out
end

-- Checkmarks ------------------------------------------------------------------------------------

DR:On("STOP_DONE_BY_HAND", function(key, route, index, done)
	local stop = route and route.stops[index]
	if stop and stop.name and stop.name ~= "" then
		send(table.concat({ "D", key, clean(stop.name), done and "1" or "0" }, "\t"))
	end
end)

local function applyTick(key, name, done)
	local route = DR:GetDungeon(key or "") and DR:GetActiveRoute(key)
	if not route or not name or name == "" then return end
	for i, stop in ipairs(route.stops) do
		if stop.name == name and DR:IsStopDone(key, route, i) ~= done then
			DR:SetStopDone(key, route, i, done)
		end
	end
end

-- Showing a stop --------------------------------------------------------------------------------

function Group:GetShownStop()
	if shownStop and time() <= shownStop.untilTime then return shownStop end
	return nil
end

local function show(from, key, floor, x, y, name)
	shownStop = { key = key, floor = floor, x = x, y = y, name = name, from = from, untilTime = time() + SHOW_SECONDS }
	if from then
		local where = DR.Floors[floor] and DR:GetFloorName(floor)
		DR:Print(L["%s shows: %s"], DR.Share.SenderName(from), name .. (where and (" (" .. DR:GetKeyName(key) .. ", " .. where .. ")") or ""))
	end
	DR:Fire("GROUP_STOP_SHOWN", key, floor)
	C_Timer.After(SHOW_SECONDS + 1, function() DR:Fire("GROUP_STOP_SHOWN", key, floor) end)
end

-- Shows a stop of the route to the group (and on the own map).
function Group:ShowStop(key, route, index)
	local stop = route and route.stops[index]
	if not stop or not stop.floor or not stop.x then return end
	if not DR.Share:Channel() then
		DR:Print(L["You are not in a group."])
		return
	end
	local name = clean(DR:GetStopName(stop))
	send(table.concat({ "S", key, tostring(stop.floor), ("%.4f"):format(stop.x), ("%.4f"):format(stop.y), name }, "\t"))
	show(nil, key, stop.floor, stop.x, stop.y, name)
	DR:Print(L["Shown to the group: %s"], name)
end

-- Messages ----------------------------------------------------------------------------------------

function Group:OnMessage(prefix, text, channel, sender)
	prefix, text, sender = DR.Safe(prefix), DR.Safe(text), DR.Safe(sender)
	if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" or DR.Share.IsMe(sender) then
		return
	end
	local f = {}
	for field in (text .. "\t"):gmatch("([^\t]*)\t") do
		f[#f + 1] = field
	end
	if f[1] == "P" then
		if f[2] and f[2] ~= "" and DR:GetDungeon(f[2]) then
			members[sender] = { key = f[2], room = f[3] ~= "" and f[3] or nil }
		else
			members[sender] = nil
		end
		DR:Fire("GROUP_ROOMS_CHANGED")
	elseif f[1] == "W" then
		sendState(true)
	elseif f[1] == "D" then
		applyTick(f[2], f[3], f[4] == "1")
	elseif f[1] == "S" then
		local floor, x, y = tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
		if DR:GetDungeon(f[2] or "") and floor and DR.Floors[floor] and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
			show(sender, f[2], floor, x, y, clean(f[6] ~= "" and f[6] or "?"))
		end
	end
end

-- The group changed: start over and ask where everyone is.
local function rosterChanged()
	if not DR.Share:Channel() then
		if next(members) then
			members = {}
			DR:Fire("GROUP_ROOMS_CHANGED")
		end
		lastState = nil
		return
	end
	if time() - lastAsk >= ASK_GAP then
		lastAsk = time()
		members = {}
		DR:Fire("GROUP_ROOMS_CHANGED")
		send("W")
		sendState(true)
	end
end

DR:On("ROOM_CHANGED", function() sendState() end)
DR:On("DUNGEON_CHANGED", function() sendState() end)

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_ADDON" then
		Group:OnMessage(...)
	else
		rosterChanged()
	end
end)
