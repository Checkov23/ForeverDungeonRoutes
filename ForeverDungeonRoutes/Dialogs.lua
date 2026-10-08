local _, DR = ...
local L = DR.L

-- One small dialog for everything that needs text: rename, new stop/note, export, import,
-- confirmation. Built from plain frames so it does not depend on optional templates.

local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Buttons\\WHITE8X8",
	edgeSize = 1,
}

local function styleBox(frame, alpha)
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0.07, 0.07, 0.08, alpha or 0.96)
	frame:SetBackdropBorderColor(0.76, 0.66, 0.47, 0.9)
end
DR.StyleBox = styleBox

local dialog

local function build()
	local f = CreateFrame("Frame", "ForeverDungeonRoutesDialog", UIParent, "BackdropTemplate")
	styleBox(f)
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

	f.Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.Title:SetPoint("TOPLEFT", 14, -12)
	f.Title:SetPoint("TOPRIGHT", -14, -12)
	f.Title:SetJustifyH("LEFT")

	f.Text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Text:SetPoint("TOPLEFT", f.Title, "BOTTOMLEFT", 0, -8)
	f.Text:SetPoint("TOPRIGHT", f.Title, "BOTTOMRIGHT", 0, -8)
	f.Text:SetJustifyH("LEFT")
	f.Text:SetSpacing(2)

	-- single line input
	local single = CreateFrame("EditBox", nil, f, "BackdropTemplate")
	styleBox(single, 1)
	single:SetBackdropColor(0, 0, 0, 0.6)
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
	styleBox(scroll, 1)
	scroll:SetBackdropColor(0, 0, 0, 0.6)
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
	f.Cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.Cancel:SetSize(110, 22)
	f.Cancel:SetPoint("RIGHT", f.Accept, "LEFT", -8, 0)
	f.Cancel:SetText(CANCEL or L["Cancel"])
	f.Cancel:SetScript("OnClick", function() f:Hide() end)

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
