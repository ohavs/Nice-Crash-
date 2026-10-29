class_name ChunkyStyle
extends StyleBox
## Toon "candy" box used by every button/panel: ink outline, darker bottom
## lip, two-tone body and a gloss streak. Built from flat boxes at draw time,
## so it stays crisp at any size and screen density.

const INK := Color("1a1420")

var color := Color("ffd23f")
var radius := 28.0
var depth := 9.0      # height of the bottom lip
var outline := 5.0
var pressed := false
var gloss := true

static var _sb: StyleBoxFlat

func _init(c := Color("ffd23f"), r := 28.0, d := 9.0, is_pressed := false, pad := Vector2(28, 10)) -> void:
	color = c
	radius = r
	depth = d
	pressed = is_pressed
	var sink := _sink()
	content_margin_left = pad.x
	content_margin_right = pad.x
	content_margin_top = outline + pad.y + sink
	content_margin_bottom = outline + pad.y + depth - sink

func _sink() -> float:
	return depth * 0.8 if pressed else 0.0

func _draw(ci: RID, rect: Rect2) -> void:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	_box(ci, Rect2(rect.position + Vector2(0, 5), rect.size), Color(0, 0, 0, 0.22), r)  # contact shadow
	_box(ci, rect, INK, r)
	var inner := rect.grow(-outline)
	var ir := maxf(r - outline, 0.0)
	_box(ci, inner, color.darkened(0.32), ir)  # lip
	var body := Rect2(inner.position + Vector2(0, _sink()), inner.size - Vector2(0, depth))
	_box(ci, body, color, ir)
	# lighter upper half (toon two-tone)
	var top_h := maxf(body.size.y * 0.52, ir)
	_box(ci, Rect2(body.position, Vector2(body.size.x, top_h)), color.lightened(0.16), ir, 0.0)
	if gloss and body.size.y > 24:
		var gh := clampf(body.size.y * 0.2, 5.0, 16.0)
		var inset := maxf(ir * 0.55, 8.0)
		var g := Rect2(body.position + Vector2(inset, body.size.y * 0.1), Vector2(body.size.x - inset * 2.0, gh))
		if g.size.x > gh:
			_box(ci, g, Color(1, 1, 1, 0.45), gh * 0.5)

static func _box(ci: RID, rect: Rect2, c: Color, r_top: float, r_bottom := -1.0) -> void:
	if _sb == null:
		_sb = StyleBoxFlat.new()
		_sb.anti_aliasing = true
		_sb.corner_detail = 10
	if r_bottom < 0.0:
		r_bottom = r_top
	_sb.bg_color = c
	_sb.corner_radius_top_left = int(r_top)
	_sb.corner_radius_top_right = int(r_top)
	_sb.corner_radius_bottom_left = int(r_bottom)
	_sb.corner_radius_bottom_right = int(r_bottom)
	_sb.draw(ci, rect)
