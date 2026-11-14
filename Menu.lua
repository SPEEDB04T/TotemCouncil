-- Totem Council: a small pop-up list (built from plain frames, so it works
-- the same on every client and never touches Blizzard's dropdown code)
local ADDON, ns = ...

local Menu = {}
ns.Menu = Menu

local ROW_H, PAD, ICON = 18, 6, 14
local frame, rows = nil, {}

local function Close()
    if frame then frame:Hide() end
end
Menu.Close = Close

local function CreateRow(i)
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(ROW_H)
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.12)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", ICON + 6, 0)
    row.text:SetJustifyH("LEFT")
    row.note = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.note:SetPoint("RIGHT", -2, 0)
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetHeight(1)
    row.line:SetPoint("LEFT", 2, 0)
    row.line:SetPoint("RIGHT", -2, 0)
    row.line:SetColorTexture(1, 1, 1, 0.15)
    row:SetScript("OnClick", function(self)
        local item = self.item
        if not item or item.disabled or item.title or item.separator then return end
        Close()
        if item.func then ns.Safe(item.func) end
    end)
    rows[i] = row
    return row
end

local function Create()
    frame = CreateFrame("Frame", "TotemCouncilMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
        frame:SetBackdropBorderColor(0.4, 0.5, 0.7, 1)
    end
    -- closes by itself shortly after the mouse leaves it
    frame:SetScript("OnUpdate", function(self, elapsed)
        local over = self:IsMouseOver() or (self.anchor and self.anchor.IsMouseOver and self.anchor:IsMouseOver())
        if over then
            self.away = 0
        else
            self.away = (self.away or 0) + elapsed
            if self.away > 1.2 then Close() end
        end
    end)
    -- and at once on a click anywhere else
    pcall(frame.RegisterEvent, frame, "GLOBAL_MOUSE_DOWN")
    frame:SetScript("OnEvent", function(self)
        if self:IsShown() and not self:IsMouseOver() then Close() end
    end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TotemCouncilMenu") end
    frame:Hide()
end

-- items: { text, icon, note, checked, disabled, title, separator, func }
function Menu.Open(anchor, items)
    if not frame then Create() end
    local width, y = 120, -PAD
    for i, item in ipairs(items) do
        local row = rows[i] or CreateRow(i)
        row.item = item
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
        row:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
        if item.separator then
            row:SetHeight(7)
            row.line:Show()
            row.icon:Hide()
            row.text:SetText("")
            row.note:SetText("")
            row:EnableMouse(false)
            y = y - 7
        else
            row:SetHeight(ROW_H)
            row.line:Hide()
            row.text:SetText(item.text or "")
            row.note:SetText(item.note or "")
            if item.icon then
                row.icon:SetTexture(item.icon)
                row.icon:Show()
            else
                row.icon:Hide()
            end
            if item.title then
                row.text:SetTextColor(1, 0.82, 0)
            elseif item.disabled then
                row.text:SetTextColor(0.5, 0.5, 0.5)
            elseif item.checked then
                row.text:SetTextColor(0.3, 1, 0.3)
            else
                row.text:SetTextColor(1, 1, 1)
            end
            row:EnableMouse(not (item.title or item.disabled))
            local w = ICON + 10 + (row.text:GetStringWidth() or 0) + 12 + (row.note:GetStringWidth() or 0)
            if w > width then width = w end
            y = y - ROW_H
        end
        row:Show()
    end
    for i = #items + 1, #rows do rows[i]:Hide() end
    frame:SetSize(width + PAD * 2, -y + PAD)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
    frame.anchor = anchor
    frame.away = 0
    frame:Show()
end

-- The "which totem for this element" list, shared by the bar and the plan window.
-- member = whose totem is being picked; picking for someone else sends a suggestion.
function Menu.OpenTotems(anchor, member, slot)
    local G = ns.Group
    local el = ns.ELEMENTS[slot]
    local own = member.isPlayer
    local items = { { text = own and (el.name .. " totem to keep up") or ("Suggest to " .. member.name), title = true } }
    local current = G.Effective(member, slot)

    -- who else in that subgroup already covers which totem
    local takenBy = {}
    for name, m in pairs(G.members) do
        if m ~= member and m.subgroup == member.subgroup then
            local key = G.Effective(m, slot)
            if key then takenBy[key] = takenBy[key] or name end
        end
    end

    local keys = G.KnownList(member, slot)
    for _, key in ipairs(keys) do
        local info = ns.Info(key)
        if info then
            items[#items + 1] = {
                text = info.name, icon = info.icon, checked = (key == current),
                note = (takenBy[key] and not info.stack) and ("|cffff9a3c" .. takenBy[key] .. "|r") or nil,
                func = function()
                    if own then ns.SetPlan(slot, key) else G.Suggest(member.name, slot, key) end
                end,
            }
        end
    end
    if #keys == 0 then
        items[#items + 1] = { text = "No " .. el.name:lower() .. " totems known", disabled = true }
    end
    if own then
        items[#items + 1] = {
            text = "Nothing", checked = (current == nil),
            func = function() ns.SetPlan(slot, nil) end,
        }
        items[#items + 1] = { separator = true }
        items[#items + 1] = { text = "Group plan...", func = function() ns.Board.Show() end }
    end
    Menu.Open(anchor, items)
end
