extends Node3D
## Game scene for both modes:
##   adventure - a world level: reach the goal (with or against 0-4 bots),
##               collect coins, earn up to 3 stars, unlock the next level
##   party     - a minigame, everyone against everyone (1-4 bots)
## Builds the level, players, camera (follows the route as it turns, drag the
## top of the screen to look around), HUD, countdown, results, crash juice.

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
var _coin_plate: PanelContainer
var _count_label: Label
var win_panel: Control

var play_mode := "adventure"
## adventure | survival | koth | brawl
var mode := "adventure"
var coop := false
var crashes := 0
var bonks := 0
var coins := 0
var best_crash := 0
var run_time := 0.0
var running := false
var _over := false
var _finish_order: Array[Player] = []
var _out_order: Array[Player] = []
var _score := {}  # Player -> points (koth seconds / brawl bonks)
var _shake := 0.0
var _cam_pos := Vector3.ZERO
var _cam_yaw := 0.0
var _look_yaw := 0.0
var _cam_offset := Vector3(0, 6.4, 8.2)

func _ready() -> void:
	play_mode = Game.play_mode
	var theme := "meadow"
	if play_mode == "party":
		level = Party.new()
		add_child(level)
		level.build(Game.party_id)
		theme = level.theme
	else:
		play_mode = "adventure"
		coop = Game.coop
		level = Adventure.new()
		add_child(level)
		level.build(Game.level_id)
		theme = level.theme
	mode = level.mode
	level.finished.connect(_on_racer_finished)
	level.coin_collected.connect(_on_coin)
	var scenery := Scenery.new()
	scenery.theme = theme
	scenery.area = level.bounds
	add_child(scenery)

	_spawn_racers()
	_spawn_guards()

	cam = Camera3D.new()
	add_child(cam)
	_apply_cam_framing()
	get_viewport().size_changed.connect(_apply_cam_framing)
	_cam_yaw = _target_yaw()
	_cam_pos = _cam_target()
	cam.global_position = _cam_pos
	cam.look_at(player.global_position)
	_build_hud()
	_countdown()

func _bot_count() -> int:
	if play_mode == "party":
		return clampi(Game.party_bots, 1, 4)
	return clampi(Game.bots, 0, 4)

func _spawn_racers() -> void:
	var skins := Player.SKINS.keys()
	var names := BOT_NAMES.duplicate()
	names.shuffle()
	var slots := level.starts.duplicate()
	var n := _bot_count() + 1
	# adventure: you start in the middle of the line; party: spread around the ring
	var order: Array[int] = []
	if play_mode == "adventure":
		order.assign([2, 1, 3, 0, 4])
	else:
		var step := 8 / n
		for i in n:
			order.append((i * step) % slots.size())
	for i in n:
		var p := Player.new()
		var human := i == 0
		p.skin = Game.skin if human else skins[(i + randi()) % skins.size()]
		p.is_human = human
		p.display_name = "YOU" if human else names[i % names.size()]
		p.respawn_enabled = mode != "survival"
		p.kill_y = level.kill_y
		p.team = 0 if coop else -1
		add_child(p)
		var slot: Vector3 = slots[order[i]]
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
		else:
			var b := Bot.new()
			b.level = level
			match mode:
				"survival":
					b.mode = "survive"
				"koth", "brawl":
					b.mode = mode
				_:
					b.mode = "coop" if coop else "race"
			b.skill = randf_range(0.55, 1.0)
			p.add_child(b)
			p.add_name_tag(UI.TEAL if coop else UI.WHITE)
		p.bonked.connect(_on_bonk.bind(p))
		p.eliminated.connect(_on_eliminated.bind(p))
		_score[p] = 0.0
		racers.append(p)
	for r in racers:
		for c in r.get_children():
			if c is Bot:
				(c as Bot).buddy = player
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
		extra = Vector3(0, 2.5, 2.0) if mode == "survival" else Vector3(0, 2.0, 1.5)
	if s.x < s.y:
		_cam_offset = Vector3(0, 6.4, 8.2) + extra
		cam.fov = 70
	else:
		_cam_offset = Vector3(0, 5.2, 7.2) + extra
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
	_pos_plate = UI.plate("", UI.YELLOW, 32, "crown")
	top.add_child(_pos_plate)
	if play_mode == "adventure":
		_coin_plate = UI.plate("0/%d" % level.coins_total, UI.YELLOW, 28, "coin")
		top.add_child(_coin_plate)
	else:
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
	if play_mode == "adventure" and _bot_count() == 0:
		_pos_plate.visible = false

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
	_count_label.position = Vector2(-320, -260)
	_count_label.size = Vector2(640, 240)
	_count_label.pivot_offset = Vector2(320, 120)
	_count_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(_count_label)
	_update_position()

func _title() -> String:
	if play_mode == "party":
		return Party.info(level.id).name
	return Adventure.info(level.id).name

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
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _to_world() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/world_map.tscn")

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
	_update_act_button()

func _update_act_button() -> void:
	var label := "PUSH"
	if player.grabbing_player():
		label = "YEET"
	elif player.item != "":
		label = Player.ITEMS[player.item].label
	controls.set_act(label, player.ammo if player.item != "" else 0)

func _process(delta: float) -> void:
	var real_dt: float = delta / max(Engine.time_scale, 0.01)
	if running and not _over:
		run_time += delta
		_score_tick(delta)
	var timed := mode == "koth" or mode == "brawl"
	UI.plate_label(_time_plate).text = "%d" % ceili(maxf(Party.ROUND_TIME - run_time, 0.0)) if timed else "%.1f" % run_time
	_update_position()
	# camera: follow the route's heading (adventure), plus whatever you dragged
	var look := controls.consume_look()
	if look != 0.0:
		_look_yaw = wrapf(_look_yaw - look * 0.006, -PI, PI)
	elif player.input_dir.length() > 0.3:
		_look_yaw = lerpf(_look_yaw, 0.0, 1.0 - exp(-real_dt * 0.6))
	_cam_yaw = lerp_angle(_cam_yaw, _target_yaw(), 1.0 - exp(-real_dt * 1.6))
	_cam_pos = _cam_pos.lerp(_cam_target(), 1.0 - exp(-real_dt * 5.0))
	_shake = max(_shake - real_dt * 2.5, 0.0)
	var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * _shake * 0.6
	cam.global_position = _cam_pos + off
	var yb := Basis(Vector3.UP, _cam_yaw + _look_yaw)
	cam.look_at(_focus() + yb * Vector3(0, 0.6, -2.6))

func _focus() -> Vector3:
	if player.is_out:
		return level.center
	return player.global_position

func _target_yaw() -> float:
	if play_mode == "party":
		return 0.0
	var h := level.heading_at(level.progress(player.global_position))
	return atan2(-h.x, -h.z)

func _cam_target() -> Vector3:
	return _focus() + Basis(Vector3.UP, _cam_yaw + _look_yaw) * _cam_offset

func _score_tick(delta: float) -> void:
	if mode == "koth":
		var party := level as Party
		for p in racers:
			if not p.is_crashed and party.on_hill(p.global_position):
				_score[p] += delta
	if (mode == "koth" or mode == "brawl") and run_time >= Party.ROUND_TIME:
		_end_timed()

func _update_position() -> void:
	if _pos_plate == null:
		return
	var l := UI.plate_label(_pos_plate)
	match mode:
		"survival":
			l.text = "%d LEFT" % racers.filter(func(r): return not r.is_out).size()
		"koth":
			l.text = "%d  #%d" % [int(_score[player]), _rank(player)]
		"brawl":
			l.text = "%d  #%d" % [int(_score[player]), _rank(player)]
		_:
			l.text = "TEAM" if coop else "%d/%d" % [_race_place(player), racers.size()]

func _rank(p: Player) -> int:
	var r := 1
	for o in racers:
		if o != p and _score[o] > _score[p]:
			r += 1
	return r

## 1-based place: finishers by order, then everyone else by route progress.
func _race_place(p: Player) -> int:
	if p in _finish_order:
		return _finish_order.find(p) + 1
	var mine := level.progress(p.global_position)
	var ahead := _finish_order.size()
	for r in racers:
		if r != p and not r in _finish_order and level.progress(r.global_position) > mine:
			ahead += 1
	return ahead + 1

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
	Game.slowmo(0.3, 0.45)
	Input.vibrate_handheld(60)
	var words := ["NICE CRASH!", "OUCH!", "SPLAT!", "BONK!", "WHOOPS!", "EPIC FAIL!"]
	var text: String = words[randi() % words.size()] if power < 14 else "LEGENDARY CRASH!"
	if player.skin == "egg" and player.cracks >= 3:
		text = "EGG-SPLOSION!"
	elif player.skin == "egg":
		text = "CRACK!" if player.cracks == 1 else "CRACK CRACK!"
	_popup("%s\n+%d" % [text, score])

func _on_bonk(victim: Player, _how: String, by: Player) -> void:
	if not running or _over:
		return
	if mode == "brawl" and not victim.is_enemy:
		_score[by] += 1
	if by != player:
		return
	bonks += 1
	var words := ["BONK!", "GOTCHA!", "YEET!", "SORRY NOT SORRY", "BULLSEYE!"]
	_popup("%s\n%s +100" % [words[randi() % words.size()], victim.display_name], UI.TEAL)
	Input.vibrate_handheld(30)

func _on_coin(_p: Player) -> void:
	coins += 1
	if _coin_plate:
		UI.plate_label(_coin_plate).text = "%d/%d" % [coins, level.coins_total]
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
	crash_label.rotation = randf_range(-0.15, 0.15)
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(crash_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.7)
	tw.tween_property(crash_label, "modulate:a", 0.0, 0.3)

func _on_racer_finished(p: Player) -> void:
	_finish_order.append(p)
	if p == player:
		_level_complete()

func _on_eliminated(p: Player) -> void:
	if mode != "survival" or _over:
		return
	_out_order.append(p)
	Game.play("eliminated", 0.0, -2.0 if p == player else -10.0)
	var alive := racers.filter(func(r): return not r.is_out)
	if p == player:
		_popup("ELIMINATED!", UI.CORAL)
		await get_tree().create_timer(1.6).timeout
		_party_results(alive.size() + 1)
	elif alive.size() == 1 and alive[0] == player:
		_party_results(1)

func _end_timed() -> void:
	if _over:
		return
	_party_results(_rank(player))

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
	ic.custom_minimum_size = Vector2(44, 44)
	hb.add_child(ic)
	var name_l := UI.label(name, 30, UI.INK, false)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(name_l)
	hb.add_child(UI.plate(value, color, 28))
	vb.add_child(hb)

func _level_complete() -> void:
	if not _finish_round():
		return
	var info := Adventure.info(level.id)
	var place := _finish_order.find(player) + 1
	var rivals := not coop and _bot_count() > 0
	var stars := 1
	if level.coins_total > 0 and coins >= ceili(level.coins_total * 0.7):
		stars += 1
	if (rivals and place == 1) or (not rivals and run_time <= info.par):
		stars += 1
	Game.complete_level(level.id, stars)
	Game.play("vo_you_win" if place == 1 or not rivals else "vo_congratulations", 0.0, 0.0)
	var m := UI.modal("LEVEL COMPLETE!", UI.YELLOW)
	var vb: VBoxContainer = m[1]
	vb.add_child(UI.star_row(stars, 3, 74))
	if rivals:
		var titles := {1: "1ST PLACE!", 2: "2ND PLACE", 3: "3RD PLACE"}
		_stat_row(vb, "crown", "PLACE", titles.get(place, "%dTH" % place), UI.YELLOW)
	_stat_row(vb, "coin", "COINS", "%d / %d" % [coins, level.coins_total], UI.YELLOW)
	_stat_row(vb, "timer", "TIME", "%.1fs" % run_time, UI.TEAL if run_time <= info.par else UI.CORAL)
	_stat_row(vb, "bang", "CRASHES", str(crashes), UI.CORAL)
	if bonks > 0:
		_stat_row(vb, "act", "BONKS", str(bonks), UI.GRAPE)
	var hint := "Star 2: grab 70%% of the coins.  Star 3: %s" % ("finish 1st" if rivals else "beat %ds" % int(info.par))
	vb.add_child(UI.ink_text(hint, 20))
	var idx := Adventure.index_of(level.id)
	if idx + 1 < Adventure.LEVELS.size():
		vb.add_child(UI.button("NEXT LEVEL", UI.YELLOW, 42, func():
			Engine.time_scale = 1.0
			Game.level_id = Adventure.LEVELS[idx + 1].id
			Game.save_settings()
			get_tree().reload_current_scene(), "play"))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.add_child(UI.button("RETRY", UI.TEAL, 32, _restart, "refresh"))
	row.add_child(UI.button("MAP", UI.GRAPE, 32, _to_world, "map"))
	vb.add_child(row)
	win_panel = m[0]
	hud.add_child(win_panel)
	UI.pop_in(win_panel.get_meta("card"))

func _party_results(place: int) -> void:
	if not _finish_round():
		return
	var won := place == 1
	Game.play("vo_you_win" if won else ("vo_congratulations" if place <= 3 else "vo_game_over"), 0.0, 0.0)
	var titles := {1: "WINNER!", 2: "2ND PLACE!", 3: "3RD PLACE!"}
	var title: String = titles.get(place, "%dTH PLACE" % place)
	if mode == "survival" and not won:
		title = "OUT! #%d" % place
	var m := UI.modal(title, UI.YELLOW if place <= 3 else UI.CORAL)
	var vb: VBoxContainer = m[1]
	# standings
	var order: Array = racers.duplicate()
	if mode == "survival":
		var alive := racers.filter(func(r): return not r.is_out)
		var outs := _out_order.duplicate()
		outs.reverse()
		order = alive + outs
	else:
		order.sort_custom(func(a, b): return _score[a] > _score[b])
	for i in order.size():
		var p: Player = order[i]
		var value := ""
		match mode:
			"koth":
				value = "%ds" % int(_score[p])
			"brawl":
				value = "%d BONKS" % int(_score[p])
			_:
				value = "OUT" if p.is_out else "ALIVE"
		_stat_row(vb, "crown" if i == 0 else "bang", "%d. %s" % [i + 1, p.display_name], value, UI.YELLOW if p == player else UI.TEAL)
	_stat_row(vb, "bang", "YOUR CRASHES", str(crashes), UI.CORAL)
	vb.add_child(UI.button("PLAY AGAIN", UI.YELLOW, 42, _restart, "refresh"))
	vb.add_child(UI.button("PARTY GAMES", UI.TEAL, 34, _to_menu, "party"))
	win_panel = m[0]
	hud.add_child(win_panel)
	UI.pop_in(win_panel.get_meta("card"))
