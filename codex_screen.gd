extends Control
## Historical Codex: units, factions, commanders, territories and forts from every campaign.
## Each entry separates HISTORICAL text (with a confidence tag) from GAMEPLAY numbers.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const CATEGORIES = ["Units", "Factions", "Commanders", "Territories", "Forts"]

var _entries: Array = []      # {cat, title, hist, gameplay}
var _list: VBoxContainer
var _detail: RichTextLabel
var _cat_title: Label


func _ready() -> void:
	UiKit.full_rect(self)
	var bg := ColorRect.new()
	bg.color = UiKit.INK
	add_child(bg)
	UiKit.full_rect(bg)
	var m := MarginContainer.new()
	add_child(m)
	UiKit.full_rect(m)
	UiKit.margin(m, 24)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	m.add_child(box)

	box.add_child(UiKit.label("Historical Codex", 40, UiKit.GOLD))
	box.add_child(UiKit.label("History and gameplay are kept apart. Each historical entry has a confidence tag.", 18, UiKit.MUTED))

	var cats := HFlowContainer.new()
	cats.add_theme_constant_override("h_separation", 8)
	cats.add_theme_constant_override("v_separation", 8)
	box.add_child(cats)
	for c in CATEGORIES:
		var b := UiKit.button(c, 52, 20)
		b.pressed.connect(_show_category.bind(c))
		cats.add_child(b)

	_cat_title = UiKit.label("", 24, UiKit.TEXT)
	box.add_child(_cat_title)

	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 280)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	sc.add_child(_list)

	_detail = UiKit.rich(0, 20)
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.text = "Choose a category, then an entry."
	box.add_child(_detail)

	var back := UiKit.button("Back", 60, 24)
	back.pressed.connect(_on_back)
	box.add_child(back)

	_collect()
	_show_category("Units")


func _on_back() -> void:
	Game.goto("main_menu")


func _collect() -> void:
	_entries.clear()
	for id in Game.units:
		var u: Dictionary = Game.units[id]
		_entries.append({"cat": "Units", "title": str(u["name"]), "hist": u["historical"],
			"gameplay": "Attack %d, defence %d, speed %d, cost %d, manpower %d. One unit = a company-sized body (abstraction)." % [
				int(u["attack"]), int(u["defense"]), int(u["move"]), int(u["cost"]), int(u["manpower"])]})
	for id in Game.factions:
		var f: Dictionary = Game.factions[id]
		var rec: Array = []
		for ut in f["recruitable"]:
			rec.append(str(Game.units[ut]["name"]))
		_entries.append({"cat": "Factions", "title": str(f["name"]), "hist": f["historical"],
			"gameplay": "Recruits: %s. %s" % [", ".join(PackedStringArray(rec)), str(f.get("gameplay_note", ""))]})
	for id in Game.commanders:
		var c: Dictionary = Game.commanders[id]
		var g: Dictionary = c["gameplay"]
		_entries.append({"cat": "Commanders", "title": str(c["name"]), "hist": c["historical"],
			"gameplay": "Attack %+d%%, defence %+d%%, speed %+d. Trait: %s. (Numbers are abstractions.)" % [
				int(round(float(g["attack_mod"]) * 100.0)), int(round(float(g["defense_mod"]) * 100.0)),
				int(g["speed_bonus"]), str(g["trait"])]})
	for sid in Game.SCENARIO_IDS:
		var d: Dictionary = Game.read_scenario_files(sid)
		var tag: String = str(d["scenario"].get("short_name", sid))
		for tid in d["territories"]:
			var t: Dictionary = d["territories"][tid]
			_entries.append({"cat": "Territories", "title": "%s (%s)" % [str(t["name"]), tag], "hist": t["historical"],
				"gameplay": "%s terrain, revenue %d, manpower %d. The map is schematic, not to scale." % [
					str(Game.terrain[t["terrain"]]["name"]), int(t["revenue"]), int(t["manpower"])]})
		for fid in d["forts"]:
			var ft: Dictionary = d["forts"][fid]
			_entries.append({"cat": "Forts", "title": "%s (%s)" % [str(ft["name"]), tag], "hist": ft["historical"],
				"gameplay": "Defence bonus %.2f, strategic value %d, walls %d. %s" % [
					float(ft["defense"]), int(ft["strategic"]), int(ft["wall_max"]), str(ft.get("gameplay_note", ""))]})


func _show_category(cat: String) -> void:
	_cat_title.text = cat
	for c in _list.get_children():
		c.queue_free()
	for i in range(_entries.size()):
		if _entries[i]["cat"] != cat:
			continue
		var conf: String = str(_entries[i]["hist"].get("confidence", "UNCERTAIN"))
		var b := UiKit.button("%s   [%s]" % [_entries[i]["title"], conf], 52, 19)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_show_entry.bind(i))
		_list.add_child(b)
	_detail.text = "Choose an entry."


func _show_entry(i: int) -> void:
	var e: Dictionary = _entries[i]
	var t: String = UiKit.confidence_block(str(e["title"]), e["hist"])
	t += "\n[b]GAMEPLAY INFORMATION[/b]\n%s" % str(e["gameplay"])
	_detail.text = t
