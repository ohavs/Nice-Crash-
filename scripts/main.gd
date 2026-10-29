extends Node3D
## Game scene: builds world, racers (you + bots), brawlers, camera, HUD.
## Countdown, race positions / survival eliminations, results. Crash juice
## lives here.

const CAM_OFFSET := Vector3(0, 5.2, 7.2)
const BOT_COUNT := 7
const BOT_NAMES := ["Eggward", "Sir Toasty", "Donutella", "Burgerella", "Cuppy Cake", "Yolko Ono",
	"Crumbs", "Sunny Side", "Butterfingers", "Big Bun", "Sprinkles", "Toastmalone"]

var player: Player
var racers: Array[Player] = []
var level: Level
var cam: Camera3D
var controls: TouchControls
var hud: CanvasLayer
var crash_label: Label
var _crash_plate: PanelContainer
var _time_plate: PanelContainer
var _pos_plate: PanelContainer
var _count_label: Label
var win_panel: Control

var mode := "race"
var crashes := 0
var bonks := 0
var best_crash := 0
var run_time := 0.0
var running := false
var _over := false
var _finish_order: Array[Player] = []
var _out_order: Array[Player] = []
var _shake := 0.0
var _cam_pos := Vector3.ZERO
var _cam_offset := CAM_OFFSET

func _ready() -> void:
	var course: String = Game.course if Level.COURSES.has(Game.course) else "meadow"
	var info: Dictionary = Level.COURSES[course]
	mode = info.mode
	level = Level.new()
	add_child(level)
	level.build(course)
	level.finished.connect(_on_racer_finished)
	var scenery := Scenery.new()
	scenery.theme = info.theme
	scenery.length = level.length
	add_child(scenery)

	_spawn_racers()
	_spawn_guards()

	cam = Camera3D.new()
	add_child(cam)
	_apply_cam_framing()
	get_viewport().size_changed.connect(_apply_cam_framing)
	_cam_pos = player.global_position + _cam_offset
	cam.global_position = _cam_pos
	cam.look_at(player.global_position)
	_build_hud()
	_countdown()

func _spawn_racers() -> void:
	var skins := Player.SKINS.keys()
	var names := BOT_NAMES.duplicate()
	names.shuffle()
	var slots := level.starts.duplicate()
	# you start in the front row, middle
	var my_slot := 1 if mode == "race" else 0
	for i in BOT_COUNT + 1:
		var p := Player.new()
		var human := i == 0
		p.skin = Game.skin if human else skins[(i + randi()) % skins.size()]
		p.is_human = human
		p.display_name = "YOU" if human else names[i % names.size()]
		p.respawn_enabled = mode == "race"
		add_child(p)
		var slot: Vector3 = slots[my_slot if human else (i if i != my_slot else 0)]
		p.global_position = slot + Vector3.UP * 0.6
		p.checkpoint = slot
		if mode == "survival":
			p._face_dir = (Vector3(0, 0, -8) - slot).normalized() * Vector3(1, 0, 1)
		if human:
			player = p
			p.crashed.connect(_on_crash)
			p.bonked.connect(_on_bonk)
			p.item_changed.connect(_on_item_changed)
		else:
			var b := Bot.new()
			b.level = level
			b.mode = "survive" if mode == "survival" else "race"
			b.skill = randf_range(0.55, 1.0)
			p.add_child(b)
			p.add_name_tag(UI.WHITE)
		p.eliminated.connect(_on_eliminated.bind(p))
		racers.append(p)
	# everyone waits in their toaster / egg cup / plate for GO
	await get_tree().physics_frame
	for p in racers:
		p.hold_in_pod(p.checkpoint + Vector3.UP * 1.0)

func _spawn_guards() -> void:
	for g in level.guards:
		var p := Player.new()
		p.skin = g[2]
		p.is_enemy = true
		p.move_speed = 4.6
		add_child(p)
		p.global_position = g[0]
		p.checkpoint = g[0]
		p.add_name_tag(UI.CORAL)
		var b := Bot.new()
		b.mode = "guard"
		b.level = level
		b.home = g[0]
		b.guard_radius = g[1]
		p.add_child(b)

## Portrait sees less to the sides, so pull the camera up/back and widen it.
func _apply_cam_framing() -> void:
	var s := get_viewport().get_visible_rect().size
	var extra := Vector3(0, 2.0, 1.5) if mode == "survival" else Vector3.ZERO
	if s.x < s.y:
		_cam_offset = Vector3(0, 6.4, 8.2) + extra
		cam.fov = 70
	else:
		_cam_offset = CAM_OFFSET + extra
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
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(top)
	_pos_plate = UI.plate("", UI.YELLOW, 34, "crown")
	top.add_child(_pos_plate)
	_crash_plate = UI.plate("0", UI.CORAL, 30, "bang")
	top.add_child(_crash_plate)
	_time_plate = UI.plate("0.0", UI.TEAL, 30, "timer")
	_time_plate.custom_minimum_size.x = 130
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

	_count_label = UI.label("", 170, UI.YELLOW)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.set_anchors_preset(Control.PRESET_CENTER)
	_count_label.position = Vector2(-300, -260)
	_count_label.size = Vector2(600, 240)
	_count_label.pivot_offset = Vector2(300, 120)
	hud.add_child(_count_label)
	_update_position()

func _countdown() -> void:
	var info: Dictionary = Level.COURSES[level.course]
	_pop_count(info.name, 72, UI.WHITE)
	await get_tree().create_timer(1.3).timeout
	for step in [["3", "vo_ready"], ["2", "vo_set"], ["1", ""]]:
		_pop_count(step[0], 170, UI.YELLOW)
		if step[1] != "":
			Game.play(step[1], 0.0, 0.0)
		Game.play("coin", 0.0, -8.0)
		await get_tree().create_timer(0.75).timeout
	_pop_count("GO!", 190, UI.TEAL)
	Game.play("vo_go", 0.0, 0.0)
	running = true
	for p in racers:
		# a little reaction-time spread so the bots don't all leave as one
		if p.is_human:
			p.launch()
		else:
			get_tree().create_timer(randf_range(0.05, 0.45)).timeout.connect(p.launch)
	await get_tree().create_timer(0.8).timeout
	var tw := create_tween()
	tw.tween_property(_count_label, "modulate:a", 0.0, 0.3)

func _pop_count(text: String, size: int, color: Color) -> void:
	_count_label.text = text
	_count_label.add_theme_font_size_override("font_size", size)
	_count_label.add_theme_color_override("font_color", color)
	_count_label.modulate.a = 1.0
	_count_label.scale = Vector2(0.4, 0.4)
	create_tween().tween_property(_count_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _pause() -> void:
	if get_tree().paused or _over:
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
		Engine.time_scale = 1.0
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
	player.input_dir = basis_y * Vector3(m.x, 0, m.y) if not _over else Vector3.ZERO
	if controls.consume_jump():
		player.jump_requested = true
	if controls.consume_act():
		player.action_requested = true
	player.grab_held = controls.grab_held
	_update_act_button()

func _update_act_button() -> void:
	var label := "PUSH"
	if player.grabbing_player():
		label = "YEET"
	elif player.item != "":
		label = Player.ITEMS[player.item].label
	controls.set_act(label, player.ammo if player.item != "" else 0)

func _process(delta: float) -> void:
	if running and not _over:
		run_time += delta
	UI.plate_label(_time_plate).text = "%.1f" % run_time
	_update_position()
	# smooth follow camera (in survival keep watching after you're out)
	var focus := player.global_position if not player.is_out else Vector3(0, 0, -8)
	var target := focus + _cam_offset
	var real_dt: float = delta / max(Engine.time_scale, 0.01)
	_cam_pos = _cam_pos.lerp(target, 1.0 - exp(-real_dt * 5.0))
	_shake = max(_shake - real_dt * 2.5, 0.0)
	var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * _shake * 0.6
	cam.global_position = _cam_pos + off
	cam.look_at(focus + Vector3(0, 0.6, -2.6))

func _update_position() -> void:
	if _pos_plate == null:
		return
	var l := UI.plate_label(_pos_plate)
	if mode == "survival":
		var alive := racers.filter(func(r): return not r.is_out).size()
		l.text = "%d LEFT" % alive
		return
	l.text = "%d/%d" % [_race_place(player), racers.size()]

## 1-based place: finishers by order, then everyone else by progress (-z).
func _race_place(p: Player) -> int:
	if p in _finish_order:
		return _finish_order.find(p) + 1
	var ahead := _finish_order.size()
	for r in racers:
		if r != p and not r in _finish_order and r.global_position.z < p.global_position.z:
			ahead += 1
	return ahead + 1

# ---------------------------------------------------------------- events

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
	var text: String = words[randi() % words.size()] if power < 14 else "LEGENDARY CRASH!"
	if player.skin == "egg" and player.cracks >= 3:
		text = "EGG-SPLOSION!"
	elif player.skin == "egg":
		text = "CRACK!" if player.cracks == 1 else "CRACK CRACK!"
	_popup("%s\n+%d" % [text, score])

func _on_bonk(victim: Player, _how: String) -> void:
	bonks += 1
	var words := ["BONK!", "GOTCHA!", "YEET!", "SORRY NOT SORRY", "BULLSEYE!"]
	_popup("%s\n%s +100" % [words[randi() % words.size()], victim.display_name], UI.TEAL)
	Input.vibrate_handheld(30)

func _on_item_changed(item: String, _ammo: int) -> void:
	if item != "" and _ammo == Player.ITEMS[item].ammo:
		var names := {"tomato": "TOMATOES!", "cookie": "COOKIE BLASTER!", "melon": "WATERMELON!", "pin": "ROLLING PIN!"}
		_popup(names[item], UI.GRAPE)

func _popup(text: String, color := UI.WHITE) -> void:
	crash_label.text = text
	crash_label.add_theme_color_override("font_color", color)
	crash_label.modulate.a = 1.0
	crash_label.scale = Vector2(0.3, 0.3)
	crash_label.rotation = randf_range(-0.15, 0.15)
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(crash_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.7)
	tw.tween_property(crash_label, "modulate:a", 0.0, 0.3)

func _on_racer_finished(p: Player) -> void:
	_finish_order.append(p)
	if p == player:
		_show_results(_finish_order.size())

func _on_eliminated(p: Player) -> void:
	if mode != "survival" or _over:
		return
	_out_order.append(p)
	Game.play("eliminated", 0.0, -2.0 if p == player else -10.0)
	var alive := racers.filter(func(r): return not r.is_out)
	if p == player:
		_popup("ELIMINATED!", UI.CORAL)
		await get_tree().create_timer(1.6).timeout
		_show_results(alive.size() + 1)
	elif alive.size() == 1 and alive[0] == player:
		_show_results(1)

func _show_results(place: int) -> void:
	if _over:
		return
	_over = true
	running = false
	controls.release_all()
	controls.visible = false
	var won := place == 1
	Game.play("vo_you_win" if won else ("vo_congratulations" if place <= 3 else "vo_game_over"), 0.0, 0.0)
	var titles := {1: "WINNER!", 2: "2ND PLACE!", 3: "3RD PLACE!"}
	var title: String = titles.get(place, "%dTH PLACE" % place)
	if mode == "survival" and not won:
		title = "OUT! #%d" % place
	var m := UI.modal(title, UI.YELLOW if place <= 3 else UI.CORAL)
	var vb: VBoxContainer = m[1]
	var rows := [["crown", "PLACE", "%d / %d" % [place, racers.size()], UI.YELLOW],
		["timer", "TIME", "%.1fs" % run_time, UI.TEAL],
		["bang", "CRASHES", str(crashes), UI.CORAL],
		["act", "BONKS", str(bonks), UI.GRAPE],
		["bang", "BEST CRASH", "+%d" % best_crash, UI.GRAPE]]
	for row in rows:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		var ic := TextureRect.new()
		ic.texture = UI.icon(row[0])
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.custom_minimum_size = Vector2(44, 44)
		hb.add_child(ic)
		var name_l := UI.label(row[1], 30, UI.INK, false)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(name_l)
		hb.add_child(UI.plate(row[2], row[3], 28))
		vb.add_child(hb)
	vb.add_child(UI.button("PLAY AGAIN", UI.YELLOW, 42, func():
		Engine.time_scale = 1.0
		get_tree().reload_current_scene(), "refresh"))
	vb.add_child(UI.button("MENU", UI.TEAL, 34, _to_menu, "home"))
	win_panel = m[0]
	hud.add_child(win_panel)
	UI.pop_in(win_panel.get_meta("card"))
