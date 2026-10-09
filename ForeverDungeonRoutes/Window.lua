local _, DR = ...
local L = DR.L

-- The route window, in the spirit of MDT: the dungeon map with the route on the left, the stops
-- of the route on the right. Dungeon and floor are chosen in the header. Inside a dungeon the map
-- follows the player from floor to floor until a floor is chosen by hand.

local HEADER_H = 36
local SIDEBAR_W = 240
local PAD = 10
local ROW_HEIGHT = 18
local MIN_W, MIN_H = 520, 320
local DEFAULT_W, DEFAULT_H = 900, 480
local MEDIA = "Interface\\AddOns\\ForeverDungeonRoutes\\media\\"

local Window = {}
DR.Window = Window

local frame, view, sidebar
local shown = {}       -- key, floor
local following = true
local rows = {}

-- Small helpers ---------------------------------------------------------------------------

local function makeButton(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 20)
	b:SetText(text)
	b:GetFontString():SetFontObject(GameFontNormalSmall)
	return b
end

local function makeDropButton(parent, width)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	DR.StyleBox(b, 1)
	b:SetBackdropColor(0.12, 0.11, 0.1, 1)
	b:SetSize(width, 22)
	b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.Text:SetPoint("LEFT", 8, 0)
	b.Text:SetPoint("RIGHT", -18, 0)
	b.Text:SetJustifyH("LEFT")
	b.Text:SetWordWrap(false)
	b.Arrow = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.Arrow:SetPoint("RIGHT", -6, 0)
	b.Arrow:SetText("v")
	b:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(1, 0.9, 0.6, 1)
		if self.tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(self.tooltip, 1, 1, 1, true)
			if self.tooltipExtra then
				GameTooltip:AddLine(self.tooltipExtra, 0.7, 0.7, 0.7, true)
			end
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(0.76, 0.66, 0.47, 0.9)
		GameTooltip:Hide()
	end)
	return b
end

local function makeIconButton(parent, texture, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	b.Icon = b:CreateTexture(nil, "ARTWORK")
	b.Icon:SetTexture(MEDIA .. texture)
	b.Icon:SetAllPoints()
	b.Icon:SetVertexColor(0.76, 0.66, 0.47)
	b:SetScript("OnEnter", function(self) self.Icon:SetVertexColor(1, 0.9, 0.6) end)
	b:SetScript("OnLeave", function(self) self.Icon:SetVertexColor(0.76, 0.66, 0.47) end)
	return b
end

local function indexOf(list, value)
	for i, v in ipairs(list) do
		if v == value then return i end
	end
	return nil
end

-- Geometry ----------------------------------------------------------------------------------

local function saveGeometry()
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	local g = DR.db.window
	g.point, g.relativePoint, g.x, g.y = point, relativePoint, x, y
	g.width, g.height = frame:GetWidth(), frame:GetHeight()
end

local function restoreGeometry()
	local g = DR.db.window
	frame:ClearAllPoints()
	if g.point then
		frame:SetPoint(g.point, UIParent, g.relativePoint or g.point, g.x or 0, g.y or 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
	frame:SetSize(math.max(MIN_W, g.width or DEFAULT_W), math.max(MIN_H, g.height or DEFAULT_H))
end

local function layout()
	local map = view.frame
	map:ClearAllPoints()
	map:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -HEADER_H)
	frame.RouteButton:ClearAllPoints()
	if DR.db.showStops then
		sidebar:Show()
		map:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(SIDEBAR_W + PAD), PAD)
		frame.RouteButton:SetParent(sidebar)
		frame.RouteButton:SetFrameLevel(sidebar:GetFrameLevel() + 2)
		frame.RouteButton:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -16)
		frame.RouteButton:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, -16)
	else
		sidebar:Hide()
		map:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
		-- without the stop list the route choice sits on the map
		frame.RouteButton:SetParent(map)
		frame.RouteButton:SetFrameLevel(map:GetFrameLevel() + 40)
		frame.RouteButton:SetPoint("TOPRIGHT", map, "TOPRIGHT", -6, -6)
		frame.RouteButton:SetWidth(210)
	end
end

-- Menus -------------------------------------------------------------------------------------

local function exportRoute()
	local key = shown.key
	local route = DR:GetActiveRoute(key)
	if not route then return end
	DR.Dialog.ShowText(L["Export route"], L["Copy the text with Ctrl+C and share it. Others can paste it via Import."],
		DR:ExportRoute(key, route))
end

local function importRoute()
	DR.Dialog.AskText(L["Import route"], L["Paste a route text with Ctrl+V."], function(text)
		local key, route = DR:ImportRoute(text)
		if not key then
			return route
		end
		DR:AddImportedRoute(key, route)
		DR:Print(L["Route imported: %s"], DR:GetRouteName(route))
		Window:Open(key, DR:GetRouteStartFloor(route))
	end, L["Import"])
end

local function renameRoute()
	local key = shown.key
	local route = DR:GetActiveRoute(key)
	DR.Dialog.AskLine(L["Rename route"], nil, DR:GetRouteName(route), function(name)
		if name == "" then return L["Please enter a name."] end
		DR:RenameRoute(key, route, name)
	end)
end

local function deleteRoute()
	local key = shown.key
	local route = DR:GetActiveRoute(key)
	DR.Dialog.Confirm(L["Delete route"], L["Delete the route \"%s\"? This cannot be undone."]:format(DR:GetRouteName(route)),
		function()
			if DR.Editor:IsEditing(key, route) then
				DR.Editor:Stop()
			end
			DR:DeleteRoute(key, route)
		end, DELETE or L["Delete"])
end

local function newRoute()
	local key = shown.key
	DR.Dialog.AskLine(L["New route"], L["Name of the new route:"], L["My route"], function(name)
		if name == "" then return L["Please enter a name."] end
		local route = DR:NewRoute(key, name)
		DR.Editor:Start(key, route)
	end)
end

local function openRouteMenu(owner)
	local key = shown.key
	local current = DR:GetActiveRoute(key)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(L["Routes"])
		for _, route in ipairs(DR:GetRoutes(key)) do
			root:CreateRadio(DR:GetRouteName(route), function() return route == DR:GetActiveRoute(key) end,
				function() DR:SetActiveRoute(key, route.id) end)
		end
		root:CreateDivider()
		root:CreateButton(L["New route"], newRoute)
		if current then
			root:CreateButton(L["Copy route"], function()
				local copy = DR:CopyRoute(key, current)
				DR:Print(L["Copied. The copy can be edited: %s"], DR:GetRouteName(copy))
			end)
			if not DR:IsBuiltIn(current) then
				root:CreateButton(L["Rename route"], renameRoute)
				root:CreateButton(L["Delete route"], deleteRoute)
			end
			root:CreateDivider()
			root:CreateButton(L["Export route"], exportRoute)
		else
			root:CreateDivider()
		end
		root:CreateButton(L["Import route"], importRoute)
	end)
end

local function openDungeonMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(L["Dungeons"])
		for _, dungeon in ipairs(DR.Dungeons) do
			local key = dungeon.key
			local text = DR:GetKeyName(key)
			if dungeon.levels then
				text = text .. "  |cff8c8c8c" .. dungeon.levels[1] .. "-" .. dungeon.levels[2] .. "|r"
			end
			if key == DR.currentKey then
				text = text .. "  |cffffd75c" .. L["(you are here)"] .. "|r"
			end
			root:CreateRadio(text, function() return shown.key == key end, function()
				following = key == DR.currentKey
				Window:ShowDungeon(key)
			end)
		end
	end)
end

local function openFloorMenu(owner)
	local dungeon = DR:GetDungeon(shown.key)
	if not dungeon then return end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(L["Map level"])
		for i, floor in ipairs(dungeon.floors) do
			root:CreateRadio(i .. ". " .. DR:GetFloorName(floor), function() return shown.floor == floor end,
				function() Window:SelectFloor(floor, true) end)
		end
	end)
end

local function setting(key, value)
	DR.db[key] = value
	DR:Fire("SETTINGS_CHANGED", key)
end

local function openSettingsMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(L["Settings"])
		root:CreateCheckbox(L["Stop list beside the map"], function() return DR.db.showStops end,
			function() setting("showStops", not DR.db.showStops) end)
		root:CreateCheckbox(L["Show my position and group"], function() return DR.db.showPlayer end,
			function() setting("showPlayer", not DR.db.showPlayer) end)
		root:CreateCheckbox(L["Arrows on the route"], function() return DR.db.showArrows end,
			function() setting("showArrows", not DR.db.showArrows) end)
		root:CreateCheckbox(L["Tick off bosses automatically"], function() return DR.db.autoCheck end,
			function() setting("autoCheck", not DR.db.autoCheck) end)
		root:CreateCheckbox(L["Open automatically in dungeons"], function() return DR.db.autoOpen end,
			function() setting("autoOpen", not DR.db.autoOpen) end)
		local width = root:CreateButton(L["Line width"])
		for _, w in ipairs({ 3, 4, 5, 6 }) do
			width:CreateRadio(tostring(w), function() return DR.db.lineWidth == w end, function() setting("lineWidth", w) end)
		end
		local opacity = root:CreateButton(L["Opacity"])
		for _, a in ipairs({ 1, 0.85, 0.7, 0.55 }) do
			opacity:CreateRadio(math.floor(a * 100 + 0.5) .. "%", function() return DR.db.alpha == a end,
				function() setting("alpha", a) end)
		end
		root:CreateDivider()
		root:CreateButton(L["Reset window size and position"], function()
			DR.db.window = {}
			restoreGeometry()
		end)
	end)
end

-- Stop list -----------------------------------------------------------------------------------

local function makeRow(index)
	local row = CreateFrame("Button", nil, sidebar.List)
	row:SetHeight(ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.Highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.Highlight:SetAllPoints()
	row.Highlight:SetColorTexture(1, 0.85, 0.5, 0.12)
	row.Hover = row:CreateTexture(nil, "BACKGROUND")
	row.Hover:SetAllPoints()
	row.Hover:SetColorTexture(1, 0.85, 0.5, 0.12)
	row.Hover:Hide()

	row.Badge = row:CreateTexture(nil, "ARTWORK")
	row.Badge:SetTexture(MEDIA .. "ring")
	row.Badge:SetSize(16, 16)
	row.Badge:SetPoint("LEFT", 2, 0)
	row.BadgeFill = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.BadgeFill:SetTexture(MEDIA .. "circle")
	row.BadgeFill:SetVertexColor(0.06, 0.05, 0.04, 0.95)
	row.BadgeFill:SetAllPoints(row.Badge)
	row.Number = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.Number:SetPoint("CENTER", row.Badge, "CENTER", 0, 0)

	row.Check = row:CreateTexture(nil, "OVERLAY")
	row.Check:SetTexture(MEDIA .. "check")
	row.Check:SetSize(14, 14)
	row.Check:SetPoint("RIGHT", -2, 0)

	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Name:SetPoint("LEFT", row.Badge, "RIGHT", 6, 0)
	row.Name:SetPoint("RIGHT", row.Check, "LEFT", -4, 0)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)

	row:SetScript("OnEnter", function(self)
		DR:Fire("HIGHLIGHT_STOP", self.index)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(self.stopName, 1, 0.82, 0)
		if self.note and self.note ~= "" then
			GameTooltip:AddLine(self.note, 1, 1, 1, true)
		end
		if self.otherFloor then
			GameTooltip:AddLine(L["On another map level"] .. ": " .. DR:GetFloorName(self.floor), 0.7, 0.7, 0.7)
		end
		GameTooltip:AddLine(L["Click: mark as done\nShift-click: show on map"], 0.4, 0.8, 1, true)
		if self.auto and DR.db.autoCheck then
			GameTooltip:AddLine(L["Ticks itself off when the boss dies."], 0.6, 0.6, 0.6, true)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		DR:Fire("HIGHLIGHT_STOP", nil)
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self, button)
		if IsShiftKeyDown() or button == "RightButton" then
			Window:FocusStop(self.index)
		else
			DR:ToggleStopDone(shown.key, DR:GetActiveRoute(shown.key), self.index)
		end
	end)
	rows[index] = row
	return row
end

local function buildSidebar()
	sidebar = CreateFrame("Frame", nil, frame)
	sidebar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -HEADER_H)
	sidebar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD + 10)
	sidebar:SetWidth(SIDEBAR_W - PAD)

	sidebar.Level = sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sidebar.Level:SetPoint("TOPLEFT", 2, 0)
	sidebar.Level:SetPoint("TOPRIGHT", 0, 0)
	sidebar.Level:SetJustifyH("LEFT")

	-- the stops scroll when the window is too small for all of them
	local scroll = CreateFrame("ScrollFrame", nil, sidebar)
	scroll:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -46)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange()
		self:SetVerticalScroll(DR.Clamp(self:GetVerticalScroll() - delta * ROW_HEIGHT * 2, 0, range))
	end)
	local list = CreateFrame("Frame", nil, scroll)
	list:SetSize(SIDEBAR_W - PAD, 10)
	scroll:SetScrollChild(list)
	scroll:SetScript("OnSizeChanged", function(_, width) list:SetWidth(width) end)
	sidebar.Scroll, sidebar.List = scroll, list

	sidebar.Empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sidebar.Empty:SetPoint("TOPLEFT", 0, -2)
	sidebar.Empty:SetPoint("TOPRIGHT", 0, -2)
	sidebar.Empty:SetJustifyH("LEFT")
	sidebar.Empty:SetSpacing(2)

	-- buttons under the list
	local bottom = CreateFrame("Frame", nil, sidebar)
	bottom:SetPoint("BOTTOMLEFT", 0, 0)
	bottom:SetPoint("BOTTOMRIGHT", 0, 0)
	bottom:SetHeight(24)
	sidebar.Bottom = bottom
	scroll:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 6)

	sidebar.EditButton = makeButton(bottom, L["Edit"], 108)
	sidebar.EditButton:SetPoint("BOTTOMLEFT", 0, 0)
	sidebar.EditButton:SetScript("OnClick", function()
		local key = shown.key
		local route = DR:GetActiveRoute(key)
		if DR:IsBuiltIn(route) then
			local copy = DR:CopyRoute(key, route)
			DR:Print(L["The standard route stays unchanged. You are editing a copy: %s"], DR:GetRouteName(copy))
			DR.Editor:Start(key, copy)
		else
			DR.Editor:Start(key, route)
		end
	end)
	sidebar.ResetButton = makeButton(bottom, L["New run"], 108)
	sidebar.ResetButton:SetPoint("LEFT", sidebar.EditButton, "RIGHT", 6, 0)
	sidebar.ResetButton:SetScript("OnClick", function() DR:ResetProgress(shown.key) end)
	sidebar.ResetButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(L["Clears all checkmarks of this dungeon."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	sidebar.ResetButton:SetScript("OnLeave", GameTooltip_Hide)
	sidebar.NewButton = makeButton(bottom, L["New route"], 108)
	sidebar.NewButton:SetPoint("BOTTOMLEFT", 0, 0)
	sidebar.NewButton:SetScript("OnClick", newRoute)
	sidebar.ImportButton = makeButton(bottom, L["Import"], 108)
	sidebar.ImportButton:SetPoint("LEFT", sidebar.NewButton, "RIGHT", 6, 0)
	sidebar.ImportButton:SetScript("OnClick", importRoute)

	sidebar.Toolbar = DR.Editor:BuildToolbar(bottom)
	sidebar.Toolbar:SetPoint("BOTTOMLEFT", 0, 0)
	sidebar.Toolbar:SetPoint("BOTTOMRIGHT", 0, 0)
end

local function refreshSidebar()
	local key = shown.key
	local route = DR:GetActiveRoute(key)
	local editing = DR.Editor:IsEditing(key, route)
	sidebar.Level:SetText(DR:GetLevelText(key) or "")
	for _, row in ipairs(rows) do
		row:Hide()
	end
	sidebar.Empty:Hide()
	sidebar.EditButton:Hide()
	sidebar.ResetButton:Hide()
	sidebar.NewButton:Hide()
	sidebar.ImportButton:Hide()
	sidebar.Toolbar:Hide()

	local y = 0
	if not route then
		sidebar.Empty:SetText(L["No route for this dungeon yet. Create one or import a route text."])
		sidebar.Empty:Show()
		y = -sidebar.Empty:GetStringHeight() - 4
		sidebar.NewButton:Show()
		sidebar.ImportButton:Show()
		sidebar.Bottom:SetHeight(24)
	else
		local labels = DR:GetStopLabels(route)
		local nextIndex = DR:GetNextStopIndex(key, route)
		for i, stop in ipairs(route.stops) do
			local row = rows[i] or makeRow(i)
			row.index = i
			row.floor = stop.floor
			row.stopName = DR:GetStopName(stop)
			row.auto = stop.encounters ~= nil
			row.note = DR.LocText(stop, "note")
			row.otherFloor = not DR.OnFloor(stop, shown.floor)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, y)
			row:SetPoint("TOPRIGHT", 0, y)
			row.Number:SetText(labels[i])
			row.Name:SetText(row.stopName)
			local done = DR:IsStopDone(key, route, i)
			row.Check:SetShown(done)
			local r, g, b = 0.95, 0.76, 0.31
			if stop.kind == "rare" then
				r, g, b = 0.89, 0.87, 0.82
			elseif stop.kind == "optional" then
				r, g, b = 0.62, 0.78, 0.95
			end
			row.Badge:SetVertexColor(r, g, b)
			row.Number:SetTextColor(r, g, b)
			if done then
				row.Name:SetTextColor(0.5, 0.5, 0.5)
			elseif i == nextIndex then
				row.Name:SetTextColor(1, 0.92, 0.6)
			elseif row.otherFloor then
				row.Name:SetTextColor(0.72, 0.72, 0.72)
			else
				row.Name:SetTextColor(1, 1, 1)
			end
			row:Show()
			y = y - ROW_HEIGHT
		end
		if #route.stops == 0 then
			sidebar.Empty:SetText(L["This route has no stops yet."])
			sidebar.Empty:Show()
			y = -sidebar.Empty:GetStringHeight() - 4
		end
		if editing then
			sidebar.Toolbar:Refresh()
			sidebar.Toolbar:Show()
			sidebar.Bottom:SetHeight(sidebar.Toolbar:GetHeight())
		else
			sidebar.EditButton:Show()
			sidebar.ResetButton:Show()
			sidebar.Bottom:SetHeight(24)
		end
	end
	sidebar.List:SetHeight(math.max(10, -y))
end

-- Building --------------------------------------------------------------------------------------

local function build()
	frame = CreateFrame("Frame", "ForeverDungeonRoutesFrame", UIParent, "BackdropTemplate")
	DR.StyleBox(frame, 0.96)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetResizeBounds(MIN_W, MIN_H)
	frame:SetDontSavePosition(true)
	frame:EnableMouse(true)
	frame:Hide()
	table.insert(UISpecialFrames, "ForeverDungeonRoutesFrame")
	restoreGeometry()
	frame:SetAlpha(DR.db.alpha or 1)
	frame:SetScript("OnHide", function()
		DR:Fire("WINDOW_HIDDEN")
	end)

	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", 0, 0)
	header:SetHeight(HEADER_H)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() frame:StartMoving() end)
	header:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		saveGeometry()
	end)
	frame.Header = header

	frame.DungeonButton = makeDropButton(header, 200)
	frame.DungeonButton:SetPoint("LEFT", PAD, -1)
	frame.DungeonButton.tooltip = L["Choose a dungeon"]
	frame.DungeonButton:SetScript("OnClick", openDungeonMenu)

	frame.FloorPrev = makeButton(header, "<", 22)
	frame.FloorPrev:SetHeight(22)
	frame.FloorPrev:SetPoint("LEFT", frame.DungeonButton, "RIGHT", 8, 0)
	frame.FloorPrev:SetScript("OnClick", function() Window:StepFloor(-1) end)
	frame.FloorButton = makeDropButton(header, 180)
	frame.FloorButton:SetPoint("LEFT", frame.FloorPrev, "RIGHT", 2, 0)
	frame.FloorButton.tooltip = L["Choose the map level"]
	frame.FloorButton:SetScript("OnClick", openFloorMenu)
	frame.FloorNext = makeButton(header, ">", 22)
	frame.FloorNext:SetHeight(22)
	frame.FloorNext:SetPoint("LEFT", frame.FloorButton, "RIGHT", 2, 0)
	frame.FloorNext:SetScript("OnClick", function() Window:StepFloor(1) end)

	frame.Close = makeButton(header, "X", 22)
	frame.Close:SetHeight(22)
	frame.Close:SetPoint("RIGHT", -PAD, -1)
	frame.Close:SetScript("OnClick", function() frame:Hide() end)
	frame.Gear = makeIconButton(header, "gear", 20)
	frame.Gear:SetPoint("RIGHT", frame.Close, "LEFT", -8, 0)
	frame.Gear:SetScript("OnClick", openSettingsMenu)

	view = DR.MapView
	view:Create(frame)
	buildSidebar()
	frame.Sidebar = sidebar

	frame.RouteButton = makeDropButton(sidebar, 210)
	frame.RouteButton.tooltip = L["Choose, copy, share or import routes"]
	frame.RouteButton:SetScript("OnClick", openRouteMenu)

	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetFrameLevel(frame:GetFrameLevel() + 50)
	grip.Icon = grip:CreateTexture(nil, "OVERLAY")
	grip.Icon:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip.Icon:SetAllPoints()
	grip.Highlight = grip:CreateTexture(nil, "HIGHLIGHT")
	grip.Highlight:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip.Highlight:SetAllPoints()
	grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		saveGeometry()
	end)
	frame.Grip = grip

	layout()
end

-- State -----------------------------------------------------------------------------------------

function Window:IsShown()
	return frame ~= nil and frame:IsShown()
end

function Window:GetShown()
	return shown.key, shown.floor
end

function Window:GetShownKey()
	return shown.key
end

function Window:IsFollowing()
	return following
end

function Window:GetFrame()
	return frame
end

function Window:Refresh()
	if not frame or not shown.key then return end
	local dungeon = DR:GetDungeon(shown.key)
	frame.DungeonButton.Text:SetText(DR:GetKeyName(shown.key))
	local floors = dungeon.floors
	local index = indexOf(floors, shown.floor) or 1
	local several = #floors > 1
	frame.FloorPrev:SetShown(several)
	frame.FloorNext:SetShown(several)
	frame.FloorButton:SetShown(several)
	if several then
		frame.FloorButton.Text:SetText(index .. "/" .. #floors .. "  " .. DR:GetFloorName(shown.floor))
		frame.FloorPrev:SetEnabled(index > 1)
		frame.FloorNext:SetEnabled(index < #floors)
	end
	local route = DR:GetActiveRoute(shown.key)
	frame.RouteButton.Text:SetText(route and DR:GetRouteName(route) or L["No route yet"])
	frame.RouteButton.tooltipExtra = route and route.source and (L["Source"] .. ": " .. route.source) or nil
	view:SetFloor(shown.key, shown.floor)
	if DR.db.showStops then
		refreshSidebar()
	end
end

-- Shows a dungeon; without a floor inside the dungeon the player's floor, else where the route
-- starts.
function Window:ShowDungeon(key, floor)
	local dungeon = DR:GetDungeon(key)
	if not dungeon then return end
	local newKey = key ~= shown.key
	if not floor and key == DR.currentKey then
		local located, playerFloor = DR:LocatePlayer(not newKey and shown.floor or nil)
		if located and located ~= key then
			-- the position showed another wing of the instance
			return self:ShowDungeon(located)
		end
		floor = playerFloor
	end
	if not floor and not newKey then
		floor = shown.floor
	end
	if not floor or DR:GetDungeonForFloor(floor) ~= dungeon then
		floor = DR:GetRouteStartFloor(DR:GetActiveRoute(key))
		if DR:GetDungeonForFloor(floor) ~= dungeon then
			floor = dungeon.floors[1]
		end
	end
	shown.key, shown.floor = key, floor
	if newKey then
		DR:Fire("SHOWN_CHANGED", key)
	end
	self:Refresh()
end

function Window:SelectFloor(floor, byHand)
	local dungeon = DR:GetDungeon(shown.key)
	if not floor or not dungeon or DR:GetDungeonForFloor(floor) ~= dungeon then return end
	if byHand then
		following = false
	end
	if floor == shown.floor then return end
	shown.floor = floor
	self:Refresh()
end

function Window:StepFloor(delta)
	local dungeon = DR:GetDungeon(shown.key)
	if not dungeon then return end
	local index = indexOf(dungeon.floors, shown.floor) or 1
	local floor = dungeon.floors[index + delta]
	if floor then
		self:SelectFloor(floor, true)
	end
end

-- Back to the player: their dungeon and floor, centered when zoomed in.
function Window:FollowPlayer()
	following = true
	if not DR.currentKey then return end
	self:ShowDungeon(DR.currentKey)
	local u, v = view:GetPlayerUV()
	if u and view.zoom > 1 then
		view:CenterOn(u, v)
	end
end

function Window:FocusStop(index)
	local route = DR:GetActiveRoute(shown.key)
	local stop = route and route.stops[index]
	if not stop then return end
	if not DR.OnFloor(stop, shown.floor) then
		self:SelectFloor(stop.floor, true)
	end
	view:CenterOn(stop.x, stop.y, 2)
end

function Window:Open(key, floor)
	if not frame then
		build()
	end
	key = key or DR.currentKey or shown.key or DR.Dungeons[1].key
	if key == DR.currentKey and not floor then
		following = true
	end
	self:ShowDungeon(key, floor)
	frame:Show()
	frame:Raise()
	view:Layout()
end

function Window:Toggle()
	if self:IsShown() then
		frame:Hide()
	else
		self:Open(DR.currentKey or shown.key)
	end
end

local function refreshIfShown(key)
	if Window:IsShown() and (key == nil or key == shown.key) then
		Window:Refresh()
	end
end

DR:On("ROUTE_CHANGED", refreshIfShown)
DR:On("PROGRESS_CHANGED", refreshIfShown)
DR:On("EDITOR_CHANGED", function() refreshIfShown() end)
DR:On("SETTINGS_CHANGED", function(key)
	if not frame then return end
	if key == "alpha" then
		frame:SetAlpha(DR.db.alpha)
	elseif key == "showStops" then
		layout()
	end
	refreshIfShown()
end)
DR:On("DUNGEON_CHANGED", function(key)
	if not Window:IsShown() then return end
	if key and following then
		Window:ShowDungeon(key)
	else
		view:UpdateGroup()
	end
end)
DR:On("STOP_HOVER", function(index)
	for _, row in ipairs(rows) do
		row.Hover:SetShown(row:IsShown() and row.index == index)
	end
end)
