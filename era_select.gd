extends Control
## Era and campaign selection. All three eras are playable in v1.0.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

var _era: String = ""
var _selected: String = ""
var _era_buttons: Dictionary = {}
var _camp_box: VBoxContainer
var _camp_buttons: Dictionary = {}
var _brief: RichTextLabel


func _ready() -> void:
	UiKit.full_rect(self)
	var bg := ColorRect.new()
	bg.color = UiKit.INK
	add_child(bg)
	UiKit.full_rect(bg)
	var m := MarginContainer.new()
	add_child(m)
	UiKit.full_rect(m)
	UiKit.margin(m, 28)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	m.add_child(box)

	box.add_child(UiKit.label("Choose an Era", 44, UiKit.GOLD))
	for e in Game.ERA_IDS:
		var b := UiKit.button("", 64, 22)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_select_era.bind(e))
		box.add_child(b)
		_era_buttons[e] = b

	box.add_child(UiKit.label("Campaigns", 28, UiKit.TEXT))
	_camp_box = VBoxContainer.new()
	_camp_box.add_theme_constant_override("separation", 8)
	box.add_child(_camp_box)

	_brief = UiKit.rich(0, 20)
	_brief.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_brief)

	var begin := UiKit.button("Begin Campaign", 76, 30)
	begin.pressed.connect(_on_begin)
	box.add_child(begin)
	var back := UiKit.button("Back", 60, 24)
	back.pressed.connect(_on_back)
	box.add_child(back)

	var start_era: String = str(Game.scenario_meta[Game.selected_scenario]["era"].get("id", "era1"))
	_select_era(start_era if Game.ERA_IDS.has(start_era) else Game.ERA_IDS[0])


func _select_era(e: String) -> void:
	_era = e
	for id in _era_buttons:
		var first: String = Game.scenarios_in_era(id)[0]
		_era_buttons[id].text = "%s%s" % ["> " if id == e else "", str(Game.scenario_meta[first]["era"]["title"])]
	for c in _camp_box.get_children():
		c.queue_free()
	_camp_buttons.clear()
	for sid in Game.scenarios_in_era(e):
		var meta: Dictionary = Game.scenario_meta[sid]
		var b := UiKit.button("", 60, 20)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_select_campaign.bind(sid))
		_camp_box.add_child(b)
		_camp_buttons[sid] = b
	_select_campaign(Game.scenarios_in_era(e)[0])


func _select_campaign(id: String) -> void:
	_selected = id
	for sid in _camp_buttons:
		var meta: Dictionary = Game.scenario_meta[sid]
		_camp_buttons[sid].text = "%s%s  (%s)" % ["> " if sid == id else "", str(meta["title"]), str(meta["period"])]
	var m: Dictionary = Game.scenario_meta[id]
	var t: String = str(m["briefing"]) + "\n\n[b]Win:[/b] %s\n[b]Lose:[/b] %s\n\n" % [str(m["win_text"]), str(m["lose_text"])]
	t += "[i]Historical dates are tagged with confidence in the Codex and Timeline. Gameplay numbers are abstractions.[/i]"
	_brief.text = t


func _on_begin() -> void:
	Game.start_new_campaign(_selected)
	Game.goto("game")


func _on_back() -> void:
	Game.goto("main_menu")
