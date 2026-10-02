extends RefCounted
## Pure combat maths. No state is mutated here except the units dictionaries
## passed to apply_losses(). All numbers are gameplay abstractions.

const TACTICS = {
	"aggressive": {"label": "Aggressive assault", "attack": 1.20, "own_losses": 1.25},
	"balanced": {"label": "Balanced assault", "attack": 1.00, "own_losses": 1.00},
	"cautious": {"label": "Cautious probe", "attack": 0.85, "own_losses": 0.75}
}


static func force_power(units: Dictionary, terrain_id: String, commander_id: String,
		morale: float, supply: float, is_attack: bool) -> float:
	var total: float = 0.0
	var tmods: Dictionary = Game.terrain[terrain_id]["unit_mod"]
	for ut in units:
		var n: float = float(units[ut])
		if n <= 0.0:
			continue
		var u: Dictionary = Game.units[ut]
		var base: float = float(u["attack"]) if is_attack else float(u["defense"])
		total += n * base * float(tmods.get(ut, 1.0))
	var cmd_mod: float = 0.0
	if commander_id != "" and Game.commanders.has(commander_id):
		var g: Dictionary = Game.commanders[commander_id]["gameplay"]
		cmd_mod = float(g["attack_mod"]) if is_attack else float(g["defense_mod"])
	var morale_f: float = 0.6 + 0.4 * clampf(morale, 0.0, 100.0) / 100.0
	var supply_f: float = 0.7 + 0.3 * clampf(supply, 0.0, 100.0) / 100.0
	return total * (1.0 + cmd_mod) * morale_f * supply_f


static func fort_multiplier(fort_id: String, wall: float, attacker_units: Dictionary) -> float:
	if fort_id == "":
		return 1.0
	var f: Dictionary = Game.forts[fort_id]
	var wall_ratio: float = clampf(wall / float(f["wall_max"]), 0.0, 1.0)
	var reduction: float = minf(0.3, 0.05 * float(attacker_units.get("artillery", 0)))
	return 1.0 + float(f["defense"]) * wall_ratio * (1.0 - reduction)


## att / defn: {"units", "commander", "morale", "supply"}
static func estimate(att: Dictionary, defn: Dictionary, terrain_id: String,
		fort_id: String, wall: float, tactic: String) -> Dictionary:
	var tac: Dictionary = TACTICS.get(tactic, TACTICS["balanced"])
	var a: float = force_power(att["units"], terrain_id, att["commander"],
		float(att["morale"]), float(att["supply"]), true) * float(tac["attack"])
	var d: float = force_power(defn["units"], terrain_id, defn["commander"],
		float(defn["morale"]), float(defn["supply"]), false)
	d *= float(Game.terrain[terrain_id]["defense"])
	d *= fort_multiplier(fort_id, wall, att["units"])
	return {"attack": a, "defense": d}


static func resolve(att: Dictionary, defn: Dictionary, terrain_id: String,
		fort_id: String, wall: float, tactic: String, rng: RandomNumberGenerator) -> Dictionary:
	var est: Dictionary = estimate(att, defn, terrain_id, fort_id, wall, tactic)
	var variance: float = rng.randf_range(0.92, 1.08)
	var a: float = float(est["attack"]) * variance
	var d: float = float(est["defense"])
	var attacker_wins: bool = a > d
	var share: float = a / maxf(0.0001, a + d)
	var win_share: float = share if attacker_wins else 1.0 - share
	var win_loss: float = 0.12 + 0.25 * (1.0 - win_share)
	var lose_loss: float = 0.35 + 0.40 * win_share
	var tac: Dictionary = TACTICS.get(tactic, TACTICS["balanced"])
	var att_frac: float = win_loss if attacker_wins else lose_loss
	var def_frac: float = lose_loss if attacker_wins else win_loss
	att_frac = clampf(att_frac * float(tac["own_losses"]), 0.05, 0.9)
	return {
		"attacker_power": float(est["attack"]),
		"defender_power": d,
		"variance": variance,
		"attacker_wins": attacker_wins,
		"attacker_loss_frac": att_frac,
		"defender_loss_frac": clampf(def_frac, 0.05, 0.9)
	}


## Removes casualties from `units` in place and returns what was lost.
static func apply_losses(units: Dictionary, frac: float, min_one: bool) -> Dictionary:
	var lost: Dictionary = {}
	for ut in units.keys():
		var n: int = int(units[ut])
		var l: int = int(round(float(n) * frac))
		if min_one and l == 0 and n > 0 and frac >= 0.1:
			l = 1
		l = mini(l, n)
		if l > 0:
			units[ut] = n - l
			lost[ut] = l
	return lost


static func odds_label(ratio: float) -> String:
	if ratio >= 1.6:
		return "Overwhelming"
	if ratio >= 1.2:
		return "Favourable"
	if ratio >= 0.95:
		return "Even"
	if ratio >= 0.7:
		return "Unfavourable"
	return "Hopeless"
