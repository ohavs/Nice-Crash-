extends Control
## Main menu: title, character pick (live 3D preview), play, settings/updates.

var _font: Font
var _skin_keys := Player.SKINS.keys()
var _skin_i := 0
var _skin_name: Label
var _preview_root: Node3D
var _update_btn: Button
var _update_status: Label
var _update_url := ""
var _settings: PanelContainer

func _ready() -> void:
	_font = load("res://assets/kenney/lilita_one_regular.ttf")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_skin_i = maxi(0, _skin_keys.find(Game.get_meta("skin", "egg")))

	var bg := ColorRect.new()
	bg.color = Color("5fb6ff")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 3D character preview
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var sv := SubViewport.new()
	sv.transparent_bg = true
	sv.own_world_3d = true
	svc.add_child(sv)
	_preview_root = Node3D.new()
	sv.add_child(_preview_root)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.6, 4.2)
	cam.fov = 40
	sv.add_child(cam)
	cam.look_at(Vector3(1.1, 0.1, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	sv.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("cfeeff")
	env.environment.ambient_light_energy = 0.8
	sv.add_child(env)
	_show_preview()

	var title := _label("NICE CRASH!", 110)
	title.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	title.position = Vector2(60, -260)
	title.rotation = -0.05
	add_child(title)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	box.position = Vector2(70, -80)
	box.add_theme_constant_override("separation", 18)
	add_child(box)
	box.add_child(_button("PLAY", Color("ffd23f"), 54, _play))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_button("<", Color("ffffff"), 36, func(): _change_skin(-1)))
	_skin_name = _label("", 40)
	_skin_name.custom_minimum_size = Vector2(220, 0)
	_skin_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_skin_name)
	row.add_child(_button(">", Color("ffffff"), 36, func(): _change_skin(1)))
	box.add_child(row)
	box.add_child(_button("SETTINGS", Color("4ecdc4"), 36, _toggle_settings))
	_update_skin_label()

	var ver := _label(Game.version_text(), 22)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(20, -44)
	add_child(ver)

	_build_settings()
	Game.update_checked.connect(_on_update_checked)
	Game.check_for_updates()  # silent check on start

func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.1))
	l.add_theme_constant_override("outline_size", int(size * 0.25))
	return l

func _button(text: String, color: Color, size: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color(0.08, 0.06, 0.1))
	b.add_theme_color_override("font_hover_color", Color(0.08, 0.06, 0.1))
	b.add_theme_color_override("font_pressed_color", Color(0.08, 0.06, 0.1))
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.darkened(0.15 if st == "pressed" else 0.0)
		sb.set_corner_radius_all(22)
		sb.set_border_width_all(5)
		sb.border_color = Color(0.08, 0.06, 0.1)
		sb.content_margin_left = 30
		sb.content_margin_right = 30
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		sb.shadow_color = Color(0, 0, 0, 0.3)
		sb.shadow_offset = Vector2(0, 6 if st != "pressed" else 2)
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(cb)
	b.pressed.connect(func(): Game.play("land", 0.1, -6.0))
	return b

func _play() -> void:
	Game.set_meta("skin", _skin_keys[_skin_i])
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _change_skin(d: int) -> void:
	_skin_i = wrapi(_skin_i + d, 0, _skin_keys.size())
	_update_skin_label()
	_show_preview()

func _update_skin_label() -> void:
	_skin_name.text = Player.SKINS[_skin_keys[_skin_i]].name

func _show_preview() -> void:
	for c in _preview_root.get_children():
		c.queue_free()
	var p := Player.new()
	p.skin = _skin_keys[_skin_i]
	p.freeze = true
	p.position = Vector3(1.2, 0, 0)
	_preview_root.add_child(p)
	p.set_physics_process(false)
	p.rotation.y = 0.4
	var tw := create_tween().set_loops()
	tw.tween_property(p, "rotation:y", -0.4, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(p, "rotation:y", 0.4, 1.2).set_trans(Tween.TRANS_SINE)
	p.visual.scale = Vector3(1.3, 0.7, 1.3)
	create_tween().tween_property(p.visual, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _build_settings() -> void:
	_settings = PanelContainer.new()
	_settings.set_anchors_preset(Control.PRESET_CENTER)
	_settings.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("ffffff")
	sb.set_corner_radius_all(24)
	sb.set_border_width_all(5)
	sb.border_color = Color(0.08, 0.06, 0.1)
	sb.set_content_margin_all(28)
	_settings.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	_settings.add_child(vb)
	vb.add_child(_label("SETTINGS", 48))
	_update_status = _label(Game.version_text(), 26)
	vb.add_child(_update_status)
	_update_btn = _button("CHECK FOR UPDATES", Color("4ecdc4"), 30, _on_update_pressed)
	vb.add_child(_update_btn)
	vb.add_child(_button("CLOSE", Color("ffffff"), 30, _toggle_settings))
	add_child(_settings)

func _toggle_settings() -> void:
	_settings.visible = not _settings.visible
	if _settings.visible:
		await get_tree().process_frame
		_settings.position = (size - _settings.size) * 0.5

func _on_update_pressed() -> void:
	if _update_url != "":
		OS.shell_open(_update_url)
		return
	_update_status.text = "Checking..."
	Game.check_for_updates()

func _on_update_checked(available: bool, latest: int, url: String, error: String) -> void:
	if error != "":
		_update_status.text = error
	elif available:
		_update_url = url
		_update_status.text = "New build %d available!" % latest
		_update_btn.text = "DOWNLOAD UPDATE"
		if not _settings.visible:
			_toggle_settings()
	else:
		_update_status.text = "Up to date (%s)" % Game.version_text()
