--[[
    DamageTracker - Combat Statistics Tracker for WoW 1.12

    Tracks all damage dealt, hits, misses, resists, and other combat stats.
    Designed for comparing gear effectiveness.
    Data persists between sessions via SavedVariables.

    Usage:
        /dmg              - Show current session statistics
        /dmg reset        - Reset current session
        /dmg spells       - Show per-spell breakdown
        /dmg melee        - Show melee statistics
        /dmg session      - Show session summary with timing
        /dmg save [name]  - Save current stats as named snapshot
        /dmg history      - Show past sessions
        /dmg snapshots    - List saved snapshots
        /dmg compare <a> <b> - Compare two snapshots
        /dmg load <name>  - Load a snapshot to view
        /dmg delete <name> - Delete a snapshot
        /dmg lifetime     - Show all-time cumulative stats
        /dmg help         - Show all commands
]]

DamageTracker1701 = {}

-- SavedVariables database (initialized on load)
DamageTrackerDB = nil

-- Character identifier
local charKey = nil

-- Session statistics
local stats = {
    -- Timing
    sessionStart = nil,
    combatStart = nil,
    totalCombatTime = 0,
    inCombat = false,

    -- Melee stats
    melee = {
        hits = 0,
        crits = 0,
        misses = 0,
        dodges = 0,
        parries = 0,
        blocks = 0,
        glancing = 0,
        damage = 0,
        critDamage = 0,
    },

    -- Spell stats (aggregate)
    spell = {
        hits = 0,
        crits = 0,
        resists = 0,
        partialResists = 0,
        damage = 0,
        critDamage = 0,
        resistedDamage = 0,
    },

    -- Per-spell breakdown
    spells = {},
}

-- Initialize per-spell stats
local function GetSpellStats(spellName)
    if not stats.spells[spellName] then
        stats.spells[spellName] = {
            hits = 0,
            crits = 0,
            resists = 0,
            partialResists = 0,
            damage = 0,
            critDamage = 0,
            resistedDamage = 0,
        }
    end
    return stats.spells[spellName]
end

-- Format a number with commas
local function FormatNumber(n)
    local formatted = tostring(n)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

-- Format time in minutes and seconds
local function FormatTime(seconds)
    if seconds < 60 then
        return string.format("%.1fs", seconds)
    else
        local mins = math.floor(seconds / 60)
        local secs = seconds - (mins * 60)
        return string.format("%dm %.1fs", mins, secs)
    end
end

-- Format a timestamp to readable date
local function FormatDate(timestamp)
    return date("%Y-%m-%d %H:%M", timestamp)
end

-- Calculate hit rate percentage
local function CalcHitRate(hits, crits, misses)
    local total = hits + crits + misses
    if total == 0 then return 0 end
    return ((hits + crits) / total) * 100
end

-- Calculate crit rate percentage
local function CalcCritRate(hits, crits)
    local total = hits + crits
    if total == 0 then return 0 end
    return (crits / total) * 100
end

-- Deep copy a table
local function DeepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

-- Initialize database for current character
local function InitDB()
    if not DamageTrackerDB then
        DamageTrackerDB = {}
    end

    if not DamageTrackerDB[charKey] then
        DamageTrackerDB[charKey] = {
            sessions = {},
            snapshots = {},
            lifetime = {
                totalDamage = 0,
                totalCombatTime = 0,
                melee = {
                    hits = 0, crits = 0, misses = 0, dodges = 0,
                    parries = 0, blocks = 0, glancing = 0,
                    damage = 0, critDamage = 0,
                },
                spell = {
                    hits = 0, crits = 0, resists = 0, partialResists = 0,
                    damage = 0, critDamage = 0, resistedDamage = 0,
                },
            },
        }
    end
end

-- Get current character's database
local function GetCharDB()
    return DamageTrackerDB[charKey]
end

-- Create a snapshot of current stats
local function CreateSnapshot()
    local combatTime = stats.totalCombatTime
    if stats.inCombat and stats.combatStart then
        combatTime = combatTime + (GetTime() - stats.combatStart)
    end

    local totalDamage = stats.melee.damage + stats.spell.damage
    local dps = 0
    if combatTime > 0 then
        dps = totalDamage / combatTime
    end

    return {
        timestamp = time(),
        combatTime = combatTime,
        totalDamage = totalDamage,
        dps = dps,
        melee = DeepCopy(stats.melee),
        spell = DeepCopy(stats.spell),
        spells = DeepCopy(stats.spells),
    }
end

-- Update lifetime stats with current session
local function UpdateLifetime()
    local db = GetCharDB()
    if not db then return end

    local lt = db.lifetime
    local combatTime = stats.totalCombatTime
    if stats.inCombat and stats.combatStart then
        combatTime = combatTime + (GetTime() - stats.combatStart)
    end

    lt.totalDamage = lt.totalDamage + stats.melee.damage + stats.spell.damage
    lt.totalCombatTime = lt.totalCombatTime + combatTime

    -- Melee
    lt.melee.hits = lt.melee.hits + stats.melee.hits
    lt.melee.crits = lt.melee.crits + stats.melee.crits
    lt.melee.misses = lt.melee.misses + stats.melee.misses
    lt.melee.dodges = lt.melee.dodges + stats.melee.dodges
    lt.melee.parries = lt.melee.parries + stats.melee.parries
    lt.melee.blocks = lt.melee.blocks + stats.melee.blocks
    lt.melee.glancing = lt.melee.glancing + stats.melee.glancing
    lt.melee.damage = lt.melee.damage + stats.melee.damage
    lt.melee.critDamage = lt.melee.critDamage + stats.melee.critDamage

    -- Spell
    lt.spell.hits = lt.spell.hits + stats.spell.hits
    lt.spell.crits = lt.spell.crits + stats.spell.crits
    lt.spell.resists = lt.spell.resists + stats.spell.resists
    lt.spell.partialResists = lt.spell.partialResists + stats.spell.partialResists
    lt.spell.damage = lt.spell.damage + stats.spell.damage
    lt.spell.critDamage = lt.spell.critDamage + stats.spell.critDamage
    lt.spell.resistedDamage = lt.spell.resistedDamage + stats.spell.resistedDamage
end

-- Save current session to history
local function SaveSessionToHistory()
    local db = GetCharDB()
    if not db then return end

    -- Only save if there's actual data
    if stats.melee.damage + stats.spell.damage == 0 then
        return
    end

    local snapshot = CreateSnapshot()
    table.insert(db.sessions, snapshot)

    -- Keep only last 50 sessions
    while table.getn(db.sessions) > 50 do
        table.remove(db.sessions, 1)
    end
end

-- Combat log parsing patterns (vanilla WoW)
local function ParseMeleeHit(msg)
    local _, _, target, damage = string.find(msg, "You hit (.+) for (%d+)%.")
    if target then
        return tonumber(damage), false
    end

    _, _, target, damage = string.find(msg, "You crit (.+) for (%d+)%.")
    if target then
        return tonumber(damage), true
    end

    _, _, target, damage = string.find(msg, "You hit (.+) for (%d+)%.%s*%(glancing%)")
    if target then
        return tonumber(damage), false, true
    end

    return nil
end

local function ParseMeleeMiss(msg)
    if string.find(msg, "^You miss") then
        return "miss"
    end
    if string.find(msg, "dodged") or string.find(msg, "dodges") then
        return "dodge"
    end
    if string.find(msg, "parried") or string.find(msg, "parries") then
        return "parry"
    end
    if string.find(msg, "blocked") or string.find(msg, "blocks") then
        return "block"
    end
    return nil
end

local function ParseSpellDamage(msg)
    local _, _, spell, target, damage, resisted = string.find(msg, "Your (.+) hits (.+) for (%d+)%.%s*%((%d+) resisted%)")
    if spell then
        return spell, tonumber(damage), false, tonumber(resisted)
    end

    _, _, spell, target, damage, resisted = string.find(msg, "Your (.+) crits (.+) for (%d+)%.%s*%((%d+) resisted%)")
    if spell then
        return spell, tonumber(damage), true, tonumber(resisted)
    end

    _, _, spell, target, damage = string.find(msg, "Your (.+) hits (.+) for (%d+)%.")
    if spell then
        return spell, tonumber(damage), false, 0
    end

    _, _, spell, target, damage = string.find(msg, "Your (.+) crits (.+) for (%d+)%.")
    if spell then
        return spell, tonumber(damage), true, 0
    end

    return nil
end

local function ParseSpellResist(msg)
    local _, _, spell, target = string.find(msg, "Your (.+) was resisted by (.+)%.")
    if spell then
        return spell
    end

    _, _, spell = string.find(msg, "Your (.+) failed%.")
    if spell then
        return spell
    end

    return nil
end

-- Event handlers
local function OnMeleeHit(msg)
    local damage, isCrit, isGlancing = ParseMeleeHit(msg)
    if damage then
        stats.melee.damage = stats.melee.damage + damage
        if isCrit then
            stats.melee.crits = stats.melee.crits + 1
            stats.melee.critDamage = stats.melee.critDamage + damage
        elseif isGlancing then
            stats.melee.glancing = stats.melee.glancing + 1
            stats.melee.hits = stats.melee.hits + 1
        else
            stats.melee.hits = stats.melee.hits + 1
        end
    end
end

local function OnMeleeMiss(msg)
    local missType = ParseMeleeMiss(msg)
    if missType then
        if missType == "miss" then
            stats.melee.misses = stats.melee.misses + 1
        elseif missType == "dodge" then
            stats.melee.dodges = stats.melee.dodges + 1
        elseif missType == "parry" then
            stats.melee.parries = stats.melee.parries + 1
        elseif missType == "block" then
            stats.melee.blocks = stats.melee.blocks + 1
        end
    end
end

local function OnSpellDamage(msg)
    local spell, damage, isCrit, resisted = ParseSpellDamage(msg)
    if spell and damage then
        stats.spell.damage = stats.spell.damage + damage
        if isCrit then
            stats.spell.crits = stats.spell.crits + 1
            stats.spell.critDamage = stats.spell.critDamage + damage
        else
            stats.spell.hits = stats.spell.hits + 1
        end

        if resisted and resisted > 0 then
            stats.spell.partialResists = stats.spell.partialResists + 1
            stats.spell.resistedDamage = stats.spell.resistedDamage + resisted
        end

        local spellStats = GetSpellStats(spell)
        spellStats.damage = spellStats.damage + damage
        if isCrit then
            spellStats.crits = spellStats.crits + 1
            spellStats.critDamage = spellStats.critDamage + damage
        else
            spellStats.hits = spellStats.hits + 1
        end

        if resisted and resisted > 0 then
            spellStats.partialResists = spellStats.partialResists + 1
            spellStats.resistedDamage = spellStats.resistedDamage + resisted
        end
    end
end

local function OnSpellResist(msg)
    local spell = ParseSpellResist(msg)
    if spell then
        stats.spell.resists = stats.spell.resists + 1

        local spellStats = GetSpellStats(spell)
        spellStats.resists = spellStats.resists + 1
    end
end

local function OnCombatStart()
    if not stats.inCombat then
        stats.inCombat = true
        stats.combatStart = GetTime()
    end
end

local function OnCombatEnd()
    if stats.inCombat then
        stats.inCombat = false
        if stats.combatStart then
            stats.totalCombatTime = stats.totalCombatTime + (GetTime() - stats.combatStart)
        end
        stats.combatStart = nil
    end
end

-- Display functions
local function Msg(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF1701_DamageTracker:|r " .. text)
end

local function ShowOverview()
    local totalDamage = stats.melee.damage + stats.spell.damage
    local combatTime = stats.totalCombatTime
    if stats.inCombat and stats.combatStart then
        combatTime = combatTime + (GetTime() - stats.combatStart)
    end

    local dps = 0
    if combatTime > 0 then
        dps = totalDamage / combatTime
    end

    Msg("=== Session Statistics ===")
    Msg(string.format("Total Damage: |cFFFFFF00%s|r", FormatNumber(totalDamage)))
    Msg(string.format("Combat Time: |cFFFFFF00%s|r | DPS: |cFFFFFF00%.1f|r", FormatTime(combatTime), dps))

    local meleeTotal = stats.melee.hits + stats.melee.crits
    local meleeMisses = stats.melee.misses + stats.melee.dodges + stats.melee.parries + stats.melee.blocks
    local meleeHitRate = CalcHitRate(stats.melee.hits, stats.melee.crits, meleeMisses)
    local meleeCritRate = CalcCritRate(stats.melee.hits, stats.melee.crits)

    if meleeTotal + meleeMisses > 0 then
        Msg(string.format("Melee: |cFFFFFF00%s|r dmg | %d hits (%d crit) | Hit: %.1f%% | Crit: %.1f%%",
            FormatNumber(stats.melee.damage), meleeTotal, stats.melee.crits, meleeHitRate, meleeCritRate))
        if meleeMisses > 0 then
            Msg(string.format("  Avoided: %d miss, %d dodge, %d parry, %d block",
                stats.melee.misses, stats.melee.dodges, stats.melee.parries, stats.melee.blocks))
        end
    end

    local spellTotal = stats.spell.hits + stats.spell.crits
    local spellHitRate = CalcHitRate(stats.spell.hits, stats.spell.crits, stats.spell.resists)
    local spellCritRate = CalcCritRate(stats.spell.hits, stats.spell.crits)

    if spellTotal + stats.spell.resists > 0 then
        Msg(string.format("Spells: |cFFFFFF00%s|r dmg | %d hits (%d crit) | Hit: %.1f%% | Crit: %.1f%%",
            FormatNumber(stats.spell.damage), spellTotal, stats.spell.crits, spellHitRate, spellCritRate))
        if stats.spell.resists > 0 or stats.spell.partialResists > 0 then
            Msg(string.format("  Resists: %d full, %d partial (|cFFFF0000%s|r dmg lost)",
                stats.spell.resists, stats.spell.partialResists, FormatNumber(stats.spell.resistedDamage)))
        end
    end
end

local function ShowSpellBreakdown()
    Msg("=== Per-Spell Breakdown ===")

    local hasSpells = false
    for spellName, s in pairs(stats.spells) do
        hasSpells = true
        local total = s.hits + s.crits
        local hitRate = CalcHitRate(s.hits, s.crits, s.resists)
        local critRate = CalcCritRate(s.hits, s.crits)
        local avgDmg = 0
        if total > 0 then
            avgDmg = s.damage / total
        end

        Msg(string.format("|cFFFFFF00%s|r:", spellName))
        Msg(string.format("  Dmg: %s | Avg: %.0f | Hits: %d (%d crit)",
            FormatNumber(s.damage), avgDmg, total, s.crits))
        Msg(string.format("  Hit: %.1f%% | Crit: %.1f%% | Resists: %d full, %d partial",
            hitRate, critRate, s.resists, s.partialResists))
    end

    if not hasSpells then
        Msg("No spell data recorded yet.")
    end
end

local function ShowMeleeBreakdown()
    Msg("=== Melee Statistics ===")

    local total = stats.melee.hits + stats.melee.crits
    local misses = stats.melee.misses + stats.melee.dodges + stats.melee.parries + stats.melee.blocks

    if total + misses == 0 then
        Msg("No melee data recorded yet.")
        return
    end

    local avgDmg = 0
    local avgCritDmg = 0
    if total > 0 then
        avgDmg = stats.melee.damage / total
    end
    if stats.melee.crits > 0 then
        avgCritDmg = stats.melee.critDamage / stats.melee.crits
    end

    Msg(string.format("Total Damage: |cFFFFFF00%s|r", FormatNumber(stats.melee.damage)))
    Msg(string.format("Swings: %d total (%d hits, %d crits, %d glancing)", total + misses, stats.melee.hits, stats.melee.crits, stats.melee.glancing))
    Msg(string.format("Average Hit: %.0f | Average Crit: %.0f", avgDmg, avgCritDmg))
    Msg(string.format("Hit Rate: %.1f%% | Crit Rate: %.1f%%",
        CalcHitRate(stats.melee.hits, stats.melee.crits, misses),
        CalcCritRate(stats.melee.hits, stats.melee.crits)))
    Msg(string.format("Avoided: %d miss, %d dodge, %d parry, %d block",
        stats.melee.misses, stats.melee.dodges, stats.melee.parries, stats.melee.blocks))
end

local function ShowSessionInfo()
    local sessionTime = 0
    if stats.sessionStart then
        sessionTime = GetTime() - stats.sessionStart
    end

    local combatTime = stats.totalCombatTime
    if stats.inCombat and stats.combatStart then
        combatTime = combatTime + (GetTime() - stats.combatStart)
    end

    local combatPercent = 0
    if sessionTime > 0 then
        combatPercent = (combatTime / sessionTime) * 100
    end

    Msg("=== Session Info ===")
    Msg(string.format("Session Duration: |cFFFFFF00%s|r", FormatTime(sessionTime)))
    Msg(string.format("Time in Combat: |cFFFFFF00%s|r (%.1f%%)", FormatTime(combatTime), combatPercent))
    Msg(string.format("Currently: %s", stats.inCombat and "|cFFFF0000In Combat|r" or "|cFF00FF00Out of Combat|r"))
end

local function ShowHistory()
    local db = GetCharDB()
    if not db then
        Msg("No data available.")
        return
    end

    local sessions = db.sessions
    if table.getn(sessions) == 0 then
        Msg("No session history recorded yet.")
        return
    end

    Msg("=== Session History (Last 10) ===")
    local start = math.max(1, table.getn(sessions) - 9)
    for i = table.getn(sessions), start, -1 do
        local s = sessions[i]
        Msg(string.format("|cFFFFFF00#%d|r %s | %s dmg | %.1f DPS | %s combat",
            i, FormatDate(s.timestamp), FormatNumber(s.totalDamage), s.dps, FormatTime(s.combatTime)))
    end
end

local function ShowSnapshots()
    local db = GetCharDB()
    if not db then
        Msg("No data available.")
        return
    end

    local snapshots = db.snapshots
    local count = 0
    for name, _ in pairs(snapshots) do
        count = count + 1
    end

    if count == 0 then
        Msg("No snapshots saved. Use /dmg save <name> to create one.")
        return
    end

    Msg("=== Saved Snapshots ===")
    for name, s in pairs(snapshots) do
        Msg(string.format("|cFFFFFF00%s|r: %s dmg | %.1f DPS | %s combat (%s)",
            name, FormatNumber(s.totalDamage), s.dps, FormatTime(s.combatTime), FormatDate(s.timestamp)))
    end
end

local function SaveSnapshot(name)
    if not name or name == "" then
        Msg("Usage: /dmg save <name>")
        return
    end

    local db = GetCharDB()
    if not db then
        Msg("Error: Database not initialized.")
        return
    end

    local snapshot = CreateSnapshot()
    db.snapshots[name] = snapshot
    Msg(string.format("Saved snapshot |cFFFFFF00%s|r: %s dmg, %.1f DPS",
        name, FormatNumber(snapshot.totalDamage), snapshot.dps))
end

local function DeleteSnapshot(name)
    if not name or name == "" then
        Msg("Usage: /dmg delete <name>")
        return
    end

    local db = GetCharDB()
    if not db or not db.snapshots[name] then
        Msg(string.format("Snapshot '%s' not found.", name))
        return
    end

    db.snapshots[name] = nil
    Msg(string.format("Deleted snapshot |cFFFFFF00%s|r.", name))
end

local function LoadSnapshot(name)
    if not name or name == "" then
        Msg("Usage: /dmg load <name>")
        return
    end

    local db = GetCharDB()
    if not db or not db.snapshots[name] then
        Msg(string.format("Snapshot '%s' not found.", name))
        return
    end

    local s = db.snapshots[name]
    Msg(string.format("=== Snapshot: %s ===", name))
    Msg(string.format("Recorded: %s", FormatDate(s.timestamp)))
    Msg(string.format("Total Damage: |cFFFFFF00%s|r | DPS: |cFFFFFF00%.1f|r", FormatNumber(s.totalDamage), s.dps))
    Msg(string.format("Combat Time: |cFFFFFF00%s|r", FormatTime(s.combatTime)))

    local meleeTotal = s.melee.hits + s.melee.crits
    local meleeMisses = s.melee.misses + s.melee.dodges + s.melee.parries + s.melee.blocks
    if meleeTotal + meleeMisses > 0 then
        Msg(string.format("Melee: %s dmg | Hit: %.1f%% | Crit: %.1f%%",
            FormatNumber(s.melee.damage),
            CalcHitRate(s.melee.hits, s.melee.crits, meleeMisses),
            CalcCritRate(s.melee.hits, s.melee.crits)))
    end

    local spellTotal = s.spell.hits + s.spell.crits
    if spellTotal + s.spell.resists > 0 then
        Msg(string.format("Spells: %s dmg | Hit: %.1f%% | Crit: %.1f%%",
            FormatNumber(s.spell.damage),
            CalcHitRate(s.spell.hits, s.spell.crits, s.spell.resists),
            CalcCritRate(s.spell.hits, s.spell.crits)))
    end
end

local function CompareSnapshots(name1, name2)
    if not name1 or not name2 or name1 == "" or name2 == "" then
        Msg("Usage: /dmg compare <snapshot1> <snapshot2>")
        return
    end

    local db = GetCharDB()
    if not db then
        Msg("No data available.")
        return
    end

    local s1 = db.snapshots[name1]
    local s2 = db.snapshots[name2]

    if not s1 then
        Msg(string.format("Snapshot '%s' not found.", name1))
        return
    end
    if not s2 then
        Msg(string.format("Snapshot '%s' not found.", name2))
        return
    end

    local function Diff(a, b, format, suffix)
        local diff = b - a
        local pct = 0
        if a > 0 then
            pct = ((b - a) / a) * 100
        end
        local color = diff >= 0 and "|cFF00FF00+" or "|cFFFF0000"
        return string.format(format .. " (%s%.1f%%|r)", diff, color, pct) .. (suffix or "")
    end

    Msg(string.format("=== Comparing: %s vs %s ===", name1, name2))
    Msg(string.format("|cFFFFFF00%s|r: %s dmg | %.1f DPS", name1, FormatNumber(s1.totalDamage), s1.dps))
    Msg(string.format("|cFFFFFF00%s|r: %s dmg | %.1f DPS", name2, FormatNumber(s2.totalDamage), s2.dps))
    Msg("--- Difference ---")
    Msg(string.format("DPS: %s", Diff(s1.dps, s2.dps, "%.1f")))
    Msg(string.format("Total Damage: %s", Diff(s1.totalDamage, s2.totalDamage, "%d")))

    local s1MeleeHit = CalcHitRate(s1.melee.hits, s1.melee.crits, s1.melee.misses + s1.melee.dodges + s1.melee.parries + s1.melee.blocks)
    local s2MeleeHit = CalcHitRate(s2.melee.hits, s2.melee.crits, s2.melee.misses + s2.melee.dodges + s2.melee.parries + s2.melee.blocks)
    local s1MeleeCrit = CalcCritRate(s1.melee.hits, s1.melee.crits)
    local s2MeleeCrit = CalcCritRate(s2.melee.hits, s2.melee.crits)

    local s1SpellHit = CalcHitRate(s1.spell.hits, s1.spell.crits, s1.spell.resists)
    local s2SpellHit = CalcHitRate(s2.spell.hits, s2.spell.crits, s2.spell.resists)
    local s1SpellCrit = CalcCritRate(s1.spell.hits, s1.spell.crits)
    local s2SpellCrit = CalcCritRate(s2.spell.hits, s2.spell.crits)

    if s1.melee.damage > 0 or s2.melee.damage > 0 then
        Msg(string.format("Melee Hit%%: %.1f%% vs %.1f%%", s1MeleeHit, s2MeleeHit))
        Msg(string.format("Melee Crit%%: %.1f%% vs %.1f%%", s1MeleeCrit, s2MeleeCrit))
    end
    if s1.spell.damage > 0 or s2.spell.damage > 0 then
        Msg(string.format("Spell Hit%%: %.1f%% vs %.1f%%", s1SpellHit, s2SpellHit))
        Msg(string.format("Spell Crit%%: %.1f%% vs %.1f%%", s1SpellCrit, s2SpellCrit))
    end
end

local function ShowLifetime()
    local db = GetCharDB()
    if not db then
        Msg("No data available.")
        return
    end

    local lt = db.lifetime
    local dps = 0
    if lt.totalCombatTime > 0 then
        dps = lt.totalDamage / lt.totalCombatTime
    end

    Msg("=== Lifetime Statistics ===")
    Msg(string.format("Total Damage: |cFFFFFF00%s|r", FormatNumber(lt.totalDamage)))
    Msg(string.format("Total Combat Time: |cFFFFFF00%s|r | Average DPS: |cFFFFFF00%.1f|r",
        FormatTime(lt.totalCombatTime), dps))
    Msg(string.format("Sessions Recorded: |cFFFFFF00%d|r", table.getn(db.sessions)))

    local meleeTotal = lt.melee.hits + lt.melee.crits
    local meleeMisses = lt.melee.misses + lt.melee.dodges + lt.melee.parries + lt.melee.blocks
    if meleeTotal + meleeMisses > 0 then
        Msg(string.format("Melee: %s dmg | %d swings | Hit: %.1f%% | Crit: %.1f%%",
            FormatNumber(lt.melee.damage), meleeTotal + meleeMisses,
            CalcHitRate(lt.melee.hits, lt.melee.crits, meleeMisses),
            CalcCritRate(lt.melee.hits, lt.melee.crits)))
    end

    local spellTotal = lt.spell.hits + lt.spell.crits
    if spellTotal + lt.spell.resists > 0 then
        Msg(string.format("Spells: %s dmg | %d casts | Hit: %.1f%% | Crit: %.1f%%",
            FormatNumber(lt.spell.damage), spellTotal + lt.spell.resists,
            CalcHitRate(lt.spell.hits, lt.spell.crits, lt.spell.resists),
            CalcCritRate(lt.spell.hits, lt.spell.crits)))
        if lt.spell.resists > 0 or lt.spell.partialResists > 0 then
            Msg(string.format("  Resists: %d full, %d partial (%s dmg lost)",
                lt.spell.resists, lt.spell.partialResists, FormatNumber(lt.spell.resistedDamage)))
        end
    end
end

local function ResetStats()
    -- Save current session to history before resetting
    SaveSessionToHistory()
    UpdateLifetime()

    stats.sessionStart = GetTime()
    stats.combatStart = nil
    stats.totalCombatTime = 0
    stats.inCombat = false

    stats.melee = {
        hits = 0, crits = 0, misses = 0, dodges = 0,
        parries = 0, blocks = 0, glancing = 0,
        damage = 0, critDamage = 0,
    }

    stats.spell = {
        hits = 0, crits = 0, resists = 0, partialResists = 0,
        damage = 0, critDamage = 0, resistedDamage = 0,
    }

    stats.spells = {}

    Msg("Statistics reset. Session saved to history.")
end

-- Slash command handler
local function SlashCmdHandler(msg)
    msg = msg or ""
    msg = string.gsub(msg, "^%s*(.-)%s*$", "%1") -- trim

    -- Parse command and arguments
    local _, _, cmd, args = string.find(msg, "^(%S+)%s*(.*)")
    cmd = string.lower(cmd or "")
    args = args or ""

    if cmd == "" then
        ShowOverview()
    elseif cmd == "reset" then
        ResetStats()
    elseif cmd == "spells" or cmd == "spell" then
        ShowSpellBreakdown()
    elseif cmd == "melee" then
        ShowMeleeBreakdown()
    elseif cmd == "session" then
        ShowSessionInfo()
    elseif cmd == "save" then
        SaveSnapshot(args)
    elseif cmd == "history" then
        ShowHistory()
    elseif cmd == "snapshots" or cmd == "list" then
        ShowSnapshots()
    elseif cmd == "load" or cmd == "show" then
        LoadSnapshot(args)
    elseif cmd == "delete" or cmd == "remove" then
        DeleteSnapshot(args)
    elseif cmd == "compare" or cmd == "cmp" then
        local _, _, name1, name2 = string.find(args, "^(%S+)%s+(%S+)")
        CompareSnapshots(name1, name2)
    elseif cmd == "lifetime" or cmd == "total" or cmd == "all" then
        ShowLifetime()
    elseif cmd == "help" then
        Msg("Commands:")
        Msg("  /dmg - Show current session stats")
        Msg("  /dmg reset - Reset session (saves to history)")
        Msg("  /dmg spells - Per-spell breakdown")
        Msg("  /dmg melee - Melee statistics")
        Msg("  /dmg session - Session timing info")
        Msg("  /dmg save <name> - Save snapshot for gear comparison")
        Msg("  /dmg snapshots - List saved snapshots")
        Msg("  /dmg load <name> - View a snapshot")
        Msg("  /dmg delete <name> - Delete a snapshot")
        Msg("  /dmg compare <a> <b> - Compare two snapshots")
        Msg("  /dmg history - View past sessions")
        Msg("  /dmg lifetime - All-time cumulative stats")
    else
        Msg("Unknown command. Type /dmg help for usage.")
    end
end

-- Create addon frame for event handling
local frame = CreateFrame("Frame")
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
frame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
frame:RegisterEvent("CHAT_MSG_SPELL_FAILED_LOCALPLAYER")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        -- Initialize character key
        local name = UnitName("player")
        local realm = GetRealmName()
        charKey = name .. "-" .. realm

        -- Initialize database
        InitDB()

        -- Register slash commands
        SLASH_DAMAGETRACKER17011 = "/dmg"
        SLASH_DAMAGETRACKER17012 = "/damage"
        SLASH_DAMAGETRACKER17013 = "/dt"
        SlashCmdList["DAMAGETRACKER1701"] = SlashCmdHandler

        stats.sessionStart = GetTime()
        Msg("Loaded. Type /dmg for stats, /dmg help for commands.")

    elseif event == "PLAYER_LOGOUT" then
        -- Save current session before logout
        SaveSessionToHistory()
        UpdateLifetime()

    elseif event == "CHAT_MSG_COMBAT_SELF_HITS" then
        OnMeleeHit(arg1)
        OnCombatStart()

    elseif event == "CHAT_MSG_COMBAT_SELF_MISSES" then
        OnMeleeMiss(arg1)
        OnCombatStart()

    elseif event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
        OnSpellDamage(arg1)
        OnCombatStart()

    elseif event == "CHAT_MSG_SPELL_FAILED_LOCALPLAYER" then
        OnSpellResist(arg1)
        OnCombatStart()

    elseif event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()

    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
    end
end)

-- Export for external use
DamageTracker1701.GetStats = function() return stats end
DamageTracker1701.GetDB = function() return GetCharDB() end
DamageTracker1701.Reset = ResetStats
DamageTracker1701.ShowOverview = ShowOverview
DamageTracker1701.SaveSnapshot = SaveSnapshot
DamageTracker1701.CompareSnapshots = CompareSnapshots
