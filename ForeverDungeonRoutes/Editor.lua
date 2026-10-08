local _, DR = ...
local L = DR.L

-- Route editor on the dungeon map, in the spirit of MDT: click points for the path, place stops
-- and notes, drag them around, undo. Works on user routes only; the built-in route is copied
-- first so it always stays available as the default.

local Editor = {}
DR.Editor = Editor

local state -- nil while not editing
local MAX_UNDO = 80
local PICK_DISTANCE = 0.03
local ASPECT = 668 / 1002

local TOOLS = { "main", "side", "stop", "note" }
local TOOL_LABEL = {
	main = "Path",
	side = "Side path",
	stop = "Stop",
	note = "Note",
}
local TOOL_HINT = {
	main = "Left-click: add a point  |  Right-click: remove the last point  |  Shift-click: start a new piece  |  Ctrl-click: select a piece",
	side = "Left-click: add a point  |  Right-click: remove the last point  |  Shift-click: start a new piece  |  Ctrl-click: select a piece",
	stop = "Left-click on the map: place a stop. On a stop: click for options, drag to move, right-click to delete.",
	note = "Left-click on the map: place a note. On a note: click to edit, drag to move, right-click to delete.",
}

local function round(v)
	return math.floor(v * 10000 + 0.5) / 10000
end

-- A stop named like one of the dungeon's boss fights is linked to it, so it ticks itself off.
local function linkByName(key, stop, name)
	local encounter = DR:FindEncounterByName(key, name)
	if encounter then
		stop.encounters = DR.DeepCopy(encounter.ids)
	end
end

function Editor:IsActive()
	return state ~= nil
end

function Editor:IsEditing(key, route)
	return state ~= nil and key ~= nil and state.key == key and state.route == route
end

function Editor:IsActivePath(index)
	return state ~= nil and state.pathIndex == index
end

function Editor:GetTool()
	return state and state.tool
end

-- Dialog callbacks can arrive after editing ended (window closed meanwhile), so both helpers
-- tolerate a missing state.
local function changed()
	if not state then
		DR:Fire("ROUTE_CHANGED")
		return
	end
	DR:RecalcProgress(state.route)
	state.route.modified = time()
	DR:Fire("ROUTE_CHANGED", state.key)
end

local function snapshot()
	if not state then return end
	local r = state.route
	table.insert(state.undo, DR.DeepCopy({ paths = r.paths, stops = r.stops, notes = r.notes, links = r.links }))
	if #state.undo > MAX_UNDO then
		table.remove(state.undo, 1)
	end
end

function Editor:Start(key, route)
	if not key or not route or DR:IsBuiltIn(route) then return end
	state = { key = key, route = route, tool = "main", undo = {} }
	-- continue the last main piece on the shown floor
	local _, floor = DR.Window:GetShown()
	for i = #route.paths, 1, -1 do
		local path = route.paths[i]
		if path.kind == "main" and path.floor == floor then
			state.pathIndex = i
			break
		end
	end
	if DR.db.active[key] ~= route.id then
		DR:SetActiveRoute(key, route.id)
	end
	DR:Fire("EDITOR_CHANGED")
	DR:Fire("ROUTE_CHANGED", key)
end

function Editor:Stop()
	if not state then return end
	local key = state.key
	state = nil
	DR:Fire("EDITOR_CHANGED")
	DR:Fire("ROUTE_CHANGED", key)
end

function Editor:SetTool(tool)
	if not state then return end
	state.tool = tool
	if tool == "main" or tool == "side" then
		local path = state.pathIndex and state.route.paths[state.pathIndex]
		if not path or path.kind ~= tool then
			state.pathIndex = nil
		end
	end
	DR:Fire("EDITOR_CHANGED")
	DR:Fire("ROUTE_CHANGED", state.key)
end

function Editor:Undo()
	if not state then return end
	local snap = table.remove(state.undo)
	if not snap then return end
	local r = state.route
	r.paths, r.stops, r.notes, r.links = snap.paths, snap.stops, snap.notes, snap.links
	if state.pathIndex and not r.paths[state.pathIndex] then
		state.pathIndex = nil
	end
	changed()
end

function Editor:CanUndo()
	return state ~= nil and #state.undo > 0
end

function Editor:DeleteActivePath()
	if not state or not state.pathIndex then return end
	snapshot()
	table.remove(state.route.paths, state.pathIndex)
	state.pathIndex = nil
	changed()
end

-- Map clicks --------------------------------------------------------------------------------

local function nearestPath(floor, x, y)
	local best, bestDist
	for i, path in ipairs(state.route.paths) do
		if path.floor == floor then
			local pts = path.pts
			for j = 1, #pts - 1, 2 do
				local dx, dy = pts[j] - x, (pts[j + 1] - y) * ASPECT
				local d = dx * dx + dy * dy
				if not bestDist or d < bestDist then
					best, bestDist = i, d
				end
			end
		end
	end
	if bestDist and bestDist <= PICK_DISTANCE * PICK_DISTANCE then
		return best
	end
	return nil
end

local function onPathClick(floor, button, x, y)
	local route = state.route
	if button == "LeftButton" then
		if IsControlKeyDown() then
			local index = nearestPath(floor, x, y)
			if index then
				state.pathIndex = index
				state.tool = route.paths[index].kind == "side" and "side" or "main"
				DR:Fire("EDITOR_CHANGED")
				DR:Fire("ROUTE_CHANGED", state.key)
			end
			return true
		end
		snapshot()
		local path = state.pathIndex and route.paths[state.pathIndex]
		if IsShiftKeyDown() or not path or path.floor ~= floor or path.kind ~= state.tool then
			path = { kind = state.tool, floor = floor, pts = {} }
			table.insert(route.paths, path)
			state.pathIndex = #route.paths
		end
		table.insert(path.pts, round(x))
		table.insert(path.pts, round(y))
		changed()
		return true
	elseif button == "RightButton" then
		local path = state.pathIndex and route.paths[state.pathIndex]
		if path and path.floor == floor and #path.pts >= 2 then
			snapshot()
			table.remove(path.pts)
			table.remove(path.pts)
			if #path.pts == 0 then
				table.remove(route.paths, state.pathIndex)
				state.pathIndex = nil
			end
			changed()
		end
		return true
	end
	return false
end

-- A click on the map (0..1 coordinates of the shown floor). Returns true when the editor used it.
function Editor:OnMapClick(button, x, y)
	if not state then
		return false
	end
	local key, floor = DR.Window:GetShown()
	if key ~= state.key or not floor then
		return false
	end
	if x < 0 or x > 1 or y < 0 or y > 1 then
		return true
	end
	local tool = state.tool
	if tool == "main" or tool == "side" then
		return onPathClick(floor, button, x, y)
	elseif tool == "stop" and button == "LeftButton" then
		snapshot()
		local editKey = state.key
		local stop = { kind = "boss", floor = floor, x = round(x), y = round(y), name = "" }
		table.insert(state.route.stops, stop)
		changed()
		DR.Dialog.AskLine(L["Name of the stop"], L["For example the boss name. Can be changed later."], "", function(name)
			stop.name = name
			linkByName(editKey, stop, name)
			changed()
		end)
		return true
	elseif tool == "note" and button == "LeftButton" then
		local route = state.route
		DR.Dialog.AskLine(L["Note"], L["Text of the note:"], "", function(text)
			if text == "" then return L["Please enter a text."] end
			snapshot()
			table.insert(route.notes, { floor = floor, x = round(x), y = round(y), text = text })
			changed()
		end)
		return true
	end
	return false
end

-- Pins while editing ----------------------------------------------------------------------

function Editor:StartDrag(pin)
	if not state then return end
	pin.dragging = true
	pin.dragStartX, pin.dragStartY = GetCursorPosition()
	pin:SetScript("OnUpdate", function(self)
		local cx, cy = GetCursorPosition()
		if not self.dragged and math.abs(cx - self.dragStartX) + math.abs(cy - self.dragStartY) < 6 then
			return
		end
		local x, y = DR.MapView:GetCursorUV()
		if not x then return end
		if not self.dragged then
			snapshot()
			self.dragged = true
		end
		x, y = DR.Clamp(x, 0, 1), DR.Clamp(y, 0, 1)
		DR.MapView:PlacePin(self, x, y)
		local entry = self.stop or self.note
		entry.x, entry.y = round(x), round(y)
	end)
end

function Editor:StopDrag(pin)
	pin.dragging = nil
	pin:SetScript("OnUpdate", nil)
	if pin.dragged and state then
		changed()
	end
end

local function moveStop(index, delta)
	local stops = state.route.stops
	local target = index + delta
	if target < 1 or target > #stops then return end
	snapshot()
	stops[index], stops[target] = stops[target], stops[index]
	DR:ResetProgress(state.key)
	changed()
end

function Editor:OnStopClicked(pin, button)
	if not state then return end
	local index = pin.index
	local stops = state.route.stops
	if button == "RightButton" then
		snapshot()
		table.remove(stops, index)
		DR:ResetProgress(state.key)
		changed()
		return
	end
	local stop = stops[index]
	local key = state.key
	MenuUtil.CreateContextMenu(pin, function(_, root)
		local shown = DR.LocText(stop, "name") or ""
		root:CreateTitle(shown ~= "" and shown or L["Stop"])
		root:CreateButton(L["Rename"], function()
			DR.Dialog.AskLine(L["Name of the stop"], nil, shown, function(name)
				snapshot()
				stop.name = name
				stop.nameDE = nil
				linkByName(key, stop, name)
				changed()
			end)
		end)
		root:CreateButton(L["Edit note"], function()
			DR.Dialog.AskLine(L["Note for this stop"], L["Shown in the tooltip."], DR.LocText(stop, "note") or "", function(text)
				snapshot()
				stop.note = text ~= "" and text or nil
				stop.noteDE = nil
				changed()
			end)
		end)
		root:CreateDivider()
		for _, kind in ipairs({ "boss", "rare", "optional" }) do
			local label = kind == "boss" and L["Boss"] or kind == "rare" and L["Rare"] or L["Optional"]
			root:CreateRadio(label, function() return stop.kind == kind end, function()
				snapshot()
				stop.kind = kind
				changed()
			end)
		end
		local fights = DR:GetEncounters(key)
		if #fights > 0 then
			local boss = root:CreateButton(L["Boss in the game"])
			boss:CreateRadio(L["None (tick off by hand)"], function() return stop.encounters == nil end, function()
				snapshot()
				stop.encounters = nil
				changed()
			end)
			for _, encounter in ipairs(fights) do
				boss:CreateRadio(DR.LocText(encounter, "name"), function()
					return stop.encounters ~= nil and stop.encounters[1] == encounter.ids[1]
				end, function()
					snapshot()
					stop.encounters = DR.DeepCopy(encounter.ids)
					if stop.name == "" then
						stop.name, stop.nameDE = encounter.name, encounter.nameDE
					end
					changed()
				end)
			end
		end
		root:CreateDivider()
		root:CreateButton(L["Move up in order"], function() moveStop(index, -1) end)
		root:CreateButton(L["Move down in order"], function() moveStop(index, 1) end)
		root:CreateButton(DELETE or L["Delete"], function()
			snapshot()
			table.remove(stops, index)
			DR:ResetProgress(state.key)
			changed()
		end)
	end)
end

function Editor:OnNoteClicked(pin, button)
	if not state then return end
	local notes = state.route.notes
	local index = pin.index
	if button == "RightButton" then
		snapshot()
		table.remove(notes, index)
		changed()
		return
	end
	local note = notes[index]
	DR.Dialog.AskLine(L["Note"], L["Text of the note:"], DR.LocText(note, "text") or "", function(text)
		if text == "" then return L["Please enter a text."] end
		snapshot()
		note.text = text
		note.textDE = nil
		changed()
	end)
end

-- Toolbar in the stop list ----------------------------------------------------------------

function Editor:BuildToolbar(parent)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(120)
	bar.tools = {}
	local previous
	for _, tool in ipairs(TOOLS) do
		local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
		b:SetSize(52, 20)
		b:SetText(L[TOOL_LABEL[tool]])
		b:GetFontString():SetFontObject(GameFontNormalSmall)
		if previous then
			b:SetPoint("LEFT", previous, "RIGHT", 2, 0)
		else
			b:SetPoint("TOPLEFT", 0, 0)
		end
		b:SetScript("OnClick", function() Editor:SetTool(tool) end)
		b.Selected = b:CreateTexture(nil, "OVERLAY")
		b.Selected:SetPoint("BOTTOMLEFT", 4, 1)
		b.Selected:SetPoint("BOTTOMRIGHT", -4, 1)
		b.Selected:SetHeight(2)
		b.Selected:SetColorTexture(1, 0.82, 0.3, 1)
		bar.tools[tool] = b
		previous = b
	end
	bar.Hint = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.Hint:SetPoint("TOPLEFT", 0, -26)
	bar.Hint:SetPoint("TOPRIGHT", 0, -26)
	bar.Hint:SetJustifyH("LEFT")
	bar.Hint:SetSpacing(2)
	bar.Hint:SetTextColor(0.75, 0.85, 1)

	bar.Undo = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
	bar.Undo:SetSize(66, 20)
	bar.Undo:SetText(L["Undo"])
	bar.Undo:GetFontString():SetFontObject(GameFontNormalSmall)
	bar.Undo:SetScript("OnClick", function() Editor:Undo() end)
	bar.DeletePiece = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
	bar.DeletePiece:SetSize(76, 20)
	bar.DeletePiece:SetText(L["Delete piece"])
	bar.DeletePiece:GetFontString():SetFontObject(GameFontNormalSmall)
	bar.DeletePiece:SetScript("OnClick", function() Editor:DeleteActivePath() end)
	bar.Done = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
	bar.Done:SetSize(56, 20)
	bar.Done:SetText(L["Done"])
	bar.Done:GetFontString():SetFontObject(GameFontNormalSmall)
	bar.Done:SetScript("OnClick", function() Editor:Stop() end)

	function bar:Refresh()
		if not state then return end
		for tool, b in pairs(self.tools) do
			b.Selected:SetShown(tool == state.tool)
			b:GetFontString():SetTextColor(tool == state.tool and 1 or 0.85, tool == state.tool and 0.82 or 0.85,
				tool == state.tool and 0.3 or 0.85)
		end
		self.Hint:SetText(L[TOOL_HINT[state.tool]])
		local hintHeight = self.Hint:GetStringHeight()
		local y = -26 - hintHeight - 8
		self.Undo:ClearAllPoints()
		self.Undo:SetPoint("TOPLEFT", 0, y)
		self.Undo:SetEnabled(Editor:CanUndo())
		self.DeletePiece:ClearAllPoints()
		self.DeletePiece:SetPoint("LEFT", self.Undo, "RIGHT", 4, 0)
		self.DeletePiece:SetEnabled(state.pathIndex ~= nil and (state.tool == "main" or state.tool == "side"))
		self.Done:ClearAllPoints()
		self.Done:SetPoint("LEFT", self.DeletePiece, "RIGHT", 4, 0)
		self:SetHeight(-y + 22)
	end
	return bar
end

function DR:InitEditor()
	-- Editing ends with the window or when another dungeon is shown.
	self:On("WINDOW_HIDDEN", function() Editor:Stop() end)
	self:On("SHOWN_CHANGED", function(key)
		if state and state.key ~= key then
			Editor:Stop()
		end
	end)
end
