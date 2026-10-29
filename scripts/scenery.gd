class_name Scenery
extends Node3D
## The world around a level, built only from real models (Kenney nature,
## food, furniture, pirate, town and holiday kits) under Kenney's painted
## skybox. It rings the level's area (any shape: levels turn) with land, so
## the play space floats over water with scenery all around. Themes:
##   meadow  - grassy cliff terraces, forests, tents, market stalls, ships
##   forest  - dense pine / autumn woods, giant mushrooms, a dark lake
##   village - hills with windmills, watermills, stalls and orchards
##   kitchen - a giant kitchen: counters, appliances, a sea of tomato soup
##   pirate  - tropical sea: rock islands with palms, ships, towers
##   snow    - snowy cliffs, snow pines, snowmen, an icy sea
## Purely visual (no collision). Shared by the menu, the world map and the
## game. Static copies are batched into MultiMeshes so the whole backdrop is
## a few dozen draw calls.

## The playable area (world space); the backdrop keeps clear of it.
var area := AABB(Vector3(-8, 0, -8), Vector3(16, 4, 16))
var theme := "meadow"
var shadows := true
## false: sky, light and clouds only (the open world brings its own land).
var backdrop := true
## Keep land at least this far outside the area.
var clearance := 22.0
## How far the ring of scenery reaches beyond the clearance.
var reach := 70.0
## World height of the water / soup surface.
var sea_level := -17.0

var _batches := {}        # model id -> Array[Transform3D]
var _drifters: Array = [] # [node, base_position, bob, speed, phase, drift]
var _t := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = hash(theme) + 7
	_environment()
	if not backdrop:
		_clouds()
		return
	match theme:
		"kitchen":
			_kitchen()
		"pirate":
			_pirate()
		"forest":
			_terraces(["nature/tree_pineRoundB", "nature/tree_pineDefaultA", "nature/tree_pineTallA", "nature/tree_oak_fall", "nature/tree_default_fall", "nature/tree_detailed"],
				["nature/mushroom_redTall", "nature/mushroom_tanTall", "nature/mushroom_red", "nature/stump_roundDetailed", "nature/plant_bushDetailed", "nature/log"],
				"nature/cliff_block_rock", 4, 6)
			_sea(Color("0f4d5c"), Color("1f8a8a"), Color("dfffee"))
			_ships(["pirate/ship_light"], 1)
		"village":
			_terraces(["town/treeHighRound", "nature/tree_oak", "nature/tree_default", "nature/tree_fat"],
				["town/windmill", "town/watermill", "town/stallRed", "town/stall", "town/stallGreen", "town/cart", "nature/plant_bushLarge", "nature/fence_simple"],
				"nature/cliff_block_rock", 2, 3)
			_sea(Color("1670b8"), Color("2fa9dc"), Color("e8fbff"))
			_ships(["pirate/ship_light", "pirate/ship_dark"], 2)
		"snow":
			_terraces(["holiday/treePineSnow", "holiday/treePineSnowRound", "holiday/treePineSnow"],
				["holiday/snowman", "holiday/snowmanFancy", "holiday/rockFormationLarge", "holiday/lightpost", "holiday/present", "holiday/snowFort", "holiday/candyCane"],
				"platformer/blockSnowLarge", 2, 3)
			_sea(Color("2a5d8f"), Color("7fc8e8"), Color("ffffff"))
		_:
			_terraces(["nature/tree_oak", "nature/tree_default", "nature/tree_detailed", "nature/tree_fat",
				"nature/tree_pineRoundA", "nature/tree_pineRoundC", "nature/tree_pineTallA", "nature/tree_plateau", "town/treeHighRound"],
				["nature/plant_bushLarge", "nature/plant_bush", "nature/flower_redA", "nature/flower_yellowA",
				"nature/flower_purpleA", "nature/mushroom_redGroup", "nature/grass_large", "nature/rock_largeA", "nature/stump_round"],
				"nature/cliff_block_rock", 2, 3)
			_sea(Color("1670b8"), Color("2fa9dc"), Color("e8fbff"))
			_ships(["pirate/ship_light", "pirate/ship_dark"], 3)
	_clouds()
	for id in _batches:
		add_child(Props.multi(id, _batches[id]))

# ------------------------------------------------------------- environment

func _environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/kenney/sky/skybox.png")
	sky.sky_material = pm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation.y = 0.6
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d4ddff")
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.8
	env.tonemap_white = 1.4
	env.glow_enabled = true
	env.glow_intensity = 0.12
	env.glow_bloom = 0.0
	env.fog_enabled = true
	var fog := {"kitchen": Color("ffe3c4"), "forest": Color("a7d6b8"), "snow": Color("e4f2ff"), "graveyard": Color("4a3f66")}
	env.fog_light_color = fog.get(theme, Color("b9b2ff"))
	env.fog_density = 0.0018 if theme == "forest" or theme == "snow" else 0.0011
	if not backdrop:
		# open world: haze hides the far mountains (and saves drawing them)
		env.fog_light_color = fog.get(theme, Color("bcd4f2"))
		env.fog_density = {"forest": 0.0035, "graveyard": 0.0045, "snow": 0.0025}.get(theme, 0.0016)
		env.fog_sky_affect = 0.0
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 0.96
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.12
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 0.95
	sun.light_color = Color("fff1dc") if theme != "snow" else Color("f2f6ff")
	if theme == "graveyard":
		# dusk: low orange sun, purple sky and shadows
		sun.rotation_degrees = Vector3(-22, -60, 0)
		sun.light_color = Color("ffae6b")
		sun.light_energy = 0.75
		env.ambient_light_color = Color("8f7fd0")
		env.ambient_light_energy = 0.45
		env.background_energy_multiplier = 0.55
		env.adjustment_brightness = 0.85
		env.adjustment_saturation = 0.95
	sun.shadow_enabled = shadows
	sun.directional_shadow_max_distance = 32.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_blur = 1.2
	add_child(sun)

func _sea(deep: Color, shallow: Color, foam: Color) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	pm.subdivide_width = 60
	pm.subdivide_depth = 60
	mi.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/water.gdshader")
	mat.set_shader_parameter("deep", deep)
	mat.set_shader_parameter("shallow", shallow)
	mat.set_shader_parameter("foam", foam)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var c := area.get_center()
	mi.position = Vector3(c.x, sea_level, c.z)
	add_child(mi)

# ------------------------------------------------------------- placement

func _put(id: String, pos: Vector3, s: float, yaw := -1.0, s_y := -1.0) -> void:
	var b := Basis(Vector3.UP, _rng.randf() * TAU if yaw < 0.0 else yaw).scaled(Vector3(s, s if s_y < 0.0 else s_y, s))
	if not _batches.has(id):
		_batches[id] = []
	_batches[id].append(Transform3D(b, pos))

## Scale factor that makes model `id` `size` metres across.
func _fit(id: String, size: float) -> float:
	var s := Props.base_size(id)
	return size / maxf(maxf(s.x, s.z), 0.001)

func _pick(arr: Array):
	return arr[_rng.randi() % arr.size()]

func _jitter(r: float) -> Vector3:
	return Vector3(_rng.randf_range(-r, r), 0, _rng.randf_range(-r, r))

## How far (x/z) a point is outside the area; 0 inside.
func _outside(x: float, z: float) -> float:
	var dx := maxf(maxf(area.position.x - x, x - area.end.x), 0.0)
	var dz := maxf(maxf(area.position.z - z, z - area.end.z), 0.0)
	return maxf(dx, dz)

## Grid cells (centre x, z, distance outside the area) in the ring between
## `inner` and `inner + reach` around the area.
func _ring(step: float, inner: float) -> Array:
	var out := []
	var x := area.position.x - inner - reach
	while x < area.end.x + inner + reach:
		var z := area.position.z - inner - reach
		while z < area.end.z + inner + reach:
			var d := _outside(x, z)
			if d >= inner:
				out.append([x, z, d])
			z += step
		x += step
	return out

## Unit direction from the area towards a point (for things that face it).
func _away(x: float, z: float) -> Vector3:
	var c := area.get_center()
	var v := Vector3(x - c.x, 0, z - c.z)
	return v.normalized() if v.length() > 0.1 else Vector3.BACK

# ------------------------------------------------------------- terraces

## Cliff blocks rising in terraces away from the level, with trees and
## things on top. Used by meadow, forest, village and snow.
func _terraces(trees: Array, small: Array, block_id: String, trees_per: int, small_per: int) -> void:
	var block := 12.0
	var big := ["town/windmill", "town/watermill", "nature/tent_detailedOpen", "holiday/snowFort", "holiday/rockFormationLarge"]
	for cell in _ring(block, clearance):
		var d: float = cell[2] - clearance
		var top := sea_level + 4.0 + d * 0.3 + _rng.randf_range(0.0, 4.0)
		var h := top - (sea_level - 4.0)
		var pos := Vector3(cell[0] + _rng.randf_range(-1.5, 1.5), sea_level - 4.0, cell[1] + _rng.randf_range(-1.5, 1.5))
		var bs := Props.base_size(block_id)
		var s := block * 1.02 / maxf(bs.x, bs.z)
		_put(block_id, pos, s, PI * 0.5 * _rng.randi_range(0, 3), h / bs.y)
		var ground := Vector3(pos.x, top, pos.z)
		var r := _rng.randf()
		if r < 0.08 and d > 6.0:
			var id: String = _pick(small.filter(func(i): return i in big)) if small.any(func(i): return i in big) else ""
			if id != "":
				var yaw := atan2(_away(pos.x, pos.z).x, _away(pos.x, pos.z).z) + PI
				_put(id, ground + _jitter(2.0), _fit(id, 8.0), yaw)
		elif r < 0.12 and d > 6.0 and theme == "meadow":
			_put("nature/tent_detailedOpen", ground + _jitter(3.0), _fit("nature/tent_detailedOpen", 6.0))
			_put("nature/campfire_logs", ground + _jitter(3.0) + Vector3(0, 0, 3), _fit("nature/campfire_logs", 2.0))
		for k in _rng.randi_range(1, trees_per):
			var id: String = _pick(trees)
			_put(id, ground + _jitter(4.5), _fit(id, _rng.randf_range(4.0, 7.0)))
		for k in _rng.randi_range(1, small_per):
			var id: String = _pick(small)
			if id in big:
				continue
			_put(id, ground + _jitter(5.0), _fit(id, _rng.randf_range(1.5, 3.2) * (2.0 if theme == "forest" else 1.0)))

# ------------------------------------------------------------- kitchen

func _kitchen() -> void:
	sea_level = -15.0
	_sea(Color("b8301a"), Color("e0582c"), Color("ffc58a"))  # tomato soup
	var counter := ["furniture/kitchenCabinet", "furniture/kitchenCabinet", "furniture/kitchenStove", "furniture/kitchenSink"]
	var w := 16.0
	var giant := ["food/tomato", "food/watermelon", "food/cheese", "food/bottleKetchup", "food/sodaCan",
		"food/loaf", "food/pie", "food/burger", "food/cupcake", "food/croissant", "food/broccoli", "food/carrot"]
	var apps := ["furniture/kitchenMicrowave", "furniture/kitchenCoffeeMachine", "furniture/kitchenBlender", "furniture/toaster", "furniture/kitchenFridgeLarge"]
	for cell in _ring(w, clearance):
		var d: float = cell[2] - clearance
		if d > w * 2.5:
			continue
		var away := _away(cell[0], cell[1])
		var yaw := atan2(away.x, away.z) + PI
		var id: String = _pick(counter)
		var s := _fit(id, w)
		var base := Vector3(cell[0], sea_level - 2.0, cell[1])
		_put(id, base, s, yaw)
		var top := sea_level - 2.0 + Props.base_size(id).y * s
		var r := _rng.randf()
		if r < 0.45:
			var g: String = _pick(giant)
			_put(g, Vector3(cell[0], top, cell[1]) + _jitter(3.0), _fit(g, _rng.randf_range(5.0, 9.0)))
		elif r < 0.6:
			var app: String = _pick(apps)
			_put(app, Vector3(cell[0], top, cell[1]), _fit(app, 11.0), yaw)
	# bits of food floating in the soup between the counters and the level
	for i in 30:
		var id: String = _pick(["food/tomato", "food/carrot", "food/broccoli", "food/croissant", "food/cookie"])
		var p := Vector3(_rng.randf_range(area.position.x - clearance, area.end.x + clearance), sea_level - 0.4,
			_rng.randf_range(area.position.z - clearance, area.end.z + clearance))
		var n := Props.sized(id, _rng.randf_range(2.0, 4.0))
		n.position = p
		n.rotation.y = _rng.randf() * TAU
		Props.no_shadows(n)
		add_child(n)
		_drifters.append([n, p, 0.25, _rng.randf_range(0.6, 1.0), _rng.randf() * TAU, 0.6])

# ------------------------------------------------------------- pirate

func _pirate() -> void:
	sea_level = -16.0
	_sea(Color("0b62a8"), Color("1fb4cc"), Color("f0ffff"))
	for cell in _ring(26.0, clearance):
		if _rng.randf() < 0.35:
			continue
		var pos := Vector3(cell[0] + _rng.randf_range(-8, 8), sea_level - 3.0, cell[1] + _rng.randf_range(-8, 8))
		var size := _rng.randf_range(14.0, 26.0)
		_put("pirate/formationLarge_rock", pos, _fit("pirate/formationLarge_rock", size))
		var top := sea_level - 3.0 + Props.base_size("pirate/formationLarge_rock").y * _fit("pirate/formationLarge_rock", size) * 0.35
		for k in _rng.randi_range(1, 3):
			_put("pirate/palm_detailed_long", Vector3(pos.x, top, pos.z) + _jitter(size * 0.3), _fit("pirate/palm_detailed_long", _rng.randf_range(6.0, 9.0)))
		if _rng.randf() < 0.18:
			_put("pirate/tower", Vector3(pos.x + 6.0, sea_level - 1.0, pos.z + 10.0), _fit("pirate/tower", 12.0))
	_ships(["pirate/ship_dark", "pirate/ship_light"], 6)
	for i in 14:
		var id: String = _pick(["platformer/barrel", "pirate/chest", "platformer/crate"])
		var p := Vector3(_rng.randf_range(area.position.x - clearance, area.end.x + clearance), sea_level - 0.5,
			_rng.randf_range(area.position.z - clearance, area.end.z + clearance))
		var n := Props.sized(id, _rng.randf_range(1.6, 2.6))
		n.position = p
		Props.no_shadows(n)
		add_child(n)
		_drifters.append([n, p, 0.3, _rng.randf_range(0.7, 1.1), _rng.randf() * TAU, 0.4])

# ------------------------------------------------------------- shared

func _ships(ids: Array, n: int) -> void:
	for i in n:
		var id: String = ids[i % ids.size()]
		var ship := Props.sized(id, _rng.randf_range(16.0, 22.0), 2)
		# somewhere on the open water around the level
		var p := Vector3.ZERO
		for tries in 12:
			p = Vector3(_rng.randf_range(area.position.x - clearance - 30, area.end.x + clearance + 30), sea_level - 1.2,
				_rng.randf_range(area.position.z - clearance - 30, area.end.z + clearance + 30))
			if _outside(p.x, p.z) > 10.0 and (theme == "pirate" or _outside(p.x, p.z) < clearance - 6.0):
				break
		ship.position = p
		ship.rotation.y = _rng.randf() * TAU
		Props.no_shadows(ship)
		add_child(ship)
		_drifters.append([ship, p, 0.35, 0.7, _rng.randf() * TAU, 1.5])

func _clouds() -> void:
	var cloud := "models/cloud"
	for i in 26:
		var c := Props.make(cloud)
		var p := Vector3(_rng.randf_range(area.position.x - 90, area.end.x + 90), _rng.randf_range(10.0, 30.0) + area.end.y,
			_rng.randf_range(area.position.z - 90, area.end.z + 90))
		if _outside(p.x, p.z) < 8.0:
			p.x += 30.0 * signf(p.x - area.get_center().x + 0.01)
		c.position = p
		var cs := _rng.randf_range(4.0, 9.0)
		c.scale = Vector3(cs, cs * 0.6, cs)
		c.rotation.y = _rng.randf() * TAU
		Props.no_shadows(c)
		add_child(c)
		_drifters.append([c, p, 0.0, 0.0, 0.0, 3.0])

static func aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

func _process(delta: float) -> void:
	_t += delta
	for d in _drifters:
		var n: Node3D = d[0]
		var base: Vector3 = d[1]
		n.position.y = base.y + sin(_t * d[3] + d[4]) * d[2]
		n.position.x = base.x + sin(_t * 0.05 + base.z) * d[5]
		if d[2] > 0.0:
			n.rotation.z = sin(_t * d[3] * 0.8 + d[4]) * 0.04
