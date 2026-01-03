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

------------------------------------------------------------
-- PLACEHOLDER: More code to follow in subsequent tasks
------------------------------------------------------------

-- Create addon frame
local frame = CreateFrame("Frame")
frame:RegisterEvent("VARIABLES_LOADED")

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
        end

        -- Register slash commands
        SLASH_DAMAGETRACKER17011 = "/dt"
        SLASH_DAMAGETRACKER17012 = "/damagetracker"
        SlashCmdList["DAMAGETRACKER1701"] = function(msg)
            Msg("Commands not yet implemented. Check back soon!")
        end
    end
end)
