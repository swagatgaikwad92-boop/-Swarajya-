extends RefCounted
## Core rules. Operates on the plain-Dictionary game state so it can be saved as JSON.
## Every number here is a gameplay abstraction unless a data file says otherwise.

const CombatResolver = preload("res://scripts/combat/combat_resolver.gd")

const ARMY_CAP = 14            # max units in one army
const WALL_REPAIR = 8          # wall points repaired per turn if not besieged
const NETWORK_MOVE_BONUS = 1   # move-cost reduction between fort-network territories
const MANPOWER_CAP = 40


# ---------------------------------------------------------------- results
static func _ok(msg: String = "") -> Dictionary:
	return {"ok": true, "msg": msg}


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "msg": msg}


# ---------------------------------------------------------------- setup
static func new_state(opts: Dictionary = {}) -> Dictionary:
	var sc: Dictionary = Game.scenario
	var start: Dictionary = sc["start"]
	var s: Dictionary = {
		"save_version": 3,
		"scenario_id": sc["id"],
		"player": str(opts.get("player", sc["player_faction"])),
		"sandbox": bool(opts.get("sandbox", false)),
		"turn": 1,
		"year": int(sc["start_year"]),
		"quarter": 1,
		"max_turns": int(sc["max_turns"]),
		"rng_seed": 20260101,
		"status": "playing",
		"end_reason": "",
		"difficulty": "normal",
		"territories": {},
		"armies": [],
		"factions": {},
		"next_army_id": 1,
		"log": [],
		"log_count": 0,
		"diplomacy": {"truces": {}, "cooldown": 0},
		"events_fired": [],
		"pending_event": "",
		"stats": {"battles_won": 0, "battles_lost": 0, "forts_captured": 0, "forts_lost": 0, "turns_played": 0}
	}
	for tid in start["territories"]:
		var t: Dictionary = start["territories"][tid]
		var fort_id: String = str(Game.territories[tid].get("fort", ""))
		var wall: float = 0.0
		if fort_id != "":
			wall = float(t.get("wall", Game.forts[fort_id]["wall_max"]))
		s["territories"][tid] = {
			"owner": t["owner"],
			"garrison": _int_units(t.get("garrison", {})),
			"wall": wall,
			"besieged": false,
			"dev": 0
		}
	for fid in start["factions"]:
		var f: Dictionary = start["factions"][fid]
		s["factions"][fid] = {"gold": int(f["gold"]), "manpower": int(f["manpower"]),
			"stability": int(f["stability"]), "start_territories": 0, "last_income": 0, "last_upkeep": 0, "weariness": 0}
	for tid in s["territories"]:
		var o: String = s["territories"][tid]["owner"]
		s["factions"][o]["start_territories"] += 1
	for a in start["armies"]:
		add_army(s, a["owner"], str(a.get("commander", "")), a["territory"],
			_int_units(a["units"]), str(a.get("role", "field")))
	if bool(opts.get("rich", false)):
		s["factions"][s["player"]]["gold"] += 200
		s["factions"][s["player"]]["manpower"] += 20
	sync_calendar(s)
	add_log(s, ("Sandbox begins: " if bool(s["sandbox"]) else "Campaign begins: ") + str(sc["title"]))
	queue_event(s)
	return s


static func _int_units(d) -> Dictionary:
	var out: Dictionary = {}
	for k in d:
		out[k] = int(d[k])
	return out


static func add_log(s: Dictionary, line: String) -> void:
	s["log_count"] = int(s.get("log_count", 0)) + 1
	s["log"].append("T%d: %s" % [int(s["turn"]), line])
	while s["log"].size() > 200:
		s["log"].pop_front()


static func add_army(s: Dictionary, owner: String, commander: String, tid: String,
		units: Dictionary, role: String = "field") -> Dictionary:
	var army: Dictionary = {
		"id": int(s["next_army_id"]), "owner": owner, "commander": commander,
		"territory": tid, "units": units, "morale": 80.0, "supply": 100.0,
		"moves_left": 0, "role": role
	}
	s["next_army_id"] = int(s["next_army_id"]) + 1
	army["moves_left"] = army_speed(army)
	s["armies"].append(army)
	return army


# ---------------------------------------------------------------- lookups
static func army_by_id(s: Dictionary, id):
	for a in s["armies"]:
		if int(a["id"]) == int(id):
			return a
	return null


static func armies_at(s: Dictionary, tid: String) -> Array:
	var out: Array = []
	for a in s["armies"]:
		if a["territory"] == tid:
			out.append(a)
	return out


static func faction_armies(s: Dictionary, fid: String) -> Array:
	var out: Array = []
	for a in s["armies"]:
		if a["owner"] == fid:
			out.append(a)
	return out


static func unit_total(units: Dictionary) -> int:
	var n: int = 0
	for ut in units:
		n += int(units[ut])
	return n


static func owner_of(s: Dictionary, tid: String) -> String:
	return str(s["territories"][tid]["owner"])


static func fort_id_of(tid: String) -> String:
	return str(Game.territories[tid].get("fort", ""))


static func has_fort(tid: String) -> bool:
	return fort_id_of(tid) != ""


static func neighbours(tid: String) -> Array:
	return Game.territories[tid]["neighbours"]


static func army_speed(army: Dictionary) -> int:
	var speed: int = 99
	var any: bool = false
	for ut in army["units"]:
		if int(army["units"][ut]) > 0:
			speed = mini(speed, int(Game.units[ut]["move"]))
			any = true
	if not any:
		return 0
	var cid: String = str(army.get("commander", ""))
	if cid != "" and Game.commanders.has(cid):
		speed += int(Game.commanders[cid]["gameplay"].get("speed_bonus", 0))
	return speed


## A territory with an owned fort, or next to one, is in that owner's fort network.
static func in_network(s: Dictionary, fid: String, tid: String) -> bool:
	if owner_of(s, tid) != fid:
		return false
	if has_fort(tid):
		return true
	for n in neighbours(tid):
		if owner_of(s, n) == fid and has_fort(n):
			return true
	return false


static func is_source(s: Dictionary, fid: String, tid: String) -> bool:
	if owner_of(s, tid) != fid:
		return false
	return has_fort(tid) or bool(Game.territories[tid].get("supply_source", false))


## Hops through own territory to the nearest supply source; -1 if cut off.
static func supply_distance(s: Dictionary, fid: String, tid: String) -> int:
	var visited: Dictionary = {tid: true}
	var frontier: Array = [tid]
	var d: int = 0
	while not frontier.is_empty():
		for t in frontier:
			if is_source(s, fid, t):
				return d
		var nxt: Array = []
		for t in frontier:
			for n in neighbours(t):
				if not visited.has(n) and owner_of(s, n) == fid:
					visited[n] = true
					nxt.append(n)
		frontier = nxt
		d += 1
	return -1


static func supply_target(s: Dictionary, fid: String, tid: String) -> float:
	var pen: float = float(Game.terrain[Game.territories[tid]["terrain"]]["supply_penalty"])
	if is_monsoon(s) and not in_network(s, fid, tid):
		pen += 10.0
	var d: int = supply_distance(s, fid, tid)
	var target: float = 0.0
	if d < 0:
		target = 30.0 - pen
	else:
		target = 100.0 - 12.0 * float(d) - pen
	return clampf(target, 10.0, 100.0)


## Hops from tid to the nearest territory not owned by fid (0 if tid itself is not).
static func distance_to_enemy(s: Dictionary, fid: String, tid: String) -> int:
	var visited: Dictionary = {tid: true}
	var frontier: Array = [tid]
	var d: int = 0
	while not frontier.is_empty():
		for t in frontier:
			if owner_of(s, t) != fid:
				return d
		var nxt: Array = []
		for t in frontier:
			for n in neighbours(t):
				if not visited.has(n):
					visited[n] = true
					nxt.append(n)
		frontier = nxt
		d += 1
	return 99


# ---------------------------------------------------------------- movement
static func move_cost(s: Dictionary, army: Dictionary, tid: String) -> int:
	var base: int = int(Game.terrain[Game.territories[tid]["terrain"]]["move_cost"])
	var fid: String = army["owner"]
	if in_network(s, fid, army["territory"]) and in_network(s, fid, tid):
		base = maxi(1, base - NETWORK_MOVE_BONUS)
	return base


static func can_move(s: Dictionary, army: Dictionary, tid: String) -> bool:
	if army["territory"] == tid:
		return false
	if not neighbours(army["territory"]).has(tid):
		return false
	if owner_of(s, tid) != army["owner"]:
		return false
	var left: int = int(army["moves_left"])
	if left <= 0:
		return false
	# A fresh army can always make one move, however rough the terrain.
	return left >= move_cost(s, army, tid) or left >= army_speed(army)


static func move_army(s: Dictionary, army: Dictionary, tid: String) -> void:
	var cost: int = move_cost(s, army, tid)
	army["moves_left"] = maxi(0, int(army["moves_left"]) - cost)
	army["territory"] = tid


static func attack_targets(s: Dictionary, army: Dictionary) -> Array:
	var out: Array = []
	if int(army["moves_left"]) <= 0 or unit_total(army["units"]) <= 0:
		return out
	for n in neighbours(army["territory"]):
		var o: String = owner_of(s, n)
		if o != army["owner"] and not has_truce(s, army["owner"], o):
			out.append(n)
	return out


# ---------------------------------------------------------------- recruitment
static func recruit_cost(s: Dictionary, fid: String, tid: String, ut: String) -> int:
	var cost: int = int(Game.units[ut]["cost"])
	if in_network(s, fid, tid):
		cost = int(ceil(float(cost) * 0.9))
	return cost


static func can_recruit(s: Dictionary, fid: String, tid: String, ut: String) -> Dictionary:
	if owner_of(s, tid) != fid:
		return _fail("You do not hold this territory.")
	if not Game.factions[fid]["recruitable"].has(ut):
		return _fail("That unit is not available to this faction.")
	var f: Dictionary = s["factions"][fid]
	if int(f["gold"]) < recruit_cost(s, fid, tid, ut):
		return _fail("Not enough revenue.")
	if int(f["manpower"]) < int(Game.units[ut]["manpower"]):
		return _fail("Not enough manpower.")
	return _ok()


static func recruit(s: Dictionary, fid: String, tid: String, ut: String) -> Dictionary:
	var check: Dictionary = can_recruit(s, fid, tid, ut)
	if not check["ok"]:
		return check
	var f: Dictionary = s["factions"][fid]
	f["gold"] = int(f["gold"]) - recruit_cost(s, fid, tid, ut)
	f["manpower"] = int(f["manpower"]) - int(Game.units[ut]["manpower"])
	for a in armies_at(s, tid):
		if a["owner"] == fid and unit_total(a["units"]) < ARMY_CAP:
			a["units"][ut] = int(a["units"].get(ut, 0)) + 1
			return _ok("Recruited %s." % Game.units[ut]["name"])
	var army: Dictionary = add_army(s, fid, "", tid, {ut: 1}, "field")
	army["moves_left"] = 0
	return _ok("Raised a new army with %s." % Game.units[ut]["name"])


# ---------------------------------------------------------------- garrison
static func garrison_capacity(tid: String) -> int:
	var fid: String = fort_id_of(tid)
	if fid == "":
		return 0
	return int(Game.forts[fid]["garrison_capacity"])


static func leave_garrison(s: Dictionary, army: Dictionary) -> Dictionary:
	var tid: String = army["territory"]
	var cap: int = garrison_capacity(tid)
	if cap <= 0:
		return _fail("Only fort territories can hold a garrison.")
	var inf: int = int(army["units"].get("infantry", 0))
	if inf <= 1:
		return _fail("Not enough infantry to spare.")
	var gar: Dictionary = s["territories"][tid]["garrison"]
	var room: int = cap - unit_total(gar)
	var amount: int = mini(maxi(1, int(round(float(inf) * 0.4))), room)
	if amount <= 0:
		return _fail("Garrison is full.")
	army["units"]["infantry"] = inf - amount
	gar["infantry"] = int(gar.get("infantry", 0)) + amount
	return _ok("%d infantry left in the garrison." % amount)


static func draw_garrison(s: Dictionary, army: Dictionary) -> Dictionary:
	var tid: String = army["territory"]
	var gar: Dictionary = s["territories"][tid]["garrison"]
	if unit_total(gar) <= 0:
		return _fail("No garrison to draw from.")
	var moved: int = 0
	for ut in gar.keys():
		while int(gar[ut]) > 0 and unit_total(army["units"]) < ARMY_CAP:
			gar[ut] = int(gar[ut]) - 1
			army["units"][ut] = int(army["units"].get(ut, 0)) + 1
			moved += 1
	if moved == 0:
		return _fail("Army is at full strength.")
	return _ok("%d units rejoined the army." % moved)


# ---------------------------------------------------------------- battle
static func gather_defenders(s: Dictionary, tid: String) -> Dictionary:
	var t: Dictionary = s["territories"][tid]
	var units: Dictionary = {}
	var weight: float = 0.0
	var morale_sum: float = 0.0
	var supply_sum: float = 0.0
	var best_cmd: String = ""
	var best_mod: float = -1.0
	var gar: Dictionary = t["garrison"]
	var gtotal: int = unit_total(gar)
	for ut in gar:
		units[ut] = int(units.get(ut, 0)) + int(gar[ut])
	if gtotal > 0:
		weight += float(gtotal)
		morale_sum += float(gtotal) * 80.0
		supply_sum += float(gtotal) * 100.0
	for a in armies_at(s, tid):
		var n: int = unit_total(a["units"])
		for ut in a["units"]:
			units[ut] = int(units.get(ut, 0)) + int(a["units"][ut])
		weight += float(n)
		morale_sum += float(n) * float(a["morale"])
		supply_sum += float(n) * float(a["supply"])
		var cid: String = str(a.get("commander", ""))
		if cid != "" and Game.commanders.has(cid):
			var m: float = float(Game.commanders[cid]["gameplay"]["defense_mod"])
			if m > best_mod:
				best_mod = m
				best_cmd = cid
	if weight <= 0.0:
		return {"units": units, "commander": "", "morale": 80.0, "supply": 100.0}
	return {"units": units, "commander": best_cmd, "morale": morale_sum / weight, "supply": supply_sum / weight}


static func _army_force(army: Dictionary) -> Dictionary:
	return {"units": army["units"], "commander": str(army.get("commander", "")),
		"morale": army["morale"], "supply": army["supply"]}


## Estimated powers for UI and AI. No randomness.
static func battle_preview(s: Dictionary, army: Dictionary, tid: String, tactic: String) -> Dictionary:
	var td: Dictionary = Game.territories[tid]
	var ts: Dictionary = s["territories"][tid]
	var defn: Dictionary = gather_defenders(s, tid)
	var est: Dictionary = CombatResolver.estimate(_army_force(army), defn, td["terrain"],
		fort_id_of(tid), float(ts["wall"]), tactic)
	est["ratio"] = float(est["attack"]) / maxf(0.01, float(est["defense"]))
	est["defenders"] = defn
	return est


static func _merge_counts(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		dst[k] = int(dst.get(k, 0)) + int(src[k])


static func _stab(s: Dictionary, fid: String, delta: int) -> void:
	var f: Dictionary = s["factions"][fid]
	f["stability"] = clampi(int(f["stability"]) + delta, 0, 100)


static func besiege(s: Dictionary, army: Dictionary, tid: String) -> Dictionary:
	if not attack_targets(s, army).has(tid):
		return _fail("That territory cannot be besieged now.")
	if not has_fort(tid):
		return _fail("There is no fort to besiege.")
	var ts: Dictionary = s["territories"][tid]
	if float(ts["wall"]) <= 0.0:
		return _fail("The walls are already breached.")
	var art: int = int(army["units"].get("artillery", 0))
	var dmg: float = 12.0 + 10.0 * float(art)
	if is_monsoon(s):
		dmg *= 0.75
	ts["wall"] = maxf(0.0, float(ts["wall"]) - dmg)
	ts["besieged"] = true
	army["moves_left"] = 0
	army["supply"] = maxf(0.0, float(army["supply"]) - 8.0)
	var msg: String = "Besieged %s: walls down by %d to %d." % [
		Game.territories[tid]["name"], int(dmg), int(ts["wall"])]
	add_log(s, "%s army #%d. %s" % [Game.factions[army["owner"]]["short_name"], int(army["id"]), msg])
	return _ok(msg)


static func attack(s: Dictionary, army: Dictionary, tid: String, tactic: String) -> Dictionary:
	if not attack_targets(s, army).has(tid):
		return _fail("That territory cannot be attacked now.")
	var td: Dictionary = Game.territories[tid]
	var ts: Dictionary = s["territories"][tid]
	var attacker_owner: String = army["owner"]
	var defender_owner: String = ts["owner"]
	var fort_id: String = fort_id_of(tid)
	var defn: Dictionary = gather_defenders(s, tid)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s["rng_seed"])
	s["rng_seed"] = int(s["rng_seed"]) + 7919
	var r: Dictionary = CombatResolver.resolve(_army_force(army), defn, td["terrain"],
		fort_id, float(ts["wall"]), tactic, rng)
	var wins: bool = r["attacker_wins"]

	var att_losses: Dictionary = CombatResolver.apply_losses(army["units"], r["attacker_loss_frac"], not wins)
	var def_losses: Dictionary = {}
	_merge_counts(def_losses, CombatResolver.apply_losses(ts["garrison"], r["defender_loss_frac"], wins))
	var def_armies: Array = armies_at(s, tid).duplicate()
	for a in def_armies:
		_merge_counts(def_losses, CombatResolver.apply_losses(a["units"], r["defender_loss_frac"], wins))
		a["morale"] = clampf(float(a["morale"]) + (-20.0 if wins else 5.0), 5.0, 100.0)

	army["morale"] = clampf(float(army["morale"]) + (10.0 if wins else -20.0), 5.0, 100.0)
	army["supply"] = maxf(0.0, float(army["supply"]) - 10.0)
	army["moves_left"] = 0

	var captured: bool = false
	var strat: int = 0
	if fort_id != "":
		strat = int(Game.forts[fort_id]["strategic"])
	var player: String = s["player"]

	if wins:
		captured = true
		ts["owner"] = attacker_owner
		ts["garrison"] = {}
		ts["besieged"] = false
		if fort_id != "":
			ts["wall"] = float(Game.forts[fort_id]["wall_max"]) * 0.4
		for a in def_armies:
			_retreat(s, a, tid, defender_owner)
		army["territory"] = tid
		_stab(s, attacker_owner, 2 + (int(round(float(strat) * 0.6)) if fort_id != "" else 0))
		_stab(s, defender_owner, -3 - strat)
		s["factions"][defender_owner]["weariness"] += 1 + (2 if fort_id != "" else 0)
		if attacker_owner == player:
			s["stats"]["battles_won"] += 1
			if fort_id != "":
				s["stats"]["forts_captured"] += 1
		elif defender_owner == player:
			s["stats"]["battles_lost"] += 1
			if fort_id != "":
				s["stats"]["forts_lost"] += 1
	else:
		s["factions"][attacker_owner]["weariness"] += 1
		_stab(s, attacker_owner, -2)
		_stab(s, defender_owner, 1)
		if attacker_owner == player:
			s["stats"]["battles_lost"] += 1
		elif defender_owner == player:
			s["stats"]["battles_won"] += 1

	_cleanup_armies(s)

	var msg: String = "%s attacked %s (%s). %s." % [
		Game.factions[attacker_owner]["short_name"], td["name"],
		CombatResolver.TACTICS[tactic]["label"] if CombatResolver.TACTICS.has(tactic) else tactic,
		("The attack succeeded and the territory was taken" if wins else "The attack was repulsed")]
	add_log(s, msg)
	check_end(s)
	return {
		"ok": true, "msg": msg, "attacker_wins": wins, "captured": captured, "fort": fort_id != "",
		"territory": tid, "attacker_owner": attacker_owner, "defender_owner": defender_owner,
		"attacker_power": r["attacker_power"], "defender_power": r["defender_power"],
		"attacker_losses": att_losses, "defender_losses": def_losses
	}


static func _retreat(s: Dictionary, army: Dictionary, from_tid: String, owner: String) -> void:
	var dest: String = ""
	for n in neighbours(from_tid):
		if owner_of(s, n) == owner:
			if dest == "" or (has_fort(n) and not has_fort(dest)):
				dest = n
	if dest == "":
		army["units"] = {}
		return
	army["territory"] = dest
	army["moves_left"] = 0


static func _cleanup_armies(s: Dictionary) -> void:
	var keep: Array = []
	for a in s["armies"]:
		if unit_total(a["units"]) > 0:
			keep.append(a)
	s["armies"] = keep


# ---------------------------------------------------------------- turn processing
static func process_economy(s: Dictionary) -> void:
	for fid in s["factions"]:
		var f: Dictionary = s["factions"][fid]
		var income: int = 0
		var manpower: int = 0
		var owned: int = 0
		for tid in s["territories"]:
			if s["territories"][tid]["owner"] == fid:
				income += territory_revenue(s, tid)
				manpower += int(Game.territories[tid]["manpower"])
				owned += 1
		var men: int = 0
		for a in faction_armies(s, fid):
			men += unit_total(a["units"])
		var gar: int = 0
		for tid in s["territories"]:
			if s["territories"][tid]["owner"] == fid:
				gar += unit_total(s["territories"][tid]["garrison"])
		var upkeep: int = int(ceil(float(men) / 5.0)) + int(ceil(float(gar) / 10.0))
		f["gold"] = maxi(0, int(f["gold"]) + income - upkeep)
		f["manpower"] = mini(MANPOWER_CAP, int(f["manpower"]) + manpower)
		f["last_income"] = income
		f["last_upkeep"] = upkeep
		var drift: int = clampi(owned - int(f["start_territories"]), -2, 2)
		if income < upkeep:
			drift -= 1
		_stab(s, fid, drift)


static func process_walls(s: Dictionary) -> void:
	for tid in s["territories"]:
		var fid: String = fort_id_of(tid)
		if fid == "":
			continue
		var ts: Dictionary = s["territories"][tid]
		if not bool(ts["besieged"]):
			ts["wall"] = minf(float(Game.forts[fid]["wall_max"]), float(ts["wall"]) + float(WALL_REPAIR))
		ts["besieged"] = false


static func process_armies(s: Dictionary) -> void:
	for a in s["armies"]:
		var fid: String = a["owner"]
		var tid: String = a["territory"]
		var target: float = supply_target(s, fid, tid)
		var sup: float = float(a["supply"])
		if sup < target:
			sup = minf(target, sup + 20.0)
		else:
			sup = maxf(target, sup - 10.0)
		a["supply"] = sup
		var morale_gain: float = 5.0 + (5.0 if in_network(s, fid, tid) else 0.0)
		if sup < 30.0:
			morale_gain = -5.0
		a["morale"] = clampf(float(a["morale"]) + morale_gain, 5.0, 100.0)
		a["moves_left"] = army_speed(a)


# ---------------------------------------------------------------- end conditions
static func _held_count(s: Dictionary, fort_ids: Array, fid: String) -> int:
	var n: int = 0
	for f in fort_ids:
		if owner_of(s, Game.forts[f]["territory"]) == fid:
			n += 1
	return n


static func check_end(s: Dictionary) -> void:
	if s["status"] != "playing":
		return
	var sc: Dictionary = Game.scenario
	var player: String = s["player"]

	# Sandbox: win by conquest, lose only if eliminated.
	if bool(s.get("sandbox", false)):
		var mine: int = 0
		var others: int = 0
		for tid in s["territories"]:
			if s["territories"][tid]["owner"] == player:
				mine += 1
			else:
				others += 1
		if mine == 0:
			s["status"] = "lost"
			s["end_reason"] = "Your realm was eliminated (sandbox)."
		elif others == 0:
			s["status"] = "won"
			s["end_reason"] = "All rivals were eliminated (sandbox)."
		return

	var victory: Dictionary = sc["victory"]
	var mode: String = str(victory.get("mode", "capture"))
	var objective: Array = victory["hold_forts"]
	if mode == "capture":
		if _held_count(s, objective, player) == objective.size():
			s["status"] = "won"
			s["end_reason"] = "All objective forts are held."
			return

	if bool(sc["defeat"].get("stability_zero", false)) and int(s["factions"][player]["stability"]) <= 0:
		s["status"] = "lost"
		s["end_reason"] = "Stability collapsed to zero (a gameplay abstraction)."
		return
	var holds_core: bool = false
	for tid in sc["defeat"]["core_territories"]:
		if owner_of(s, tid) == player:
			holds_core = true
	if not holds_core:
		s["status"] = "lost"
		s["end_reason"] = "All core territories were lost."
		return
	if faction_armies(s, player).is_empty():
		var f: Dictionary = s["factions"][player]
		if int(f["gold"]) < 10 or int(f["manpower"]) < 1:
			s["status"] = "lost"
			s["end_reason"] = "No army remains and no means to raise one."
			return
	if int(s["turn"]) > int(s["max_turns"]):
		if mode == "survive":
			var need: int = int(victory.get("hold_min", objective.size()))
			var have: int = _held_count(s, objective, player)
			if have >= need:
				s["status"] = "won"
				s["end_reason"] = "Survived to the end holding %d of %d objective forts." % [have, objective.size()]
			else:
				s["status"] = "lost"
				s["end_reason"] = "Only %d of the %d required forts are held at the end." % [have, need]
		else:
			s["status"] = "lost"
			s["end_reason"] = "Time ran out before the forts were secured."


static func forts_held(s: Dictionary, fid: String) -> Array:
	var out: Array = []
	for f in Game.forts:
		if owner_of(s, Game.forts[f]["territory"]) == fid:
			out.append(Game.forts[f]["name"])
	return out


static func player_outcome(s: Dictionary) -> String:
	var st: Dictionary = s["stats"]
	var head: String = "VICTORY (gameplay result)." if s["status"] == "won" else "DEFEAT (gameplay result)."
	var t: String = "%s %s\nReached turn %d of %d (year %d).\n" % [
		head, s["end_reason"], int(s["turn"]), int(s["max_turns"]), int(s["year"])]
	t += "Forts held: %s.\n" % (", ".join(PackedStringArray(forts_held(s, s["player"]))) if not forts_held(s, s["player"]).is_empty() else "none")
	t += "Battles won %d, lost %d. Forts captured %d, lost %d.\n" % [
		int(st["battles_won"]), int(st["battles_lost"]), int(st["forts_captured"]), int(st["forts_lost"])]
	t += "This describes your playthrough only. It is not documented history."
	return t


# ---------------------------------------------------------------- calendar and seasons
## Quarters are calendar quarters: Q1 Jan-Mar ... Q4 Oct-Dec (a gameplay abstraction).
static func sync_calendar(s: Dictionary) -> void:
	var idx: int = int(Game.scenario.get("start_quarter", 1)) - 1 + int(s["turn"]) - 1
	s["year"] = int(Game.scenario["start_year"]) + int(floor(float(idx) / 4.0))
	s["quarter"] = (idx % 4) + 1


static func is_monsoon(s: Dictionary) -> bool:
	return int(s.get("quarter", 1)) == 3


# ---------------------------------------------------------------- economy: development and repair
static func territory_revenue(s: Dictionary, tid: String) -> int:
	return int(Game.territories[tid]["revenue"]) + int(s["territories"][tid].get("dev", 0))


static func develop_cost(s: Dictionary, tid: String) -> int:
	return 30 * (int(s["territories"][tid].get("dev", 0)) + 1)


static func can_develop(s: Dictionary, fid: String, tid: String) -> Dictionary:
	if owner_of(s, tid) != fid:
		return _fail("You do not hold this territory.")
	if int(s["territories"][tid].get("dev", 0)) >= 2:
		return _fail("Fully developed.")
	if int(s["factions"][fid]["gold"]) < develop_cost(s, tid):
		return _fail("Not enough revenue.")
	return _ok()


static func develop(s: Dictionary, fid: String, tid: String) -> Dictionary:
	var check: Dictionary = can_develop(s, fid, tid)
	if not check["ok"]:
		return check
	s["factions"][fid]["gold"] = int(s["factions"][fid]["gold"]) - develop_cost(s, tid)
	s["territories"][tid]["dev"] = int(s["territories"][tid].get("dev", 0)) + 1
	return _ok("%s developed: +1 revenue per turn." % Game.territories[tid]["name"])


const REPAIR_COST = 15
const REPAIR_AMOUNT = 30.0


static func can_repair(s: Dictionary, fid: String, tid: String) -> Dictionary:
	if owner_of(s, tid) != fid:
		return _fail("You do not hold this territory.")
	var f: String = fort_id_of(tid)
	if f == "":
		return _fail("No fort here.")
	if float(s["territories"][tid]["wall"]) >= float(Game.forts[f]["wall_max"]):
		return _fail("Walls are intact.")
	if int(s["factions"][fid]["gold"]) < REPAIR_COST:
		return _fail("Not enough revenue.")
	return _ok()


static func repair_walls(s: Dictionary, fid: String, tid: String) -> Dictionary:
	var check: Dictionary = can_repair(s, fid, tid)
	if not check["ok"]:
		return check
	var f: String = fort_id_of(tid)
	var ts: Dictionary = s["territories"][tid]
	s["factions"][fid]["gold"] = int(s["factions"][fid]["gold"]) - REPAIR_COST
	ts["wall"] = minf(float(Game.forts[f]["wall_max"]), float(ts["wall"]) + REPAIR_AMOUNT)
	return _ok("Walls repaired to %d." % int(ts["wall"]))


# ---------------------------------------------------------------- diplomacy
const TRUCE_COST = 20
const TRUCE_TURNS = 3


static func truce_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


static func has_truce(s: Dictionary, a: String, b: String) -> bool:
	if not s.has("diplomacy"):
		return false
	return int(s["diplomacy"]["truces"].get(truce_key(a, b), 0)) > 0


static func truce_turns_left(s: Dictionary, a: String, b: String) -> int:
	return int(s["diplomacy"]["truces"].get(truce_key(a, b), 0))


static func set_truce(s: Dictionary, a: String, b: String, turns: int) -> void:
	s["diplomacy"]["truces"][truce_key(a, b)] = turns


static func military_strength(s: Dictionary, fid: String) -> float:
	var total: float = 0.0
	for a in faction_armies(s, fid):
		for ut in a["units"]:
			var u: Dictionary = Game.units[ut]
			total += float(a["units"][ut]) * (float(u["attack"]) + float(u["defense"]))
	for tid in s["territories"]:
		if s["territories"][tid]["owner"] == fid:
			for ut in s["territories"][tid]["garrison"]:
				var u2: Dictionary = Game.units[ut]
				total += 0.5 * float(s["territories"][tid]["garrison"][ut]) * (float(u2["attack"]) + float(u2["defense"]))
	return total


## Why a truce cannot be proposed right now ("" if it can).
static func truce_blocker(s: Dictionary, proposer: String, other: String) -> String:
	if has_truce(s, proposer, other):
		return "A truce is already in force."
	if int(s["diplomacy"]["cooldown"]) > 0:
		return "They will not talk again for %d turn(s)." % int(s["diplomacy"]["cooldown"])
	if int(s["factions"][proposer]["gold"]) < TRUCE_COST:
		return "You need %d revenue to offer terms." % TRUCE_COST
	return ""


static func propose_truce(s: Dictionary, proposer: String, other: String) -> Dictionary:
	var why: String = truce_blocker(s, proposer, other)
	if why != "":
		return _fail(why)
	var ratio: float = military_strength(s, proposer) / maxf(1.0, military_strength(s, other))
	var weary: int = int(s["factions"][other]["weariness"])
	if ratio >= 1.0 or weary >= 3:
		s["factions"][proposer]["gold"] = int(s["factions"][proposer]["gold"]) - TRUCE_COST
		set_truce(s, proposer, other, TRUCE_TURNS)
		var msg: String = "%s accepts a truce for %d turns (tribute paid: %d)." % [
			Game.factions[other]["short_name"], TRUCE_TURNS, TRUCE_COST]
		add_log(s, msg)
		return _ok(msg)
	s["diplomacy"]["cooldown"] = 2
	var msg2: String = "%s refuses: they feel strong and have not been worn down." % Game.factions[other]["short_name"]
	add_log(s, msg2)
	return _fail(msg2)


static func tick_diplomacy(s: Dictionary) -> void:
	var truces: Dictionary = s["diplomacy"]["truces"]
	for k in truces.keys():
		truces[k] = int(truces[k]) - 1
		if int(truces[k]) <= 0:
			truces.erase(k)
			add_log(s, "A truce has expired.")
	s["diplomacy"]["cooldown"] = maxi(0, int(s["diplomacy"]["cooldown"]) - 1)
	if int(s["turn"]) % 2 == 0:
		for fid in s["factions"]:
			s["factions"][fid]["weariness"] = maxi(0, int(s["factions"][fid]["weariness"]) - 1)


# ---------------------------------------------------------------- events
static func event_by_id(id: String) -> Dictionary:
	for e in Game.scenario.get("events", []):
		if e["id"] == id:
			return e
	return {}


## Marks the next due, unfired event as pending (shown to the player).
static func queue_event(s: Dictionary) -> void:
	if s["status"] != "playing" or str(s.get("pending_event", "")) != "":
		return
	if bool(s.get("sandbox", false)):
		return   # events are written for the default player; sandbox skips them
	for e in Game.scenario.get("events", []):
		if s["events_fired"].has(e["id"]):
			continue
		if int(s["turn"]) >= int(e["turn"]):
			s["pending_event"] = e["id"]
			return


static func _who(s: Dictionary, f: String) -> String:
	return s["player"] if f == "player" else f


static func describe_effects(effects: Array) -> String:
	var parts: Array = []
	for ef in effects:
		match str(ef["type"]):
			"gold":
				parts.append("Revenue %+d" % int(ef["amount"]))
			"manpower":
				parts.append("Manpower %+d" % int(ef["amount"]))
			"stability":
				parts.append("Stability %+d" % int(ef["amount"]))
			"truce":
				parts.append("Truce for %d turns" % int(ef["turns"]))
			"wall":
				parts.append("Fort walls %+d" % int(ef["amount"]))
			"garrison":
				parts.append("Enemy garrison grows")
			"army":
				parts.append("An enemy army appears")
			"weariness":
				parts.append("War weariness %+d" % int(ef["amount"]))
	return ", ".join(PackedStringArray(parts))


static func apply_effect(s: Dictionary, ef: Dictionary) -> void:
	match str(ef["type"]):
		"gold":
			var f: Dictionary = s["factions"][_who(s, str(ef["faction"]))]
			f["gold"] = maxi(0, int(f["gold"]) + int(ef["amount"]))
		"manpower":
			var f2: Dictionary = s["factions"][_who(s, str(ef["faction"]))]
			f2["manpower"] = clampi(int(f2["manpower"]) + int(ef["amount"]), 0, MANPOWER_CAP)
		"stability":
			_stab(s, _who(s, str(ef["faction"])), int(ef["amount"]))
		"weariness":
			var f3: Dictionary = s["factions"][_who(s, str(ef["faction"]))]
			f3["weariness"] = maxi(0, int(f3["weariness"]) + int(ef["amount"]))
		"truce":
			set_truce(s, s["player"], str(ef["with"]), int(ef["turns"]))
		"wall":
			var tid: String = str(ef["territory"])
			var fid: String = fort_id_of(tid)
			if fid != "":
				var ts: Dictionary = s["territories"][tid]
				ts["wall"] = clampf(float(ts["wall"]) + float(ef["amount"]), 0.0, float(Game.forts[fid]["wall_max"]))
		"garrison":
			var gar: Dictionary = s["territories"][str(ef["territory"])]["garrison"]
			for ut in ef["units"]:
				gar[ut] = int(gar.get(ut, 0)) + int(ef["units"][ut])
		"army":
			add_army(s, str(ef["owner"]), str(ef.get("commander", "")), str(ef["territory"]),
				_int_units(ef["units"]), "field")


static func resolve_event(s: Dictionary, event_id: String, choice_idx: int) -> Dictionary:
	var e: Dictionary = event_by_id(event_id)
	if e.is_empty() or choice_idx < 0 or choice_idx >= e["choices"].size():
		return _fail("Unknown event choice.")
	var choice: Dictionary = e["choices"][choice_idx]
	if int(s["factions"][s["player"]]["gold"]) < int(choice.get("min_gold", 0)):
		return _fail("Not enough revenue for that choice.")
	for ef in choice["effects"]:
		apply_effect(s, ef)
	s["events_fired"].append(event_id)
	s["pending_event"] = ""
	add_log(s, "Event: %s - %s" % [e["title"], choice["label"]])
	queue_event(s)
	check_end(s)
	return _ok(str(choice["label"]))
