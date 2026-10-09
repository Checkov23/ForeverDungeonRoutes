local _, DR = ...
local L = DR.L

-- The dungeon map inside the window: the game's own map art, the route on top, stops, notes,
-- floor links, the own position and the group. The art comes in twelve tiles of 256 pixels
-- (4 across, 3 down) of which the map uses the top left 1002 by 668 pixels; route coordinates
-- are 0..1 across that part. Mouse wheel zooms, dragging pans.

local MAP_W, MAP_H = 1002, 668
local TILE = 256
local MAX_ZOOM = 4
local ZOOM_STEP = 1.25
local DRAG_START = 5        -- pixels the mouse moves before a press becomes a pan
local UPDATE_INTERVAL = 0.1 -- seconds between position updates
local MEDIA = "Interface\\AddOns\\ForeverDungeonRoutes\\media\\"

DR.MAP_W, DR.MAP_H = MAP_W, MAP_H

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

local KIND_STYLE = {
	boss = { ring = { 0.95, 0.76, 0.31 }, text = { 1.00, 0.91, 0.66 } },
	rare = { ring = { 0.89, 0.87, 0.82 }, text = { 0.89, 0.87, 0.82 } },
	optional = { ring = { 0.62, 0.78, 0.95 }, text = { 0.80, 0.89, 1.00 } },
}

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

local View = {}
DR.MapView = View

-- Pins ------------------------------------------------------------------------------------

local function editing(pin)
	return DR.Editor:IsEditing(View.key, View.route) and pin.route == View.route
end

local function pinMouseDown(pin, button)
	pin.dragged = nil
	if button == "LeftButton" and editing(pin) and not IsShiftKeyDown() then
		DR.Editor:StartDrag(pin)
	end
end

local function pinMouseUp(pin)
	if pin.dragging then
		DR.Editor:StopDrag(pin)
	end
end

local function stopOnEnter(pin)
	local stop = pin.stop
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	local kindText = stop.kind == "rare" and L["Rare"] or stop.kind == "optional" and L["Optional"] or L["Boss"]
	local name = DR.LocText(stop, "name") or ""
	GameTooltip:SetText(name ~= "" and name or kindText, 1, 0.82, 0)
	if name ~= "" then
		GameTooltip:AddLine(kindText, 0.7, 0.7, 0.7)
	end
	local note = DR.LocText(stop, "note")
	if note and note ~= "" then
		GameTooltip:AddLine(note, 1, 1, 1, true)
	end
	if editing(pin) then
		GameTooltip:AddLine(L["Drag: move\nClick: options\nRight-click: delete"], 0.4, 0.8, 1, true)
	else
		GameTooltip:AddLine(L["Click: mark as done"], 0.4, 0.8, 1)
		if stop.encounters and DR.db.autoCheck then
			GameTooltip:AddLine(L["Ticks itself off when the boss dies."], 0.6, 0.6, 0.6, true)
		end
	end
	GameTooltip:Show()
	DR:Fire("STOP_HOVER", pin.index)
end

local function stopOnLeave()
	GameTooltip:Hide()
	DR:Fire("STOP_HOVER", nil)
end

local function stopOnClick(pin, button)
	if pin.dragged then
		pin.dragged = nil
		return
	end
	if editing(pin) then
		DR.Editor:OnStopClicked(pin, button)
	elseif button == "LeftButton" then
		DR:ToggleStopDone(View.key, pin.route, pin.index)
	end
end

local function createStopPin(view)
	local pin = CreateFrame("Button", nil, view.canvas)
	pin:SetSize(24, 24)
	pin:SetFrameLevel(view.canvas:GetFrameLevel() + 12)
	pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	pin.Glow = pin:CreateTexture(nil, "BACKGROUND")
	pin.Glow:SetTexture(MEDIA .. "glow")
	pin.Glow:SetBlendMode("ADD")
	pin.Glow:SetSize(46, 46)
	pin.Glow:SetPoint("CENTER")
	pin.Fill = pin:CreateTexture(nil, "ARTWORK")
	pin.Fill:SetTexture(MEDIA .. "circle")
	pin.Fill:SetAllPoints()
	pin.Ring = pin:CreateTexture(nil, "OVERLAY", nil, 1)
	pin.Ring:SetTexture(MEDIA .. "ring")
	pin.Ring:SetAllPoints()
	pin.Label = pin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	pin.Label:SetDrawLayer("OVERLAY", 2)
	pin.Label:SetPoint("CENTER", 0, 0)
	pin.Check = pin:CreateTexture(nil, "OVERLAY", nil, 3)
	pin.Check:SetTexture(MEDIA .. "check")
	pin.Check:SetSize(18, 18)
	pin.Check:SetPoint("CENTER", 8, -8)
	pin:SetScript("OnEnter", stopOnEnter)
	pin:SetScript("OnLeave", stopOnLeave)
	pin:SetScript("OnMouseDown", pinMouseDown)
	pin:SetScript("OnMouseUp", pinMouseUp)
	pin:SetScript("OnClick", stopOnClick)
	return pin
end

local function noteOnEnter(pin)
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:SetText(L["Note"], 1, 0.82, 0)
	GameTooltip:AddLine(DR.LocText(pin.note, "text") or "", 1, 1, 1, true)
	if editing(pin) then
		GameTooltip:AddLine(L["Drag: move\nClick: edit text\nRight-click: delete"], 0.4, 0.8, 1, true)
	end
	GameTooltip:Show()
end

local function noteOnClick(pin, button)
	if pin.dragged then
		pin.dragged = nil
		return
	end
	if editing(pin) then
		DR.Editor:OnNoteClicked(pin, button)
	end
end

local function createNotePin(view)
	local pin = CreateFrame("Button", nil, view.canvas)
	pin:SetSize(20, 20)
	pin:SetFrameLevel(view.canvas:GetFrameLevel() + 10)
	pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	pin.Fill = pin:CreateTexture(nil, "ARTWORK")
	pin.Fill:SetTexture(MEDIA .. "diamond")
	pin.Fill:SetAllPoints()
	pin.Fill:SetVertexColor(0.55, 0.16, 0.14, 0.95)
	pin.Edge = pin:CreateTexture(nil, "OVERLAY")
	pin.Edge:SetTexture(MEDIA .. "diamondring")
	pin.Edge:SetAllPoints()
	pin.Edge:SetVertexColor(1, 0.78, 0.7, 1)
	pin.Label = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pin.Label:SetPoint("CENTER", 0, 0)
	pin.Label:SetText("!")
	pin:SetScript("OnEnter", noteOnEnter)
	pin:SetScript("OnLeave", GameTooltip_Hide)
	pin:SetScript("OnMouseDown", pinMouseDown)
	pin:SetScript("OnMouseUp", pinMouseUp)
	pin:SetScript("OnClick", noteOnClick)
	return pin
end

local function linkOnEnter(pin)
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:SetText(pin.link.forward and L["Route continues on"] or L["Route comes from"], 1, 0.82, 0)
	GameTooltip:AddLine(DR:GetFloorName(pin.link.to), 1, 1, 1)
	GameTooltip:AddLine(L["Click: show this map level"], 0.4, 0.8, 1)
	GameTooltip:Show()
end

local function linkOnClick(pin, button)
	if button == "LeftButton" then
		DR.Window:SelectFloor(pin.link.to, true)
	end
end

local function createLinkPin(view)
	local pin = CreateFrame("Button", nil, view.canvas)
	pin:SetSize(20, 20)
	pin:SetFrameLevel(view.canvas:GetFrameLevel() + 10)
	pin:RegisterForClicks("LeftButtonUp")
	pin.Fill = pin:CreateTexture(nil, "ARTWORK")
	pin.Fill:SetTexture(MEDIA .. "square")
	pin.Fill:SetAllPoints()
	pin.Fill:SetVertexColor(0.12, 0.24, 0.36, 0.95)
	pin.Edge = pin:CreateTexture(nil, "OVERLAY")
	pin.Edge:SetTexture(MEDIA .. "squarering")
	pin.Edge:SetAllPoints()
	pin.Edge:SetVertexColor(0.67, 0.82, 1, 1)
	pin.Label = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pin.Label:SetPoint("CENTER", 0, 0)
	pin:SetScript("OnEnter", linkOnEnter)
	pin:SetScript("OnLeave", GameTooltip_Hide)
	pin:SetScript("OnClick", linkOnClick)
	return pin
end

local function createMarker(view, size, level)
	local marker = CreateFrame("Frame", nil, view.canvas)
	marker:SetSize(size, size)
	marker:SetFrameLevel(view.canvas:GetFrameLevel() + level)
	marker:EnableMouse(false)
	marker.Dot = marker:CreateTexture(nil, "ARTWORK")
	marker.Dot:SetTexture(MEDIA .. "circle")
	marker.Dot:SetSize(size * 0.6, size * 0.6)
	marker.Dot:SetPoint("CENTER")
	marker.Ring = marker:CreateTexture(nil, "OVERLAY")
	marker.Ring:SetTexture(MEDIA .. "ring")
	marker.Ring:SetVertexColor(0.05, 0.04, 0.03, 1)
	marker.Ring:SetSize(size * 0.6, size * 0.6)
	marker.Ring:SetPoint("CENTER")
	marker:Hide()
	return marker
end

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
			-- a copy of the route for a twin floor restarts the gradient; that is no floor change
			local continues = not previous or not path.t0 or not previous.t1 or path.t0 >= previous.t1 - 0.01
			if previous and previous.floor ~= path.floor and continues then
				local pts = previous.pts
				table.insert(links, { floor = previous.floor, x = pts[#pts - 1], y = pts[#pts], to = path.floor, forward = true })
				table.insert(links, { floor = path.floor, x = path.pts[1], y = path.pts[2], to = previous.floor })
			end
			previous = path
		end
	end
	return links
end

-- Setup -------------------------------------------------------------------------------------

function View:Create(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetClipsChildren(true)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	self.frame = frame
	local background = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 1)

	local canvas = CreateFrame("Frame", nil, frame)
	canvas:SetSize(MAP_W, MAP_H)
	canvas:SetPoint("TOPLEFT")
	self.canvas = canvas
	self.tiles = {}
	for i = 1, 12 do
		local row, col = math.floor((i - 1) / 4), (i - 1) % 4
		local w = math.min(TILE, MAP_W - col * TILE)
		local h = math.min(TILE, MAP_H - row * TILE)
		local tile = canvas:CreateTexture(nil, "BACKGROUND")
		tile:SetSize(w, h)
		tile:SetPoint("TOPLEFT", canvas, "TOPLEFT", col * TILE, -row * TILE)
		tile:SetTexCoord(0, w / TILE, 0, h / TILE)
		self.tiles[i] = tile
	end

	self.layer = CreateFrame("Frame", nil, canvas)
	self.layer:SetAllPoints(canvas)
	self.layer:SetFrameLevel(canvas:GetFrameLevel() + 1)
	self.lines, self.numLines = {}, 0
	self.dots, self.numDots = {}, 0
	self.stopPins, self.notePins, self.linkPins = {}, {}, {}
	self.numStops, self.numNotes, self.numLinks = 0, 0, 0

	self.player = createMarker(self, 28, 20)
	self.player.Dot:SetVertexColor(1, 0.84, 0.36, 1)
	self.player.Arrow = self.player:CreateTexture(nil, "OVERLAY", nil, 1)
	self.player.Arrow:SetTexture(MEDIA .. "player")
	self.player.Arrow:SetAllPoints()
	self.party = {}

	self.message = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	self.message:SetPoint("CENTER")
	self.message:SetText(L["The game has no map art for this floor."])
	self.message:Hide()
	self.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.status:SetPoint("BOTTOMLEFT", 8, 8)
	self.status:SetPoint("BOTTOMRIGHT", -40, 8)
	self.status:SetJustifyH("LEFT")
	self.status:SetTextColor(0.8, 0.8, 0.8)

	local locate = CreateFrame("Button", nil, frame)
	locate:SetSize(26, 26)
	locate:SetPoint("BOTTOMRIGHT", -6, 6)
	locate:SetFrameLevel(frame:GetFrameLevel() + 40)
	locate.Back = locate:CreateTexture(nil, "BACKGROUND")
	locate.Back:SetTexture(MEDIA .. "circle")
	locate.Back:SetAllPoints()
	locate.Back:SetVertexColor(0.05, 0.05, 0.06, 0.85)
	locate.Icon = locate:CreateTexture(nil, "ARTWORK")
	locate.Icon:SetTexture(MEDIA .. "locate")
	locate.Icon:SetSize(18, 18)
	locate.Icon:SetPoint("CENTER")
	locate.Icon:SetVertexColor(1, 0.84, 0.36)
	locate.Highlight = locate:CreateTexture(nil, "HIGHLIGHT")
	locate.Highlight:SetTexture(MEDIA .. "glow")
	locate.Highlight:SetBlendMode("ADD")
	locate.Highlight:SetAllPoints()
	locate:SetScript("OnClick", function() DR.Window:FollowPlayer() end)
	locate:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_LEFT")
		GameTooltip:SetText(L["Show my position"], 1, 1, 1)
		GameTooltip:AddLine(L["The map follows you to the next floor again."], 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	locate:SetScript("OnLeave", GameTooltip_Hide)
	locate:Hide()
	self.locate = locate

	frame:SetScript("OnSizeChanged", function() View:Layout() end)
	frame:SetScript("OnMouseWheel", function(_, delta) View:OnMouseWheel(delta) end)
	frame:SetScript("OnMouseDown", function(_, button) View:OnMouseDown(button) end)
	frame:SetScript("OnMouseUp", function(_, button) View:OnMouseUp(button) end)
	frame:SetScript("OnUpdate", function(_, elapsed) View:OnUpdate(elapsed) end)
	frame:SetScript("OnHide", function() View.press = nil end)

	self.zoom, self.ox, self.oy, self.fit, self.scale = 1, 0, 0, 1, 1
	self.elapsed = 0

	DR:On("HIGHLIGHT_STOP", function(index) View:HighlightStop(index) end)
	return frame
end

-- Geometry ----------------------------------------------------------------------------------

function View:Layout()
	local w, h = self.frame:GetWidth(), self.frame:GetHeight()
	if not w or w <= 0 or not h or h <= 0 then return end
	self.fit = math.min(w / MAP_W, h / MAP_H)
	self:ApplyTransform(true)
end

-- Places the canvas for the current zoom and pan; the map stays inside the view where it can.
function View:ApplyTransform(redraw)
	local w, h = self.frame:GetWidth(), self.frame:GetHeight()
	if not w or w <= 0 or not h or h <= 0 then return end
	local s = self.fit * self.zoom
	if s <= 0 then return end
	local cw, ch = MAP_W * s, MAP_H * s
	if cw <= w then
		self.ox = (w - cw) / 2
	else
		self.ox = DR.Clamp(self.ox, w - cw, 0)
	end
	if ch <= h then
		self.oy = (h - ch) / 2
	else
		self.oy = DR.Clamp(self.oy, h - ch, 0)
	end
	local rescaled = s ~= self.scale
	self.scale = s
	self.canvas:SetScale(s)
	self.canvas:ClearAllPoints()
	self.canvas:SetPoint("TOPLEFT", self.frame, "TOPLEFT", self.ox / s, -self.oy / s)
	if rescaled or redraw then
		self:PlaceAllPins()
		self:RequestRedraw()
	end
end

function View:CursorInFrame()
	local x, y = GetCursorPosition()
	local scale = self.frame:GetEffectiveScale()
	local left, top = self.frame:GetLeft(), self.frame:GetTop()
	if not left or not top or not scale or scale <= 0 then return nil end
	return x / scale - left, top - y / scale
end

function View:GetCursorUV()
	local fx, fy = self:CursorInFrame()
	if not fx then return nil end
	local s = self.scale
	return (fx - self.ox) / (MAP_W * s), (fy - self.oy) / (MAP_H * s)
end

function View:ZoomAt(fx, fy, factor)
	local zoom = DR.Clamp(self.zoom * factor, 1, MAX_ZOOM)
	if zoom == self.zoom then return end
	local s = self.scale
	local px, py = (fx - self.ox) / s, (fy - self.oy) / s
	local s2 = self.fit * zoom
	self.zoom = zoom
	self.ox, self.oy = fx - px * s2, fy - py * s2
	self:ApplyTransform()
end

-- Centers the map on a point, zooming in to at least the given zoom.
function View:CenterOn(u, v, zoom)
	local w, h = self.frame:GetWidth(), self.frame:GetHeight()
	if not w or w <= 0 then return end
	self.zoom = DR.Clamp(math.max(self.zoom, zoom or 1), 1, MAX_ZOOM)
	local s = self.fit * self.zoom
	self.ox, self.oy = w / 2 - u * MAP_W * s, h / 2 - v * MAP_H * s
	self:ApplyTransform()
end

function View:ResetZoom()
	self.zoom = 1
	self:ApplyTransform()
end

-- Mouse ---------------------------------------------------------------------------------------

function View:OnMouseWheel(delta)
	local fx, fy = self:CursorInFrame()
	if not fx then return end
	self:ZoomAt(fx, fy, delta > 0 and ZOOM_STEP or 1 / ZOOM_STEP)
end

function View:OnMouseDown(button)
	local fx, fy = self:CursorInFrame()
	if not fx then return end
	-- While editing the left button places points, so only the other buttons pan.
	local canPan = button ~= "LeftButton" or not DR.Editor:IsEditing(self.key, self.route)
	self.press = { button = button, fx = fx, fy = fy, ox = self.ox, oy = self.oy, canPan = canPan }
end

function View:OnMouseUp(button)
	local press = self.press
	self.press = nil
	if not press or press.button ~= button or press.moved then return end
	local u, v = self:GetCursorUV()
	if not u then return end
	if DR.Editor:OnMapClick(button, u, v) then return end
	if button == "RightButton" then
		self:ResetZoom()
	end
end

function View:OnUpdate(elapsed)
	local press = self.press
	if press and press.canPan then
		local fx, fy = self:CursorInFrame()
		if fx then
			local dx, dy = fx - press.fx, fy - press.fy
			if not press.moved and math.abs(dx) + math.abs(dy) >= DRAG_START then
				press.moved = true
			end
			if press.moved then
				self.ox, self.oy = press.ox + dx, press.oy + dy
				self:ApplyTransform()
			end
		end
	end
	self.elapsed = self.elapsed + elapsed
	if self.elapsed >= UPDATE_INTERVAL then
		self.elapsed = 0
		self:UpdateGroup()
	end
end

-- Content -------------------------------------------------------------------------------------

function View:SetFloor(key, floor)
	if key ~= self.key or floor ~= self.floor then
		self.key, self.floor = key, floor
		self.zoom = 1
		local info = DR.Floors[floor]
		local hasArt = DR.FloorHasArt(floor)
		for i, tile in ipairs(self.tiles) do
			if hasArt then
				tile:SetTexture(info.tiles[i], nil, nil, "TRILINEAR")
				tile:Show()
			else
				tile:Hide()
			end
		end
		self.message:SetShown(floor ~= nil and not hasArt)
	end
	self:Refresh()
end

function View:Refresh()
	self.route = self.key and DR:GetActiveRoute(self.key)
	self:ReleasePins()
	if self.route and self.floor then
		self:AddPins()
	end
	self:Layout()
	self:UpdateGroup()
end

function View:RequestRedraw()
	if self.redrawPending then return end
	self.redrawPending = true
	C_Timer.After(0, function()
		View.redrawPending = nil
		View:DrawLines()
	end)
end

-- Lines ---------------------------------------------------------------------------------------

function View:ReleaseLines()
	for i = 1, self.numLines do
		self.lines[i]:Hide()
	end
	self.numLines = 0
	for i = 1, self.numDots do
		self.dots[i]:Hide()
	end
	self.numDots = 0
end

function View:Segment(subLevel, x1, y1, x2, y2, thickness, r, g, b, a)
	self.numLines = self.numLines + 1
	local line = self.lines[self.numLines]
	if not line then
		line = self.layer:CreateLine(nil, "ARTWORK")
		self.lines[self.numLines] = line
	end
	line:SetDrawLayer("ARTWORK", subLevel)
	line:SetStartPoint("TOPLEFT", self.layer, x1, -y1)
	line:SetEndPoint("TOPLEFT", self.layer, x2, -y2)
	line:SetThickness(thickness)
	line:SetColorTexture(r, g, b, a or 1)
	line:Show()
	return line
end

function View:Dot(x, y, size, r, g, b, a)
	self.numDots = self.numDots + 1
	local dot = self.dots[self.numDots]
	if not dot then
		dot = self.layer:CreateTexture(nil, "OVERLAY")
		dot:SetTexture(MEDIA .. "circle")
		self.dots[self.numDots] = dot
	end
	dot:ClearAllPoints()
	dot:SetPoint("CENTER", self.layer, "TOPLEFT", x, -y)
	dot:SetSize(size, size)
	dot:SetVertexColor(r, g, b, a or 1)
	dot:Show()
	return dot
end

local function toCanvas(pts)
	local xs, ys = {}, {}
	for i = 1, #pts / 2 do
		xs[i] = pts[2 * i - 1] * MAP_W
		ys[i] = pts[2 * i] * MAP_H
	end
	return xs, ys
end

-- k is the canvas scale: widths are given in screen units and divided by it, so lines keep their
-- width on screen while zooming.
function View:DrawMainPath(path, k)
	local xs, ys = toCanvas(path.pts)
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

function View:DrawSidePath(path, k)
	local xs, ys = toCanvas(path.pts)
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

function View:DrawLines()
	self:ReleaseLines()
	local route, floor = self.route, self.floor
	if not route or not floor then return end
	local k = self.scale
	if not k or k <= 0 then return end
	local editingRoute = DR.Editor:IsEditing(self.key, route)
	for index, path in ipairs(route.paths) do
		if path.floor == floor then
			local xs, ys
			if path.kind == "main" then
				xs, ys = self:DrawMainPath(path, k)
			else
				xs, ys = self:DrawSidePath(path, k)
			end
			if editingRoute and xs then
				local active = DR.Editor:IsActivePath(index)
				for i = 1, #xs do
					local size = (active and i == #xs) and 9 / k or 5 / k
					self:Dot(xs[i], ys[i], size, unpack(EDIT_DOT_COLOR))
				end
			end
		end
	end
end

-- Pins ----------------------------------------------------------------------------------------

function View:PlacePin(pin, u, v)
	pin.u, pin.v = u, v
	local s = self.scale
	pin:SetScale(1 / s)
	pin:ClearAllPoints()
	pin:SetPoint("CENTER", self.canvas, "TOPLEFT", u * MAP_W * s, -v * MAP_H * s)
end

local function eachPin(view, fn)
	for i = 1, view.numStops do fn(view.stopPins[i]) end
	for i = 1, view.numNotes do fn(view.notePins[i]) end
	for i = 1, view.numLinks do fn(view.linkPins[i]) end
end

function View:PlaceAllPins()
	eachPin(self, function(pin) self:PlacePin(pin, pin.u, pin.v) end)
	if self.player:IsShown() and self.player.u then
		self:PlacePin(self.player, self.player.u, self.player.v)
	end
	for _, dot in ipairs(self.party) do
		if dot:IsShown() and dot.u then
			self:PlacePin(dot, dot.u, dot.v)
		end
	end
end

function View:ReleasePins()
	-- "dragged" stays: the click that ends a drag arrives after the pins were drawn again
	eachPin(self, function(pin)
		pin:Hide()
		pin:SetScript("OnUpdate", nil)
		pin.dragging = nil
	end)
	self.numStops, self.numNotes, self.numLinks = 0, 0, 0
end

local function acquire(view, list, countKey, create)
	view[countKey] = view[countKey] + 1
	local pin = list[view[countKey]]
	if not pin then
		pin = create(view)
		list[view[countKey]] = pin
	end
	pin:Show()
	return pin
end

function View:AddPins()
	local key, route, floor = self.key, self.route, self.floor
	local labels = DR:GetStopLabels(route)
	local nextIndex = DR:GetNextStopIndex(key, route)
	for i, stop in ipairs(route.stops) do
		if DR.OnFloor(stop, floor) then
			local pin = acquire(self, self.stopPins, "numStops", createStopPin)
			pin.route, pin.index, pin.stop = route, i, stop
			local style = KIND_STYLE[stop.kind] or KIND_STYLE.boss
			local done = DR:IsStopDone(key, route, i)
			pin.Label:SetText(labels[i])
			pin.Label:SetTextColor(style.text[1], style.text[2], style.text[3])
			pin.Ring:SetVertexColor(style.ring[1], style.ring[2], style.ring[3])
			pin.Fill:SetVertexColor(0.06, 0.05, 0.04, 0.92)
			pin.Check:SetShown(done)
			pin:SetAlpha(done and 0.55 or 1)
			pin.isNext = i == nextIndex and not done
			pin.Glow:SetVertexColor(1, 0.85, 0.4, 0.55)
			pin.Glow:SetShown(pin.isNext)
			self:PlacePin(pin, stop.x, stop.y)
		end
	end
	for i, note in ipairs(route.notes) do
		if DR.OnFloor(note, floor) then
			local pin = acquire(self, self.notePins, "numNotes", createNotePin)
			pin.route, pin.index, pin.note = route, i, note
			self:PlacePin(pin, note.x, note.y)
		end
	end
	for _, link in ipairs(collectLinks(route)) do
		if link.floor == floor and DR:GetDungeonForFloor(link.to) == DR:GetDungeon(key) then
			local pin = acquire(self, self.linkPins, "numLinks", createLinkPin)
			pin.link = link
			if link.label and link.label ~= "" then
				pin.Label:SetText(link.label)
			else
				pin.Label:SetText(link.forward and ">" or "<")
			end
			self:PlacePin(pin, link.x, link.y)
		end
	end
end

function View:HighlightStop(index)
	for i = 1, self.numStops do
		local pin = self.stopPins[i]
		if pin.index == index then
			pin.Glow:SetVertexColor(1, 1, 1, 0.8)
			pin.Glow:Show()
		else
			pin.Glow:SetVertexColor(1, 0.85, 0.4, 0.55)
			pin.Glow:SetShown(pin.isNext)
		end
	end
end

-- Own position and group ----------------------------------------------------------------------

function View:SetStatus(text)
	self.status:SetText(text or "")
	self.status:SetShown(text ~= nil)
end

function View:HideGroup()
	self.player:Hide()
	for _, dot in ipairs(self.party) do
		dot:Hide()
	end
end

function View:UpdateGroup()
	local inside = self.key ~= nil and self.key == DR.currentKey
	self.locate:SetShown(inside)
	if not inside or not DR.db.showPlayer then
		self:HideGroup()
		self:SetStatus(nil)
		return
	end
	local _, floor, u, v = DR:LocatePlayer(self.floor)
	if not floor then
		self:HideGroup()
		local x = DR:GetUnitWorldPosition("player")
		self:SetStatus(not x and L["The game does not reveal your position here."] or nil)
		return
	end
	self:SetStatus(nil)
	if floor ~= self.floor then
		if DR.Window:IsFollowing() then
			DR.Window:SelectFloor(floor)
			return
		end
		self.player:Hide()
	else
		local player = self.player
		local facing = DR:GetPlayerFacing()
		player.Arrow:SetShown(facing ~= nil)
		player.Dot:SetShown(facing == nil)
		player.Ring:SetShown(facing == nil)
		if facing then
			player.Arrow:SetRotation(facing)
		end
		player:Show()
		self:PlacePin(player, u, v)
	end
	local members = DR:GroupOnFloor(self.floor)
	for i, member in ipairs(members) do
		local dot = self.party[i]
		if not dot then
			dot = createMarker(self, 18, 19)
			self.party[i] = dot
		end
		dot.Dot:SetVertexColor(member.r, member.g, member.b, 1)
		dot:Show()
		self:PlacePin(dot, member.u, member.v)
	end
	for i = #members + 1, #self.party do
		self.party[i]:Hide()
	end
end

-- Where the player stands on the shown floor, if known.
function View:GetPlayerUV()
	if self.player:IsShown() then
		return self.player.u, self.player.v
	end
	return nil
end
