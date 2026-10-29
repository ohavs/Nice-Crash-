class_name Fx
## Small one-shot effects built from real models: bursts of crumbs / shell
## chips (CPUParticles3D using a model's mesh) and fade-outs.

static var _mesh_cache := {}

## First mesh of a model, baked with its candy material (for particles).
static func model_mesh(id: String) -> Mesh:
	if _mesh_cache.has(id):
		return _mesh_cache[id]
	var probe := Props.make(id)
	var mi: MeshInstance3D = Props.meshes(probe)[0]
	var mesh := mi.mesh.duplicate() as Mesh
	for i in mesh.get_surface_count():
		var m := mi.get_active_material(i)
		if m:
			mesh.surface_set_material(i, m)
	probe.free()
	_mesh_cache[id] = mesh
	return mesh

## Spray `count` tiny copies of model `id` out from `pos`.
static func burst(parent: Node, pos: Vector3, id: String, count := 8, size := 0.15, speed := 4.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.mesh = model_mesh(id)
	p.amount = count
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.6
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -14, 0)
	p.angular_velocity_min = -400
	p.angular_velocity_max = 400
	var base := Props.base_size(id)
	var s := size / maxf(maxf(base.x, base.y), maxf(base.z, 0.001))
	p.scale_amount_min = s * 0.6
	p.scale_amount_max = s * 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(0.7, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)

## Shrink a node away after `delay` seconds, then free it.
static func fade_out(n: Node3D, delay: float) -> void:
	# physics bodies must not be scaled: shrink their model child instead
	var target: Node3D = n.get_child(0) if n is PhysicsBody3D else n
	var tw := n.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(target, "scale", target.scale * 0.01, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(n.queue_free)

## Comic word ("POW!", "YEET!") that pops up at `pos`, floats and fades:
## makes it obvious what just happened to whom.
static func word(parent: Node, pos: Vector3, text: String, color := UI.YELLOW, size := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var l := Label3D.new()
	l.text = text
	l.font = UI.font()
	l.font_size = 96
	l.pixel_size = 0.0045 * size
	l.outline_size = 26
	l.modulate = color
	l.outline_modulate = UI.INK
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 2
	l.outline_render_priority = 1
	parent.add_child(l)
	# a little scatter so back-to-back hits don't print on top of each other
	l.global_position = pos + Vector3(randf_range(-0.35, 0.35), randf_range(0.0, 0.35), randf_range(-0.2, 0.2))
	l.rotation.z = randf_range(-0.25, 0.25)
	l.scale = Vector3.ONE * 0.3
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector3.ONE * 1.15, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector3.ONE, 0.08)
	tw.parallel().tween_property(l, "position:y", l.position.y + 0.7, 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.15)
	tw.tween_property(l, "modulate:a", 0.0, 0.2)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.2)
	tw.tween_callback(l.queue_free)

static var _swoosh_mesh: ArrayMesh

## A white arc sweeping in front of `xf` (origin at the body, -z forward):
## the "swing" of a shove or a throw.
static func swoosh(parent: Node, xf: Transform3D, wide := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _swoosh_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := 14
		for i in n:
			var a0 := lerpf(-1.1, 1.1, float(i) / n)
			var a1 := lerpf(-1.1, 1.1, float(i + 1) / n)
			# thick in the middle, tapering at both ends
			var w0 := sin(PI * float(i) / n) * 0.16
			var w1 := sin(PI * float(i + 1) / n) * 0.16
			var o0 := Vector3(sin(a0), 0, -cos(a0))
			var o1 := Vector3(sin(a1), 0, -cos(a1))
			var q := [o0 * (0.8 - w0), o0 * (0.8 + w0), o1 * (0.8 + w1), o1 * (0.8 - w1)]
			for k in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(q[k])
		_swoosh_mesh = st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = _swoosh_mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1, 1, 1, 0.75)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_transform = xf
	mi.scale = Vector3(wide * 0.7, 1, 0.7)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(wide * 1.25, 1, 1.25), 0.18).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.18)
	tw.tween_callback(mi.queue_free)
