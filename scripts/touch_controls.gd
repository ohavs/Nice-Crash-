class_name TouchControls
extends Control
## Floating joystick on the left half, JUMP + GRAB buttons on the right.
## Keyboard fallback for PC testing: WASD/arrows, Space, E/Shift.

var move := Vector2.ZERO
var jump_pressed := false
var grab_held := false

var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _kb := false
var _btn_touch := {}   # touch index -> "jump"/"grab"
const JOY_RADIUS := 110.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _buttons() -> Dictionary:
	var s := get_viewport_rect().size
	var r := clampf(s.y * 0.11, 55.0, 95.0)
	return {
		"jump": [Vector2(s.x - r * 1.5, s.y - r * 1.6), r],
		"grab": [Vector2(s.x - r * 3.7, s.y - r * 1.0), r * 0.8],
	}

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			for b in _buttons():
				var d: Array = _buttons()[b]
				if event.position.distance_to(d[0]) < d[1] * 1.25:
					_btn_touch[event.index] = b
					if b == "jump":
						jump_pressed = true
					else:
						grab_held = true
					queue_redraw()
					return
			if event.position.x < get_viewport_rect().size.x * 0.5 and _joy_index == -1:
				_joy_index = event.index
				_joy_origin = event.position
				_joy_pos = event.position
		else:
			if event.index == _joy_index:
				_joy_index = -1
				move = Vector2.ZERO
			if _btn_touch.has(event.index):
				if _btn_touch[event.index] == "grab":
					grab_held = false
				_btn_touch.erase(event.index)
		queue_redraw()
	elif event is InputEventScreenDrag and event.index == _joy_index:
		_joy_pos = event.position
		var d: Vector2 = _joy_pos - _joy_origin
		if d.length() > JOY_RADIUS:
			_joy_origin = _joy_pos - d.normalized() * JOY_RADIUS  # follow finger
		move = (_joy_pos - _joy_origin) / JOY_RADIUS
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

func consume_jump() -> bool:
	var j := jump_pressed
	jump_pressed = false
	return j

func _draw() -> void:
	if _joy_index != -1:
		draw_circle(_joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.15))
		draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.5), 4.0, true)
		var knob := _joy_origin + (_joy_pos - _joy_origin).limit_length(JOY_RADIUS)
		draw_circle(knob, 44, Color(1, 1, 1, 0.75))
	var font := ThemeDB.fallback_font
	var cols := {"jump": Color("ffd23f"), "grab": Color("4ecdc4")}
	var labels := {"jump": "JUMP", "grab": "GRAB"}
	for b in _buttons():
		var d: Array = _buttons()[b]
		var held: bool = b in _btn_touch.values()
		draw_circle(d[0] + Vector2(0, 6), d[1], Color(0, 0, 0, 0.35))
		draw_circle(d[0] + (Vector2(0, 4) if held else Vector2.ZERO), d[1], cols[b].darkened(0.2 if held else 0.0))
		draw_arc(d[0], d[1], 0, TAU, 48, Color(0.08, 0.06, 0.1), 5.0, true)
		var fs := int(d[1] * 0.38)
		var tw := font.get_string_size(labels[b], HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(font, d[0] + Vector2(-tw * 0.5, fs * 0.35), labels[b], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.08, 0.06, 0.1))

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
