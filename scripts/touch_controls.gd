class_name TouchControls
extends Control
## Floating joystick + JUMP / GRAB / ACT buttons. Positions come from Game.layout
## (fractions of the screen) and can be dragged around in edit mode.
## A touch that misses the buttons drives the joystick if it is closer to the
## joystick's home than to any button; one on the upper part of the screen
## drags the camera around instead (consume_look()). Keyboard fallback for PC testing:
## WASD/arrows, Space, E/Shift (grab), F/Q (act).

signal layout_changed

const JOY_RADIUS := 105.0
const KNOB_RADIUS := 46.0
## How far (fraction of its radius) the joystick base may slide away from
## its home spot to meet the thumb: a little give, not a wandering stick.
const JOY_DRIFT := 0.3

var move := Vector2.ZERO
var jump_pressed := false
var grab_held := false
var act_pressed := false
## What the ACT button says: PUSH, THROW, SHOOT, BONK, YEET...
var act_label := "PUSH"
var act_ammo := 0
var edit_mode := false

var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _kb := false
var _btn_touch := {}   # touch index -> "jump"/"grab"/"act"
var _look_index := -1
var _look := 0.0
var _drag := {}        # edit mode: touch index -> [item, grab offset]
## Edit mode: the control the size buttons act on.
var selected := "jump"

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _btn_radius() -> float:
	var s := get_viewport_rect().size
	return clampf(minf(s.x, s.y) * 0.13, 55.0, 100.0)

func _joy_r() -> float:
	return JOY_RADIUS * Game.sizes.joy

## item -> [center, radius]
func _items() -> Dictionary:
	var s := get_viewport_rect().size
	var r := _btn_radius()
	return {
		"jump": [Game.layout.jump * s, r * Game.sizes.jump],
		"grab": [Game.layout.grab * s, r * 0.8 * Game.sizes.grab],
		"act": [Game.layout.act * s, r * 0.8 * Game.sizes.act],
		"joy": [Game.layout.joy * s, _joy_r()],
	}

## Edit mode: grow / shrink the selected control by `step`, within limits.
func resize_selected(step: float) -> void:
	Game.sizes[selected] = clampf(snappedf(Game.sizes[selected] + step, 0.05), Game.SIZE_MIN, Game.SIZE_MAX)
	# keep it on screen at its new size
	var s := get_viewport_rect().size
	var r: float = _items()[selected][1]
	Game.layout[selected] = (Game.layout[selected] * s).clamp(Vector2(r, r), s - Vector2(r, r)) / s
	layout_changed.emit()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if edit_mode:
		_edit_input(event)
		return
	var items := _items()
	if event is InputEventScreenTouch:
		if event.pressed:
			for b in ["jump", "grab", "act"]:
				if event.position.distance_to(items[b][0]) < items[b][1] * 1.2:
					_btn_touch[event.index] = b
					if b == "jump":
						jump_pressed = true
					elif b == "act":
						act_pressed = true
					else:
						grab_held = true
					queue_redraw()
					return
			var near_joy: bool = event.position.distance_to(items.joy[0]) < _joy_r() * 1.6
			if _look_index == -1 and not near_joy and event.position.y < get_viewport_rect().size.y * 0.5:
				_look_index = event.index
				return
			if _joy_index == -1 and _closest(event.position, items) == "joy":
				_joy_index = event.index
				var home: Vector2 = items.joy[0]
				_joy_origin = home + (event.position - home).limit_length(_joy_r() * JOY_DRIFT)
				_joy_pos = event.position
				move = ((_joy_pos - _joy_origin) / _joy_r()).limit_length(1.0)
		else:
			if event.index == _look_index:
				_look_index = -1
			if event.index == _joy_index:
				_joy_index = -1
				move = Vector2.ZERO
			if _btn_touch.has(event.index):
				if _btn_touch[event.index] == "grab":
					grab_held = false
				_btn_touch.erase(event.index)
		queue_redraw()
	elif event is InputEventScreenDrag and event.index == _look_index:
		_look += event.relative.x
	elif event is InputEventScreenDrag and event.index == _joy_index:
		_joy_pos = event.position
		var jr := _joy_r()
		var d: Vector2 = _joy_pos - _joy_origin
		if d.length() > jr:
			# follow the finger a little, but never far from home
			var home: Vector2 = Game.layout.joy * get_viewport_rect().size
			_joy_origin = home + (_joy_pos - d.normalized() * jr - home).limit_length(jr * JOY_DRIFT)
		move = ((_joy_pos - _joy_origin) / jr).limit_length(1.0)
		queue_redraw()

func _closest(p: Vector2, items: Dictionary) -> String:
	var best := ""
	var best_d := INF
	for k in items:
		# distance to the item's edge, so the big joystick zone isn't penalised
		var d: float = p.distance_to(items[k][0]) - items[k][1]
		if d < best_d:
			best_d = d
			best = k
	return best

func _edit_input(event: InputEvent) -> void:
	var s := get_viewport_rect().size
	if event is InputEventScreenTouch:
		if event.pressed:
			var items := _items()
			for k in ["jump", "grab", "act", "joy"]:
				if event.position.distance_to(items[k][0]) < items[k][1] * 1.1:
					_drag[event.index] = [k, items[k][0] - event.position]
					selected = k
					queue_redraw()
					break
		elif _drag.has(event.index):
			_drag.erase(event.index)
			layout_changed.emit()
	elif event is InputEventScreenDrag and _drag.has(event.index):
		var k: String = _drag[event.index][0]
		var r: float = _items()[k][1]
		var p: Vector2 = (event.position + _drag[event.index][1]).clamp(Vector2(r, r), s - Vector2(r, r))
		Game.layout[k] = p / s
		queue_redraw()

func release_all() -> void:
	_joy_index = -1
	_look_index = -1
	_look = 0.0
	move = Vector2.ZERO
	grab_held = false
	_btn_touch.clear()
	_drag.clear()
	queue_redraw()

func read_keyboard() -> void:
	if _joy_index != -1:
		return
	var k := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if k != Vector2.ZERO:
		move = k.limit_length(1.0)
		_kb = true
	elif _kb:
		move = Vector2.ZERO
		_kb = false

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		if event.physical_keycode == KEY_SPACE and event.pressed:
			jump_pressed = true
		if event.physical_keycode in [KEY_E, KEY_SHIFT]:
			grab_held = event.pressed
		if event.physical_keycode in [KEY_F, KEY_Q] and event.pressed:
			act_pressed = true

func consume_jump() -> bool:
	var j := jump_pressed
	jump_pressed = false
	return j

## Horizontal camera drag (pixels) since the last call.
func consume_look() -> float:
	var l := _look
	_look = 0.0
	return l

func consume_act() -> bool:
	var a := act_pressed
	act_pressed = false
	return a

func set_act(label: String, ammo: int) -> void:
	if label != act_label or ammo != act_ammo:
		act_label = label
		act_ammo = ammo
		queue_redraw()

# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var items := _items()
	var font := UI.font()
	# joystick: live where the thumb is, ghost at home otherwise
	var joy_active := _joy_index != -1 and not edit_mode
	var origin: Vector2 = _joy_origin if joy_active else items.joy[0]
	var jr := _joy_r()
	var kr: float = KNOB_RADIUS * Game.sizes.joy
	var knob := origin + (_joy_pos - _joy_origin).limit_length(jr) if joy_active else origin
	var a := 1.0 if joy_active or edit_mode else 0.45
	draw_circle(origin, jr + 6, Color(UI.INK, 0.28 * a))
	draw_circle(origin, jr, Color(1, 1, 1, 0.14 * a))
	draw_arc(origin, jr - 3, 0, TAU, 64, Color(1, 1, 1, 0.7 * a), 6.0, true)
	for i in 4:  # direction ticks
		var dir := Vector2.RIGHT.rotated(i * PI * 0.5)
		draw_line(origin + dir * (jr - 22), origin + dir * (jr - 12), Color(1, 1, 1, 0.6 * a), 6.0, true)
	if joy_active or edit_mode:
		draw_style_box(ChunkyStyle.new(UI.WHITE, kr, 7.0), Rect2(knob - Vector2.ONE * kr, Vector2.ONE * kr * 2))
	else:
		draw_circle(knob, kr, Color(1, 1, 1, 0.5))
	# buttons
	var cols := {"jump": UI.YELLOW, "grab": UI.TEAL, "act": UI.CORAL if act_label == "PUSH" else UI.GRAPE}
	var labels := {"jump": "JUMP", "grab": "GRAB", "act": act_label}
	for b in ["jump", "grab", "act"]:
		var c: Vector2 = items[b][0]
		var r: float = items[b][1]
		var held: bool = b in _btn_touch.values() or (b == "grab" and grab_held)
		var st := ChunkyStyle.new(cols[b], r, clampf(r * 0.14, 6.0, 12.0), held)
		var rect := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
		draw_style_box(st, rect)
		var sink := st.depth * 0.8 if held else 0.0
		var body_c := c + Vector2(0, sink - st.depth * 0.5)
		var isz := r * 0.72
		draw_texture_rect(UI.icon(b), Rect2(body_c - Vector2(isz * 0.5, isz * 0.72), Vector2(isz, isz)), false)
		if b == "act" and act_ammo > 0:
			var bc := c + Vector2(r * 0.72, -r * 0.72)
			draw_circle(bc, r * 0.3, UI.INK)
			draw_circle(bc, r * 0.24, UI.YELLOW)
			var astr := str(act_ammo)
			var afs := int(r * 0.32)
			var aw := font.get_string_size(astr, HORIZONTAL_ALIGNMENT_LEFT, -1, afs).x
			draw_string(font, bc + Vector2(-aw * 0.5, afs * 0.36), astr, HORIZONTAL_ALIGNMENT_LEFT, -1, afs, UI.INK)
		var fs := int(r * 0.3)
		var tw := font.get_string_size(labels[b], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tp := body_c + Vector2(-tw * 0.5, isz * 0.28 + fs * 0.75)
		draw_string_outline(font, tp, labels[b], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.4), UI.INK)
		draw_string(font, tp, labels[b], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.WHITE)
	if edit_mode:
		for k in items:
			var c: Vector2 = items[k][0]
			var r: float = items[k][1] + 12.0
			_dashed_ring(c, r, k == selected or k in _drag.values().map(func(v): return v[0]))
			if k == selected:
				var pct := "%d%%" % roundi(Game.sizes[k] * 100.0)
				var fs := 30
				var tw := font.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				# under the control (above it if that's off screen)
				var below := c.y + r + 46 < get_viewport_rect().size.y
				var tp := c + Vector2(-tw * 0.5, r + 42 if below else -r - 14)
				draw_string_outline(font, tp, pct, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, UI.INK)
				draw_string(font, tp, pct, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.YELLOW)

func _dashed_ring(c: Vector2, r: float, active: bool) -> void:
	var n := 24
	var col := UI.YELLOW if active else Color(1, 1, 1, 0.9)
	for i in n:
		var a0 := i * TAU / n
		draw_arc(c, r, a0, a0 + TAU / n * 0.55, 6, col, 5.0, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
