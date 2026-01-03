--[[
    DamageTracker - DPSMate Companion for Boss Fight History

    Auto-captures boss fights from DPSMate and stores historical snapshots
    for cross-session comparison. Helps measure gear improvements over time.

    Requires: DPSMate addon

    Usage:
        /dt              - Show boss history summary
        /dt list         - List all stored boss fights
        /dt show <fight> - Show detailed stats for a fight
        /dt compare <a> <b> - Compare two fights
        /dt compare <a> <b> spells - Compare with per-ability breakdown
        /dt delete <fight> - Delete a specific snapshot
        /dt config keepcount N - Set retention count (default 3)
        /dt help         - Show commands

    Fight identifiers:
        Lucifron         - Most recent kill
        Lucifron-2       - Second most recent
        Lucifron-Jan-02  - By date (case-insensitive month)
        Lucifron-2025-01-02 - Full ISO date
]]

DamageTracker1701 = {}

-- SavedVariables database
DamageTrackerDB = nil

-- Local state
local charKey = nil
local dpsMateMissing = false
local lastSegmentCount = 0

-- Month name mapping for date parsing
local MONTH_MAP = {
    jan = 1, january = 1,
    feb = 2, february = 2,
    mar = 3, march = 3,
    apr = 4, april = 4,
    may = 5,
    jun = 6, june = 6,
    jul = 7, july = 7,
    aug = 8, august = 8,
    sep = 9, september = 9,
    oct = 10, october = 10,
    nov = 11, november = 11,
    dec = 12, december = 12,
}

------------------------------------------------------------
-- UTILITY FUNCTIONS
------------------------------------------------------------

local function Msg(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF1701_DamageTracker:|r " .. text)
end

local function MsgError(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000DamageTracker Error:|r " .. text)
end

local function FormatNumber(n)
    if not n then return "0" end
    local formatted = string.format("%.0f", n)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

local function FormatTime(seconds)
    if not seconds or seconds < 0 then return "0s" end
    if seconds < 60 then
        return string.format("%.1fs", seconds)
    else
        local mins = math.floor(seconds / 60)
        local secs = seconds - (mins * 60)
        return string.format("%dm %.1fs", mins, secs)
    end
end

local function FormatDateShort(dateStr)
    -- Convert "2025-01-02" to "Jan-02"
    if not dateStr then return "?" end
    local _, _, year, month, day = string.find(dateStr, "(%d+)-(%d+)-(%d+)")
    if not month then return dateStr end
    local months = {"Jan", "Feb", "Mar", "Apr", "May", "Jun",
                    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}
    return months[tonumber(month)] .. "-" .. day
end

local function GetCurrentDate()
    return date("%Y-%m-%d")
end

local function DeepCopy(orig)
    if type(orig) ~= 'table' then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

------------------------------------------------------------
-- DATE PARSING
------------------------------------------------------------

-- Parse flexible date input: "Jan-02", "january-02", "2025-01-02"
-- Returns "YYYY-MM-DD" string or nil
local function ParseDateInput(input)
    if not input then return nil end

    -- Try ISO format: YYYY-MM-DD
    local _, _, year, month, day = string.find(input, "^(%d%d%d%d)-(%d%d?)-(%d%d?)$")
    if year then
        return string.format("%04d-%02d-%02d", tonumber(year), tonumber(month), tonumber(day))
    end

    -- Try month-day format: Jan-02, january-02, JANUARY-02
    local _, _, monthStr, dayStr = string.find(input, "^(%a+)-(%d%d?)$")
    if monthStr then
        local monthNum = MONTH_MAP[string.lower(monthStr)]
        if monthNum then
            -- Assume current year
            local currentYear = tonumber(date("%Y"))
            return string.format("%04d-%02d-%02d", currentYear, monthNum, tonumber(dayStr))
        end
    end

    return nil
end

-- Check if a date string matches a snapshot's date
local function DateMatches(snapshotDate, inputDate)
    if not snapshotDate or not inputDate then return false end
    return snapshotDate == inputDate
end

------------------------------------------------------------
-- NAME RESOLUTION
------------------------------------------------------------

-- Parse fight identifier: "Lucifron", "Lucifron-2", "Lucifron-Jan-02"
-- Returns: bossName, snapshot (or nil, errorMessage)
local function ResolveFightId(fightId)
    if not fightId or fightId == "" then
        return nil, "No fight specified"
    end

    local db = GetCharDB()
    if not db then
        return nil, "Database not initialized"
    end

    -- Try to parse as "BossName-Suffix"
    local _, _, bossName, suffix = string.find(fightId, "^(.+)-(.+)$")

    if not bossName then
        -- No suffix - just boss name, get most recent
        bossName = fightId
        suffix = nil
    end

    -- Check if boss exists
    local bossData = db.bosses[bossName]
    if not bossData or table.getn(bossData) == 0 then
        return nil, string.format("No data for boss '%s'", bossName)
    end

    if not suffix then
        -- Return most recent
        return bossName, bossData[1]
    end

    -- Try suffix as index: "2", "3"
    local index = tonumber(suffix)
    if index then
        if bossData[index] then
            return bossName, bossData[index]
        else
            return nil, string.format("No kill #%d for %s (have %d)", index, bossName, table.getn(bossData))
        end
    end

    -- Try suffix as date
    local targetDate = ParseDateInput(suffix)
    if targetDate then
        for i, snapshot in ipairs(bossData) do
            if DateMatches(snapshot.date, targetDate) then
                return bossName, snapshot
            end
        end
        return nil, string.format("No %s kill on %s", bossName, FormatDateShort(targetDate))
    end

    return nil, string.format("Invalid identifier: %s", fightId)
end

-- Get all boss names with kill counts
local function GetBossList()
    local db = GetCharDB()
    if not db or not db.bosses then return {} end

    local list = {}
    for bossName, kills in pairs(db.bosses) do
        table.insert(list, {
            name = bossName,
            count = table.getn(kills),
            latest = kills[1],
        })
    end

    -- Sort by most recent kill
    table.sort(list, function(a, b)
        if not a.latest then return false end
        if not b.latest then return true end
        return (a.latest.timestamp or 0) > (b.latest.timestamp or 0)
    end)

    return list
end

------------------------------------------------------------
-- DPSMATE DATA READER
------------------------------------------------------------

-- DPSMate array indices (from DPSMate_Details_Damage.lua)
local DPM = {
    HITS = 1,
    HIT_MIN = 2,
    HIT_MAX = 3,
    HIT_AVG = 4,
    CRITS = 5,
    CRIT_MIN = 6,
    CRIT_MAX = 7,
    CRIT_AVG = 8,
    MISS = 9,
    PARRY = 10,
    DODGE = 11,
    RESIST = 12,
    TOTAL_DAMAGE = 13,
    GLANCE = 14,
    GLANCE_MIN = 15,
    GLANCE_MAX = 16,
    GLANCE_AVG = 17,
    BLOCK = 18,
    BLOCK_MIN = 19,
    BLOCK_MAX = 20,
    BLOCK_AVG = 21,
}

-- Get player's user ID in DPSMate
local function GetPlayerDPSMateId()
    if not DPSMateUser then return nil end
    local playerName = UnitName("player")
    local userData = DPSMateUser[playerName]
    if userData then
        return userData[1]  -- First element is the user ID
    end
    return nil
end

-- Get ability name by DPSMate ability ID
local function GetAbilityName(abilityId)
    if not DPSMateAbility then return "Unknown" end
    for name, data in pairs(DPSMateAbility) do
        if data[1] == abilityId then
            return name
        end
    end
    return "Unknown-" .. tostring(abilityId)
end

-- Extract player's data from a DPSMate segment
-- segmentIndex: which segment in DPSMateHistory to read
-- Returns: snapshot table or nil
local function ExtractSegmentData(segmentIndex)
    if dpsMateMissing then return nil end

    local playerId = GetPlayerDPSMateId()
    if not playerId then
        return nil
    end

    -- Get the damage data for this segment
    -- DPSMateHistory stores historical data, indexed by module name
    local histDamage = DPSMateHistory and DPSMateHistory["Damage"]
    if not histDamage or not histDamage[segmentIndex] then
        return nil
    end

    local segmentData = histDamage[segmentIndex]
    local playerData = segmentData[playerId]
    if not playerData then
        return nil
    end

    -- Get combat time for this segment
    local combatTime = 0
    if DPSMateCombatTime and DPSMateCombatTime["segments"] then
        local segTime = DPSMateCombatTime["segments"][segmentIndex]
        if segTime then
            combatTime = segTime[1] or 0
        end
    end

    -- Build abilities table
    local abilities = {}
    local totalDamage = 0
    local totalHits = 0
    local totalCrits = 0
    local totalMisses = 0
    local totalResists = 0
    local totalResistedDamage = 0

    for abilityId, abilityData in pairs(playerData) do
        if abilityId ~= "i" and type(abilityData) == "table" then
            local abilityName = GetAbilityName(abilityId)
            local hits = abilityData[DPM.HITS] or 0
            local crits = abilityData[DPM.CRITS] or 0
            local misses = abilityData[DPM.MISS] or 0
            local resists = abilityData[DPM.RESIST] or 0
            local damage = abilityData[DPM.TOTAL_DAMAGE] or 0
            local parry = abilityData[DPM.PARRY] or 0
            local dodge = abilityData[DPM.DODGE] or 0
            local glance = abilityData[DPM.GLANCE] or 0
            local block = abilityData[DPM.BLOCK] or 0

            -- DPSMate doesn't track partial resists separately in this structure
            -- We'll estimate resisted damage as 0 for now (would need more parsing)
            local resistedDamage = 0

            abilities[abilityName] = {
                damage = damage,
                hits = hits,
                crits = crits,
                misses = misses,
                resists = resists,
                partialResists = 0,  -- Not directly available
                resistedDamage = resistedDamage,
                parry = parry,
                dodge = dodge,
                glance = glance,
                block = block,
                hitMin = abilityData[DPM.HIT_MIN] or 0,
                hitMax = abilityData[DPM.HIT_MAX] or 0,
                hitAvg = abilityData[DPM.HIT_AVG] or 0,
                critMin = abilityData[DPM.CRIT_MIN] or 0,
                critMax = abilityData[DPM.CRIT_MAX] or 0,
                critAvg = abilityData[DPM.CRIT_AVG] or 0,
            }

            totalDamage = totalDamage + damage
            totalHits = totalHits + hits
            totalCrits = totalCrits + crits
            totalMisses = totalMisses + misses + parry + dodge + block
            totalResists = totalResists + resists
        end
    end

    local dps = 0
    if combatTime > 0 then
        dps = totalDamage / combatTime
    end

    return {
        date = GetCurrentDate(),
        timestamp = time(),
        combatTime = combatTime,
        totalDamage = totalDamage,
        dps = dps,
        totalHits = totalHits,
        totalCrits = totalCrits,
        totalMisses = totalMisses,
        totalResists = totalResists,
        totalResistedDamage = totalResistedDamage,
        abilities = abilities,
    }
end

-- Get count of segments in DPSMateHistory
local function GetDPSMateSegmentCount()
    if not DPSMateHistory or not DPSMateHistory["names"] then
        return 0
    end
    return table.getn(DPSMateHistory["names"])
end

-- Get segment name (boss name) by index
local function GetSegmentName(index)
    if not DPSMateHistory or not DPSMateHistory["names"] then
        return nil
    end
    return DPSMateHistory["names"][index]
end

------------------------------------------------------------
-- AUTO-CAPTURE
------------------------------------------------------------

-- Save a snapshot for a boss
local function SaveBossSnapshot(bossName, snapshot)
    local db = GetCharDB()
    if not db then return false end

    if not db.bosses[bossName] then
        db.bosses[bossName] = {}
    end

    -- Insert at beginning (newest first)
    table.insert(db.bosses[bossName], 1, snapshot)

    -- Prune old snapshots
    local keepCount = GetKeepCount()
    while table.getn(db.bosses[bossName]) > keepCount do
        table.remove(db.bosses[bossName])
    end

    return true
end

-- Check for new DPSMate segments and capture them
local function CheckForNewSegments()
    if dpsMateMissing then return end

    local currentCount = GetDPSMateSegmentCount()

    if currentCount > lastSegmentCount then
        -- New segment(s) detected
        for i = lastSegmentCount + 1, currentCount do
            local bossName = GetSegmentName(i)
            if bossName and bossName ~= "" then
                local snapshot = ExtractSegmentData(i)
                if snapshot and snapshot.totalDamage > 0 then
                    if SaveBossSnapshot(bossName, snapshot) then
                        Msg(string.format("Captured |cFFFFFF00%s|r kill: %.1f DPS, %s damage",
                            bossName, snapshot.dps, FormatNumber(snapshot.totalDamage)))
                    end
                end
            end
        end
    end

    lastSegmentCount = currentCount
end

-- Timer frame for delayed segment check
local timerFrame = CreateFrame("Frame")
local pendingCheck = false
local checkDelay = 0

timerFrame:SetScript("OnUpdate", function()
    if pendingCheck then
        checkDelay = checkDelay - arg1
        if checkDelay <= 0 then
            pendingCheck = false
            CheckForNewSegments()
        end
    end
end)

-- Schedule a segment check after delay
local function ScheduleSegmentCheck()
    pendingCheck = true
    checkDelay = 3  -- 3 second delay for DPSMate to finalize
end

------------------------------------------------------------
-- STAT CALCULATIONS
------------------------------------------------------------

local function CalcHitRate(hits, crits, misses)
    local total = hits + crits + misses
    if total == 0 then return 0 end
    return ((hits + crits) / total) * 100
end

local function CalcCritRate(hits, crits)
    local total = hits + crits
    if total == 0 then return 0 end
    return (crits / total) * 100
end

-- Calculate aggregate stats from a snapshot
local function CalcSnapshotStats(snapshot)
    local totalHits = 0
    local totalCrits = 0
    local totalMisses = 0
    local totalResists = 0
    local totalResistedDamage = 0

    if snapshot.abilities then
        for _, ability in pairs(snapshot.abilities) do
            totalHits = totalHits + (ability.hits or 0)
            totalCrits = totalCrits + (ability.crits or 0)
            totalMisses = totalMisses + (ability.misses or 0) +
                         (ability.parry or 0) + (ability.dodge or 0) + (ability.block or 0)
            totalResists = totalResists + (ability.resists or 0)
            totalResistedDamage = totalResistedDamage + (ability.resistedDamage or 0)
        end
    end

    return {
        hitRate = CalcHitRate(totalHits, totalCrits, totalMisses + totalResists),
        critRate = CalcCritRate(totalHits, totalCrits),
        totalResists = totalResists,
        partialResists = snapshot.partialResists or 0,
        resistedDamage = totalResistedDamage,
    }
end

-- Format percentage difference with color
local function FormatDiff(old, new, format, isLowerBetter)
    if not old or not new then return "?" end
    local diff = new - old
    local pct = 0
    if old ~= 0 then
        pct = (diff / math.abs(old)) * 100
    end

    local color
    if diff == 0 then
        color = "|cFFFFFFFF"  -- White
    elseif (diff > 0 and not isLowerBetter) or (diff < 0 and isLowerBetter) then
        color = "|cFF00FF00"  -- Green (improvement)
    else
        color = "|cFFFF0000"  -- Red (regression)
    end

    local sign = diff >= 0 and "+" or ""
    return string.format(format .. " (%s%s%.1f%%|r)", new, color, sign, pct)
end

------------------------------------------------------------
-- DISPLAY COMMANDS
------------------------------------------------------------

-- /dt - Show boss history summary
local function ShowSummary()
    local bossList = GetBossList()

    if table.getn(bossList) == 0 then
        Msg("No boss kills recorded yet.")
        Msg("Kill a boss with DPSMate running to start tracking!")
        return
    end

    Msg("=== DamageTracker Boss History ===")

    for _, boss in ipairs(bossList) do
        local latest = boss.latest
        local dpsStr = string.format("%.0f DPS", latest.dps or 0)

        -- Calculate diff from previous if exists
        local db = GetCharDB()
        local bossData = db.bosses[boss.name]
        if bossData and bossData[2] then
            local prevDps = bossData[2].dps or 0
            if prevDps > 0 then
                local diff = ((latest.dps - prevDps) / prevDps) * 100
                local color = diff >= 0 and "|cFF00FF00+" or "|cFFFF0000"
                dpsStr = string.format("%.0f DPS (%s%.1f%%|r)", latest.dps, color, diff)
            end
        end

        Msg(string.format("|cFFFFFF00%s|r: %d kills (latest: %s, %s)",
            boss.name, boss.count, FormatDateShort(latest.date), dpsStr))
    end
end

-- /dt list - List all stored boss fights
local function ShowList()
    local db = GetCharDB()
    if not db or not db.bosses then
        Msg("No data available.")
        return
    end

    local hasData = false

    Msg("=== All Stored Boss Fights ===")

    for bossName, kills in pairs(db.bosses) do
        hasData = true
        Msg(string.format("|cFFFFFF00%s|r:", bossName))
        for i, snapshot in ipairs(kills) do
            Msg(string.format("  %d. %s - %.0f DPS, %s, %s combat",
                i, FormatDateShort(snapshot.date), snapshot.dps or 0,
                FormatNumber(snapshot.totalDamage), FormatTime(snapshot.combatTime)))
        end
    end

    if not hasData then
        Msg("No boss kills recorded yet.")
    end
end

-- /dt show <fight> - Show detailed stats for a fight
local function ShowFight(fightId)
    local bossName, snapshot = ResolveFightId(fightId)
    if not bossName then
        MsgError(snapshot)  -- snapshot contains error message on failure
        return
    end

    local stats = CalcSnapshotStats(snapshot)

    Msg(string.format("=== %s: %s ===", bossName, FormatDateShort(snapshot.date)))
    Msg(string.format("DPS: |cFFFFFF00%.1f|r | Damage: |cFFFFFF00%s|r",
        snapshot.dps or 0, FormatNumber(snapshot.totalDamage)))
    Msg(string.format("Combat Time: %s", FormatTime(snapshot.combatTime)))
    Msg(string.format("Hit Rate: %.1f%% | Crit Rate: %.1f%%",
        stats.hitRate, stats.critRate))

    if stats.totalResists > 0 or stats.resistedDamage > 0 then
        Msg(string.format("Resists: %d | Dmg Lost: %s",
            stats.totalResists, FormatNumber(stats.resistedDamage)))
    end

    -- Show top abilities
    if snapshot.abilities then
        Msg("--- Top Abilities ---")
        local sorted = {}
        for name, data in pairs(snapshot.abilities) do
            table.insert(sorted, {name = name, damage = data.damage or 0, data = data})
        end
        table.sort(sorted, function(a, b) return a.damage > b.damage end)

        local shown = 0
        for _, ability in ipairs(sorted) do
            if shown >= 5 then break end
            shown = shown + 1
            local a = ability.data
            local hitRate = CalcHitRate(a.hits or 0, a.crits or 0, (a.misses or 0) + (a.resists or 0))
            local critRate = CalcCritRate(a.hits or 0, a.crits or 0)
            Msg(string.format("  |cFFFFFF00%s|r: %s (%.1f%% hit, %.1f%% crit)",
                ability.name, FormatNumber(ability.damage), hitRate, critRate))
        end
    end
end

-- /dt compare <a> <b> - Compare two fights
local function CompareFights(fightId1, fightId2, showSpells)
    local boss1, snap1 = ResolveFightId(fightId1)
    if not boss1 then
        MsgError(snap1)
        return
    end

    local boss2, snap2 = ResolveFightId(fightId2)
    if not boss2 then
        MsgError(snap2)
        return
    end

    local stats1 = CalcSnapshotStats(snap1)
    local stats2 = CalcSnapshotStats(snap2)

    Msg(string.format("=== %s: %s vs %s ===",
        boss1, FormatDateShort(snap1.date), FormatDateShort(snap2.date)))

    -- DPS comparison
    Msg(string.format("DPS:        %s",
        FormatDiff(snap1.dps, snap2.dps, "%.1f")))
    Msg(string.format("Damage:     %s",
        FormatDiff(snap1.totalDamage, snap2.totalDamage, "%.0f")))
    Msg(string.format("Combat Time: %.1fs vs %.1fs",
        snap1.combatTime or 0, snap2.combatTime or 0))
    Msg("")
    Msg(string.format("Hit Rate:   %.1f%% vs %.1f%%  (%s%.1f%%|r)",
        stats1.hitRate, stats2.hitRate,
        stats2.hitRate >= stats1.hitRate and "|cFF00FF00+" or "|cFFFF0000",
        stats2.hitRate - stats1.hitRate))
    Msg(string.format("Crit Rate:  %.1f%% vs %.1f%%  (%s%.1f%%|r)",
        stats1.critRate, stats2.critRate,
        stats2.critRate >= stats1.critRate and "|cFF00FF00+" or "|cFFFF0000",
        stats2.critRate - stats1.critRate))
    Msg(string.format("Resists:    %d vs %d",
        stats1.totalResists, stats2.totalResists))
    Msg(string.format("Dmg Lost:   %s",
        FormatDiff(stats1.resistedDamage, stats2.resistedDamage, "%.0f", true)))

    -- Per-ability breakdown if requested
    if showSpells then
        Msg("")
        Msg("=== Per-Ability Breakdown ===")

        -- Collect all ability names
        local allAbilities = {}
        if snap1.abilities then
            for name, _ in pairs(snap1.abilities) do
                allAbilities[name] = true
            end
        end
        if snap2.abilities then
            for name, _ in pairs(snap2.abilities) do
                allAbilities[name] = true
            end
        end

        -- Sort by snap2 damage (or snap1 if not in snap2)
        local sorted = {}
        for name, _ in pairs(allAbilities) do
            local dmg2 = snap2.abilities and snap2.abilities[name] and snap2.abilities[name].damage or 0
            local dmg1 = snap1.abilities and snap1.abilities[name] and snap1.abilities[name].damage or 0
            table.insert(sorted, {name = name, damage = dmg2 > 0 and dmg2 or dmg1})
        end
        table.sort(sorted, function(a, b) return a.damage > b.damage end)

        for _, entry in ipairs(sorted) do
            local name = entry.name
            local a1 = snap1.abilities and snap1.abilities[name] or {}
            local a2 = snap2.abilities and snap2.abilities[name] or {}

            local hit1 = CalcHitRate(a1.hits or 0, a1.crits or 0, (a1.misses or 0) + (a1.resists or 0))
            local hit2 = CalcHitRate(a2.hits or 0, a2.crits or 0, (a2.misses or 0) + (a2.resists or 0))
            local crit1 = CalcCritRate(a1.hits or 0, a1.crits or 0)
            local crit2 = CalcCritRate(a2.hits or 0, a2.crits or 0)
            local dmgLost1 = a1.resistedDamage or 0
            local dmgLost2 = a2.resistedDamage or 0

            -- Calculate ability DPS
            local dps1 = snap1.combatTime and snap1.combatTime > 0 and (a1.damage or 0) / snap1.combatTime or 0
            local dps2 = snap2.combatTime and snap2.combatTime > 0 and (a2.damage or 0) / snap2.combatTime or 0

            Msg(string.format("|cFFFFFF00%s|r:", name))
            Msg(string.format("  DPS:      %s", FormatDiff(dps1, dps2, "%.1f")))
            Msg(string.format("  Hit%%:     %.1f%% vs %.1f%%", hit1, hit2))
            Msg(string.format("  Crit%%:    %.1f%% vs %.1f%%", crit1, crit2))
            if dmgLost1 > 0 or dmgLost2 > 0 then
                Msg(string.format("  Dmg Lost: %s", FormatDiff(dmgLost1, dmgLost2, "%.0f", true)))
            end
        end
    end
end

------------------------------------------------------------
-- DATABASE
------------------------------------------------------------

local function InitDB()
    if not DamageTrackerDB then
        DamageTrackerDB = {}
    end

    if not DamageTrackerDB[charKey] then
        DamageTrackerDB[charKey] = {
            config = {
                keepCount = 3,
            },
            bosses = {},
        }
    end

    -- Migration: ensure config exists
    if not DamageTrackerDB[charKey].config then
        DamageTrackerDB[charKey].config = { keepCount = 3 }
    end
    if not DamageTrackerDB[charKey].bosses then
        DamageTrackerDB[charKey].bosses = {}
    end
end

local function GetCharDB()
    return DamageTrackerDB and DamageTrackerDB[charKey]
end

local function GetKeepCount()
    local db = GetCharDB()
    return db and db.config and db.config.keepCount or 3
end

-- Create addon frame
local frame = CreateFrame("Frame")
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        local name = UnitName("player")
        local realm = GetRealmName()
        charKey = name .. "-" .. realm

        InitDB()

        -- Check for DPSMate
        if not DPSMate then
            dpsMateMissing = true
            MsgError("DPSMate not found! Auto-capture disabled.")
            MsgError("Install DPSMate to use this addon.")
        else
            Msg("Loaded. Type /dt for boss history, /dt help for commands.")
            -- Initialize segment count
            lastSegmentCount = GetDPSMateSegmentCount()
        end

        -- Register slash commands
        SLASH_DAMAGETRACKER17011 = "/dt"
        SLASH_DAMAGETRACKER17012 = "/damagetracker"
        SlashCmdList["DAMAGETRACKER1701"] = function(msg)
            Msg("Commands not yet implemented. Check back soon!")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended - check for new DPSMate segments after delay
        if not dpsMateMissing then
            ScheduleSegmentCheck()
        end
    end
end)
