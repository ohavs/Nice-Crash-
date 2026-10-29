class_name Bot
extends Node
## Drives a Player like a thumb on a joystick would.
##   race     - adventure rival: follow the level route, hop gaps, ride rafts,
##              shove whoever is in the way, throw items at players ahead
##   coop     - adventure buddy: same route, never picks on its team, waits
##              up if it gets too far ahead of you
##   survive  - party: stay on the arena, roam to safe spots, pick fights
##   koth     - party: get on the hill and shove everyone else off it
##   brawl    - party: grab items, hunt the nearest player
##   guard    - veggie brawler: patrol around home, charge and bonk players

var mode := "race"
var level: Level
var home := Vector3.ZERO
var guard_radius := 5.0
## 0..1: how fast / sharp this bot is.
var skill := 0.8
## coop: the player we travel with.
var buddy: Player

var p: Player
var _lane := 0.0
var _stuck := 0.0
var _think := 0.0
var _jump_cd := 0.0
var _target: Player
var _wander := Vector3.ZERO
var _s := 0.0
var _waited := 0.0
var _dare := 0.0

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
		"koth":
			_koth(delta)
		"brawl":
			_brawl(delta)
		_:
			_route(delta)

# ---------------------------------------------------------------- route

func _route(delta: float) -> void:
	var pos := p.global_position
	# progress may only creep forwards (no leaping to a later part that
	# happens to be close), but drops right back after a respawn
	_s = level.progress(pos, _s + 10.0)
	var i := level.waypoint_after(_s)
	var target := level.path[i]
	var to := target - pos
	to.y = 0
	var dir := to.normalized() if to.length() > 0.01 else p.forward()
	# keep to our lane a little so the pack spreads out
	dir = (dir + dir.cross(Vector3.UP) * _lane * 0.3 * clampf(to.length() / 6.0, 0.0, 1.0)).normalized()
	p.input_dir = dir
	if _ferry_wait():
		return
	if mode == "coop" and buddy and not buddy.finished and not buddy.is_out:
		var lead := _s - level.progress(buddy.global_position)
		if lead > 22.0 and p.is_grounded():
			p.input_dir = Vector3.ZERO  # wait for your friend
			return
	# hammer / saw about to be where we're stepping: hold back (unless
	# we're already in its way - then run)
	# (give up after a while and just go: some things never clear)
	_dare -= delta
	if _dare <= 0.0 and p.is_grounded() and level.danger_at(pos + dir * 1.8) and not level.danger_at(pos):
		_waited += delta
		if _waited < 2.5:
			p.input_dir = Vector3.ZERO
			_stuck = 0.0
			return
		_waited = 0.0
		_dare = 1.5
	else:
		_waited = 0.0
	_hop(dir, target)
	_unstick(delta, dir)
	if _think <= 0.0:
		_think = randf_range(0.25, 0.5)
		_fight(14.0)

## Rafts: wait at the dock until it's there, then stay on until it lands.
func _ferry_wait() -> bool:
	var pos := p.global_position
	for f in level.ferries:
		var body: Node3D = f[0]
		var a: Vector3 = f[1]
		var b: Vector3 = f[2]
		var at := body.global_position
		if p.ground_body() == body:
			if _flat(at - b).length() > 1.0:
				var to := at - pos
				to.y = 0
				p.input_dir = to * 0.6 if to.length() > 0.4 else Vector3.ZERO
				return true
			return false
		var near_a := _flat(pos - a).length() < 4.5 and absf(pos.y - a.y) < 2.5
		var heading_b := _flat(level.path[level.waypoint_after(_s)] - b).length() < _flat(level.path[level.waypoint_after(_s)] - a).length()
		if near_a and heading_b and _flat(at - a).length() > 1.2:
			# step back from the edge and wait
			var to := a - pos
			to.y = 0
			p.input_dir = -to.normalized() * 0.4 if to.length() < 3.0 else Vector3.ZERO
			return true
	return false

func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)

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
	if gap or climb or randf() < 0.004 or level.jump_hint(pos):
		p.jump_requested = true
		_jump_cd = 0.5

func _unstick(delta: float, dir: Vector3) -> void:
	var hv := Vector3(p.linear_velocity.x, 0, p.linear_velocity.z) - p.ground_velocity()
	if hv.length() < 0.6 and not p.is_crashed and p.input_dir.length() > 0.3:
		_stuck += delta
		if _stuck > 0.8:
			p.jump_requested = true
			p.input_dir = (dir + dir.cross(Vector3.UP) * randf_range(-1, 1)).normalized()
			_stuck = 0.0
	else:
		_stuck = 0.0

func _foe(o: Player) -> bool:
	if o == p or o.is_out or o.is_held():
		return false
	if o.is_enemy and p.is_enemy:
		return false
	if p.team >= 0 and o.team == p.team:
		return false
	return true

## Use items on / shove the nearest foe in front of us.
func _fight(range_: float, cone := 0.5) -> void:
	var best: Player
	var best_d := range_
	var fwd := p.forward()
	for o: Player in p.get_tree().get_nodes_in_group("players"):
		if not _foe(o):
			continue
		var to := o.global_position - p.global_position
		var d := to.length()
		if d < best_d and fwd.dot(to.normalized()) > cone:
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

func _nearest_foe(max_d: float) -> Player:
	var best: Player
	var best_d := max_d
	for o: Player in p.get_tree().get_nodes_in_group("players"):
		if not _foe(o):
			continue
		var d := o.global_position.distance_to(p.global_position)
		if d < best_d:
			best = o
			best_d = d
	return best

func _go(goal: Vector3, delta: float, slow_r := 0.5) -> void:
	var to := goal - p.global_position
	to.y = 0
	p.input_dir = to.normalized() if to.length() > slow_r else Vector3.ZERO
	_hop(p.input_dir if p.input_dir != Vector3.ZERO else p.forward(), goal)
	_unstick(delta, p.forward())

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

# ---------------------------------------------------------------- party

func _survive(delta: float) -> void:
	if _think <= 0.0 or _wander == Vector3.ZERO:
		_think = randf_range(0.4, 0.9)
		_wander = level.safe_spot(p.global_position)
		_fight(10.0)
	_go(_wander, delta)

func _koth(delta: float) -> void:
	if _think <= 0.0 or _wander == Vector3.ZERO:
		_think = randf_range(0.3, 0.7)
		var a := randf() * TAU
		_wander = level.center + Vector3(cos(a), 0, sin(a)) * level.radius * randf_range(0.0, 0.4)
		_target = _nearest_foe(4.0)
		_fight(8.0, 0.2)
	var goal := _wander
	# someone on the hill near us: go shove them
	if _target and _target.global_position.distance_to(level.center) < level.radius:
		goal = _target.global_position
		if goal.distance_to(p.global_position) < 1.4 and randf() < 0.1 + skill * 0.1:
			p.action_requested = true
	_go(goal, delta, 0.3)

func _brawl(delta: float) -> void:
	if _think <= 0.0 or _wander == Vector3.ZERO:
		_think = randf_range(0.3, 0.6)
		_target = _nearest_foe(40.0)
		_wander = Vector3.ZERO
		if p.item == "":
			var best := 9.0
			for b: Vector3 in level.item_boxes():
				var d := b.distance_to(p.global_position)
				if d < best:
					best = d
					_wander = b
		_fight(10.0, 0.6)
	var goal: Vector3 = _wander
	if goal == Vector3.ZERO:
		goal = _target.global_position if _target else level.safe_spot(p.global_position)
	# stay off the edge
	if _flat(goal - level.center).length() > level.radius * 0.85:
		goal = level.center
	_go(goal, delta, 0.3)
	if _target and _target.global_position.distance_to(p.global_position) < 1.4 and randf() < 0.08 + skill * 0.08:
		p.action_requested = true
