extends Control
## Timeline of historical dates relevant to the campaigns, with confidence tags.

const UiKit = preload("res://scripts/ui/ui_kit.gd")


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
	box.add_child(UiKit.label("Timeline", 40, UiKit.GOLD))
	var rt := UiKit.rich(0, 20)
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.text = UiKit.timeline_bbcode("")
	box.add_child(rt)
	var back := UiKit.button("Back", 60, 24)
	back.pressed.connect(_on_back)
	box.add_child(back)


func _on_back() -> void:
	Game.goto("main_menu")
