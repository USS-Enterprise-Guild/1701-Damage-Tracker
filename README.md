# DamageTracker - DPSMate Companion

A World of Warcraft 1.12 addon that stores historical boss fight data from DPSMate for cross-session comparison.

## Purpose

Measure whether gear changes (especially hit rating) translate to actual DPS improvements by comparing your performance on the same boss across multiple kills.

## Requirements

- **DPSMate** addon must be installed and enabled

## Installation

1. Install DPSMate if not already installed
2. Copy `DamageTracker` folder to `Interface/AddOns/`
3. Restart WoW or `/reload`

## Commands

| Command | Description |
|---------|-------------|
| `/dt` | Show boss history summary with DPS trends |
| `/dt list` | List all stored boss fights |
| `/dt show <fight>` | Show detailed stats for a fight |
| `/dt compare <a> <b>` | Compare two fights (summary) |
| `/dt compare <a> <b> spells` | Compare with per-ability breakdown |
| `/dt delete <fight>` | Delete a specific snapshot |
| `/dt config keepcount N` | Set how many kills to keep per boss (default 3) |
| `/dt help` | Show all commands |

## Fight Identifiers

| Format | Example | Meaning |
|--------|---------|---------|
| Boss name | `Lucifron` | Most recent kill |
| Index | `Lucifron-2` | Second most recent kill |
| Date (short) | `Lucifron-Jan-02` | Kill on January 2nd |
| Date (full) | `Lucifron-2025-01-02` | Kill on specific date |

Month names are case-insensitive: `jan`, `Jan`, `JANUARY` all work.

## Example Usage

```
/dt
=== DamageTracker Boss History ===
Lucifron: 3 kills (latest: Jan-02, 1067 DPS (+7.3%))
Magmadar: 2 kills (latest: Jan-02, 982 DPS (-2.1%))

/dt compare Lucifron Lucifron-2
=== Lucifron: Jan-02 vs Dec-26 ===
DPS:        1067.1 (+7.2%)
Hit Rate:   96.8% vs 91.2%  (+5.6%)
Dmg Lost:   1,200 vs 3,840  (-68.8%)
```

## How It Works

1. DPSMate tracks your combat data as usual
2. When combat ends, DamageTracker checks for new DPSMate fight segments
3. Named boss fights are automatically saved with your personal stats
4. Old snapshots are pruned based on `keepcount` setting

## Version History

- **2.0.0** - Complete rewrite as DPSMate companion
- **1.x** - Original standalone combat parser (deprecated)
