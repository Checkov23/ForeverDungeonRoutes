local _, DR = ...
local L = DR.L

-- Draws the active route of the shown dungeon floor onto the world map: path lines on a layer
-- right above the map art, stops, notes and floor links as map pins above everything else.

local PIN_LEVEL = "PIN_FRAME_LEVEL_DUNGEONROUTES"
local STOP_PIN = "ForeverDungeonRoutesStopPinTemplate"
local NOTE_PIN = "ForeverDungeonRoutesNotePinTemplate"
local LINK_PIN = "ForeverDungeonRoutesLinkPinTemplate"

-- Color of the main path runs from the first to the last stop.
local GRADIENT = {
	{ 0.00, 0.37, 0.84, 0.82 },
	{ 0.55, 1.00, 0.84, 0.36 },
	{ 1.00, 1.00, 0.50, 0.25 },
}
local SIDE_COLOR = { 0.89, 0.87, 0.82 }
local CASING_COLOR = { 0.05, 0.04, 0.03, 0.78 }
local ARROW_COLOR = { 0.06, 0.05, 0.03, 0.92 }
local EDIT_DOT_COLOR = { 1.00, 1.00, 1.00, 0.95 }

local function gradient(t)
	for i = 1, #GRADIENT - 1 do
		local a, b = GRADIENT[i], GRADIENT[i + 1]
		if t <= b[1] then
			local u = (b[1] > a[1]) and (t - a[1]) / (b[1] - a[1]) or 0
			return a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u, a[4] + (b[4] - a[4]) * u
		end
	end
	local last = GRADIENT[#GRADIENT]
	return last[2], last[3], last[4]
end
DR.GradientColor = gradient

local Provider = CreateFromMixins(MapCanvasDataProviderMixin)

function Provider:OnAdded(map)
	MapCanvasDataProviderMixin.OnAdded(self, map)
	local levels = map:GetPinFrameLevelsManager()
	if not levels:InsertFrameLevelAbove(PIN_LEVEL, "PIN_FRAME_LEVEL_ENCOUNTER", 3) then
		levels:AddFrameLevel(PIN_LEVEL, 3)
	end
	local canvas = map:GetCanvas()
	self.layer = CreateFrame("Frame", nil, canvas)
	self.layer:SetAllPoints(canvas)
	-- Detail layers (the map art) use the canvas frame level, pins start far above.
	self.layer:SetFrameLevel(canvas:GetFrameLevel() + 1)
	self.lines, self.numLines = {}, 0
	self.dots, self.numDots = {}, 0
end

function Provider:ReleaseLines()
	for i = 1, self.numLines do
		self.lines[i]:Hide()
	end
	self.numLines = 0
	for i = 1, self.numDots do
		self.dots[i]:Hide()
	end
	self.numDots = 0
end

function Provider:RemoveAllData()
	self:ReleaseLines()
	local map = self:GetMap()
	map:RemoveAllPinsByTemplate(STOP_PIN)
	map:RemoveAllPinsByTemplate(NOTE_PIN)
	map:RemoveAllPinsByTemplate(LINK_PIN)
	self.key, self.route, self.mapID = nil, nil, nil
end

function Provider:RefreshAllData()
	self:RemoveAllData()
	local map = self:GetMap()
	local mapID = map:GetMapID()
	DR.shownMapID = mapID
	if DR.db.showOnMap then
		local key = DR:GetKeyForMap(mapID)
		local route = key and DR:GetActiveRoute(key)
		if route then
			self.key, self.route, self.mapID = key, route, mapID
			self:DrawLines()
			self:AddPins()
		end
	end
	DR:Fire("MAP_SHOWN", mapID)
end

function Provider:OnCanvasScaleChanged()
	if self.route and not self.redrawPending then
		self.redrawPending = true
		C_Timer.After(0, function()
			self.redrawPending = nil
			if self.route then
				self:ReleaseLines()
				self:DrawLines()
			end
		end)
	end
end

function Provider:OnCanvasSizeChanged()
	self:OnCanvasScaleChanged()
end

-- Lines -----------------------------------------------------------------------------------

function Provider:AcquireLine(subLevel)
	self.numLines = self.numLines + 1
	local line = self.lines[self.numLines]
	if not line then
		line = self.layer:CreateLine(nil, "ARTWORK")
		self.lines[self.numLines] = line
	end
	line:SetDrawLayer("ARTWORK", subLevel)
	line:Show()
	return line
end

function Provider:Segment(subLevel, x1, y1, x2, y2, thickness, r, g, b, a)
	local line = self:AcquireLine(subLevel)
	line:SetStartPoint("TOPLEFT", self.layer, x1, -y1)
	line:SetEndPoint("TOPLEFT", self.layer, x2, -y2)
	line:SetThickness(thickness)
	line:SetColorTexture(r, g, b, a or 1)
	return line
end

function Provider:Dot(x, y, size, r, g, b, a)
	self.numDots = self.numDots + 1
	local dot = self.dots[self.numDots]
	if not dot then
		dot = self.layer:CreateTexture(nil, "OVERLAY")
		dot:SetTexture("Interface\\AddOns\\ForeverDungeonRoutes\\media\\circle")
		self.dots[self.numDots] = dot
	end
	dot:ClearAllPoints()
	dot:SetPoint("CENTER", self.layer, "TOPLEFT", x, -y)
	dot:SetSize(size, size)
	dot:SetVertexColor(r, g, b, a or 1)
	dot:Show()
	return dot
end

-- Screen units per canvas unit, so lines keep the same width on screen while zooming.
function Provider:UnitsPerCanvasUnit()
	local scale = self.layer:GetEffectiveScale() / UIParent:GetEffectiveScale()
	if not scale or scale <= 0 then
		return 1
	end
	return scale
end

local function toCanvas(pts, w, h)
	local xs, ys = {}, {}
	for i = 1, #pts / 2 do
		xs[i] = pts[2 * i - 1] * w
		ys[i] = pts[2 * i] * h
	end
	return xs, ys
end

function Provider:DrawMainPath(path, w, h, k)
	local xs, ys = toCanvas(path.pts, w, h)
	local n = #xs
	if n < 2 then return end
	local width = (DR.db.lineWidth or 4) / k
	local casing = width + 3 / k
	local cum = { 0 }
	for i = 2, n do
		local dx, dy = xs[i] - xs[i - 1], ys[i] - ys[i - 1]
		cum[i] = cum[i - 1] + math.sqrt(dx * dx + dy * dy)
	end
	local total = cum[n] > 0 and cum[n] or 1
	local t0, t1 = path.t0 or 0, path.t1 or 1
	for i = 2, n do
		self:Segment(-6, xs[i - 1], ys[i - 1], xs[i], ys[i], casing, unpack(CASING_COLOR))
	end
	for i = 2, n do
		local t = t0 + (t1 - t0) * ((cum[i - 1] + cum[i]) * 0.5 / total)
		local r, g, b = gradient(t)
		self:Segment(0, xs[i - 1], ys[i - 1], xs[i], ys[i], width, r, g, b, 1)
	end
	if DR.db.showArrows then
		local spacing, size = 64 / k, 5 / k
		local s = spacing * 0.6
		local i = 2
		while s < cum[n] - 8 / k do
			while cum[i] < s do
				i = i + 1
			end
			local seg = cum[i] - cum[i - 1]
			local u = seg > 0 and (s - cum[i - 1]) / seg or 0
			local mx = xs[i - 1] + (xs[i] - xs[i - 1]) * u
			local my = ys[i - 1] + (ys[i] - ys[i - 1]) * u
			local angle = math.atan2(ys[i] - ys[i - 1], xs[i] - xs[i - 1])
			local ax1 = mx - size * math.cos(angle - 0.75)
			local ay1 = my - size * math.sin(angle - 0.75)
			local ax2 = mx - size * math.cos(angle + 0.75)
			local ay2 = my - size * math.sin(angle + 0.75)
			local thick = 2 / k
			self:Segment(4, ax1, ay1, mx, my, thick, unpack(ARROW_COLOR))
			self:Segment(4, ax2, ay2, mx, my, thick, unpack(ARROW_COLOR))
			s = s + spacing
		end
	end
	return xs, ys
end

function Provider:DrawSidePath(path, w, h, k)
	local xs, ys = toCanvas(path.pts, w, h)
	local n = #xs
	if n < 2 then return end
	local width = math.max(2, (DR.db.lineWidth or 4) - 1) / k
	local casing = width + 3 / k
	local dash, gap = 7 / k, 5 / k
	for i = 2, n do
		self:Segment(-6, xs[i - 1], ys[i - 1], xs[i], ys[i], casing, CASING_COLOR[1], CASING_COLOR[2], CASING_COLOR[3], 0.55)
	end
	local phase, drawing = dash, true
	for i = 2, n do
		local x1, y1, x2, y2 = xs[i - 1], ys[i - 1], xs[i], ys[i]
		local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
		local pos = 0
		while pos < len do
			local step = math.min(phase, len - pos)
			if drawing then
				local a, b = pos / len, (pos + step) / len
				self:Segment(0, x1 + (x2 - x1) * a, y1 + (y2 - y1) * a, x1 + (x2 - x1) * b, y1 + (y2 - y1) * b,
					width, SIDE_COLOR[1], SIDE_COLOR[2], SIDE_COLOR[3], 1)
			end
			pos = pos + step
			phase = phase - step
			if phase <= 0 then
				drawing = not drawing
				phase = drawing and dash or gap
			end
		end
	end
	return xs, ys
end

function Provider:DrawLines()
	local route, mapID = self.route, self.mapID
	-- The canvas size is set explicitly per map; the layer covers it 1:1.
	local w, h = self:GetMap():GetCanvas():GetSize()
	if not w or w <= 0 or not h or h <= 0 then return end
	local k = self:UnitsPerCanvasUnit()
	local editing = DR.Editor and DR.Editor:IsEditing(self.key, route)
	for index, path in ipairs(route.paths) do
		if path.floor == mapID then
			local xs, ys
			if path.kind == "main" then
				xs, ys = self:DrawMainPath(path, w, h, k)
			else
				xs, ys = self:DrawSidePath(path, w, h, k)
			end
			if editing and xs then
				local active = DR.Editor:IsActivePath(index)
				for i = 1, #xs do
					local size = (active and i == #xs) and 9 / k or 5 / k
					self:Dot(xs[i], ys[i], size, unpack(EDIT_DOT_COLOR))
				end
			end
		end
	end
end

-- Pins ------------------------------------------------------------------------------------

-- Floor changes along the main path get a link pin at both ends, so the next floor is one
-- click away. Explicit links stored in the route are shown as well.
local function collectLinks(route)
	local links = {}
	for _, link in ipairs(route.links or {}) do
		table.insert(links, link)
	end
	local previous
	for _, path in ipairs(route.paths) do
		if path.kind == "main" and #path.pts >= 4 then
			-- a copy of the route for a twin map restarts the gradient; that is no floor change
			local continues = not previous or not path.t0 or not previous.t1 or path.t0 >= previous.t1 - 0.01
			if previous and previous.floor ~= path.floor and continues then
				local pts = previous.pts
				table.insert(links, { floor = previous.floor, x = pts[#pts - 1], y = pts[#pts], to = path.floor, auto = true, forward = true })
				table.insert(links, { floor = path.floor, x = path.pts[1], y = path.pts[2], to = previous.floor, auto = true })
			end
			previous = path
		end
	end
	return links
end

function Provider:AddPins()
	local map, key, route, mapID = self:GetMap(), self.key, self.route, self.mapID
	local labels = DR:GetStopLabels(route)
	local nextIndex = DR:GetNextStopIndex(key, route)
	for i, stop in ipairs(route.stops) do
		if DR.OnFloor(stop, mapID) then
			map:AcquirePin(STOP_PIN, key, route, i, labels[i], i == nextIndex)
		end
	end
	for i, note in ipairs(route.notes) do
		if DR.OnFloor(note, mapID) then
			map:AcquirePin(NOTE_PIN, key, route, i)
		end
	end
	for _, link in ipairs(collectLinks(route)) do
		if link.floor == mapID then
			map:AcquirePin(LINK_PIN, link)
		end
	end
end

function Provider:HighlightStop(index)
	for pin in self:GetMap():EnumeratePinsByTemplate(STOP_PIN) do
		pin:SetHighlighted(pin.index == index)
	end
end

-- Stop pin --------------------------------------------------------------------------------

local KIND_STYLE = {
	boss = { ring = { 0.95, 0.76, 0.31 }, text = { 1.00, 0.91, 0.66 } },
	rare = { ring = { 0.89, 0.87, 0.82 }, text = { 0.89, 0.87, 0.82 } },
	optional = { ring = { 0.62, 0.78, 0.95 }, text = { 0.80, 0.89, 1.00 } },
}

ForeverDungeonRoutesStopPinMixin = CreateFromMixins(MapCanvasPinMixin)

function ForeverDungeonRoutesStopPinMixin:OnLoad()
	self:UseFrameLevelType(PIN_LEVEL, 2)
	self:SetScalingLimits(1, 0.85, 1.2)
end

function ForeverDungeonRoutesStopPinMixin:OnAcquired(key, route, index, label, isNext)
	self.key, self.route, self.index = key, route, index
	local stop = route.stops[index]
	self.stop = stop
	self:SetPosition(stop.x, stop.y)
	local style = KIND_STYLE[stop.kind] or KIND_STYLE.boss
	local done = DR:IsStopDone(key, route, index)
	self.Label:SetText(label)
	self.Label:SetTextColor(style.text[1], style.text[2], style.text[3])
	self.Ring:SetVertexColor(style.ring[1], style.ring[2], style.ring[3])
	self.Fill:SetVertexColor(0.06, 0.05, 0.04, 0.92)
	self.Check:SetShown(done)
	self:SetAlpha(done and 0.55 or 1)
	self.Glow:SetVertexColor(1, 0.85, 0.4, 0.55)
	self.isNext = isNext
	self.Glow:SetShown(isNext and not done)
	self.dragged = nil
end

function ForeverDungeonRoutesStopPinMixin:SetHighlighted(on)
	if on then
		self.Glow:SetVertexColor(1, 1, 1, 0.8)
		self.Glow:Show()
	else
		self.Glow:SetVertexColor(1, 0.85, 0.4, 0.55)
		self.Glow:SetShown(self.isNext and not DR:IsStopDone(self.key, self.route, self.index))
	end
end

function ForeverDungeonRoutesStopPinMixin:OnMouseEnter()
	local stop = self.stop
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local kindText = stop.kind == "rare" and L["Rare"] or stop.kind == "optional" and L["Optional"] or L["Boss"]
	GameTooltip:SetText((stop.name ~= "" and stop.name) or kindText, 1, 0.82, 0)
	if stop.name ~= "" then
		GameTooltip:AddLine(kindText, 0.7, 0.7, 0.7)
	end
	local note = DR.LocText(stop, "note")
	if note and note ~= "" then
		GameTooltip:AddLine(note, 1, 1, 1, true)
	end
	if DR.Editor:IsEditing(self.key, self.route) then
		GameTooltip:AddLine(L["Drag: move  |  Click: options  |  Right-click: delete"], 0.4, 0.8, 1, true)
	else
		GameTooltip:AddLine(L["Click: mark as done"], 0.4, 0.8, 1)
	end
	GameTooltip:Show()
	DR:Fire("STOP_HOVER", self.key, self.index)
end

function ForeverDungeonRoutesStopPinMixin:OnMouseLeave()
	GameTooltip:Hide()
	DR:Fire("STOP_HOVER", self.key, nil)
end

function ForeverDungeonRoutesStopPinMixin:OnMouseDownAction(button)
	if button == "LeftButton" and DR.Editor:IsEditing(self.key, self.route) and not IsShiftKeyDown() then
		DR.Editor:StartDrag(self)
	end
end

function ForeverDungeonRoutesStopPinMixin:OnMouseUpAction(button)
	if self.dragging then
		DR.Editor:StopDrag(self)
	end
end

function ForeverDungeonRoutesStopPinMixin:OnMouseClickAction(button)
	if self.dragged then
		self.dragged = nil
		return
	end
	if DR.Editor:IsEditing(self.key, self.route) then
		DR.Editor:OnStopClicked(self, button)
		return
	end
	if button == "LeftButton" then
		DR:ToggleStopDone(self.key, self.route, self.index)
	end
end

function ForeverDungeonRoutesStopPinMixin:ShouldMouseButtonBePassthrough(button)
	-- Right-click zooms the map out, except while editing where it deletes the stop.
	return button == "RightButton" and not DR.Editor:IsEditing(self.key, self.route)
end

-- Note pin --------------------------------------------------------------------------------

ForeverDungeonRoutesNotePinMixin = CreateFromMixins(MapCanvasPinMixin)

function ForeverDungeonRoutesNotePinMixin:OnLoad()
	self:UseFrameLevelType(PIN_LEVEL, 1)
	self:SetScalingLimits(1, 0.8, 1.1)
	self.Fill:SetVertexColor(0.55, 0.16, 0.14, 0.95)
	self.Edge:SetVertexColor(1, 0.78, 0.7, 1)
end

function ForeverDungeonRoutesNotePinMixin:OnAcquired(key, route, index)
	self.key, self.route, self.index = key, route, index
	self.note = route.notes[index]
	self:SetPosition(self.note.x, self.note.y)
	self.dragged = nil
end

function ForeverDungeonRoutesNotePinMixin:OnMouseEnter()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(L["Note"], 1, 0.82, 0)
	GameTooltip:AddLine(DR.LocText(self.note, "text") or "", 1, 1, 1, true)
	if DR.Editor:IsEditing(self.key, self.route) then
		GameTooltip:AddLine(L["Drag: move  |  Click: edit text  |  Right-click: delete"], 0.4, 0.8, 1, true)
	end
	GameTooltip:Show()
end

function ForeverDungeonRoutesNotePinMixin:OnMouseLeave()
	GameTooltip:Hide()
end

ForeverDungeonRoutesNotePinMixin.OnMouseDownAction = ForeverDungeonRoutesStopPinMixin.OnMouseDownAction
ForeverDungeonRoutesNotePinMixin.OnMouseUpAction = ForeverDungeonRoutesStopPinMixin.OnMouseUpAction
ForeverDungeonRoutesNotePinMixin.ShouldMouseButtonBePassthrough = ForeverDungeonRoutesStopPinMixin.ShouldMouseButtonBePassthrough

function ForeverDungeonRoutesNotePinMixin:OnMouseClickAction(button)
	if self.dragged then
		self.dragged = nil
		return
	end
	if DR.Editor:IsEditing(self.key, self.route) then
		DR.Editor:OnNoteClicked(self, button)
	end
end

-- Link pin --------------------------------------------------------------------------------

ForeverDungeonRoutesLinkPinMixin = CreateFromMixins(MapCanvasPinMixin)

function ForeverDungeonRoutesLinkPinMixin:OnLoad()
	self:UseFrameLevelType(PIN_LEVEL, 1)
	self:SetScalingLimits(1, 0.8, 1.1)
	self.Fill:SetVertexColor(0.12, 0.24, 0.36, 0.95)
	self.Edge:SetVertexColor(0.67, 0.82, 1, 1)
end

local function floorName(mapID)
	local info = C_Map.GetMapInfo(mapID)
	return info and info.name or tostring(mapID)
end

function ForeverDungeonRoutesLinkPinMixin:OnAcquired(link)
	self.link = link
	self:SetPosition(link.x, link.y)
	if link.label and link.label ~= "" then
		self.Label:SetText(link.label)
	else
		self.Label:SetText(link.forward and ">" or "<")
	end
end

function ForeverDungeonRoutesLinkPinMixin:OnMouseEnter()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(self.link.forward and L["Route continues on"] or L["Route comes from"], 1, 0.82, 0)
	GameTooltip:AddLine(floorName(self.link.to), 1, 1, 1)
	GameTooltip:AddLine(L["Click: show this map level"], 0.4, 0.8, 1)
	GameTooltip:Show()
end

function ForeverDungeonRoutesLinkPinMixin:OnMouseLeave()
	GameTooltip:Hide()
end

function ForeverDungeonRoutesLinkPinMixin:OnMouseClickAction(button)
	if button == "LeftButton" and DR.MapHasArt(self.link.to) then
		self:GetMap():SetMapID(self.link.to)
	end
end

-- Setup -----------------------------------------------------------------------------------

function DR:InitMapOverlay()
	self.mapProvider = Provider
	WorldMapFrame:AddDataProvider(Provider)
	self:On("ROUTE_CHANGED", function()
		if WorldMapFrame:IsShown() then
			Provider:RefreshAllData()
		end
	end)
	self:On("PROGRESS_CHANGED", function()
		if WorldMapFrame:IsShown() then
			Provider:RefreshAllData()
		end
	end)
	self:On("HIGHLIGHT_STOP", function(index)
		if Provider.route then
			Provider:HighlightStop(index)
		end
	end)
end

-- Show a stop on the map: switch to its floor and pan there.
function DR:ShowStopOnMap(route, index)
	local stop = route and route.stops[index]
	if not stop then return end
	if not WorldMapFrame:IsShown() then
		ToggleWorldMap()
	end
	if not DR.OnFloor(stop, WorldMapFrame:GetMapID()) then
		if not DR.MapHasArt(stop.floor) then return end
		WorldMapFrame:SetMapID(stop.floor)
	end
	WorldMapFrame:PanAndZoomTo(stop.x, stop.y)
end
