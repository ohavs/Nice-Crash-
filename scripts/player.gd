class_name Player
extends RigidBody3D
## Wobbly physics character: stays upright while in control, goes full
## ragdoll ("crash") on hard impacts, floppy limbs on pin joints, can grab.

signal crashed(power: float)
signal recovered

const SKINS := {
	"egg": {"color": Color("fff3dc"), "shape": "egg", "name": "Eggbert"},
	"toast": {"color": Color("e8a75a"), "shape": "toast", "name": "Toasty"},
	"marsh": {"color": Color("ffd0e4"), "shape": "marsh", "name": "Marshy"},
}

@export var skin := "egg"
@export var move_speed := 5.5
@export var jump_speed := 6.8
@export var crash_threshold := 8.0

var input_dir := Vector3.ZERO          # world-space, set by game each frame
var jump_requested := false
var grab_held := false

var is_crashed := false
var crash_timer := 0.0
var checkpoint := Vector3.ZERO

var _prev_vel := Vector3.ZERO
var _ignore_dv := 0
var _grounded := false
var _coyote := 0.0
var _air_time := 0.0
var _tilt_timer := 0.0
var _face_dir := Vector3.FORWARD
var _grab_joint: Joint3D
var _limbs: Array[RigidBody3D] = []
var _limb_offsets: Array[Vector3] = []
var visual: Node3D
var _waddle := 0.0

func _ready() -> void:
	mass = 1.0
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = 2
	collision_mask = 1 | 2
	angular_damp = 1.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.25, 0)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.15
	physics_material_override = pm

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.15
	col.shape = cap
	add_child(col)
	_build_visual()
	body_entered.connect(_on_body_entered)
	checkpoint = global_position
	if not freeze:
		call_deferred("_build_limbs")

# ---------------------------------------------------------------- visuals

func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	var data: Dictionary = SKINS.get(skin, SKINS.egg)
	var body := MeshInstance3D.new()
	match data.shape:
		"toast":
			var b := BoxMesh.new()
			b.size = Vector3(0.82, 1.05, 0.42)
			body.mesh = b
			# crust top
			var top := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.42
			c.bottom_radius = 0.42
			c.height = 0.42
			top.mesh = c
			top.rotation_degrees.x = 90
			top.position.y = 0.52
			top.material_override = Toon.mat(Color("b86b2e"))
			visual.add_child(top)
		"marsh":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.4
			cyl.bottom_radius = 0.44
			cyl.height = 1.1
			body.mesh = cyl
		_:
			var s := SphereMesh.new()
			s.radius = 0.43
			s.height = 1.2
			body.mesh = s
	body.material_override = Toon.mat(data.color)
	visual.add_child(body)

	# googly eyes
	for side in [-1, 1]:
		var white := MeshInstance3D.new()
		var ws := SphereMesh.new()
		ws.radius = 0.13
		ws.height = 0.26
		white.mesh = ws
		white.material_override = Toon.mat(Color.WHITE)
		white.position = Vector3(0.15 * side, 0.22, -0.36 if data.shape != "toast" else -0.22)
		visual.add_child(white)
		var pupil := MeshInstance3D.new()
		var ps := SphereMesh.new()
		ps.radius = 0.06
		ps.height = 0.12
		pupil.mesh = ps
		pupil.material_override = Toon.unshaded(Color(0.05, 0.05, 0.08))
		pupil.position = Vector3(0.0, 0.0, -0.09)
		pupil.set_meta("pupil", true)
		white.add_child(pupil)
	# little mouth
	var mouth := MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = 0.06
	mm.height = 0.06
	mouth.mesh = mm
	mouth.scale = Vector3(1.6, 0.6, 0.6)
	mouth.material_override = Toon.unshaded(Color("5a1f2b"))
	mouth.position = Vector3(0, 0.0, -0.4 if data.shape != "toast" else -0.22)
	visual.add_child(mouth)

func _make_limb(local_pos: Vector3, length: float, radius: float) -> RigidBody3D:
	var limb := RigidBody3D.new()
	limb.mass = 0.08
	limb.collision_layer = 4
	limb.collision_mask = 1
	limb.angular_damp = 3.0
	limb.linear_damp = 0.5
	limb.can_sleep = false
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = max(length, radius * 2.0)
	col.shape = cap
	col.position.y = -length * 0.5 + radius
	limb.add_child(col)
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = cap.height
	mi.mesh = cm
	mi.position = col.position
	mi.material_override = Toon.mat(Color("2b2b38"))
	limb.add_child(mi)
	get_parent().add_child(limb)
	limb.global_transform = global_transform * Transform3D(Basis(), local_pos)
	var pin := PinJoint3D.new()
	add_child(pin)
	pin.global_position = limb.global_position
	pin.node_a = get_path()
	pin.node_b = limb.get_path()
	_limbs.append(limb)
	_limb_offsets.append(local_pos)
	return limb

func _build_limbs() -> void:
	_make_limb(Vector3(-0.47, 0.05, 0), 0.42, 0.07)  # arms
	_make_limb(Vector3(0.47, 0.05, 0), 0.42, 0.07)
	_make_limb(Vector3(-0.18, -0.52, 0), 0.32, 0.08) # legs
	_make_limb(Vector3(0.18, -0.52, 0), 0.32, 0.08)

# ---------------------------------------------------------------- physics

func _physics_process(delta: float) -> void:
	var vel := linear_velocity
	var dv := (vel - _prev_vel).length()
	_prev_vel = vel
	if _ignore_dv > 0:
		_ignore_dv -= 1
	elif not is_crashed and dv > crash_threshold:
		crash(dv)

	_grounded = _check_ground()
	if _grounded:
		if _air_time > 0.35 and not is_crashed:
			Game.play("land", 0.1, -4.0)
			_squash(Vector3(1.25, 0.75, 1.25))
		_air_time = 0.0
		_coyote = 0.12
	else:
		_air_time += delta
		_coyote -= delta

	if is_crashed:
		crash_timer += delta
		if (crash_timer > 1.3 and linear_velocity.length() < 1.5) or crash_timer > 4.0:
			_recover()
	else:
		_control(delta)

	if global_position.y < -15.0:
		respawn()

	_update_grab()
	_animate_visual(delta)

func _control(delta: float) -> void:
	var up := global_basis.y
	# stay upright (PD controller)
	var tilt_axis := up.cross(Vector3.UP)
	var ang := angular_velocity
	var torque := tilt_axis * 9.0 - Vector3(ang.x, 0, ang.z) * 1.2
	# face movement direction
	var flat_in := Vector3(input_dir.x, 0, input_dir.z)
	if flat_in.length() > 0.1:
		_face_dir = flat_in.normalized()
	var fwd := -global_basis.z
	fwd.y = 0
	if fwd.length() > 0.01:
		var yaw_err := fwd.normalized().signed_angle_to(_face_dir, Vector3.UP)
		torque.y = yaw_err * 5.0 - ang.y * 0.8
	apply_torque(torque)

	# tipped too far for too long -> crash
	if up.angle_to(Vector3.UP) > deg_to_rad(65):
		_tilt_timer += delta
		if _tilt_timer > 0.35:
			crash(crash_threshold)
	else:
		_tilt_timer = 0.0

	# horizontal movement
	var target := flat_in.limit_length(1.0) * move_speed
	var hv := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var accel := 14.0 if _grounded else 5.0
	apply_central_force((target - hv) * accel * mass)

	if jump_requested and _coyote > 0.0:
		_ignore_dv = 2
		linear_velocity.y = jump_speed
		_coyote = 0.0
		Game.play("jump", 0.12, -6.0)
		_squash(Vector3(0.8, 1.3, 0.8))
	jump_requested = false

func _check_ground() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.05, 1)
	q.exclude = [get_rid()]
	return not space.intersect_ray(q).is_empty()

# ---------------------------------------------------------------- crash

func _on_body_entered(b: Node) -> void:
	if is_crashed or not b is AnimatableBody3D:
		return
	# hazard velocity at contact point (works for sliding and rotating parts)
	var lin: Vector3 = b.get_meta("hazard_vel", Vector3.ZERO)
	var ang: Vector3 = b.get_meta("hazard_ang", Vector3.ZERO)
	var v := lin + ang.cross(global_position - b.global_position)
	v.y = 0
	if v.length() > 1.5:
		hit(v.normalized() * clampf(v.length(), 4.0, 9.0) * 0.9 + Vector3.UP * 3.5)


func crash(power: float) -> void:
	if is_crashed:
		return
	is_crashed = true
	crash_timer = 0.0
	release_grab()
	# extra comedic spin
	apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * 0.25)
	Game.play("fall", 0.2)
	crashed.emit(power)

func hit(impulse: Vector3) -> void:
	_ignore_dv = 2
	apply_central_impulse(impulse)
	crash(impulse.length() * 2.0)

func _recover() -> void:
	is_crashed = false
	_tilt_timer = 0.0
	_ignore_dv = 3
	angular_velocity *= 0.2
	linear_velocity.y = 3.5
	recovered.emit()

func respawn() -> void:
	release_grab()
	is_crashed = false
	_ignore_dv = 3
	var t := Transform3D(Basis.looking_at(_face_dir if _face_dir.length() > 0.1 else Vector3.FORWARD, Vector3.UP), checkpoint + Vector3.UP * 1.5)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	global_transform = t
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_prev_vel = Vector3.ZERO
	for i in _limbs.size():
		var lt := t * Transform3D(Basis(), _limb_offsets[i])
		_limbs[i].global_transform = lt
		PhysicsServer3D.body_set_state(_limbs[i].get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, lt)
		_limbs[i].linear_velocity = Vector3.ZERO
		_limbs[i].angular_velocity = Vector3.ZERO

# ---------------------------------------------------------------- grab

func _update_grab() -> void:
	if grab_held and _grab_joint == null and not is_crashed:
		_try_grab()
	elif not grab_held and _grab_joint != null:
		release_grab()
	# arms reach forward while grabbing
	if grab_held and _limbs.size() >= 2:
		var reach := (-global_basis.z + Vector3.UP * 0.3).normalized()
		for i in 2:
			_limbs[i].apply_central_force(reach * 3.0)

func _try_grab() -> void:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.35
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1 | 2
	q.transform = Transform3D(Basis(), global_position - global_basis.z * 0.7 + Vector3.UP * 0.1)
	var ex: Array[RID] = [get_rid()]
	for l in _limbs:
		ex.append(l.get_rid())
	q.exclude = ex
	var hits := space.intersect_shape(q, 1)
	if hits.is_empty():
		return
	var other: Node = hits[0].collider
	if not other is PhysicsBody3D:
		return
	var j := PinJoint3D.new()
	add_child(j)
	j.global_position = global_position - global_basis.z * 0.55
	j.node_a = get_path()
	j.node_b = other.get_path()
	_grab_joint = j
	Game.play("coin", 0.1, -10.0)

func release_grab() -> void:
	if _grab_joint:
		_grab_joint.queue_free()
		_grab_joint = null

# ---------------------------------------------------------------- juice

func _squash(s: Vector3) -> void:
	var tw := create_tween()
	visual.scale = s
	tw.tween_property(visual, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _animate_visual(delta: float) -> void:
	var speed := Vector3(linear_velocity.x, 0, linear_velocity.z).length()
	if _grounded and not is_crashed and speed > 0.5:
		_waddle += delta * speed * 2.6
		visual.rotation.z = sin(_waddle) * 0.12
		visual.position.y = abs(sin(_waddle)) * 0.06
	else:
		visual.rotation.z = lerp(visual.rotation.z, 0.0, delta * 8.0)
		visual.position.y = lerp(visual.position.y, 0.0, delta * 8.0)
