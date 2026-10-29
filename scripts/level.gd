class_name Level
extends Node3D
## Base for every playable place: the piece library (land, bridges, hazards,
## items, coins, checkpoints, goal) plus the route bookkeeping that bots, the
## camera and race positions use. Built only from real models (Kenney
## platformer/nature/food/furniture/pirate/holiday kits).
##
## Pieces are authored inside a "section": section(origin, yaw) opens a frame
## whose local -Z is "onwards", so a level is a chain of sections that can turn
## anywhere. Adventure (the world levels) and Party (minigame arenas) extend
## this class.

signal finished(p: Player)
signal coin_collected(p: Player)
## Network: a coin / present was taken here (index), tell the others.
signal coin_taken(i: int)
signal box_taken(i: int)

var id := ""
## adventure (reach the goal) | survival (last one standing) |
## koth (score on the hill) | brawl (most bonks)
var mode := "adventure"
var theme := "meadow"
## Route through the level, in order (bots, camera heading, race places).
var path: Array[Vector3] = []
var starts: Array[Vector3] = []
var start_dir := Vector3.FORWARD
## [position, radius, skin]
var guards: Array = []
var coins_total := 0
## [body, dock_a, dock_b] (world) for every raft, so bots can ride them.
var ferries: Array = []
## Things bots wait for: [body, offset of the dangerous bit, radius, mover].
var hazards: Array = []
## Sweeping bars bots jump: [body, centre, half length, speed].
var sweepers: Array = []
## Arena centre / radius (party games: camera and bots).
var center := Vector3.ZERO
var radius := 10.0
## Players below this height have fallen off.
var kill_y := -15.0
## Extent of everything walkable (the backdrop keeps clear of it).
var bounds := AABB()

var _root: Node3D
var _frame := Transform3D.IDENTITY
var _yaw := 0.0
var _rng := RandomNumberGenerator.new()
var _path_s: Array[float] = []
var _checkpoints := 0
var _bounds_set := false

var _movers: Array = []   # [body, callable(t) -> local Transform3D, frame]
var _spinners: Array = [] # [node, axis, speed] purely visual spin
var _boxes: Array = []    # item boxes: [node, area, base_y, cooldown]
var _coins: Array = []    # [node, base_y]
var _tiles: Array = []    # survival tiles: [body, home, state]
var _cannons: Array = []  # [pivot, muzzle, timer, period, range]
var _rollers: Array = []  # [spawn, lateral, timer, period, kind, velocity]
var _t := 0.0
## Network client: the host fires the cannons and rollers (we get copies).
var remote_hazards := false

func _init() -> void:
	_root = self

## Builds level `level_id`. Subclasses fill this in.
func build(level_id: String) -> void:
	id = level_id

## Call once building is done: route lengths and bounds.
func finalize() -> void:
	_path_s.clear()
	var acc := 0.0
	for i in path.size():
		if i > 0:
			acc += path[i].distance_to(path[i - 1])
		_path_s.append(acc)
	for p in path:
		_grow(p)
	bounds = bounds.grow(3.0)
	kill_y = minf(bounds.position.y - 10.0, -15.0)

# ================================================================ frames

## Opens a new section at `origin` (world) facing `yaw` (0 = towards -Z,
## +PI/2 = towards -X).
func section(origin: Vector3, yaw := 0.0) -> void:
	_yaw = yaw
	_frame = Transform3D(Basis(Vector3.UP, yaw), origin)
	_root = Node3D.new()
	_root.transform = _frame
	add_child(_root)

## Continues with a new section starting below local point `at` of the
## current one, turned by `turn` radians (positive = left). Heights stay
## absolute: the new frame sits at y = 0.
func next_section(at: Vector3, turn := 0.0) -> void:
	section(_g(Vector3(at.x, 0, at.z)), _yaw + turn)

## Local (section) point -> world.
func _g(p: Vector3) -> Vector3:
	return _frame * p

## Local direction -> world.
func _gd(d: Vector3) -> Vector3:
	return _frame.basis * d

func _grow(p: Vector3) -> void:
	if not _bounds_set:
		bounds = AABB(p, Vector3.ZERO)
		_bounds_set = true
	else:
		bounds = bounds.expand(p)

func _wp(p: Vector3) -> void:
	path.append(_g(p))

# ================================================================ route

func route_length() -> float:
	return _path_s[-1] if not _path_s.is_empty() else 0.0

## Distance along the route of the point nearest to `pos`, looking no
## further than `max_s`. Height counts extra so stacked parts of a level
## don't get mixed up.
func progress(pos: Vector3, max_s := INF) -> float:
	if path.size() < 2:
		return 0.0
	var best := INF
	var best_s := 0.0
	for i in path.size() - 1:
		if _path_s[i] > max_s:
			break
		var a := path[i]
		var b := path[i + 1]
		var ab := b - a
		var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var c := a + ab * t
		var d := ((pos - c) * Vector3(1, 2.5, 1)).length()
		if d < best:
			best = d
			best_s = _path_s[i] + ab.length() * t
	return best_s

func point_at(s: float) -> Vector3:
	if path.is_empty():
		return Vector3.ZERO
	s = clampf(s, 0.0, route_length())
	for i in path.size() - 1:
		if s <= _path_s[i + 1]:
			var seg := _path_s[i + 1] - _path_s[i]
			return path[i].lerp(path[i + 1], (s - _path_s[i]) / maxf(seg, 0.0001))
	return path[-1]

## Flat direction the route heads in around distance `s`.
func heading_at(s: float) -> Vector3:
	var d := point_at(s + 7.0) - point_at(s - 1.0)
	d.y = 0
	return d.normalized() if d.length() > 0.1 else start_dir

## Index of the first waypoint past distance `s`.
func waypoint_after(s: float) -> int:
	for i in _path_s.size():
		if _path_s[i] > s + 0.5:
			return i
	return path.size() - 1

## Where a bot should head in party games. Default: somewhere on the arena.
func safe_spot(_from: Vector3) -> Vector3:
	var a := randf() * TAU
	return center + Vector3(cos(a), 0, sin(a)) * radius * randf_range(0.0, 0.5)

## Should a bot standing at `pos` jump right now (a sweeper coming)?
func jump_hint(pos: Vector3) -> bool:
	for sw in sweepers:
		var body: Node3D = sw[0]
		var c: Vector3 = sw[1]
		var rel := Vector3(pos.x - c.x, 0, pos.z - c.z)
		if rel.length() > sw[2] + 0.5 or rel.length() < 0.6 or absf(pos.y - c.y) > 2.0:
			continue
		var bar := body.global_basis.x
		bar.y = 0
		var soon := bar.rotated(Vector3.UP, sw[3] * 0.28)
		# the bar is a full line through the hub: when either end sweeps past
		# us, we change sides of it
		if signf(bar.cross(rel).y) != signf(soon.cross(rel).y) and randf() < 0.85:
			return true
	return false

## Is something nasty (hammer head, saw) at `p` now or in the next ~0.8 s?
func danger_at(p: Vector3) -> bool:
	for h in hazards:
		var body: Node3D = h[0]
		if body.global_position.distance_to(p) > 9.0:
			continue
		var m: Array = h[3]
		for k in 4:
			var xf: Transform3D = (m[2] as Transform3D) * (m[1].call(_t + k * 0.25) as Transform3D)
			var head: Vector3 = xf * (h[1] as Vector3)
			if absf(head.y - p.y) < 2.2 and Vector2(head.x - p.x, head.z - p.z).length() < h[2]:
				return true
	return false

# ================================================================ helpers

func _model(id_: String) -> Node3D:
	return Props.make(id_)

func _deco(id_: String, pos: Vector3, size: float, yaw := -1.0) -> Node3D:
	var n := Props.sized(id_, size)
	n.position = pos
	n.rotation.y = _rng.randf() * TAU if yaw < 0.0 else yaw
	_root.add_child(n)
	return n

## Decoration scattered along the rim of a land rect (keeps the middle free).
func _rim(pos: Vector3, w: float, d: float, ids: Array, n: int, size_min := 0.6, size_max := 1.4) -> void:
	for i in n:
		var side := _rng.randi() % 4
		var u := _rng.randf_range(-0.45, 0.45)
		var inset := _rng.randf_range(0.5, 1.2)
		var p := pos
		match side:
			0: p += Vector3(u * w, 0, -d * 0.5 + inset)
			1: p += Vector3(u * w, 0, d * 0.5 - inset)
			2: p += Vector3(-w * 0.5 + inset, 0, u * d)
			_: p += Vector3(w * 0.5 - inset, 0, u * d)
		_deco(ids[_rng.randi() % ids.size()], p, _rng.randf_range(size_min, size_max))

## StaticBody with a model and trimesh collision. `s` is the model scale.
func _static_prop(id_: String, pos: Vector3, s: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	_root.add_child(body)
	body.position = pos
	var m := _model(id_)
	m.scale = s
	body.add_child(m)
	for mi: MeshInstance3D in Props.meshes(m):
		var col := CollisionShape3D.new()
		col.shape = mi.mesh.create_trimesh_shape()
		body.add_child(col)
		col.transform = body.global_transform.affine_inverse() * mi.global_transform
	var top := pos + Vector3(0, Props.base_size(id_).y * s.y, 0)
	_grow(_g(top))
	return body

func _platform(id_: String, pos: Vector3, s: float) -> StaticBody3D:
	return _static_prop(id_, pos, Vector3.ONE * s)

func _box_col(parent: Node3D, size: Vector3, offset := Vector3.ZERO) -> CollisionShape3D:
	var c := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	c.shape = bs
	c.position = offset
	parent.add_child(c)
	return c

func _cyl_col(parent: Node3D, r: float, h: float, offset := Vector3.ZERO) -> CollisionShape3D:
	var c := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = r
	cs.height = h
	c.shape = cs
	c.position = offset
	parent.add_child(c)
	return c

func _area(pos_global: Vector3, shape: Shape3D) -> Area3D:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var c := CollisionShape3D.new()
	c.shape = shape
	area.add_child(c)
	add_child(area)
	area.global_position = pos_global
	return area

func _cyl(r: float, h: float) -> CylinderShape3D:
	var cs := CylinderShape3D.new()
	cs.radius = r
	cs.height = h
	return cs

# ================================================================ land

const LAND := {
	"grass": "platformer/blockLarge",
	"snow": "platformer/blockSnowLarge",
	"ice": "platformer/blockSnowLarge",
	"stone": "nature/cliff_block_stone",
	"sand": "platformer/blockLarge",
}

## A slab of ground whose top centre is `pos` (local), `w` wide (x) and `d`
## deep (z). Box collision; "ice" is slippery.
func _land(pos: Vector3, w: float, d: float, kind := "grass", depth := 1.6) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	_root.add_child(body)
	body.position = pos
	var id_: String = LAND.get(kind, LAND.grass)
	var base := Props.base_size(id_)
	var m := _model(id_)
	m.scale = Vector3(w / base.x, depth / base.y, d / base.z)
	m.position.y = -depth
	body.add_child(m)
	match kind:
		"ice":
			Props.tint(m, Color("9fe4ff"), 0.45)
			body.set_meta("ice", true)
			var pm := PhysicsMaterial.new()
			pm.friction = 0.02
			body.physics_material_override = pm
		"sand":
			Props.tint(m, Color("f4d58d"), 0.55)
	_box_col(body, Vector3(w, depth, d), Vector3(0, -depth * 0.5, 0))
	for c in [Vector3(-w, 0, -d), Vector3(w, 0, d), Vector3(-w, 0, d), Vector3(w, 0, -d)]:
		_grow(_g(pos + c * 0.5))
	return body

## Flat slab of any model (cutting board, waffle, plate...) whose top centre
## is `pos`, `w` x `d` and `thick` deep. Box collision.
func _slab(id_: String, pos: Vector3, w: float, d: float, thick := 0.4) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	_root.add_child(body)
	body.position = pos
	var base := Props.base_size(id_)
	var m := _model(id_)
	m.scale = Vector3(w / base.x, thick / base.y, d / base.z)
	m.position.y = -thick
	body.add_child(m)
	_box_col(body, Vector3(w, thick, d), Vector3(0, -thick * 0.5, 0))
	for c in [Vector3(-w, 0, -d), Vector3(w, 0, d)]:
		_grow(_g(pos + c * 0.5))
	return body

## Walkable strip from local point `a` to `b` (tops), `w` wide: a sloped
## block of land ("grass"/"snow"/...) or a plank walkway ("planks").
func _ramp(a: Vector3, b: Vector3, w: float, kind := "grass") -> StaticBody3D:
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	var len3 := a.distance_to(b)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	_root.add_child(body)
	body.position = (a + b) * 0.5
	body.basis = Basis(Vector3.UP, atan2(-flat.x, -flat.z)) * Basis(Vector3.RIGHT, atan2(b.y - a.y, flat.length()))
	var thick := 0.3 if kind == "planks" else 1.0
	var id_: String = "platformer/platform" if kind == "planks" else LAND.get(kind, LAND.grass)
	var base := Props.base_size(id_)
	var m := _model(id_)
	m.scale = Vector3(w / base.x, thick / base.y, (len3 + 0.3) / base.z)
	m.position.y = -thick
	body.add_child(m)
	if kind == "ice":
		Props.tint(m, Color("9fe4ff"), 0.45)
		body.set_meta("ice", true)
	_box_col(body, Vector3(w, thick, len3 + 0.3), Vector3(0, -thick * 0.5, 0))
	_grow(_g(a))
	_grow(_g(b))
	return body

## Fence-free plank bridge with posts and rope-ish rails of logs.
func _bridge(a: Vector3, b: Vector3, w := 2.6) -> void:
	_ramp(a, b, w, "planks")

## Something solid you have to go around (tree trunks, rocks, stalls).
func _solid(id_: String, pos: Vector3, size: float, r := 0.45, h := 3.0) -> Node3D:
	var n := _deco(id_, pos, size)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos
	_root.add_child(body)
	_cyl_col(body, r, h, Vector3(0, h * 0.5, 0))
	return n

func _start_pad(pos: Vector3) -> void:
	for i in 5:
		starts.append(_g(pos + Vector3((i - 2) * 1.9, 0.1, 0)))
	start_dir = _gd(Vector3.FORWARD)
	_wp(pos + Vector3(0, 0.5, -1.5))

# ================================================================ collectibles

func _coin(pos: Vector3) -> void:
	var gp := _g(pos)
	var c := Props.sized("models/coin", 0.7)
	add_child(c)
	c.global_position = gp
	var entry := [c, gp.y]
	var idx := _coins.size()
	_coins.append(entry)
	coins_total += 1
	var area := _area(gp + Vector3(0, 0.3, 0), _sphere(0.75))
	c.set_meta("area", area)
	area.body_entered.connect(func(b):
		if not b is Player or not b.is_human or not c.visible:
			return
		take_coin(idx)
		coin_taken.emit(idx)
		coin_collected.emit(b))

func take_coin(i: int) -> void:
	if i < 0 or i >= _coins.size():
		return
	var c: Node3D = _coins[i][0]
	if not c.visible:
		return
	c.visible = false
	(c.get_meta("area") as Area3D).set_deferred("monitoring", false)
	Fx.burst(self, c.global_position, "models/coin", 5, 0.2, 4.0)
	Game.play("coin", 0.1, -4.0)

func _sphere(r: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = r
	return s

func _coin_line(a: Vector3, b: Vector3, n: int) -> void:
	for i in n:
		_coin(a.lerp(b, i / maxf(n - 1.0, 1.0)) + Vector3.UP * 0.6)

## Coins along a jump arc from `a` to `b`.
func _coin_arc(a: Vector3, b: Vector3, n: int, h := 2.0) -> void:
	for i in n:
		var t := (i + 1.0) / (n + 1.0)
		_coin(a.lerp(b, t) + Vector3.UP * (0.6 + sin(t * PI) * h))

func _coin_ring(c: Vector3, r: float, n: int) -> void:
	for i in n:
		var a := i * TAU / n
		_coin(c + Vector3(cos(a) * r, 0.6, sin(a) * r))

## Present that hands out a random item (tomatoes, cookie blaster,
## watermelon, rolling pin).
func _item_box(pos: Vector3) -> void:
	var gp := _g(pos)
	var box := Props.sized("holiday/presentRound", 0.9)
	add_child(box)
	box.global_position = gp
	var area := _area(gp + Vector3(0, 0.4, 0), _sphere(0.8))
	var entry := [box, area, gp.y, 0.0]
	var idx := _boxes.size()
	_boxes.append(entry)
	area.body_entered.connect(func(b):
		if not b is Player or entry[3] > 0.0 or b.item != "" or b.is_enemy or b.puppet:
			return
		var keys := Player.ITEMS.keys()
		b.give_item(keys[randi() % keys.size()])
		take_box(idx)
		box_taken.emit(idx)
		Game.play("powerup", 0.05, -2.0 if b.is_human else -14.0))

func take_box(i: int) -> void:
	if i < 0 or i >= _boxes.size() or _boxes[i][3] > 0.0:
		return
	var entry: Array = _boxes[i]
	entry[3] = 6.0
	(entry[0] as Node3D).visible = false
	Fx.burst(self, (entry[0] as Node3D).global_position, "holiday/presentRound", 6, 0.25, 5.0)

func item_boxes() -> Array:
	return _boxes.filter(func(e): return e[3] <= 0.0).map(func(e): return (e[0] as Node3D).global_position)

func _crates(pos: Vector3, n := 3) -> void:
	for i in n:
		var c := RigidBody3D.new()
		c.add_to_group("grabbable")
		c.mass = 0.6
		c.collision_layer = 1
		c.collision_mask = 1 | 2 | 4 | 8
		_root.add_child(c)
		c.position = pos + Vector3(0, 0.35 + i * 0.72, 0)
		var m := Props.sized("platformer/crate", 0.7)
		m.position = Vector3(0, -0.35, 0)
		c.add_child(m)
		_box_col(c, Vector3.ONE * 0.7)

# ================================================================ checkpoints / goal

func _checkpoint(pos: Vector3) -> void:
	_checkpoints += 1
	var idx := _checkpoints
	var gp := _g(pos)
	var flag := _model("models/flag")
	flag.position = pos + Vector3(2.4, -0.35, 0)
	flag.scale = Vector3.ONE * 1.4
	_root.add_child(flag)
	var area := _area(gp + Vector3(0, 0.6, 0), _cyl(4.5, 4.0))
	area.body_entered.connect(func(b):
		if b is Player and not b.is_enemy and b.checkpoint_i < idx:
			b.checkpoint_i = idx
			b.checkpoint = gp
			if b.is_human:
				Game.play("coin")
				var tw := create_tween()
				tw.tween_property(flag, "scale", Vector3.ONE * 2.0, 0.12)
				tw.tween_property(flag, "scale", Vector3.ONE * 1.4, 0.3).set_trans(Tween.TRANS_BACK))

func _finish(pos: Vector3) -> void:
	for side in [-1, 1]:
		var f := _model("models/flag")
		f.position = pos + Vector3(side * 2.6, -0.35, 0)
		f.scale = Vector3.ONE * 2.2
		_root.add_child(f)
	var trophy := Props.sized("pirate/chest", 1.4)
	trophy.position = pos + Vector3(0, -0.35, -2.2)
	_root.add_child(trophy)
	var gp := _g(pos)
	var area := _area(gp + Vector3(0, 0.6, 0), _cyl(2.8, 3.0))
	_wp(pos)
	_wp(pos + Vector3(0, 0, -2))
	area.body_entered.connect(func(b):
		if b is Player and not b.finished and not b.is_enemy:
			b.finished = true
			Fx.burst(self, gp + Vector3(0, 1.0, 0), "models/coin", 14, 0.3, 7.0)
			finished.emit(b))

# ================================================================ movers

func _mover(body: AnimatableBody3D, fn: Callable) -> void:
	body.sync_to_physics = true
	body.collision_layer = 1
	add_child(body)
	body.global_transform = _frame * (fn.call(0.0) as Transform3D)
	_movers.append([body, fn, _frame])

## Rolling-pin (or whisk...) sweeper spinning around a cheese hub.
func _spinner(c: Vector3, length_: float, speed: float, id_: String, height := 0.75) -> void:
	var hub := _model("food/cheese")
	hub.scale = Vector3.ONE * 1.3
	hub.position = c
	_root.add_child(hub)
	var hub_body := StaticBody3D.new()
	hub_body.position = c + Vector3(0, 0.15, 0)
	_root.add_child(hub_body)
	_cyl_col(hub_body, 0.5, 0.3)
	var bar := AnimatableBody3D.new()
	var base := Props.base_size(id_)
	var thick := 0.6
	var m := _model(id_)
	m.scale = Vector3(length_ / base.x, thick / base.y, thick / base.z)
	m.position.y = -thick * 0.5
	bar.add_child(m)
	_box_col(bar, Vector3(length_, thick, thick))
	_mover(bar, func(t): return Transform3D(Basis(Vector3.UP, t * speed), c + Vector3(0, height, 0)))
	sweepers.append([bar, _g(c), length_ * 0.5, speed])

## Two rolling pins crossed, turning like a windmill across the path (they
## sweep the floor, so time your run through). The hub floats at `c`.
func _wheel(c: Vector3, arm: float, speed: float) -> void:
	var w := AnimatableBody3D.new()
	var base := Props.base_size("food/rollingPin")
	for k in 2:
		var m := _model("food/rollingPin")
		m.basis = Basis(Vector3.BACK, k * PI * 0.5).scaled(Vector3(arm * 2.0 / base.x, 0.55 / base.y, 0.55 / base.z))
		m.get_child(0).position.y -= base.y * 0.5
		w.add_child(m)
		var col := _box_col(w, Vector3(arm * 2.0, 0.5, 0.5))
		col.rotation.z = k * PI * 0.5
	var hub := Props.sized("food/cheese", 1.2)
	hub.rotation.x = PI * 0.5
	w.add_child(hub)
	_mover(w, func(t): return Transform3D(Basis(Vector3.BACK, t * speed), c))

func _hammer(pivot: Vector3, phase: float, speed := 1.9) -> void:
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
		pole.position = Vector3(side * 2.3 + pivot.x, pivot.y + 0.2, pivot.z)
		_root.add_child(pole)
	var beam := _log(5.0)
	beam.rotation.y = PI * 0.5
	beam.position = pivot + Vector3(0, 0.1, 0)
	_root.add_child(beam)
	_mover(h, func(t): return Transform3D(Basis(Vector3.FORWARD, sin(t * speed + phase) * 1.15), pivot))
	hazards.append([h, Vector3(0, -arm_len + 0.7, 0), 1.8, _movers[-1]])

## Nature-kit log `len` metres long (along z), a sensible 0.45 m thick.
func _log(len: float) -> Node3D:
	var base := Props.base_size("nature/log")
	var m := _model("nature/log")
	var t := 0.45 / base.x
	m.scale = Vector3(t, t, len / base.z)
	m.get_child(0).position.y -= base.y * 0.5
	return m

## Loaf that shoves sideways (along local x) and back.
func _pusher(start: Vector3, travel: float, phase: float) -> void:
	var p := AnimatableBody3D.new()
	var base := Props.base_size("food/loaf")
	var s := 2.0 / base.x
	var m := _model("food/loaf")
	m.basis = Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * s)
	m.position.y = -base.y * s * 0.5
	p.add_child(m)
	_box_col(p, Vector3(base.z * s, base.y * s, base.x * s))
	_mover(p, func(t):
		var k := clampf(sin(t * 2.2 + phase) * 1.6, -1.0, 1.0) * 0.5 + 0.5
		return Transform3D(Basis(), start + Vector3(travel * k, 0, 0)))

## Rotating pizza you ride across.
func _turntable(pos: Vector3, diameter: float, speed: float, thick := 1.6) -> AnimatableBody3D:
	var b := AnimatableBody3D.new()
	b.set_meta("ride", true)
	var base := Props.base_size("food/pizza")
	var s := diameter / base.x
	var m := _model("food/pizza")
	m.scale = Vector3(s, s * thick, s)
	b.add_child(m)
	var h := base.y * s * thick
	_cyl_col(b, diameter * 0.5, h, Vector3(0, h * 0.5, 0))
	_mover(b, func(t): return Transform3D(Basis(Vector3.UP, t * speed), pos))
	_grow(_g(pos + Vector3(diameter * 0.5, h, diameter * 0.5)))
	_grow(_g(pos - Vector3(diameter * 0.5, 0, diameter * 0.5)))
	return b

## Raft / floating block shuttling between local `a` and `b` (you ride it).
## Bots wait for it at `a` and stay on until it reaches `b`.
func _ferry(a: Vector3, b: Vector3, size: Vector2, period: float, phase := 0.0, id_ := "platformer/blockMoving") -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.set_meta("ride", true)
	var base := Props.base_size(id_)
	var m := _model(id_)
	var h := 0.5
	m.scale = Vector3(size.x / base.x, h / base.y, size.y / base.z)
	m.position.y = -h
	body.add_child(m)
	_box_col(body, Vector3(size.x, h, size.y), Vector3(0, -h * 0.5, 0))
	_mover(body, func(t):
		var k := 0.5 - cos(t * TAU / period + phase) * 0.5
		return Transform3D(Basis(), a.lerp(b, k)))
	_grow(_g(a))
	_grow(_g(b))
	ferries.append([body, _g(a), _g(b)])
	return body

## Giant toaster: step on it and it pops you up and onwards.
func _toaster_launcher(pos: Vector3, launch := Vector3(0, 11.5, -5.2)) -> void:
	var k := 2.4 / Props.base_size("furniture/toaster").x
	var body := _static_prop("furniture/toaster", pos, Vector3(k, k * 0.75, k * 1.4))
	var top: float = Props.base_size("furniture/toaster").y * (body.get_child(0) as Node3D).scale.y
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.2, 0.6, 1.2)
	var area := _area(_g(pos + Vector3(0, top + 0.3, 0)), bs)
	area.rotation.y = _yaw
	var m: Node3D = body.get_child(0)
	var v := _gd(launch)
	area.body_entered.connect(func(b):
		if b is Player and not b.is_crashed:
			b.fling(v + Vector3(b.linear_velocity.x, 0, b.linear_velocity.z) * 0.2)
			Game.play("ding", 0.05, -2.0 if b.is_human else -12.0)
			var tw := create_tween()
			var s := m.scale
			m.scale = Vector3(s.x * 1.15, s.y * 0.7, s.z * 1.15)
			tw.tween_property(m, "scale", s, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
	_wp(pos + Vector3(0, top + 0.6, 0))

## Cleaver that slams down across the floor (blade along local x).
func _cleaver(pos: Vector3, phase: float, length_ := 4.6) -> void:
	var b := AnimatableBody3D.new()
	b.set_meta("slam", true)
	var base := Props.base_size("food/cookingKnifeChopping")
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

## Saw blade sliding along local x.
func _saw(pos: Vector3, travel: float, phase: float, speed := 1.6) -> void:
	var b := AnimatableBody3D.new()
	var base := Props.base_size("platformer/saw")
	var s := 1.6 / base.y
	var m := _model("platformer/saw")
	m.scale = Vector3.ONE * s
	m.get_child(0).position.y -= base.y * 0.5
	b.add_child(m)
	_spinners.append([m, Vector3.RIGHT, 9.0])
	var c := _cyl_col(b, 0.75, 0.3)
	c.rotation.z = PI * 0.5
	_mover(b, func(t): return Transform3D(Basis(), pos + Vector3(sin(t * speed + phase) * travel * 0.5, 0, 0)))
	hazards.append([b, Vector3.ZERO, 1.4, _movers[-1]])

## Toy train crossing along local x from `from_x` to `to_x` (both off to the
## sides), then again after a pause. Getting hit sends you flying.
func _train(pos: Vector3, from_x: float, to_x: float, period: float, phase := 0.0) -> void:
	var b := AnimatableBody3D.new()
	var holder := Node3D.new()
	b.add_child(holder)
	var k := 8.0
	var x := 0.0
	for id_ in ["holiday/trainLocomotive", "holiday/trainWagon", "holiday/trainWagon"]:
		var m := _model(id_)
		var size := Props.base_size(id_)
		m.scale = Vector3.ONE * k
		m.position.x = x + size.x * k * 0.5
		holder.add_child(m)
		x += size.x * k + 0.15
	var dir := signf(to_x - from_x)
	if dir > 0.0:
		holder.rotation.y = PI  # locomotive leads towards +x
	_box_col(b, Vector3(x, 2.2, 1.5), Vector3(-dir * x * 0.5, 1.1, 0))
	b.set_meta("train", true)
	# rails
	for z in [-0.45, 0.45]:
		var r := _log(absf(to_x - from_x))
		r.rotation.y = PI * 0.5
		r.scale *= Vector3(0.35, 0.35, 1.0)
		r.position = pos + Vector3((from_x + to_x) * 0.5, 0.03, z)
		Props.tint(r, Color("8b93a8"), 0.7)
		_root.add_child(r)
	var travel := to_x + dir * x - from_x
	_mover(b, func(t):
		# drive across for 55% of the cycle, wait off-stage for the rest
		var u := clampf(fmod(t / period + phase, 1.0) / 0.55, 0.0, 1.0)
		return Transform3D(Basis(), pos + Vector3(from_x + travel * u, 0.0, 0)))

## Pirate cannon on a rock: aims at the nearest player and fires.
func _cannon(pos: Vector3, range_ := 26.0, period := 2.6) -> void:
	var rock := Props.sized("pirate/formationLarge_rock", 4.0)
	rock.position = pos + Vector3(0, -5.0, 0)
	_root.add_child(rock)
	var stand := _platform("models/platform", pos + Vector3(0, -0.55, 0), 1.0)
	stand.position.y = pos.y - 0.55
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.global_position = _g(pos)
	var gun := Props.sized("pirate/cannon", 1.8)
	gun.rotation.y = PI
	pivot.add_child(gun)
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0, 0.8, -1.2)
	pivot.add_child(muzzle)
	_cannons.append([pivot, muzzle, randf_range(1.0, 2.5), period, range_])

func _falling(pos: Vector3, id_ := "food/waffle", size := 2.4) -> void:
	var body := RigidBody3D.new()
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.collision_layer = 1
	body.mass = 5.0
	_root.add_child(body)
	body.position = pos
	var base := Props.base_size(id_)
	var m := _model(id_)
	m.scale = Vector3(size / base.x, 0.45 / base.y, size / base.z)
	body.add_child(m)
	_box_col(body, Vector3(size, 0.45, size), Vector3(0, 0.225, 0))
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var ab := BoxShape3D.new()
	ab.size = Vector3(size - 0.2, 0.6, size - 0.2)
	var ac := CollisionShape3D.new()
	ac.shape = ab
	ac.position.y = 0.7
	area.add_child(ac)
	body.add_child(area)
	var home := body.transform
	_grow(_g(pos))
	area.body_entered.connect(func(_b):
		if body.has_meta("falling"):
			return
		body.set_meta("falling", true)
		var tw := create_tween()
		for k in 5:
			tw.tween_property(m, "position:x", 0.06, 0.05)
			tw.tween_property(m, "position:x", -0.06, 0.05)
		await get_tree().create_timer(0.6).timeout
		if not is_instance_valid(body):
			return
		body.freeze = false
		Game.play("break", 0.1, -8.0)
		await get_tree().create_timer(3.5).timeout
		if not is_instance_valid(body):
			return
		body.freeze = true
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.transform = home
		m.position = Vector3.ZERO
		body.remove_meta("falling"))

## Survival tile: shakes when touched, then drops for good.
func _drop_tile(pos: Vector3, size: float, id_ := "food/waffle", tint := Color("c0521c")) -> void:
	var body := RigidBody3D.new()
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.collision_layer = 1
	body.mass = 3.0
	_root.add_child(body)
	body.position = pos
	var base := Props.base_size(id_)
	var m := _model(id_)
	m.scale = Vector3((size - 0.08) / base.x, 0.5 / base.y, (size - 0.08) / base.z)
	m.rotation.y = randi_range(0, 3) * PI * 0.5
	body.add_child(m)
	_box_col(body, Vector3(size - 0.08, 0.5, size - 0.08), Vector3(0, 0.25, 0))
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var ab := BoxShape3D.new()
	ab.size = Vector3(size - 0.3, 0.5, size - 0.3)
	var ac := CollisionShape3D.new()
	ac.shape = ab
	ac.position.y = 0.7
	area.add_child(ac)
	body.add_child(area)
	var entry := [body, _g(pos + Vector3(0, 0.5, 0)), 0]
	_tiles.append(entry)
	_grow(_g(pos))
	area.body_entered.connect(func(_b):
		if entry[2] != 0:
			return
		entry[2] = 1
		Props.tint(m, tint, 0.45)  # changing colour = about to drop
		var tw := create_tween()
		for k in 8:
			tw.tween_property(m, "position:x", 0.05, 0.05)
			tw.tween_property(m, "position:x", -0.05, 0.05)
		await get_tree().create_timer(1.0).timeout
		if not is_instance_valid(body):
			return
		entry[2] = 2
		body.freeze = false
		body.angular_velocity = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		await get_tree().create_timer(3.0).timeout
		if is_instance_valid(body):
			body.queue_free())

## Frying pan (or mushroom...) that bounces you up and onwards.
func _bounce_pad(pos: Vector3, launch := Vector3(0, 13.5, -4.0), id_ := "food/fryingPan", size := 3.0) -> void:
	var pad := Props.sized(id_, size)
	pad.position = pos
	pad.rotation.y = PI * 0.5
	_root.add_child(pad)
	var area := _area(_g(pos + Vector3(0, 0.3, 0)), _cyl(size * 0.34, 0.6))
	_bouncer(area, pad, launch)

## Big mushroom: the cap is a trampoline. Walk into it or land on it and
## it throws you up and onwards.
func _mushroom(pos: Vector3, height: float, width: float, launch := Vector3(0, 13.0, -4.0), id_ := "nature/mushroom_red") -> void:
	var base := Props.base_size(id_)
	var m := _model(id_)
	var sw := width / maxf(base.x, base.z)
	m.scale = Vector3(sw, height / base.y, sw)
	m.position = pos
	m.rotation.y = _rng.randf() * TAU
	_root.add_child(m)
	var body := StaticBody3D.new()
	body.position = pos
	_root.add_child(body)
	_cyl_col(body, width * 0.45, 0.5, Vector3(0, height - 0.3, 0))
	_cyl_col(body, width * 0.15, height, Vector3(0, height * 0.5, 0))
	var area := _area(_g(pos + Vector3(0, height + 0.1, 0)), _cyl(width * 0.55, 1.2))
	_bouncer(area, m, launch)
	_grow(_g(pos + Vector3(0, height, 0)))

func _bouncer(area: Area3D, visual: Node3D, launch: Vector3) -> void:
	var s := visual.scale
	var v := _gd(launch)
	area.body_entered.connect(func(b):
		if b is Player:
			b.fling(Vector3(v.x + b.linear_velocity.x * 0.3, v.y, v.z + b.linear_velocity.z * 0.3))
			Game.play("boing", 0.05, 0.0 if b.is_human else -12.0)
			var tw := create_tween()
			visual.scale = Vector3(s.x * 1.3, s.y * 0.5, s.z * 1.3)
			tw.tween_property(visual, "scale", s, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))

## Things rolling down at you from local `pos`, spread `half_w` sideways,
## rolling towards local +z.
func _roller_spawn(pos: Vector3, half_w: float, period: float, kind := "roller", speed := 3.0) -> void:
	_rollers.append([_g(pos), _gd(Vector3(half_w, 0, 0)), randf_range(0.2, period), period, kind, _gd(Vector3(0, 0, speed))])

# ================================================================ update

func _physics_process(delta: float) -> void:
	_t += delta
	for m in _movers:
		var body: AnimatableBody3D = m[0]
		var frame: Transform3D = m[2]
		var old: Transform3D = frame * (m[1].call(_t - delta) as Transform3D)
		var new: Transform3D = frame * (m[1].call(_t) as Transform3D)
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
	for c in _coins:
		var n: Node3D = c[0]
		if n.visible:
			n.rotation.y += delta * 3.0
			n.position.y = c[1] + sin(_t * 3.0 + n.position.x) * 0.12

func _update_cannons(delta: float) -> void:
	for c in _cannons:
		var pivot: Node3D = c[0]
		var target: Player = null
		var best: float = c[4]
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
		if c[2] <= 0.0 and not remote_hazards:
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
		if r[2] <= 0.0 and not remote_hazards:
			r[2] = r[3] + randf_range(-0.3, 0.4)
			var pos: Vector3 = r[0] + r[1] * randf_range(-1.0, 1.0)
			Projectile.fire(self, r[4], pos, r[5])
