# Swarajya: The Maratha Age - Version 1.0 (content-complete, untested)

Turn-based grand strategy for Android (portrait, touch). Built with **Godot 4.3+** (GDScript).

> **Status: written but never run.** This code was produced without a Godot editor, so no
> version (0.1 to 1.0) has been opened, played or exported yet. "1.0" means every roadmap feature
> now exists in code, not that it is tested or balanced. Expect small errors on first launch and
> uneven balance. Paste errors from Godot's Output panel back to Claude to fix them.

## Contents
**Four campaigns across three eras**
| Era | Campaign | Turns |
|---|---|---|
| 1 | The Fort Consolidation of the Pune Highlands, c. 1646-49 | 24 |
| 1 | The Expedition of 1659 | 12 |
| 2 | The Peshwa's Deccan and Malwa Campaigns, c. 1727-38 (3 factions) | 20 |
| 3 | The Last Peshwa's War, 1817-18 (survive 8 turns) | 8 |

**Also:** Sandbox (any map, any faction, conquest win), Historical Codex, Timeline, diplomacy (truces),
territory development, fort repair, monsoon quarter, scripted events with choices, procedural sound effects,
personality-driven AI (aggressive / balanced / defensive), versioned saves (v1 and v2 saves migrate).

## Quick start (desktop)
1. Install Godot 4.3 or newer (standard build, not .NET): https://godotengine.org
2. Unzip, open Godot, **Import** `project.godot`, press **Play** (F5).
3. Optional smoke tests: `godot --headless --path . res://tests/test_runner.tscn`
   (open the project once in the editor first). **The tests overwrite your save file.**

## How to play
- Tap a territory with your army to select it (green rings = can move, red = can attack). Tap a green one to move; tap a red one for the battle screen (Aggressive / Balanced / Cautious / Besiege).
- **Sieges** lower fort walls (guns more). Walls rebuild when not besieged, or pay to **Repair**.
- **Recruit / Develop** in territories you hold. Forts and their neighbours form a **fort network** (cheaper recruits, faster movement).
- **Supply** falls with distance from a fort or core territory. **Monsoon** (quarter 3) hurts supply outside fort networks and slows sieges.
- **Diplomacy** (Menu): a rival accepts a truce if your forces are at least as strong, or they are worn down. 20 revenue, 3 turns.
- **Events** appear at set turns with choices and a confidence-tagged historical note.
- **Sandbox** (main menu): choose map and faction, optional rich start. Events and turn limits are off.
- Settings: AI difficulty, sound on/off.

## Android
See `docs/ANDROID_BUILD.md` and `docs/RELEASE_CHECKLIST.md`.

## Layout
```
project.godot            autoloads: Game (data + state), Sfx (generated sounds)
scenes/                  main_menu, era_select, sandbox, game, codex, timeline
scripts/core/            game.gd, rules.gd, turn_manager.gd, sfx.gd
scripts/combat/ ai/ save/ ui/
data/                    terrain, units, factions, commanders, timeline
data/campaigns/<id>/     scenario.json (start state, events), territories.json, forts.json
docs/                    SOURCES.md, ARCHITECTURE.md, ANDROID_BUILD.md, RELEASE_CHECKLIST.md
tests/                   headless smoke tests
```

## Known limitations
- **Never run, never balanced.** AI difficulty is the main tuning lever; expect to adjust numbers in `data/`.
- No fog of war (the AI sees everything). No music (only short generated sound effects). Placeholder vector art; the map is schematic.
- Third Battle of Panipat (1761) and the Second Anglo-Maratha War (1803) appear on the Timeline but are not playable campaigns.
- One save slot. Diplomacy covers truces only.
- Historical entries are hedged and tagged; source pointers are real books but **not verified page by page**. Era II and III entries in particular need a verification pass.
