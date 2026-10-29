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
