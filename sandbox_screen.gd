extends Control
## Sandbox: pick any campaign map, play any faction, optional rich start.
## Win by conquest; scripted events and turn limits are off.

const UiKit = preload("res://scripts/ui/ui_kit.gd")

var _sid_idx: int = 0
var _fid_idx: int = 0
var _rich: bool = false
var _b_map: Button
var _b_fac: Button
var _b_rich: Button
var _info: RichTextLabel


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
	box.add_theme_constant_override("separation", 14)
	m.add_child(box)
	box.add_child(UiKit.label("Sandbox", 44, UiKit.GOLD))
	box.add_child(UiKit.label("Play any map as any faction. No scripted events and no turn limit. You win by eliminating every rival and lose only if you are eliminated.", 20, UiKit.MUTED))

	_b_map = UiKit.button("", 64, 22)
	_b_map.pressed.connect(_cycle_map)
	box.add_child(_b_map)
	_b_fac = UiKit.button("", 64, 22)
	_b_fac.pressed.connect(_cycle_faction)
	box.add_child(_b_fac)
	_b_rich = UiKit.button("", 64, 22)
	_b_rich.pressed.connect(_toggle_rich)
	box.add_child(_b_rich)

	_info = UiKit.rich(0, 20)
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_info)

	var begin := UiKit.button("Start Sandbox", 76, 30)
	begin.pressed.connect(_on_begin)
	box.add_child(begin)
	var back := UiKit.button("Back", 60, 24)
	back.pressed.connect(_on_back)
	box.add_child(back)
	_update()


func _sid() -> String:
	return Game.SCENARIO_IDS[_sid_idx]


func _factions() -> Array:
	return Game.scenario_meta[_sid()]["start"]["factions"].keys()


func _cycle_map() -> void:
	_sid_idx = (_sid_idx + 1) % Game.SCENARIO_IDS.size()
	_fid_idx = 0
	_update()


func _cycle_faction() -> void:
	_fid_idx = (_fid_idx + 1) % _factions().size()
	_update()


func _toggle_rich() -> void:
	_rich = not _rich
	_update()


func _update() -> void:
	var meta: Dictionary = Game.scenario_meta[_sid()]
	var fid: String = str(_factions()[_fid_idx])
	_b_map.text = "Map: %s" % str(meta["title"])
	_b_fac.text = "Play as: %s" % str(Game.factions[fid]["name"])
	_b_rich.text = "Rich start (+200 revenue, +20 manpower): %s" % ("On" if _rich else "Off")
	var t: String = "[b]%s[/b]  %s\n\n" % [str(meta["title"]), str(meta["period"])]
	var h: Dictionary = Game.factions[fid]["historical"]
	t += UiKit.confidence_block(str(Game.factions[fid]["name"]), h)
	_info.text = t


func _on_begin() -> void:
	var fid: String = str(_factions()[_fid_idx])
	Game.start_new_campaign(_sid(), {"sandbox": true, "player": fid, "rich": _rich})
	Game.goto("game")


func _on_back() -> void:
	Game.goto("main_menu")
