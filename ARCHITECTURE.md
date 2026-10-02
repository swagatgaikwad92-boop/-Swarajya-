# Architecture

- **State** is one plain Dictionary (`Game.state`): territories, armies, factions, log, stats.
  It is saved as JSON; `SaveSystem.normalize()` restores ints after loading.
- **Static data:** shared files (`terrain`, `units`, `factions`, `commanders`, `timeline`) load once. Each campaign has its own folder `data/campaigns/<id>/` (scenario, territories, forts); `Game.load_scenario(id)` swaps the active one. Neighbour links are made symmetric on load.
- **Save format v2** adds quarter, diplomacy, events and development; `SaveSystem._migrate` upgrades v1 saves. `Game.continue_campaign()` peeks the saved scenario id first.
- **Events** are defined in `scenario.json` (turn, choices, effects). `Rules.queue_event` sets `pending_event`; the UI shows it and calls `Rules.resolve_event`.
- **Diplomacy** keeps truces in `state.diplomacy`; `Rules.attack_targets` excludes truce-protected territories, so AI and player obey the same rule.
- **Rules** (`rules.gd`) are static functions on the state: movement, recruitment, garrisons,
  sieges, battles, economy, supply, end conditions. Actions return `{ok, msg}`.
- **Combat** (`combat_resolver.gd`) is pure maths: power = units x stats x terrain x commander x morale x supply;
  fort walls multiply defence; casualties scale with the power share; a seeded RNG (stored in the save) adds +-8%.
- **AI** (`ai_player.gd`): attack if the power ratio beats a difficulty threshold, siege forts with guns,
  advance toward the nearest enemy territory when odds are plausible, recruit near the front.
- **Turn** (`turn_manager.gd`): AI acts, then economy, wall repair, supply/morale, move reset, end check.
- **UI** is built in code (`ui_kit.gd`); scenes are single nodes holding scripts.
- No cyclic preloads: Rules -> CombatResolver; AIPlayer -> Rules; TurnManager -> Rules, AIPlayer.

## Extending
- New scenario: add a JSON under `data/campaigns/` and point `Game.SCENARIO_PATH` at it.
- New territory/fort: add entries to `territories.json` / `forts.json` and the scenario `start` block.
- Planned: fog of war, diplomacy, events, leader traits, more eras.

## Added in 1.0
- **Victory modes** (`scenario.json` -> `victory.mode`): `capture` (hold all objective forts, immediate win) and `survive` (at the time limit, hold at least `hold_min` of them).
- **Sandbox** is a state flag (`state.sandbox`): events are skipped, win = all rivals eliminated, lose = eliminated, no turn limit.
- **AI** (`ai_player.gd`): per-faction style from `scenario.json` -> `ai_styles` shifts the attack threshold; armies in one territory merge; surplus gold goes to wall repair and development; objectives are chosen by value x weakness / distance.
- **Sfx** autoload generates short tones in code (`AudioStreamWAV`), so no audio assets are needed.
- Save format v3 adds `sandbox`; older saves migrate on load.
