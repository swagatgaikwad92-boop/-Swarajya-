extends Node
## Headless smoke tests. Run with:
##   godot --headless --path . res://tests/test_runner.tscn
## Exit code 0 = all passed.

const Rules = preload("res://scripts/core/rules.gd")
const TurnManager = preload("res://scripts/core/turn_manager.gd")
const SaveSystem = preload("res://scripts/save/save_system.gd")

var _fails: int = 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_fails += 1


func _ready() -> void:
	_check(Game.territories.size() == 10, "10 territories loaded")
	_check(Game.forts.size() == 5, "5 forts loaded")
	_check(Game.timeline.size() > 5, "timeline loaded")
	_check(Game.scenario_meta.size() == 4, "four scenarios registered")
	_check(Game.scenario.has("start"), "scenario loaded")

	var s: Dictionary = Rules.new_state()
	_check(s["status"] == "playing", "new state is playing")
	_check(s["armies"].size() == 4, "four starting armies")
	_check(s["territories"]["torna"]["owner"] == "adilshahi", "Torna starts Adil Shahi")

	# Movement and attack.
	var a = Rules.army_by_id(s, 1)
	_check(a != null and a["territory"] == "maval", "army 1 at Maval")
	_check(Rules.attack_targets(s, a).has("torna"), "Torna attackable from Maval")
	var before_wall: float = float(s["territories"]["torna"]["wall"])
	var sres: Dictionary = Rules.besiege(s, a, "torna")
	_check(sres["ok"] and float(s["territories"]["torna"]["wall"]) < before_wall, "besiege lowers walls")
	_check(not Rules.attack(s, a, "torna", "balanced")["ok"], "no attack after besiege (moves spent)")

	# Recruit.
	var gold: int = int(s["factions"]["swarajya"]["gold"])
	var rr: Dictionary = Rules.recruit(s, "swarajya", "pune", "infantry")
	_check(rr["ok"] and int(s["factions"]["swarajya"]["gold"]) < gold, "recruit spends revenue")
	_check(not Rules.recruit(s, "swarajya", "torna", "infantry")["ok"], "cannot recruit in enemy land")

	# Save round trip.
	_check(SaveSystem.save_state(s), "save written")
	var loaded: Dictionary = SaveSystem.load_state()
	_check(not loaded.is_empty(), "save loads and validates")
	_check(int(loaded["turn"]) == int(s["turn"]), "turn survives round trip")
	_check(typeof(loaded["armies"][0]["id"]) == TYPE_INT, "ids normalised to int")

	# AI-only simulation: player never acts. Must not crash and must terminate.
	var sim: Dictionary = Rules.new_state()
	sim["difficulty"] = "normal"
	var guard: int = 0
	while sim["status"] == "playing" and guard < 40:
		TurnManager.end_player_turn(sim)
		guard += 1
	_check(sim["status"] != "playing", "idle game ends (status=%s after %d turns)" % [sim["status"], guard])

	# Diplomacy, development, repair.
	var d: Dictionary = Rules.new_state()
	_check(not Rules.propose_truce(d, "swarajya", "adilshahi")["ok"], "weak player is refused a truce")
	d["factions"]["adilshahi"]["weariness"] = 3
	d["diplomacy"]["cooldown"] = 0
	d["factions"]["swarajya"]["gold"] = 100
	_check(Rules.propose_truce(d, "swarajya", "adilshahi")["ok"], "worn-down rival accepts a truce")
	var army1 = Rules.army_by_id(d, 1)
	_check(not Rules.attack_targets(d, army1).has("torna"), "truce blocks attacks")
	_check(Rules.develop(d, "swarajya", "pune")["ok"], "develop works")
	_check(Rules.territory_revenue(d, "pune") == 7, "development adds revenue")
	d["territories"]["rajgad"]["wall"] = 30.0
	_check(Rules.repair_walls(d, "swarajya", "rajgad")["ok"] and float(d["territories"]["rajgad"]["wall"]) == 60.0, "repair adds 30 walls")

	# Events: the 1646 scenario has none on turn 1; 1659 has one at once.
	_check(d["pending_event"] == "", "no event at start of 1646 campaign")
	Game.start_new_campaign("afzal_khan_1659")
	var e: Dictionary = Game.state
	_check(e["pending_event"] == "s2_army", "1659 campaign opens with an event")
	_check(Rules.resolve_event(e, "s2_army", 0)["ok"] and e["pending_event"] == "s2_parley" or e["pending_event"] == "", "event resolves and next is queued")
	_check(int(e["quarter"]) == 3 and Rules.is_monsoon(e), "1659 starts in the monsoon quarter")

	# Save v1 -> v2 migration.
	Game.start_new_campaign("early_consolidation_1646")
	var old: Dictionary = Game.state.duplicate(true)
	old["save_version"] = 1
	for k in ["quarter", "diplomacy", "events_fired", "pending_event"]:
		old.erase(k)
	var mig: Dictionary = SaveSystem.normalize(SaveSystem._migrate(old))
	_check(int(mig["save_version"]) == 2 and mig.has("diplomacy"), "v1 save migrates to v2")

	# AI-only simulation on the 1659 scenario too.
	Game.start_new_campaign("afzal_khan_1659")
	var sim2: Dictionary = Game.state
	guard = 0
	while sim2["status"] == "playing" and guard < 40:
		if sim2["pending_event"] != "":
			Rules.resolve_event(sim2, sim2["pending_event"], 0)
		TurnManager.end_player_turn(sim2)
		guard += 1
	_check(sim2["status"] != "playing", "1659 idle game ends (status=%s after %d turns)" % [sim2["status"], guard])

	# Every campaign: starts, validates, survives an idle AI simulation, and ends.
	for sid in Game.SCENARIO_IDS:
		Game.start_new_campaign(sid)
		var g: Dictionary = Game.state
		_check(g["status"] == "playing" and g["armies"].size() >= 4, "%s starts" % sid)
		var turns: int = 0
		while g["status"] == "playing" and turns < 60:
			if str(g["pending_event"]) != "":
				Rules.resolve_event(g, str(g["pending_event"]), 0)
				if str(g["pending_event"]) != "":
					# first choice unaffordable: take the last choice instead
					var ev: Dictionary = Rules.event_by_id(str(g["pending_event"]))
					Rules.resolve_event(g, str(g["pending_event"]), ev["choices"].size() - 1)
			TurnManager.end_player_turn(g)
			turns += 1
		_check(g["status"] != "playing", "%s idle game ends (%s after %d turns)" % [sid, g["status"], turns])

	# Sandbox: play as a non-default faction with a rich start; no events, no turn limit.
	Game.start_new_campaign("peshwa_expansion_1727", {"sandbox": true, "player": "nizam", "rich": true})
	var sb: Dictionary = Game.state
	_check(sb["sandbox"] and sb["pending_event"] == "", "sandbox has no events")
	_check(int(sb["factions"]["nizam"]["gold"]) >= 300, "rich start applied")
	for i in range(30):
		TurnManager.end_player_turn(sb)
		if sb["status"] != "playing":
			break
	_check(true, "sandbox ran %d turns without error (status=%s)" % [int(sb["turn"]), sb["status"]])

	# Save round trip keeps the sandbox flag.
	_check(SaveSystem.save_state(sb), "sandbox save written")
	Game.load_scenario("peshwa_expansion_1727")
	var back: Dictionary = SaveSystem.load_state()
	_check(not back.is_empty() and back["sandbox"] == true and back["player"] == "nizam", "sandbox save reloads")

	print("Failures: ", _fails)
	get_tree().quit(1 if _fails > 0 else 0)
