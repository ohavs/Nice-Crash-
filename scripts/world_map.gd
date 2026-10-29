extends Control
## Adventure world map: every level is an island in the sea, dressed like the
## place it takes you to (meadow, mushroom woods, windmill village, a giant
## kitchen, a pirate cove, frosty peaks), linked by stepping stones. Your
## character hops from island to island; locked islands wait behind a lock.
## The card at the bottom shows stars, how many bots come along (0-4), with
## you or against you, and PLAY.

const ISLAND_Y := -14.0
const GAP := 17.0

var _sv: SubViewport
var _world: Node3D
var _cam: Camera3D
var _hero: Player
var _islands: Array[Vector3] = []
var _locks: Array[Node3D] = []
var _sel := 0
var _hero_at := 0
var _hopping := false
var _cam_focus := Vector3.ZERO
var _t := 0.0

var _card: Control
var _name_plate: PanelContainer
var _blurb: Label
var _stars_box: Control
var _play_btn: Button
var _team_btn: Button
var _team_row: Control

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_sel = clampi(Adventure.index_of(Game.level_id), 0, mini(Game.unlocked, Adventure.LEVELS.size() - 1))
	_hero_at = _sel
	_build_world()
	_build_ui()
	_select(_sel, false)

# ------------------------------------------------------------- 3D

func _island_pos(i: int) -> Vector3:
	return Vector3(sin(i * 1.25) * 7.5, ISLAND_Y, -i * GAP)

func _build_world() -> void:
	_sv = UI.world_view(self)
	_world = Node3D.new()
	_sv.add_child(_world)
	var n := Adventure.LEVELS.size()
	var scenery := Scenery.new()
	scenery.area = AABB(Vector3(-14, ISLAND_Y, -(n - 1) * GAP - 10), Vector3(28, 8, (n - 1) * GAP + 60))
	scenery.clearance = 18.0
	scenery.reach = 50.0
	_world.add_child(scenery)
	for i in n:
		_islands.append(_island_pos(i))
		_island(i)
		if i > 0:
			_stones(_island_pos(i - 1), _island_pos(i), i <= Game.unlocked)
	_cam = Camera3D.new()
	_cam.fov = 50
	_world.add_child(_cam)
	_hero = Player.new()
	_hero.skin = Game.skin
	_hero.freeze = true
	_world.add_child(_hero)
	_hero.set_physics_process(false)
	_hero.position = _islands[_hero_at] + Vector3(0, 0.6, 1.5)
	_cam_focus = _islands[_sel]

func _put(id: String, pos: Vector3, size: float, yaw := 0.0) -> Node3D:
	var m := Props.sized(id, size)
	m.position = pos
	m.rotation.y = yaw
	_world.add_child(m)
	return m

func _island(i: int) -> void:
	var info: Dictionary = Adventure.LEVELS[i]
	var p := _islands[i]
	var ground := {"snow": "platformer/blockSnowLarge", "kitchen": "food/cuttingBoard"}.get(info.theme, "platformer/blockLarge") as String
	var base := Props.base_size(ground)
	var g := Props.make(ground)
	var depth := 4.0 if ground != "food/cuttingBoard" else 0.6
	g.scale = Vector3(9.0 / base.x, depth / base.y, 9.0 / base.z)
	g.position = p - Vector3(0, depth, 0)
	_world.add_child(g)
	if info.theme == "pirate":
		Props.tint(g, Color("f4d58d"), 0.55)
	if ground == "food/cuttingBoard":
		# the board sits on a stack of plates in the soup
		_put("food/plate", p - Vector3(0, 1.2, 0), 10.0)
		_put("furniture/kitchenCabinet", p - Vector3(0, 9.0, 0), 8.0)
	# landmark + dressing
	match info.id:
		"meadow":
			_put("nature/tree_oak", p + Vector3(-2.5, 0, -2.2), 3.4)
			_put("nature/tree_default", p + Vector3(2.8, 0, -1.8), 2.6)
			for k in 5:
				_put(["nature/flower_redA", "nature/flower_yellowA", "nature/plant_bush"][k % 3], p + Vector3(-3.0 + k * 1.5, 0, 3.0), 0.9, k)
		"forest":
			_put("nature/mushroom_red", p + Vector3(-2.2, 0, -1.5), 3.2)
			_put("nature/tree_pineRoundB", p + Vector3(2.6, 0, -2.4), 3.0)
			_put("nature/tree_oak_fall", p + Vector3(3.2, 0, 1.6), 2.4)
			_put("nature/mushroom_tanTall", p + Vector3(-3.2, 0, 2.2), 1.2)
		"village":
			_put("town/windmill", p + Vector3(-1.5, 0, -2.0), 4.5, 0.4)
			_put("town/stallRed", p + Vector3(2.8, 0, 0.5), 2.0, -0.6)
			_put("town/treeHighRound", p + Vector3(3.0, 0, -2.8), 2.0)
		"kitchen":
			_put("furniture/toaster", p + Vector3(-2.0, 0, -1.8), 3.0, 0.3)
			_put("food/pizza", p + Vector3(2.4, 0, -1.5), 2.6)
			_put("food/cupcake", p + Vector3(2.8, 0, 2.0), 1.2)
		"cove":
			_put("pirate/ship_light", p + Vector3(-0.5, 0.2, -2.5), 6.0, 0.8)
			_put("pirate/palm_detailed_long", p + Vector3(3.0, 0, 1.0), 3.0)
			_put("pirate/chest", p + Vector3(-3.0, 0, 2.2), 1.2, 0.5)
		"peaks":
			_put("holiday/snowmanFancy", p + Vector3(-2.2, 0, -1.6), 2.2, 0.3)
			_put("holiday/treePineSnow", p + Vector3(2.6, 0, -2.4), 2.0)
			_put("holiday/treePineSnowRound", p + Vector3(3.2, 0, 1.4), 1.6)
			_put("holiday/rockFormationLarge", p + Vector3(0.5, 0, -3.5), 2.4)
	# a flag shows its stars, a lock if you can't go yet
	var flag := Props.make("models/flag")
	flag.position = p + Vector3(-3.4, 0, 3.0)
	flag.scale = Vector3.ONE * 1.6
	_world.add_child(flag)
	var label := Label3D.new()
	label.text = "%d" % (i + 1)
	label.font = UI.font()
	label.font_size = 120
	label.pixel_size = 0.01
	label.outline_size = 30
	label.outline_modulate = UI.INK
	label.modulate = info.color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = p + Vector3(0, 4.6, 0)
	_world.add_child(label)
	if i > Game.unlocked:
		var lock := Props.sized("holiday/present", 1.8)
		lock.position = p + Vector3(0, 0.0, 1.0)
		Props.tint(lock, Color("6b6478"), 0.7)
		_world.add_child(lock)
		_locks.append(lock)
		label.modulate = Color("8a8299")

func _stones(a: Vector3, b: Vector3, open: bool) -> void:
	var n := 4
	for k in n:
		var t := (k + 1.0) / (n + 1.0)
		var s := Props.sized("platformer/blockLarge" if open else "nature/rock_largeA", 1.6)
		s.scale.y *= 0.6
		var p := a.lerp(b, t)
		s.position = p - Vector3(0, 0.6, 0)
		_world.add_child(s)
		if open:
			var c := Props.sized("models/coin", 0.6)
			c.position = p + Vector3(0, 0.5, 0)
			_world.add_child(c)

func _process(delta: float) -> void:
	_t += delta
	_cam_focus = _cam_focus.lerp(_islands[_sel], 1.0 - exp(-delta * 4.0))
	var portrait := size.x < size.y
	# the level card covers the lower half in portrait: aim below the island
	# so it sits in the upper part of the screen
	_cam.position = _cam_focus + (Vector3(0, 27, 34) if portrait else Vector3(0, 13, 16))
	_cam.look_at(_cam_focus + (Vector3(0, -6, 7) if portrait else Vector3(0, 0, 2)))
	if not _hopping:
		_hero.rotation.y = PI + sin(_t * 1.3) * 0.4
		_hero.visual.position.y = absf(sin(_t * 3.0)) * 0.08
	for l in _locks:
		l.rotation.y += delta * 0.8

# ------------------------------------------------------------- UI

func _build_ui() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 20
	top.offset_right = -20
	top.offset_top = 36
	top.add_theme_constant_override("separation", 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	top.add_child(UI.round_button("home", UI.CORAL, 84, func():
		get_tree().change_scene_to_file("res://scenes/menu.tscn")))
	var title := UI.plate("WORLD", UI.TEAL, 40, "map")
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	var st := UI.plate("%d/%d" % [Game.total_stars(), Adventure.LEVELS.size() * 3], UI.YELLOW, 34, "star")
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(st)

	# level card
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	vb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vb.offset_bottom = -40
	vb.add_theme_constant_override("separation", 14)
	add_child(vb)
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 14)
	nav.add_child(UI.round_button("left", UI.WHITE, 84, func(): _select(_sel - 1)))
	_name_plate = UI.plate("", UI.GRAPE, 38)
	_name_plate.custom_minimum_size.x = 420
	_name_plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nav.add_child(_name_plate)
	nav.add_child(UI.round_button("right", UI.WHITE, 84, func(): _select(_sel + 1)))
	vb.add_child(nav)

	var card := PanelContainer.new()
	var cs := ChunkyStyle.new(UI.CREAM, 36, 12, false, Vector2(28, 18))
	card.add_theme_stylebox_override("panel", cs)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.custom_minimum_size.x = 600
	vb.add_child(card)
	_card = card
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	card.add_child(inner)
	_stars_box = HBoxContainer.new()
	_stars_box.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_child(_stars_box)
	_blurb = UI.ink_text("", 24)
	inner.add_child(_blurb)
	inner.add_child(UI.stepper("bot", Game.bots, 0, 4, func(v):
		Game.bots = v
		Game.save_settings()
		_update_team(), "%d BOTS"))
	_team_row = HBoxContainer.new()
	(_team_row as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_child(_team_row)
	_team_btn = UI.button("", UI.TEAL, 32, func():
		Game.coop = not Game.coop
		Game.save_settings()
		_update_team(), "team", Vector2(420, 0))
	_team_row.add_child(_team_btn)
	_play_btn = UI.button("PLAY", UI.YELLOW, 62, _play, "play", Vector2(380, 0))
	_play_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(_play_btn)
	_update_team()

func _update_team() -> void:
	_team_row.visible = Game.bots > 0
	_team_btn.text = "WITH YOU (TEAM)" if Game.coop else "AGAINST YOU (RACE)"
	_team_btn.icon = UI.icon("team" if Game.coop else "versus")
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var s := _team_btn.get_theme_stylebox(st) as ChunkyStyle
		if s:
			s.color = UI.TEAL if Game.coop else UI.CORAL
	_team_btn.queue_redraw()

func _select(i: int, hop := true) -> void:
	i = clampi(i, 0, Adventure.LEVELS.size() - 1)
	var changed := i != _sel
	_sel = i
	var info: Dictionary = Adventure.LEVELS[i]
	var open := i <= Game.unlocked
	UI.plate_label(_name_plate).text = "%d. %s" % [i + 1, info.name]
	_blurb.text = info.blurb if open else "Locked - finish level %d first!" % i
	for c in _stars_box.get_children():
		c.queue_free()
	if open:
		_stars_box.add_child(UI.star_row(int(Game.stars.get(info.id, 0)), 3, 56))
	else:
		var l := TextureRect.new()
		l.texture = UI.icon("lock")
		l.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		l.custom_minimum_size = Vector2(56, 56)
		_stars_box.add_child(l)
	_play_btn.disabled = not open
	_play_btn.modulate.a = 1.0 if open else 0.5
	if open and hop and changed:
		_hop_to(i)

## Hop the hero along the stepping stones to island `i`.
func _hop_to(i: int) -> void:
	if _hopping:
		return
	_hopping = true
	var tw := create_tween()
	var step := 1 if i > _hero_at else -1
	var at := _hero_at
	while at != i:
		var a := _islands[at]
		var b := _islands[at + step]
		for k in 6:
			var from := a.lerp(b, k / 5.0) + Vector3(0, 0.6, 1.5 if k == 0 else 0.0)
			var to := a.lerp(b, (k + 1) / 5.0) + Vector3(0, 0.6, 1.5 if k == 4 else 0.0)
			if k == 5:
				break
			tw.tween_callback(func():
				var d := to - from
				_hero.rotation.y = atan2(d.x, d.z) + PI
				Game.play("jump", 0.15, -12.0))
			tw.tween_method(func(u: float): _hero.position = from.lerp(to, u) + Vector3.UP * sin(u * PI) * 1.2, 0.0, 1.0, 0.16)
		at += step
	tw.tween_callback(func():
		_hero_at = i
		_hopping = false
		Game.play("land", 0.1, -6.0))

func _input(event: InputEvent) -> void:
	# tap an island to go there
	if event is InputEventScreenTouch and event.pressed and _card:
		if event.position.y > size.y * 0.55:
			return
		var best := -1
		var best_d := 140.0
		for i in _islands.size():
			if _cam.is_position_behind(_islands[i]):
				continue
			var sp := _cam.unproject_position(_islands[i] + Vector3(0, 1.0, 0))
			# the 3D view renders at the screen's real pixels: back to canvas units
			sp *= size / Vector2(_sv.size)
			var d := sp.distance_to(event.position)
			if d < best_d:
				best_d = d
				best = i
		if best >= 0:
			_select(best)

func _play() -> void:
	if _sel > Game.unlocked:
		return
	Game.play_mode = "adventure"
	Game.level_id = Adventure.LEVELS[_sel].id
	Game.save_settings()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
