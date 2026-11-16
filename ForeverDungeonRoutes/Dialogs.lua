local _, DR = ...
local L = DR.L

-- One small dialog for everything that needs text: rename, new stop/note, export, import,
-- confirmation. Built from plain frames so it does not depend on optional templates.

local dialog

local function build()
	local f = CreateFrame("Frame", "ForeverDungeonRoutesDialog", UIParent, "BackdropTemplate")
	DR.StyleBox(f)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetSize(420, 150)
	f:SetPoint("CENTER", 0, 120)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	f:Hide()
	table.insert(UISpecialFrames, "ForeverDungeonRoutesDialog")
	-- routes from the group wait for the dialog; when it closes the next one may come
	f:SetScript("OnHide", function()
		if DR.Dialog.onHidden then
			DR.Dialog.onHidden()
		end
	end)

	f.Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.Title:SetPoint("TOPLEFT", 14, -12)
	f.Title:SetPoint("TOPRIGHT", -14, -12)
	f.Title:SetJustifyH("LEFT")
	DR.ThemeText(f.Title, "title")

	f.Text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Text:SetPoint("TOPLEFT", f.Title, "BOTTOMLEFT", 0, -8)
	f.Text:SetPoint("TOPRIGHT", f.Title, "BOTTOMRIGHT", 0, -8)
	f.Text:SetJustifyH("LEFT")
	f.Text:SetSpacing(2)
	DR.ThemeText(f.Text, "text")

	-- single line input
	local single = CreateFrame("EditBox", nil, f, "BackdropTemplate")
	DR.StyleBox(single, 1, "input")
	single:SetFontObject(ChatFontNormal)
	single:SetTextInsets(6, 6, 0, 0)
	single:SetHeight(24)
	single:SetAutoFocus(false)
	single:SetMaxLetters(120)
	single:SetScript("OnEscapePressed", function() f:Hide() end)
	single:SetScript("OnEnterPressed", function() f.Accept:Click() end)
	f.Single = single

	-- multi line text with scrolling
	local scroll = CreateFrame("ScrollFrame", nil, f, "BackdropTemplate")
	DR.StyleBox(scroll, 1, "input")
	scroll:EnableMouseWheel(true)
	local multi = CreateFrame("EditBox", nil, scroll)
	multi:SetMultiLine(true)
	multi:SetFontObject(ChatFontNormal)
	multi:SetAutoFocus(false)
	multi:SetMaxLetters(0)
	multi:SetTextInsets(6, 6, 4, 4)
	multi:SetScript("OnEscapePressed", function() f:Hide() end)
	multi:SetScript("OnCursorChanged", function(_, _, y, _, h)
		local offset = scroll:GetVerticalScroll()
		local height = scroll:GetHeight()
		y = -y
		if y < offset then
			scroll:SetVerticalScroll(y)
		elseif y + h > offset + height then
			scroll:SetVerticalScroll(y + h - height)
		end
	end)
	scroll:SetScrollChild(multi)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange()
		self:SetVerticalScroll(DR.Clamp(self:GetVerticalScroll() - delta * 24, 0, range))
	end)
	scroll:SetScript("OnSizeChanged", function(self, width)
		multi:SetWidth(width)
	end)
	scroll:SetScript("OnMouseDown", function() multi:SetFocus() end)
	f.Scroll, f.Multi = scroll, multi

	f.Accept = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.Accept:SetSize(110, 22)
	f.Accept:SetPoint("BOTTOMRIGHT", -12, 12)
	DR.StyleButton(f.Accept, { primary = true })
	f.Cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.Cancel:SetSize(110, 22)
	f.Cancel:SetPoint("RIGHT", f.Accept, "LEFT", -8, 0)
	f.Cancel:SetText(CANCEL or L["Cancel"])
	f.Cancel:SetScript("OnClick", function() f:Hide() end)
	DR.StyleButton(f.Cancel)

	f.Error = f:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
	f.Error:SetPoint("BOTTOMLEFT", 14, 18)
	f.Error:SetPoint("RIGHT", f.Cancel, "LEFT", -8, 0)
	f.Error:SetJustifyH("LEFT")
	return f
end

local function open(opts)
	dialog = dialog or build()
	local f = dialog
	f.Title:SetText(opts.title or "")
	f.Text:SetText(opts.text or "")
	f.Error:SetText("")
	f.Single:Hide()
	f.Scroll:Hide()
	local textHeight = (opts.text and opts.text ~= "") and (f.Text:GetStringHeight() + 8) or 0
	local height = 64 + textHeight
	if opts.mode == "single" then
		f.Single:ClearAllPoints()
		f.Single:SetPoint("TOPLEFT", 14, -(36 + textHeight))
		f.Single:SetPoint("TOPRIGHT", -14, -(36 + textHeight))
		f.Single:SetText(opts.value or "")
		f.Single:Show()
		f.Single:SetFocus()
		f.Single:HighlightText()
		height = height + 34
		f:SetWidth(420)
	elseif opts.mode == "multi" then
		f.Scroll:ClearAllPoints()
		f.Scroll:SetPoint("TOPLEFT", 14, -(36 + textHeight))
		f.Scroll:SetPoint("TOPRIGHT", -14, -(36 + textHeight))
		f.Scroll:SetHeight(180)
		f.Multi:SetWidth(f.Scroll:GetWidth() > 0 and f.Scroll:GetWidth() or 470)
		f.Multi:SetText(opts.value or "")
		f.Scroll:SetVerticalScroll(0)
		f.Scroll:Show()
		f.Multi:SetFocus()
		if opts.selectAll then
			f.Multi:HighlightText()
		end
		height = height + 190
		f:SetWidth(500)
	else
		f:SetWidth(420)
	end
	f:SetHeight(height)
	f.Accept:SetText(opts.acceptText or OKAY or L["OK"])
	f.Accept:SetShown(opts.onAccept ~= nil)
	f.Cancel:SetText(opts.onAccept and (CANCEL or L["Cancel"]) or (CLOSE or L["Close"]))
	f.Accept:SetScript("OnClick", function()
		local value
		if opts.mode == "single" then
			value = strtrim(f.Single:GetText() or "")
		elseif opts.mode == "multi" then
			value = f.Multi:GetText() or ""
		end
		local errorText = opts.onAccept(value)
		if errorText then
			f.Error:SetText(errorText)
		else
			f:Hide()
		end
	end)
	f:Show()
	f:Raise()
end

DR.Dialog = {}

function DR.Dialog.IsShown()
	return dialog ~= nil and dialog:IsShown()
end

function DR.Dialog.AskLine(title, text, value, onAccept)
	open({ mode = "single", title = title, text = text, value = value, onAccept = onAccept })
end

function DR.Dialog.ShowText(title, text, value)
	open({ mode = "multi", title = title, text = text, value = value, selectAll = true })
end

function DR.Dialog.AskText(title, text, onAccept, acceptText)
	open({ mode = "multi", title = title, text = text, value = "", onAccept = onAccept, acceptText = acceptText })
end

function DR.Dialog.Confirm(title, text, onAccept, acceptText)
	open({ title = title, text = text, onAccept = function() onAccept() end, acceptText = acceptText })
end

-- Menus in the game's controller mode -------------------------------------------------------------
-- In controller mode (Forever's gamepad interface) the game steers each of its menus itself. A menu
-- that an addon opens leaves that steering in the addon's hands, and when such a menu closes after a
-- choice the game blocks it: "ForeverDungeonRoutes has been blocked from an action only available to
-- the Blizzard UI" (CurseForge, 15.11.2026: choosing a map in the dropdown with a controller). There
-- the addon shows its menus as a list of its own: the same entries; a submenu opens in its place with
-- a line back at the top. With mouse and keyboard the game's menus stay.

local MEDIA = "Interface\\AddOns\\ForeverDungeonRoutes\\media\\"
local ROW_H = 20 -- height of a line
local ROWS = 20 -- lines per column; a longer list continues in the next column
local PAD = 8
local MIN_W, MAX_W = 140, 420 -- width of a column; longer texts end in "..."

local list -- the frame of the list

-- What a menu generator builds: the part of the game's menu description the addon uses.
local Entry = {}
Entry.__index = Entry

local function newEntry(kind, text, isSelected, onSelect)
	return setmetatable({ kind = kind, text = text, isSelected = isSelected, onSelect = onSelect,
		enabled = true, entries = {} }, Entry)
end

local function add(parent, entry)
	parent.entries[#parent.entries + 1] = entry
	entry.parent = parent
	return entry
end

function Entry:CreateTitle(text) return add(self, newEntry("title", text)) end
function Entry:CreateDivider() return add(self, newEntry("divider")) end
function Entry:CreateButton(text, onClick) return add(self, newEntry("button", text, nil, onClick)) end
function Entry:CreateRadio(text, isSelected, onSelect) return add(self, newEntry("radio", text, isSelected, onSelect)) end
function Entry:CreateCheckbox(text, isSelected, onToggle)
	return add(self, newEntry("checkbox", text, isSelected, onToggle))
end
function Entry:SetEnabled(on) self.enabled = on and true or false end

local function buildList()
	local f = CreateFrame("Frame", "ForeverDungeonRoutesMenu", UIParent, "BackdropTemplate")
	DR.StyleBox(f, 1)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:Hide()
	table.insert(UISpecialFrames, "ForeverDungeonRoutesMenu")
	f.rows = {}
	f.Measure = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Measure:SetPoint("TOPLEFT")
	f.Measure:SetAlpha(0) -- invisible, only measures how wide the texts are
	-- a click anywhere else closes the list; a click on its own button closes it there (DR.Menu.Open)
	f:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
	f:SetScript("OnHide", function(self)
		self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
		self.owner, self.root, self.current = nil, nil, nil
	end)
	f:SetScript("OnEvent", function(self)
		if self:IsMouseOver() or (self.owner and self.owner:IsMouseOver()) then return end
		self:Hide()
	end)
	-- the list belongs to its button: when the button goes (the window closes), the list goes too
	f:SetScript("OnUpdate", function(self)
		if self.owner and not self.owner:IsVisible() then self:Hide() end
	end)
	return f
end

local function row(i)
	if list.rows[i] then return list.rows[i] end
	local r = CreateFrame("Button", nil, list)
	r:SetHeight(ROW_H)
	local light = r:CreateTexture(nil, "HIGHLIGHT")
	light:SetAllPoints()
	light:SetColorTexture(1, 1, 1, 0.12)
	r.Mark = r:CreateTexture(nil, "ARTWORK")
	r.Mark:SetSize(12, 12)
	r.Mark:SetPoint("LEFT", 4, 0)
	r.Dot = r:CreateTexture(nil, "OVERLAY")
	r.Dot:SetSize(12, 12)
	r.Dot:SetPoint("CENTER", r.Mark)
	r.Text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.Text:SetPoint("LEFT", 22, 0)
	r.Text:SetPoint("RIGHT", -16, 0)
	r.Text:SetJustifyH("LEFT")
	r.Text:SetWordWrap(false)
	DR.ThemeText(r.Text)
	r.Arrow = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.Arrow:SetPoint("RIGHT", -4, 0)
	r.Arrow:SetText(">")
	DR.ThemeText(r.Arrow)
	r.Line = r:CreateTexture(nil, "ARTWORK")
	r.Line:SetHeight(1)
	r.Line:SetPoint("LEFT", 4, 0)
	r.Line:SetPoint("RIGHT", -4, 0)
	r:SetScript("OnClick", function(self) DR.Menu.Pick(self.entry) end)
	list.rows[i] = r
	return r
end

local function themeColor(role)
	return DR.Theme()[role] or { 1, 1, 1 }
end

-- One line: a title, a divider, a button (with ">" when it opens a submenu), a radio (ring, dot when
-- chosen), a checkbox (box, tick when on) or the line back out of a submenu.
local function fill(r, entry)
	r.entry = entry
	local kind = entry.kind
	r:SetEnabled(entry.enabled and kind ~= "title" and kind ~= "divider")
	r.Line:SetShown(kind == "divider")
	local muted = themeColor("muted")
	r.Line:SetColorTexture(muted[1], muted[2], muted[3], 0.6)
	r.Text:SetText(kind ~= "divider" and entry.text or "")
	local c = themeColor((kind == "title" or kind == "back") and "title" or entry.enabled and "text" or "muted")
	r.Text:SetTextColor(c[1], c[2], c[3])
	r.Arrow:SetShown(kind == "button" and #entry.entries > 0)
	r.Arrow:SetTextColor(muted[1], muted[2], muted[3])
	local mark = kind == "radio" and "ring" or kind == "checkbox" and "squarering" or nil
	r.Mark:SetShown(mark ~= nil)
	r.Dot:SetShown(false)
	if mark then
		r.Mark:SetTexture(MEDIA .. mark)
		r.Mark:SetVertexColor(c[1], c[2], c[3])
		if entry.isSelected and entry.isSelected() then
			local accent = themeColor("title")
			r.Dot:SetTexture(MEDIA .. (kind == "radio" and "circle" or "check"))
			r.Dot:SetVertexColor(accent[1], accent[2], accent[3])
			r.Dot:SetShown(true)
		end
	end
end

-- Shows the entries of a menu (the root or a submenu), in columns of at most ROWS lines.
local function show(menu)
	list.current = menu
	local items = {}
	if menu ~= list.root then
		items[1] = { kind = "back", text = "< " .. (menu.text or ""), target = menu.parent, enabled = true, entries = {} }
	end
	for _, entry in ipairs(menu.entries) do
		items[#items + 1] = entry
	end
	local columns = math.max(1, math.ceil(#items / ROWS))
	local perColumn = math.ceil(#items / columns)
	local x = PAD
	for col = 1, columns do
		local first, last = (col - 1) * perColumn + 1, math.min(col * perColumn, #items)
		local width = MIN_W
		for i = first, last do
			if items[i].kind ~= "divider" then
				list.Measure:SetText(items[i].text or "")
				width = math.max(width, list.Measure:GetStringWidth() + 46)
			end
		end
		width = math.min(width, MAX_W)
		for i = first, last do
			local r = row(i)
			fill(r, items[i])
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", x, -(PAD + (i - first) * ROW_H))
			r:SetWidth(width)
			r:Show()
		end
		x = x + width + PAD
	end
	for i = #items + 1, #list.rows do
		list.rows[i]:Hide()
	end
	list:SetSize(x, 2 * PAD + perColumn * ROW_H)
end

DR.Menu = {}

function DR.Menu.Open(owner, generator)
	list = list or buildList()
	if list:IsShown() and list.owner == owner then
		list:Hide() -- a second click on its button closes the list
		return
	end
	local root = newEntry("root")
	generator(owner, root)
	list:Hide()
	list.owner, list.root = owner, root
	-- below its button; on the right half of the screen it opens to the left (like the game's menus)
	list:ClearAllPoints()
	local x = owner and owner:GetCenter()
	if not x then
		list:SetPoint("CENTER")
	elseif x * owner:GetEffectiveScale() > UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2 then
		list:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
	else
		list:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
	end
	list:Show()
	show(root)
	list:Raise()
end

function DR.Menu.IsShown()
	return list ~= nil and list:IsShown()
end

function DR.Menu.Pick(entry)
	if not entry or not list or not list:IsShown() then return end
	local kind = entry.kind
	if kind == "back" then
		show(entry.target)
	elseif kind == "title" or kind == "divider" or not entry.enabled then
		return
	elseif #entry.entries > 0 then
		show(entry)
	elseif kind == "checkbox" then
		-- like the game's menu: the box ticks and the menu stays open
		if entry.onSelect then entry.onSelect() end
		if list:IsShown() then show(list.current) end
	else
		-- a choice closes the menu first, so that what it opens (a dialog, another menu) stays open
		list:Hide()
		if entry.onSelect then entry.onSelect() end
	end
end

-- Is the game in controller mode? The same check the game makes before it steers a menu itself
-- (InputUtil.IsGamepadUIEnabled). "/fdr menu" shows the list with the mouse too, to try it.
function DR.ControllerUI()
	if DR.ownMenu then return true end
	local styles = Enum and Enum.InputDeviceInterfaceType
	if not (C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle and styles and styles.Gamepad) then
		return false
	end
	local ok, style = pcall(C_InputInterfaceStyle.GetCurrentStyle)
	return ok and style == styles.Gamepad
end

-- The addon's menus: the game's own, in controller mode the list above.
function DR.OpenMenu(owner, generator)
	if DR.ControllerUI() then
		DR.Menu.Open(owner, generator)
	else
		MenuUtil.CreateContextMenu(owner, generator)
	end
end
