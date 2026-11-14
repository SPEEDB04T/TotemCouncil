-- Totem Council: settings, the player's own totems, events, slash commands
local ADDON, ns = ...
local issecret = ns.issecret

local defaults = {
    shown = true,
    locked = false,
    scale = 1,
    idleAlpha = 0.55,       -- bar opacity when nothing needs attention
    clickCast = true,       -- left-click an icon to drop the planned totem
    clickThrough = false,   -- bar ignores the mouse completely
    sound = false,          -- soft ping when a planned totem goes missing in combat
    warnAlways = false,     -- warn about missing totems out of combat too
    soonSeconds = 10,       -- timer turns yellow below this
    autoAdopt = true,       -- an empty plan slot adopts the first totem dropped in it
    point = nil,
    boardPoint = nil,
    learned = {},           -- spellID -> { slot, name, icon, dur } for totems not in Data.lua
    durations = {},         -- spellID / key -> seconds, as read from the game
}
local charDefaults = {
    plan = {},              -- [slot] = totem key
}

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff3399ffTotem Council|r: " .. tostring(msg))
end

-- Run something without letting an error repeat every frame in the error log.
local seenErrors, errorCount = {}, 0
function ns.Safe(f, ...)
    local ok, err = pcall(f, ...)
    if ok then return true end
    local msg = issecret(err) and "blocked by a secret value" or tostring(err)
    if not seenErrors[msg] and errorCount < 5 then
        seenErrors[msg] = true
        errorCount = errorCount + 1
        ns.Print("|cffff6060error:|r " .. msg)
    end
    return false
end

----------------------------------------------------------------------
-- The player's own totems
-- ns.active[slot] = { key, spellID, name, rawName, icon, start, duration, castAt, src }
----------------------------------------------------------------------
ns.active = {}
ns.dirty = true

local function SetActive(slot, entry)
    ns.active[slot] = entry
    ns.dirty = true
end

-- Reads one slot from the game. Returns false when the game hides it (secret),
-- true when the slot was readable (ns.active is then exact).
function ns.ReadSlot(slot)
    if not GetTotemInfo then return false end
    local ok, have, name, start, dur, icon, _, spellID = pcall(GetTotemInfo, slot)
    if not ok or issecret(have) or issecret(name) or issecret(start) or issecret(dur) then return false end
    local now = GetTime()
    local cur = ns.active[slot]
    local up = have and type(name) == "string" and name ~= "" and type(start) == "number" and start > 0
        and type(dur) == "number" and dur > 0 and start + dur > now
    if not up then
        -- right after a cast the totem may not be registered yet
        if cur and cur.castAt and now - cur.castAt < 0.6 then return true end
        if cur then SetActive(slot, nil) end
        return true
    end
    local sid = (not issecret(spellID)) and type(spellID) == "number" and spellID > 0 and spellID or nil
    local shownIcon = (not issecret(icon)) and icon or nil
    if cur and cur.rawName == name and math.abs((cur.start + cur.duration) - (start + dur)) < 0.05 then
        cur.src = "read"
        return true
    end
    local key = (sid and ns.KeyBySpellID(sid)) or ns.KeyByName(name)
    if not key and sid then key = ns.Learn(sid, slot, name, shownIcon, dur) end
    local info = key and ns.Info(key)
    if key then ns.RememberDuration(key, sid, dur) end
    SetActive(slot, {
        key = key, spellID = sid, rawName = name,
        name = info and info.name or name,
        icon = shownIcon or (info and info.icon),
        start = start, duration = dur, src = "read",
        castAt = cur and cur.castAt,
    })
    return true
end

function ns.ReadAllSlots()
    for slot = 1, 4 do ns.ReadSlot(slot) end
end

-- The player's own cast is always visible, so it keeps the timers going in
-- places where the totem slots themselves are hidden.
local function OnPlayerCast(spellID)
    local key = ns.KeyBySpellID(spellID)
    local name, icon = ns.SpellInfo(spellID)
    if not key and name then key = ns.KeyByExactName(name) end
    if not key then return end
    local info = ns.Info(key)
    local slot = info and info.slot
    if not slot then return end
    local now = GetTime()
    SetActive(slot, {
        key = key, spellID = spellID,
        name = name or info.name, icon = icon or info.icon,
        start = now, duration = ns.Duration(key, spellID), src = "cast", castAt = now,
    })
    if ns.db.autoAdopt and not ns.cdb.plan[slot] then ns.SetPlan(slot, key) end
    C_Timer.After(0.3, function() ns.Safe(ns.ReadSlot, slot) end)
end

local function OnTotemUpdate(slot)
    if issecret(slot) or type(slot) ~= "number" then
        ns.ReadAllSlots()
        return
    end
    if slot < 1 or slot > 4 then return end
    if ns.ReadSlot(slot) then return end
    -- Hidden slot: something changed. Keep the totem if the player just cast
    -- it, otherwise it died, expired or was replaced.
    local cur = ns.active[slot]
    if not cur then return end
    if cur.castAt and GetTime() - cur.castAt < 0.6 then return end
    C_Timer.After(0.4, function()
        ns.Safe(function()
            if ns.active[slot] ~= cur then return end   -- a new cast took the slot
            if ns.ReadSlot(slot) then return end
            SetActive(slot, nil)
        end)
    end)
end

----------------------------------------------------------------------
-- Plan
----------------------------------------------------------------------
function ns.SetPlan(slot, key)
    if key and not ns.ValidKey(key, slot) then return end
    ns.cdb.plan[slot] = key
    ns.dirty = true
    ns.HUD.ApplySecure()
    ns.Group.BroadcastState()
end

-- Everything the bar needs to draw one element.
function ns.SlotStatus(slot)
    local a, plan = ns.active[slot], ns.cdb.plan[slot]
    local st = { active = a, plan = plan }
    if a then
        st.remaining = a.start + a.duration - GetTime()
        st.state = (plan and a.key ~= plan) and "offplan" or "ok"
    elseif plan then
        st.state = "missing"
    else
        st.state = "empty"
    end
    st.warn = st.state == "missing" and (ns.inCombat or ns.db.warnAlways) or false
    st.overlap = ns.Group.Overlaps(slot)
    st.conflict = ns.Group.PlanConflictsFor(slot)
    return st
end

local function Ping()
    if not ns.db.sound then return end
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.MAP_PING) or 3175, "Master")
end

local wasWarn, wasOverlap = {}, {}
local function CheckAlerts()
    if not ns.isShaman then return end
    for slot = 1, 4 do
        local a, plan = ns.active[slot], ns.cdb.plan[slot]
        local warn = (not a) and plan ~= nil and (ns.inCombat or ns.db.warnAlways)
        if warn and not wasWarn[slot] then Ping() end
        wasWarn[slot] = warn
        local overlap = ns.Group.Overlaps(slot) ~= nil
        if overlap and not wasOverlap[slot] then Ping() end
        wasOverlap[slot] = overlap
    end
end

----------------------------------------------------------------------
-- Update loop
----------------------------------------------------------------------
local driver = CreateFrame("Frame")
local fast, slow = 0, 0

local function Tick(_, elapsed)
    fast = fast + elapsed
    if fast < 0.1 then return end
    slow = slow + fast
    fast = 0
    local now = GetTime()
    for slot = 1, 4 do
        local a = ns.active[slot]
        if a and a.start + a.duration <= now then SetActive(slot, nil) end
    end
    if slow >= 1 then
        slow = 0
        if ns.isShaman then ns.ReadAllSlots() end
        ns.Group.Tick(now)
        ns.dirty = true
    end
    CheckAlerts()
    ns.HUD.Update()
    if ns.dirty then
        ns.dirty = false
        ns.Board.Refresh()
    end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local events = {}

function events.PLAYER_TOTEM_UPDATE(slot)
    if ns.isShaman then OnTotemUpdate(slot) end
end

function events.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
    if issecret(unit) or issecret(spellID) or type(unit) ~= "string" or type(spellID) ~= "number" then return end
    if unit == "player" then
        if ns.isShaman then OnPlayerCast(spellID) end
    elseif unit:find("^party%d+$") or unit:find("^raid%d+$") then
        ns.Group.ObserveCast(unit, spellID)
    end
end

function events.PLAYER_ENTERING_WORLD()
    ns.inCombat = InCombatLockdown() and true or false
    if ns.isShaman then ns.ReadAllSlots() end
    ns.Group.Rebuild()
    ns.HUD.ApplySecure()
end

function events.GROUP_ROSTER_UPDATE()
    ns.Group.Rebuild()
end

function events.PLAYER_REGEN_DISABLED()
    ns.inCombat = true
    ns.dirty = true
end

function events.PLAYER_REGEN_ENABLED()
    ns.inCombat = false
    ns.dirty = true
    ns.HUD.ApplySecure()
end

function events.SPELLS_CHANGED()
    ns.InvalidateKnown()
    ns.HUD.ApplySecure()
    ns.Group.BroadcastState()
end

function events.CHAT_MSG_ADDON(prefix, text, channel, sender)
    ns.Group.OnAddonMessage(prefix, text, channel, sender)
end

local function Init()
    TotemCouncilDB = TotemCouncilDB or {}
    TotemCouncilCharDB = TotemCouncilCharDB or {}
    for k, v in pairs(defaults) do
        if TotemCouncilDB[k] == nil then TotemCouncilDB[k] = type(v) == "table" and {} or v end
    end
    for k, v in pairs(charDefaults) do
        if TotemCouncilCharDB[k] == nil then TotemCouncilCharDB[k] = type(v) == "table" and {} or v end
    end
    ns.db, ns.cdb = TotemCouncilDB, TotemCouncilCharDB

    local _, class = UnitClass("player")
    ns.isShaman = (class == "SHAMAN")
    ns.playerName = UnitName("player")
    ns.inCombat = InCombatLockdown() and true or false

    -- drop plan entries that no longer mean anything
    for slot, key in pairs(ns.cdb.plan) do
        if not ns.ValidKey(key, slot) then ns.cdb.plan[slot] = nil end
    end

    ns.Group.Init()
    ns.HUD.Create()
    ns.Board.Create()

    for ev in pairs(events) do pcall(driver.RegisterEvent, driver, ev) end
    driver:SetScript("OnEvent", function(_, event, ...)
        local handler = events[event]
        if handler then ns.Safe(handler, ...) end
    end)
    driver:SetScript("OnUpdate", function(self, elapsed) ns.Safe(Tick, self, elapsed) end)

    if ns.isShaman and not ns.db.welcomed then
        ns.db.welcomed = true
        ns.Print("drag the totem bar where you want it, then /totems lock. Right-click an icon to pick the totem you want kept up. /totems for more.")
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function() ns.Safe(Init) end)

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
local function OnOff(v) return v and "on" or "off" end

local function Help()
    ns.Print("commands:")
    ns.Print("  /totems  - show or hide the totem bar")
    ns.Print("  /totems plan  - open the group plan (who drops what, conflicts, sort it out)")
    ns.Print("  /totems lock | unlock | scale <0.5-2> | fade <0.1-1>")
    ns.Print("  /totems click  - left-click casts the planned totem (" .. OnOff(ns.db.clickCast) .. ")")
    ns.Print("  /totems mouse  - bar reacts to the mouse (" .. OnOff(not ns.db.clickThrough) .. ")")
    ns.Print("  /totems sound  - ping when a planned totem goes missing (" .. OnOff(ns.db.sound) .. ")")
    ns.Print("  /totems warn  - warn out of combat too (" .. OnOff(ns.db.warnAlways) .. ")")
    ns.Print("  /totems adopt  - empty plan slots adopt what you drop (" .. OnOff(ns.db.autoAdopt) .. ")")
    ns.Print("  /totems clear | status | demo | reset")
end

local function Status()
    for _, slot in ipairs(ns.SLOT_ORDER) do
        local el = ns.ELEMENTS[slot]
        local a, plan = ns.active[slot], ns.cdb.plan[slot]
        local planInfo = plan and ns.Info(plan)
        local hidden = "?"
        if C_Secrets and C_Secrets.ShouldTotemSlotBeSecret then
            local ok, v = pcall(C_Secrets.ShouldTotemSlotBeSecret, slot)
            if ok and not issecret(v) then hidden = v and "hidden" or "readable" end
        end
        ns.Print(("%s: plan %s, active %s (%s), slot %s"):format(el.name,
            planInfo and planInfo.name or "none",
            a and a.name or "none",
            a and (("%ds left, from %s"):format(math.floor(a.start + a.duration - GetTime()), a.src)) or "-",
            hidden))
    end
    ns.Group.PrintStatus()
end

SLASH_TOTEMCOUNCIL1 = "/totems"
SLASH_TOTEMCOUNCIL2 = "/totemcouncil"
SLASH_TOTEMCOUNCIL3 = "/tcouncil"
SlashCmdList.TOTEMCOUNCIL = function(msg)
    if not ns.db then return end
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    local db = ns.db
    if cmd == "plan" or cmd == "group" or cmd == "council" then
        ns.Board.Toggle()
    elseif cmd == "demo" then
        ns.Group.SetDemo(not ns.Group.demo)
        ns.Print(ns.Group.demo and "demo on: two pretend shamans joined your group. /totems demo again to remove them." or "demo off.")
        if ns.Group.demo then ns.Board.Show() end
    elseif cmd == "status" then
        Status()
    elseif cmd == "help" or cmd == "?" then
        Help()
    elseif not ns.isShaman then
        ns.Print("the totem bar is for Shamans. /totems plan opens the group plan.")
    elseif cmd == "" then
        if InCombatLockdown() then ns.Print("can't show or hide the bar in combat.") return end
        db.shown = not db.shown
        ns.HUD.ApplySecure()
    elseif cmd == "lock" or cmd == "unlock" then
        db.locked = (cmd == "lock")
        ns.Print(db.locked and "bar locked." or "bar unlocked: drag an icon to move it.")
    elseif cmd == "scale" then
        local n = tonumber(arg)
        if n and n >= 0.5 and n <= 2 and not InCombatLockdown() then
            db.scale = n
            ns.HUD.ApplySecure()
        else
            ns.Print("usage: /totems scale 1.2 (out of combat)")
        end
    elseif cmd == "fade" or cmd == "alpha" then
        local n = tonumber(arg)
        if n and n >= 0.1 and n <= 1 then
            db.idleAlpha = n
        else
            ns.Print("usage: /totems fade 0.5 (opacity while nothing needs attention)")
        end
    elseif cmd == "click" then
        db.clickCast = not db.clickCast
        ns.HUD.ApplySecure()
        ns.Print("left-click casting " .. OnOff(db.clickCast) .. (InCombatLockdown() and " (applies after combat)" or ""))
    elseif cmd == "mouse" then
        db.clickThrough = not db.clickThrough
        ns.HUD.ApplySecure()
        ns.Print(db.clickThrough and "bar now ignores the mouse. /totems mouse to undo." or "bar reacts to the mouse again.")
    elseif cmd == "sound" then
        db.sound = not db.sound
        ns.Print("missing-totem ping " .. OnOff(db.sound))
    elseif cmd == "warn" then
        db.warnAlways = not db.warnAlways
        ns.Print(db.warnAlways and "warning about missing totems in and out of combat." or "warning about missing totems in combat only.")
    elseif cmd == "adopt" then
        db.autoAdopt = not db.autoAdopt
        ns.Print("adopting dropped totems into empty plan slots " .. OnOff(db.autoAdopt))
    elseif cmd == "clear" then
        for slot = 1, 4 do ns.cdb.plan[slot] = nil end
        ns.dirty = true
        ns.HUD.ApplySecure()
        ns.Group.BroadcastState()
        ns.Print("plan cleared.")
    elseif cmd == "reset" then
        if InCombatLockdown() then ns.Print("can't reset in combat.") return end
        local learned, durations = db.learned, db.durations
        for k in pairs(db) do db[k] = nil end
        for k, v in pairs(defaults) do db[k] = type(v) == "table" and {} or v end
        db.learned, db.durations, db.welcomed = learned, durations, true
        ns.HUD.RestorePosition()
        ns.HUD.ApplySecure()
        ns.Print("settings reset.")
    else
        Help()
    end
end
