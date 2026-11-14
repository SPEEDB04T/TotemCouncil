-- Totem Council: the totem bar. Four small icons (earth, fire, water, air)
-- with the time left on each; it only gets loud when something is wrong.
local ADDON, ns = ...

local HUD = {}
ns.HUD = HUD

local SIZE, GAP, PIP = 34, 4, 8

local RED = { 1.0, 0.15, 0.15 }
local ORANGE = { 1.0, 0.55, 0.10 }
local YELLOW = { 1.0, 0.85, 0.20 }

local function UseKeyDown()
    local ok, v
    if C_CVar and C_CVar.GetCVarBool then
        ok, v = pcall(C_CVar.GetCVarBool, "ActionButtonUseKeyDown")
    elseif GetCVarBool then
        ok, v = pcall(GetCVarBool, "ActionButtonUseKeyDown")
    end
    return ok and v
end

function HUD.FormatTime(sec)
    if sec < 0 then sec = 0 end
    if sec >= 60 then
        return ("%d:%02d"):format(math.floor(sec / 60), math.floor(sec % 60))
    end
    return ("%d"):format(math.floor(sec + 0.5))
end

local function JoinNames(list)
    return table.concat(list, ", ")
end

----------------------------------------------------------------------
-- Tooltip
----------------------------------------------------------------------
local function OnEnter(self)
    HUD.frame.hover = true
    local slot = self.slot
    local el = ns.ELEMENTS[slot]
    local st = ns.SlotStatus(slot)
    local a = st.active
    local planInfo = st.plan and ns.Info(st.plan)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(el.name .. " totem", el.color[1], el.color[2], el.color[3])
    if a then
        GameTooltip:AddDoubleLine(a.name or "Unknown totem", HUD.FormatTime(st.remaining or 0), 1, 1, 1, 1, 1, 1)
    else
        GameTooltip:AddLine("No totem down", 0.7, 0.7, 0.7)
    end
    if planInfo then
        if st.state == "missing" then
            GameTooltip:AddLine("Missing: " .. planInfo.name, RED[1], RED[2], RED[3])
        elseif st.state == "offplan" then
            GameTooltip:AddLine("Your plan here is " .. planInfo.name, YELLOW[1], YELLOW[2], YELLOW[3])
        end
    else
        GameTooltip:AddLine("Nothing planned: right-click to pick one", 0.7, 0.7, 0.7)
    end
    if st.overlap then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Doubled up: " .. JoinNames(st.overlap) .. " has the same totem down.", ORANGE[1], ORANGE[2], ORANGE[3], true)
    end
    if st.conflict then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Same plan as " .. JoinNames(st.conflict) .. ". Open the group plan to sort it out.", ORANGE[1], ORANGE[2], ORANGE[3], true)
    end
    GameTooltip:AddLine(" ")
    if planInfo and ns.db.clickCast then
        GameTooltip:AddLine("Left-click: drop " .. planInfo.name, 0.5, 0.8, 1)
    end
    GameTooltip:AddLine("Right-click: choose the totem to keep up", 0.5, 0.8, 1)
    if not ns.db.locked then GameTooltip:AddLine("Drag: move the bar (/totems lock)", 0.5, 0.5, 0.5) end
    GameTooltip:Show()
end

local function OnLeave()
    HUD.frame.hover = false
    GameTooltip:Hide()
end

----------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------
function HUD.SavePosition()
    local point, _, relPoint, x, y = HUD.frame:GetPoint()
    ns.db.point = { point, relPoint, x, y }
end

function HUD.RestorePosition()
    local f, p = HUD.frame, ns.db.point
    if not f then return end
    f:ClearAllPoints()
    if p then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
    end
end

local function StartMove()
    local f = HUD.frame
    if not ns.db.locked and not InCombatLockdown() then
        f:StartMoving()
        f.moving = true
    end
end

local function StopMove()
    local f = HUD.frame
    if f.moving then
        f:StopMovingOrSizing()
        f.moving = nil
        HUD.SavePosition()
    end
end

local function CreateButton(f, slot, index)
    local el = ns.ELEMENTS[slot]
    local b = CreateFrame("Button", "TotemCouncilButton" .. slot, f, "SecureActionButtonTemplate")
    b.slot = slot
    b:SetSize(SIZE, SIZE)
    b:SetPoint("LEFT", f, "LEFT", (index - 1) * (SIZE + GAP), 0)
    if UseKeyDown() then b:RegisterForClicks("AnyDown", "AnyUp") else b:RegisterForClicks("AnyUp") end
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", StartMove)
    b:SetScript("OnDragStop", StopMove)

    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", -2, 2)
    b.border:SetPoint("BOTTOMRIGHT", 2, -2)
    b.border:SetColorTexture(1, 1, 1, 1)
    b.border:SetAlpha(0)

    b.bg = b:CreateTexture(nil, "BORDER")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.55)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.12)

    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    b.cd.noCooldownCount = true     -- keep cooldown-text addons off it, the bar draws its own
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
    if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
    if b.cd.SetReverse then b.cd:SetReverse(true) end

    -- text sits on its own frame so it stays above the cooldown sweep
    b.over = CreateFrame("Frame", nil, b)
    b.over:SetAllPoints()
    b.over:SetFrameLevel(b.cd:GetFrameLevel() + 2)

    b.strip = b.over:CreateTexture(nil, "ARTWORK")
    b.strip:SetHeight(2)
    b.strip:SetPoint("BOTTOMLEFT", 0, 0)
    b.strip:SetPoint("BOTTOMRIGHT", 0, 0)
    b.strip:SetColorTexture(el.color[1], el.color[2], el.color[3], 0.9)

    b.timer = b.over:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.timer:SetPoint("CENTER", 0, 0)
    local font, _, flags = b.timer:GetFont()
    if font then b.timer:SetFont(font, 15, flags or "OUTLINE") end

    b.letter = b.over:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.letter:SetPoint("CENTER", 0, 0)
    b.letter:SetText(el.letter)
    b.letter:SetTextColor(el.color[1], el.color[2], el.color[3], 0.7)

    b.badge = b.over:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.badge:SetPoint("TOPRIGHT", 1, 1)

    b.dot = b.over:CreateTexture(nil, "OVERLAY")
    b.dot:SetSize(6, 6)
    b.dot:SetPoint("TOPLEFT", 1, -1)
    b.dot:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 1)
    b.dot:Hide()

    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", OnLeave)
    b:SetScript("PostClick", function(self, button, down)
        if button == "RightButton" and not down then
            local me = ns.Group.members[ns.playerName]
            if me then ns.Menu.OpenTotems(self, me, self.slot) end
        end
    end)
    return b
end

function HUD.Create()
    if HUD.frame or not ns.isShaman then return end
    local f = CreateFrame("Frame", "TotemCouncilHUD", UIParent)
    HUD.frame = f
    f:SetSize(4 * SIZE + 3 * GAP, SIZE)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)

    f.buttons = {}
    for index, slot in ipairs(ns.SLOT_ORDER) do
        f.buttons[slot] = CreateButton(f, slot, index)
    end

    -- small marker that appears when another shaman is in the group; opens the group plan
    local pip = CreateFrame("Button", nil, f)
    f.pip = pip
    pip:SetSize(PIP, SIZE)
    pip:SetPoint("LEFT", f, "RIGHT", 3, 0)
    pip.tex = pip:CreateTexture(nil, "ARTWORK")
    pip.tex:SetAllPoints()
    pip.tex:SetColorTexture(0.5, 0.6, 0.8, 0.7)
    pip:SetScript("OnClick", function() ns.Board.Toggle() end)
    pip:SetScript("OnEnter", function(self)
        f.hover = true
        local G = ns.Group
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Group totem plan")
        GameTooltip:AddLine(("%d other shaman(s) in the group"):format(G.OtherShamans()), 1, 1, 1)
        if G.conflictCount > 0 then
            GameTooltip:AddLine(("%d totem(s) planned twice"):format(G.conflictCount), ORANGE[1], ORANGE[2], ORANGE[3])
        else
            GameTooltip:AddLine("No conflicts", 0.3, 1, 0.3)
        end
        GameTooltip:AddLine("Click to open", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    pip:SetScript("OnLeave", OnLeave)
    pip:Hide()

    HUD.RestorePosition()
    HUD.ApplySecure()   -- decides shown or hidden (after combat, if the UI was reloaded mid-fight)
end

-- Visibility, scale, mouse and click actions. The game blocks these in
-- combat, so they wait for combat to end.
function HUD.ApplySecure()
    local f = HUD.frame
    if not f then return end
    if InCombatLockdown() then
        HUD.pending = true
        return
    end
    HUD.pending = false
    f:SetScale(ns.db.scale or 1)
    for _, slot in ipairs(ns.SLOT_ORDER) do
        local b = f.buttons[slot]
        local known = ns.db.clickCast and ns.Known(ns.cdb.plan[slot]) or nil
        if known then
            b:SetAttribute("type1", "spell")
            b:SetAttribute("spell1", known.name)
        else
            b:SetAttribute("type1", nil)
            b:SetAttribute("spell1", nil)
        end
        b:EnableMouse(not ns.db.clickThrough)
    end
    if ns.db.shown then f:Show() else f:Hide() end
end

----------------------------------------------------------------------
-- Drawing (runs ten times a second; nothing here is blocked in combat)
----------------------------------------------------------------------
local function SetBorder(b, color, alpha)
    if color then
        b.border:SetColorTexture(color[1], color[2], color[3], 1)
        b.border:SetAlpha(alpha)
    else
        b.border:SetAlpha(0)
    end
end

function HUD.Update()
    local f = HUD.frame
    if not f or not f:IsShown() then return end
    if HUD.pending and not InCombatLockdown() then HUD.ApplySecure() end
    local now = GetTime()
    local pulse = 0.35 + 0.65 * math.abs(math.sin(now * 5))
    local slowPulse = 0.5 + 0.5 * math.abs(math.sin(now * 2.5))
    local attention = false
    local soon = ns.db.soonSeconds or 10

    for _, slot in ipairs(ns.SLOT_ORDER) do
        local b = f.buttons[slot]
        local st = ns.SlotStatus(slot)
        local a = st.active
        local planInfo = st.plan and ns.Info(st.plan)

        -- icon
        local icon = (a and a.icon) or (planInfo and planInfo.icon) or nil
        if b.shownIcon ~= icon then
            b.icon:SetTexture(icon)
            b.shownIcon = icon
        end
        if icon then b.icon:Show() else b.icon:Hide() end
        b.letter:SetShown(icon == nil)
        b.icon:SetDesaturated(a == nil)
        b.icon:SetAlpha(a and 1 or (st.warn and 0.9 or 0.4))

        -- sweep
        if b.cdEntry ~= a then
            b.cdEntry = a
            if a then
                b.cd:SetCooldown(a.start, a.duration)
                b.cd:Show()
            else
                b.cd:Hide()
            end
        end

        -- time left
        if a then
            local left = st.remaining or 0
            b.timer:SetText(HUD.FormatTime(left))
            if left <= 5 then
                b.timer:SetTextColor(1, 0.25, 0.25)
            elseif left <= soon then
                b.timer:SetTextColor(1, 0.9, 0.3)
            else
                b.timer:SetTextColor(1, 1, 1)
            end
        else
            b.timer:SetText("")
        end

        -- border and badge, most urgent first
        local badge = ""
        if st.warn then
            SetBorder(b, RED, pulse)
            badge = "|cffff3030!|r"
            attention = true
        elseif st.overlap then
            SetBorder(b, ORANGE, slowPulse)
            badge = ("|cffff9a3cx%d|r"):format(#st.overlap + 1)
            attention = true
        elseif a and ns.inCombat and (st.remaining or 0) <= 5 then
            SetBorder(b, YELLOW, pulse)
        elseif st.state == "offplan" then
            SetBorder(b, YELLOW, 0.55)
        else
            SetBorder(b, nil)
        end
        if b.shownBadge ~= badge then
            b.badge:SetText(badge)
            b.shownBadge = badge
        end
        b.dot:SetShown(st.conflict ~= nil and not st.overlap)
    end

    -- group marker
    local G = ns.Group
    local others = G.OtherShamans() > 0
    f.pip:SetShown(others)
    if others then
        if G.proposal and not G.proposal.doneAt then
            f.pip.tex:SetColorTexture(0.3, 0.6, 1, slowPulse)
        elseif G.conflictCount > 0 then
            f.pip.tex:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.9)
        else
            f.pip.tex:SetColorTexture(0.3, 0.8, 0.4, 0.6)
        end
    end

    local alpha = (attention or ns.inCombat or f.hover) and 1 or (ns.db.idleAlpha or 0.55)
    if f.shownAlpha ~= alpha then
        f:SetAlpha(alpha)
        f.shownAlpha = alpha
    end
end
