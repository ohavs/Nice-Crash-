class_name Projectile
extends RigidBody3D
## Thrown / fired things: tomatoes (splat), cookies (fast, bouncy), watermelons
## (heavy), cannonballs (from pirate cannons) and rollers (big tomatoes that
## roll down ramps). Knocks over any player it hits, except its thrower.

const KINDS := {
	"tomato": {"model": "food/tomato", "size": 0.45, "radius": 0.22, "mass": 0.5, "power": 7.0, "splat": true, "life": 3.0},
	"cookie": {"model": "food/cookie", "size": 0.5, "radius": 0.2, "mass": 0.3, "power": 6.0, "splat": false, "life": 2.0},
	"melon": {"model": "food/watermelon", "size": 0.9, "radius": 0.42, "mass": 3.0, "power": 11.0, "splat": true, "life": 4.0},
	"cannon": {"model": "pirate/cannonBall", "size": 0.7, "radius": 0.35, "mass": 4.0, "power": 10.0, "splat": false, "life": 4.0},
	"roller": {"model": "food/tomato", "size": 1.8, "radius": 0.85, "mass": 6.0, "power": 9.0, "splat": false, "life": 14.0, "keep": true},
	"barrel": {"model": "platformer/barrel", "size": 1.5, "radius": 0.72, "mass": 6.0, "power": 9.0, "splat": false, "life": 14.0, "keep": true},
}

var kind := "tomato"
var thrower: Player
var _life := 0.0
var _done := false

static func fire(parent: Node, k: String, pos: Vector3, vel: Vector3, by: Player = null) -> Projectile:
	var p := Projectile.new()
	p.kind = k
	p.thrower = by
	parent.add_child(p)
	p.global_position = pos
	p.linear_velocity = vel
	p.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	if by:
		p.add_collision_exception_with(by)
	return p

func _ready() -> void:
	var d: Dictionary = KINDS[kind]
	collision_layer = 8
	collision_mask = 1 | 2 | 8
	mass = d.mass
	contact_monitor = true
	max_contacts_reported = 2
	continuous_cd = true
	var m := Props.sized(d.model, d.size)
	m.position.y = -d.size * Props.base_size(d.model).y / maxf(Props.base_size(d.model).x, Props.base_size(d.model).z) * 0.5
	add_child(m)
	move_child(m, 0)
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = d.radius
	cs.shape = sp
	add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.55 if kind == "cookie" else 0.2
	pm.friction = 0.6
	physics_material_override = pm
	body_entered.connect(_on_hit)

func _physics_process(delta: float) -> void:
	_life += delta
	if _life > KINDS[kind].life or global_position.y < -25.0:
		queue_free()

func _on_hit(b: Node) -> void:
	if _done:
		return
	var d: Dictionary = KINDS[kind]
	if b is Player and b != thrower:
		var v := linear_velocity
		if v.length() < 2.5:
			return  # resting / slow rollers don't knock people over
		var dir := Vector3(v.x, 0, v.z).normalized()
		(b as Player).hit(dir * d.power + Vector3.UP * 3.5, thrower)
		Game.play("splat" if d.splat else "bonk", 0.15, -2.0)
		if d.get("keep", false):
			return
		_pop()
	elif d.splat and linear_velocity.length() > 3.0:
		Game.play("splat", 0.2, -12.0)
		_pop()

func _pop() -> void:
	_done = true
	Fx.burst(get_parent(), global_position, KINDS[kind].model, 7, 0.16, 5.0)
	queue_free()
