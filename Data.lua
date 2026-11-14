-- Totem Council: totem definitions and spell lookups
local ADDON, ns = ...

ns.ADDON = ADDON
ns.VERSION = "1.0.1"

-- WoW Forever hides some values from addons in combat ("secret values").
-- Comparing or indexing one throws, so every API result is checked first.
local issecret = issecretvalue or function() return false end
ns.issecret = issecret

local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- GetTotemInfo slots: 1 fire, 2 earth, 3 water, 4 air. Shown as earth, fire, water, air.
ns.SLOT_ORDER = { 2, 1, 3, 4 }
ns.ELEMENTS = {
    [1] = { name = "Fire",  letter = "F", color = { 1.00, 0.42, 0.18 } },
    [2] = { name = "Earth", letter = "E", color = { 0.55, 0.80, 0.30 } },
    [3] = { name = "Water", letter = "W", color = { 0.30, 0.62, 1.00 } },
    [4] = { name = "Air",   letter = "A", color = { 0.82, 0.78, 1.00 } },
}

-- Keys double as the short codes sent between players, so never rename them.
-- ids: every rank, lowest first. dur: seconds (durs = per rank), only used
-- until the real duration has been read from the game once.
-- stack = true: two of these in one group are not a waste (damage, healing
-- and utility totems), so they never count as a conflict.
ns.TOTEMS = {
    -- Earth
    st = { slot = 2, english = "Strength of Earth Totem", short = "Strength of Earth",
           ids = { 8075, 8160, 8161, 10442, 25361 }, dur = 120, icon = "Spell_Nature_EarthBindTotem" },
    ss = { slot = 2, english = "Stoneskin Totem", short = "Stoneskin",
           ids = { 8071, 8154, 8155, 10406, 10407, 10408 }, dur = 120, icon = "Spell_Nature_StoneSkinTotem" },
    tr = { slot = 2, english = "Tremor Totem", short = "Tremor",
           ids = { 8143 }, dur = 120, icon = "Spell_Nature_TremorTotem" },
    eb = { slot = 2, english = "Earthbind Totem", short = "Earthbind", stack = true,
           ids = { 2484 }, dur = 45, icon = "Spell_Nature_StrengthOfEarthTotem02" },
    sc = { slot = 2, english = "Stoneclaw Totem", short = "Stoneclaw", stack = true,
           ids = { 5730, 6390, 6391, 6392, 10427, 10428 }, dur = 15, icon = "Spell_Nature_StoneClawTotem" },
    -- Fire
    se = { slot = 1, english = "Searing Totem", short = "Searing", stack = true,
           ids = { 3599, 6363, 6364, 6365, 10437, 10438 }, durs = { 30, 35, 40, 45, 50, 55 }, icon = "Spell_Fire_SearingTotem" },
    mg = { slot = 1, english = "Magma Totem", short = "Magma", stack = true,
           ids = { 8190, 10585, 10586, 10587 }, dur = 20, icon = "Spell_Fire_SelfDestruct" },
    fn = { slot = 1, english = "Fire Nova Totem", short = "Fire Nova", stack = true,
           ids = { 1535, 8498, 8499, 11314, 11315 }, dur = 5, icon = "Spell_Fire_SealOfFire" },
    ft = { slot = 1, english = "Flametongue Totem", short = "Flametongue",
           ids = { 8227, 8249, 10526, 16387 }, dur = 120, icon = "Spell_Nature_GuardianWard" },
    fr = { slot = 1, english = "Frost Resistance Totem", short = "Frost Resist",
           ids = { 8181, 10478, 10479 }, dur = 120, icon = "Spell_FrostResistanceTotem_01" },
    -- Water
    ms = { slot = 3, english = "Mana Spring Totem", short = "Mana Spring",
           ids = { 5675, 10495, 10496, 10497 }, dur = 60, icon = "Spell_Nature_ManaRegenTotem" },
    hs = { slot = 3, english = "Healing Stream Totem", short = "Healing Stream", stack = true,
           ids = { 5394, 6375, 6377, 10462, 10463 }, dur = 60, icon = "INV_Spear_04" },
    mt = { slot = 3, english = "Mana Tide Totem", short = "Mana Tide", stack = true,
           ids = { 16190, 17354, 17359 }, dur = 12, icon = "Spell_Frost_SummonWaterElemental" },
    pc = { slot = 3, english = "Poison Cleansing Totem", short = "Poison Cleansing",
           ids = { 8166 }, dur = 120, icon = "Spell_Nature_PoisonCleansingTotem" },
    dc = { slot = 3, english = "Disease Cleansing Totem", short = "Disease Cleansing",
           ids = { 8170 }, dur = 120, icon = "Spell_Nature_DiseaseCleansingTotem" },
    rf = { slot = 3, english = "Fire Resistance Totem", short = "Fire Resist",
           ids = { 8184, 10537, 10538 }, dur = 120, icon = "Spell_FireResistanceTotem_01" },
    -- Air
    wf = { slot = 4, english = "Windfury Totem", short = "Windfury",
           ids = { 8512, 10613, 10614 }, dur = 120, icon = "Spell_Nature_Windfury" },
    ga = { slot = 4, english = "Grace of Air Totem", short = "Grace of Air",
           ids = { 8835, 10627, 25359 }, dur = 120, icon = "Spell_Nature_InvisibilityTotem" },
    ta = { slot = 4, english = "Tranquil Air Totem", short = "Tranquil Air",
           ids = { 25908 }, dur = 120, icon = "Spell_Nature_Brilliance" },
    nr = { slot = 4, english = "Nature Resistance Totem", short = "Nature Resist",
           ids = { 10595, 10600, 10601 }, dur = 120, icon = "Spell_Nature_NatureResistanceTotem" },
    ww = { slot = 4, english = "Windwall Totem", short = "Windwall",
           ids = { 15107, 15111, 15112 }, dur = 120, icon = "Spell_Nature_EarthBind" },
    gr = { slot = 4, english = "Grounding Totem", short = "Grounding", stack = true,
           ids = { 8177 }, dur = 45, icon = "Spell_Nature_GroundingTotem" },
    sn = { slot = 4, english = "Sentry Totem", short = "Sentry", stack = true,
           ids = { 6495 }, dur = 300, icon = "Spell_Nature_RemoveCurse" },
}

-- Menu order, and the order "Sort it out" walks when it looks for a free totem.
ns.BY_SLOT = {
    [1] = { "se", "mg", "fn", "ft", "fr" },
    [2] = { "st", "ss", "tr", "eb", "sc" },
    [3] = { "ms", "hs", "mt", "pc", "dc", "rf" },
    [4] = { "wf", "ga", "ta", "nr", "ww", "gr", "sn" },
}

----------------------------------------------------------------------
-- Spell API (classic-style and modern-style clients)
----------------------------------------------------------------------
function ns.SpellInfo(spell)
    if spell == nil then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spell)
        if ok and type(info) == "table" then return info.name, info.iconID, info.spellID end
        if ok then return nil end
    end
    if GetSpellInfo then
        local ok, name, _, icon, _, _, _, spellID = pcall(GetSpellInfo, spell)
        if ok then return name, icon, spellID end
    end
end

-- true / false, or nil when this client can't tell.
local function PlayerKnows(id)
    local any = false
    local checks = { C_SpellBook and C_SpellBook.IsSpellKnown or false, IsPlayerSpell or false, IsSpellKnown or false }
    for i = 1, #checks do
        local f = checks[i]
        if f then
            any = true
            local ok, known = pcall(f, id)
            if ok and not issecret(known) and known then return true end
        end
    end
    if not any then return nil end
    return false
end

----------------------------------------------------------------------
-- Lookups: spell id -> key, totem name -> key
----------------------------------------------------------------------
local byID, byName = {}, {}
local mapsBuilt, mapsLocalized = false, false
local nextBuild = 0

local function BuildMaps()
    -- while some spell names are still missing, look again every few seconds, not on every lookup
    if mapsBuilt and (mapsLocalized or GetTime() < nextBuild) then return end
    nextBuild = GetTime() + 5
    local allLocalized = true
    for key, def in pairs(ns.TOTEMS) do
        for _, id in ipairs(def.ids) do byID[id] = key end
        byName[def.english:lower()] = key
        local localName = ns.SpellInfo(def.ids[1])
        if type(localName) == "string" and localName ~= "" then
            byName[localName:lower()] = key
        else
            allLocalized = false    -- spell data not loaded yet, try again later
        end
    end
    mapsBuilt, mapsLocalized = true, allLocalized
end

local function LearnedKey(id) return "#" .. id end
local function LearnedID(key) return type(key) == "string" and tonumber(key:match("^#(%d+)$")) or nil end

function ns.KeyBySpellID(id)
    BuildMaps()
    local key = byID[id]
    if key then return key end
    if ns.db and ns.db.learned[id] then return LearnedKey(id) end
end

function ns.KeyByExactName(name)
    if type(name) ~= "string" then return nil end
    BuildMaps()
    return byName[name:lower()]
end

-- GetTotemInfo names can carry a rank ("Searing Totem VI"), so a known name
-- that starts the string also counts; the longest one wins.
function ns.KeyByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    BuildMaps()
    local lower = name:lower()
    if byName[lower] then return byName[lower] end
    local best, bestLen = nil, 0
    for n, key in pairs(byName) do
        local len = #n
        if len > bestLen and lower:sub(1, len) == n then best, bestLen = key, len end
    end
    if best then return best end
    if ns.db then
        for id, l in pairs(ns.db.learned) do
            if type(l.name) == "string" and l.name:lower() == lower then return LearnedKey(id) end
        end
    end
end

-- A totem this addon has no entry for (new in WoW Forever): remember it from
-- the player's own totem slot so it can be planned and shared like the rest.
function ns.Learn(spellID, slot, name, icon, dur)
    if not ns.db or type(spellID) ~= "number" then return nil end
    ns.db.learned[spellID] = { slot = slot, name = name, icon = icon, dur = dur }
    ns.InvalidateKnown()
    return LearnedKey(spellID)
end

local infoCache = {}

-- Display info for any key, whether or not the player knows the totem.
function ns.Info(key)
    if not key then return nil end
    local cached = infoCache[key]
    if cached then return cached end
    local def = ns.TOTEMS[key]
    if def then
        local name, icon = ns.SpellInfo(def.ids[1])
        local info = {
            key = key, slot = def.slot, stack = def.stack and true or false, short = def.short,
            name = name or def.english,
            icon = icon or ("Interface\\Icons\\" .. def.icon),
        }
        if name then infoCache[key] = info end
        return info
    end
    local id = LearnedID(key)
    if id then
        local l = ns.db and ns.db.learned[id]
        local name, icon = ns.SpellInfo(id)
        name = (l and l.name) or name
        if not name then return nil end
        local info = {
            key = key, slot = l and l.slot, stack = false, name = name,
            short = (name:gsub("%s+[Tt]otem.*$", "")),
            icon = (l and l.icon) or icon or QUESTION_MARK,
        }
        if l then infoCache[key] = info end
        return info
    end
end

function ns.ValidKey(key, slot)
    local info = ns.Info(key)
    if not info then return false end
    return slot == nil or info.slot == nil or info.slot == slot
end

----------------------------------------------------------------------
-- What the player can cast
----------------------------------------------------------------------
local knownCache = {}

function ns.InvalidateKnown()
    for k in pairs(knownCache) do knownCache[k] = nil end
    for k in pairs(infoCache) do infoCache[k] = nil end
end

-- { spellID, name, icon } for the highest rank the player knows, or nil.
function ns.Known(key)
    if not key then return nil end
    local cached = knownCache[key]
    if cached ~= nil then return cached or nil end
    local result
    local def = ns.TOTEMS[key]
    if def then
        local knownID
        for i = #def.ids, 1, -1 do
            if PlayerKnows(def.ids[i]) then knownID = def.ids[i]; break end
        end
        if not knownID then
            -- A name lookup only resolves spells in the spellbook (catches new spell ids).
            local names = { def.english }
            local localName = ns.SpellInfo(def.ids[1])
            if localName and localName ~= def.english then table.insert(names, 1, localName) end
            for _, n in ipairs(names) do
                local _, _, id = ns.SpellInfo(n)
                if id and PlayerKnows(id) ~= false then knownID = id; break end
            end
        end
        if knownID then
            local name, icon, id = ns.SpellInfo(knownID)
            local info = ns.Info(key)
            result = { spellID = id or knownID, name = name or info.name, icon = icon or info.icon }
        end
    else
        -- only totems learned from the player's own totem slot count; a "#id"
        -- key made up by someone else must never become something to cast
        local id = LearnedID(key)
        local info = id and ns.Info(key)
        if info and ns.db and ns.db.learned[id] and PlayerKnows(id) ~= false then
            result = { spellID = id, name = info.name, icon = info.icon }
        end
    end
    knownCache[key] = result or false
    return result
end

-- Keys the player can cast for one element, best first.
function ns.KnownList(slot)
    local out = {}
    for _, key in ipairs(ns.BY_SLOT[slot]) do
        if ns.Known(key) then out[#out + 1] = key end
    end
    if ns.db then
        local extra = {}
        for id, l in pairs(ns.db.learned) do
            if l.slot == slot and ns.Known(LearnedKey(id)) then extra[#extra + 1] = LearnedKey(id) end
        end
        table.sort(extra)
        for _, key in ipairs(extra) do out[#out + 1] = key end
    end
    return out
end

----------------------------------------------------------------------
-- Durations: read from the game when possible, built-in numbers otherwise
----------------------------------------------------------------------
function ns.Duration(key, spellID)
    local d = ns.db and ns.db.durations
    if d then
        if spellID and d[spellID] then return d[spellID] end
        -- totems whose ranks last different times (Searing) use the per-rank table below
        if key and d[key] and not (ns.TOTEMS[key] and ns.TOTEMS[key].durs) then return d[key] end
    end
    local def = key and ns.TOTEMS[key]
    if def then
        if def.durs then
            if spellID then
                for i, id in ipairs(def.ids) do
                    if id == spellID and def.durs[i] then return def.durs[i] end
                end
            end
            return def.durs[#def.durs]
        end
        return def.dur or 120
    end
    local id = LearnedID(key)
    local l = id and ns.db and ns.db.learned[id]
    return (l and l.dur) or 120
end

function ns.RememberDuration(key, spellID, dur)
    if not ns.db or type(dur) ~= "number" or dur <= 0 then return end
    if spellID then ns.db.durations[spellID] = dur end
    if key then ns.db.durations[key] = dur end
end
