extends RefCounted
## Rule-based AI with simple personalities. It sees the whole map (no fog of war).
## Each turn: merge armies, spend on repairs/development, recruit near the front, then act per army.

const Rules = preload("res://scripts/core/rules.gd")

const THRESHOLDS = {"easy": 1.45, "normal": 1.2, "hard": 1.05}
const RECRUIT_EVERY = {"easy": 3, "normal": 2, "hard": 1}
const STYLE_OFFSET = {"aggressive": -0.15, "balanced": 0.0, "defensive": 0.2}


static func run_faction(s: Dictionary, fid: String) -> void:
	_merge_armies(s, fid)
	_economy(s, fid)
	_recruit(s, fid)
	var ids: Array = []
	for a in Rules.faction_armies(s, fid):
		ids.append(int(a["id"]))
	for id in ids:
		var army = Rules.army_by_id(s, id)
		if army == null:
			continue
		_act(s, army)


static func _style(fid: String) -> String:
	return str(Game.scenario.get("ai_styles", {}).get(fid, "balanced"))


static func _base_threshold(s: Dictionary, fid: String) -> float:
	var t: float = float(THRESHOLDS.get(str(s.get("difficulty", "normal")), 1.2))
	return t + float(STYLE_OFFSET.get(_style(fid), 0.0))


static func _value(s: Dictionary, tid: String) -> float:
	var v: float = float(Game.territories[tid]["revenue"])
	var f: String = Rules.fort_id_of(tid)
	if f != "":
		v += float(Game.forts[f]["strategic"])
	if bool(Game.territories[tid].get("supply_source", false)):
		v += 6.0
	return v


# ------------------------------------------------------------------ housekeeping
static func _merge_armies(s: Dictionary, fid: String) -> void:
	for tid in s["territories"]:
		var here: Array = []
		for a in Rules.armies_at(s, tid):
			if a["owner"] == fid:
				here.append(a)
		if here.size() < 2:
			continue
		var base: Dictionary = here[0]
		for i in range(1, here.size()):
			var other: Dictionary = here[i]
			if Rules.unit_total(base["units"]) + Rules.unit_total(other["units"]) > Rules.ARMY_CAP:
				continue
			for ut in other["units"]:
				base["units"][ut] = int(base["units"].get(ut, 0)) + int(other["units"][ut])
			if str(base["commander"]) == "":
				base["commander"] = other["commander"]
			base["morale"] = minf(float(base["morale"]), float(other["morale"]))
			base["supply"] = minf(float(base["supply"]), float(other["supply"]))
			base["moves_left"] = mini(int(base["moves_left"]), int(other["moves_left"]))
			other["units"] = {}
	Rules._cleanup_armies(s)


static func _economy(s: Dictionary, fid: String) -> void:
	var f: Dictionary = s["factions"][fid]
	# Repair a threatened fort.
	if int(f["gold"]) >= 40:
		for tid in s["territories"]:
			if s["territories"][tid]["owner"] == fid and Rules.has_fort(tid):
				if Rules.distance_to_enemy(s, fid, tid) <= 1 and Rules.can_repair(s, fid, tid)["ok"]:
					Rules.repair_walls(s, fid, tid)
					break
	# Develop the safest territory when rich.
	if int(f["gold"]) >= 90:
		var best: String = ""
		var best_d: int = 1
		for tid in s["territories"]:
			if s["territories"][tid]["owner"] != fid:
				continue
			if not Rules.can_develop(s, fid, tid)["ok"]:
				continue
			var d: int = Rules.distance_to_enemy(s, fid, tid)
			if d > best_d:
				best_d = d
				best = tid
		if best != "":
			Rules.develop(s, fid, best)


static func _recruit(s: Dictionary, fid: String) -> void:
	var every: int = int(RECRUIT_EVERY.get(str(s.get("difficulty", "normal")), 2))
	if _style(fid) == "aggressive":
		every = maxi(1, every - 1)
	if int(s["turn"]) % every != 0:
		return
	var best_tid: String = ""
	var best_d: int = 999
	for tid in s["territories"]:
		if s["territories"][tid]["owner"] != fid or not Rules.is_source(s, fid, tid):
			continue
		var d: int = Rules.distance_to_enemy(s, fid, tid)
		if d < best_d:
			best_d = d
			best_tid = tid
	if best_tid == "":
		return
	var recruitable: Array = Game.factions[fid]["recruitable"]
	var line: Array = ["infantry", "infantry", "cavalry"]
	var ut: String = line[int(s["turn"]) % 3]
	if recruitable.has("drilled_infantry") and int(s["turn"]) % 2 == 0:
		ut = "drilled_infantry"
	if recruitable.has("artillery") and int(s["turn"]) % 6 == 0 and int(s["factions"][fid]["gold"]) >= 45:
		ut = "artillery"
	if not recruitable.has(ut):
		ut = "infantry"
	var res: Dictionary = Rules.recruit(s, fid, best_tid, ut)
	if not res["ok"]:
		Rules.recruit(s, fid, best_tid, "infantry")


# ------------------------------------------------------------------ army decisions
static func _act(s: Dictionary, army: Dictionary) -> void:
	if int(army["moves_left"]) <= 0:
		return
	var fid: String = army["owner"]
	var base_need: float = _base_threshold(s, fid)
	var targets: Array = Rules.attack_targets(s, army)
	var best_tid: String = ""
	var best_score: float = 0.0
	var best_ratio: float = 0.0
	for tid in targets:
		var ratio: float = float(Rules.battle_preview(s, army, tid, "balanced")["ratio"])
		var need: float = base_need
		var f: String = Rules.fort_id_of(tid)
		if f != "" and float(s["territories"][tid]["wall"]) < 0.5 * float(Game.forts[f]["wall_max"]):
			need -= 0.1
		if army["role"] == "guard":
			need = maxf(need, 1.6)
		if float(army["supply"]) < 35.0:
			need += 0.3
		if ratio >= need:
			var score: float = ratio * (1.0 + _value(s, tid) / 10.0)
			if score > best_score:
				best_score = score
				best_tid = tid
				best_ratio = ratio
	if best_tid != "":
		Rules.attack(s, army, best_tid, "aggressive" if best_ratio > 1.6 else "balanced")
		return
	# Siege a strong fort if we have guns and the odds are not hopeless.
	if int(army["units"].get("artillery", 0)) > 0:
		for tid in targets:
			var f2: String = Rules.fort_id_of(tid)
			if f2 != "" and float(s["territories"][tid]["wall"]) > 35.0:
				if float(Rules.battle_preview(s, army, tid, "balanced")["ratio"]) >= 0.6:
					Rules.besiege(s, army, tid)
					return
	if army["role"] == "guard" or float(army["supply"]) < 40.0:
		return
	# Hold if outnumbered by neighbouring enemy armies.
	var own: int = Rules.unit_total(army["units"])
	var threat: int = 0
	for n in Rules.neighbours(army["territory"]):
		if Rules.owner_of(s, n) != fid:
			for e in Rules.armies_at(s, n):
				threat += Rules.unit_total(e["units"])
	if threat > own:
		return
	var plan: Array = _plan(s, army)
	if plan.size() == 2 and Rules.can_move(s, army, plan[0]):
		var ratio2: float = float(Rules.battle_preview(s, army, plan[1], "balanced")["ratio"])
		if ratio2 >= base_need * 0.75:
			var from_name: String = Game.territories[army["territory"]]["name"]
			Rules.move_army(s, army, plan[0])
			Rules.add_log(s, "%s army #%d moved from %s to %s." % [
				Game.factions[fid]["short_name"], int(army["id"]), from_name,
				Game.territories[plan[0]]["name"]])


## Chooses the most attractive enemy territory (value, weakness, distance) and returns
## [next_step, objective], or [] when the next step is an attack or nothing is worth pursuing.
static func _plan(s: Dictionary, army: Dictionary) -> Array:
	var fid: String = army["owner"]
	var start: String = army["territory"]
	var dist: Dictionary = {start: 0}
	var parent: Dictionary = {start: ""}
	var queue: Array = [start]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for n in Rules.neighbours(cur):
			if not dist.has(n):
				dist[n] = int(dist[cur]) + 1
				parent[n] = cur
				queue.append(n)
	var best: String = ""
	var best_score: float = -1.0
	for tid in dist:
		var o: String = Rules.owner_of(s, tid)
		if o == fid or Rules.has_truce(s, fid, o):
			continue
		var ratio: float = float(Rules.battle_preview(s, army, tid, "balanced")["ratio"])
		var score: float = _value(s, tid) * clampf(ratio, 0.3, 2.0) / (1.0 + 0.7 * float(dist[tid]))
		if score > best_score:
			best_score = score
			best = tid
	if best == "":
		return []
	var node: String = best
	while parent[node] != start and parent[node] != "":
		node = parent[node]
	if node == best:
		return []
	if Rules.owner_of(s, node) != fid:
		return []
	return [node, best]
