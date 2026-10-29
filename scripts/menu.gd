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

# ------------------------------------------------------------- 3D backdrop

func _build_world() -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_2X
	svc.add_child(sv)
	var world := Node3D.new()
	sv.add_child(world)
	var scenery := Scenery.new()
	scenery.length = 0.0
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
	_burst.modulate.a = 0.55
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

	var play := UI.button("PLAY", UI.YELLOW, 76, _open_courses, "play", Vector2(0, 150))
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(play)

	var ver := UI.label(Game.version_text(), 22)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.modulate.a = 0.8
	vb.add_child(ver)
	_update_skin_label()

func _play(course: String) -> void:
	Game.skin = _skin_keys[_skin_i]
	Game.course = course
	Game.save_settings()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

var _courses: Control

func _open_courses() -> void:
	if _courses:
		return
	var m := UI.modal("PICK A ROUND", UI.YELLOW)
	_courses = m[0]
	var vb: VBoxContainer = m[1]
	for id in Level.COURSES:
		var c: Dictionary = Level.COURSES[id]
		var b := UI.button(c.name, c.color, 34, _play.bind(id), "crown" if c.mode == "survival" else "play")
		b.custom_minimum_size.x = 470
		vb.add_child(b)
		var blurb := UI.ink_text(c.blurb, 20)
		blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(blurb)
	vb.add_child(UI.button("BACK", UI.CORAL, 30, func():
		_courses.queue_free()
		_courses = null, "close"))
	add_child(_courses)
	UI.pop_in(_courses.get_meta("card"))

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
	var tip := UI.label("Joystick, JUMP and GRAB\ncan go anywhere you like", 28)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tip)
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
