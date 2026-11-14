-- Totem Council: the other shamans in the group.
-- Who they are, what they plan (shared between addon users), what they were
-- seen dropping (works without the addon), conflicts, and the back-and-forth
-- that settles them: suggestions to one shaman, proposals to all.
local ADDON, ns = ...
local issecret = ns.issecret

local G = {}
ns.Group = G

local PREFIX = "TotemCouncil"

G.members = {}      -- [name] = { name, unit, subgroup, isPlayer, hasAddon, version, plan, known, seen, habit, demo }
G.byUnit = {}       -- unit token -> name, for every group member
G.names = {}        -- [name] = true for every group member of any class (who may send us messages)
G.pending = {}      -- suggestions this player sent: [id] = { target, slot, key, time }
G.proposal = nil    -- { id, from, lines = { [name] = plan }, votes = { [name] = "y"/"n" }, time, mine, answered, doneAt }
G.conflictMap = {}  -- [name][slot] = { other names planning the same totem }
G.conflictCount = 0

local queue = {}
local slotByLetter = {}
for slot, el in pairs(ns.ELEMENTS) do slotByLetter[el.letter] = slot end

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local function Norm(name)
    if issecret(name) or type(name) ~= "string" or name == "" then return nil end
    if Ambiguate then
        local ok, short = pcall(Ambiguate, name, "none")
        if ok and type(short) == "string" and not issecret(short) then name = short end
    end
    return name
end

local function FullUnitName(unit)
    local ok, name, realm = pcall(UnitName, unit)
    if not ok or issecret(name) or issecret(realm) or type(name) ~= "string" or name == "" then return nil end
    if type(realm) == "string" and realm ~= "" then name = name .. "-" .. realm end
    return Norm(name)
end

-- Names go out with their realm so players from another realm read them right.
local function Qualified(name)
    if name:find("-", 1, true) or not GetNormalizedRealmName then return name end
    local ok, realm = pcall(GetNormalizedRealmName)
    if ok and type(realm) == "string" and realm ~= "" and not issecret(realm) then return name .. "-" .. realm end
    return name
end

local function Split(s, sep)
    local out, pos = {}, 1
    while true do
        local i = s:find(sep, pos, true)
        if not i then
            out[#out + 1] = s:sub(pos)
            break
        end
        out[#out + 1] = s:sub(pos, i - 1)
        pos = i + 1
    end
    return out
end

local idCounter = 0
local function NewID()
    idCounter = idCounter + 1
    return ("%x%x"):format(math.floor(GetTime() * 10) % 65536, idCounter % 256) .. math.random(10, 99)
end

local function NewMember(name)
    return { name = name, subgroup = 1, plan = {}, known = {}, seen = {}, habit = {} }
end

-- Plans travel as "earth,fire,water,air" with "-" for an empty slot.
local function EncodePlan(plan)
    local t = {}
    for i, slot in ipairs(ns.SLOT_ORDER) do t[i] = plan[slot] or "-" end
    return table.concat(t, ",")
end

local function DecodePlan(s)
    local plan = {}
    for i, tok in ipairs(Split(s or "", ",")) do
        local slot = ns.SLOT_ORDER[i]
        if slot and tok ~= "-" and tok ~= "" and ns.ValidKey(tok, slot) then plan[slot] = tok end
    end
    return plan
end

----------------------------------------------------------------------
-- Roster
----------------------------------------------------------------------
-- A shaman without the addon can't be asked to change, so their totems are fixed.
function G.Fixed(m)
    return not (m.isPlayer or m.hasAddon)
end

-- What a shaman is expected to drop: their shared plan, or without the addon
-- the last totem they were seen dropping.
function G.Effective(m, slot)
    if G.Fixed(m) then return m.habit[slot] end
    return m.plan[slot]
end

function G.KnownList(m, slot)
    if m.isPlayer then return ns.KnownList(slot) end
    local out = {}
    local any = next(m.known) ~= nil
    for _, key in ipairs(ns.BY_SLOT[slot]) do
        if not any or m.known[key] then out[#out + 1] = key end
    end
    for key in pairs(m.known) do
        if key:sub(1, 1) == "#" then
            local info = ns.Info(key)
            if info and info.slot == slot then out[#out + 1] = key end
        end
    end
    return out
end

function G.OtherShamans()
    local n = 0
    for _, m in pairs(G.members) do
        if not m.isPlayer then n = n + 1 end
    end
    return n
end

-- Sorted for display: by subgroup, the player first, then by name.
function G.SortedMembers()
    local list = {}
    for _, m in pairs(G.members) do list[#list + 1] = m end
    table.sort(list, function(a, b)
        if a.subgroup ~= b.subgroup then return a.subgroup < b.subgroup end
        if a.isPlayer ~= b.isPlayer then return a.isPlayer and true or false end
        return a.name < b.name
    end)
    return list
end

function G.Recompute()
    local map, count, groups = {}, 0, {}
    for name, m in pairs(G.members) do
        for slot = 1, 4 do
            local key = G.Effective(m, slot)
            local info = key and ns.Info(key)
            if info and not info.stack then
                local id = m.subgroup .. ":" .. slot .. ":" .. key
                local list = groups[id]
                if not list then
                    list = { slot = slot }
                    groups[id] = list
                end
                list[#list + 1] = name
            end
        end
    end
    for _, list in pairs(groups) do
        if #list > 1 then
            count = count + 1
            table.sort(list)
            for _, name in ipairs(list) do
                local others = {}
                for _, other in ipairs(list) do
                    if other ~= name then others[#others + 1] = other end
                end
                map[name] = map[name] or {}
                map[name][list.slot] = others
            end
        end
    end
    G.conflictMap, G.conflictCount = map, count
end

function G.Touch()
    G.Recompute()
    ns.dirty = true
end

function G.Rebuild()
    local old = G.members
    local members, byUnit, names = {}, {}, {}
    local hadOthers = G.OtherShamans()

    local function add(name, unit, subgroup, class)
        name = Norm(name)
        if not name then return end
        byUnit[unit] = name
        names[name] = true
        if class ~= "SHAMAN" then return end
        local m = members[name] or old[name] or NewMember(name)
        m.unit = unit
        m.subgroup = type(subgroup) == "number" and subgroup or 1
        m.isPlayer = (name == ns.playerName)
        members[name] = m
    end

    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local ok, name, _, subgroup, _, _, class = pcall(GetRaidRosterInfo, i)
            if ok and not issecret(name) and not issecret(subgroup) and not issecret(class) then
                add(name, "raid" .. i, subgroup, class)
            end
        end
        -- inside a raid, partyN units are the player's subgroup mates
        for i = 1, 4 do
            local name = FullUnitName("party" .. i)
            if name then byUnit["party" .. i] = name end
        end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. i
            local name = FullUnitName(unit)
            if name then
                local ok, _, class = pcall(UnitClass, unit)
                if ok and not issecret(class) then add(name, unit, 1, class) end
            end
        end
    end

    if ns.isShaman and ns.playerName then
        local m = members[ns.playerName] or old[ns.playerName] or NewMember(ns.playerName)
        m.isPlayer, m.hasAddon, m.version = true, true, ns.VERSION
        m.unit = m.unit or "player"
        m.plan = ns.cdb.plan
        members[ns.playerName] = m
    end

    if G.demo then
        local me = members[ns.playerName]
        local sub = me and me.subgroup or 1
        local kara = old["Demo Kara"] or NewMember("Demo Kara")
        if not kara.demo then
            kara.demo, kara.hasAddon, kara.version = true, true, ns.VERSION
            for slot = 1, 4 do
                kara.plan[slot] = (ns.isShaman and ns.cdb.plan[slot]) or ns.BY_SLOT[slot][1]
            end
        end
        kara.subgroup = sub
        members[kara.name] = kara
        local thok = old["Demo Thok"] or NewMember("Demo Thok")
        if not thok.demo then
            thok.demo = true
            thok.habit = { [2] = "st", [3] = "ms", [4] = "wf" }
        end
        thok.subgroup = sub
        members[thok.name] = thok
    end

    G.members, G.byUnit, G.names = members, byUnit, names
    if G.OtherShamans() > hadOthers then
        -- someone new: ask for their plan and send ours
        G.wantRequest = true
        G.stateDirty = true
    end
    G.Touch()
end

function G.SetDemo(on)
    G.demo = on and true or false
    if not G.demo then G.proposal = nil end
    G.Rebuild()
end

----------------------------------------------------------------------
-- Totems seen on the ground (works for shamans without the addon)
----------------------------------------------------------------------
function G.ObserveCast(unit, spellID)
    local name = G.byUnit[unit]
    local m = name and G.members[name]
    if not m or m.isPlayer then return end
    local key = ns.KeyBySpellID(spellID)
    if not key then
        local spellName = ns.SpellInfo(spellID)
        key = spellName and ns.KeyByExactName(spellName)
    end
    local info = key and ns.Info(key)
    local slot = info and info.slot
    if not slot then return end
    local now = GetTime()
    local s = m.seen[slot]
    if s and s.key == key and now - s.start < 0.5 then return end   -- same cast reported as raidN and partyN
    m.seen[slot] = { key = key, start = now, expires = now + ns.Duration(key, spellID) }
    m.habit[slot] = key
    G.Touch()
end

-- Is this shaman close enough for their totem to matter to the player? The
-- game's own range check is wider than a totem, so it only rules out the
-- clearly far away. Anything it can't tell counts as near.
local function Near(m)
    if m.demo or not m.unit or not UnitInRange then return true end
    local ok, inRange, checked = pcall(UnitInRange, m.unit)
    if not ok or issecret(inRange) or issecret(checked) or not checked then return true end
    return inRange and true or false
end

-- Names of subgroup mates who have the same totem down as the player right now.
function G.Overlaps(slot)
    local a = ns.active[slot]
    if not a or not a.key then return nil end
    local info = ns.Info(a.key)
    if not info or info.stack then return nil end
    local me = G.members[ns.playerName]
    if not me then return nil end
    local now, out = GetTime(), nil
    for name, m in pairs(G.members) do
        if not m.isPlayer and m.subgroup == me.subgroup then
            local s = m.seen[slot]
            if s and s.key == a.key and s.expires > now and Near(m) then
                out = out or {}
                out[#out + 1] = name
            end
        end
    end
    if out then table.sort(out) end
    return out
end

-- Names of subgroup mates who plan the same totem as the player.
function G.PlanConflictsFor(slot)
    local mine = ns.playerName and G.conflictMap[ns.playerName]
    return mine and mine[slot] or nil
end

----------------------------------------------------------------------
-- Sending
----------------------------------------------------------------------
local function AddonChannel()
    if not (IsInGroup and IsInGroup()) then return nil end
    if LE_PARTY_CATEGORY_INSTANCE and LE_PARTY_CATEGORY_HOME
        and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid() then return "RAID" end
    return "PARTY"
end

-- nil when messages can go out, otherwise why not.
function G.CommsBlocked()
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return "this client has no addon messages" end
    if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted then
        local ok, v = pcall(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)
        if ok and not issecret(v) and v then return "this realm blocks addon messages" end
    end
    if C_ChatInfo.InChatMessagingLockdown then
        local ok, v = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and (issecret(v) or v) then return "chat is locked right now (plans sync again afterwards)" end
    end
    return nil
end

local function Enqueue(msg)
    if #queue >= 20 then table.remove(queue, 1) end
    queue[#queue + 1] = msg
end

local function StateMessage()
    local known = {}
    for slot = 1, 4 do
        for _, key in ipairs(ns.KnownList(slot)) do known[#known + 1] = key end
    end
    return "S;" .. ns.VERSION .. ";" .. EncodePlan(ns.cdb.plan) .. ";" .. table.concat(known, ".")
end

-- One message a second at most: the state first, then whatever is queued.
-- The state never goes twice in a row while replies wait, so someone asking
-- for it over and over can't hold them back.
local lastKind, sendErrors = nil, 0
local function Flush()
    local channel = AddonChannel()
    if not channel then
        for i = #queue, 1, -1 do queue[i] = nil end
        G.stateDirty, G.wantRequest = false, false
        return
    end
    if G.OtherShamans() == 0 and #queue == 0 then
        G.stateDirty, G.wantRequest = false, false
        return
    end
    if G.CommsBlocked() then return end
    local msg, kind
    if G.wantRequest then
        msg, kind = "Q", "request"
    elseif G.stateDirty and ns.isShaman and not (lastKind == "state" and #queue > 0) then
        msg, kind = StateMessage(), "state"
    elseif #queue > 0 then
        msg, kind = queue[1], "queue"
    else
        G.stateDirty = false
        return
    end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel)
    if not ok then
        -- the game rejects this very message (too long, malformed): after a few
        -- tries give up on it, so everything behind it is not stuck for good
        sendErrors = sendErrors + 1
        if sendErrors < 3 then return end
    else
        local sent = not (type(result) == "number" and result ~= 0) and result ~= false
        if not sent then return end     -- throttled or refused: try again next second
    end
    sendErrors = 0
    lastKind = kind
    if kind == "request" then
        G.wantRequest = false
    elseif kind == "state" then
        G.stateDirty = false
    else
        table.remove(queue, 1)
    end
end

function G.BroadcastState()
    G.stateDirty = true
    G.Touch()
end

----------------------------------------------------------------------
-- Suggestions: one shaman asks another to change one totem
----------------------------------------------------------------------
function G.Suggest(targetName, slot, key)
    local m = G.members[targetName]
    local info = ns.Info(key)
    if not m or not info then return end
    if G.Fixed(m) then
        ns.Print(targetName .. " doesn't have Totem Council, so they can't get suggestions. Use Announce to post the plan in chat.")
        return
    end
    if m.demo then
        ns.Print(("suggested %s to %s."):format(info.name, targetName))
        C_Timer.After(1.2, function()
            ns.Safe(function()
                m.plan[slot] = key
                ns.Print(("%s accepted: %s."):format(targetName, info.name))
                G.Touch()
            end)
        end)
        return
    end
    local blocked = G.CommsBlocked()
    if blocked then
        ns.Print("can't send the suggestion: " .. blocked .. ".")
        return
    end
    local id = NewID()
    G.pending[id] = { target = targetName, slot = slot, key = key, time = GetTime() }
    Enqueue(("G;%s;%s;%s;%s"):format(id, Qualified(targetName), ns.ELEMENTS[slot].letter, key))
    ns.Print(("suggested %s to %s."):format(info.name, targetName))
end

local lastUnknown = {}   -- [sender] = when they last suggested a totem the player can't cast

local function OnSuggestion(from, id, target, letter, key)
    if not ns.isShaman or Norm(target) ~= ns.playerName then return end
    local slot = slotByLetter[letter or ""]
    local info = slot and ns.ValidKey(key, slot) and ns.Info(key)
    if not info or not id then return end
    if not ns.Known(key) then
        -- answered at most once per sender every 10 seconds, and not in chat mid-fight
        local now = GetTime()
        if now - (lastUnknown[from] or -99) < 10 then return end
        lastUnknown[from] = now
        Enqueue("R;" .. id .. ";n")
        if not ns.inCombat then
            ns.Print(("%s suggested %s, which you don't know."):format(from, info.name))
        end
        return
    end
    if ns.cdb.plan[slot] == key then
        Enqueue("R;" .. id .. ";y")
        return
    end
    ns.Board.Toast({
        text = ("|cffffd200%s|r suggests you drop\n|cffffffff%s|r (%s)"):format(from, info.name, ns.ELEMENTS[slot].name),
        icon = info.icon,
        onAccept = function()
            ns.SetPlan(slot, key)
            Enqueue("R;" .. id .. ";y")
        end,
        onDecline = function()
            Enqueue("R;" .. id .. ";n")
        end,
    })
end

local function OnSuggestionReply(from, id, answer)
    local p = id and G.pending[id]
    if not p or p.target ~= from then return end
    G.pending[id] = nil
    local info = ns.Info(p.key)
    ns.Print(("%s %s your suggestion (%s)."):format(from, answer == "y" and "accepted" or "declined", info and info.name or "?"))
end

----------------------------------------------------------------------
-- Proposals: a conflict-free plan for everyone, each shaman accepts their part
----------------------------------------------------------------------
-- Returns lines = { [name] = new plan } for the shamans who should change,
-- and how many conflicts can't be solved (both sides lack the addon).
function G.Resolve()
    local bySub = {}
    for _, m in pairs(G.members) do
        local list = bySub[m.subgroup] or {}
        bySub[m.subgroup] = list
        list[#list + 1] = m
    end
    local lines, stuck = {}, 0
    for _, list in pairs(bySub) do
        -- shamans who can't be asked keep theirs; after that it's alphabetical,
        -- so every client works out the same answer
        table.sort(list, function(a, b)
            local fa, fb = G.Fixed(a), G.Fixed(b)
            if fa ~= fb then return fa end
            return a.name < b.name
        end)
        for _, slot in ipairs(ns.SLOT_ORDER) do
            local taken, movers = {}, {}
            for _, m in ipairs(list) do
                local want = G.Effective(m, slot)
                local info = want and ns.Info(want)
                if info and not info.stack then
                    if not taken[want] then
                        taken[want] = m
                    elseif G.Fixed(m) then
                        stuck = stuck + 1
                    else
                        movers[#movers + 1] = m
                    end
                end
            end
            for _, m in ipairs(movers) do
                local pick
                for _, key in ipairs(G.KnownList(m, slot)) do
                    if not taken[key] then
                        pick = key
                        break
                    end
                end
                local info = pick and ns.Info(pick)
                if info and not info.stack then taken[pick] = m end
                local line = lines[m.name]
                if not line then
                    line = {}
                    for s = 1, 4 do line[s] = G.Effective(m, s) end
                    lines[m.name] = line
                end
                line[slot] = pick
            end
        end
    end
    return lines, stuck
end

-- only = { [slot] = true }: touch just these slots (nil = all four).
local function ApplyLine(line, only)
    for slot = 1, 4 do
        if not only or only[slot] then
            local key = line[slot]
            if key and not (ns.ValidKey(key, slot) and ns.Known(key)) then key = nil end
            ns.cdb.plan[slot] = key
        end
    end
    ns.HUD.ApplySecure()
    G.BroadcastState()
end

-- What accepting a line would change for the player: the text for the pop-up
-- and the slots it touches. A totem the player can't cast counts as "nothing",
-- exactly as ApplyLine treats it.
local function DescribeLine(line)
    local parts, slots = {}, {}
    for _, slot in ipairs(ns.SLOT_ORDER) do
        local old, new = ns.cdb.plan[slot], line[slot]
        if new and not (ns.ValidKey(new, slot) and ns.Known(new)) then new = nil end
        if old ~= new then
            slots[slot] = true
            local oi, ni = old and ns.Info(old), new and ns.Info(new)
            parts[#parts + 1] = ("%s: %s -> |cffffffff%s|r"):format(ns.ELEMENTS[slot].name,
                oi and oi.short or "nothing", ni and ni.short or "nothing")
        end
    end
    return parts, slots
end

-- yes, no, total over the shamans a proposal asks; those who left the group no longer count.
local function Tally(prop)
    local yes, no, total = 0, 0, 0
    for name in pairs(prop.lines) do
        if G.members[name] then
            total = total + 1
            if prop.votes[name] == "y" then yes = yes + 1 elseif prop.votes[name] == "n" then no = no + 1 end
        end
    end
    return yes, no, total
end

local function ProposalCheckDone(prop)
    if prop.doneAt then return end
    local yes, no, total = Tally(prop)
    if yes + no < total then return end
    prop.doneAt = GetTime()
    if total == 0 then return end
    if no == 0 then
        ns.Print("totem plan agreed by everyone.")
    else
        ns.Print(("totem plan: %d accepted, %d declined."):format(yes, no))
    end
end

-- yes, total, declined: how far a proposal has got.
function G.ProposalProgress()
    local prop = G.proposal
    if not prop then return nil end
    local yes, no, total = Tally(prop)
    return yes, total, no
end

function G.Propose()
    if G.OtherShamans() == 0 then
        ns.Print("there are no other shamans in your group.")
        return
    end
    local lines, stuck = G.Resolve()
    if next(lines) == nil then
        if G.conflictCount == 0 then
            ns.Print("no conflicts: nothing to sort out.")
        else
            ns.Print("the conflicts left are between shamans without the addon, so nobody can be asked to move. Use Announce to post the plan in chat.")
        end
        return
    end
    local needsComms = false
    for name in pairs(lines) do
        local m = G.members[name]
        if m and not m.isPlayer and not m.demo then needsComms = true end
    end
    local blocked = needsComms and G.CommsBlocked()
    if blocked then
        ns.Print("can't send a proposal: " .. blocked .. ".")
        return
    end
    local id = NewID()
    local prop = { id = id, from = ns.playerName, lines = lines, votes = {}, time = GetTime(), mine = true, answered = true }
    G.proposal = prop
    local mine = lines[ns.playerName]
    if mine and ns.isShaman then
        ApplyLine(mine)
        prop.votes[ns.playerName] = "y"
    end
    local head = "P;" .. id
    local chunk = head
    for name, line in pairs(lines) do
        local m = G.members[name]
        if m and m.demo then
            prop.demoAt = GetTime() + 1.5
        else
            local part = ";" .. Qualified(name) .. "=" .. EncodePlan(line)
            if #chunk + #part > 240 then
                Enqueue(chunk)
                chunk = head
            end
            chunk = chunk .. part
        end
    end
    if needsComms and chunk ~= head then Enqueue(chunk) end
    ns.Print("proposed a conflict-free plan. Each shaman accepts their own change.")
    if stuck > 0 then
        ns.Print(("%d conflict(s) involve shamans without the addon and stay as they are."):format(stuck))
    end
    ProposalCheckDone(prop)
    G.Touch()
end

local function OnProposal(from, fields)
    local id = fields[2]
    if not id or id == "" then return end
    local prop = G.proposal
    if not prop or prop.id ~= id then
        prop = { id = id, from = from, lines = {}, votes = {}, time = GetTime() }
        G.proposal = prop
    elseif prop.from ~= from then
        return      -- only the proposer can add to their own proposal
    end
    for i = 3, #fields do
        local name, plan = fields[i]:match("^(.-)=(.*)$")
        name = Norm(name)
        if name and G.members[name] then
            prop.lines[name] = DecodePlan(plan)
            if name == from then prop.votes[name] = "y" end
        end
    end
    local mine = prop.lines[ns.playerName]
    if mine and ns.isShaman and not prop.answered then
        prop.answered = true
        local parts, slots = DescribeLine(mine)
        if #parts == 0 then
            prop.votes[ns.playerName] = "y"
            Enqueue("V;" .. id .. ";y")
        else
            ns.Board.Toast({
                text = ("|cffffd200%s|r proposes a group totem plan. Your part:\n%s"):format(from, table.concat(parts, "\n")),
                -- a proposal that was replaced or ran out is not asked about any more
                valid = function() return G.proposal == prop end,
                onAccept = function()
                    if G.proposal ~= prop then
                        ns.Print("that proposal is out of date. Ask for a new one if it is still needed.")
                        return
                    end
                    ApplyLine(mine, slots)      -- only what the pop-up showed
                    prop.votes[ns.playerName] = "y"
                    Enqueue("V;" .. id .. ";y")
                    ProposalCheckDone(prop)
                    G.Touch()
                end,
                onDecline = function()
                    prop.votes[ns.playerName] = "n"
                    Enqueue("V;" .. id .. ";n")
                    ProposalCheckDone(prop)
                    G.Touch()
                end,
            })
        end
    end
    G.Touch()
end

local function OnVote(from, id, answer)
    local prop = G.proposal
    if not prop or prop.id ~= id or not prop.lines[from] then return end
    prop.votes[from] = (answer == "y") and "y" or "n"
    ProposalCheckDone(prop)
    G.Touch()
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------
function G.OnAddonMessage(prefix, text, channel, sender)
    if issecret(prefix) or issecret(text) or issecret(sender) then return end
    if prefix ~= PREFIX or type(text) ~= "string" then return end
    local from = Norm(sender)
    if not from or from == ns.playerName then return end
    if not G.names[from] then return end    -- only people in the group are listened to
    local f = Split(text, ";")
    local kind = f[1]
    if kind == "S" then
        local m = G.members[from]
        if not m then return end
        -- the version ends up in chat (/totems status): keep it to plain characters
        m.hasAddon, m.version = true, (tostring(f[2] or ""):gsub("[^%w%._%-]", "")):sub(1, 12)
        m.plan = DecodePlan(f[3])
        m.known = {}
        for _, key in ipairs(Split(f[4] or "", ".")) do
            if key ~= "" then m.known[key] = true end
        end
        G.Touch()
    elseif kind == "Q" then
        G.stateDirty = true
    elseif kind == "G" then
        OnSuggestion(from, f[2], f[3], f[4], f[5])
    elseif kind == "R" then
        OnSuggestionReply(from, f[2], f[3])
    elseif kind == "P" then
        OnProposal(from, f)
    elseif kind == "V" then
        OnVote(from, f[2], f[3])
    end
end

----------------------------------------------------------------------
-- Announce: the plan as plain chat, for shamans without the addon
----------------------------------------------------------------------
function G.Announce()
    local channel
    if IsInRaid and IsInRaid() then channel = "RAID" elseif IsInGroup and IsInGroup() then channel = "PARTY" end
    if not channel then
        ns.Print("you're not in a group.")
        return
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return end
    local me = G.members[ns.playerName]
    local sent = 0
    for _, m in ipairs(G.SortedMembers()) do
        if not m.demo and (channel == "PARTY" or not me or m.subgroup == me.subgroup) then
            local parts = {}
            for _, slot in ipairs(ns.SLOT_ORDER) do
                local info = ns.Info(G.Effective(m, slot))
                parts[#parts + 1] = info and info.short or "-"
            end
            -- a non-shaman posts every party, so each line says which one
            local who = m.name
            if channel == "RAID" and not me then who = ("%s (group %d)"):format(who, m.subgroup) end
            local ok = pcall(send, ("Totems - %s: %s"):format(who, table.concat(parts, " / ")), channel)
            if ok then sent = sent + 1 end
        end
    end
    if sent == 0 then ns.Print("nothing to announce.") end
end

----------------------------------------------------------------------
-- Once a second
----------------------------------------------------------------------
function G.Tick(now)
    local changed = false
    for _, m in pairs(G.members) do
        for slot = 1, 4 do
            local s = m.seen[slot]
            if s and s.expires <= now then
                m.seen[slot] = nil
                changed = true
            end
        end
    end
    for id, p in pairs(G.pending) do
        if now - p.time > 60 then G.pending[id] = nil end
    end
    local prop = G.proposal
    if prop then
        if prop.demoAt and now >= prop.demoAt then
            prop.demoAt = nil
            for name, line in pairs(prop.lines) do
                local m = G.members[name]
                if m and m.demo then
                    m.plan = line
                    prop.votes[name] = "y"
                end
            end
            ProposalCheckDone(prop)
            changed = true
        end
        if not prop.doneAt then
            ProposalCheckDone(prop)     -- someone still being waited for may have left the group
            if prop.doneAt then changed = true end
        end
        if (prop.doneAt and now - prop.doneAt > 8) or now - prop.time > 120 then
            if prop.mine and not prop.doneAt then
                local yes, _, total = Tally(prop)
                ns.Print(("your totem proposal ran out of time: %d of %d accepted."):format(yes, total))
            end
            G.proposal = nil
            changed = true
        end
    end
    if G.demo then
        -- the pretend shaman without the addon keeps re-dropping its totems,
        -- and copies the player's air totem to show an overlap
        local thok = G.members["Demo Thok"]
        if thok then
            local air = ns.active[4]
            local airInfo = air and air.key and ns.Info(air.key)
            if airInfo and not airInfo.stack then thok.habit[4] = air.key end
            for slot, key in pairs(thok.habit) do
                if not thok.seen[slot] then
                    thok.seen[slot] = { key = key, start = now, expires = now + 25 }
                    changed = true
                end
            end
        end
    end
    Flush()
    if changed then G.Touch() end
end

function G.Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end
    G.Rebuild()
end

function G.PrintStatus()
    local n = 0
    for _, m in ipairs(G.SortedMembers()) do
        if not m.isPlayer then
            n = n + 1
            local parts = {}
            for _, slot in ipairs(ns.SLOT_ORDER) do
                local info = ns.Info(G.Effective(m, slot))
                parts[#parts + 1] = info and info.short or "-"
            end
            ns.Print(("%s (group %d, %s): %s"):format(m.name, m.subgroup,
                m.hasAddon and ("addon " .. tostring(m.version)) or "no addon, totems as seen",
                table.concat(parts, " / ")))
        end
    end
    if n == 0 then ns.Print("no other shamans in the group.") end
    ns.Print(("plan conflicts: %d. Addon messages: %s."):format(G.conflictCount, G.CommsBlocked() or "ok"))
end
