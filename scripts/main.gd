extends Node3D
## Game scene: builds world, player, camera, HUD. Crash juice lives here.

const CAM_OFFSET := Vector3(0, 5.2, 7.2)

var player: Player
var level: Level
var cam: Camera3D
var controls: TouchControls
var hud: CanvasLayer
var crash_label: Label
var stats_label: Label
var win_panel: Control

var crashes := 0
var best_crash := 0
var run_time := 0.0
var running := true
var _shake := 0.0
var _cam_pos := Vector3.ZERO
var _font: Font

func _ready() -> void:
	_font = load("res://assets/kenney/lilita_one_regular.ttf")
	_build_environment()
	level = Level.new()
	add_child(level)
	level.build_course_1()
	level.finished.connect(_on_finished)

	player = Player.new()
	player.skin = Game.get_meta("skin", "egg")
	add_child(player)
	player.global_position = level.spawn_point
	player.crashed.connect(_on_crash)

	cam = Camera3D.new()
	cam.fov = 60
	add_child(cam)
	_cam_pos = player.global_position + CAM_OFFSET
	cam.global_position = _cam_pos
	cam.look_at(player.global_position)
	_build_hud()

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("5fb6ff")
	sm.sky_horizon_color = Color("cfeeff")
	sm.ground_horizon_color = Color("cfeeff")
	sm.ground_bottom_color = Color("7cc6ff")
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color("cfeeff")
	env.fog_density = 0.006
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.2
	sun.light_color = Color("fff4e0")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	controls = TouchControls.new()
	hud.add_child(controls)

	stats_label = _label(30, HORIZONTAL_ALIGNMENT_LEFT)
	stats_label.position = Vector2(24, 16)
	hud.add_child(stats_label)

	crash_label = _label(72, HORIZONTAL_ALIGNMENT_CENTER)
	crash_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	crash_label.position = Vector2(-300, 90)
	crash_label.size = Vector2(600, 160)
	crash_label.pivot_offset = Vector2(300, 60)
	crash_label.modulate.a = 0
	hud.add_child(crash_label)

	var menu_btn := Button.new()
	menu_btn.text = "II"
	menu_btn.add_theme_font_override("font", _font)
	menu_btn.add_theme_font_size_override("font_size", 30)
	menu_btn.custom_minimum_size = Vector2(70, 70)
	menu_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	menu_btn.position = Vector2(-94, 16)
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	hud.add_child(menu_btn)

func _label(size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.1))
	l.add_theme_constant_override("outline_size", int(size * 0.28))
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

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
	stats_label.text = "CRASHES %d   TIME %.1f" % [crashes, run_time]
	# smooth follow camera
	var target := player.global_position + CAM_OFFSET
	var real_dt: float = delta / max(Engine.time_scale, 0.01)
	_cam_pos = _cam_pos.lerp(target, 1.0 - exp(-real_dt * 5.0))
	_shake = max(_shake - real_dt * 2.5, 0.0)
	var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * _shake * 0.6
	cam.global_position = _cam_pos + off
	cam.look_at(player.global_position + Vector3(0, 0.6, -2.0))

func _on_crash(power: float) -> void:
	crashes += 1
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
	Game.play("coin", 0.0)
	win_panel = PanelContainer.new()
	win_panel.set_anchors_preset(Control.PRESET_CENTER)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	win_panel.add_child(vb)
	var t := _label(64, HORIZONTAL_ALIGNMENT_CENTER)
	t.text = "FINISH!"
	vb.add_child(t)
	var s := _label(32, HORIZONTAL_ALIGNMENT_CENTER)
	s.text = "Time %.1fs\nCrashes %d\nBest crash +%d" % [run_time, crashes, best_crash]
	vb.add_child(s)
	var again := Button.new()
	again.text = "PLAY AGAIN"
	again.add_theme_font_override("font", _font)
	again.add_theme_font_size_override("font_size", 34)
	again.pressed.connect(func(): get_tree().reload_current_scene())
	vb.add_child(again)
	hud.add_child(win_panel)
	win_panel.position = (get_viewport().get_visible_rect().size - win_panel.get_combined_minimum_size()) * 0.5
