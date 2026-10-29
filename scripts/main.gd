extends Node3D
## Game scene: builds world, player, camera, HUD. Crash juice lives here.

const CAM_OFFSET := Vector3(0, 5.2, 7.2)

var player: Player
var level: Level
var cam: Camera3D
var controls: TouchControls
var hud: CanvasLayer
var crash_label: Label
var _crash_plate: PanelContainer
var _time_plate: PanelContainer
var win_panel: Control

var crashes := 0
var best_crash := 0
var run_time := 0.0
var running := true
var _shake := 0.0
var _cam_pos := Vector3.ZERO
var _cam_offset := CAM_OFFSET
var _font: Font

func _ready() -> void:
	_font = UI.font()
	var scenery := Scenery.new()
	scenery.length = 100.0
	add_child(scenery)
	level = Level.new()
	add_child(level)
	level.build_course_1()
	level.finished.connect(_on_finished)

	player = Player.new()
	player.skin = Game.skin
	add_child(player)
	player.global_position = level.spawn_point
	player.crashed.connect(_on_crash)

	cam = Camera3D.new()
	add_child(cam)
	_apply_cam_framing()
	get_viewport().size_changed.connect(_apply_cam_framing)
	_cam_pos = player.global_position + _cam_offset
	cam.global_position = _cam_pos
	cam.look_at(player.global_position)
	_build_hud()

## Portrait sees less to the sides, so pull the camera up/back and widen it.
func _apply_cam_framing() -> void:
	var s := get_viewport().get_visible_rect().size
	if s.x < s.y:
		_cam_offset = Vector3(0, 6.4, 8.2)
		cam.fov = 70
	else:
		_cam_offset = CAM_OFFSET
		cam.fov = 60

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	controls = TouchControls.new()
	hud.add_child(controls)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 20
	top.offset_right = -20
	top.offset_top = 36
	top.add_theme_constant_override("separation", 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(top)
	_crash_plate = UI.plate("0", UI.CORAL, 34, "bang")
	top.add_child(_crash_plate)
	_time_plate = UI.plate("0.0", UI.TEAL, 34, "timer")
	_time_plate.custom_minimum_size.x = 150
	top.add_child(_time_plate)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	top.add_child(UI.round_button("pause", UI.WHITE, 84, _pause))

	crash_label = UI.label("", 76)
	crash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crash_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	crash_label.position = Vector2(-320, 170)
	crash_label.size = Vector2(640, 200)
	crash_label.pivot_offset = Vector2(320, 70)
	crash_label.modulate.a = 0
	hud.add_child(crash_label)

func _pause() -> void:
	if get_tree().paused or not running:
		return
	get_tree().paused = true
	controls.release_all()
	var m := UI.modal("PAUSED", UI.TEAL)
	var overlay: Control = m[0]
	var vb: VBoxContainer = m[1]
	vb.add_child(UI.button("RESUME", UI.YELLOW, 46, func():
		overlay.queue_free()
		get_tree().paused = false, "play"))
	vb.add_child(UI.button("RESTART", UI.TEAL, 38, func():
		get_tree().paused = false
		get_tree().reload_current_scene(), "refresh"))
	vb.add_child(UI.button("MENU", UI.CORAL, 38, _to_menu, "home"))
	hud.add_child(overlay)
	UI.pop_in(overlay.get_meta("card"))

func _to_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _physics_process(_delta: float) -> void:
	controls.read_keyboard()
	var m := controls.move
	# camera-relative input (camera looks along -Z)
	var basis_y := Basis(Vector3.UP, cam.global_rotation.y)
	player.input_dir = basis_y * Vector3(m.x, 0, m.y)
	if controls.consume_jump():
		player.jump_requested = true
	player.grab_held = controls.grab_held

func _process(delta: float) -> void:
	if running:
		run_time += delta
	UI.plate_label(_time_plate).text = "%.1f" % run_time
	# smooth follow camera
	var target := player.global_position + _cam_offset
	var real_dt: float = delta / max(Engine.time_scale, 0.01)
	_cam_pos = _cam_pos.lerp(target, 1.0 - exp(-real_dt * 5.0))
	_shake = max(_shake - real_dt * 2.5, 0.0)
	var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * _shake * 0.6
	cam.global_position = _cam_pos + off
	cam.look_at(player.global_position + Vector3(0, 0.6, -2.6))

func _on_crash(power: float) -> void:
	crashes += 1
	var cl := UI.plate_label(_crash_plate)
	cl.text = str(crashes)
	_crash_plate.pivot_offset = _crash_plate.size * 0.5
	_crash_plate.scale = Vector2(1.35, 1.35)
	_crash_plate.create_tween().set_ignore_time_scale(true).tween_property(_crash_plate, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var score := int(clampf(power, 0, 40) * 25.0)
	best_crash = max(best_crash, score)
	_shake = clampf(power / 14.0, 0.4, 1.0)
	Game.slowmo(0.3, 0.45)
	Input.vibrate_handheld(60)
	var words := ["NICE CRASH!", "OUCH!", "SPLAT!", "BONK!", "WHOOPS!", "EPIC FAIL!"]
	crash_label.text = "%s\n+%d" % [words[randi() % words.size()] if power < 14 else "LEGENDARY CRASH!", score]
	crash_label.modulate.a = 1.0
	crash_label.scale = Vector2(0.3, 0.3)
	crash_label.rotation = randf_range(-0.15, 0.15)
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(crash_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.7)
	tw.tween_property(crash_label, "modulate:a", 0.0, 0.3)

func _on_finished() -> void:
	running = false
	controls.release_all()
	controls.visible = false
	Game.play("coin", 0.0)
	var m := UI.modal("FINISH!", UI.YELLOW)
	var vb: VBoxContainer = m[1]
	for row in [["timer", "TIME", "%.1fs" % run_time, UI.TEAL], ["bang", "CRASHES", str(crashes), UI.CORAL], ["bang", "BEST CRASH", "+%d" % best_crash, UI.GRAPE]]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		var ic := TextureRect.new()
		ic.texture = UI.icon(row[0])
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.custom_minimum_size = Vector2(48, 48)
		hb.add_child(ic)
		var name_l := UI.label(row[1], 34, UI.INK, false)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(name_l)
		hb.add_child(UI.plate(row[2], row[3], 32))
		vb.add_child(hb)
	vb.add_child(UI.button("PLAY AGAIN", UI.YELLOW, 44, func(): get_tree().reload_current_scene(), "refresh"))
	vb.add_child(UI.button("MENU", UI.TEAL, 36, _to_menu, "home"))
	win_panel = m[0]
	hud.add_child(win_panel)
	UI.pop_in(win_panel.get_meta("card"))
