extends Control
## Main menu: New Game, Continue, Settings.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const SaveSystem = preload("res://scripts/save/save_system.gd")

var _settings_overlay: Control = null
var _diff_button: Button = null
var _sound_button: Button = null


func _ready() -> void:
	UiKit.full_rect(self)
	var bg := ColorRect.new()
	bg.color = UiKit.INK
	add_child(bg)
	UiKit.full_rect(bg)

	var m := MarginContainer.new()
	add_child(m)
	UiKit.full_rect(m)
	UiKit.margin(m, 48)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)
	m.add_child(box)

	var title := UiKit.label("SWARAJYA", 72, UiKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := UiKit.label("THE MARATHA AGE", 30, UiKit.TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var rule := ColorRect.new()
	rule.color = UiKit.GOLD
	rule.custom_minimum_size = Vector2(0, 3)
	box.add_child(rule)
	var tag := UiKit.label("A turn-based grand strategy game. Prototype v" + Game.VERSION + ": four campaigns, sandbox.", 20, UiKit.MUTED)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tag)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	box.add_child(spacer)

	var b_new := UiKit.button("New Game", 76, 30)
	b_new.pressed.connect(func(): Game.goto("era_select"))
	box.add_child(b_new)

	var b_cont := UiKit.button("Continue", 76, 30)
	b_cont.disabled = not SaveSystem.has_save()
	b_cont.pressed.connect(_on_continue)
	box.add_child(b_cont)

	var b_sand := UiKit.button("Sandbox", 76, 30)
	b_sand.pressed.connect(_goto.bind("sandbox"))
	box.add_child(b_sand)

	var b_set := UiKit.button("Settings", 76, 30)
	b_set.pressed.connect(_show_settings)
	box.add_child(b_set)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var b_codex := UiKit.button("Codex", 64, 26)
	b_codex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_codex.pressed.connect(_goto.bind("codex"))
	row.add_child(b_codex)
	var b_tl := UiKit.button("Timeline", 64, 26)
	b_tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_tl.pressed.connect(_goto.bind("timeline"))
	row.add_child(b_tl)

	if not OS.has_feature("mobile"):
		var b_quit := UiKit.button("Quit", 64, 26)
		b_quit.pressed.connect(func(): get_tree().quit())
		box.add_child(b_quit)

	var foot := UiKit.label("Historical notes carry confidence tags. Gameplay numbers are abstractions, not records.", 16, UiKit.MUTED)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(foot)


func _on_continue() -> void:
	if Game.continue_campaign():
		Game.goto("game")


func _show_settings() -> void:
	if _settings_overlay != null:
		return
	_settings_overlay = Control.new()
	add_child(_settings_overlay)
	UiKit.full_rect(_settings_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	_settings_overlay.add_child(dim)
	UiKit.full_rect(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.style(UiKit.INK_LIGHT, UiKit.GOLD, 14, 3))
	_settings_overlay.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(580, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	v.add_child(UiKit.label("Settings", 36, UiKit.GOLD))
	v.add_child(UiKit.label("AI difficulty changes how readily the Adil Shahi AI attacks and how often it recruits. It applies to new games.", 20, UiKit.MUTED))
	_diff_button = UiKit.button("", 64, 26)
	_diff_button.pressed.connect(_cycle_difficulty)
	v.add_child(_diff_button)
	_update_diff_text()
	_sound_button = UiKit.button("", 64, 26)
	_sound_button.pressed.connect(_toggle_sound)
	v.add_child(_sound_button)
	_update_sound_text()
	var back := UiKit.button("Back", 64, 26)
	back.pressed.connect(_close_settings)
	v.add_child(back)


func _cycle_difficulty() -> void:
	var order: Array = ["easy", "normal", "hard"]
	var cur: int = order.find(str(Game.settings.get("difficulty", "normal")))
	Game.set_difficulty(order[(cur + 1) % order.size()])
	_update_diff_text()


func _update_diff_text() -> void:
	_diff_button.text = "AI difficulty: " + str(Game.settings.get("difficulty", "normal")).capitalize()


func _close_settings() -> void:
	if _settings_overlay != null:
		_settings_overlay.queue_free()
		_settings_overlay = null


func _goto(scene: String) -> void:
	Game.goto(scene)


func _toggle_sound() -> void:
	Game.settings["sound"] = not bool(Game.settings.get("sound", true))
	Game.set_difficulty(str(Game.settings.get("difficulty", "normal")))   # also saves settings
	_update_sound_text()
	Sfx.play("click")


func _update_sound_text() -> void:
	_sound_button.text = "Sound effects: " + ("On" if bool(Game.settings.get("sound", true)) else "Off")
