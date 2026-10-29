class_name Party
extends Level
## Party mode: everybody against everybody in short minigames you pick from a
## list. Every arena is centred on the origin.
##   survival - last one standing (falling off = out)
##   koth     - score a point per second while on the hill, 60 s
##   brawl    - most bonks in 60 s (falling off just respawns you)

const GAMES := {
	"waffle": {"name": "WAFFLE DROP", "mode": "survival", "theme": "kitchen", "color": Color("ffc93c"),
		"blurb": "Tiles fall when touched. Last one standing!"},
	"sumo": {"name": "PIZZA SUMO", "mode": "survival", "theme": "kitchen", "color": Color("ff8a4c"),
		"blurb": "A spinning pizza that keeps speeding up. Shove!"},
	"sweeper": {"name": "ROLLING PIN JUMP", "mode": "survival", "theme": "meadow", "color": Color("6fd36b"),
		"blurb": "Jump the rolling pins. They get faster..."},
	"cannons": {"name": "CANNON CHAOS", "mode": "survival", "theme": "pirate", "color": Color("4ea8ff"),
		"blurb": "Cannons fire at everyone. Don't get knocked off!"},
	"hill": {"name": "KING OF THE CHEESE", "mode": "koth", "theme": "meadow", "color": Color("ffd23f"),
		"blurb": "Stand on the cheese hill to score. 60 seconds"},
	"brawl": {"name": "TOMATO BRAWL", "mode": "brawl", "theme": "village", "color": Color("ff5a5f"),
		"blurb": "Grab presents, bonk everyone. Most bonks wins"},
}
## How long timed games (koth, brawl) last.
const ROUND_TIME := 60.0

## Rolling pins in the sweeper: [half length, angle fn(t)]
var _bars: Array = []

static func info(game_id: String) -> Dictionary:
	return GAMES.get(game_id, GAMES.waffle)

func build(game_id: String) -> void:
	id = game_id if GAMES.has(game_id) else "waffle"
	var g := info(id)
	mode = g.mode
	theme = g.theme
	_rng.seed = hash(id)
	section(Vector3.ZERO)
	match id:
		"sumo":
			_sumo()
		"sweeper":
			_sweeper()
		"cannons":
			_cannons_arena()
		"hill":
			_hill()
		"brawl":
			_brawl()
		_:
			_waffle()
	finalize()
	kill_y = -12.0

## Everyone on a ring around the middle, facing in.
func _ring_starts(r: float, y: float) -> void:
	for i in 8:
		var a := i * TAU / 8.0 + PI * 0.5
		starts.append(Vector3(cos(a) * r, y + 0.1, sin(a) * r))
	start_dir = Vector3.FORWARD

func _waffle() -> void:
	# two layers of waffle tiles over the soup; tiles drop once stepped on
	var tile := 2.5
	for layer in 2:
		var n := 8 if layer == 0 else 9
		var y := 0.0 if layer == 0 else -6.0
		for ix in n:
			for iz in n:
				var p := Vector3((ix - (n - 1) * 0.5) * tile, y, (iz - (n - 1) * 0.5) * tile)
				if Vector2(p.x, p.z).length() > tile * n * 0.52:
					continue  # round off the corners
				_drop_tile(p, tile)
	_ring_starts(4.6, 0.5)
	_item_box(Vector3(0, 1.4, 0))
	_item_box(Vector3(-5.0, 1.4, 4.4))
	_item_box(Vector3(5.0, 1.4, -4.4))
	radius = 9.0

func _sumo() -> void:
	var d := 18.5
	var base := Props.base_size("food/pizza")
	var h := base.y * d / base.x * 1.6
	var b := AnimatableBody3D.new()
	b.set_meta("ride", true)
	var m := _model("food/pizza")
	m.scale = Vector3(d / base.x, d / base.x * 1.6, d / base.z)
	b.add_child(m)
	_cyl_col(b, d * 0.5, h, Vector3(0, h * 0.5, 0))
	# speeds up over the round
	_mover(b, func(t): return Transform3D(Basis(Vector3.UP, 0.35 * t + 0.012 * t * t), Vector3(0, -h, 0)))
	_grow(Vector3(d * 0.5, 0, d * 0.5))
	_grow(Vector3(-d * 0.5, -h, -d * 0.5))
	_ring_starts(5.6, 0.0)
	_item_box(Vector3(-3.2, 1.2, 0))
	_item_box(Vector3(3.2, 1.2, 0))
	radius = d * 0.5

func _sweeper() -> void:
	var r := 11.0
	var island := "models/platform-grass-large-round"
	var base := Props.base_size(island)
	var k := r * 2.0 / base.x
	_static_prop(island, Vector3(0, -base.y * k * 0.4, 0), Vector3(k, k * 0.4, k))
	var top := 0.0
	var hub := _model("food/cheese")
	hub.scale = Vector3.ONE * 1.6
	hub.position = Vector3(0, top, 0)
	_root.add_child(hub)
	var hub_body := StaticBody3D.new()
	_root.add_child(hub_body)
	_cyl_col(hub_body, 0.8, 1.0, Vector3(0, top + 0.5, 0))
	# two pins: a long one that keeps speeding up, a shorter one the other way
	_pin(r * 2.0 + 1.0, top + 0.55, func(t): return 0.55 * t + 0.008 * t * t + PI / 8.0)
	_pin(r * 1.2, top + 0.55, func(t): return -0.35 * t - 0.005 * t * t + PI * 0.5 + PI / 8.0)
	_ring_starts(5.0, top)
	_item_box(Vector3(6.8, top + 1.2, 0))
	radius = r

func _pin(length_: float, y: float, angle: Callable) -> void:
	var bar := AnimatableBody3D.new()
	bar.set_meta("sweep", true)
	var base := Props.base_size("food/rollingPin")
	var thick := 0.5
	var m := _model("food/rollingPin")
	m.scale = Vector3(length_ / base.x, thick / base.y, thick / base.z)
	m.position.y = -thick * 0.5
	bar.add_child(m)
	_box_col(bar, Vector3(length_, thick, thick))
	_mover(bar, func(t): return Transform3D(Basis(Vector3.UP, angle.call(t)), Vector3(0, y, 0)))
	_bars.append([length_ * 0.5, angle])

func jump_hint(pos: Vector3) -> bool:
	if super.jump_hint(pos):
		return true
	var d := Vector2(pos.x, pos.z).length()
	var me := atan2(-pos.z, pos.x)  # same convention as Basis(UP, a) * +X
	for b in _bars:
		if d > b[0] + 0.4 or d < 0.8:
			continue
		var a: float = b[1].call(_t)
		var a2: float = b[1].call(_t + 0.28)
		# the bar is a full line: either end may be coming
		for off in [0.0, PI]:
			var now := wrapf(me - a - off, -PI, PI)
			var soon := wrapf(me - a2 - off, -PI, PI)
			if signf(now) != signf(soon) and absf(now) < 1.0:
				return randf() < 0.8
	return false

func _cannons_arena() -> void:
	_land(Vector3(0, 0, 0), 20, 20, "sand")
	_rim(Vector3.ZERO, 20, 20, ["platformer/barrel", "pirate/cannonBall", "nature/grass_large"], 8)
	for c in [Vector3(-4, 0, -4), Vector3(4.5, 0, 3.2)]:
		_crates(c, 2)
	for a in 4:
		var ang := a * TAU / 4.0 + PI * 0.25
		_cannon(Vector3(cos(ang) * 17.0, 0.5, sin(ang) * 17.0), 34.0, 2.2)
	_ring_starts(5.0, 0.0)
	_item_box(Vector3(0, 1.0, 0))
	radius = 10.0

func _hill() -> void:
	_land(Vector3(0, 0, 0), 27, 27)
	_rim(Vector3.ZERO, 27, 27, ["nature/flower_redA", "nature/flower_yellowA", "nature/grass_large", "nature/plant_bush"], 14)
	# the cheese hill in the middle, ramps on all four sides
	_slab("food/cheese", Vector3(0, 1.4, 0), 7.2, 7.2, 1.4)
	for i in 4:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, i * PI * 0.5)
		_ramp(dir * 7.6, dir * 3.5 + Vector3(0, 1.4, 0), 3.4)
	_ring_starts(10.0, 0.0)
	for a in 4:
		var ang := a * TAU / 4.0 + PI * 0.25
		_item_box(Vector3(cos(ang) * 8.6, 1.0, sin(ang) * 8.6))
	center = Vector3(0, 1.4, 0)
	radius = 3.6

func _brawl() -> void:
	_land(Vector3(0, 0, 0), 25, 25)
	_solid("town/fountainRound", Vector3(0, 0, 0), 4.6, 2.3, 0.6)
	_rim(Vector3.ZERO, 25, 25, ["town/lantern", "nature/plant_bush", "platformer/flowers", "nature/flower_yellowA"], 12)
	_crates(Vector3(-7.5, 0, 6), 2)
	_crates(Vector3(7.5, 0, -6), 2)
	_ring_starts(7.5, 0.0)
	for p in [Vector3(-6, 1, -6), Vector3(6, 1, 6), Vector3(-7.5, 1, 7.5), Vector3(7.5, 1, -7.5), Vector3(0, 1, 9)]:
		_item_box(p)
	radius = 12.5

## Survival waffle: a tile to head for, near `from` on the same layer.
func safe_spot(from: Vector3) -> Vector3:
	if _tiles.is_empty():
		return super.safe_spot(from)
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

## Is `pos` on the hill (king of the cheese)?
func on_hill(pos: Vector3) -> bool:
	return Vector2(pos.x, pos.z).length() < radius + 0.3 and pos.y > center.y - 0.2
