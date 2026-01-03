# DamageTracker: DPSMate Integration Design

**Date:** 2026-01-03
**Status:** Approved
**Goal:** Redesign DamageTracker as a DPSMate companion that stores historical boss fight snapshots for cross-session comparison.

## Overview

DamageTracker pivots from a standalone combat parser to a **DPSMate companion addon** that:

1. Reads fight data from DPSMate (no duplicate combat log parsing)
2. Auto-captures boss fights when DPSMate records a named segment
3. Stores historical snapshots (configurable, default 3 per boss)
4. Enables comparison like `/dt compare Lucifron-Jan-02 Lucifron-Dec-26`

Primary use case: Measure whether hit rating improvements translate to DPS gains across the same boss encounter over time.

## Architecture

```
DPSMate (required)
    ↓ reads fight data
DamageTracker (companion)
    ↓ stores historical snapshots
DamageTrackerDB (SavedVariables)
```

### Data Flow

1. DPSMate detects fight end → saves segment to `DPSMateHistory`
2. DamageTracker hooks `PLAYER_REGEN_ENABLED` + polls DPSMate for new segments (2-3 second delay)
3. If new segment has a boss name → extract player's personal data → save snapshot
4. Old snapshots beyond retention limit are pruned

### Addon Load Order

- `DamageTracker.toc` declares `## Dependencies: DPSMate`
- On `VARIABLES_LOADED`, verify DPSMate globals exist
- If DPSMate missing, print error and disable auto-capture

## Data Model

```lua
DamageTrackerDB = {
    ["CharName-Realm"] = {
        config = {
            keepCount = 3,  -- fights per boss to retain
        },

        -- Boss fight history, keyed by normalized boss name
        bosses = {
            ["Lucifron"] = {
                -- Array of snapshots, newest first
                [1] = {
                    date = "2025-01-02",      -- YYYY-MM-DD for storage
                    timestamp = 1735830000,   -- Unix timestamp
                    combatTime = 45.2,

                    -- Player's personal stats from this fight
                    totalDamage = 48230,
                    dps = 1067.1,

                    -- Per-ability breakdown
                    abilities = {
                        ["Frostbolt"] = {
                            damage = 32000,
                            hits = 28, crits = 8, misses = 0,
                            resists = 1, partialResists = 3,
                            resistedDamage = 1200,
                            hitMin = 800, hitMax = 1100, hitAvg = 950,
                            critMin = 1600, critMax = 2200, critAvg = 1900,
                        },
                    },
                },
                [2] = { --[[ older kill ]] },
                [3] = { --[[ oldest kill ]] },
            },
        },
    },
}
```

### Name Resolution

Fight identifiers support multiple formats:

| Input | Resolution |
|-------|------------|
| `Lucifron` | Most recent (`bosses["Lucifron"][1]`) |
| `Lucifron-2` | Second most recent (`bosses["Lucifron"][2]`) |
| `Lucifron-Jan-02` | Match where `date == "2025-01-02"` |
| `Lucifron-2025-01-02` | Exact date match |

Date parsing accepts:
- ISO format: `YYYY-MM-DD`
- Spelled months (case-insensitive): `Jan-02`, `january-02`, `JANUARY-02`

## DPSMate Integration

### Data Sources

```lua
DPSMateHistory          -- Historical fight segments
DPSMateHistory["names"] -- Segment names (boss/encounter names)
DPSMateDamageDone       -- Damage data per player per ability
DPSMateCombatTime       -- Fight durations
DPSMateUser             -- Player ID mapping
DPSMateAbility          -- Ability ID mapping
```

### DPSMate Ability Data Format

```lua
-- Array indices from DPSMate_Details_Damage.lua
path[1]  = hits
path[2]  = hitMin
path[3]  = hitMax
path[4]  = hitAvg
path[5]  = crits
path[6]  = critMin
path[7]  = critMax
path[8]  = critAvg
path[9]  = miss
path[10] = parry
path[11] = dodge
path[12] = resist
path[13] = totalDamage
path[14] = glance
path[15] = glanceMin
path[16] = glanceMax
path[17] = glanceAvg
path[18] = block
path[19] = blockMin
path[20] = blockMax
path[21] = blockAvg
```

### Detection Strategy

1. Track `lastKnownSegmentCount` on addon load
2. On `PLAYER_REGEN_ENABLED`, wait 2-3 seconds for DPSMate to finalize
3. Check if `DPSMateHistory` has a new segment
4. If segment has a name → extract data → save snapshot

## Command Interface

```
/dt                     - Show available boss history summary
/dt list                - List all stored boss fights
/dt show <fight>        - Show detailed stats for a fight
/dt compare <a> <b>     - Compare two fights (summary)
/dt compare <a> <b> spells - Compare with per-ability breakdown
/dt delete <fight>      - Delete a specific snapshot
/dt config keepcount N  - Set retention count (default 3)
/dt help                - Show commands
```

Aliases: `/damagetracker`, `/dmg`

## Output Formats

### Summary View (`/dt`)

```
=== DamageTracker Boss History ===
Lucifron: 3 kills (latest: Jan-02, 1067 DPS (+7.3%))
Magmadar: 2 kills (latest: Jan-02, 982 DPS (-2.1%))
Ragnaros: 1 kill (latest: Dec-26, 1124 DPS)
```

Percentage shows change from previous kill. Green for improvement, red for regression.

### Summary Comparison (`/dt compare Lucifron Lucifron-2`)

```
=== Lucifron: Jan-02 vs Dec-26 ===
DPS:        1067.1 vs  995.3  (+7.2%)
Damage:     48,230 vs 44,920  (+7.4%)
Combat Time: 45.2s vs  45.1s

Hit Rate:    96.8% vs  91.2%  (+5.6%)
Crit Rate:   19.3% vs  18.1%  (+1.2%)
Resists:     1 full, 3 partial vs 4 full, 8 partial
Dmg Lost:    1,200 vs 3,840   (-68.8%)
```

### Per-Ability Comparison (`/dt compare Lucifron Lucifron-2 spells`)

```
=== Lucifron: Jan-02 vs Dec-26 (Per-Ability) ===

Frostbolt:
  DPS:      710.2 vs 658.4  (+7.9%)
  Hit%:     97.2% vs 89.3%  (+7.9%)
  Crit%:    22.1% vs 21.8%  (+0.3%)
  Dmg Lost: 800 vs 2,400    (-66.7%)

Cone of Cold:
  DPS:      186.3 vs 178.1  (+4.6%)
  Hit%:     95.0% vs 92.5%  (+2.5%)
  Crit%:    15.2% vs 14.8%  (+0.4%)
  Dmg Lost: 400 vs 1,440    (-72.2%)
```

## Implementation Phases

1. **Strip combat parsing** - Remove all `CHAT_MSG_COMBAT_*` handlers and pattern matching (~300 lines deleted)

2. **Add DPSMate reader** - Module to extract player data from DPSMate structures, translate array indices to readable fields

3. **Auto-capture hook** - On `PLAYER_REGEN_ENABLED`, poll DPSMate for new segments after short delay

4. **Date utilities** - Parse flexible date formats (YYYY-MM-DD, Jan-02, january-02, etc.)

5. **Name resolver** - Convert `Lucifron-2` or `Lucifron-Jan-02` to actual snapshot

6. **Comparison engine** - Calculate deltas and format output with colors

7. **Pruning logic** - Enforce retention limit per boss on each new save

## Error Handling

| Scenario | Behavior |
|----------|----------|
| DPSMate not installed | Disable auto-capture, show warning once |
| DPSMate data format changed | Log error, skip snapshot |
| Corrupt snapshot | Skip in comparisons, warn user |
| Fight has no name (trash) | Skip silently |

## Removed Features

The following features from the original DamageTracker are removed:

- Combat log parsing (DPSMate handles this)
- `/dmg reset`, `/dmg session`, `/dmg melee`, `/dmg spells` (use DPSMate for live tracking)
- `/dmg save <name>` (replaced by auto-capture)
- `/dmg lifetime` (not needed for boss comparison use case)

## Testing Strategy

- Manual testing in-game with MC/BWL clears
- Verify extracted data matches DPSMate's detail view
- Test date parsing with various formats
- Test retention pruning with >3 kills of same boss
