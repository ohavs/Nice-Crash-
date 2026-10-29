class_name Level
extends Node3D
## Builds a course from Kenney models + toon-shaded obstacles.
## Course runs along -Z. Each section is a small function so new
## levels are just new combinations.

signal checkpoint_reached(pos: Vector3)
signal finished

const M := "res://assets/kenney/models/%s.glb"

var spawn_point := Vector3(0, 1.5, 0)
var _movers: Array = []   # [body, callable(t) -> Transform3D]
var _t := 0.0

func build_course_1() -> void:
	var z := 0.0
	_platform("platform-grass-large-round", Vector3(0, 0, z), 1.6)
	_decor_grass(Vector3(0, 0.8, z), 6)
	z -= 9.0
	# 1: spinning bar
	_platform("platform-large", Vector3(0, 0, z), 1.8)
	_spinner(Vector3(0, 0.99, z), 8.0, 1.6)
	z -= 9.5
	# 2: hop gaps
	for i in 3:
		_platform("platform", Vector3(sin(i * 1.7) * 1.5, 0, z), 1.3)
		z -= 3.6
	z -= 1.5
	_platform("platform-large", Vector3(0, 0, z), 1.6)
	_checkpoint(Vector3(0, 0.9, z))
	_crates(Vector3(2.2, 0.9, z + 1.5))
	z -= 9.0
	# 3: pendulum hammers
	_bridge(Vector3(0, 0, z), 14.0)
	_hammer(Vector3(0, 6.5, z + 4.0), 0.0)
	_hammer(Vector3(0, 6.5, z - 1.5), PI * 0.5)
	_hammer(Vector3(0, 6.5, z - 6.0), PI)
	z -= 11.0
	_platform("platform-large", Vector3(0, 0, z), 1.6)
	_checkpoint(Vector3(0, 0.9, z))
	z -= 7.5
	# 4: falling platforms
	for i in 4:
		_falling(Vector3((i % 2) * 2.4 - 1.2, 0, z))
		z -= 3.4
	z -= 1.5
	_platform("platform-large", Vector3(0, 0, z), 1.6)
	_bounce_pad(Vector3(0, 0.9, z - 2.0))
	z -= 12.0
	# 5: high landing + pushers
	_platform("platform-large", Vector3(0, 2.5, z), 2.0)
	_checkpoint(Vector3(0, 3.6, z + 3.0))
	_pusher(Vector3(-5.5, 3.6, z - 1.5), 3.4, 0.0)
	_pusher(Vector3(5.5, 3.6, z - 3.5), -3.4, 1.4)
	z -= 9.5
	_platform("platform-grass-large-round", Vector3(0, 2.5, z), 1.6)
	_finish(Vector3(0, 3.4, z))
	_clouds()

# ------------------------------------------------------------- pieces

func _model(name: String) -> Node3D:
	return load(M % name).instantiate()

func _static_from_model(name: String, pos: Vector3, s: float, s_y := -1.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	body.position = pos
	var m := _model(name)
	m.scale = Vector3(s, s if s_y < 0 else s_y, s)
	body.add_child(m)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var col := CollisionShape3D.new()
		col.shape = mi.mesh.create_trimesh_shape()
		body.add_child(col)
		col.transform = m.transform * mi.transform
	return body

func _platform(name: String, pos: Vector3, s: float) -> StaticBody3D:
	return _static_from_model(name, pos, s)

func _bridge(pos: Vector3, length: float) -> void:
	var b := StaticBody3D.new()
	add_child(b)
	b.position = pos + Vector3(0, 0.4, 0)
	var size := Vector3(3.2, 0.5, length)
	_box_visual(b, size, Color("c98b55"))
	_box_col(b, size)
	# rails stripes
	for side in [-1, 1]:
		var rail := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.2, 0.3, length)
		rail.mesh = bm
		rail.material_override = Toon.mat(Color("8f5a34"))
		rail.position = Vector3(side * 1.6, 0.3, 0)
		b.add_child(rail)

func _box_visual(parent: Node3D, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = Toon.mat(color)
	parent.add_child(mi)
	return mi

func _box_col(parent: Node3D, size: Vector3) -> void:
	var c := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	c.shape = bs
	parent.add_child(c)

func _mover(body: AnimatableBody3D, fn: Callable) -> void:
	body.sync_to_physics = true
	body.collision_layer = 1
	add_child(body)
	_movers.append([body, fn])

func _spinner(center: Vector3, length: float, speed: float) -> void:
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.45
	cm.height = 1.0
	post.mesh = cm
	post.material_override = Toon.mat(Color("ff5a5f"))
	var post_body := StaticBody3D.new()
	post_body.position = center + Vector3(0, 0.5, 0)
	add_child(post_body)
	post_body.add_child(post)
	var pc := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 0.45
	cs.height = 1.0
	pc.shape = cs
	post_body.add_child(pc)
	var bar := AnimatableBody3D.new()
	var size := Vector3(length, 0.45, 0.45)
	var v := _box_visual(bar, size, Color("ffd23f"))
	v.position.y = 0
	_box_col(bar, size)
	_mover(bar, func(t): return Transform3D(Basis(Vector3.UP, t * speed), center + Vector3(0, 0.75, 0)))

func _hammer(pivot: Vector3, phase: float) -> void:
	var arm_len := 5.2
	var h := AnimatableBody3D.new()
	var stick := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.1
	cm.bottom_radius = 0.1
	cm.height = arm_len
	stick.mesh = cm
	stick.material_override = Toon.mat(Color("6b6b80"))
	stick.position.y = -arm_len * 0.5
	h.add_child(stick)
	var head_size := Vector3(1.0, 1.0, 1.6)
	var head := _box_visual(h, head_size, Color("ff5a5f"))
	head.position.y = -arm_len
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = head_size
	col.shape = bs
	col.position.y = -arm_len
	h.add_child(col)
	# frame
	for side in [-1, 1]:
		var pole := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.12
		pm.bottom_radius = 0.12
		pm.height = pivot.y
		pole.mesh = pm
		pole.material_override = Toon.mat(Color("6b6b80"))
		pole.position = Vector3(side * 2.2, pivot.y * 0.5, pivot.z)
		add_child(pole)
	_mover(h, func(t): return Transform3D(Basis(Vector3.FORWARD, sin(t * 1.9 + phase) * 1.15), pivot))

func _pusher(start: Vector3, travel: float, phase: float) -> void:
	var p := AnimatableBody3D.new()
	var size := Vector3(1.6, 1.4, 1.6)
	_box_visual(p, size, Color("4ecdc4"))
	_box_col(p, size)
	_mover(p, func(t):
		var k := clampf(sin(t * 2.2 + phase) * 1.6, -1.0, 1.0) * 0.5 + 0.5
		return Transform3D(Basis(), start + Vector3(travel * k, 0, 0)))

func _falling(pos: Vector3) -> void:
	var body := RigidBody3D.new()
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.collision_layer = 1
	body.mass = 5.0
	add_child(body)
	body.position = pos
	var m := _model("platform-falling")
	body.add_child(m)
	var c := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.2, 0.5, 2.2)
	c.shape = bs
	c.position.y = 0.25
	body.add_child(c)
	var area := Area3D.new()
	area.collision_mask = 2
	var ac := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(2.0, 0.6, 2.0)
	ac.shape = ab
	ac.position.y = 0.7
	area.add_child(ac)
	body.add_child(area)
	var home := body.transform
	area.body_entered.connect(func(_b):
		if body.has_meta("falling"):
			return
		body.set_meta("falling", true)
		var tw := create_tween()
		tw.tween_property(m, "position:x", 0.06, 0.05)
		tw.tween_property(m, "position:x", -0.06, 0.05)
		tw.set_loops(5)
		await get_tree().create_timer(0.6).timeout
		body.freeze = false
		Game.play("break", 0.1, -8.0)
		await get_tree().create_timer(3.5).timeout
		body.freeze = true
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.transform = home
		m.position = Vector3.ZERO
		body.remove_meta("falling"))

func _bounce_pad(pos: Vector3) -> void:
	var pad := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.1
	cm.height = 0.25
	pad.mesh = cm
	pad.material_override = Toon.mat(Color("b388ff"))
	pad.position = pos
	add_child(pad)
	var area := Area3D.new()
	area.collision_mask = 2
	var ac := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 1.0
	cs.height = 0.6
	ac.shape = cs
	area.add_child(ac)
	area.position = pos + Vector3(0, 0.3, 0)
	add_child(area)
	area.body_entered.connect(func(b):
		if b is Player:
			b._ignore_dv = 3
			b.linear_velocity = Vector3(b.linear_velocity.x, 13.5, -4.0)
			Game.play("jump", 0.05, 0.0)
			var tw := create_tween()
			pad.scale = Vector3(1.3, 0.4, 1.3)
			tw.tween_property(pad, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))

func _crates(pos: Vector3) -> void:
	for i in 3:
		var c := RigidBody3D.new()
		c.mass = 0.6
		c.collision_layer = 1
		c.collision_mask = 1 | 2 | 4
		add_child(c)
		c.position = pos + Vector3(0, 0.35 + i * 0.72, 0)
		var m := _model("brick")
		m.scale = Vector3.ONE * 0.7
		m.position = Vector3(0, -0.35, 0)
		c.add_child(m)
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3.ONE * 0.7
		col.shape = bs
		c.add_child(col)

func _checkpoint(pos: Vector3) -> void:
	var flag := _model("flag")
	flag.position = pos + Vector3(2.0, -0.35, 0)
	flag.scale = Vector3.ONE * 1.4
	add_child(flag)
	var area := Area3D.new()
	area.collision_mask = 2
	var ac := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(7, 3, 2)
	ac.shape = bs
	area.add_child(ac)
	area.position = pos
	add_child(area)
	area.body_entered.connect(func(b):
		if b is Player and b.checkpoint.distance_to(pos) > 0.5:
			b.checkpoint = pos
			Game.play("coin")
			var tw := create_tween()
			tw.tween_property(flag, "scale", Vector3.ONE * 2.0, 0.12)
			tw.tween_property(flag, "scale", Vector3.ONE * 1.4, 0.3).set_trans(Tween.TRANS_BACK)
			checkpoint_reached.emit(pos))

func _finish(pos: Vector3) -> void:
	for side in [-1, 1]:
		var f := _model("flag")
		f.position = pos + Vector3(side * 2.3, -0.35, 0)
		f.scale = Vector3.ONE * 2.2
		add_child(f)
	var area := Area3D.new()
	area.collision_mask = 2
	var ac := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(5, 3, 1.5)
	ac.shape = bs
	area.add_child(ac)
	area.position = pos
	add_child(area)
	area.body_entered.connect(func(b):
		if b is Player:
			finished.emit(), CONNECT_ONE_SHOT)

func _decor_grass(center: Vector3, n: int) -> void:
	for i in n:
		var g := _model("grass" if i % 2 else "grass-small")
		var a := i * TAU / n
		g.position = center + Vector3(cos(a) * 3.0, -0.25, sin(a) * 3.0)
		g.scale = Vector3.ONE * 1.5
		add_child(g)

func _clouds() -> void:
	for i in 14:
		var c := _model("cloud")
		c.position = Vector3(randf_range(-30, 30), randf_range(-12, -4), randf_range(-90, 10))
		c.scale = Vector3.ONE * randf_range(2.5, 5.0)
		add_child(c)

func _physics_process(delta: float) -> void:
	_t += delta
	for m in _movers:
		var body: AnimatableBody3D = m[0]
		var old: Transform3D = m[1].call(_t - delta)
		var new: Transform3D = m[1].call(_t)
		body.global_transform = new
		body.set_meta("hazard_vel", (new.origin - old.origin) / max(delta, 0.0001))
		var dq := (new.basis * old.basis.inverse()).get_rotation_quaternion()
		var ang: Vector3 = dq.get_axis() * dq.get_angle() / max(delta, 0.0001) if dq.get_angle() > 0.00001 else Vector3.ZERO
		body.set_meta("hazard_ang", ang)
