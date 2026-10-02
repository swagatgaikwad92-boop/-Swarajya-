extends RefCounted
## Small helpers so screens can be built in code with a consistent look.

const INK = Color("#14110f")
const INK_LIGHT = Color("#241e19")
const PARCH = Color("#d7c59b")
const GOLD = Color("#c8963e")
const TEXT = Color("#efe4cc")
const MUTED = Color("#a89a80")
const RED = Color("#c0553f")
const GREEN = Color("#5f9a63")


static func style(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 10, border_w: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.set_content_margin_all(12)
	return sb


static func button(text: String, min_h: int = 64, font_size: int = 24) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_disabled_color", Color("#6f6455"))
	b.add_theme_stylebox_override("normal", style(Color("#3a2f24"), GOLD, 10, 2))
	b.add_theme_stylebox_override("hover", style(Color("#4a3c2d"), GOLD, 10, 2))
	b.add_theme_stylebox_override("pressed", style(GOLD, GOLD, 10, 2))
	b.add_theme_stylebox_override("disabled", style(Color("#26201a"), Color("#4a3f31"), 10, 2))
	b.add_theme_stylebox_override("focus", style(Color.TRANSPARENT, GOLD, 10, 3))
	b.pressed.connect(Sfx.play.bind("click"))
	return b


static func label(text: String, size: int = 24, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func full_rect(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func margin(c: MarginContainer, px: int) -> void:
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		c.add_theme_constant_override(side, px)


static func rich(min_h: int = 0, size: int = 22) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = true
	r.fit_content = false
	r.custom_minimum_size = Vector2(0, min_h)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	r.add_theme_color_override("default_color", TEXT)
	return r


static func confidence_color(conf: String) -> String:
	if conf == "HIGH":
		return "#5f9a63"
	if conf == "MEDIUM":
		return "#d6a23e"
	return "#c0553f"


## BBCode block: title, confidence tag, text and source pointers.
static func confidence_block(title: String, h: Dictionary) -> String:
	var conf: String = str(h.get("confidence", "UNCERTAIN"))
	var t: String = "[b][color=#c8963e]%s[/color][/b]  [color=%s](confidence: %s)[/color]\n%s\n" % [
		title, confidence_color(conf), conf, str(h.get("text", "No entry."))]
	var src: Array = h.get("sources", [])
	if not src.is_empty():
		t += "[i]Source pointers, still to be verified page by page: %s[/i]\n" % "; ".join(PackedStringArray(src))
	return t


## Timeline as BBCode. If scenario_id is given, entries for that scenario are marked.
static func timeline_bbcode(scenario_id: String = "") -> String:
	var items: Array = Game.timeline.duplicate()
	items.sort_custom(func(a, b): return int(a["year"]) < int(b["year"]))
	var t: String = "[i]Dates carry confidence tags. This is a reading aid, not a verified chronology.[/i]\n\n"
	for e in items:
		var conf: String = str(e.get("confidence", "UNCERTAIN"))
		var mark: String = ""
		if scenario_id != "" and e.get("scenarios", []).has(scenario_id):
			mark = "  [color=#c8963e](in this campaign)[/color]"
		t += "[b]%d - %s[/b]%s\n[color=%s](%s)[/color] %s\n\n" % [
			int(e["year"]), str(e["title"]), mark, confidence_color(conf), conf, str(e["text"])]
	return t
