extends Control
## Main play screen: HUD, map, info panel, actions, dialogs.

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Rules = preload("res://scripts/core/rules.gd")
const TurnManager = preload("res://scripts/core/turn_manager.gd")
const CombatResolver = preload("res://scripts/combat/combat_resolver.gd")
const MapView = preload("res://scripts/ui/map_view.gd")

var hud_turn: Label
var hud_res: Label
var map_view: Control
var info_text: RichTextLabel
var status_label: Label
var action_box: HFlowContainer
var end_turn_btn: Button
var overlay: Control = null

var selected_tid: String = ""
var selected_army: int = -1


func _ready() -> void:
	UiKit.full_rect(self)
	if Game.state.is_empty():
		Game.goto("main_menu")
		return
	_build_ui()
	var s: Dictionary = Game.state
	for a in s["armies"]:
		if a["owner"] == s["player"]:
			selected_tid = a["territory"]
			selected_army = int(a["id"])
			break
	_refresh()
	if s["status"] != "playing":
		_show_end()
	else:
		_check_pending_event()


# ------------------------------------------------------------------ layout
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.INK
	add_child(bg)
	UiKit.full_rect(bg)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	UiKit.full_rect(root)

	var hud := PanelContainer.new()
	hud.add_theme_stylebox_override("panel", UiKit.style(UiKit.INK_LIGHT, Color.TRANSPARENT, 0, 0))
	root.add_child(hud)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	hud.add_child(hv)
	hud_turn = UiKit.label("", 22, UiKit.GOLD)
	hud_res = UiKit.label("", 20, UiKit.TEXT)
	hv.add_child(hud_turn)
	hv.add_child(hud_res)

	map_view = MapView.new()
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.custom_minimum_size = Vector2(0, 360)
	root.add_child(map_view)
	map_view.territory_tapped.connect(_on_territory_tapped)

	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", UiKit.style(UiKit.INK_LIGHT, UiKit.GOLD, 0, 2))
	root.add_child(bottom)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	bottom.add_child(bv)
	info_text = UiKit.rich(210, 20)
	bv.add_child(info_text)
	status_label = UiKit.label("", 19, UiKit.GOLD)
	bv.add_child(status_label)
	action_box = HFlowContainer.new()
	action_box.add_theme_constant_override("h_separation", 8)
	action_box.add_theme_constant_override("v_separation", 8)
	bv.add_child(action_box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bv.add_child(row)
	end_turn_btn = UiKit.button("End Turn", 66, 26)
	end_turn_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_turn_btn.pressed.connect(_on_end_turn)
	row.add_child(end_turn_btn)
	var codex := UiKit.button("Codex", 66, 22)
	codex.pressed.connect(_show_codex)
	row.add_child(codex)
	var menu := UiKit.button("Menu", 66, 22)
	menu.pressed.connect(_show_menu)
	row.add_child(menu)


# ------------------------------------------------------------------ refresh
func _say(msg: String) -> void:
	status_label.text = msg


func _refresh() -> void:
	var s: Dictionary = Game.state
	var player: String = s["player"]
	var f: Dictionary = s["factions"][player]
	hud_turn.text = "%sTurn %d%s   %d, Q%d%s" % [
		"SANDBOX  " if bool(s.get("sandbox", false)) else "",
		int(s["turn"]), "" if bool(s.get("sandbox", false)) else " / %d" % int(s["max_turns"]),
		int(s["year"]), int(s["quarter"]),
		"  MONSOON" if Rules.is_monsoon(s) else ""]
	hud_res.text = "Revenue %d (%+d/turn)   Manpower %d   Stability %d" % [
		int(f["gold"]), int(f["last_income"]) - int(f["last_upkeep"]), int(f["manpower"]), int(f["stability"])]
	for other in s["factions"]:
		if other != player and Rules.has_truce(s, player, other):
			hud_res.text += "   Truce: %d" % Rules.truce_turns_left(s, player, other)
	if selected_army >= 0 and Rules.army_by_id(s, selected_army) == null:
		selected_army = -1
	if selected_tid == "":
		selected_tid = "pune"
	map_view.set_selection(selected_tid, selected_army, _compute_highlights())
	info_text.text = _territory_text(selected_tid)
	_rebuild_actions()
	end_turn_btn.disabled = s["status"] != "playing"


func _compute_highlights() -> Dictionary:
	var hl: Dictionary = {}
	var s: Dictionary = Game.state
	if selected_army < 0:
		return hl
	var army = Rules.army_by_id(s, selected_army)
	if army == null or army["owner"] != s["player"]:
		return hl
	for n in Rules.neighbours(army["territory"]):
		if Rules.can_move(s, army, n):
			hl[n] = UiKit.GREEN
		elif Rules.attack_targets(s, army).has(n):
			hl[n] = UiKit.RED
	return hl


func _units_text(units: Dictionary) -> String:
	var parts: Array = []
	for ut in units:
		if int(units[ut]) > 0:
			parts.append("%s %d" % [Game.units[ut]["short"], int(units[ut])])
	return ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "none"


func _territory_text(tid: String) -> String:
	var s: Dictionary = Game.state
	var td: Dictionary = Game.territories[tid]
	var ts: Dictionary = s["territories"][tid]
	var owner_id: String = ts["owner"]
	var t: String = "[b][color=#c8963e]%s[/color][/b] - %s\n" % [td["name"], Game.factions[owner_id]["name"]]
	t += "%s. Revenue %d%s, manpower %d.\n" % [Game.terrain[td["terrain"]]["name"], Rules.territory_revenue(s, tid),
		(" (developed +%d)" % int(ts.get("dev", 0))) if int(ts.get("dev", 0)) > 0 else "", int(td["manpower"])]
	var fid: String = Rules.fort_id_of(tid)
	if fid != "":
		t += "Fort: %s. Walls %d/%d. Garrison %s (cap %d).\n" % [
			Game.forts[fid]["name"], int(ts["wall"]), int(Game.forts[fid]["wall_max"]),
			_units_text(ts["garrison"]), Rules.garrison_capacity(tid)]
	else:
		var gt: int = Rules.unit_total(ts["garrison"])
		if gt > 0:
			t += "Garrison %s.\n" % _units_text(ts["garrison"])
	if Rules.in_network(s, owner_id, tid):
		t += "In a fort network: cheaper recruits and faster movement.\n"
	var d: int = Rules.supply_distance(s, owner_id, tid)
	t += "Supply line: %s.\n" % ("cut off" if d < 0 else ("source" if d == 0 else "%d hop(s) from source" % d))
	for a in Rules.armies_at(s, tid):
		var sel: String = ">> " if int(a["id"]) == selected_army else "- "
		var cname: String = "no commander"
		if str(a["commander"]) != "":
			cname = str(Game.commanders[a["commander"]]["name"])
		t += "%sArmy #%d (%s, %s): %s | Morale %d | Supply %d | Moves %d\n" % [
			sel, int(a["id"]), Game.factions[a["owner"]]["short_name"], cname,
			_units_text(a["units"]), int(a["morale"]), int(a["supply"]), int(a["moves_left"])]
	return t


func _rebuild_actions() -> void:
	for c in action_box.get_children():
		c.queue_free()
	var s: Dictionary = Game.state
	if s["status"] != "playing":
		return
	var player: String = s["player"]
	var tid: String = selected_tid
	if s["territories"][tid]["owner"] == player:
		for ut in Game.factions[player]["recruitable"]:
			var cost: int = Rules.recruit_cost(s, player, tid, ut)
			var b := UiKit.button("Recruit %s (%dg)" % [Game.units[ut]["short"], cost], 56, 19)
			b.disabled = not Rules.can_recruit(s, player, tid, ut)["ok"]
			b.pressed.connect(_on_recruit.bind(ut))
			action_box.add_child(b)
		var dev := UiKit.button("Develop (%dg)" % Rules.develop_cost(s, tid), 56, 19)
		dev.disabled = not Rules.can_develop(s, player, tid)["ok"]
		dev.pressed.connect(_on_develop)
		action_box.add_child(dev)
		if Rules.has_fort(tid):
			var rp := UiKit.button("Repair walls (%dg)" % Rules.REPAIR_COST, 56, 19)
			rp.disabled = not Rules.can_repair(s, player, tid)["ok"]
			rp.pressed.connect(_on_repair)
			action_box.add_child(rp)
	var here: Array = []
	for a in Rules.armies_at(s, tid):
		if a["owner"] == player:
			here.append(a)
	if here.size() > 1:
		for a in here:
			var b2 := UiKit.button("Select #%d" % int(a["id"]), 52, 18)
			b2.pressed.connect(_on_select_army.bind(int(a["id"])))
			action_box.add_child(b2)
	var army = Rules.army_by_id(s, selected_army) if selected_army >= 0 else null
	if army != null and army["owner"] == player and army["territory"] == tid and Rules.garrison_capacity(tid) > 0:
		var g1 := UiKit.button("Leave garrison", 52, 18)
		g1.pressed.connect(_on_garrison.bind(true))
		action_box.add_child(g1)
		var g2 := UiKit.button("Draw garrison", 52, 18)
		g2.pressed.connect(_on_garrison.bind(false))
		action_box.add_child(g2)
	if army != null and army["owner"] == player:
		if Rules.attack_targets(s, army).has(tid):
			var ab := UiKit.button("Attack / Besiege", 56, 19)
			ab.pressed.connect(_show_battle_dialog.bind(int(army["id"]), tid))
			action_box.add_child(ab)


# ------------------------------------------------------------------ input
func _on_territory_tapped(tid: String) -> void:
	var s: Dictionary = Game.state
	if s["status"] != "playing":
		selected_tid = tid
		_refresh()
		return
	var player: String = s["player"]
	_say("")
	if selected_army >= 0:
		var army = Rules.army_by_id(s, selected_army)
		if army != null and army["owner"] == player:
			if Rules.can_move(s, army, tid):
				Rules.move_army(s, army, tid)
				Sfx.play("move")
				selected_tid = tid
				_say("Army #%d moved to %s." % [int(army["id"]), Game.territories[tid]["name"]])
				_refresh()
				return
			if Rules.attack_targets(s, army).has(tid):
				selected_tid = tid
				_refresh()
				_show_battle_dialog(int(army["id"]), tid)
				return
	selected_tid = tid
	var mine: Array = []
	for a in Rules.armies_at(s, tid):
		if a["owner"] == player:
			mine.append(a)
	if mine.is_empty():
		selected_army = -1
	else:
		var idx: int = -1
		for i in range(mine.size()):
			if int(mine[i]["id"]) == selected_army:
				idx = i
		selected_army = int(mine[(idx + 1) % mine.size()]["id"])
	_refresh()


func _on_select_army(id: int) -> void:
	selected_army = id
	_refresh()


func _on_recruit(ut: String) -> void:
	var s: Dictionary = Game.state
	var res: Dictionary = Rules.recruit(s, s["player"], selected_tid, ut)
	_say(str(res["msg"]))
	for a in Rules.armies_at(s, selected_tid):
		if a["owner"] == s["player"] and selected_army < 0:
			selected_army = int(a["id"])
	_refresh()


func _on_develop() -> void:
	var s: Dictionary = Game.state
	_say(str(Rules.develop(s, s["player"], selected_tid)["msg"]))
	_refresh()


func _on_repair() -> void:
	var s: Dictionary = Game.state
	_say(str(Rules.repair_walls(s, s["player"], selected_tid)["msg"]))
	_refresh()


func _on_garrison(leave: bool) -> void:
	var s: Dictionary = Game.state
	var army = Rules.army_by_id(s, selected_army)
	if army == null:
		return
	var res: Dictionary = Rules.leave_garrison(s, army) if leave else Rules.draw_garrison(s, army)
	_say(str(res["msg"]))
	_refresh()


# ------------------------------------------------------------------ dialogs
func _close_dialog() -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null


## buttons: Array of [text, Callable]
func _open_dialog(title: String, body: String, buttons: Array) -> void:
	_close_dialog()
	overlay = Control.new()
	add_child(overlay)
	UiKit.full_rect(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	overlay.add_child(dim)
	UiKit.full_rect(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.style(UiKit.INK_LIGHT, UiKit.GOLD, 14, 3))
	overlay.add_child(panel)
	UiKit.full_rect(panel)
	panel.offset_left = 22.0
	panel.offset_right = -22.0
	panel.offset_top = 70.0
	panel.offset_bottom = -70.0
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(UiKit.label(title, 30, UiKit.GOLD))
	var rt := UiKit.rich(0, 20)
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.text = body
	v.add_child(rt)
	var hb := HFlowContainer.new()
	hb.add_theme_constant_override("h_separation", 8)
	hb.add_theme_constant_override("v_separation", 8)
	v.add_child(hb)
	for spec in buttons:
		var b := UiKit.button(str(spec[0]), 58, 20)
		b.pressed.connect(_on_dialog_button.bind(spec[1]))
		hb.add_child(b)


func _on_dialog_button(cb: Callable) -> void:
	_close_dialog()
	if cb.is_valid():
		cb.call()


# ---- battle
func _show_battle_dialog(army_id: int, tid: String) -> void:
	var s: Dictionary = Game.state
	var army = Rules.army_by_id(s, army_id)
	if army == null:
		return
	var td: Dictionary = Game.territories[tid]
	var ts: Dictionary = s["territories"][tid]
	var pv: Dictionary = Rules.battle_preview(s, army, tid, "balanced")
	var ratio: float = float(pv["ratio"])
	var fid: String = Rules.fort_id_of(tid)
	var t: String = "[b]Target: %s[/b] (%s)\n" % [td["name"], Game.terrain[td["terrain"]]["name"]]
	t += "Your army #%d: %s\nDefenders: %s\n" % [int(army["id"]), _units_text(army["units"]), _units_text(pv["defenders"]["units"])]
	if fid != "":
		t += "Fort walls: %d/%d. Besieging lowers walls; guns lower them faster and help in assaults.\n" % [
			int(ts["wall"]), int(Game.forts[fid]["wall_max"])]
	t += "\nBalanced estimate: your power %d vs %d.\nOdds: [b]%s[/b] (ratio %.2f)\n" % [
		int(pv["attack"]), int(pv["defense"]), CombatResolver.odds_label(ratio), ratio]
	t += "\nAggressive: +20% attack but +25% own losses.\nCautious: -15% attack and -25% own losses.\nA win captures the territory; a loss costs morale."
	var btns: Array = [
		["Aggressive", _do_attack.bind(army_id, tid, "aggressive")],
		["Balanced", _do_attack.bind(army_id, tid, "balanced")],
		["Cautious", _do_attack.bind(army_id, tid, "cautious")]
	]
	if fid != "" and float(ts["wall"]) > 0.0:
		btns.append(["Besiege", _do_besiege.bind(army_id, tid)])
	btns.append(["Cancel", Callable()])
	_open_dialog("Battle", t, btns)


func _do_attack(army_id: int, tid: String, tactic: String) -> void:
	var s: Dictionary = Game.state
	var army = Rules.army_by_id(s, army_id)
	if army == null:
		return
	var res: Dictionary = Rules.attack(s, army, tid, tactic)
	Sfx.play("battle")
	if not res["ok"]:
		_say(str(res["msg"]))
		_refresh()
		return
	var t: String = "[b]%s[/b]\n\n" % res["msg"]
	t += "Attacker power %d vs defender power %d.\n" % [int(res["attacker_power"]), int(res["defender_power"])]
	t += "Your losses: %s\nEnemy losses: %s\n" % [
		_units_text(res["attacker_losses"] if res["attacker_owner"] == s["player"] else res["defender_losses"]),
		_units_text(res["defender_losses"] if res["attacker_owner"] == s["player"] else res["attacker_losses"])]
	if res["captured"]:
		selected_tid = tid
	Game.save_game()
	_refresh()
	if s["status"] != "playing":
		_open_dialog("Battle result", t, [["Continue", _show_end]])
	else:
		_open_dialog("Battle result", t, [["OK", Callable()]])


func _do_besiege(army_id: int, tid: String) -> void:
	var s: Dictionary = Game.state
	var army = Rules.army_by_id(s, army_id)
	if army == null:
		return
	var res: Dictionary = Rules.besiege(s, army, tid)
	_say(str(res["msg"]))
	Game.save_game()
	_refresh()


# ---- turn
func _on_end_turn() -> void:
	var s: Dictionary = Game.state
	if s["status"] != "playing":
		return
	_close_dialog()
	_say("")
	var report: Array = TurnManager.end_player_turn(s)
	Game.save_game()
	_refresh()
	if s["status"] != "playing":
		_show_end()
		return
	var body: String = "[b]Turn %d begins.[/b]\n\n" % int(s["turn"])
	for line in report:
		body += "- %s\n" % str(line)
	_open_dialog("Turn report", body, [["OK", _check_pending_event]])


# ---- menu hub
func _show_menu() -> void:
	_open_dialog("Menu", "Progress is saved automatically every turn and after each battle.", [
		["Resume", Callable()],
		["Armies", _show_armies],
		["Diplomacy", _show_diplomacy],
		["Event log", _show_log],
		["Timeline", _show_timeline],
		["Save now", _menu_save],
		["Main menu", _menu_main]
	])


func _menu_save() -> void:
	_say("Saved." if Game.save_game() else "Save failed.")


func _menu_main() -> void:
	Game.save_game()
	Game.goto("main_menu")


func _show_armies() -> void:
	var s: Dictionary = Game.state
	var body: String = ""
	var btns: Array = []
	for a in Rules.faction_armies(s, s["player"]):
		var cname: String = "no commander"
		if str(a["commander"]) != "":
			cname = str(Game.commanders[a["commander"]]["name"])
		body += "[b]Army #%d[/b] at %s - %s\n%s | Morale %d | Supply %d | Moves %d\n\n" % [
			int(a["id"]), Game.territories[a["territory"]]["name"], cname,
			_units_text(a["units"]), int(a["morale"]), int(a["supply"]), int(a["moves_left"])]
		btns.append(["Go to #%d" % int(a["id"]), _focus_army.bind(int(a["id"]))])
	if body == "":
		body = "You have no armies. Recruit in a territory you hold."
	btns.append(["Close", Callable()])
	_open_dialog("Your armies", body, btns)


func _focus_army(id: int) -> void:
	var army = Rules.army_by_id(Game.state, id)
	if army == null:
		return
	selected_army = id
	selected_tid = army["territory"]
	_refresh()


func _show_log() -> void:
	var s: Dictionary = Game.state
	var lines: Array = s["log"]
	var body: String = ""
	var start: int = maxi(0, lines.size() - 40)
	for i in range(lines.size() - 1, start - 1, -1):
		body += "- %s\n" % str(lines[i])
	_open_dialog("Event log (newest first)", body, [["Close", Callable()]])


func _show_timeline() -> void:
	_open_dialog("Timeline", UiKit.timeline_bbcode(str(Game.state["scenario_id"])), [["Close", Callable()]])


func _show_diplomacy() -> void:
	var s: Dictionary = Game.state
	var player: String = s["player"]
	var body: String = "[i]Diplomacy here is a gameplay abstraction. A rival agrees to a truce only if your forces are at least as strong as theirs, or if they have been worn down by recent losses. Terms cost %d revenue and last %d turns. While a truce holds, neither side can attack or besiege the other.[/i]\n\n" % [Rules.TRUCE_COST, Rules.TRUCE_TURNS]
	var btns: Array = []
	for other in s["factions"]:
		if other == player:
			continue
		var fname: String = str(Game.factions[other]["name"])
		var ratio: float = Rules.military_strength(s, player) / maxf(1.0, Rules.military_strength(s, other))
		body += "[b]%s[/b]\nRelative strength %.2f. War weariness %d.\n" % [fname, ratio, int(s["factions"][other]["weariness"])]
		if Rules.has_truce(s, player, other):
			body += "Truce in force: %d turn(s) left.\n\n" % Rules.truce_turns_left(s, player, other)
		else:
			var why: String = Rules.truce_blocker(s, player, other)
			body += ("%s\n\n" % why) if why != "" else "No truce. You may offer terms.\n\n"
			if why == "":
				btns.append(["Offer truce (%dg)" % Rules.TRUCE_COST, _do_truce.bind(other)])
	btns.append(["Close", Callable()])
	_open_dialog("Diplomacy", body, btns)


func _do_truce(other: String) -> void:
	var s: Dictionary = Game.state
	var res: Dictionary = Rules.propose_truce(s, s["player"], other)
	_say(str(res["msg"]))
	Game.save_game()
	_refresh()
	_open_dialog("Diplomacy", str(res["msg"]), [["OK", Callable()]])


# ---- events
func _check_pending_event() -> void:
	var s: Dictionary = Game.state
	if s["status"] != "playing":
		return
	var id: String = str(s.get("pending_event", ""))
	if id == "":
		return
	var e: Dictionary = Rules.event_by_id(id)
	if e.is_empty():
		s["pending_event"] = ""
		return
	Sfx.play("event")
	var body: String = "%s\n\n" % str(e["text"])
	var btns: Array = []
	var gold: int = int(s["factions"][s["player"]]["gold"])
	for i in range(e["choices"].size()):
		var ch: Dictionary = e["choices"][i]
		var fx: String = Rules.describe_effects(ch["effects"])
		var need: int = int(ch.get("min_gold", 0))
		body += "[b]%s[/b]%s\n   %s\n" % [str(ch["label"]), ("  (needs %d revenue)" % need) if need > 0 else "", fx]
		var label: String = str(ch["label"])
		btns.append([label, _on_event_choice.bind(id, i)])
	body += "\n" + UiKit.confidence_block("Historical note", e["historical"])
	body += "[i]The numeric effects are gameplay values, not records.[/i]"
	_open_dialog(str(e["title"]), body, btns)
	# Disable unaffordable choices.
	var hb: Control = _dialog_button_box()
	if hb != null:
		for i in range(e["choices"].size()):
			if gold < int(e["choices"][i].get("min_gold", 0)) and i < hb.get_child_count():
				hb.get_child(i).disabled = true


func _dialog_button_box() -> Control:
	if overlay == null:
		return null
	var panel: Node = overlay.get_child(1)
	var v: Node = panel.get_child(0)
	return v.get_child(v.get_child_count() - 1) as Control


func _on_event_choice(id: String, idx: int) -> void:
	var s: Dictionary = Game.state
	var res: Dictionary = Rules.resolve_event(s, id, idx)
	_say(str(res["msg"]))
	Game.save_game()
	_refresh()
	if s["status"] != "playing":
		_show_end()
	else:
		_check_pending_event()


# ---- end screen
func _show_end() -> void:
	var s: Dictionary = Game.state
	var ho: Dictionary = Game.scenario["historical_outcome"]
	Sfx.play("win" if s["status"] == "won" else "lose")
	var t: String = "[b][color=#c8963e]PLAYER OUTCOME%s[/color][/b]\n%s\n\n" % [
		" (SANDBOX)" if bool(s.get("sandbox", false)) else "", Rules.player_outcome(s)]
	t += _confidence_block("HISTORICAL OUTCOME", ho)
	_open_dialog("Campaign over", t, [
		["View map", Callable()],
		["Main menu", _menu_main]
	])


# ---- codex
func _confidence_color(conf: String) -> String:
	if conf == "HIGH":
		return "#5f9a63"
	if conf == "MEDIUM":
		return "#d6a23e"
	return "#c0553f"


func _confidence_block(title: String, h: Dictionary) -> String:
	var conf: String = str(h.get("confidence", "UNCERTAIN"))
	var t: String = "[b][color=#c8963e]%s[/color][/b]  [color=%s](confidence: %s)[/color]\n%s\n" % [
		title, _confidence_color(conf), conf, str(h.get("text", "No entry."))]
	var src: Array = h.get("sources", [])
	if not src.is_empty():
		t += "[i]Source pointers, still to be verified page by page: %s[/i]\n" % "; ".join(PackedStringArray(src))
	return t


func _show_codex() -> void:
	var s: Dictionary = Game.state
	var tid: String = selected_tid
	var td: Dictionary = Game.territories[tid]
	var t: String = "[b]HISTORICAL INFORMATION vs GAMEPLAY INFORMATION[/b]\nHistorical text carries a confidence tag. Gameplay numbers are always abstractions.\n\n"
	t += _confidence_block("Scenario background", Game.scenario["historical_background"]) + "\n"
	t += _confidence_block("Territory: %s" % td["name"], td["historical"])
	t += "[b]Gameplay:[/b] %s terrain, revenue %d, manpower %d. The map is schematic, not to scale.\n\n" % [
		Game.terrain[td["terrain"]]["name"], int(td["revenue"]), int(td["manpower"])]
	var fid: String = Rules.fort_id_of(tid)
	if fid != "":
		var f: Dictionary = Game.forts[fid]
		t += _confidence_block("Fort: %s" % f["name"], f["historical"])
		t += "[b]Gameplay:[/b] defence bonus %.2f, strategic value %d, wall max %d. %s\n\n" % [
			float(f["defense"]), int(f["strategic"]), int(f["wall_max"]), str(f.get("gameplay_note", ""))]
	var army = Rules.army_by_id(s, selected_army) if selected_army >= 0 else null
	if army != null and str(army["commander"]) != "":
		var c: Dictionary = Game.commanders[army["commander"]]
		t += _confidence_block("Commander: %s" % c["name"], c["historical"])
		var g: Dictionary = c["gameplay"]
		t += "[b]Gameplay:[/b] attack %+d%%, defence %+d%%, speed %+d, trait: %s.\n\n" % [
			int(round(float(g["attack_mod"]) * 100.0)), int(round(float(g["defense_mod"]) * 100.0)),
			int(g["speed_bonus"]), str(g["trait"])]
	var owner_id: String = s["territories"][tid]["owner"]
	t += _confidence_block("Faction: %s" % Game.factions[owner_id]["name"], Game.factions[owner_id]["historical"])
	t += "[b]Gameplay:[/b] %s\n\n" % str(Game.factions[owner_id].get("gameplay_note", ""))
	t += "[b]Rules in this build:[/b] fort walls fall with sieges and rebuild when not besieged. Supply depends on distance to a fort or core territory. Fort networks cut recruit costs by 10% and ease movement. The AI sees the whole map (no fog of war yet)."
	_open_dialog("Codex", t, [["Close", Callable()]])
