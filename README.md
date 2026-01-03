# DamageTracker

A combat statistics addon for WoW 1.12 that tracks all your damage output, hits, misses, and resists. Designed for comparing gear effectiveness. Data persists between sessions.

## Installation

1. Copy the `DamageTracker` folder to your `Interface/AddOns` directory
2. Restart WoW or `/reload` if already in-game

## Commands

### Current Session

| Command | Description |
|---------|-------------|
| `/dmg` | Show overall session statistics |
| `/dmg reset` | Reset session (automatically saves to history) |
| `/dmg spells` | Show per-spell breakdown |
| `/dmg melee` | Show detailed melee statistics |
| `/dmg session` | Show session timing information |

### Snapshots (Gear Comparison)

| Command | Description |
|---------|-------------|
| `/dmg save <name>` | Save current stats as a named snapshot |
| `/dmg snapshots` | List all saved snapshots |
| `/dmg load <name>` | View details of a saved snapshot |
| `/dmg delete <name>` | Delete a snapshot |
| `/dmg compare <a> <b>` | Compare two snapshots side-by-side |

### History & Lifetime

| Command | Description |
|---------|-------------|
| `/dmg history` | View past sessions (last 10) |
| `/dmg lifetime` | Show all-time cumulative statistics |

### Other

| Command | Description |
|---------|-------------|
| `/dmg help` | Display available commands |

Aliases: `/damage`, `/dt`

## What Gets Tracked

### Melee
- **Hits & Crits** - Successful melee attacks with damage totals
- **Glancing Blows** - Reduced damage hits against higher level targets
- **Misses** - Attacks that missed entirely
- **Dodges** - Attacks dodged by the target
- **Parries** - Attacks parried by the target
- **Blocks** - Attacks blocked by the target

### Spells
- **Hits & Crits** - Successful spell casts with damage totals
- **Full Resists** - Spells completely resisted (0 damage)
- **Partial Resists** - Spells that dealt reduced damage
- **Resisted Damage** - Total damage lost to partial resists

### Session
- **Combat Time** - Actual time spent in combat
- **DPS** - Damage per second based on combat time
- **Session Duration** - Total time since addon load or last reset

## Data Persistence

All data is saved automatically via WoW's SavedVariables system:

- **Session History**: Last 50 sessions are kept per character
- **Snapshots**: Named snapshots persist until manually deleted
- **Lifetime Stats**: Cumulative statistics across all sessions
- **Per-Character**: Each character has separate data

Data is saved when you:
- Log out
- Reload UI (`/reload`)
- Reset the session (`/dmg reset`)

## Gear Comparison Workflow

1. Equip your first gear set
2. Fight mobs/bosses for a few minutes to gather data
3. Run `/dmg save gearset1` to snapshot the results
4. Run `/dmg reset` to start fresh
5. Equip your second gear set
6. Fight the same mobs/bosses for similar duration
7. Run `/dmg save gearset2` to snapshot
8. Run `/dmg compare gearset1 gearset2` to see the difference

### Example Compare Output

```
1701_DamageTracker: === Comparing: tier1 vs tier2 ===
1701_DamageTracker: tier1: 45,230 dmg | 221.4 DPS
1701_DamageTracker: tier2: 52,180 dmg | 248.7 DPS
1701_DamageTracker: --- Difference ---
1701_DamageTracker: DPS: 27.3 (+12.3%)
1701_DamageTracker: Total Damage: 6950 (+15.4%)
1701_DamageTracker: Melee Hit%: 93.8% vs 95.2%
1701_DamageTracker: Melee Crit%: 26.7% vs 28.1%
```

## Example Output

```
1701_DamageTracker: === Session Statistics ===
1701_DamageTracker: Total Damage: 45,230
1701_DamageTracker: Combat Time: 3m 24.5s | DPS: 221.4
1701_DamageTracker: Melee: 12,450 dmg | 45 hits (12 crit) | Hit: 93.8% | Crit: 26.7%
1701_DamageTracker:   Avoided: 2 miss, 1 dodge, 0 parry, 0 block
1701_DamageTracker: Spells: 32,780 dmg | 28 hits (8 crit) | Hit: 96.6% | Crit: 28.6%
1701_DamageTracker:   Resists: 1 full, 3 partial (520 dmg lost)
```

## API

The addon exposes functions for external use:

```lua
-- Get current session stats
local stats = DamageTracker1701.GetStats()

-- Get saved database (history, snapshots, lifetime)
local db = DamageTracker1701.GetDB()

-- Reset current session
DamageTracker1701.Reset()

-- Display the overview
DamageTracker1701.ShowOverview()

-- Save a snapshot programmatically
DamageTracker1701.SaveSnapshot("mySnapshot")

-- Compare two snapshots
DamageTracker1701.CompareSnapshots("snap1", "snap2")
```

### Database Structure

```lua
DamageTrackerDB = {
    ["CharacterName-Realm"] = {
        sessions = {
            -- Last 50 sessions
            { timestamp, combatTime, totalDamage, dps, melee, spell, spells },
            ...
        },
        snapshots = {
            ["SnapshotName"] = { timestamp, combatTime, totalDamage, dps, melee, spell, spells },
            ...
        },
        lifetime = {
            totalDamage = 0,
            totalCombatTime = 0,
            melee = { hits, crits, misses, ... },
            spell = { hits, crits, resists, ... },
        },
    }
}
```

## Use Cases

- **Gear Comparison**: Save snapshots with different gear sets and compare DPS/hit rates
- **Hit Cap Testing**: Check your miss rate against raid bosses to see if you need more +hit
- **Spell Resist Analysis**: Track which spells get resisted most to optimize spell penetration
- **Crit Rate Validation**: Verify your actual crit rate matches your character sheet
- **Long-term Tracking**: Use lifetime stats to see overall performance trends
