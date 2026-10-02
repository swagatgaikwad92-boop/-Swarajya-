extends Node
## Autoload singleton "Game": static data, the live game state, scene helpers.

const DataLoader = preload("res://scripts/core/data_loader.gd")
const Rules = preload("res://scripts/core/rules.gd")
const SaveSystem = preload("res://scripts/save/save_system.gd")

const CAMPAIGN_DIR = "res://data/campaigns/"
const SCENARIO_IDS = ["early_consolidation_1646", "afzal_khan_1659", "peshwa_expansion_1727", "last_peshwa_1817"]
const ERA_IDS = ["era1", "era2", "era3"]
const VERSION = "1.0.0"

var terrain: Dictionary = {}
var units: Dictionary = {}
var factions: Dictionary = {}
var commanders: Dictionary = {}
var timeline: Array = []
var scenario_meta: Dictionary = {}   # id -> scenario.json (no map data)

# Loaded for the currently selected scenario:
var scenario: Dictionary = {}
var territories: Dictionary = {}
var forts: Dictionary = {}
var selected_scenario: String = "early_consolidation_1646"

var state: Dictionary = {}
var settings: Dictionary = {"difficulty": "normal", "sound": true}


func _ready() -> void:
	load_data()
	settings = SaveSystem.load_settings(settings)


func load_data() -> void:
	terrain = _as_dict(DataLoader.load_json("res://data/terrain.json"))
	units = _as_dict(DataLoader.load_json("res://data/units.json"))
	factions = _as_dict(DataLoader.load_json("res://data/factions.json"))
	commanders = _as_dict(DataLoader.load_json("res://data/commanders.json"))
	var tl = DataLoader.load_json("res://data/timeline.json")
	timeline = tl if tl is Array else []
	for sid in SCENARIO_IDS:
		scenario_meta[sid] = _as_dict(DataLoader.load_json(CAMPAIGN_DIR + sid + "/scenario.json"))
	load_scenario(selected_scenario)


## Reads one scenario's files without changing the active scenario.
func read_scenario_files(id: String) -> Dictionary:
	var base: String = CAMPAIGN_DIR + id + "/"
	var sc: Dictionary = _as_dict(DataLoader.load_json(base + "scenario.json"))
	var terr: Dictionary = _as_dict(DataLoader.load_json(base + "territories.json"))
	var frts: Dictionary = _as_dict(DataLoader.load_json(base + "forts.json"))
	# Data files list each link once; make adjacency symmetric.
	for tid in terr:
		for n in terr[tid]["neighbours"]:
			if terr.has(n) and not terr[n]["neighbours"].has(tid):
				terr[n]["neighbours"].append(tid)
	for fid in frts:
		if not frts[fid].has("wall_start"):
			frts[fid]["wall_start"] = frts[fid]["wall_max"]
	return {"scenario": sc, "territories": terr, "forts": frts}


func load_scenario(id: String) -> void:
	var d: Dictionary = read_scenario_files(id)
	scenario = d["scenario"]
	territories = d["territories"]
	forts = d["forts"]
	selected_scenario = id


func _as_dict(v) -> Dictionary:
	if v is Dictionary:
		return v
	return {}


## Scenario ids belonging to one era, in play order.
func scenarios_in_era(era_id: String) -> Array:
	var out: Array = []
	for sid in SCENARIO_IDS:
		if str(scenario_meta[sid]["era"].get("id", "")) == era_id:
			out.append(sid)
	return out


## opts: {"sandbox": bool, "player": faction id, "rich": bool}
func start_new_campaign(id: String = "", opts: Dictionary = {}) -> void:
	if id == "":
		id = selected_scenario
	load_scenario(id)
	state = Rules.new_state(opts)
	state["difficulty"] = str(settings.get("difficulty", "normal"))
	SaveSystem.save_state(state)


func continue_campaign() -> bool:
	var sid: String = SaveSystem.peek_scenario_id()
	if sid == "" or not SCENARIO_IDS.has(sid):
		return false
	load_scenario(sid)
	var loaded: Dictionary = SaveSystem.load_state()
	if loaded.is_empty():
		return false
	state = loaded
	return true


func save_game() -> bool:
	if state.is_empty():
		return false
	return SaveSystem.save_state(state)


func set_difficulty(d: String) -> void:
	settings["difficulty"] = d
	SaveSystem.save_settings(settings)


func goto(scene_name: String) -> void:
	get_tree().change_scene_to_file("res://scenes/%s.tscn" % scene_name)
