class_name UI
## Shared UI kit: palette, font, chunky buttons, plates, panels, pop-in juice.

const INK := Color("1a1420")
const YELLOW := Color("ffd23f")
const TEAL := Color("4ecdc4")
const CORAL := Color("ff5a5f")
const GRAPE := Color("b388ff")
const CREAM := Color("fff6e5")
const WHITE := Color("ffffff")

static var _font: Font
static var _icons := {}

static func font() -> Font:
	if _font == null:
		_font = load("res://assets/kenney/lilita_one_regular.ttf")
	return _font

static func icon(name: String) -> Texture2D:
	if not _icons.has(name):
		_icons[name] = load("res://assets/ui/%s.svg" % name)
	return _icons[name]

static func label(text: String, size: int, color := WHITE, outline := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_color_override("font_outline_color", INK)
		l.add_theme_constant_override("outline_size", int(size * 0.26))
		l.add_theme_color_override("font_shadow_color", INK)
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", int(size * 0.08))
		l.add_theme_constant_override("shadow_outline_size", int(size * 0.26))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Big candy button. `icon_name` is a file in assets/ui/. Text may be "".
static func button(text: String, color: Color, size: int, cb: Callable, icon_name := "", min_size := Vector2.ZERO) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	var r := size * 0.75
	var d := clampf(size * 0.22, 6.0, 14.0)
	var pad := Vector2(size * 0.7 if text != "" else size * 0.35, size * 0.22)
	var up := ChunkyStyle.new(color, r, d, false, pad)
	var down := ChunkyStyle.new(color, r, d, true, pad)
	for st in ["normal", "hover", "disabled"]:
		b.add_theme_stylebox_override(st, up)
	for st in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, down)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", size)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, WHITE)
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", int(size * 0.28))
	if icon_name != "":
		b.icon = icon(icon_name)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", int(size * 1.15))
		b.add_theme_constant_override("h_separation", int(size * 0.25))
	b.button_down.connect(func():
		b.pivot_offset = b.size * 0.5
		b.create_tween().tween_property(b, "scale", Vector2(0.94, 0.94), 0.06))
	b.button_up.connect(func():
		b.pivot_offset = b.size * 0.5
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
	b.pressed.connect(func(): Game.play("land", 0.1, -6.0))
	b.pressed.connect(cb)
	return b

## Round icon-only button.
static func round_button(icon_name: String, color: Color, diameter: float, cb: Callable) -> Button:
	var b := button("", color, int(diameter * 0.42), cb, icon_name, Vector2(diameter, diameter))
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for st in ["normal", "hover", "disabled", "pressed", "hover_pressed"]:
		var s: ChunkyStyle = b.get_theme_stylebox(st)
		s.radius = diameter * 0.5
		s.content_margin_left = 0
		s.content_margin_right = 0
	return b

## Small rounded plate holding a label (HUD stats, skin name, panel headers).
static func plate(text: String, color: Color, size: int, icon_name := "") -> PanelContainer:
	var p := PanelContainer.new()
	var st := ChunkyStyle.new(color, size * 0.6, 6.0, false, Vector2(size * 0.55, size * 0.12))
	st.gloss = false
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", int(size * 0.25))
	p.add_child(hb)
	if icon_name != "":
		var tr := TextureRect.new()
		tr.texture = icon(icon_name)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(size, size) * 1.1
		hb.add_child(tr)
	var l := label(text, size)
	l.name = "Text"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(l)
	return p

static func plate_label(p: PanelContainer) -> Label:
	return p.find_child("Text", true, false)

## Modal: dim backdrop + centered cream card with a ribbon header.
## Returns [overlay, content_vbox]. Add overlay to a full-rect parent.
static func modal(title: String, ribbon_color := CORAL) -> Array:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.04, 0.12, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	# ribbon overlaps the card's top edge (negative separation, drawn on top)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", -34)
	center.add_child(stack)
	var ribbon := plate(title, ribbon_color, 50)
	ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ribbon.z_index = 1
	stack.add_child(ribbon)
	var card := PanelContainer.new()
	card.name = "Card"
	var st := ChunkyStyle.new(CREAM, 40, 14, false, Vector2(36, 26))
	st.content_margin_top = 56
	card.add_theme_stylebox_override("panel", st)
	card.custom_minimum_size = Vector2(540, 0)
	stack.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	card.add_child(vb)
	overlay.set_meta("card", stack)
	return [overlay, vb]

static func pop_in(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.6, 0.6)
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel().set_ignore_time_scale(true)
	tw.tween_property(c, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.15)

static func ink_text(text: String, size: int) -> Label:
	var l := label(text, size, INK, false)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
