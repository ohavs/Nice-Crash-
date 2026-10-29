class_name Adventure
extends Level
## The world: levels you play in order, each in a different place and a bit
## bigger and nastier than the one before. Wide open ground (big slabs of
## land, side islands, several ways across) instead of narrow tracks, and the
## route turns as it goes. Coins reward exploring; the goal is a flag + chest.

const LEVELS := [
	{"id": "meadow", "name": "SUNNY MEADOW", "theme": "meadow", "color": Color("6fd36b"), "par": 75.0,
		"blurb": "Rolling pins, river stones and a big bouncy pan", "landmark": "nature/tree_oak"},
	{"id": "forest", "name": "MUSHROOM WOODS", "theme": "forest", "color": Color("b06ad8"), "par": 95.0,
		"blurb": "Bouncy mushrooms, rolling logs, a broccoli bully", "landmark": "nature/mushroom_red"},
	{"id": "village", "name": "WINDMILL VILLAGE", "theme": "village", "color": Color("ffb03b"), "par": 100.0,
		"blurb": "Market pushers, the windmill wheel, rooftop hops", "landmark": "town/windmill"},
	{"id": "kitchen", "name": "KITCHEN CHAOS", "theme": "kitchen", "color": Color("ff8a4c"), "par": 120.0,
		"blurb": "Toaster launchers, cleavers, a tomato avalanche", "landmark": "furniture/toaster"},
	{"id": "cove", "name": "CANNON COVE", "theme": "pirate", "color": Color("4ea8ff"), "par": 120.0,
		"blurb": "Cannon fire, rafts, saws and a pirate deck", "landmark": "pirate/ship_light"},
	{"id": "peaks", "name": "FROSTY PEAKS", "theme": "snow", "color": Color("9fe4ff"), "par": 150.0,
		"blurb": "Slippery ice, toy trains and a summit climb", "landmark": "holiday/snowmanFancy"},
]

const DECO := {
	"meadow": ["nature/flower_redA", "nature/flower_yellowA", "nature/flower_purpleA", "nature/grass_large", "nature/plant_bush", "nature/mushroom_redGroup", "platformer/flowers"],
	"forest": ["nature/mushroom_red", "nature/mushroom_tanTall", "nature/mushroom_redTall", "nature/stump_roundDetailed", "nature/plant_bushDetailed", "nature/flower_redB", "nature/grass_large"],
	"village": ["nature/plant_bush", "nature/flower_yellowA", "platformer/flowers", "town/lantern", "nature/grass_large", "platformer/crate"],
	"kitchen": ["food/tomato", "food/cheese", "food/sodaCan", "food/bottleKetchup", "food/cupcake", "food/pepper", "food/croissant"],
	"pirate": ["platformer/barrel", "platformer/crate", "pirate/cannonBall", "nature/grass_large", "nature/rock_largeA"],
	"snow": ["holiday/present", "holiday/candyCane", "holiday/candyCaneMint", "holiday/snowman", "holiday/sled", "holiday/rockFormationMedium"],
}
const TREES := {
	"meadow": ["nature/tree_oak", "nature/tree_default", "nature/tree_fat", "nature/tree_detailed"],
	"forest": ["nature/tree_pineRoundB", "nature/tree_pineDefaultA", "nature/tree_oak_fall", "nature/tree_default_fall", "nature/tree_pineTallA"],
	"village": ["town/treeHighRound", "nature/tree_oak", "nature/tree_default"],
	"kitchen": ["food/bottleKetchup", "food/sodaCan"],
	"pirate": ["pirate/palm_detailed_long", "nature/tree_palm"],
	"snow": ["holiday/treePineSnow", "holiday/treePineSnowRound"],
}

static func info(level_id: String) -> Dictionary:
	for l in LEVELS:
		if l.id == level_id:
			return l
	return LEVELS[0]

static func index_of(level_id: String) -> int:
	for i in LEVELS.size():
		if LEVELS[i].id == level_id:
			return i
	return 0

func build(level_id: String) -> void:
	id = level_id
	mode = "adventure"
	theme = info(level_id).theme
	_rng.seed = hash(level_id)
	match level_id:
		"forest":
			_forest()
		"village":
			_village()
		"kitchen":
			_kitchen()
		"cove":
			_cove()
		"peaks":
			_peaks()
		_:
			_meadow()
	finalize()

# ================================================================ dressing

func _dress(pos: Vector3, w: float, d: float, n := 6) -> void:
	_rim(pos, w, d, DECO[theme], n, 0.6, 1.5)

## Solid trees standing around the rim of a land slab.
func _trees(pos: Vector3, w: float, d: float, n := 3) -> void:
	var ids: Array = TREES[theme]
	for i in n:
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := pos + Vector3(side * (w * 0.5 - 1.0), 0, _rng.randf_range(-d * 0.4, d * 0.4))
		_solid(ids[_rng.randi() % ids.size()], p, _rng.randf_range(2.6, 4.2), 0.4)

## Kitchen surface: a giant cutting board.
func _board(pos: Vector3, w: float, d: float) -> StaticBody3D:
	return _slab("food/cuttingBoard", pos, w, d, 0.5)

## Pizza turntable whose top sits at `top`.
func _pizza(top: Vector3, diameter: float, speed: float) -> void:
	var base := Props.base_size("food/pizza")
	var h := base.y * diameter / base.x * 1.6
	_turntable(top - Vector3(0, h, 0), diameter, speed)

# ================================================================ 1 meadow

func _meadow() -> void:
	section(Vector3.ZERO)
	# start meadow
	_land(Vector3(0, 0, -2), 16, 16)
	_start_pad(Vector3(0, 0, 2))
	_trees(Vector3(0, 0, -2), 16, 16, 4)
	_dress(Vector3(0, 0, -2), 16, 16, 10)
	_coin_line(Vector3(-5.5, 0, 0), Vector3(-5.5, 0, -8), 4)
	# 1: wide path with a rolling-pin sweeper
	_land(Vector3(0, 0, -19), 11, 18)
	_dress(Vector3(0, 0, -19), 11, 18, 6)
	_spinner(Vector3(0, 0, -19), 9.5, 1.3, "food/rollingPin")
	_wp(Vector3(0, 0.5, -12)); _wp(Vector3(0, 0.5, -26))
	# side island with a present and a ring of coins
	_land(Vector3(10.5, 0.6, -19), 6, 8)
	_dress(Vector3(10.5, 0.6, -19), 6, 8, 4)
	_item_box(Vector3(10.5, 1.6, -19))
	_coin_ring(Vector3(10.5, 0.6, -19), 2.0, 6)
	# 2: river - stepping stones (coins) or the plank bridge
	var stones := [Vector3(1, 0.4, -31), Vector3(4.5, 0.0, -33), Vector3(1.8, 0.8, -36), Vector3(5, 0.4, -38.5), Vector3(1.5, 0.2, -41)]
	for st: Vector3 in stones:
		_land(st, 2.6, 2.6, "grass", 1.2)
		_coin(st)
	_bridge(Vector3(-3.5, 0, -27.5), Vector3(-3.5, 0, -44.5), 2.6)
	_wp(Vector3(-3.5, 0.5, -29)); _wp(Vector3(-3.5, 0.5, -43))
	# 3: big field: checkpoint, crates, loaf pushers
	_land(Vector3(0, 0, -53), 16, 18)
	_trees(Vector3(0, 0, -53), 16, 18, 2)
	_dress(Vector3(0, 0, -53), 16, 18, 8)
	_checkpoint(Vector3(0, 0, -47))
	_wp(Vector3(-2, 0.5, -47))
	_crates(Vector3(5.5, 0, -49))
	_item_box(Vector3(-5.5, 1.0, -50))
	_pusher(Vector3(-6.5, 0.6, -55), 6.0, 0.0)
	_pusher(Vector3(6.5, 0.6, -58), -6.0, 1.6)
	# up to the plateau: ramp on the left or the big frying pan on the right
	_ramp(Vector3(-4.5, 0, -61.9), Vector3(-4.5, 4, -72.1), 3.6)
	_wp(Vector3(-4.5, 0.5, -60)); _wp(Vector3(-4.5, 4.5, -73))
	_bounce_pad(Vector3(4, 0.05, -59), Vector3(0, 13, -6))
	_coin_arc(Vector3(4, 0.6, -59), Vector3(4, 4.6, -73), 4, 6.0)
	# 4: plateau with two hammers
	_land(Vector3(0, 4, -82), 14, 20)
	_dress(Vector3(0, 4, -82), 14, 20, 8)
	_checkpoint(Vector3(-3, 4, -74))
	_hammer(Vector3(0, 10.5, -79), 0.0)
	_hammer(Vector3(0, 10.5, -86), PI * 0.6)
	_coin_line(Vector3(5, 4, -76), Vector3(5, 4, -90), 4)
	_wp(Vector3(-1, 4.5, -77)); _wp(Vector3(0, 4.5, -90))
	# turn left: bridge down to the sweeper island and the goal
	next_section(Vector3(0, 4, -92), PI * 0.5)
	_bridge(Vector3(0, 4, -0.2), Vector3(0, 2, -14.2), 4.0)
	_wp(Vector3(0, 4.5, -1)); _wp(Vector3(0, 2.5, -14))
	_land(Vector3(0, 2, -21), 13, 13)
	_dress(Vector3(0, 2, -21), 13, 13, 6)
	_checkpoint(Vector3(0, 2, -15.5))
	_spinner(Vector3(0, 2, -21.5), 10.0, -1.5, "food/rollingPin")
	_coin_ring(Vector3(0, 2, -21), 4.0, 8)
	_wp(Vector3(0, 2.5, -27))
	_land(Vector3(0, 2.5, -35), 12, 12)
	_trees(Vector3(0, 2.5, -35), 12, 12, 2)
	_dress(Vector3(0, 2.5, -35), 12, 12, 8)
	_finish(Vector3(0, 2.5, -36))

# ================================================================ 2 forest

func _forest() -> void:
	section(Vector3.ZERO)
	_land(Vector3(0, 0, -2), 16, 14)
	_start_pad(Vector3(0, 0, 2))
	_trees(Vector3(0, 0, -2), 16, 14, 4)
	_dress(Vector3(0, 0, -2), 16, 14, 10)
	# 1: forest floor - weave between the trunks, mind the broccoli
	_land(Vector3(0, 0, -20), 14, 22)
	_dress(Vector3(0, 0, -20), 14, 22, 10)
	var ids: Array = TREES.forest
	for t in [Vector3(-3, 0, -13), Vector3(3.5, 0, -16), Vector3(-1.2, 0, -21), Vector3(4, 0, -24.5), Vector3(-4.5, 0, -27)]:
		_solid(ids[_rng.randi() % ids.size()], t, _rng.randf_range(3.0, 4.5), 0.4)
	_coin_line(Vector3(0.8, 0, -12), Vector3(1.2, 0, -19), 3)
	_coin_line(Vector3(-2.5, 0, -23), Vector3(1.0, 0, -28), 3)
	guards.append([_g(Vector3(1.5, 0.6, -25)), 6.0, "broccoli"])
	_item_box(Vector3(-5.5, 1.0, -17))
	_wp(Vector3(0.5, 0.5, -10)); _wp(Vector3(0.5, 0.5, -18)); _wp(Vector3(1.5, 0.5, -29))
	_checkpoint(Vector3(-4, 0, -28.5))
	# 2: ravine - narrow log bridge with a saw, or ride the raft
	_bridge(Vector3(-4, 0, -30.8), Vector3(-4, 0, -45.2), 2.2)
	_saw(Vector3(-4, 0.9, -38), 1.6, 0.0, 1.4)
	_wp(Vector3(-4, 0.5, -32)); _wp(Vector3(-4, 0.5, -44))
	_ferry(Vector3(3, -0.05, -33.6), Vector3(3, -0.05, -42.4), Vector2(3.6, 3.6), 7.0)
	_coin_line(Vector3(3, -0.05, -35), Vector3(3, -0.05, -41), 3)
	# 3: clearing with mushroom trampolines up to the ledge
	_land(Vector3(0, 0, -53), 14, 16)
	_dress(Vector3(0, 0, -53), 14, 16, 8)
	_checkpoint(Vector3(0, 0, -48))
	_item_box(Vector3(5, 1.0, -50))
	_mushroom(Vector3(-3, 0, -57), 1.1, 3.0, Vector3(0, 13.0, -6.0))
	_mushroom(Vector3(3, 0, -57), 1.1, 3.0, Vector3(0, 13.0, -6.0))
	_coin_arc(Vector3(3, 1.5, -57), Vector3(3, 6.2, -68), 4, 7.0)
	_wp(Vector3(-1, 0.5, -52)); _wp(Vector3(-3, 1.4, -57))
	# 4: the ledge and a slope of rolling logs
	_land(Vector3(0, 6, -71), 14, 14)
	_dress(Vector3(0, 6, -71), 14, 14, 6)
	_trees(Vector3(0, 6, -71), 14, 14, 2)
	_checkpoint(Vector3(0, 6, -69))
	_wp(Vector3(-2, 6.5, -68)); _wp(Vector3(0, 6.5, -77))
	_ramp(Vector3(0, 6, -77.9), Vector3(0, 9.5, -92.1), 8.0)
	_roller_spawn(Vector3(0, 11.2, -93), 3.2, 1.6, "barrel")
	_wp(Vector3(-2.5, 10, -92))
	_land(Vector3(0, 9.5, -98), 12, 12)
	_dress(Vector3(0, 9.5, -98), 12, 12, 6)
	_checkpoint(Vector3(0, 9.5, -96))
	_coin_ring(Vector3(0, 9.5, -99), 3.0, 6)
	_wp(Vector3(0, 10, -100))
	# turn right: crumbling platforms and the hammer bridge
	next_section(Vector3(0, 9.5, -104), -PI * 0.5)
	for row in 4:
		for x in [-1.6, 1.6]:
			_falling(Vector3(x, 9.5, -2.0 - row * 3.2), "models/platform-falling", 2.8)
	_wp(Vector3(-1.6, 10, -2)); _wp(Vector3(1.6, 10, -8)); _wp(Vector3(-1.6, 10, -12))
	_land(Vector3(0, 9.5, -18), 8, 6)
	_checkpoint(Vector3(0, 9.5, -18))
	_bridge(Vector3(0, 9.5, -20.8), Vector3(0, 9.5, -36.2), 5.0)
	_hammer(Vector3(0, 15.6, -24), 0.0, 2.0)
	_hammer(Vector3(0, 15.6, -29), 2.1, 2.0)
	_hammer(Vector3(0, 15.6, -34), 4.2, 2.0)
	_wp(Vector3(0, 10, -21)); _wp(Vector3(0, 10, -36))
	_land(Vector3(0, 9.5, -42), 12, 12)
	_trees(Vector3(0, 9.5, -42), 12, 12, 2)
	_dress(Vector3(0, 9.5, -42), 12, 12, 8)
	_finish(Vector3(0, 9.5, -43))

# ================================================================ 3 village

func _village() -> void:
	section(Vector3.ZERO)
	# town square around a fountain
	_land(Vector3(0, 0, -4), 18, 18)
	_start_pad(Vector3(0, 0, 2))
	_solid("town/fountainRound", Vector3(0, 0, -7), 4.0, 2.0, 0.6)
	for x in [-6.5, 6.5]:
		_solid("town/stallRed" if x < 0 else "town/stallGreen", Vector3(x, 0, -9), 3.0, 1.2, 2.5)
	_dress(Vector3(0, 0, -4), 18, 18, 10)
	_coin_ring(Vector3(0, 0, -7), 3.2, 8)
	_wp(Vector3(-3.5, 0.5, -6)); _wp(Vector3(0, 0.5, -12))
	# 1: market street - loaf pushers from the stalls and rolling barrels
	_land(Vector3(0, 0, -27), 10, 28)
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		_pusher(Vector3(side * 6.0, 0.6, -17.0 - i * 5.0), -side * 5.0, i * 1.3)
		_deco("town/stall" if i % 2 == 0 else "town/stallRed", Vector3(side * 6.8, -0.2, -19.5 - i * 5.0), 2.6, PI * 0.5 * side)
	_roller_spawn(Vector3(0, 1.0, -41), 3.8, 2.4, "barrel", 3.5)
	_coin_line(Vector3(-3.8, 0, -16), Vector3(-3.8, 0, -38), 5)
	_wp(Vector3(0.5, 0.5, -20)); _wp(Vector3(0, 0.5, -38))
	# 2: plaza with brawlers
	_land(Vector3(0, 0, -50), 18, 18)
	_dress(Vector3(0, 0, -50), 18, 18, 8)
	_trees(Vector3(0, 0, -50), 18, 18, 2)
	_checkpoint(Vector3(0, 0, -44))
	guards.append([_g(Vector3(-3, 0.6, -51)), 6.5, "carrot"])
	guards.append([_g(Vector3(3, 0.6, -54)), 6.5, "eggplant"])
	_item_box(Vector3(-6, 1.0, -46))
	_item_box(Vector3(6, 1.0, -46))
	_crates(Vector3(6.5, 0, -56))
	_wp(Vector3(0, 0.5, -50)); _wp(Vector3(0, 0.5, -58))
	# 3: the windmill wheel gate
	_land(Vector3(0, 0, -63), 7, 8)
	_wheel(Vector3(0, 3.5, -63), 3.3, 1.1)
	_wp(Vector3(0, 0.5, -66))
	_ramp(Vector3(0, 0, -66.9), Vector3(0, 4, -79.1), 6)
	_coin_line(Vector3(0, 0.6, -69), Vector3(0, 3.4, -77), 3)
	_land(Vector3(0, 4, -86), 14, 14)
	_dress(Vector3(0, 4, -86), 14, 14, 6)
	_land(Vector3(13, 3.5, -86), 8, 8)
	_deco("town/windmill", Vector3(13, 3.5, -86), 8.0, -PI * 0.5)
	_checkpoint(Vector3(0, 4, -84))
	_wp(Vector3(0, 4.5, -80)); _wp(Vector3(0, 4.5, -91))
	# turn left: crumbling planks over the canal, then the bouncy climb
	next_section(Vector3(0, 4, -93), PI * 0.5)
	for row in 4:
		for x in [-1.6, 1.6]:
			_falling(Vector3(x, 4, -2.0 - row * 3.2), "models/platform-falling", 2.8)
	_coin_line(Vector3(1.6, 4.2, -2), Vector3(1.6, 4.2, -11.6), 4)
	_wp(Vector3(-1.6, 4.5, -2)); _wp(Vector3(-1.6, 4.5, -11))
	_land(Vector3(0, 4, -20), 12, 10)
	_dress(Vector3(0, 4, -20), 12, 10, 6)
	_checkpoint(Vector3(0, 4, -17))
	_bounce_pad(Vector3(-3, 4.05, -22.5), Vector3(0, 13, -5))
	_bounce_pad(Vector3(3, 4.05, -22.5), Vector3(0, 13, -5))
	_wp(Vector3(-3, 4.5, -22.5))
	_land(Vector3(0, 8, -34), 10, 10)
	_dress(Vector3(0, 8, -34), 10, 10, 6)
	_finish(Vector3(0, 8, -35))

# ================================================================ 4 kitchen

func _kitchen() -> void:
	section(Vector3.ZERO)
	_board(Vector3(0, 0, -2), 14, 12)
	_start_pad(Vector3(0, 0, 1.5))
	_dress(Vector3(0, 0, -2), 14, 12, 6)
	# 1: pizza turntable
	_pizza(Vector3(0, 0.05, -14), 9.5, 0.7)
	_coin_ring(Vector3(0, 0.1, -14), 3.0, 6)
	_wp(Vector3(0, 0.6, -10)); _wp(Vector3(0, 0.6, -18))
	# 2: toaster launchers up to the shelf
	_board(Vector3(0, 0, -25), 12, 8)
	_dress(Vector3(0, 0, -25), 12, 8, 4)
	_wp(Vector3(-2.5, 0.6, -23))
	_toaster_launcher(Vector3(-2.5, 0, -26.5))
	_toaster_launcher(Vector3(2.5, 0, -26.5))
	_board(Vector3(0, 4, -38), 12, 10)
	_checkpoint(Vector3(0, 4, -36))
	_item_box(Vector3(4.5, 5, -38))
	_wp(Vector3(0, 4.6, -40))
	# 3: cleaver field
	_board(Vector3(0, 4, -52), 12, 18)
	for row in 3:
		_cleaver(Vector3(-2.6, 4.4, -46.0 - row * 5.0), row * 0.33)
		_cleaver(Vector3(2.6, 4.4, -47.5 - row * 5.0), row * 0.33 + 0.5)
	_coin_line(Vector3(-5.3, 4, -45), Vector3(-5.3, 4, -59), 4)
	_wp(Vector3(0, 4.6, -44)); _wp(Vector3(0, 4.6, -60))
	_board(Vector3(0, 4, -66), 12, 8)
	_checkpoint(Vector3(0, 4, -65))
	# turn right: tomato avalanche, whisk, falling waffles
	next_section(Vector3(0, 4, -70), -PI * 0.5)
	_ramp(Vector3(0, 4, 0), Vector3(0, 8, -16), 8.0, "planks")
	_roller_spawn(Vector3(0, 9.6, -17), 3.3, 1.3, "roller")
	_wp(Vector3(-2.5, 4.6, -2)); _wp(Vector3(-2.5, 8.6, -16))
	_board(Vector3(0, 8, -21), 12, 10)
	_dress(Vector3(0, 8, -21), 12, 10, 4)
	_checkpoint(Vector3(0, 8, -19))
	guards.append([_g(Vector3(0, 8.6, -23)), 4.5, "eggplant"])
	_item_box(Vector3(-4.5, 9, -21))
	_slab("food/waffle", Vector3(0, 8, -33), 14, 14, 0.5)
	_spinner(Vector3(0, 8, -33), 12.5, -1.9, "food/whisk")
	_coin_ring(Vector3(0, 8, -33), 4.5, 8)
	_wp(Vector3(0, 8.6, -27)); _wp(Vector3(0, 8.6, -39))
	for row in 4:
		for x in [-1.6, 1.6]:
			_falling(Vector3(x, 8, -42.0 - row * 3.2))
	_wp(Vector3(1.6, 8.6, -42)); _wp(Vector3(1.6, 8.6, -51.6))
	# turn left: frying pan up to the big plate
	next_section(Vector3(0, 8, -55), PI * 0.5)
	_board(Vector3(0, 8, -2.5), 9, 8)
	_bounce_pad(Vector3(0, 8.05, -3.5), Vector3(0, 13.5, -5))
	_wp(Vector3(0, 8.6, -3.5))
	_slab("food/plate", Vector3(0, 12, -16), 12, 12, 0.8)
	_dress(Vector3(0, 12, -16), 12, 12, 4)
	_finish(Vector3(0, 12, -16.5))

# ================================================================ 5 cove

func _cove() -> void:
	section(Vector3.ZERO)
	_land(Vector3(0, 0, -2), 16, 14, "sand")
	_start_pad(Vector3(0, 0, 2))
	_trees(Vector3(0, 0, -2), 16, 14, 3)
	_dress(Vector3(0, 0, -2), 16, 14, 8)
	# 1: plank bridge under cannon fire
	_bridge(Vector3(0, 0, -8.8), Vector3(0, 0, -21.2), 3.5)
	_cannon(Vector3(-10, 0, -15), 24.0)
	_coin_line(Vector3(0, 0.1, -10), Vector3(0, 0.1, -20), 4)
	_wp(Vector3(0, 0.5, -10)); _wp(Vector3(0, 0.5, -20))
	_land(Vector3(0, 0, -28), 14, 14, "sand")
	_dress(Vector3(0, 0, -28), 14, 14, 6)
	_trees(Vector3(0, 0, -28), 14, 14, 2)
	_checkpoint(Vector3(0, 0, -24))
	_item_box(Vector3(4.5, 1, -30))
	_cannon(Vector3(10, 0, -30), 24.0)
	# 2: lagoon - raft ride, or the saw plank
	_wp(Vector3(2.5, 0.5, -32))
	_ferry(Vector3(2.5, -0.05, -37.4), Vector3(2.5, -0.05, -48.6), Vector2(3.8, 3.8), 8.0)
	_wp(Vector3(2.5, 0.5, -50))
	_bridge(Vector3(-4.5, 0, -34.8), Vector3(-4.5, 0, -51.2), 2.4)
	_saw(Vector3(-4.5, 0.9, -40), 1.6, 0.0)
	_saw(Vector3(-4.5, 0.9, -46), 1.6, 1.8)
	_coin_line(Vector3(-4.5, 0.1, -37), Vector3(-4.5, 0.1, -49), 4)
	# 3: brawler deck with cannons
	_land(Vector3(0, 0, -58), 16, 14, "sand")
	_dress(Vector3(0, 0, -58), 16, 14, 6)
	_checkpoint(Vector3(0, 0, -53))
	guards.append([_g(Vector3(-2.5, 0.6, -59)), 5.5, "carrot"])
	guards.append([_g(Vector3(2.5, 0.6, -61)), 5.5, "eggplant"])
	_item_box(Vector3(-6, 1, -54))
	_item_box(Vector3(6, 1, -54))
	_cannon(Vector3(-11, 1, -60), 22.0)
	_wp(Vector3(0, 0.5, -58)); _wp(Vector3(-2.5, 0.5, -64))
	# 4: barrel ramp
	_ramp(Vector3(-2.5, 0, -64.9), Vector3(-2.5, 4, -79.1), 7.0, "planks")
	_roller_spawn(Vector3(-2.5, 5.6, -80), 3.0, 1.5, "barrel")
	_wp(Vector3(-4.5, 4.5, -79))
	_land(Vector3(0, 4, -85), 12, 12, "sand")
	_dress(Vector3(0, 4, -85), 12, 12, 6)
	_checkpoint(Vector3(0, 4, -83))
	_wp(Vector3(0, 4.5, -89))
	# turn left: hop the barrel tops, then saw alley
	next_section(Vector3(0, 4, -91), PI * 0.5)
	var hops := [Vector3(-1.5, 4, -2.5), Vector3(1.6, 4.6, -6.2), Vector3(-1.4, 5.2, -9.8), Vector3(1.5, 5.8, -13.4)]
	for h: Vector3 in hops:
		_land(h, 2.6, 2.6, "sand", 1.2)
		_coin(h)
		_wp(h + Vector3(0, 0.5, 0))
	_cannon(Vector3(-9, 5, -8), 20.0, 3.0)
	_land(Vector3(0, 6, -18), 6, 4, "sand")
	_bridge(Vector3(0, 6, -19.8), Vector3(0, 6, -36.2), 3.4)
	_saw(Vector3(0, 6.9, -23), 2.4, 0.0, 1.8)
	_saw(Vector3(0, 6.9, -28), 2.4, 1.9, 1.8)
	_saw(Vector3(0, 6.9, -33), 2.4, 3.6, 1.8)
	_wp(Vector3(0, 6.5, -20)); _wp(Vector3(0, 6.5, -36))
	_land(Vector3(0, 6, -42), 14, 12, "sand")
	_trees(Vector3(0, 6, -42), 14, 12, 2)
	_dress(Vector3(0, 6, -42), 14, 12, 8)
	_finish(Vector3(0, 6, -43))

# ================================================================ 6 peaks

func _peaks() -> void:
	section(Vector3.ZERO)
	_land(Vector3(0, 0, -2), 16, 14, "snow")
	_start_pad(Vector3(0, 0, 2))
	_trees(Vector3(0, 0, -2), 16, 14, 4)
	_dress(Vector3(0, 0, -2), 16, 14, 8)
	# 1: ice rink with a sweeper - hard to dodge when you slide
	_land(Vector3(0, 0, -20), 14, 22, "ice")
	_spinner(Vector3(0, 0, -20), 11.5, 1.2, "food/rollingPin")
	_coin_ring(Vector3(0, 0, -20), 5.0, 8)
	_wp(Vector3(0, 0.5, -11)); _wp(Vector3(0, 0.5, -29))
	# 2: train crossing
	_land(Vector3(0, 0, -38), 14, 14, "snow")
	_checkpoint(Vector3(0, 0, -33))
	_train(Vector3(0, 0, -38.5), -17.0, 17.0, 6.0)
	_dress(Vector3(0, 0, -38), 14, 14, 4)
	_wp(Vector3(0, 0.5, -42))
	# 3: snowmen guarding the presents
	_land(Vector3(0, 0, -53), 14, 16, "snow")
	_trees(Vector3(0, 0, -53), 14, 16, 2)
	_dress(Vector3(0, 0, -53), 14, 16, 6)
	guards.append([_g(Vector3(-2.5, 0.6, -52)), 5.5, "snowman"])
	guards.append([_g(Vector3(2.5, 0.6, -56)), 5.5, "snowman"])
	_item_box(Vector3(-5.5, 1, -48))
	_item_box(Vector3(5.5, 1, -48))
	_wp(Vector3(0, 0.5, -50)); _wp(Vector3(0, 0.5, -59))
	# turn right: snowy slope with barrels rolling down
	next_section(Vector3(0, 0, -61), -PI * 0.5)
	_ramp(Vector3(0, 0, 0.5), Vector3(0, 4, -14.1), 7.0, "snow")
	_roller_spawn(Vector3(0, 5.6, -15), 2.8, 1.5, "barrel")
	_wp(Vector3(2.5, 0.5, -1)); _wp(Vector3(2.5, 4.5, -14))
	_land(Vector3(0, 4, -19), 10, 10, "snow")
	_dress(Vector3(0, 4, -19), 10, 10, 4)
	_checkpoint(Vector3(0, 4, -17))
	_wp(Vector3(0, 4.5, -23))
	# turn left: icy crumbling tiles, another train, climb
	next_section(Vector3(0, 4, -24), PI * 0.5)
	for row in 4:
		for x in [-1.6, 1.6]:
			_falling(Vector3(x, 4, -2.0 - row * 3.2), "models/platform-falling", 2.8)
	_coin_line(Vector3(-1.6, 4.2, -2), Vector3(-1.6, 4.2, -11.6), 4)
	_wp(Vector3(1.6, 4.5, -2)); _wp(Vector3(1.6, 4.5, -11))
	_land(Vector3(0, 4, -20), 12, 10, "snow")
	_train(Vector3(0, 4, -20), 16.0, -16.0, 5.0, 0.3)
	_wp(Vector3(0, 4.5, -17)); _wp(Vector3(0, 4.5, -24))
	_ramp(Vector3(0, 4, -24.9), Vector3(0, 8, -37.1), 6.0, "snow")
	_wp(Vector3(0, 8.5, -37))
	_land(Vector3(0, 8, -42), 12, 10, "snow")
	_dress(Vector3(0, 8, -42), 12, 10, 4)
	_checkpoint(Vector3(0, 8, -40))
	_cannon(Vector3(-10, 8, -42), 22.0, 3.2)
	_wp(Vector3(0, 8.5, -46))
	# turn left: hammer bridge and the jump to the summit
	next_section(Vector3(0, 8, -47), PI * 0.5)
	_bridge(Vector3(0, 8, 0), Vector3(0, 8, -18.2), 4.6)
	_hammer(Vector3(0, 14.1, -4), 0.0, 2.3)
	_hammer(Vector3(0, 14.1, -9.5), 2.0, 2.3)
	_hammer(Vector3(0, 14.1, -15), 4.0, 2.3)
	_wp(Vector3(0, 8.5, -1)); _wp(Vector3(0, 8.5, -18))
	_land(Vector3(0, 8, -22), 8, 8, "snow")
	_bounce_pad(Vector3(0, 8.05, -23), Vector3(0, 14, -5))
	_wp(Vector3(0, 8.6, -23))
	_land(Vector3(0, 13, -35), 12, 12, "snow")
	_trees(Vector3(0, 13, -35), 12, 12, 2)
	_dress(Vector3(0, 13, -35), 12, 12, 6)
	_finish(Vector3(0, 13, -36))
