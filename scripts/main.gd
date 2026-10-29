extends Node3D
## Game scene for every mode:
##   adventure (open world) - roam a zone (adventure.gd) with bot buddies or
##               friends, three missions = three stars, hearts, camps
##   party     - minigames, everyone against everyone; a "show" plays several
##               rounds and keeps a leaderboard (round points by place)
## Offline or networked (Net.active()): then every peer drives its own
## player, streams it to the others (puppets there) and the host runs bots,
## skeletons, cannons, scores and round ends.
## Builds the level, players, camera, HUD, countdown, results, crash juice.

const BOT_NAMES := ["Eggward", "Sir Toasty", "Donutella", "Burgerella", "Cuppy Cake", "Yolko Ono",
	"Crumbs", "Sunny Side", "Butterfingers", "Big Bun", "Sprinkles", "Toastmalone"]
## Party show points for 1st, 2nd, 3rd...
const ROUND_POINTS := [10, 8, 6, 5, 4, 3, 2, 1]
const MAX_HP := 5
const SEND_RATE := 1.0 / 15.0

var player: Player
var racers: Array[Player] = []
var level: Level
var world: Adventure
var cam: Camera3D
var controls: TouchControls
var hud: CanvasLayer
var crash_label: Label
var _crash_plate: PanelContainer
var _time_plate: PanelContainer
var _pos_plate: PanelContainer
var _coin_plate: PanelContainer
var _count_label: Label
var _hearts: HBoxContainer
var _mission_box: VBoxContainer
var _compass: Control
var _compass_arrow: TextureRect
var _compass_label: Label
var win_panel: Control

var play_mode := "adventure"
## world | survival | koth | brawl
var mode := "world"
var net := false
var crashes := 0
var bonks := 0
var kos := 0
var coins := 0
var best_crash := 0
var run_time := 0.0
var running := false
var _over := false
var _out_order: Array[Player] = []
var _score := {}  # Player -> points (koth seconds / brawl bonks)
var _by_id := {}  # net id -> Player
var _loaded := {}
var _send_t := 0.0
var _enemy_t := 0.0
var _score_t := 0.0
var _started := false
var _shake := 0.0
var _cam_pos := Vector3.ZERO
var _cam_yaw := 0.0
var _look_yaw := 0.0
var _cam_offset := Vector3(0, 6.4, 8.2)
var _aim_marker: Node3D
var _aim_ring: MeshInstance3D
var _aim_arrow: MeshInstance3D
var _aim_last: Node3D
var _aim_t := 0.0

func _ready() -> void:
	net = Net.active()
	play_mode = Game.play_mode
	var lid := Game.level_id
	var pid := Game.party_id
	if net:
		play_mode = Net.game.mode
		lid = Net.game.id
		pid = Net.game.id
	if play_mode == "party":
		level = Party.new()
		add_child(level)
		level.build(pid)
	else:
		play_mode = "adventure"
		world = Adventure.new()
		level = world
		add_child(level)
		world.build(lid)
		world.mission_changed.connect(_on_mission)
		world.all_done.connect(_zone_complete)
		for e in world.enemies:
			e.puppet = net and not Net.is_host()
	level.remote_hazards = net and not Net.is_host()
	mode = level.mode
	level.coin_collected.connect(_on_coin)
	level.coin_taken.connect(func(i): _net_send("coin", [i]))
	level.box_taken.connect(func(i): _net_send("box", [i]))
	var scenery := Scenery.new()
	scenery.theme = level.theme
	scenery.area = level.bounds
	scenery.backdrop = world == null
	add_child(scenery)

	_spawn_racers()
	if not net:
		_spawn_guards()

	cam = Camera3D.new()
	cam.far = 260.0
	add_child(cam)
	_apply_cam_framing()
	get_viewport().size_changed.connect(_apply_cam_framing)
	_cam_yaw = _target_yaw(0.0)
	_cam_pos = _cam_target()
	cam.global_position = _cam_pos
	cam.look_at(player.global_position)
	_build_hud()
	_build_aim_marker()
	if net:
		Net.message.connect(_on_net)
		Net.closed.connect(_on_net_closed)
		Net.to_host("loaded")
		if Net.is_host():
			# don't wait forever for a slow phone
			get_tree().create_timer(8.0).timeout.connect(_host_go)
	else:
		_begin()

func _bot_count() -> int:
	if play_mode == "party":
		return clampi(Game.party_bots, 1, 4)
	return clampi(Game.bots, 0, 4)

## Who plays: [{id, name, skin, local, bot}] (local = driven on this phone).
func _roster() -> Array:
	var out := []
	var skins := Player.SKINS.keys()
	if net:
		for r in Net.game.roster:
			out.append({"id": "%d:0" % r.peer, "name": r.name, "skin": r.skin, "local": int(r.peer) == Net.my_id, "bot": false})
		var bi := 0
		for b in Net.game.get("bots", []):
			out.append({"id": "%d:b%d" % [Net.host_id, bi], "name": b.name, "skin": b.skin, "local": Net.is_host(), "bot": true})
			bi += 1
		return out
	out.append({"id": "", "name": "YOU", "skin": Game.skin, "local": true, "bot": false})
	var names := BOT_NAMES.duplicate()
	names.shuffle()
	for i in _bot_count():
		out.append({"id": "", "name": names[i % names.size()], "skin": skins[(i + 1 + randi()) % skins.size()], "local": true, "bot": true})
	return out

func _spawn_racers() -> void:
	var slots := level.starts.duplicate()
	var roster := _roster()
	var n := roster.size()
	# my own player goes first so `player` is set before the others look for a buddy
	roster.sort_custom(func(a, b): return a.local and not a.bot and not (b.local and not b.bot))
	var order: Array[int] = []
	if play_mode == "adventure":
		order.assign([2, 1, 3, 0, 4])
	else:
		var step := maxi(8 / maxi(n, 1), 1)
		for i in n:
			order.append((i * step) % slots.size())
	for i in n:
		var r: Dictionary = roster[i]
		var p := Player.new()
		var human: bool = r.local and not r.bot
		p.skin = r.skin
		p.is_human = human
		p.display_name = "YOU" if human and not net else r.name
		p.net_id = r.id
		p.puppet = not r.local
		p.respawn_enabled = mode != "survival"
		p.kill_y = level.kill_y
		p.team = 0 if play_mode == "adventure" else -1
		if play_mode == "adventure":
			p.max_hp = MAX_HP
			p.hp = MAX_HP
		var slot: Vector3 = slots[order[i % order.size()] % slots.size()]
		if i >= order.size():
			slot += Vector3(1.0, 0, 1.2) * (i / order.size())
		p.position = slot + Vector3.UP * 0.6
		add_child(p)
		p.global_position = slot + Vector3.UP * 0.6
		p.checkpoint = slot
		if play_mode == "party":
			var to_mid := level.center - slot
			to_mid.y = 0
			p._face_dir = to_mid.normalized() if to_mid.length() > 0.1 else Vector3.FORWARD
		else:
			p._face_dir = level.start_dir
		if human:
			player = p
			p.crashed.connect(_on_crash)
			p.item_changed.connect(_on_item_changed)
			p.hp_changed.connect(func(_hp): _update_hearts())
			p.knocked_out.connect(_on_ko)
		else:
			if r.bot and r.local:
				var b := Bot.new()
				b.level = level
				match mode:
					"survival":
						b.mode = "survive"
					"koth", "brawl":
						b.mode = mode
					_:
						b.mode = "follow"
				b.skill = randf_range(0.55, 1.0)
				p.add_child(b)
			p.add_name_tag(UI.TEAL if play_mode == "adventure" else UI.WHITE)
		if r.local:
			p.bonked.connect(_on_bonk.bind(p))
			p.eliminated.connect(_on_eliminated.bind(p))
		_score[p] = 0.0
		if r.id != "":
			_by_id[r.id] = p
		racers.append(p)
	for r in racers:
		for c in r.get_children():
			if c is Bot:
				(c as Bot).buddy = player
	# everyone waits in their toaster / egg cup / plate for GO
	await get_tree().physics_frame
	for p in racers:
		if not p.puppet:
			p.hold_in_pod(p.checkpoint + Vector3.UP * 1.0)

func _spawn_guards() -> void:
	for g in level.guards:
		var p := Player.new()
		p.skin = g[2]
		p.is_enemy = true
		p.move_speed = 5.6
		p.kill_y = level.kill_y
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
	var extra := Vector3.ZERO
	if play_mode == "party":
		extra = Vector3(0, 3.2, 2.6) if mode == "survival" else Vector3(0, 2.6, 2.0)
	elif world:
		extra = Vector3(0, -0.6, 0.6)
	if s.x < s.y:
		_cam_offset = Vector3(0, 6.4, 8.2) + extra
		cam.fov = 70
	else:
		_cam_offset = Vector3(0, 5.2, 7.2) + extra
		cam.fov = 60

# ---------------------------------------------------------------- HUD

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
	if world:
		_hearts = HBoxContainer.new()
		_hearts.add_theme_constant_override("separation", 2)
		_hearts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(_hearts)
		_update_hearts()
		_coin_plate = UI.plate("0", UI.YELLOW, 26, "coin")
		_coin_plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(_coin_plate)
	else:
		_pos_plate = UI.plate("", UI.YELLOW, 32, "crown")
		top.add_child(_pos_plate)
		_crash_plate = UI.plate("0", UI.CORAL, 28, "bang")
		top.add_child(_crash_plate)
		_time_plate = UI.plate("0.0", UI.TEAL, 28, "timer")
		_time_plate.custom_minimum_size.x = 120
		top.add_child(_time_plate)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	top.add_child(UI.round_button("pause", UI.WHITE, 84, _pause))
	if world:
		_build_missions()
	elif not Game.show.is_empty() or (net and Net.game.get("rounds", 1) > 1):
		var r := UI.plate(_round_text(), UI.GRAPE, 24)
		r.set_anchors_preset(Control.PRESET_TOP_WIDE)
		r.offset_top = 120
		r.offset_left = 240
		r.offset_right = -240
		hud.add_child(r)

	crash_label = UI.label("", 76)
	crash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crash_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	crash_label.position = Vector2(-320, 230)
	crash_label.size = Vector2(640, 200)
	crash_label.pivot_offset = Vector2(320, 70)
	crash_label.modulate.a = 0
	crash_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(crash_label)

	_count_label = UI.label("", 170, UI.YELLOW)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.set_anchors_preset(Control.PRESET_CENTER)
	_count_label.position = Vector2(-320, -260)
	_count_label.size = Vector2(640, 240)
	_count_label.pivot_offset = Vector2(320, 120)
	_count_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(_count_label)
	_update_position()

func _round_text() -> String:
	if net:
		return "ROUND %d / %d" % [Net.game.get("round", 1), Net.game.get("rounds", 1)]
	return "ROUND %d / %d" % [Game.show.get("round", 1), Game.show.get("rounds", 1)]

func _update_hearts() -> void:
	if _hearts == null:
		return
	for c in _hearts.get_children():
		c.queue_free()
	for i in MAX_HP:
		var tr := TextureRect.new()
		tr.texture = UI.icon("heart" if i < player.hp else "heart_empty")
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(46, 46)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hearts.add_child(tr)
	if player.hp < MAX_HP:
		_hearts.pivot_offset = Vector2(0, 23)
		_hearts.scale = Vector2(1.2, 1.2)
		_hearts.create_tween().tween_property(_hearts, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)

## Mission list (top left) and the compass pointing at the nearest thing
## still to do.
func _build_missions() -> void:
	_mission_box = VBoxContainer.new()
	_mission_box.position = Vector2(20, 112)
	_mission_box.add_theme_constant_override("separation", 6)
	_mission_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_mission_box)
	_refresh_missions()
	_compass = Control.new()
	_compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_compass.position = Vector2(-60, 110)
	_compass.size = Vector2(120, 120)
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_compass)
	var ring := TextureRect.new()
	ring.texture = UI.icon("target")
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.size = Vector2(70, 70)
	ring.position = Vector2(25, 0)
	ring.modulate = Color(1, 1, 1, 0.35)
	_compass.add_child(ring)
	_compass_arrow = TextureRect.new()
	_compass_arrow.texture = UI.icon("arrow")
	_compass_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_compass_arrow.size = Vector2(54, 54)
	_compass_arrow.position = Vector2(33, 8)
	_compass_arrow.pivot_offset = Vector2(27, 27)
	_compass_arrow.modulate = UI.YELLOW
	_compass.add_child(_compass_arrow)
	_compass_label = UI.label("", 24)
	_compass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compass_label.position = Vector2(0, 70)
	_compass_label.size = Vector2(120, 30)
	_compass.add_child(_compass_label)

func _refresh_missions() -> void:
	if _mission_box == null:
		return
	for c in _mission_box.get_children():
		c.queue_free()
	for m in world.missions:
		var text: String = "%s  %d/%d" % [m.title, m.got, m.need] if m.need > 1 else m.title
		var pl := UI.plate(text, UI.TEAL if m.done else Color("3b3350"), 20, "checkmark" if m.done else m.icon)
		pl.modulate.a = 0.75 if m.done else 0.95
		_mission_box.add_child(pl)

func _update_compass() -> void:
	if _compass == null:
		return
	var t := world.next_target(player.global_position)
	_compass.visible = not t.is_empty() and not _over
	if t.is_empty():
		return
	var to: Vector3 = t[0] - player.global_position
	var d := Vector2(to.x, to.z).length()
	# angle relative to where the camera looks
	var a := atan2(-to.x, -to.z) - cam.global_rotation.y
	_compass_arrow.rotation = -a
	_compass_label.text = "%dm" % roundi(d)

# ---------------------------------------------------------------- start

func _title() -> String:
	if play_mode == "party":
		return Party.info(level.id).name
	return Adventure.info(level.id).name

func _begin() -> void:
	if _started:
		return
	_started = true
	level._t = 0.0
	if world:
		_intro()
	else:
		_countdown()

## Host: everyone has loaded (or it took too long): GO.
func _host_go() -> void:
	if _started or not Net.is_host():
		return
	Net.to_all("go")

func _intro() -> void:
	_pop_count(_title(), 72, UI.WHITE)
	Game.play("vo_ready", 0.0, -2.0)
	await get_tree().create_timer(1.2).timeout
	running = true
	for p in racers:
		if p.puppet:
			continue
		if p.is_human:
			p.launch()
		else:
			get_tree().create_timer(randf_range(0.1, 0.6)).timeout.connect(p.launch)
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(_count_label, "modulate:a", 0.0, 0.4)
	_popup("%d MISSIONS!" % world.missions.size(), UI.YELLOW)

func _countdown() -> void:
	_pop_count(_title(), 64, UI.WHITE)
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
	level._t = 0.0
	for p in racers:
		if p.puppet:
			continue
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

# ---------------------------------------------------------------- pause

func _pause() -> void:
	if get_tree().paused or _over:
		return
	if not net:
		get_tree().paused = true
	controls.release_all()
	var m := UI.modal("PAUSED" if not net else "MENU", UI.TEAL)
	var overlay: Control = m[0]
	var vb: VBoxContainer = m[1]
	vb.add_child(UI.button("RESUME", UI.YELLOW, 46, func():
		overlay.queue_free()
		get_tree().paused = false, "play"))
	if net:
		vb.add_child(UI.button("LEAVE GAME", UI.CORAL, 38, _leave_net, "home"))
	else:
		vb.add_child(UI.button("RESTART", UI.TEAL, 38, _restart, "refresh"))
		if play_mode == "adventure":
			vb.add_child(UI.button("WORLD MAP", UI.GRAPE, 38, _to_world, "map"))
		vb.add_child(UI.button("MENU", UI.CORAL, 38, _to_menu, "home"))
	hud.add_child(overlay)
	UI.pop_in(overlay.get_meta("card"))

func _restart() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

func _to_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	Game.open_party = play_mode == "party"
	Game.show = {}
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _to_world() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/world_map.tscn")

func _leave_net() -> void:
	Net.leave()
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _to_lobby() -> void:
	Engine.time_scale = 1.0
	Net.game = {}
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

# ---------------------------------------------------------------- frame

func _physics_process(_delta: float) -> void:
	controls.read_keyboard()
	var m := controls.move
	# camera-relative input
	var basis_y := Basis(Vector3.UP, cam.global_rotation.y)
	player.input_dir = basis_y * Vector3(m.x, 0, m.y) if not _over else Vector3.ZERO
	if controls.consume_jump():
		player.jump_requested = true
	if controls.consume_act():
		player.action_requested = true
	player.grab_held = controls.grab_held
	controls.set_grab_shown(_grab_useful())
	_update_act_button()

## GRAB only shows up when there's something to grab: another player close
## by, or a crate. (Holding on keeps it up until you let go.)
func _grab_useful() -> bool:
	if player.grab_held or player.grabbing_player():
		return true
	var pos := player.global_position
	for o in get_tree().get_nodes_in_group("players"):
		var p := o as Player
		if p != player and not p.is_out and not p.is_held() and p.global_position.distance_to(pos) < 3.5:
			return true
	for o in get_tree().get_nodes_in_group("grabbable"):
		if (o as Node3D).global_position.distance_to(pos) < 3.0:
			return true
	return false

func _update_act_button() -> void:
	var label := "PUSH"
	if player.grabbing_player():
		label = "YEET"
	elif player.item != "":
		label = Player.ITEMS[player.item].label
	elif world:
		label = "HIT"
	controls.set_act(label, player.ammo if player.item != "" else 0)

func _process(delta: float) -> void:
	var real_dt: float = delta / max(Engine.time_scale, 0.01)
	if running and not _over:
		run_time += delta
		if not net or Net.is_host():
			_score_tick(delta)
	if _time_plate:
		var timed := mode == "koth" or mode == "brawl"
		UI.plate_label(_time_plate).text = "%d" % ceili(maxf(Party.ROUND_TIME - run_time, 0.0)) if timed else "%.1f" % run_time
	_update_position()
	if net:
		_net_tick(delta)
	# camera: open world follows where you run; party looks at the arena;
	# drag the top half of the screen to look around
	var look := controls.consume_look()
	if world:
		_look_yaw = 0.0
		if look != 0.0:
			_world_yaw = wrapf(_world_yaw - look * 0.006, -PI, PI)
			_cam_yaw = _world_yaw
	elif look != 0.0:
		_look_yaw = wrapf(_look_yaw - look * 0.006, -PI, PI)
	elif player.input_dir.length() > 0.3:
		_look_yaw = lerpf(_look_yaw, 0.0, 1.0 - exp(-real_dt * 0.6))
	_cam_yaw = lerp_angle(_cam_yaw, _target_yaw(real_dt), 1.0 - exp(-real_dt * 2.2))
	_cam_pos = _cam_pos.lerp(_cam_target(), 1.0 - exp(-real_dt * 5.0))
	if world:
		var gy := world.terrain.height_at(_cam_pos.x, _cam_pos.z) + 1.4
		_cam_pos.y = maxf(_cam_pos.y, gy)
	_shake = max(_shake - real_dt * 2.5, 0.0)
	var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * _shake * 0.6
	cam.global_position = _cam_pos + off
	var yb := Basis(Vector3.UP, _cam_yaw + _look_yaw)
	cam.look_at(_focus() + yb * Vector3(0, 0.6, -2.6))
	_update_aim_marker(real_dt)
	if world:
		_update_compass()

var _world_yaw := 0.0

func _target_yaw(dt: float) -> float:
	if play_mode == "party":
		return 0.0
	if dt == 0.0:
		var h := level.start_dir
		_world_yaw = atan2(-h.x, -h.z)
		return _world_yaw
	# swing round behind you while you run away from the camera, never when
	# running at it (that would spin the view)
	var v := player.linear_velocity
	v.y = 0
	if v.length() > 2.5 and player.input_dir.length() > 0.3 and not player.is_crashed:
		var want := atan2(-v.x, -v.z)
		if absf(angle_difference(_world_yaw, want)) < 2.0:
			_world_yaw = lerp_angle(_world_yaw, want, 1.0 - exp(-dt * 0.9))
	return _world_yaw

## Lock-on marker for throws: a ring at the target's feet and an arrow over
## its head (seen through walls), popping in when the lock changes.
func _build_aim_marker() -> void:
	_aim_marker = Node3D.new()
	_aim_marker.visible = false
	add_child(_aim_marker)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = 3
	m.albedo_color = Color(UI.CORAL, 0.85)
	_aim_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.5
	tm.outer_radius = 0.62
	tm.rings = 32
	tm.ring_segments = 6
	_aim_ring.mesh = tm
	_aim_ring.scale = Vector3(1, 0.3, 1)
	_aim_ring.material_override = m
	_aim_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_marker.add_child(_aim_ring)
	_aim_arrow = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.2
	cm.bottom_radius = 0.0
	cm.height = 0.32
	cm.radial_segments = 4
	_aim_arrow.mesh = cm
	_aim_arrow.material_override = m
	_aim_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_marker.add_child(_aim_arrow)

func _update_aim_marker(real_dt: float) -> void:
	var t := player.aim_target
	if t == null or not is_instance_valid(t) or _over:
		_aim_marker.visible = false
		_aim_last = null
		return
	if t != _aim_last:
		_aim_last = t
		_aim_t = 0.0
		Game.play("pop", 0.05, -16.0)
	_aim_t += real_dt
	_aim_marker.visible = true
	var foot := 0.0 if t is Player else 0.55
	_aim_marker.global_position = t.global_position + Vector3.UP * foot
	# pops in big and settles, then breathes gently
	var pop := 1.0 + maxf(0.0, 0.35 - _aim_t) * 2.0
	var s := pop * (1.0 + sin(_aim_t * 7.0) * 0.06)
	_aim_ring.position.y = -0.55
	_aim_ring.scale = Vector3(s, 0.3, s)
	_aim_ring.rotation.y = _aim_t * 1.5
	_aim_arrow.position.y = (1.35 if t is Player else 1.9) + absf(sin(_aim_t * 5.0)) * 0.15
	_aim_arrow.rotation.y = _aim_t * 3.0
	_aim_arrow.scale = Vector3.ONE * pop

func _focus() -> Vector3:
	if player.is_out:
		return level.center
	return player.global_position

func _cam_target() -> Vector3:
	return _focus() + Basis(Vector3.UP, _cam_yaw + _look_yaw) * _cam_offset

func _score_tick(delta: float) -> void:
	if mode == "koth":
		var party := level as Party
		for p in racers:
			if not p.is_crashed and not p.is_out and party.on_hill(p.global_position):
				_score[p] += delta
	if (mode == "koth" or mode == "brawl") and run_time >= Party.ROUND_TIME:
		_end_round()

func _update_position() -> void:
	if _pos_plate == null:
		return
	var l := UI.plate_label(_pos_plate)
	match mode:
		"survival":
			l.text = "%d LEFT" % racers.filter(func(r): return not r.is_out).size()
		"koth", "brawl":
			l.text = "%d  #%d" % [int(_score.get(player, 0)), _rank(player)]

func _rank(p: Player) -> int:
	var r := 1
	for o in racers:
		if o != p and _score.get(o, 0) > _score.get(p, 0):
			r += 1
	return r

# ---------------------------------------------------------------- events

func _on_crash(power: float) -> void:
	crashes += 1
	if _crash_plate:
		UI.plate_label(_crash_plate).text = str(crashes)
		_crash_plate.pivot_offset = _crash_plate.size * 0.5
		_crash_plate.scale = Vector2(1.35, 1.35)
		_crash_plate.create_tween().set_ignore_time_scale(true).tween_property(_crash_plate, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var score := int(clampf(power, 0, 40) * 25.0)
	best_crash = max(best_crash, score)
	_shake = clampf(power / 14.0, 0.4, 1.0)
	if not net:
		Game.slowmo(0.3, 0.45)
	Input.vibrate_handheld(60)
	var words := ["NICE CRASH!", "OUCH!", "SPLAT!", "BONK!", "WHOOPS!", "EPIC FAIL!"]
	var text: String = words[randi() % words.size()] if power < 14 else "LEGENDARY CRASH!"
	if player.skin == "egg" and player.cracks >= 3:
		text = "EGG-SPLOSION!"
	elif player.skin == "egg":
		text = "CRACK!" if player.cracks == 1 else "CRACK CRACK!"
	_popup("%s\n+%d" % [text, score])

func _on_ko() -> void:
	kos += 1
	_shake = 1.0
	_popup("KNOCKED OUT!\nBack to camp...", UI.CORAL)

func _on_bonk(victim: Player, _how: String, by: Player) -> void:
	if not running or _over:
		return
	# `by` hit one of our players (we own the victim): the host keeps score
	if mode == "brawl" and not victim.is_enemy:
		if net:
			Net.to_host("bonk", [victim.net_id, by.net_id])
		else:
			_score[by] += 1
	if by != player:
		return
	_my_bonk(victim)

func _my_bonk(victim: Player) -> void:
	bonks += 1
	var words := ["BONK!", "GOTCHA!", "YEET!", "SORRY NOT SORRY", "BULLSEYE!"]
	_popup("%s\n%s +100" % [words[randi() % words.size()], victim.display_name], UI.TEAL)
	Input.vibrate_handheld(30)

func _on_coin(_p: Player) -> void:
	_add_coin()

func _add_coin() -> void:
	coins += 1
	if _coin_plate:
		UI.plate_label(_coin_plate).text = str(coins)
		_coin_plate.pivot_offset = _coin_plate.size * 0.5
		_coin_plate.scale = Vector2(1.25, 1.25)
		_coin_plate.create_tween().tween_property(_coin_plate, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_item_changed(item: String, _ammo: int) -> void:
	if item != "" and _ammo == Player.ITEMS[item].ammo:
		var names := {"tomato": "TOMATOES!", "cookie": "COOKIE BLASTER!", "melon": "WATERMELON!", "pin": "ROLLING PIN!"}
		_popup(names[item], UI.GRAPE)

func _popup(text: String, color := UI.WHITE) -> void:
	crash_label.text = text
	crash_label.add_theme_color_override("font_color", color)
	crash_label.modulate.a = 1.0
	crash_label.scale = Vector2(0.3, 0.3)
	crash_label.rotation = randf_range(-0.12, 0.12)
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(crash_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.8)
	tw.tween_property(crash_label, "modulate:a", 0.0, 0.3)

func _on_mission(i: int) -> void:
	_refresh_missions()
	var m: Dictionary = world.missions[i]
	if net and Net.is_host():
		Net.send(0, "mp", [i, m.got])
	if m.done:
		Game.play("vo_congratulations" if world.stars() < world.missions.size() else "vo_you_win", 0.0, 0.0)
		_popup("MISSION COMPLETE!\n%s" % m.title.to_upper(), UI.YELLOW)
		Game.complete_level(level.id, world.stars())

func _on_eliminated(p: Player) -> void:
	if mode != "survival" or _over:
		return
	Game.play("eliminated", 0.0, -2.0 if p == player else -10.0)
	if p == player:
		_popup("ELIMINATED!", UI.CORAL)
	if net:
		Net.to_all("out", [p.net_id])
	else:
		_mark_out(p)

## Host / offline: someone is out of a survival round.
func _mark_out(p: Player) -> void:
	if p in _out_order:
		return
	_out_order.append(p)
	var alive := racers.filter(func(r): return not r.is_out and not r in _out_order)
	if alive.size() <= 1:
		get_tree().create_timer(1.2).timeout.connect(_end_round)
	elif not net and p == player:
		# you're out: watch a moment, then see the standings
		get_tree().create_timer(1.6).timeout.connect(_end_round)

# ---------------------------------------------------------------- network

func _net_send(type: String, data) -> void:
	if net:
		Net.send(0, type, data)

func _net_tick(delta: float) -> void:
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = SEND_RATE
		var states := []
		for p in racers:
			if not p.puppet and p.net_id != "" and is_instance_valid(p):
				states.append(p.net_state())
		if not states.is_empty():
			Net.send(0, "st", states)
	if not Net.is_host():
		return
	if world:
		_enemy_t -= delta
		if _enemy_t <= 0.0:
			_enemy_t = 0.1
			var es := []
			for e in world.enemies:
				if is_instance_valid(e) and not e.is_dead():
					es.append([e.net_id] + e.net_state())
			if not es.is_empty():
				Net.send(0, "es", es)
	elif mode == "koth" or mode == "brawl":
		_score_t -= delta
		if _score_t <= 0.0:
			_score_t = 0.5
			var sc := {}
			for p in racers:
				sc[p.net_id] = _score[p]
			Net.send(0, "score", sc)

func _on_net(from: int, type: String, data) -> void:
	match type:
		"loaded":
			_loaded[from] = true
			if Net.is_host() and Net.peers.keys().all(func(k): return _loaded.has(k)):
				_host_go()
		"go":
			_begin()
		"st":
			for st in data:
				var p: Player = _by_id.get(st[0])
				if p and is_instance_valid(p) and p.puppet:
					p.net_apply(st)
		"es":
			if world:
				for st in data:
					var i: int = st[0]
					if i < world.enemies.size() and is_instance_valid(world.enemies[i]):
						world.enemies[i].net_apply(st.slice(1))
		"edie":
			if world and data[0] < world.enemies.size() and is_instance_valid(world.enemies[data[0]]):
				world.enemies[data[0]].net_die()
		"ehit":
			if world and Net.is_host() and data[0] < world.enemies.size() and is_instance_valid(world.enemies[data[0]]):
				world.enemies[data[0]].net_hit(data[1], data[2], _by_id.get(data[3]))
		"hit", "push":
			var p: Player = _by_id.get(data[0])
			if p and not p.puppet:
				if type == "hit":
					p.hit(data[1], _by_id.get(data[2]))
				else:
					p.push(data[1], _by_id.get(data[2]))
		"fire":
			Projectile.fire(level, data[0], data[1], data[2], _by_id.get(data[3]), true)
		"w_egg":
			world.remote_egg(data[0])
		"w_light":
			world.remote_light(data[0])
		"w_reach":
			world.remote_reach(data[0])
		"mp":
			world.set_progress(data[0], data[1])
		"coin":
			level.take_coin(data[0])
			if world:
				_add_coin()
		"box":
			level.take_box(data[0])
		"out":
			var p: Player = _by_id.get(data[0])
			if p:
				if p.puppet:
					p.knock_out()
				if Net.is_host():
					_mark_out(p)
		"bonk":
			if Net.is_host() and mode == "brawl":
				var by: Player = _by_id.get(data[1])
				if by:
					_score[by] += 1
					if by == player:
						_my_bonk(_by_id.get(data[0], player))
		"score":
			for k in data:
				var p: Player = _by_id.get(k)
				if p:
					_score[p] = data[k]
		"end":
			_show_results(data)
		"wend":
			_zone_complete()
		"next":
			Net.game = data
			Engine.time_scale = 1.0
			get_tree().reload_current_scene()
		"lobby":
			_to_lobby()
		"peer_leave":
			for p in racers.duplicate():
				if p.net_id != "" and Net.owner_of(p.net_id) == from:
					racers.erase(p)
					_score.erase(p)
					_by_id.erase(p.net_id)
					p.queue_free()
			if Net.is_host() and mode == "survival" and running:
				var alive := racers.filter(func(r): return not r.is_out)
				if alive.size() <= 1:
					_end_round()

func _on_net_closed(reason: String) -> void:
	_over = true
	var m := UI.modal("DISCONNECTED", UI.CORAL)
	var vb: VBoxContainer = m[1]
	vb.add_child(UI.ink_text(reason, 28))
	vb.add_child(UI.button("MENU", UI.YELLOW, 40, func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/menu.tscn"), "home"))
	hud.add_child(m[0])
	UI.pop_in(m[0].get_meta("card"))

# ---------------------------------------------------------------- results

func _finish_round() -> bool:
	if _over:
		return false
	_over = true
	running = false
	controls.release_all()
	controls.visible = false
	return true

func _stat_row(vb: VBoxContainer, icon: String, name: String, value: String, color: Color) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var ic := TextureRect.new()
	ic.texture = UI.icon(icon)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(44, 44)
	ic.modulate = UI.INK
	hb.add_child(ic)
	var name_l := UI.label(name, 30, UI.INK, false)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(name_l)
	hb.add_child(UI.plate(value, color, 28))
	vb.add_child(hb)

## Every mission in the zone done.
func _zone_complete() -> void:
	if net and Net.is_host():
		Net.send(0, "wend")
	if not _finish_round():
		return
	var stars := world.stars()
	Game.complete_level(level.id, stars)
	Game.play("vo_you_win", 0.0, 0.0)
	var m := UI.modal("ZONE CLEARED!", UI.YELLOW)
	var vb: VBoxContainer = m[1]
	vb.add_child(UI.star_row(stars, 3, 74))
	for ms in world.missions:
		_stat_row(vb, "checkmark", ms.title, "DONE", UI.TEAL)
	_stat_row(vb, "coin", "COINS", str(coins), UI.YELLOW)
	_stat_row(vb, "timer", "TIME", "%d:%02d" % [int(run_time) / 60, int(run_time) % 60], UI.TEAL)
	_stat_row(vb, "bang", "KNOCKOUTS", str(kos), UI.CORAL)
	var idx := Adventure.index_of(level.id)
	var has_next := idx + 1 < Adventure.LEVELS.size()
	if net:
		if Net.is_host():
			if has_next:
				vb.add_child(UI.button("NEXT ZONE", UI.YELLOW, 42, func():
					var g := Net.game.duplicate(true)
					g.id = Adventure.LEVELS[idx + 1].id
					Net.to_all("next", g), "play"))
			vb.add_child(UI.button("BACK TO LOBBY", UI.TEAL, 34, func(): Net.to_all("lobby"), "party"))
		else:
			vb.add_child(UI.ink_text("Waiting for the host...", 24))
	else:
		if has_next:
			vb.add_child(UI.button("NEXT ZONE", UI.YELLOW, 42, func():
				Engine.time_scale = 1.0
				Game.level_id = Adventure.LEVELS[idx + 1].id
				Game.save_settings()
				get_tree().reload_current_scene(), "play"))
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 14)
		row.add_child(UI.button("REPLAY", UI.TEAL, 32, _restart, "refresh"))
		row.add_child(UI.button("MAP", UI.GRAPE, 32, _to_world, "map"))
		vb.add_child(row)
	win_panel = m[0]
	hud.add_child(win_panel)
	UI.pop_in(win_panel.get_meta("card"))

## Host / offline: the round is over. Work out the standings, hand out show
## points and show everyone the results.
func _end_round() -> void:
	if _over:
		return
	var order: Array = []
	if mode == "survival":
		var alive := racers.filter(func(r): return not r.is_out and not r in _out_order)
		var outs := _out_order.duplicate()
		outs.reverse()
		order = alive + outs
	else:
		order = racers.duplicate()
		order.sort_custom(func(a, b): return _score[a] > _score[b])
	var res := {"order": [], "names": {}, "values": {}, "skins": {}}
	for p in order:
		var key := _key(p)
		res.order.append(key)
		res.names[key] = p.display_name if not (p == player and not net) else "YOU"
		res.skins[key] = p.skin
		match mode:
			"koth":
				res.values[key] = "%ds" % int(_score[p])
			"brawl":
				res.values[key] = "%d BONKS" % int(_score[p])
			_:
				res.values[key] = "OUT" if p in _out_order or p.is_out else "ALIVE"
	# the show's running totals
	var totals: Dictionary = (Net.game.get("totals", {}) if net else Game.show.get("totals", {})).duplicate()
	for i in res.order.size():
		var key: String = res.order[i]
		totals[key] = int(totals.get(key, 0)) + int(ROUND_POINTS[mini(i, ROUND_POINTS.size() - 1)])
	res.totals = totals
	if net:
		Net.game.totals = totals
		Net.to_all("end", res)
	else:
		if not Game.show.is_empty():
			Game.show.totals = totals
			var names: Dictionary = Game.show.get("names", {})
			names.merge(res.names, true)
			Game.show.names = names
		_show_results(res)

func _key(p: Player) -> String:
	return p.net_id if net else ("me" if p == player else p.display_name)

func _show_results(res: Dictionary) -> void:
	if not _finish_round():
		return
	var me := _key(player)
	var place: int = res.order.find(me) + 1
	var won := place == 1
	var rounds: int = Net.game.get("rounds", 1) if net else Game.show.get("rounds", 1)
	var round_: int = Net.game.get("round", 1) if net else Game.show.get("round", 1)
	var last := round_ >= rounds
	if net:
		Net.game.totals = res.totals
	Game.play("vo_you_win" if won else ("vo_congratulations" if place <= 3 else "vo_game_over"), 0.0, 0.0)
	var titles := {1: "WINNER!", 2: "2ND PLACE!", 3: "3RD PLACE!"}
	var title: String = titles.get(place, "%dTH PLACE" % place)
	if mode == "survival" and not won:
		title = "OUT! #%d" % place
	var m := UI.modal(title, UI.YELLOW if place <= 3 else UI.CORAL)
	var vb: VBoxContainer = m[1]
	vb.add_theme_constant_override("separation", 10)
	for i in res.order.size():
		var key: String = res.order[i]
		_stat_row(vb, "trophy" if i == 0 else "star", "%d. %s" % [i + 1, res.names[key]], res.values[key], UI.YELLOW if key == me else UI.TEAL)
	if rounds > 1:
		vb.add_child(UI.label("LEADERBOARD  (round %d/%d)" % [round_, rounds], 30, UI.GRAPE))
		var keys: Array = res.totals.keys()
		keys.sort_custom(func(a, b): return res.totals[a] > res.totals[b])
		var names: Dictionary = res.names.duplicate()
		if not net:
			names.merge(Game.show.get("names", {}))
		for i in keys.size():
			_stat_row(vb, "leaderboard" if i == 0 else "multiplayer", "%d. %s" % [i + 1, names.get(keys[i], keys[i])], "%d PTS" % res.totals[keys[i]], UI.YELLOW if keys[i] == me else UI.GRAPE)
		if last:
			var champ: String = names.get(keys[0], keys[0])
			vb.add_child(UI.label("%s WINS THE SHOW!" % champ.to_upper(), 36, UI.YELLOW))
	else:
		_stat_row(vb, "bang", "YOUR CRASHES", str(crashes), UI.CORAL)
	if net:
		if Net.is_host():
			if not last:
				vb.add_child(UI.button("NEXT ROUND", UI.YELLOW, 42, _net_next_round, "play"))
			vb.add_child(UI.button("BACK TO LOBBY", UI.TEAL, 34, func(): Net.to_all("lobby"), "party"))
		else:
			vb.add_child(UI.ink_text("Waiting for the host...", 24))
	elif rounds > 1 and not last:
		vb.add_child(UI.button("NEXT ROUND", UI.YELLOW, 42, _next_round, "play"))
		vb.add_child(UI.button("QUIT SHOW", UI.CORAL, 30, _to_menu, "close"))
	else:
		vb.add_child(UI.button("PLAY AGAIN", UI.YELLOW, 42, func():
			if rounds > 1:
				Game.show = {"rounds": rounds, "round": 1, "totals": {}, "names": {}, "played": [level.id]}
			_restart(), "refresh"))
		vb.add_child(UI.button("PARTY GAMES", UI.TEAL, 34, _to_menu, "party"))
	win_panel = m[0]
	hud.add_child(win_panel)
	UI.pop_in(win_panel.get_meta("card"))

## A different game than the last ones.
static func pick_next_game(played: Array) -> String:
	var all := Party.GAMES.keys()
	var fresh := all.filter(func(g): return not g in played.slice(-3))
	return (fresh if not fresh.is_empty() else all).pick_random()

func _next_round() -> void:
	var played: Array = Game.show.get("played", [])
	played.append(level.id)
	Game.show.played = played
	Game.show.round = int(Game.show.get("round", 1)) + 1
	Game.party_id = pick_next_game(played)
	_restart()

func _net_next_round() -> void:
	var g := Net.game.duplicate(true)
	var played: Array = g.get("played", [])
	played.append(level.id)
	g.played = played
	g.round = int(g.get("round", 1)) + 1
	g.id = pick_next_game(played)
	Net.to_all("next", g)
