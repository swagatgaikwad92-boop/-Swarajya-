extends Control
## Draws the abstract campaign map and handles pan, zoom and tapping.
## The map is schematic, not geographic: distances are not to scale.

signal territory_tapped(tid)

const UiKit = preload("res://scripts/ui/ui_kit.gd")
const NODE_R = 36.0
const TAP_RADIUS = 70.0

var zoom: float = 0.7
var offset: Vector2 = Vector2.ZERO
var highlights: Dictionary = {}      # tid -> Color
var selected_tid: String = ""
var selected_army: int = -1

var _pressed: bool = false
var _moved: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _fitted: bool = false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_on_resized)
	_build_zoom_buttons()


func _build_zoom_buttons() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 0.0
	box.anchor_bottom = 0.0
	box.offset_left = -84.0
	box.offset_right = -10.0
	box.offset_top = 10.0
	box.offset_bottom = 10.0
	box.add_theme_constant_override("separation", 8)
	for spec in [["+", 1.25], ["-", 0.8]]:
		var b := UiKit.button(spec[0], 64, 30)
		b.pressed.connect(zoom_by.bind(float(spec[1])))
		box.add_child(b)
	var fit := UiKit.button("Fit", 56, 20)
	fit.pressed.connect(reset_view)
	box.add_child(fit)


func _on_resized() -> void:
	if not _fitted and size.x > 10.0 and size.y > 10.0:
		reset_view()
		_fitted = true
	queue_redraw()


func set_selection(tid: String, army_id: int, hl: Dictionary) -> void:
	selected_tid = tid
	selected_army = army_id
	highlights = hl
	queue_redraw()


func _pos(tid: String) -> Vector2:
	var p: Array = Game.territories[tid]["pos"]
	return Vector2(float(p[0]), float(p[1]))


func to_screen(p: Vector2) -> Vector2:
	return p * zoom + offset


func to_map(sp: Vector2) -> Vector2:
	return (sp - offset) / zoom


func reset_view() -> void:
	if Game.territories.is_empty():
		return
	var minp := Vector2(1e9, 1e9)
	var maxp := Vector2(-1e9, -1e9)
	for tid in Game.territories:
		var p: Vector2 = _pos(tid)
		minp = Vector2(minf(minp.x, p.x), minf(minp.y, p.y))
		maxp = Vector2(maxf(maxp.x, p.x), maxf(maxp.y, p.y))
	minp -= Vector2(110, 150)
	maxp += Vector2(110, 110)
	var span: Vector2 = maxp - minp
	zoom = clampf(minf(size.x / span.x, size.y / span.y), 0.25, 2.0)
	offset = size / 2.0 - (minp + span / 2.0) * zoom
	queue_redraw()


func zoom_by(factor: float) -> void:
	_zoom_at(size / 2.0, factor)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var old: float = zoom
	zoom = clampf(zoom * factor, 0.3, 2.2)
	var ratio: float = zoom / old
	offset = screen_pos - (screen_pos - offset) * ratio
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_moved = false
				_press_pos = mb.position
			else:
				if _pressed and not _moved:
					_tap(mb.position)
				_pressed = false
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.1)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.1)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _pressed:
			if not _moved and (mm.position - _press_pos).length() > 14.0:
				_moved = true
			if _moved:
				offset += mm.relative
				queue_redraw()
	elif event is InputEventMagnifyGesture:
		var mg: InputEventMagnifyGesture = event
		_zoom_at(mg.position, mg.factor)


func _tap(pos: Vector2) -> void:
	var mp: Vector2 = to_map(pos)
	var best: String = ""
	var best_d: float = TAP_RADIUS
	for tid in Game.territories:
		var d: float = _pos(tid).distance_to(mp)
		if d < best_d:
			best_d = d
			best = tid
	if best != "":
		territory_tapped.emit(best)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#cdb98d"))
	draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), Color("#5a4a30"), false, 3.0)
	var s: Dictionary = Game.state
	if s.is_empty() or Game.territories.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var fs: int = int(clampf(24.0 * zoom, 13.0, 30.0))
	var ink := Color("#2a2118")

	# Links between territories.
	for tid in Game.territories:
		for n in Game.territories[tid]["neighbours"]:
			if tid < n:
				draw_line(to_screen(_pos(tid)), to_screen(_pos(n)), Color("#6b5a3e", 0.75), maxf(2.0, 4.0 * zoom), true)

	var r: float = NODE_R * zoom
	for tid in Game.territories:
		var td: Dictionary = Game.territories[tid]
		var ts: Dictionary = s["territories"][tid]
		var p: Vector2 = to_screen(_pos(tid))
		var owner_col := Color(Game.factions[ts["owner"]]["color"])
		var terr_col := Color(Game.terrain[td["terrain"]]["color"])
		draw_circle(p, r + 7.0 * zoom, owner_col)
		draw_circle(p, r, terr_col)

		if highlights.has(tid):
			draw_arc(p, r + 16.0 * zoom, 0.0, TAU, 40, highlights[tid], maxf(3.0, 6.0 * zoom))
		if tid == selected_tid:
			draw_arc(p, r + 24.0 * zoom, 0.0, TAU, 40, Color("#fff4d0"), maxf(3.0, 5.0 * zoom))

		# Fort icon.
		if str(td.get("fort", "")) != "":
			var u: float = zoom
			draw_rect(Rect2(p + Vector2(-15, -10) * u, Vector2(30, 22) * u), ink)
			for i in range(3):
				draw_rect(Rect2(p + Vector2(-15 + i * 11, -18) * u, Vector2(8, 9) * u), ink)
		# Garrison number.
		var g: int = 0
		for ut in ts["garrison"]:
			g += int(ts["garrison"][ut])
		if g > 0:
			draw_string(font, p + Vector2(-r, r * 0.55 + fs * 0.4), "G%d" % g,
				HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, ink)
		# Name.
		draw_string(font, p + Vector2(-90.0 * zoom, r + 24.0 * zoom), str(td["name"]),
			HORIZONTAL_ALIGNMENT_CENTER, 180.0 * zoom, fs, ink)
		# Wall bar.
		var fid: String = str(td.get("fort", ""))
		if fid != "":
			var ratio: float = clampf(float(ts["wall"]) / float(Game.forts[fid]["wall_max"]), 0.0, 1.0)
			var bw: float = 64.0 * zoom
			var by: float = r + 30.0 * zoom
			draw_rect(Rect2(p + Vector2(-bw / 2.0, by), Vector2(bw, 7.0 * zoom)), Color("#5a4a30"))
			draw_rect(Rect2(p + Vector2(-bw / 2.0, by), Vector2(bw * ratio, 7.0 * zoom)), Color("#8e2f23"))

		# Armies stacked above the territory.
		var idx: int = 0
		for a in s["armies"]:
			if a["territory"] != tid:
				continue
			var total: int = 0
			for ut in a["units"]:
				total += int(a["units"][ut])
			var w: float = 70.0 * zoom
			var h: float = 28.0 * zoom
			var top: Vector2 = p + Vector2(-w / 2.0, -r - 20.0 * zoom - h - float(idx) * (h + 4.0 * zoom))
			var col := Color(Game.factions[a["owner"]]["color"])
			draw_rect(Rect2(top, Vector2(w, h)), col.darkened(0.25))
			var sel: bool = int(a["id"]) == selected_army
			draw_rect(Rect2(top, Vector2(w, h)), Color("#fff4d0") if sel else ink, false, 3.0 if sel else 2.0)
			draw_string(font, top + Vector2(0, h * 0.74), "#%d  x%d" % [int(a["id"]), total],
				HORIZONTAL_ALIGNMENT_CENTER, w, int(clampf(20.0 * zoom, 11.0, 24.0)), Color("#fff8e6"))
			idx += 1
