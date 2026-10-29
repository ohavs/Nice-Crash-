class_name Enemy
extends CharacterBody3D
## KayKit skeletons roaming the open world. They guard a home spot, wake up
## when a player comes close, chase and swing at them (melee) or keep their
## distance and shoot (rogue: crossbow bolts, mage: flying skulls). Every
## hit knocks a heart off the player. Players hurt them back with shoves,
## items and thrown friends; at 0 HP they collapse into a pile of bones.
## On network clients they're puppets: the host runs the AI and streams
## their state (see net_state / net_apply).

signal died(e: Enemy, by: Player)

const KINDS := {
	"minion": {"model": "Skeleton_Minion", "hp": 3, "speed": 3.6, "height": 1.7, "weapon": "Skeleton_Blade",
		"attack": "1H_Melee_Attack_Chop", "range": 1.7, "hit_at": 0.42, "cooldown": 1.3, "name": "BONEHEAD"},
	"warrior": {"model": "Skeleton_Warrior", "hp": 5, "speed": 3.2, "height": 1.95, "weapon": "Skeleton_Axe",
		"shield": "Skeleton_Shield_Small_A", "attack": "1H_Melee_Attack_Chop", "range": 1.9, "hit_at": 0.42, "cooldown": 1.5, "name": "BONE KNIGHT"},
	"rogue": {"model": "Skeleton_Rogue", "hp": 3, "speed": 3.8, "height": 1.7, "weapon": "Skeleton_Crossbow",
		"attack": "1H_Ranged_Shoot", "range": 13.0, "keep": 7.0, "hit_at": 0.35, "cooldown": 2.2, "shot": "arrow", "name": "BONE ARCHER"},
	"mage": {"model": "Skeleton_Mage", "hp": 3, "speed": 3.0, "height": 1.75, "weapon": "Skeleton_Staff",
		"attack": "Spellcast_Shoot", "range": 12.0, "keep": 8.0, "hit_at": 0.5, "cooldown": 2.6, "shot": "skull", "name": "BONE MAGE"},
	"chief": {"model": "Skeleton_Warrior", "hp": 14, "speed": 3.4, "height": 2.8, "weapon": "Skeleton_Axe",
		"shield": "Skeleton_Shield_Small_A", "attack": "2H_Melee_Attack_Spin", "range": 2.8, "hit_at": 0.55, "cooldown": 1.6, "name": "BONE CHIEF"},
}
const GRAVITY := 9.8 * 1.5
const LOOPS := ["Idle", "Walking_D_Skeletons", "Running_C"]

var kind := "minion"
var hp := 2
var max_hp := 2
var home := Vector3.ZERO
## How far from home it will chase you.
var leash := 16.0
## Notices players this close.
var aggro := 10.0
## Mission this one counts for (OpenWorld), -1 = none.
var mission := -1
## false: stands lifeless until a player comes near, then gets up.
var awake := true
## Network client copy: the host drives it.
var puppet := false
## Network id (index in the level's enemy list).
var net_id := -1

var data: Dictionary
var _model: Node3D
var _anim: AnimationPlayer
var _state := "idle"   # idle | chase | attack | hurt | dead | waking
var _state_t := 0.0
var _cd := 0.0
var _target: Player
var _knock := Vector3.ZERO
var _attacked := false
var _wander := Vector3.ZERO
var _think := 0.0
var _invuln := 0.0
var _flash := 0.0
var _flash_mat: StandardMaterial3D
var _anim_name := ""
var _net_goal := Transform3D()
var _bar: Node3D
var _bar_fill: Node3D

func _ready() -> void:
	data = KINDS.get(kind, KINDS.minion)
	max_hp = data.hp
	hp = max_hp
	collision_layer = 2
	collision_mask = 1 | 2
	floor_snap_length = 0.5
	add_to_group("enemies")
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var h: float = data.height
	cap.radius = 0.42 * h / 1.7
	cap.height = h * 0.95
	col.shape = cap
	col.position.y = h * 0.48
	add_child(col)
	var id: String = "kaykit/skeletons/" + data.model
	_model = Props.make(id)
	var s: float = h / Props.base_size(id).y
	_model.scale = Vector3.ONE * s
	_model.rotation.y = PI  # KayKit characters face +z
	add_child(_model)
	_anim = _model.find_children("*", "AnimationPlayer", true, false)[0]
	for a in LOOPS:
		if _anim.has_animation(a):
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_attach(data.weapon, "handslot.r")
	if data.has("shield"):
		_attach(data.shield, "handslot.l")
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1, 1, 1, 0.0)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mi in Props.meshes(_model):
		mi.material_overlay = _flash_mat
	_build_bar()
	if not awake:
		_play("Skeletons_Awaken_Standing", 0.0)
		_anim.pause()
		_state = "dormant"
	else:
		_play("Idle")
	_wander = home

func _attach(weapon: String, bone: String) -> void:
	var sk: Skeleton3D = _model.find_children("*", "Skeleton3D", true, false)[0]
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	sk.add_child(ba)
	var w := Props.make("kaykit/skeletons/" + weapon)
	# the weapon models are built around the grip (KayKit hand slots)
	(w.get_child(0) as Node3D).position = Vector3.ZERO
	ba.add_child(w)

## Little health bar over the head (shows once hurt).
func _build_bar() -> void:
	_bar = Node3D.new()
	_bar.position.y = data.height + 0.35
	_bar.visible = false
	add_child(_bar)
	var back := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.14)
	back.mesh = q
	back.material_override = Toon.unshaded(UI.INK)
	(back.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_bar.add_child(back)
	_bar_fill = MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(0.82, 0.08)
	(_bar_fill as MeshInstance3D).mesh = q2
	var fm := Toon.unshaded(UI.CORAL)
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.render_priority = 1
	(_bar_fill as MeshInstance3D).material_override = fm
	_bar.add_child(_bar_fill)

func _play(a: String, blend := 0.15) -> void:
	if _anim_name == a or not _anim.has_animation(a):
		return
	_anim_name = a
	_anim.play(a, blend)

func is_dead() -> bool:
	return _state == "dead"

# ---------------------------------------------------------------- AI

func _physics_process(delta: float) -> void:
	_cd -= delta
	_invuln -= delta
	_state_t += delta
	if _flash > 0.0:
		_flash -= delta
		_flash_mat.albedo_color.a = clampf(_flash / 0.15, 0.0, 1.0) * 0.8
	if puppet:
		global_transform = global_transform.interpolate_with(_net_goal, minf(delta * 12.0, 1.0))
		return
	if _state == "dead":
		velocity.x = 0
		velocity.z = 0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	var want := Vector3.ZERO
	match _state:
		"dormant":
			if _nearest(aggro * 0.7):
				_state = "waking"
				_state_t = 0.0
				_anim.play("Skeletons_Awaken_Standing")
				_anim_name = "Skeletons_Awaken_Standing"
				Game.play("crack", 0.2, -6.0)
		"waking":
			if _state_t > 1.4:
				_state = "idle"
		"hurt":
			if _state_t > 0.45:
				_state = "idle"
		"attack":
			_attack_tick()
		_:
			want = _decide(delta)
	_knock = _knock.move_toward(Vector3.ZERO, delta * 14.0)
	velocity.x = want.x + _knock.x
	velocity.z = want.z + _knock.z
	velocity.y = velocity.y - GRAVITY * delta if not is_on_floor() else maxf(velocity.y, -0.5)
	move_and_slide()
	# face where we're going (or the target while shooting)
	var face := Vector3(want.x, 0, want.z)
	if _target and (_state == "attack" or data.has("keep")):
		face = _target.global_position - global_position
		face.y = 0
	if face.length() > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), minf(delta * 8.0, 1.0))
	if _state in ["idle", "chase"]:
		var sp := Vector2(velocity.x, velocity.z).length()
		_play("Idle" if sp < 0.4 else ("Running_C" if sp > data.speed * 0.8 else "Walking_D_Skeletons"))
	if global_position.y < -30.0:
		_die(null)

func _targetable(p: Player) -> bool:
	return not p.is_out and not p.is_enemy and not p.is_held() and p.max_hp > 0 and p.hp > 0

func _nearest(r: float) -> Player:
	var best: Player
	var best_d := r
	for o in get_tree().get_nodes_in_group("players"):
		var p := o as Player
		if p == null or not _targetable(p):
			continue
		var d := p.global_position.distance_to(global_position)
		if d < best_d and p.global_position.distance_to(home) < leash + aggro:
			best = p
			best_d = d
	return best

func _decide(delta: float) -> Vector3:
	_think -= delta
	if _think <= 0.0:
		_think = 0.3
		_target = _nearest(aggro if _target == null else aggro * 1.6)
		if _target == null and (randf() < 0.25 or _wander.distance_to(global_position) < 0.8):
			var a := randf() * TAU
			_wander = home + Vector3(cos(a), 0, sin(a)) * randf_range(0.0, 3.0)
	var speed: float = data.speed
	if _target == null or global_position.distance_to(home) > leash:
		_state = "idle"
		var to := _wander - global_position
		to.y = 0
		if global_position.distance_to(home) > leash:
			_target = null
			to = home - global_position
			to.y = 0
			return to.normalized() * speed
		return to.normalized() * speed * 0.35 if to.length() > 0.6 else Vector3.ZERO
	_state = "chase"
	var to := _target.global_position - global_position
	to.y = 0
	var d := to.length()
	var dir := to / maxf(d, 0.01)
	if _cd <= 0.0 and d < data.range and absf(_target.global_position.y - global_position.y) < 2.5:
		_start_attack()
		return Vector3.ZERO
	if data.has("keep"):
		# shooters keep their distance and circle a little
		var side := dir.cross(Vector3.UP) * sin(Time.get_ticks_msec() * 0.0007 + net_id)
		if d < data.keep - 1.0:
			return (-dir + side * 0.5).normalized() * speed * 0.8
		if d > data.range * 0.85:
			return dir * speed
		return side * speed * 0.4
	return dir * speed if d > data.range * 0.7 else Vector3.ZERO

func _start_attack() -> void:
	_state = "attack"
	_state_t = 0.0
	_attacked = false
	_cd = data.cooldown + randf_range(0.0, 0.5)
	_anim.play(data.attack, 0.1)
	_anim_name = data.attack
	if not data.has("shot"):
		Game.play("creak", 0.2, -12.0)

func _attack_tick() -> void:
	if not _attacked and _state_t >= data.hit_at:
		_attacked = true
		if data.has("shot"):
			_shoot()
		else:
			_swing()
	if _state_t > data.hit_at + 0.45:
		_state = "idle"

func _swing() -> void:
	var reach: float = data.range + 0.4
	var fwd := -global_basis.z
	Game.play("chop", 0.2, -6.0)
	for o in get_tree().get_nodes_in_group("players"):
		var p := o as Player
		if p == null or not _targetable(p):
			continue
		var to := p.global_position - global_position
		if absf(to.y) > 2.2:
			continue
		to.y = 0
		var spin := kind == "chief"
		if to.length() < reach and (spin or fwd.angle_to(to.normalized()) < 1.2):
			p.enemy_hit(to.normalized() * (9.0 if spin else 6.5) + Vector3.UP * 5.0)
			Fx.word(get_parent(), p.global_position + Vector3.UP * 1.0, ["WHACK!", "CLONK!", "OUCH!"].pick_random(), UI.CORAL)

func _shoot() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var origin: Vector3 = global_position + Vector3.UP * data.height * 0.7 - global_basis.z * 0.6
	var aim := _target.global_position + _target.linear_velocity * 0.35 + Vector3.UP * 0.2
	var to: Vector3 = aim - origin
	var flat := Vector3(to.x, 0, to.z)
	var speed := 13.0 if data.shot == "arrow" else 9.0
	var t := maxf(flat.length() / speed, 0.1)
	var v := flat / t
	var g := 0.4 if data.shot == "arrow" else 0.0  # bolts barely drop, skulls float
	v.y = (to.y + 0.5 * 9.8 * g * t * t) / t
	var pr := Projectile.fire(get_parent(), data.shot, origin, v)
	pr.add_collision_exception_with(self)
	Game.play("shoot" if data.shot == "arrow" else "pop", 0.15, -8.0)

# ---------------------------------------------------------------- damage

## A player (or their thrown stuff) hit us: knocked back, lose `dmg` HP.
func take_hit(dmg: int, dir: Vector3, by: Player = null) -> void:
	if _state == "dead" or _invuln > 0.0:
		return
	_invuln = 0.25
	if puppet:
		# the host decides; just show it here
		_flash = 0.15
		Net.send_enemy_hit(net_id, dmg, dir, by)
		return
	_apply_hit(dmg, dir, by)

func _apply_hit(dmg: int, dir: Vector3, by: Player) -> void:
	hp -= dmg
	_flash = 0.15
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	_knock = flat * (5.0 + dmg * 2.0)
	velocity.y = 3.0 + dmg * 1.2
	_bar.visible = true
	_bar_fill.scale.x = maxf(float(hp) / max_hp, 0.001)
	_bar_fill.position.x = -0.41 * (1.0 - _bar_fill.scale.x)
	Game.play("bonk", 0.15, -2.0)
	if _state == "dormant" or _state == "waking":
		awake = true
	if hp <= 0:
		_die(by)
		return
	_state = "hurt"
	_state_t = 0.0
	_anim.play("Hit_A", 0.05)
	_anim_name = "Hit_A"
	if by and _target == null:
		_target = by

func _die(by: Player) -> void:
	if _state == "dead":
		return
	_state = "dead"
	_bar.visible = false
	collision_layer = 0
	_anim.play("Death_C_Skeletons", 0.1)
	_anim_name = "Death_C_Skeletons"
	Game.play("crack_big", 0.15, -4.0)
	Fx.word(get_parent(), global_position + Vector3.UP * 1.6, ["SMASHED!", "BONES!", "KO!"].pick_random(), UI.YELLOW, 1.2)
	died.emit(self, by)
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_callback(func():
		Fx.burst(get_parent(), global_position + Vector3.UP * 0.6, "kaykit/halloween/bone_A", 8, 0.35, 5.0))
	tw.tween_property(_model, "scale", _model.scale * 0.01, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)

# ---------------------------------------------------------------- network

func net_state() -> Array:
	return [global_position, rotation.y, _anim_name, hp]

func net_apply(st: Array) -> void:
	_net_goal = Transform3D(Basis(Vector3.UP, st[1]), st[0])
	if st[2] != _anim_name and _anim.has_animation(st[2]):
		_anim_name = st[2]
		_anim.play(_anim_name, 0.12)
	if st[3] < hp:
		_bar.visible = true
		_flash = 0.15
	hp = st[3]
	_bar_fill.scale.x = maxf(float(hp) / max_hp, 0.001)
	_bar_fill.position.x = -0.41 * (1.0 - _bar_fill.scale.x)

## Host: a client's player hit this enemy.
func net_hit(dmg: int, dir: Vector3, by: Player) -> void:
	_invuln = 0.0
	_apply_hit(dmg, dir, by)

## Client: the host says it died.
func net_die() -> void:
	if _state != "dead":
		_state = "puppet_dead"
		_die(null)
