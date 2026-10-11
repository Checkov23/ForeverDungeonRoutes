local _, DR = ...
local L = DR.L

-- A small display of the run inside a dungeon, for when the map stays closed: dungeon and bosses
-- down, run time, the next boss and the room the game names. Optional (gear button), movable by
-- dragging; a click opens the map.

local Tracker = {}
DR.Tracker = Tracker

local WIDTH, LINE = 230, 13
local frame
local ticker = 0

local function savePosition()
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	local t = DR.db.tracker
	t.point, t.relativePoint, t.x, t.y = point, relativePoint, x, y
end

local function line(font, y)
	local text = frame:CreateFontString(nil, "OVERLAY", font)
	text:SetPoint("TOPLEFT", 8, y)
	text:SetPoint("TOPRIGHT", -8, y)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	return text
end

local function build()
	frame = CreateFrame("Button", "ForeverDungeonRoutesTracker", UIParent, "BackdropTemplate")
	DR.StyleBox(frame, 0.85)
	frame:SetSize(WIDTH, 16 + 3 * LINE)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:RegisterForClicks("LeftButtonUp")
	local t = DR.db.tracker
	if t.point then
		frame:SetPoint(t.point, UIParent, t.relativePoint or t.point, t.x or 0, t.y or 0)
	else
		frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -260)
	end
	frame.Title = line("GameFontNormalSmall", -7)
	frame.Count = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.Count:SetPoint("TOPRIGHT", -8, -7)
	frame.Count:SetJustifyH("RIGHT")
	frame.Title:SetPoint("TOPRIGHT", frame.Count, "TOPLEFT", -6, 0)
	frame.Next = line("GameFontHighlightSmall", -7 - LINE)
	frame.Room = line("GameFontHighlightSmall", -7 - 2 * LINE)
	DR.ThemeText(frame.Title, "title")
	DR.ThemeText(frame.Count, "text")
	DR.ThemeText(frame.Next, "text")
	DR.ThemeText(frame.Room, "accent")

	frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePosition()
	end)
	frame:SetScript("OnClick", function() DR.Window:Open(DR.currentKey) end)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(L["Forever Dungeon Routes"], 1, 1, 1)
		GameTooltip:AddLine(L["Click: open the map\nDrag: move"], 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	-- the run time counts up while the display is shown
	frame:SetScript("OnUpdate", function(_, elapsed)
		ticker = ticker + elapsed
		if ticker >= 1 then
			ticker = 0
			Tracker:UpdateTime()
		end
	end)
end

local function bossCount(key, route)
	local done, total = 0, 0
	for i, stop in ipairs(route.stops) do
		if stop.kind == "boss" then
			total = total + 1
			if DR:IsStopDone(key, route, i) then done = done + 1 end
		end
	end
	return done, total
end

function Tracker:UpdateTime()
	if not frame or not frame:IsShown() then return end
	local key = DR.currentKey
	local route = key and DR:GetActiveRoute(key)
	if not route then return end
	local done, total = bossCount(key, route)
	local text = done .. "/" .. total
	local started, finished = DR:GetRunTimes(key)
	if started then
		text = text .. "  " .. DR.FormatDuration((finished or time()) - started)
	end
	frame.Count:SetText(text)
end

function Tracker:Update()
	local key = DR.currentKey
	local route = key and DR:GetActiveRoute(key)
	if not DR.db.showTracker or not route then
		if frame then frame:Hide() end
		return
	end
	if not frame then build() end
	frame.Title:SetText(DR:GetKeyName(key))
	local index = DR:GetNextStopIndex(key, route)
	local nextStop = index and route.stops[index]
	local nextRoom = nextStop and nextStop.floor and DR.Room:At(key, nextStop.floor, nextStop.x, nextStop.y)
	if nextRoom then
		frame.Next:SetText(L["Next: %s (%s)"]:format(DR:GetStopName(nextStop), DR.LocText(nextRoom, "name")))
	else
		frame.Next:SetText(nextStop and L["Next: %s"]:format(DR:GetStopName(nextStop)) or L["All bosses down"])
	end
	local room = DR.Room:Get()
	frame.Room:SetText(room and L["Room: %s"]:format(DR.LocText(room, "name")) or "")
	frame.Room:SetShown(room ~= nil)
	frame:SetHeight(16 + (room and 3 or 2) * LINE)
	frame:Show()
	self:UpdateTime()
end

local function update() Tracker:Update() end
DR:On("DUNGEON_CHANGED", update)
DR:On("PROGRESS_CHANGED", update)
DR:On("ROUTE_CHANGED", update)
DR:On("ROOM_CHANGED", update)
DR:On("SETTINGS_CHANGED", update)
