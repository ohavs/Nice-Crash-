class_name Bot
extends Node
## Drives a Player like a thumb on a joystick would.
##   race     - follow the course path, hop gaps, shove whoever is in the way,
##              throw items at players ahead
##   survive  - stay on the arena tiles, roam to fresh ones, pick fights
##   guard    - veggie brawler: patrol around home, charge and bonk racers

var mode := "race"
var level: Level
var home := Vector3.ZERO
var guard_radius := 5.0
## 0..1: how fast / sharp this bot is.
var skill := 0.8

var p: Player
var _lane := 0.0
var _stuck := 0.0
var _think := 0.0
var _jump_cd := 0.0
var _target: Player
var _wander := Vector3.ZERO

func _ready() -> void:
	p = get_parent()
	_lane = randf_range(-0.9, 0.9)
	p.move_speed *= lerpf(0.8, 0.97, skill)

func _physics_process(delta: float) -> void:
	if p.is_out or p.finished or p.is_held() or level == null:
		p.input_dir = Vector3.ZERO
		return
	_jump_cd -= delta
	_think -= delta
	match mode:
		"guard":
			_guard(delta)
		"survive":
			_survive(delta)
		_:
			_race(delta)

# ---------------------------------------------------------------- race

func _race(delta: float) -> void:
	var pos := p.global_position
	var target := _next_waypoint(pos)
	var to := target - pos
	to.y = 0
	var dir := to.normalized() if to.length() > 0.01 else Vector3.FORWARD
	# keep to our lane a little so the pack spreads out
	dir = (dir + dir.cross(Vector3.UP) * _lane * 0.25 * clampf(to.length() / 6.0, 0.0, 1.0)).normalized()
	p.input_dir = dir
	_hop(dir, target)
	_unstick(delta, dir)
	if _think <= 0.0:
		_think = randf_range(0.25, 0.5)
		_fight(14.0)

func _next_waypoint(pos: Vector3) -> Vector3:
	# first path point clearly ahead of us (the course runs towards -z)
	for w: Vector3 in level.path:
		if w.z < pos.z - 1.2:
			return w
	return level.path[-1] if not level.path.is_empty() else pos + Vector3.FORWARD

func _hop(dir: Vector3, target: Vector3) -> void:
	if _jump_cd > 0.0 or not p.is_grounded():
		return
	var pos := p.global_position
	var space := p.get_world_3d().direct_space_state
	# gap ahead?
	var ahead := pos + dir * 1.1
	var q := PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3.DOWN * 2.5, 1)
	var gap := space.intersect_ray(q).is_empty()
	# step up ahead?
	var climb := target.y > pos.y + 0.4 and Vector2(target.x - pos.x, target.z - pos.z).length() < 3.2
	if gap or climb or randf() < 0.004:
		p.jump_requested = true
		_jump_cd = 0.5

func _unstick(delta: float, dir: Vector3) -> void:
	var hv := Vector3(p.linear_velocity.x, 0, p.linear_velocity.z)
	if hv.length() < 0.6 and not p.is_crashed:
		_stuck += delta
		if _stuck > 0.8:
			p.jump_requested = true
			p.input_dir = (dir + dir.cross(Vector3.UP) * randf_range(-1, 1)).normalized()
			_stuck = 0.0
	else:
		_stuck = 0.0

## Use items on / shove the nearest player in front of us.
func _fight(range_: float) -> void:
	var best: Player
	var best_d := range_
	var fwd := p.forward()
	for o: Player in p.get_tree().get_nodes_in_group("players"):
		if o == p or o.is_out or o.is_held() or (o.is_enemy and p.is_enemy):
			continue
		var to := o.global_position - p.global_position
		var d := to.length()
		if d < best_d and fwd.dot(to.normalized()) > 0.5:
			best = o
			best_d = d
	if best == null:
		return
	if p.item != "":
		var reach := 2.0 if p.item == "pin" else 12.0
		if best_d < reach and randf() < 0.5 + skill * 0.4:
			p.action_requested = true
	elif best_d < 1.5 and randf() < 0.25 + skill * 0.3:
		p.action_requested = true

# ---------------------------------------------------------------- guard

func _guard(_delta: float) -> void:
	var pos := p.global_position
	if _think <= 0.0:
		_think = 0.4
		_target = null
		var best := guard_radius + 1.5
		for o: Player in p.get_tree().get_nodes_in_group("players"):
			if o.is_enemy or o.is_out or o.is_held():
				continue
			var d := (o.global_position - home).length()
			if d < best and absf(o.global_position.y - home.y) < 2.0:
				best = d
				_target = o
		if _target == null and (_wander == Vector3.ZERO or randf() < 0.3):
			var a := randf() * TAU
			_wander = home + Vector3(cos(a), 0, sin(a)) * guard_radius * 0.5
	var goal := _target.global_position if _target else _wander
	var to := goal - pos
	to.y = 0
	# don't wander off the platform edge
	if (pos - home).length() > guard_radius:
		to = home - pos
		to.y = 0
	p.input_dir = to.normalized() * (1.0 if _target else 0.45) if to.length() > 0.4 else Vector3.ZERO
	if _target and to.length() < 1.4:
		p.action_requested = true

# ---------------------------------------------------------------- survive

func _survive(delta: float) -> void:
	var pos := p.global_position
	if _think <= 0.0 or _wander == Vector3.ZERO:
		_think = randf_range(0.4, 0.9)
		_wander = level.safe_spot(pos)
		_fight(10.0)
	var to := _wander - pos
	to.y = 0
	p.input_dir = to.normalized() if to.length() > 0.5 else Vector3.ZERO
	_hop(p.input_dir if p.input_dir != Vector3.ZERO else p.forward(), _wander)
	_unstick(delta, p.forward())
