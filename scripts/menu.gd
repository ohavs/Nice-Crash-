extends Control
## Main menu: logo, character pick on a floating island (live 3D), play,
## settings (controls layout editor, update check).
##
## Note: nothing here uses Tween.set_loops(). An infinite tween whose target
## gets freed spins forever in release builds (the loop guard is debug-only),
## which froze the menu when switching characters. Idle motion lives in
## _process instead.

var _skin_keys := Player.SKINS.keys()
var _skin_i := 0
var _skin_plate: PanelContainer
var _preview_root: Node3D
var _preview: Player
var _cam: Camera3D
var _stand_y := 0.0
var _title: Control
var _burst: TextureRect
var _t := 0.0
var _update_btn: Button
var _update_status: Label
var _update_url := ""
var _settings: Control
var _editor: Control

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_skin_i = maxi(0, _skin_keys.find(Game.skin))
	_build_world()
	_build_title()
	_build_bottom()
	Game.update_checked.connect(_on_update_checked)
	Game.check_for_updates()  # silent check on start
	if Game.open_party:
		Game.open_party = false
		_open_party.call_deferred()

# ------------------------------------------------------------- 3D backdrop

func _build_world() -> void:
	var sv := UI.world_view(self)
	var world := Node3D.new()
	sv.add_child(world)
	var scenery := Scenery.new()
	scenery.area = AABB(Vector3(-3, 0, -3), Vector3(6, 3, 6))
	scenery.clearance = 20.0
	world.add_child(scenery)

	# the hero island: a grassy platform on a rock pillar, with flowers,
	# a tree and the toaster everyone pops out of
	var island := Props.make("models/platform-grass-large-round")
	island.scale = Vector3.ONE * 0.9
	world.add_child(island)
	_stand_y = Props.base_size("models/platform-grass-large-round").y * 0.9
	var r := 2.5 * 0.9
	var rock := Props.sized("nature/rock_tallE", r * 2.0)
	rock.rotation.x = PI
	rock.position.y = 0.05
	world.add_child(rock)
	var tree := Props.sized("nature/tree_oak", 1.6)
	tree.position = Vector3(-r * 0.62, _stand_y, -r * 0.45)
	world.add_child(tree)
	var toaster := Props.sized("furniture/toaster", 1.1)
	toaster.position = Vector3(r * 0.6, _stand_y, -r * 0.35)
	toaster.rotation.y = -0.5
	world.add_child(toaster)
	for i in 6:
		var id: String = ["nature/flower_redA", "nature/grass_large", "nature/flower_yellowA", "nature/plant_bush", "nature/flower_purpleA", "nature/grass_large"][i]
		var g := Props.sized(id, 0.45)
		var a := PI * 0.12 + i * PI * 0.16
		g.position = Vector3(cos(a) * r * 0.78, _stand_y - 0.02, -absf(sin(a)) * r * 0.55 + 0.2)
		world.add_child(g)

	_preview_root = Node3D.new()
	world.add_child(_preview_root)
	_cam = Camera3D.new()
	_cam.fov = 34
	world.add_child(_cam)
	_frame_camera()
	resized.connect(_frame_camera)
	_show_preview(false)

func _frame_camera() -> void:
	if _cam == null:
		return
	var portrait := size.x < size.y
	_cam.position = Vector3(0, _stand_y + (2.4 if portrait else 1.6), 9.5 if portrait else 7.0)
	_cam.look_at(Vector3(0 if portrait else -1.8, _stand_y + (0.95 if portrait else 0.8), 0))

func _show_preview(hop := true) -> void:
	if _preview:
		_preview.queue_free()
	var p := Player.new()
	p.skin = _skin_keys[_skin_i]
	p.freeze = true
	_preview_root.add_child(p)
	p.set_physics_process(false)
	p.position = Vector3(0, _stand_y + 0.6, 0)
	_preview = p
	if hop:
		p.visual.scale = Vector3(1.35, 0.65, 1.35)
		var tw := p.create_tween()
		tw.tween_property(p.visual, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		var up := p.create_tween()
		up.tween_property(p.visual, "position:y", 0.6, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		up.tween_property(p.visual, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _process(delta: float) -> void:
	_t += delta
	if _preview:
		_preview.rotation.y = PI + sin(_t * 1.3) * 0.45  # face the camera, idle sway
	if _title:
		_title.rotation = sin(_t * 1.7) * 0.035
		_title.scale = Vector2.ONE * (1.0 + sin(_t * 3.4) * 0.015)
	if _burst:
		_burst.rotation += delta * 0.12

# ------------------------------------------------------------- 2D layer

func _build_title() -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	holder.position = Vector2(0, 230)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_burst = TextureRect.new()
	_burst.texture = UI.icon("burst")
	_burst.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_burst.size = Vector2(760, 760)
	_burst.position = -_burst.size * 0.5
	_burst.pivot_offset = _burst.size * 0.5
	_burst.modulate = Color(1.0, 0.86, 0.45, 0.6)
	_burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_burst)

	_title = VBoxContainer.new()
	_title.add_theme_constant_override("separation", -46)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_title)
	var nice := UI.label("NICE", 130, UI.WHITE)
	var crash := UI.label("CRASH!", 156, UI.YELLOW)
	for l in [nice, crash]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_constant_override("shadow_offset_y", 14)
		_title.add_child(l)
	nice.rotation = -0.06
	_title.size = _title.get_combined_minimum_size()
	_title.position = -_title.size * 0.5
	_title.pivot_offset = _title.size * 0.5

	var gear := UI.round_button("gear", UI.TEAL, 88, _open_settings)
	gear.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	gear.position = Vector2(-112, 40)
	add_child(gear)

func _build_bottom() -> void:
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	vb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vb.offset_bottom = -70
	vb.add_theme_constant_override("separation", 34)
	vb.alignment = BoxContainer.ALIGNMENT_END
	add_child(vb)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	row.add_child(UI.round_button("left", UI.WHITE, 92, func(): _change_skin(-1)))
	_skin_plate = UI.plate("", UI.GRAPE, 44)
	_skin_plate.custom_minimum_size = Vector2(280, 0)
	_skin_plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_skin_plate)
	row.add_child(UI.round_button("right", UI.WHITE, 92, func(): _change_skin(1)))
	vb.add_child(row)

	var play := UI.button("PLAY", UI.YELLOW, 76, _open_modes, "play", Vector2(0, 150))
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(play)

	var ver := UI.label(Game.version_text(), 22)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.modulate.a = 0.8
	vb.add_child(ver)
	_update_skin_label()

func _go(scene: String) -> void:
	Game.skin = _skin_keys[_skin_i]
	Game.save_settings()
	get_tree().change_scene_to_file(scene)

var _modes: Control
var _party: Control

func _open_modes() -> void:
	if _modes:
		return
	var m := UI.modal("PLAY", UI.YELLOW)
	_modes = m[0]
	var vb: VBoxContainer = m[1]
	var adv := UI.button("WORLD", UI.TEAL, 48, func():
		Game.play_mode = "adventure"
		_go("res://scenes/world_map.tscn"), "map", Vector2(470, 0))
	vb.add_child(adv)
	vb.add_child(UI.ink_text("Explore open worlds, beat skeletons, do missions. %d / %d stars" % [Game.total_stars(), Adventure.LEVELS.size() * 3], 22))
	vb.add_child(UI.button("PARTY", UI.CORAL, 48, func():
		_modes.queue_free()
		_modes = null
		_open_party(), "party", Vector2(470, 0)))
	vb.add_child(UI.ink_text("Everyone vs everyone minigames", 22))
	vb.add_child(UI.button("WITH FRIENDS", UI.YELLOW, 48, func():
		_go("res://scenes/lobby.tscn"), "online", Vector2(470, 0)))
	vb.add_child(UI.ink_text("Online or on the same Wi-Fi: party shows or the world together", 22))
	vb.add_child(UI.button("BACK", UI.GRAPE, 30, func():
		_modes.queue_free()
		_modes = null, "close"))
	add_child(_modes)
	UI.pop_in(_modes.get_meta("card"))

func _open_party() -> void:
	if _party:
		return
	var m := UI.modal("PARTY GAMES", UI.CORAL)
	_party = m[0]
	var vb: VBoxContainer = m[1]
	vb.add_theme_constant_override("separation", 10)
	vb.add_child(UI.stepper("bot", Game.party_bots, 1, 4, func(v):
		Game.party_bots = v
		Game.save_settings(), "%d BOTS"))
	vb.add_child(UI.stepper("trophy", Game.party_rounds, 1, 10, func(v):
		Game.party_rounds = v
		Game.save_settings(), "%d ROUNDS"))
	vb.add_child(UI.ink_text("More than 1 round: a show of random games with a leaderboard", 19))
	var start_show := func(id: String):
		Game.play_mode = "party"
		Game.party_id = id
		Game.show = {}
		if Game.party_rounds > 1:
			Game.show = {"rounds": Game.party_rounds, "round": 1, "totals": {}, "names": {}, "played": []}
		_go("res://scenes/main.tscn")
	var rnd := UI.button("RANDOM SHOW", UI.YELLOW, 32, func(): start_show.call(Party.GAMES.keys().pick_random()), "refresh")
	rnd.custom_minimum_size.x = 480
	vb.add_child(rnd)
	for id in Party.GAMES:
		var g: Dictionary = Party.GAMES[id]
		var icon := {"survival": "crown", "koth": "crown", "brawl": "act"}.get(g.mode, "play") as String
		var b := UI.button(g.name, g.color, 32, start_show.bind(id), icon)
		b.custom_minimum_size.x = 480
		vb.add_child(b)
		vb.add_child(UI.ink_text(g.blurb, 19))
	vb.add_child(UI.button("BACK", UI.GRAPE, 30, func():
		_party.queue_free()
		_party = null, "close"))
	add_child(_party)
	UI.pop_in(_party.get_meta("card"))

func _change_skin(d: int) -> void:
	_skin_i = wrapi(_skin_i + d, 0, _skin_keys.size())
	Game.skin = _skin_keys[_skin_i]
	_update_skin_label()
	_show_preview()

func _update_skin_label() -> void:
	UI.plate_label(_skin_plate).text = Player.SKINS[_skin_keys[_skin_i]].name

# ------------------------------------------------------------- settings

func _open_settings() -> void:
	if _settings:
		return
	var m := UI.modal("SETTINGS", UI.TEAL)
	_settings = m[0]
	var vb: VBoxContainer = m[1]
	vb.add_child(UI.button("CONTROLS LAYOUT", UI.GRAPE, 38, _open_editor, "grab"))
	vb.add_child(UI.label("ONLINE SERVER", 26, UI.INK, false))
	var url := UI.field(Game.relay_url, "wss://your-server.onrender.com", 20, 120, 470)
	url.text_changed.connect(func(t):
		Game.relay_url = t.strip_edges()
		Game.save_settings())
	vb.add_child(url)
	_update_btn = UI.button("CHECK FOR UPDATES", UI.TEAL, 34, _on_update_pressed, "refresh")
	vb.add_child(_update_btn)
	_update_status = UI.ink_text(Game.version_text(), 28)
	vb.add_child(_update_status)
	if _update_url != "":
		_show_update_available()
	vb.add_child(UI.button("CLOSE", UI.CORAL, 34, _close_settings, "close"))
	add_child(_settings)
	UI.pop_in(_settings.get_meta("card"))

func _close_settings() -> void:
	if _settings:
		_settings.queue_free()
		_settings = null

func _open_editor() -> void:
	_close_settings()
	_editor = Control.new()
	_editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_editor.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.04, 0.12, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_editor.add_child(dim)
	var tc := TouchControls.new()
	tc.edit_mode = true
	tc.layout_changed.connect(Game.save_settings)
	_editor.add_child(tc)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vb.grow_vertical = Control.GROW_DIRECTION_BOTH
	vb.add_theme_constant_override("separation", 22)
	_editor.add_child(vb)
	var hint := UI.plate("DRAG TO MOVE", UI.TEAL, 40, "grab")
	hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(hint)
	var tip := UI.label("Drag controls anywhere.\nTap one, then resize it:", 28)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tip)
	var size_row := HBoxContainer.new()
	size_row.alignment = BoxContainer.ALIGNMENT_CENTER
	size_row.add_theme_constant_override("separation", 18)
	size_row.add_child(UI.button("-  SMALLER", UI.TEAL, 32, func(): tc.resize_selected(-0.1)))
	size_row.add_child(UI.button("+  BIGGER", UI.TEAL, 32, func(): tc.resize_selected(0.1)))
	vb.add_child(size_row)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	row.add_child(UI.button("RESET", UI.CORAL, 34, func():
		Game.reset_layout()
		tc.queue_redraw(), "refresh"))
	row.add_child(UI.button("DONE", UI.YELLOW, 40, func():
		Game.save_settings()
		_editor.queue_free()
		_editor = null
		_open_settings(), "play"))
	vb.add_child(row)
	add_child(_editor)

func _on_update_pressed() -> void:
	if _update_url != "":
		OS.shell_open(_update_url)
		return
	_update_status.text = "Checking..."
	Game.check_for_updates()

func _show_update_available() -> void:
	_update_btn.text = "DOWNLOAD UPDATE"
	_update_btn.icon = UI.icon("download")

func _on_update_checked(available: bool, latest: int, url: String, error: String) -> void:
	if available:
		_update_url = url
		if not _settings and not _editor:
			_open_settings()
	if not _settings:
		return
	if error != "":
		_update_status.text = error
	elif available:
		_update_status.text = "New build %d available!" % latest
		_show_update_available()
	else:
		_update_status.text = "Up to date (%s)" % Game.version_text()
