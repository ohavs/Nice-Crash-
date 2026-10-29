class_name Player
extends RigidBody3D
## Wobbly physics food character: stays upright while in control, goes full
## ragdoll ("crash") on hard impacts, floppy limbs on pin joints, can grab,
## shove, throw grabbed players and use items. The same class drives the
## human player, the racing bots and the veggie brawlers (see Bot).
##
## Skins are real Kenney Food Kit models. The egg cracks a bit more on every
## crash and splats into a fried egg on the third; toast pops out of a toaster
## whenever it (re)spawns and gets darker every time it crashes.

signal crashed(power: float)
signal recovered
signal splatted
signal eliminated
## Emitted on the attacker when one of its hits knocks someone over.
signal bonked(victim: Player, how: String)
signal item_changed(item: String, ammo: int)

const SKINS := {
	"egg": {"model": "food/egg", "name": "Eggbert", "height": 1.25, "tint": Color("fff0d2"), "tint_amt": 0.75, "pod": "food/eggCup"},
	"toast": {"model": "food/bread", "name": "Toasty", "height": 1.2, "stand": true, "turn": true, "thick": 3.2, "pod": "furniture/toaster"},
	"donut": {"model": "food/donutSprinkles", "name": "Donny", "height": 1.15, "stand": true, "thick": 1.4, "pod": "food/plate"},
	"burger": {"model": "food/burger", "name": "Burgz", "height": 1.1, "pod": "food/plate"},
	"cupcake": {"model": "food/cupcake", "name": "Cuppy", "height": 1.25, "pod": "food/plate"},
}
## Brawler enemies (not selectable).
const VEGGIES := {
	"broccoli": {"model": "food/broccoli", "name": "Brocc", "height": 1.4},
	"eggplant": {"model": "food/eggplant", "name": "Aubergine", "height": 1.45},
	"carrot": {"model": "food/carrot", "name": "Carrot", "height": 1.6},
}
const ITEMS := {
	"tomato": {"model": "food/tomato", "ammo": 3, "label": "THROW"},
	"cookie": {"model": "food/cookie", "ammo": 5, "label": "SHOOT"},
	"melon": {"model": "food/watermelon", "ammo": 1, "label": "THROW"},
	"pin": {"model": "food/rollingPin", "ammo": 3, "label": "BONK"},
}

@export var skin := "egg"
@export var move_speed := 5.5
@export var jump_speed := 6.8
@export var crash_threshold := 8.0

var display_name := ""
var is_human := false
var is_enemy := false
## false in survival rounds: falling off means you're out.
var respawn_enabled := true

var input_dir := Vector3.ZERO          # world-space, set by the controller each frame
var jump_requested := false
var grab_held := false
var action_requested := false

var is_crashed := false
var crash_timer := 0.0
var checkpoint := Vector3.ZERO
var finished := false
var is_out := false
var item := ""
var ammo := 0
var cracks := 0
var crash_count := 0

var _prev_vel := Vector3.ZERO
var _ignore_dv := 0
var _grounded := false
var _coyote := 0.0
var _air_time := 0.0
var _tilt_timer := 0.0
var _face_dir := Vector3.FORWARD
var _grab_joint: Joint3D
var _grabbed: Node
var _limbs: Array[RigidBody3D] = []
var _limb_offsets: Array[Vector3] = []
var visual: Node3D
var _body_model: Node3D
var _item_model: Node3D
var _waddle := 0.0
var _action_cd := 0.0
var _swing := 0.0
var _hold := false
var _hold_xf := Transform3D()
var _last_hit_by: Player
var _last_hit_time := -10.0
var _pod: Node3D
var _crack_mats: Array = []

func _ready() -> void:
	mass = 1.0
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = 2
	collision_mask = 1 | 2 | 8
	angular_damp = 1.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.25, 0)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.15
	physics_material_override = pm
	add_to_group("players")

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

static func skin_data(id: String) -> Dictionary:
	if SKINS.has(id):
		return SKINS[id]
	return VEGGIES.get(id, SKINS.egg)

# ---------------------------------------------------------------- visuals

func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	var data := skin_data(skin)
	if display_name == "":
		display_name = data.name
	var id: String = data.model
	_body_model = Props.make(id)
	var size := Props.base_size(id)
	var stand: bool = data.get("stand", false)
	var turn: bool = data.get("turn", false)  # crust is on the model's -x side: roll it to the top
	var tall: float = (size.x if turn else size.z) if stand else size.y
	var s: float = data.height / tall
	if stand:
		# lying models (bread slice, donut) stand up like a coin, face forward
		# (-90 deg about X: model z becomes height, model y becomes depth)
		var thick: float = data.get("thick", 1.0)
		var b := Basis(Vector3.RIGHT, -PI * 0.5)
		if turn:
			b = Basis(Vector3.BACK, -PI * 0.5) * b
		_body_model.basis = b.scaled(Vector3(s, s, s * thick))
		_body_model.get_child(0).position.y -= size.y * 0.5  # centre the depth
		_body_model.position.y = -0.575 + data.height * 0.5
	else:
		_body_model.scale = Vector3.ONE * s
		_body_model.position.y = -0.575
	visual.add_child(_body_model)
	if data.has("tint"):
		Props.tint(_body_model, data.tint, data.tint_amt)
	else:
		Props.tint(_body_model, Color.WHITE, 0.0)  # own materials so toasting/cracks stay per player
	var depth: float = (size.y * s * data.get("thick", 1.0)) if stand else size.z * s
	var width: float = (size.z if turn else size.x) * s
	_add_face(depth * 0.5, width, data.height)

func _add_face(front: float, width: float, height: float) -> void:
	var eye_r := clampf(width * 0.13, 0.09, 0.14)
	var eye_y := -0.575 + height * 0.62
	for side in [-1, 1]:
		var white := MeshInstance3D.new()
		var ws := SphereMesh.new()
		ws.radius = eye_r
		ws.height = eye_r * 2.0
		white.mesh = ws
		white.material_override = Toon.mat(Color.WHITE)
		white.position = Vector3(eye_r * 1.25 * side, eye_y, -front - eye_r * 0.35)
		visual.add_child(white)
		var pupil := MeshInstance3D.new()
		var ps := SphereMesh.new()
		ps.radius = eye_r * 0.46
		ps.height = eye_r * 0.92
		pupil.mesh = ps
		pupil.material_override = Toon.unshaded(Color(0.05, 0.05, 0.08))
		pupil.position = Vector3(0.0, 0.0, -eye_r * 0.7)
		white.add_child(pupil)
	var mouth := MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = eye_r * 0.45
	mm.height = eye_r * 0.45
	mouth.mesh = mm
	mouth.scale = Vector3(1.8, 0.6, 0.6)
	mouth.material_override = Toon.unshaded(Color("5a1f2b"))
	mouth.position = Vector3(0, eye_y - eye_r * 1.6, -front - 0.02)
	visual.add_child(mouth)

func add_name_tag(color: Color) -> void:
	var l := Label3D.new()
	l.text = display_name
	l.font = UI.font()
	l.font_size = 64
	l.pixel_size = 0.004
	l.outline_size = 18
	l.modulate = color
	l.outline_modulate = UI.INK
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	l.position.y = 1.05
	visual.add_child(l)

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

func _exit_tree() -> void:
	for l in _limbs:
		if is_instance_valid(l):
			l.queue_free()

# ---------------------------------------------------------------- physics

func _physics_process(delta: float) -> void:
	if is_out:
		return
	if _hold:
		_apply_hold()
		_animate_visual(delta)
		return
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

	_action_cd -= delta
	if is_crashed:
		crash_timer += delta
		if (crash_timer > 1.3 and linear_velocity.length() < 1.5) or crash_timer > 4.0:
			_recover()
	else:
		_control(delta)
	action_requested = false

	if global_position.y < -15.0:
		fell_off()

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
		Game.play("jump", 0.12, -6.0 if is_human else -14.0)
		_squash(Vector3(0.8, 1.3, 0.8))
	jump_requested = false

	if action_requested and _action_cd <= 0.0:
		_action()

func _check_ground() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.05, 1 | 2)
	q.exclude = [get_rid()]
	return not space.intersect_ray(q).is_empty()

func is_grounded() -> bool:
	return _grounded

func forward() -> Vector3:
	var f := -global_basis.z
	f.y = 0
	return f.normalized() if f.length() > 0.01 else _face_dir

# ---------------------------------------------------------------- crash

func _on_body_entered(b: Node) -> void:
	if is_crashed or _hold:
		return
	if not b is AnimatableBody3D or b.get_meta("ride", false):
		return
	# hazard velocity at contact point (works for sliding and rotating parts)
	var lin: Vector3 = b.get_meta("hazard_vel", Vector3.ZERO)
	var ang: Vector3 = b.get_meta("hazard_ang", Vector3.ZERO)
	var v := lin + ang.cross(global_position - b.global_position)
	if b.get_meta("slam", false) and v.y < -3.0:
		# cleaver coming down: squashed and flung sideways
		hit(Vector3(1.0 if randf() < 0.5 else -1.0, 0, 0) * 5.0 + Vector3.UP * 4.0)
		Game.play("chop", 0.1, 0.0 if is_human else -10.0)
		return
	v.y = 0
	if v.length() > 1.5:
		hit(v.normalized() * clampf(v.length(), 4.0, 9.0) * 0.9 + Vector3.UP * 3.5)

func crash(power: float) -> void:
	if is_crashed or is_out:
		return
	is_crashed = true
	crash_timer = 0.0
	crash_count += 1
	release_grab()
	# extra comedic spin
	apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * 0.25)
	Game.play("fall", 0.2, 0.0 if is_human else -10.0)
	# whoever hit us recently gets the credit
	if _last_hit_by and Time.get_ticks_msec() / 1000.0 - _last_hit_time < 1.2 and _last_hit_by != self:
		_last_hit_by.bonked.emit(self, "BONK")
	_skin_crash(power)
	crashed.emit(power)

## Knock this character over. `by` is the attacker (for credit), if any.
func hit(impulse: Vector3, by: Player = null) -> void:
	if is_out or _hold:
		return
	if by:
		_last_hit_by = by
		_last_hit_time = Time.get_ticks_msec() / 1000.0
	_ignore_dv = 2
	apply_central_impulse(impulse)
	crash(impulse.length() * 2.0)

## A shove that only knocks over someone already off balance.
func push(impulse: Vector3, by: Player = null) -> void:
	if is_out or _hold:
		return
	_last_hit_by = by
	_last_hit_time = Time.get_ticks_msec() / 1000.0
	_ignore_dv = 2
	apply_central_impulse(impulse)
	if not _grounded or is_crashed:
		crash(impulse.length() * 2.0)

func _recover() -> void:
	is_crashed = false
	_tilt_timer = 0.0
	_ignore_dv = 3
	angular_velocity *= 0.2
	linear_velocity.y = 3.5
	recovered.emit()

func fell_off() -> void:
	if not respawn_enabled:
		knock_out()
		return
	Game.play("splat", 0.1, -4.0 if is_human else -16.0)
	respawn()

## Out of the round (survival): vanish and stop simulating.
func knock_out() -> void:
	if is_out:
		return
	is_out = true
	release_grab()
	visible = false
	freeze = true
	for l in _limbs:
		l.visible = false
		l.freeze = true
	eliminated.emit()

func respawn(pod := true) -> void:
	release_grab()
	is_crashed = false
	_ignore_dv = 3
	if skin == "egg":
		cracks = 0
		_update_cracks()
	_show_body(true)
	var look := _face_dir if _face_dir.length() > 0.1 else Vector3.FORWARD
	var t := Transform3D(Basis.looking_at(look, Vector3.UP), checkpoint + Vector3.UP * 1.5)
	_teleport(t)
	if pod:
		hold_in_pod(t.origin, 0.45)

func _teleport(t: Transform3D) -> void:
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

# ---------------------------------------------------------------- spawn pods

## Sit inside this skin's spawner (toaster / egg cup / plate) at `ground`
## until launch(); `auto` > 0 launches by itself after that many seconds.
func hold_in_pod(ground: Vector3, auto := 0.0) -> void:
	var data := skin_data(skin)
	if _pod and is_instance_valid(_pod):
		_pod.queue_free()
	var pod_id: String = data.get("pod", "food/plate")
	# the toaster's slots run along its x axis, like the toast's width
	_pod = Props.sized(pod_id, 1.9 if pod_id == "furniture/toaster" else 1.6)
	get_parent().add_child(_pod)
	var floor_y := ground.y - 2.0
	var r := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(ground, ground + Vector3.DOWN * 4.0, 1))
	if not r.is_empty():
		floor_y = r.position.y
	var base := Vector3(ground.x, floor_y, ground.z)
	var look := _face_dir if _face_dir.length() > 0.1 else Vector3.FORWARD
	_pod.global_position = base
	_pod.rotation.y = Basis.looking_at(look, Vector3.UP).get_euler().y
	var s: Vector3 = _pod.scale
	_pod.scale = s * 0.01
	_pod.create_tween().tween_property(_pod, "scale", s, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# sunk into the pod, only the top peeks out: height of our feet above the floor
	var feet := {"furniture/toaster": 0.4, "food/eggCup": 0.75}.get(pod_id, 0.16) as float
	_hold_xf = Transform3D(Basis.looking_at(look, Vector3.UP), base + Vector3.UP * (feet + 0.575))
	_hold = true
	_apply_hold()
	if auto > 0.0:
		get_tree().create_timer(auto).timeout.connect(launch)

func _apply_hold() -> void:
	_teleport(_hold_xf)

## Pop out of the pod: toast flies out of the toaster with a ding.
func launch() -> void:
	if not _hold:
		return
	_hold = false
	_ignore_dv = 4
	var toaster := skin == "toast"
	linear_velocity = Vector3.UP * (9.0 if toaster else 6.0) + _face_dir * 1.2
	angular_velocity = Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)) if toaster else Vector3.ZERO
	if is_human or randf() < 0.3:
		Game.play("ding" if toaster else "pop", 0.08, -2.0 if is_human else -12.0)
	_squash(Vector3(0.7, 1.4, 0.7))
	var pod := _pod
	_pod = null
	if pod:
		var tw := pod.create_tween()
		tw.tween_interval(0.8)
		tw.tween_property(pod, "scale", pod.scale * 0.01, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(pod.queue_free)

func is_held() -> bool:
	return _hold

# ---------------------------------------------------------------- skin flavour

func _skin_crash(power: float) -> void:
	match skin:
		"egg":
			cracks += 2 if power >= 14.0 else 1
			Fx.burst(get_parent(), global_position, "food/eggHalf", 6, 0.12)
			if cracks >= 3:
				_splat()
			else:
				Game.play("crack", 0.1, 0.0 if is_human else -10.0)
				_update_cracks()
		"toast":
			# a little more toasted every time
			Props.tint(_body_model, Color("3a2412"), clampf(crash_count * 0.12, 0.0, 0.75))
			Fx.burst(get_parent(), global_position, "food/bread", 5, 0.1)
		_:
			Fx.burst(get_parent(), global_position, skin_data(skin).model, 4, 0.12)

func _show_body(on: bool) -> void:
	visual.visible = on
	for l in _limbs:
		for mi in Props.meshes(l):
			mi.visible = on

func _update_cracks() -> void:
	if _crack_mats.is_empty():
		for i in 2:
			var m := StandardMaterial3D.new()
			m.albedo_texture = load("res://assets/fx/crack%d.png" % (i + 1))
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.4
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(6, 6, 6)
			_crack_mats.append(m)
	for mi: MeshInstance3D in Props.meshes(_body_model):
		mi.material_overlay = null if cracks <= 0 else _crack_mats[mini(cracks, 2) - 1]

## Third crack: the shell bursts, a fried egg lands on the floor, and a fresh
## egg pops out of an egg cup at the checkpoint.
func _splat() -> void:
	Game.play("crack_big", 0.05, 0.0 if is_human else -8.0)
	Game.play("splat", 0.1, 0.0 if is_human else -10.0)
	_show_body(false)
	var parent := get_parent()
	# two shell halves fly off
	for k in 2:
		var shell := RigidBody3D.new()
		shell.collision_layer = 0
		shell.collision_mask = 1
		shell.mass = 0.2
		var m := Props.sized("food/eggHalf", 0.75)
		Props.tint(m, Color("fff0d2"), 0.75)
		if k == 1:
			m.rotation.x = PI
		shell.add_child(m)
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 0.3
		cs.shape = sp
		shell.add_child(cs)
		parent.add_child(shell)
		shell.global_position = global_position + Vector3(0, 0.3 * k, 0)
		shell.linear_velocity = Vector3(randf_range(-3, 3), 5.0 + k * 2.0, randf_range(-3, 3))
		shell.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		Fx.fade_out(shell, 2.5)
	# fried egg splat where we stand
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 4.0, 1)
	var r := space.intersect_ray(q)
	if not r.is_empty():
		var fried := Props.sized("food/eggCooked", 1.9)
		parent.add_child(fried)
		fried.global_position = r.position + Vector3.UP * 0.02
		fried.rotation.y = randf() * TAU
		fried.scale *= 0.2
		fried.create_tween().tween_property(fried, "scale", fried.scale * 5.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Fx.fade_out(fried, 4.0)
	splatted.emit()
	get_tree().create_timer(1.1).timeout.connect(func():
		if is_inside_tree() and not is_out:
			respawn())

# ---------------------------------------------------------------- actions

func give_item(id: String) -> void:
	item = id
	ammo = ITEMS[id].ammo
	if _item_model:
		_item_model.queue_free()
	_item_model = Props.sized(ITEMS[id].model, 0.55 if id != "pin" else 0.9)
	_item_model.position = Vector3(0.5, -0.05, -0.35)
	if id == "pin":
		_item_model.rotation = Vector3(0, PI * 0.5, 0)
	visual.add_child(_item_model)
	item_changed.emit(item, ammo)

func _use_ammo() -> void:
	ammo -= 1
	if ammo <= 0:
		item = ""
		if _item_model:
			_item_model.queue_free()
			_item_model = null
	item_changed.emit(item, ammo)

func _action() -> void:
	_swing = 1.0
	# 1) holding someone: YEET them
	if _grabbed is Player and is_instance_valid(_grabbed):
		var victim: Player = _grabbed
		release_grab()
		victim.hit(forward() * 9.0 + Vector3.UP * 6.0, self)
		Game.play("throw", 0.1, 0.0 if is_human else -8.0)
		_action_cd = 0.6
		return
	# 2) items
	if item != "":
		_use_item()
		return
	# 3) plain shove
	_action_cd = 0.55
	var hits := _bodies_in_front(0.75, 0.85)
	var any := false
	for b in hits:
		if b is Player and b != self:
			(b as Player).push(forward() * 5.5 + Vector3.UP * 1.8, self)
			any = true
		elif b is RigidBody3D:
			(b as RigidBody3D).apply_central_impulse(forward() * 3.0 + Vector3.UP * 1.0)
			any = true
	if any:
		Game.play("punch", 0.15, 0.0 if is_human else -8.0)
	else:
		Game.play("throw", 0.2, -10.0 if is_human else -20.0)

func _use_item() -> void:
	var f := forward()
	var origin := global_position + f * 0.7 + Vector3.UP * 0.35
	match item:
		"tomato":
			Projectile.fire(get_parent(), "tomato", origin, f * 13.0 + Vector3.UP * 3.5, self)
			_action_cd = 0.35
		"cookie":
			Projectile.fire(get_parent(), "cookie", origin, f * 19.0 + Vector3.UP * 1.2, self)
			_action_cd = 0.25
			Game.play("shoot", 0.1, -4.0 if is_human else -14.0)
		"melon":
			Projectile.fire(get_parent(), "melon", origin, f * 10.0 + Vector3.UP * 4.5, self)
			_action_cd = 0.6
		"pin":
			_action_cd = 0.5
			var landed := false
			for b in _bodies_in_front(1.0, 1.1):
				if b is Player and b != self:
					(b as Player).hit(f * 8.5 + Vector3.UP * 4.0, self)
					landed = true
			Game.play("bonk" if landed else "throw", 0.1, 0.0 if is_human else -8.0)
	if item != "pin":
		Game.play("throw", 0.1, -2.0 if is_human else -14.0)
	_use_ammo()

func _bodies_in_front(radius: float, dist: float) -> Array:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 2 | 8
	q.transform = Transform3D(Basis(), global_position + forward() * dist)
	var ex: Array[RID] = [get_rid()]
	for l in _limbs:
		ex.append(l.get_rid())
	q.exclude = ex
	var out := []
	for h in space.intersect_shape(q, 8):
		if not h.collider in out:
			out.append(h.collider)
	return out

# ---------------------------------------------------------------- grab

func _update_grab() -> void:
	if grab_held and _grab_joint == null and not is_crashed:
		_try_grab()
	elif (not grab_held or is_crashed) and _grab_joint != null:
		release_grab()
	elif _grabbed and not is_instance_valid(_grabbed):
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
	_grabbed = other
	if is_human:
		Game.play("coin", 0.1, -10.0)

func release_grab() -> void:
	if _grab_joint:
		_grab_joint.queue_free()
		_grab_joint = null
	_grabbed = null

func grabbing_player() -> bool:
	return _grabbed is Player

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
	# punch: body lunges and arms fling forward
	if _swing > 0.0:
		_swing = maxf(_swing - delta * 4.0, 0.0)
		visual.rotation.x = -sin(_swing * PI) * 0.35
		if _limbs.size() >= 2:
			for i in 2:
				_limbs[i].apply_central_force(forward() * 12.0 * _swing)
		if _item_model and item == "pin":
			_item_model.rotation.x = -sin(_swing * PI) * 1.6
