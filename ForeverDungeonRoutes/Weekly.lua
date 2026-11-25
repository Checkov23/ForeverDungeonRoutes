local _, DR = ...
local L = DR.L

-- The weekly quest of Pix Xizzix in Booty Bay (level 60, "In Demand"): three quest items from three dungeons, another
-- set each week. A very small display on the screen (since 1.3.14) shows which quest it is, whether the player has
-- accepted it and which of the three items are in the bags. Dragging moves it; the X hides it until the next week, a
-- right-click on the X or the gear button switches it off.
--
-- Accepted comes from the quest log, the items from the bags, "done" from the game's flag for finished quests (in the
-- client's table QuestV2 the four quests share one flag, the lock for the week). Which quest it is before the player has
-- it only the quest window in Booty Bay tells: seen there once, it is known to all characters of the account until the
-- week is over; before that the display says "?".

local Weekly = {}
DR.Weekly = Weekly

local LEVEL = 60
local PAD, LINE, MARK, GAP = 6, 13, 9, 4
local MAX_TEXT = 240 -- wider texts are cut off
local MEDIA = "Interface\\AddOns\\ForeverDungeonRoutes\\media\\"
local GOLD, WHITE, DIM = { 1, 0.82, 0 }, { 1, 1, 1 }, { 0.75, 0.75, 0.75 }
local GREEN, ORANGE = { 0.45, 0.9, 0.45 }, { 1, 0.55, 0.25 }

-- The quests of the client (1.60.1.71091): a title until the game names the quest in the player's language, and for
-- each item the dungeon and the boss that drops it (English name as in Data/Encounters.lua).
local QUESTS = {
	[96075] = { title = "Blackrock Legal Records",
		{ item = 272017, key = "upperblackrock", boss = "General Drakkisath" },
		{ item = 272018, key = "lowerblackrock", boss = "Overlord Wyrmthalak" },
		{ item = 272019, key = "blackrockdepths", boss = "Emperor Dagran Thaurissan" } },
	[96076] = { title = "Ancient Elven Curiosities",
		{ item = 272020, key = "diremaul_east", boss = "Alzzin the Wildshaper" },
		{ item = 272021, key = "diremaul_west", boss = "Prince Tortheldrin" },
		{ item = 272022, key = "diremaul_north", boss = "King Gordok" } },
	[96087] = { title = "Plague Records",
		{ item = 272023, key = "scholomance", boss = "Darkmaster Gandling" },
		{ item = 272024, key = "stratholme", boss = "Baron Rivendare" },
		{ item = 272025, key = "stratholme", boss = "Balnazzar" } },
	[96088] = { title = "Titan Relics",
		{ item = 272026, key = "sunkentemple", boss = "Shade of Eranikus" },
		{ item = 272027, key = "blackmawhold", boss = "Varrox Bleakhoof" },
		{ item = 272028, key = "shapersterrace", boss = "Nanaya" } },
}
Weekly.QUESTS = QUESTS

local IDS = {}
for id in pairs(QUESTS) do IDS[#IDS + 1] = id end
table.sort(IDS)

local frame
local logThere = false  -- after login the quest log comes a moment later: until then nothing is known
local tooLow = true     -- until the game has told that the character is level 60
local asked = {}        -- [questID or itemID] = true: name asked for at the game, once

-- What the game tells -----------------------------------------------------------------------------

local function call(fn, ...)
	if not fn then return nil end
	return DR.Safe((fn(...)))
end

-- Start of the running week (the weekly reset) as the game counts it; nil where it does not tell.
local function thisWeek()
	local start = C_DateAndTime and call(C_DateAndTime.GetWeeklyResetStartTime)
	return type(start) == "number" and start > 0 and start or nil
end

-- This week's quest, for all characters of the account.
local function remember(id)
	local week = thisWeek()
	if QUESTS[id] and week then
		DR.db.weekly = { week = week, quest = id }
	end
end

-- Quests offered by a quest giver: one of the pool among them is this week's.
local function learn(ids)
	local found
	for _, id in ipairs(ids) do
		if QUESTS[id] then
			if found and found ~= id then return end
			found = id
		end
	end
	remember(found)
end

local function offeredIn(event)
	local ids = {}
	if event == "QUEST_DETAIL" then
		ids[1] = call(GetQuestID)
	elseif event == "QUEST_GREETING" then
		for i = 1, call(GetNumAvailableQuests) or 0 do
			ids[#ids + 1] = DR.Safe((select(5, GetAvailableQuestInfo(i))))
		end
	elseif C_GossipInfo then
		for _, info in ipairs(call(C_GossipInfo.GetAvailableQuests) or {}) do
			ids[#ids + 1] = DR.Safe(info.questID)
		end
	end
	return ids
end

-- The quest of this week as far as the addon knows it (nil: not known), whether the player has it in the quest log,
-- and whether it is done for this week. The log alone is not kept for the other characters: right after the weekly
-- reset it may still hold the quest of the week before.
local function current()
	local week, known = thisWeek(), DR.db.weekly
	local id = week and known.week == week and known.quest or nil
	if QUESTS[id] and call(C_QuestLog.IsOnQuest, id) == true then return id, true, false end
	for _, other in ipairs(IDS) do
		if call(C_QuestLog.IsOnQuest, other) == true then return other, true, false end
	end
	local mine = DR.cdb.weeklyDone
	if mine and week and mine.week == week then return mine.quest, false, true end
	for _, other in ipairs(IDS) do
		if call(C_QuestLog.IsQuestFlaggedCompleted, other) == true then return id, false, true end
	end
	return id, false, false
end

-- Which of the items the player has (nil: the game does not tell) and how many ("?" then): those in the bags, all of
-- them once the log calls the quest complete.
local function progress(id, accepted)
	local got, found = {}, 0
	local all = accepted and call(C_QuestLog.IsComplete, id) == true
	for i, entry in ipairs(QUESTS[id] or {}) do
		local count = C_Item and call(C_Item.GetItemCount, entry.item)
		if all then
			got[i] = true
		elseif type(count) == "number" then
			got[i] = count > 0
		else
			found = nil
		end
		if got[i] and found then found = found + 1 end
	end
	return got, found or "?"
end

-- Names in the player's language --------------------------------------------------------------------

local function questTitle(id)
	local title = call(C_QuestLog.GetTitleForQuestID, id)
	if type(title) == "string" and title ~= "" then return title end
	if not asked[id] and C_QuestLog.RequestLoadQuestByID then
		asked[id] = true
		C_QuestLog.RequestLoadQuestByID(id)
	end
	return nil
end

local function itemName(item)
	local name = C_Item and call(C_Item.GetItemNameByID, item)
	if type(name) == "string" and name ~= "" then return name end
	if not asked[item] and C_Item and C_Item.RequestLoadItemDataByID then
		asked[item] = true
		C_Item.RequestLoadItemDataByID(item)
	end
	return nil
end

-- Without the name of the series: "In Demand - Titan Relics", "Gefragt: Relikte der Titanen" (the other marks are the
-- dash and the colon of other languages).
function Weekly.ShortTitle(title)
	for _, mark in ipairs({ " - ", " \226\128\147 ", ": ", "\239\188\154" }) do
		local _, last = title:find(mark, 1, true)
		if last and last < #title then return title:sub(last + 1) end
	end
	return title
end

local function bossName(entry)
	local encounter = DR:FindEncounterByName(entry.key, entry.boss)
	return encounter and DR.LocText(encounter, "name") or entry.boss
end

-- The dungeon; two items from the same one also name the boss.
local function placeName(quest, entry)
	local name = DR:GetKeyName(entry.key)
	for _, other in ipairs(quest) do
		if other ~= entry and other.key == entry.key then return name .. ": " .. bossName(entry) end
	end
	return name
end

-- The display ---------------------------------------------------------------------------------------

local function paint(text, color)
	text:SetTextColor(color[1], color[2], color[3])
end

local function showTooltip(self)
	local id, accepted, done = current()
	local quest = QUESTS[id]
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:SetText(L["Forever Dungeon Routes"], 1, 1, 1)
	if quest then
		GameTooltip:AddLine(questTitle(id) or quest.title, GOLD[1], GOLD[2], GOLD[3])
	end
	local got, found = progress(id, accepted)
	local status = L["Which quest it is this week, the addon learns from the quest window in Booty Bay. One of your characters is enough."]
	if done then
		status = L["Done for this week."]
	elseif accepted and found == #quest then
		status = L["All items found, ready to turn in."]
	elseif accepted then
		status = L["Accepted, %s of %d items found."]:format(found, #quest)
	elseif quest then
		status = L["Not accepted yet."]
	end
	GameTooltip:AddLine(status, 1, 1, 1, true)
	if not done then
		GameTooltip:AddLine(L["Pix Xizzix, Booty Bay"] .. " (28, 76)", 1, 1, 1)
		for i, entry in ipairs(quest or {}) do
			local c = got[i] and GREEN or DIM
			GameTooltip:AddDoubleLine(itemName(entry.item) or placeName(quest, entry), bossName(entry),
				c[1], c[2], c[3], c[1], c[2], c[3])
		end
	end
	GameTooltip:AddLine(L["Drag: move"], 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local function newText(font)
	local text = frame:CreateFontString(nil, "OVERLAY", font)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	return text
end

-- A text in its full width, cut off only beyond MAX_TEXT; returns the width.
local function fit(text)
	text:SetWidth(0)
	local width = math.ceil(text:GetStringWidth())
	if width > MAX_TEXT then
		width = MAX_TEXT
		text:SetWidth(width)
	end
	return width
end

local function build()
	frame = CreateFrame("Frame", "ForeverDungeonRoutesWeekly", UIParent)
	frame:SetFrameStrata("LOW")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetDontSavePosition(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	local p = DR.db.weeklyPos
	if p.point then
		frame:SetPoint(p.point, UIParent, p.relativePoint or p.point, p.x or 0, p.y or 0)
	else
		frame:SetPoint("TOP", UIParent, "TOP", 0, -10)
	end
	frame.Ground = frame:CreateTexture(nil, "BACKGROUND")
	frame.Ground:SetAllPoints()
	frame.Ground:SetColorTexture(0, 0, 0, 0.4)
	frame.Title = newText("GameFontNormalSmall")
	frame.Title:SetPoint("TOPLEFT", PAD, -PAD + 1)
	paint(frame.Title, GOLD)
	frame.Count = newText("GameFontHighlightSmall")
	frame.Count:SetPoint("LEFT", frame.Title, "RIGHT", 2 * GAP, 0)
	frame.Status = newText("GameFontHighlightSmall")
	frame.Status:SetPoint("TOPLEFT", PAD, -PAD + 1 - LINE)
	frame.Rows = {}
	for i = 1, 3 do
		local row = { Mark = frame:CreateTexture(nil, "ARTWORK"), Text = newText("GameFontHighlightSmall") }
		row.Mark:SetSize(MARK, MARK)
		row.Text:SetPoint("LEFT", row.Mark, "RIGHT", GAP, 0)
		frame.Rows[i] = row
	end

	local close = CreateFrame("Button", nil, frame)
	close:SetSize(14, 14)
	close:SetPoint("TOPRIGHT", -1, -3)
	close:SetAlpha(0.5)
	close:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	close.Icon = close:CreateTexture(nil, "ARTWORK")
	close.Icon:SetTexture(MEDIA .. "close")
	close.Icon:SetSize(8, 8)
	close.Icon:SetPoint("CENTER")
	close:SetScript("OnClick", function(_, button)
		GameTooltip:Hide()
		if button == "RightButton" then
			Weekly:SetWanted(false)
		else
			Weekly:HideThisWeek()
		end
		-- clicked away by mistake? (Oliver, 25.11.2026)
		DR:Print(L["The weekly quest is hidden. To show it again, right-click the button at the minimap or open the settings of the map (/fdr)."])
	end)
	close:SetScript("OnEnter", function(self)
		self:SetAlpha(1)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L["Forever Dungeon Routes"], 1, 1, 1)
		GameTooltip:AddLine(L["Click: hide until next week\nRight-click: switch off (on again in the settings of the map)"],
			0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	close:SetScript("OnLeave", function(self)
		self:SetAlpha(0.5)
		GameTooltip:Hide()
	end)
	frame.Close = close

	frame:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relativePoint, x, y = self:GetPoint(1)
		DR.db.weeklyPos = { point = point, relativePoint = relativePoint, x = x, y = y }
	end)
	frame:SetScript("OnEnter", showTooltip)
	frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- Whether the display is switched on and the X has not hidden it for this week.
function Weekly:IsWanted()
	local hidden, week = DR.cdb.weeklyHidden, thisWeek()
	return DR.db.showWeekly == true and not (hidden and (hidden == true or not week or hidden == week))
end

-- On or off for good (gear button, minimap button); on again brings back what the X has hidden.
function Weekly:SetWanted(on)
	DR.db.showWeekly = on
	if on then DR.cdb.weeklyHidden = nil end
	DR:Fire("SETTINGS_CHANGED", "showWeekly")
end

-- The X: away until the next week, for this character (until switched on again where the game does not tell the week).
function Weekly:HideThisWeek()
	DR.cdb.weeklyHidden = thisWeek() or true
	self:Update()
end

function Weekly:Update()
	if not DR.db or not C_QuestLog then return end
	local level = DR.Safe(UnitLevel("player"))
	if type(level) == "number" and level > 0 then tooLow = level < LEVEL end
	if not logThere or tooLow or not self:IsWanted() then
		if frame then frame:Hide() end
		return
	end
	if call(C_QuestLog.IsOnQuest, IDS[1]) == nil then return end -- the game does not tell at the moment: what is shown stays
	if not frame then build() end
	local id, accepted, done = current()
	local quest = QUESTS[id]
	local got, found = progress(id, accepted)
	local title = quest and questTitle(id)
	title = title and Weekly.ShortTitle(title) or quest and quest.title or done and L["done"] or "?"
	frame.Title:SetText(L["Weekly: %s"]:format(title))
	local ready = accepted and found == #quest
	frame.Count:SetText(quest and done and L["done"] or accepted and (found .. "/" .. #quest) or "")
	paint(frame.Count, (done or ready) and GREEN or WHITE)
	frame.Status:SetText(ready and L["Turn in: Booty Bay"] or not (accepted or done) and L["Not accepted: Booty Bay"] or "")
	paint(frame.Status, ready and GREEN or ORANGE)

	local count = fit(frame.Count)
	local width = fit(frame.Title) + (count > 0 and 2 * GAP + count or 0) + 12
	local y = -PAD + 1 - LINE
	if frame.Status:GetText() ~= "" then
		width = math.max(width, fit(frame.Status))
		y = y - LINE
	end
	for i, row in ipairs(frame.Rows) do
		local entry = quest and not done and quest[i] or nil
		row.Mark:SetShown(entry ~= nil)
		row.Text:SetShown(entry ~= nil)
		if entry then
			itemName(entry.item) -- for the tooltip
			row.Mark:SetShown(got[i] ~= nil)
			row.Mark:SetTexture(MEDIA .. (got[i] and "check" or "squarering"))
			row.Mark:SetVertexColor(unpack(got[i] and GREEN or DIM))
			row.Mark:SetPoint("TOPLEFT", PAD, y - 2)
			row.Text:SetText(placeName(quest, entry))
			paint(row.Text, got[i] and GREEN or accepted and WHITE or DIM)
			width = math.max(width, MARK + GAP + fit(row.Text))
			y = y - LINE
		end
	end
	frame:SetSize(width + 2 * PAD, PAD - y)
	frame:Show()
end

-- Events --------------------------------------------------------------------------------------------

local pending = false
local function updateSoon()
	if pending then return end
	pending = true
	C_Timer.After(0.2, function()
		pending = false
		Weekly:Update()
	end)
end

DR:On("SETTINGS_CHANGED", function() Weekly:Update() end)

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
	"QUEST_TURNED_IN", "BAG_UPDATE_DELAYED", "QUEST_DATA_LOAD_RESULT", "QUEST_DETAIL", "QUEST_GREETING", "GOSSIP_SHOW" }) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, id)
	if not DR.db then return end
	id = DR.Safe(id)
	if event == "QUEST_LOG_UPDATE" then
		logThere = true
	elseif event == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(5, function()
			logThere = true
			updateSoon()
		end)
	elseif event == "QUEST_ACCEPTED" then
		remember(id)
	elseif event == "QUEST_TURNED_IN" then
		if QUESTS[id] then
			remember(id)
			DR.cdb.weeklyDone = { week = thisWeek(), quest = id }
		end
	elseif event == "QUEST_DETAIL" or event == "QUEST_GREETING" or event == "GOSSIP_SHOW" then
		learn(offeredIn(event))
	end
	updateSoon()
end)
