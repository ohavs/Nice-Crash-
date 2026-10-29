extends SceneTree
## Dev tool: renders every model in a folder into a contact sheet.
## xvfb-run godot --rendering-method mobile --script tools/model_sheet.gd -- res://assets/kenney/food /tmp/sheet.png

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0]
	var out: String = args[1] if args.size() > 1 else "/tmp/sheet.png"
	var files := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".glb") or f.ends_with(".gltf"):
			files.append(f)
	files.sort()
	var cols := 6
	var cell := 200
	var sheet := Image.create(cols * cell, int(ceil(files.size() / float(cols))) * cell, false, Image.FORMAT_RGBA8)
	var vp := SubViewport.new()
	vp.size = Vector2i(cell, cell)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.85, 0.9, 1)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color.WHITE
	we.environment.ambient_light_energy = 0.6
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40
	vp.add_child(cam)
	var lbl := Label.new()
	lbl.add_theme_color_override("font_color", Color.BLACK)
	vp.add_child(lbl)
	for i in files.size():
		var m: Node3D = load(dir + "/" + files[i]).instantiate()
		vp.add_child(m)
		var box := AABB()
		var first := true
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var c := box.get_center()
		cam.position = c + Vector3(1, 0.8, 1.4).normalized() * box.size.length() * 1.3
		cam.look_at(c)
		lbl.text = files[i].get_basename()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, cell, cell), Vector2i((i % cols) * cell, (i / cols) * cell))
		print(files[i], " pos=", box.position, " size=", box.size)
		m.free()
	sheet.save_png(out)
	quit()
