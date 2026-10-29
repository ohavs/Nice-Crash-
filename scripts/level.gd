class_name Level
extends Node3D
## Builds courses from real models (Kenney platformer/food/furniture/pirate
## kits). Race courses run along -Z; every piece is a small function so new
## courses are new combinations. Also records a waypoint path for the bots,
## start positions and brawler spawns.

signal finished(p: Player)

const M := "res://assets/kenney/models/%s.glb"

## Course list for the menu. mode: "race" (first to the flags) or
## "survival" (last one standing).
const COURSES := {
	"meadow": {"name": "SUNNY MEADOW", "theme": "meadow", "mode": "race", "color": Color("6fd36b"), "blurb": "Rolling pins, hammers, falling waffles"},
	"kitchen": {"name": "KITCHEN CHAOS", "theme": "kitchen", "mode": "race", "color": Color("ff8a4c"), "blurb": "Cleavers, toaster launchers, tomato avalanche"},
	"pirate": {"name": "CANNON COVE", "theme": "pirate", "mode": "race", "color": Color("4ea8ff"), "blurb": "Cannons, saws and veggie brawlers"},
	"waffle": {"name": "WAFFLE DROP", "theme": "kitchen", "mode": "survival", "color": Color("ffc93c"), "blurb": "Tiles fall when touched. Last one standing!"},
}

var course := "meadow"
var mode := "race"
var length := 100.0
var path: Array[Vector3] = []
var starts: Array[Vector3] = []
## [position, radius, skin]
var guards: Array = []

var _movers: Array = []   # [body, callable(t) -> Transform3D]
var _spinners: Array = [] # [node, axis, speed] purely visual spin
var _boxes: Array = []    # item boxes: [node, area, base_y, cooldown]
var _tiles: Array = []    # survival tiles: [body, home, state]
var _cannons: Array = []  # [pivot, muzzle, timer, period]
var _rollers: Array = []  # [spawn_pos, half_width, timer, period, kind]
var _t := 0.0

func build(id: String) -> void:
	course = id
	mode = COURSES[id].mode
	match id:
		"kitchen":
			_course_kitchen()
		"pirate":
			_course_pirate()
		"waffle":
			_arena_waffle()
		_:
			_course_meadow()

# ================================================================ courses

func _course_meadow() -> void:
	var z := 0.0
	_start_pad("models/platform-grass-large-round", Vector3(0, 0, z), 2.0)
	z -= 10.0
	# 1: rolling-pin sweeper
	_platform("models/platform-large", Vector3(0, 0, z), 1.8)
	_spinner(Vector3(0, 0.99, z), 8.0, 1.6, "food/rollingPin")
	_wp(Vector3(0, 1, z + 3)); _wp(Vector3(0, 1, z - 3))
	z -= 9.5
	# 2: hop gaps
	for i in 3:
		var x := sin(i * 1.7) * 1.5
		_platform("models/platform", Vector3(x, 0, z), 1.3)
		_wp(Vector3(x, 0.8, z))
		z -= 3.6
	z -= 1.5
	_platform("models/platform-large", Vector3(0, 0, z), 1.6)
	_checkpoint(Vector3(0, 0.9, z))
	_crates(Vector3(2.4, 0.9, z + 1.5))
	_item_box(Vector3(-2.0, 1.6, z))
	_wp(Vector3(0, 0.9, z))
	z -= 9.0
	# 3: meat-tenderizer hammers over a cutting-board bridge
	_board_bridge(Vector3(0, 0, z), 14.0)
	_hammer(Vector3(0, 6.5, z + 4.0), 0.0)
	_hammer(Vector3(0, 6.5, z - 1.5), PI * 0.5)
	_hammer(Vector3(0, 6.5, z - 6.0), PI)
	_wp(Vector3(0, 0.9, z + 5)); _wp(Vector3(0, 0.9, z - 5))
	z -= 11.0
	_platform("models/platform-large", Vector3(0, 0, z), 1.6)
	_checkpoint(Vector3(0, 0.9, z))
	_wp(Vector3(0, 0.9, z))
	z -= 7.5
	# 4: falling waffles
	for i in 4:
		var x := (i % 2) * 2.4 - 1.2
		_falling(Vector3(x, 0, z))
		_wp(Vector3(x, 0.6, z))
		z -= 3.4
	z -= 1.5
	_platform("models/platform-large", Vector3(0, 0, z), 1.6)
	_wp(Vector3(0, 0.9, z + 1))
	_bounce_pad(Vector3(0, 0.88, z - 2.0))
	_wp(Vector3(0, 0.9, z - 2.0))
	z -= 12.0
	# 5: high landing, loaf pushers and a broccoli bouncer
	_platform("models/platform-large", Vector3(0, 2.5, z), 2.0)
	_checkpoint(Vector3(0, 3.6, z + 3.0))
	_wp(Vector3(0, 3.5, z + 3))
	_pusher(Vector3(-5.5, 3.6, z - 1.5), 3.4, 0.0)
	_pusher(Vector3(5.5, 3.6, z - 3.5), -3.4, 1.4)
	guards.append([Vector3(1.5, 3.8, z - 0.5), 3.5, "broccoli"])
	_wp(Vector3(0, 3.5, z - 4))
	z -= 9.5
	_platform("models/platform-grass-large-round", Vector3(0, 2.5, z), 1.6)
	_finish(Vector3(0, 3.4, z))
	length = -z

func _course_kitchen() -> void:
	var z := 0.0
	_start_pad("food/plate", Vector3(0, 0, z), 10.0)
	z -= 10.5
	# 1: pizza turntable
	_turntable(Vector3(0, 0, z), 8.0, 0.7)
	_wp(Vector3(0, 0.6, z + 2.5)); _wp(Vector3(0, 0.6, z - 2.5))
	z -= 7.5
	_static_prop("food/cuttingBoard", Vector3(0, 0, z), Vector3(5.0, 6.0, 5.0))
	_checkpoint(Vector3(0, 0.6, z))
	_item_box(Vector3(1.6, 1.3, z - 1.0))
	_wp(Vector3(0, 0.6, z))
	z -= 6.5
	# 2: toaster launchers up to a high shelf
	_static_prop("food/cuttingBoard", Vector3(0, 0, z), Vector3(6.0, 6.0, 7.5))
	_wp(Vector3(-1.2, 0.8, z + 2.0))
	_toaster_launcher(Vector3(-1.3, 0.24, z - 0.5))
	_toaster_launcher(Vector3(1.4, 0.24, z - 0.9))
	z -= 9.0
	_static_prop("food/cuttingBoard", Vector3(0, 4.0, z), Vector3(5.5, 6.0, 7.0))
	_wp(Vector3(0, 4.6, z + 2)); _wp(Vector3(0, 4.6, z - 2))
	z -= 7.0
	# 3: cleaver alley
	_board_bridge(Vector3(0, 4.0, z - 2.0), 16.0)
	_cleaver(Vector3(0, 4.4, z + 3.0), 0.0)
	_cleaver(Vector3(0, 4.4, z - 2.0), 1.1)
	_cleaver(Vector3(0, 4.4, z - 7.0), 2.2)
	_wp(Vector3(0, 4.9, z + 4)); _wp(Vector3(0, 4.9, z - 9))
	z -= 13.0
	_static_prop("food/plate", Vector3(0, 4.0, z), Vector3(7.5, 2.6, 7.5))
	_checkpoint(Vector3(0, 4.6, z))
	_item_box(Vector3(-2.0, 5.3, z))
	_wp(Vector3(0, 4.6, z))
	z -= 5.5
	# 4: tomato avalanche up a tilted board
	var ramp_len := 16.0
	var rise := 4.0
	var ramp := _static_prop("food/cuttingBoard", Vector3(0, 4.0 + rise * 0.5 - 0.25, z - ramp_len * 0.5), Vector3(5.5, 6.0, ramp_len / 0.82))
	ramp.rotation.x = atan2(rise, ramp_len)
	_wp(Vector3(0, 5.0, z - 1)); _wp(Vector3(0, 4.6 + rise, z - ramp_len + 0.5))
	_rollers.append([Vector3(0, 4.0 + rise + 1.4, z - ramp_len - 0.5), 1.8, 1.0, 1.5, "roller"])
	z -= ramp_len + 4.0
	_static_prop("food/cuttingBoard", Vector3(0, 4.0 + rise, z), Vector3(6.0, 6.0, 7.0))
	_checkpoint(Vector3(0, 4.6 + rise, z + 1.5))
	_wp(Vector3(0, 4.6 + rise, z))
	guards.append([Vector3(0, 5.0 + rise, z - 1.0), 2.6, "eggplant"])
	z -= 8.0
	# 5: whisk spinners
	_static_prop("food/waffle", Vector3(0, 4.0 + rise, z), Vector3(28.0, 10.0, 28.0))
	_spinner(Vector3(0, 4.3 + rise, z), 8.0, -1.9, "food/whisk")
	_wp(Vector3(0, 4.6 + rise, z + 3)); _wp(Vector3(0, 4.6 + rise, z - 3))
	z -= 8.0
	_static_prop("food/cuttingBoard", Vector3(0, 4.0 + rise, z), Vector3(5.0, 6.0, 4.0))
	_bounce_pad(Vector3(0, 4.25 + rise, z))
	_wp(Vector3(0, 4.6 + rise, z))
	z -= 12.0
	_static_prop("food/plate", Vector3(0, 6.0 + rise, z), Vector3(9.0, 3.2, 9.0))
	_finish(Vector3(0, 7.0 + rise, z))
	length = -z

func _course_pirate() -> void:
	var z := 0.0
	_start_pad("models/platform-grass-large-round", Vector3(0, 0, z), 2.0)
	z -= 10.0
	# 1: cannon crossfire over three wide platforms
	for i in 3:
		_platform("models/platform-large", Vector3(0, 0, z), 1.4)
		_wp(Vector3(0, 0.9, z))
		if i < 2:
			_cannon(Vector3(-8.0 if i % 2 == 0 else 8.0, 0.0, z - 3.5))
		z -= 7.5
	_platform("models/platform-large", Vector3(0, 0, z), 1.6)
	_checkpoint(Vector3(0, 0.9, z))
	_item_box(Vector3(2.0, 1.6, z))
	_wp(Vector3(0, 0.9, z))
	z -= 9.0
	# 2: saw alley on a narrow plank
	_board_bridge(Vector3(0, 0, z - 2.0), 16.0)
	_saw(Vector3(0, 1.2, z + 3.0), 2.6, 0.0)
	_saw(Vector3(0, 1.2, z - 2.0), 2.6, 1.7)
	_saw(Vector3(0, 1.2, z - 7.0), 2.6, 3.1)
	_wp(Vector3(0, 0.9, z + 4)); _wp(Vector3(0, 0.9, z - 9))
	z -= 13.5
	_platform("models/platform-large", Vector3(0, 0, z), 1.6)
	_checkpoint(Vector3(0, 0.9, z))
	_wp(Vector3(0, 0.9, z))
	z -= 8.0
	# 3: barrel roll down the ramp
	var ramp := _static_prop("food/cuttingBoard", Vector3(0, 1.6, z - 6.0), Vector3(6.0, 6.0, 14.0))
	ramp.rotation.x = atan2(3.2, 11.5)
	_rollers.append([Vector3(0, 4.8, z - 12.6), 2.0, 0.5, 1.7, "barrel"])
	_wp(Vector3(0, 1.0, z)); _wp(Vector3(0, 3.8, z - 11))
	z -= 15.5
	# 4: brawler deck
	_platform("models/platform-large", Vector3(0, 2.6, z), 2.2)
	_checkpoint(Vector3(0, 3.6, z + 3.5))
	guards.append([Vector3(-1.8, 3.9, z), 4.0, "carrot"])
	guards.append([Vector3(1.8, 3.9, z - 1.5), 4.0, "eggplant"])
	_item_box(Vector3(-3.0, 4.3, z + 2.0))
	_item_box(Vector3(3.0, 4.3, z + 2.0))
	_cannon(Vector3(9.0, 2.6, z))
	_wp(Vector3(0, 3.6, z + 3)); _wp(Vector3(0, 3.6, z - 4))
	z -= 9.5
	# 5: hop across barrels-in-a-row
	for i in 3:
		var x := (i % 2) * 2.0 - 1.0
		_platform("models/platform", Vector3(x, 2.6, z), 1.2)
		_wp(Vector3(x, 3.4, z))
		z -= 3.5
	z -= 4.0
	_platform("models/platform-grass-large-round", Vector3(0, 2.6, z), 1.6)
	var chest := Props.sized("pirate/chest", 2.0)
	chest.position = Vector3(0, 3.1, z - 2.6)
	add_child(chest)
	_finish(Vector3(0, 3.5, z))
	length = -z

func _arena_waffle() -> void:
	# two layers of waffle tiles over the soup; tiles drop once stepped on
	var tile := 2.3
	for layer in 2:
		var n := 6 if layer == 0 else 7
		var y := 0.0 if layer == 0 else -6.0
		for ix in n:
			for iz in n:
				var p := Vector3((ix - (n - 1) * 0.5) * tile, y, (iz - (n - 1) * 0.5) * tile - 8.0)
				if Vector2(p.x, p.z + 8.0).length() > tile * n * 0.52:
					continue  # round off the corners
				_waffle_tile(p, tile)
	for i in 8:
		var a := i * TAU / 8.0
		starts.append(Vector3(cos(a) * 3.6, 1.2, sin(a) * 3.6 - 8.0))
	_item_box(Vector3(0, 1.4, -8.0))
	_item_box(Vector3(-4.0, 1.4, -4.5))
	_item_box(Vector3(4.0, 1.4, -11.5))
	length = 20.0

# ================================================================ pieces

func _model(id: String) -> Node3D:
	return Props.make(id)

func _wp(p: Vector3) -> void:
	path.append(p)

## StaticBody with a model and trimesh collision. `s` is the model scale.
func _static_prop(id: String, pos: Vector3, s: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	body.position = pos
	var m := _model(id)
	m.scale = s
	body.add_child(m)
	for mi: MeshInstance3D in Props.meshes(m):
		var col := CollisionShape3D.new()
		col.shape = mi.mesh.create_trimesh_shape()
		body.add_child(col)
		col.transform = body.global_transform.affine_inverse() * mi.global_transform
	return body

func _platform(id: String, pos: Vector3, s: float) -> StaticBody3D:
	return _static_prop(id, pos, Vector3.ONE * s)

## Start platform + a grid of start positions on it.
func _start_pad(id: String, pos: Vector3, s: float) -> void:
	var body: StaticBody3D
	if id == "food/plate":
		var k := s / Props.base_size(id).x
		body = _static_prop(id, pos, Vector3(k, k * 0.35, k))  # flattened: no wall-like rim
	else:
		body = _platform(id, pos, s)
	var top: float = pos.y + Props.base_size(id).y * (body.get_child(0) as Node3D).scale.y
	for row in 2:
		for i in 4:
			starts.append(Vector3((i - 1.5) * 1.95, top + 0.1, pos.z + 1.3 - row * 2.1))
	_wp(Vector3(0, top + 0.5, pos.z - 2.0))
	if course == "meadow":
		_decor_grass(Vector3(0, top - 0.05, pos.z), 8, 4.2)

func _board_bridge(pos: Vector3, length_: float) -> void:
	var size := Props.base_size("food/cuttingBoard")
	_static_prop("food/cuttingBoard", pos + Vector3(0, 0.45, 0), Vector3(3.4 / size.x, 9.0, length_ / size.z))

func _mover(body: AnimatableBody3D, fn: Callable) -> void:
	body.sync_to_physics = true
	body.collision_layer = 1
	add_child(body)
	_movers.append([body, fn])

## Model on a body with a box collider fitted to the scaled model.
func _prop_on(body: Node3D, id: String, s: Vector3, offset := Vector3.ZERO, rot := Basis()) -> Node3D:
	var m := _model(id)
	m.basis = rot.scaled(s) if rot != Basis() else Basis().scaled(s)
	m.position = offset
	body.add_child(m)
	return m

func _box_col(parent: Node3D, size: Vector3, offset := Vector3.ZERO) -> void:
	var c := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	c.shape = bs
	c.position = offset
	parent.add_child(c)

func _spinner(center: Vector3, length_: float, speed: float, id: String) -> void:
	var hub := _model("food/cheese")
	hub.scale = Vector3.ONE * 1.3
	hub.position = center
	add_child(hub)
	var hub_body := StaticBody3D.new()
	hub_body.position = center + Vector3(0, 0.15, 0)
	add_child(hub_body)
	var cs := CylinderShape3D.new()
	cs.radius = 0.5
	cs.height = 0.3
	var pc := CollisionShape3D.new()
	pc.shape = cs
	hub_body.add_child(pc)
	var bar := AnimatableBody3D.new()
	var base := Props.base_size(id)
	var s := length_ / base.x
	var thick := 0.6
	var m := _prop_on(bar, id, Vector3(s, thick / base.y, thick / base.z))
	m.position.y = -thick * 0.5
	_box_col(bar, Vector3(length_, thick, thick))
	_mover(bar, func(t): return Transform3D(Basis(Vector3.UP, t * speed), center + Vector3(0, 0.75, 0)))

func _hammer(pivot: Vector3, phase: float) -> void:
	var arm_len := 5.4
	var h := AnimatableBody3D.new()
	# tenderizer: handle along its x axis, head at the -x end -> point it down
	var base := Props.base_size("food/meatTenderizer")
	var s := arm_len / base.x
	var m := _model("food/meatTenderizer")
	m.basis = Basis(Vector3.BACK, PI * 0.5).scaled(Vector3(s, s, s * 0.6))
	m.position = Vector3(0, -arm_len * 0.5, 0)
	m.get_child(0).position.y -= base.y * 0.5
	h.add_child(m)
	_box_col(h, Vector3(1.4, 1.5, 1.6), Vector3(0, -arm_len + 0.7, 0))
	# gallows: two log posts and a log crossbeam
	for side in [-1, 1]:
		var pole := _log(pivot.y + 0.4)
		pole.rotation.x = PI * 0.5
		pole.position = Vector3(side * 2.3, pivot.y + 0.2, pivot.z)
		add_child(pole)
	var beam := _log(5.0)
	beam.rotation.y = PI * 0.5
	beam.position = pivot + Vector3(0, 0.1, 0)
	add_child(beam)
	_mover(h, func(t): return Transform3D(Basis(Vector3.FORWARD, sin(t * 1.9 + phase) * 1.15), pivot))

## Nature-kit log `len` metres long (along z), a sensible 0.45 m thick.
func _log(len: float) -> Node3D:
	var base := Props.base_size("nature/log")
	var m := _model("nature/log")
	var t := 0.45 / base.x
	m.scale = Vector3(t, t, len / base.z)
	m.get_child(0).position.y -= base.y * 0.5
	return m

func _pusher(start: Vector3, travel: float, phase: float) -> void:
	var p := AnimatableBody3D.new()
	var base := Props.base_size("food/loaf")
	var s := 2.0 / base.x
	var m := _prop_on(p, "food/loaf", Vector3.ONE * s, Vector3(0, -base.y * s * 0.5, 0), Basis(Vector3.UP, PI * 0.5))
	m.position.y = -base.y * s * 0.5
	_box_col(p, Vector3(base.z * s, base.y * s, base.x * s))
	_mover(p, func(t):
		var k := clampf(sin(t * 2.2 + phase) * 1.6, -1.0, 1.0) * 0.5 + 0.5
		return Transform3D(Basis(), start + Vector3(travel * k, 0, 0)))

## Rotating pizza you ride across.
func _turntable(pos: Vector3, diameter: float, speed: float) -> void:
	var b := AnimatableBody3D.new()
	b.set_meta("ride", true)
	var base := Props.base_size("food/pizza")
	var s := diameter / base.x
	var m := _model("food/pizza")
	m.scale = Vector3(s, s * 1.6, s)
	b.add_child(m)
	var cs := CylinderShape3D.new()
	cs.radius = diameter * 0.5
	cs.height = base.y * s * 1.6
	var c := CollisionShape3D.new()
	c.shape = cs
	c.position.y = cs.height * 0.5
	b.add_child(c)
	_mover(b, func(t): return Transform3D(Basis(Vector3.UP, t * speed), pos))

## Giant toaster: step on it and it pops you up and forward.
func _toaster_launcher(pos: Vector3) -> void:
	var k := 2.4 / Props.base_size("furniture/toaster").x
	var body := _static_prop("furniture/toaster", pos, Vector3(k, k * 0.75, k * 1.4))
	var top: float = Props.base_size("furniture/toaster").y * (body.get_child(0) as Node3D).scale.y
	var area := Area3D.new()
	area.collision_mask = 2
	var ac := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.2, 0.6, 1.2)
	ac.shape = bs
	area.add_child(ac)
	area.position = pos + Vector3(0, top + 0.3, 0)
	add_child(area)
	var m: Node3D = body.get_child(0)
	area.body_entered.connect(func(b):
		if b is Player and not b.is_crashed:
			b._ignore_dv = 4
			b.linear_velocity = Vector3(b.linear_velocity.x * 0.3, 11.5, -5.2)
			Game.play("ding", 0.05, -2.0 if b.is_human else -12.0)
			var tw := create_tween()
			var s := m.scale
			m.scale = Vector3(s.x * 1.15, s.y * 0.7, s.z * 1.15)
			tw.tween_property(m, "scale", s, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
	_wp(pos + Vector3(0, top + 0.6, 0))

## Cleaver that slams down across the board.
func _cleaver(pos: Vector3, phase: float) -> void:
	var b := AnimatableBody3D.new()
	b.set_meta("slam", true)
	var base := Props.base_size("food/cookingKnifeChopping")
	var length_ := 4.6
	var s := length_ / base.x
	# blade stands on its edge: model's flat side faces z
	var m := _model("food/cookingKnifeChopping")
	m.basis = Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(s, s, s * 2.5))
	m.get_child(0).position.y -= base.y * 0.5
	m.position.y = base.z * s * 0.5
	b.add_child(m)
	Props.tint(m, Color("7d879c"), 0.45)
	_box_col(b, Vector3(length_ * 0.78, base.z * s, 0.35), Vector3(length_ * 0.11, base.z * s * 0.5, 0))
	_mover(b, func(t):
		# hold up, slam down fast, rest, rise slowly
		var c := fmod(t * 0.55 + phase, 1.0)
		var h := 0.0
		if c < 0.45:
			h = 1.0
		elif c < 0.55:
			h = 1.0 - (c - 0.45) / 0.1
		elif c < 0.7:
			h = 0.0
		else:
			h = (c - 0.7) / 0.3
		return Transform3D(Basis(), pos + Vector3(0, h * 2.8, 0)))

func _saw(pos: Vector3, travel: float, phase: float) -> void:
	var b := AnimatableBody3D.new()
	var base := Props.base_size("platformer/saw")
	var s := 1.6 / base.y
	var m := _model("platformer/saw")
	m.scale = Vector3.ONE * s
	m.get_child(0).position.y -= base.y * 0.5
	b.add_child(m)
	_spinners.append([m, Vector3.RIGHT, 9.0])
	var cs := CylinderShape3D.new()
	cs.radius = 0.75
	cs.height = 0.3
	var c := CollisionShape3D.new()
	c.shape = cs
	c.rotation.z = PI * 0.5
	b.add_child(c)
	_mover(b, func(t): return Transform3D(Basis(), pos + Vector3(sin(t * 1.6 + phase) * travel * 0.5, 0, 0)))

## Pirate cannon on a rock: aims at the nearest racer and fires.
func _cannon(pos: Vector3) -> void:
	var rock := Props.sized("pirate/formationLarge_rock", 4.0)
	rock.position = pos + Vector3(0, -5.0, 0)
	add_child(rock)
	var stand := _platform("models/platform", pos + Vector3(0, -0.4, 0), 1.0)
	stand.position.y = pos.y - 0.55
	var pivot := Node3D.new()
	pivot.position = pos
	add_child(pivot)
	var gun := Props.sized("pirate/cannon", 1.8)
	gun.rotation.y = PI
	pivot.add_child(gun)
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0, 0.8, -1.2)
	pivot.add_child(muzzle)
	_cannons.append([pivot, muzzle, randf_range(1.0, 2.5), 2.6])

func _falling(pos: Vector3) -> void:
	var body := RigidBody3D.new()
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.collision_layer = 1
	body.mass = 5.0
	add_child(body)
	body.position = pos
	var base := Props.base_size("food/waffle")
	var m := _model("food/waffle")
	m.scale = Vector3(2.4 / base.x, 0.45 / base.y, 2.4 / base.z)
	body.add_child(m)
	var c := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.4, 0.45, 2.4)
	c.shape = bs
	c.position.y = 0.225
	body.add_child(c)
	var area := Area3D.new()
	area.collision_mask = 2
	var ac := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(2.2, 0.6, 2.2)
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
		for k in 5:
			tw.tween_property(m, "position:x", 0.06, 0.05)
			tw.tween_property(m, "position:x", -0.06, 0.05)
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

## Survival tile: shakes when touched, then drops for good.
func _waffle_tile(pos: Vector3, size: float) -> void:
	var body := RigidBody3D.new()
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.collision_layer = 1
	body.mass = 3.0
	add_child(body)
	body.position = pos
	var base := Props.base_size("food/waffle")
	var m := _model("food/waffle")
	m.scale = Vector3((size - 0.08) / base.x, 0.5 / base.y, (size - 0.08) / base.z)
	m.rotation.y = randi_range(0, 3) * PI * 0.5
	body.add_child(m)
	var c := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size - 0.08, 0.5, size - 0.08)
	c.shape = bs
	c.position.y = 0.25
	body.add_child(c)
	var area := Area3D.new()
	area.collision_mask = 2
	var ac := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(size - 0.3, 0.5, size - 0.3)
	ac.shape = ab
	ac.position.y = 0.7
	area.add_child(ac)
	body.add_child(area)
	var entry := [body, pos + Vector3(0, 0.5, 0), 0]
	_tiles.append(entry)
	area.body_entered.connect(func(_b):
		if entry[2] != 0:
			return
		entry[2] = 1
		Props.tint(m, Color("c0521c"), 0.45)  # going golden-brown = about to drop
		var tw := create_tween()
		for k in 4:
			tw.tween_property(m, "position:x", 0.05, 0.05)
			tw.tween_property(m, "position:x", -0.05, 0.05)
		await get_tree().create_timer(0.55).timeout
		entry[2] = 2
		body.freeze = false
		body.angular_velocity = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		await get_tree().create_timer(3.0).timeout
		body.queue_free())

## A tile to head for in survival: an untouched one near `from`, same layer.
func safe_spot(from: Vector3) -> Vector3:
	var best := from
	var best_score := -INF
	for e in _tiles:
		if e[2] != 0:
			continue
		var p: Vector3 = e[1]
		var d := Vector2(p.x - from.x, p.z - from.z).length()
		# prefer our own layer, a short hop away
		var score := -absf(d - 3.0) + randf() * 2.5 - absf(p.y - (from.y - 0.6)) * 3.0
		if score > best_score:
			best_score = score
			best = p
	return best

func _bounce_pad(pos: Vector3) -> void:
	var pad := Props.sized("food/fryingPan", 3.0)
	pad.position = pos
	pad.rotation.y = PI * 0.5
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
	var s := pad.scale
	area.body_entered.connect(func(b):
		if b is Player:
			b._ignore_dv = 3
			b.linear_velocity = Vector3(b.linear_velocity.x, 13.5, -4.0)
			Game.play("boing", 0.05, 0.0 if b.is_human else -12.0)
			var tw := create_tween()
			pad.scale = Vector3(s.x * 1.3, s.y * 0.4, s.z * 1.3)
			tw.tween_property(pad, "scale", s, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))

func _crates(pos: Vector3) -> void:
	for i in 3:
		var c := RigidBody3D.new()
		c.mass = 0.6
		c.collision_layer = 1
		c.collision_mask = 1 | 2 | 4 | 8
		add_child(c)
		c.position = pos + Vector3(0, 0.35 + i * 0.72, 0)
		var m := Props.sized("platformer/crate", 0.7)
		m.position = Vector3(0, -0.35, 0)
		c.add_child(m)
		_box_col(c, Vector3.ONE * 0.7)

## Present that hands out a random item (tomatoes, cookie blaster,
## watermelon, rolling pin).
func _item_box(pos: Vector3) -> void:
	var box := Props.sized("holiday/presentRound", 0.9)
	box.position = pos
	add_child(box)
	var area := Area3D.new()
	area.collision_mask = 2
	var ac := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.8
	ac.shape = sp
	area.add_child(ac)
	area.position = pos + Vector3(0, 0.4, 0)
	add_child(area)
	var entry := [box, area, pos.y, 0.0]
	_boxes.append(entry)
	area.body_entered.connect(func(b):
		if not b is Player or entry[3] > 0.0 or b.item != "" or b.is_enemy:
			return
		var keys := Player.ITEMS.keys()
		b.give_item(keys[randi() % keys.size()])
		entry[3] = 6.0
		box.visible = false
		Fx.burst(self, pos + Vector3(0, 0.4, 0), "holiday/presentRound", 6, 0.25, 5.0)
		Game.play("powerup", 0.05, -2.0 if b.is_human else -14.0))

func _checkpoint(pos: Vector3) -> void:
	var flag := _model("models/flag")
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
		if b is Player and not b.is_enemy and b.checkpoint.z > pos.z + 0.5:
			b.checkpoint = pos
			if b.is_human:
				Game.play("coin")
				var tw := create_tween()
				tw.tween_property(flag, "scale", Vector3.ONE * 2.0, 0.12)
				tw.tween_property(flag, "scale", Vector3.ONE * 1.4, 0.3).set_trans(Tween.TRANS_BACK))

func _finish(pos: Vector3) -> void:
	for side in [-1, 1]:
		var f := _model("models/flag")
		f.position = pos + Vector3(side * 2.3, -0.35, 0)
		f.scale = Vector3.ONE * 2.2
		add_child(f)
	var area := Area3D.new()
	area.collision_mask = 2
	var ac := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(6, 3, 1.5)
	ac.shape = bs
	area.add_child(ac)
	area.position = pos
	add_child(area)
	_wp(pos)
	_wp(pos + Vector3(0, 0, -3))
	area.body_entered.connect(func(b):
		if b is Player and not b.finished and not b.is_enemy:
			b.finished = true
			finished.emit(b))

func _decor_grass(center: Vector3, n: int, r: float) -> void:
	for i in n:
		var id := "nature/flower_redA" if i % 3 == 0 else ("nature/flower_yellowA" if i % 3 == 1 else "nature/grass_large")
		var g := Props.sized(id, 0.6)
		var a := i * TAU / n
		g.position = center + Vector3(cos(a) * r, 0, sin(a) * r)
		add_child(g)

# ================================================================ update

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
	_update_cannons(delta)
	_update_rollers(delta)

func _process(delta: float) -> void:
	for s in _spinners:
		(s[0] as Node3D).rotate(s[1], s[2] * delta)
	for e in _boxes:
		var box: Node3D = e[0]
		if e[3] > 0.0:
			e[3] -= delta
			if e[3] <= 0.0:
				box.visible = true
				box.scale = Vector3.ONE * 0.01
				var s := 0.9 / maxf(Props.base_size("holiday/presentRound").x, Props.base_size("holiday/presentRound").z)
				box.create_tween().tween_property(box, "scale", Vector3.ONE * s, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		box.rotation.y += delta * 1.5
		box.position.y = e[2] + sin(_t * 2.5 + e[2]) * 0.15

func _update_cannons(delta: float) -> void:
	for c in _cannons:
		var pivot: Node3D = c[0]
		var target: Player = null
		var best := 26.0
		for p: Player in get_tree().get_nodes_in_group("players"):
			if p.is_out or p.is_enemy or p.finished or p.is_held():
				continue
			var d := p.global_position.distance_to(pivot.global_position)
			if d < best:
				best = d
				target = p
		if target == null:
			continue
		# lead the target a little
		var aim := target.global_position + target.linear_velocity * 0.45
		var to := aim - pivot.global_position
		var yaw := atan2(-to.x, -to.z)
		pivot.rotation.y = lerp_angle(pivot.rotation.y, yaw, delta * 3.0)
		c[2] -= delta
		if c[2] <= 0.0:
			c[2] = c[3] + randf_range(-0.4, 0.6)
			var muzzle: Node3D = c[1]
			var flat := Vector3(to.x, 0, to.z)
			var t := clampf(flat.length() / 16.0, 0.4, 1.3)  # flight time
			var v := flat / t
			v.y = (to.y + 0.5 * 9.8 * t * t) / t
			Projectile.fire(self, "cannon", muzzle.global_position, v)
			Fx.burst(self, muzzle.global_position, "models/cloud", 6, 0.6, 3.0)
			Game.play("punch", 0.1, -6.0 if best < 14.0 else -14.0)
			var tw := pivot.create_tween()
			pivot.scale = Vector3(1.15, 0.9, 1.15)
			tw.tween_property(pivot, "scale", Vector3.ONE, 0.3)

func _update_rollers(delta: float) -> void:
	for r in _rollers:
		r[2] -= delta
		if r[2] <= 0.0:
			r[2] = r[3] + randf_range(-0.3, 0.4)
			var pos: Vector3 = r[0] + Vector3(randf_range(-r[1], r[1]), 0, 0)
			Projectile.fire(self, r[4], pos, Vector3(0, 0, 3.0))
