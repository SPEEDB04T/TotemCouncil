-- Totem Council: the group plan window (every shaman in the group, what each
-- drops per element, conflicts in red) and the small accept/decline pop-up.
local ADDON, ns = ...

local Board = {}
ns.Board = Board

local ROW_H, CELL, NAME_W, PAD, MAX_ROWS = 40, 30, 150, 12, 12
local COL_W = CELL + 22
local WIDTH = PAD * 2 + NAME_W + 4 * COL_W

local RED = { 1.0, 0.2, 0.2 }
local BLUE = { 0.3, 0.6, 1.0 }

local function Backdrop(f, r, g, b)
    if not f.SetBackdrop then return end
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.04, 0.05, 0.08, 0.94)
    f:SetBackdropBorderColor(r or 0.35, g or 0.5, b or 0.8, 1)
end

local function MakeButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    return b
end

----------------------------------------------------------------------
-- Accept / decline pop-up (one at a time, the rest wait their turn)
----------------------------------------------------------------------
local toast, toastQueue = nil, {}

local function NextToast()
    if not toast or toast:IsShown() then return end
    local req = table.remove(toastQueue, 1)
    if not req then return end
    toast.req = req
    toast.text:SetText(req.text or "")
    if req.icon then
        toast.icon:SetTexture(req.icon)
        toast.icon:Show()
    else
        toast.icon:Hide()
    end
    toast:SetHeight(math.max(74, (toast.text:GetStringHeight() or 30) + 54))
    toast.left = 45
    toast:Show()
end

local function CloseToast(answer)
    local req = toast.req
    toast.req = nil
    toast:Hide()
    if req then
        if answer == "y" and req.onAccept then ns.Safe(req.onAccept) end
        if answer == "n" and req.onDecline then ns.Safe(req.onDecline) end
    end
    NextToast()
end

local function CreateToast()
    toast = CreateFrame("Frame", "TotemCouncilToast", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    toast:SetSize(300, 80)
    toast:SetPoint("TOP", UIParent, "TOP", 0, -170)
    toast:SetFrameStrata("DIALOG")
    toast:EnableMouse(true)
    Backdrop(toast, 0.3, 0.6, 1)
    toast.icon = toast:CreateTexture(nil, "ARTWORK")
    toast.icon:SetSize(28, 28)
    toast.icon:SetPoint("TOPLEFT", 12, -12)
    toast.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toast.text:SetPoint("TOPLEFT", 48, -12)
    toast.text:SetPoint("RIGHT", -12, 0)
    toast.text:SetJustifyH("LEFT")
    toast.text:SetTextColor(0.85, 0.85, 0.85)
    toast.accept = MakeButton(toast, "Accept", 90)
    toast.accept:SetPoint("BOTTOMRIGHT", toast, "BOTTOM", -4, 10)
    toast.accept:SetScript("OnClick", function() CloseToast("y") end)
    toast.decline = MakeButton(toast, "Decline", 90)
    toast.decline:SetPoint("BOTTOMLEFT", toast, "BOTTOM", 4, 10)
    toast.decline:SetScript("OnClick", function() CloseToast("n") end)
    -- an unanswered request counts as declined after 45 seconds
    toast:SetScript("OnUpdate", function(self, elapsed)
        self.left = (self.left or 45) - elapsed
        if self.left <= 0 then CloseToast("n") end
    end)
    toast:Hide()
end

-- req = { text, icon, onAccept, onDecline }
function Board.Toast(req)
    if not toast then CreateToast() end
    toastQueue[#toastQueue + 1] = req
    NextToast()
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local frame, rows = nil, {}

local function CellEnter(self)
    local m, slot = self.member, self.slot
    if not m then return end
    local G = ns.Group
    local el = ns.ELEMENTS[slot]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(m.name .. ": " .. el.name, el.color[1], el.color[2], el.color[3])
    local key = G.Effective(m, slot)
    local info = key and ns.Info(key)
    if G.Fixed(m) then
        GameTooltip:AddLine(info and ("Last seen dropping " .. info.name) or "No totem seen yet", 1, 1, 1)
        GameTooltip:AddLine("No Totem Council: can't take suggestions. Announce posts the plan in chat.", 0.6, 0.6, 0.6, true)
    else
        GameTooltip:AddLine(info and ("Plans " .. info.name) or "Nothing planned", 1, 1, 1)
    end
    local live = m.isPlayer and ns.active[slot] or m.seen[slot]
    if live then
        local liveInfo = ns.Info(live.key)
        local left = m.isPlayer and (live.start + live.duration - GetTime()) or (live.expires - GetTime())
        GameTooltip:AddLine(("Down now: %s (%s)"):format(liveInfo and liveInfo.name or live.name or "a totem",
            ns.HUD.FormatTime(left)), 0.6, 0.9, 0.6)
    end
    local conflict = G.conflictMap[m.name] and G.conflictMap[m.name][slot]
    if conflict then
        GameTooltip:AddLine("Same totem as " .. table.concat(conflict, ", ") .. " in this group.", RED[1], RED[2], RED[3], true)
    end
    local prop = G.proposal
    local line = prop and not prop.doneAt and prop.lines[m.name]
    if line and line[slot] ~= key then
        local newInfo = line[slot] and ns.Info(line[slot])
        GameTooltip:AddLine(("%s proposes: %s"):format(prop.from, newInfo and newInfo.name or "nothing"), BLUE[1], BLUE[2], BLUE[3], true)
    end
    if m.isPlayer then
        GameTooltip:AddLine("Click to change", 0.5, 0.8, 1)
    elseif not G.Fixed(m) then
        GameTooltip:AddLine("Click to suggest a totem", 0.5, 0.8, 1)
    end
    GameTooltip:Show()
end

local function CellClick(self)
    local m = self.member
    if not m or ns.Group.Fixed(m) then return end
    if m.isPlayer and not ns.isShaman then return end
    ns.Menu.OpenTotems(self, m, self.slot)
end

local function CreateRow(i)
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(WIDTH - PAD * 2, ROW_H)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(52 + (i - 1) * ROW_H))
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", 0, -5)
    row.name:SetWidth(NAME_W - 6)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.sub:SetWidth(NAME_W - 6)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    row.cells = {}
    for index, slot in ipairs(ns.SLOT_ORDER) do
        local c = CreateFrame("Button", nil, row)
        c.slot = slot
        c:SetSize(CELL, CELL)
        c:SetPoint("LEFT", row, "LEFT", NAME_W + (index - 1) * COL_W + (COL_W - CELL) / 2, 0)
        c.border = c:CreateTexture(nil, "BACKGROUND")
        c.border:SetPoint("TOPLEFT", -2, 2)
        c.border:SetPoint("BOTTOMRIGHT", 2, -2)
        c.border:SetColorTexture(1, 1, 1, 1)
        c.bg = c:CreateTexture(nil, "BORDER")
        c.bg:SetAllPoints()
        c.bg:SetColorTexture(0, 0, 0, 0.6)
        c.icon = c:CreateTexture(nil, "ARTWORK")
        c.icon:SetAllPoints()
        c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        c.hl = c:CreateTexture(nil, "HIGHLIGHT")
        c.hl:SetAllPoints()
        c.hl:SetColorTexture(1, 1, 1, 0.15)
        c.live = c:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        c.live:SetPoint("BOTTOMRIGHT", 1, 0)
        c:SetScript("OnEnter", CellEnter)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
        c:SetScript("OnClick", CellClick)
        row.cells[slot] = c
    end
    rows[i] = row
    return row
end

function Board.Create()
    if frame then return end
    frame = CreateFrame("Frame", "TotemCouncilBoard", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    Board.frame = frame
    frame:SetSize(WIDTH, 200)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.boardPoint = { point, relPoint, x, y }
    end)
    Backdrop(frame)
    local p = ns.db.boardPoint
    if p then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", PAD, -10)
    frame.title:SetText("Totem Council")

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", 2, 2)

    for index, slot in ipairs(ns.SLOT_ORDER) do
        local el = ns.ELEMENTS[slot]
        local h = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOP", frame, "TOPLEFT", PAD + NAME_W + (index - 1) * COL_W + COL_W / 2, -36)
        h:SetText(el.name)
        h:SetTextColor(el.color[1], el.color[2], el.color[3])
    end

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.empty:SetPoint("TOPLEFT", PAD, -58)
    frame.empty:SetWidth(WIDTH - PAD * 2)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetText("No shamans in your group yet.\n\nWhen another shaman joins, their totems show up here: their plan if they have Totem Council, otherwise whatever they are seen dropping. Totems planned twice in one group turn red.\n\n/totems demo adds two pretend shamans so you can try it.")

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("BOTTOMLEFT", PAD, 40)
    frame.status:SetWidth(WIDTH - PAD * 2)
    frame.status:SetJustifyH("LEFT")

    frame.resolve = MakeButton(frame, "Sort it out", 110)
    frame.resolve:SetPoint("BOTTOMLEFT", PAD, 12)
    frame.resolve:SetScript("OnClick", function() ns.Safe(ns.Group.Propose) end)
    frame.resolve:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Sort it out")
        GameTooltip:AddLine("Works out a plan with no totem dropped twice in one group and sends it to every shaman with Totem Council. Each one accepts or declines their own change.", 1, 1, 1, true)
        GameTooltip:AddLine("Shamans without the addon keep their totems; otherwise the one earlier in the alphabet keeps theirs and the other moves to their next best free totem.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    frame.resolve:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.announce = MakeButton(frame, "Announce", 100)
    frame.announce:SetPoint("LEFT", frame.resolve, "RIGHT", 6, 0)
    frame.announce:SetScript("OnClick", function() ns.Safe(ns.Group.Announce) end)
    frame.announce:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Announce")
        GameTooltip:AddLine("Posts the plan for your group in party or raid chat, one line per shaman, so shamans without the addon can read it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.announce:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.hint:SetPoint("TOPRIGHT", -30, -15)
    frame.hint:SetText("click a totem to change it")

    frame:SetScript("OnShow", function() ns.Safe(Board.Refresh) end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "TotemCouncilBoard") end
    frame:Hide()
end

function Board.Show()
    if not frame then return end
    frame:Show()
end

function Board.Toggle()
    if not frame then return end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

local function SubLabel(m, inRaid)
    local parts = {}
    if inRaid then parts[#parts + 1] = "Group " .. m.subgroup end
    if m.isPlayer then
        parts[#parts + 1] = "you"
    elseif m.demo then
        parts[#parts + 1] = m.hasAddon and "demo, has addon" or "demo, no addon"
    elseif m.hasAddon then
        parts[#parts + 1] = "shared plan"
    else
        parts[#parts + 1] = "no addon, as seen"
    end
    return table.concat(parts, " - ")
end

function Board.Refresh()
    if not frame or not frame:IsShown() then return end
    local G = ns.Group
    local list = G.SortedMembers()
    local inRaid = IsInRaid and IsInRaid() or false
    local prop = G.proposal
    local now = GetTime()
    local shown = math.min(#list, MAX_ROWS)

    for i = 1, shown do
        local m = list[i]
        local row = rows[i] or CreateRow(i)
        row.name:SetText(m.name)
        if m.isPlayer then row.name:SetTextColor(1, 1, 1) else row.name:SetTextColor(0.0, 0.55, 1.0) end
        local sub = SubLabel(m, inRaid)
        local vote = prop and prop.lines[m.name] and prop.votes[m.name]
        if vote == "y" then
            sub = sub .. " - |cff40ff40accepted|r"
        elseif vote == "n" then
            sub = sub .. " - |cffff6060declined|r"
        elseif prop and prop.lines[m.name] and not prop.doneAt then
            sub = sub .. " - |cff4d99ffasked|r"
        end
        row.sub:SetText(sub)
        local line = prop and not prop.doneAt and prop.lines[m.name]
        for _, slot in ipairs(ns.SLOT_ORDER) do
            local c = row.cells[slot]
            c.member = m
            local key = G.Effective(m, slot)
            local proposed = line and line[slot] ~= key
            local showKey = key
            if proposed then showKey = line[slot] end
            local info = showKey and ns.Info(showKey)
            if info then
                c.icon:SetTexture(info.icon)
                c.icon:Show()
            else
                c.icon:Hide()
            end
            c.icon:SetDesaturated(G.Fixed(m))
            local conflict = G.conflictMap[m.name] and G.conflictMap[m.name][slot]
            if proposed then
                c.border:SetColorTexture(BLUE[1], BLUE[2], BLUE[3], 1)
                c.border:Show()
            elseif conflict then
                c.border:SetColorTexture(RED[1], RED[2], RED[3], 1)
                c.border:Show()
            else
                c.border:Hide()
            end
            local live = m.isPlayer and ns.active[slot] or m.seen[slot]
            if live then
                local left = m.isPlayer and (live.start + live.duration - now) or (live.expires - now)
                c.live:SetText(ns.HUD.FormatTime(left))
            else
                c.live:SetText("")
            end
        end
        row:Show()
    end
    for i = shown + 1, #rows do rows[i]:Hide() end

    local alone = #list == 0 or (#list == 1 and list[1].isPlayer)
    frame.empty:SetShown(alone)
    if alone then
        frame.empty:ClearAllPoints()
        frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(58 + shown * ROW_H))
    end
    local others = G.OtherShamans()
    local status
    if prop and not prop.doneAt then
        local yes, total = G.ProposalProgress()
        status = ("|cff4d99ffProposal from %s: %d of %d accepted.|r Blue outlines show the proposed changes."):format(prop.from, yes, total)
    elseif others == 0 then
        status = ""
    elseif G.conflictCount > 0 then
        status = ("|cffff5050%d totem(s) planned twice in one group.|r Red outlines mark them."):format(G.conflictCount)
    else
        status = "|cff40ff40No conflicts.|r Every group gets each totem once."
    end
    if #list > MAX_ROWS then status = status .. (" (+%d more shamans not shown)"):format(#list - MAX_ROWS) end
    local blocked = others > 0 and G.CommsBlocked()
    if blocked then status = status .. "\n|cffaaaaaaPlans can't sync: " .. blocked .. ".|r" end
    frame.status:SetText(status)
    frame.resolve:SetEnabled(others > 0)
    frame.announce:SetEnabled(others > 0)

    local body = math.max(shown, 3) * ROW_H
    if alone then
        body = math.max(body, shown * ROW_H + (frame.empty:GetStringHeight() or 90) + 12)
    end
    frame:SetHeight(52 + body + 84)
end
