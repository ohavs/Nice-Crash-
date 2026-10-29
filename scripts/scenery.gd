class_name Scenery
extends Node3D
## The world around a course, built only from real models (Kenney nature,
## food, furniture, pirate and town kits) under Kenney's painted skybox.
## Themes:
##   meadow  - river valley: grassy cliffs, forests, tents, market stalls, sailing ships
##   kitchen - a giant kitchen: cabinets, stove, fridge, huge food, a sea of tomato soup
##   pirate  - tropical sea: rock islands with palms, ships, towers, floating barrels
## Purely visual (no collision). Shared by the menu and the game. Static
## copies are batched into MultiMeshes so the whole backdrop is a few dozen
## draw calls.

## Course runs from z = 0 to z = -length; the backdrop surrounds that span.
var length := 100.0
var theme := "meadow"
var shadows := true
## Keep land at least this far to the side of the course centre line.
var clearance := 26.0
## World height of the water / soup surface.
var sea_level := -17.0

var _batches := {}        # model id -> Array[Transform3D]
var _drifters: Array = [] # [node, base_position, bob, speed, phase, drift]
var _t := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = hash(theme) + 7
	_environment()
	match theme:
		"kitchen":
			_kitchen()
		"pirate":
			_pirate()
		_:
			_meadow()
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
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.0
	env.fog_enabled = true
	env.fog_light_color = Color("b9b2ff") if theme != "kitchen" else Color("ffe3c4")
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.12
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.05
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.0
	sun.light_color = Color("fff1dc")
	sun.shadow_enabled = shadows
	sun.directional_shadow_max_distance = 40.0
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
	mi.position = Vector3(0, sea_level, -length * 0.5)
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

## z positions covering the course plus margins before and after.
func _span(step: float, before := 60.0, after := 140.0) -> Array:
	var out := []
	var z := before
	while z > -length - after:
		out.append(z)
		z -= step
	return out

# ------------------------------------------------------------- meadow

func _meadow() -> void:
	_sea(Color("1670b8"), Color("2fa9dc"), Color("e8fbff"))
	var trees := ["nature/tree_oak", "nature/tree_default", "nature/tree_detailed", "nature/tree_fat",
		"nature/tree_pineRoundA", "nature/tree_pineRoundC", "nature/tree_pineTallA", "nature/tree_plateau", "town/treeHighRound"]
	var small := ["nature/plant_bushLarge", "nature/plant_bush", "nature/flower_redA", "nature/flower_yellowA",
		"nature/flower_purpleA", "nature/mushroom_redGroup", "nature/grass_large", "nature/rock_largeA", "nature/stump_round"]
	var block := 12.0
	for side in [-1.0, 1.0]:
		for z in _span(block):
			for col in 4:
				var x: float = side * (clearance + col * block + _rng.randf_range(-2.0, 2.0))
				# terraces rise away from the course
				var top := sea_level + 4.0 + col * 3.5 + _rng.randf_range(0.0, 4.0)
				var h := top - (sea_level - 4.0)
				var pos := Vector3(x, sea_level - 4.0, z)
				_put("nature/cliff_block_rock", pos, block * 1.02, PI * 0.5 * _rng.randi_range(0, 3), h)
				var ground := Vector3(x, top, z)
				# a few things on top of every block
				var r := _rng.randf()
				if r < 0.07 and col > 0:
					_put("nature/tent_detailedOpen", ground + _jitter(3.0), _fit("nature/tent_detailedOpen", 6.0))
					_put("nature/campfire_logs", ground + _jitter(3.0) + Vector3(0, 0, 3), _fit("nature/campfire_logs", 2.0))
				elif r < 0.12 and col > 0:
					_put("town/stallRed", ground + _jitter(3.0), _fit("town/stallRed", 5.0))
				for k in _rng.randi_range(1, 3):
					var id: String = _pick(trees)
					_put(id, ground + _jitter(4.5), _fit(id, _rng.randf_range(4.0, 7.0)))
				for k in _rng.randi_range(1, 3):
					var id: String = _pick(small)
					_put(id, ground + _jitter(5.0), _fit(id, _rng.randf_range(1.5, 3.0)))
				if col == 0 and _rng.randf() < 0.35:
					_put("nature/fence_simple", ground + Vector3(-side * block * 0.42, 0, _rng.randf_range(-3, 3)), _fit("nature/fence_simple", 4.0), PI * 0.5)
	# hills closing the valley far ahead
	for i in 9:
		var x := (i - 4) * 22.0 + _rng.randf_range(-5, 5)
		var z := -length - _rng.randf_range(150.0, 190.0)
		_put("nature/rock_tallE", Vector3(x, sea_level - 2.0, z), _fit("nature/rock_tallE", _rng.randf_range(26.0, 40.0)))
		_put("nature/tree_pineTallA", Vector3(x + _rng.randf_range(-12, 12), sea_level + 2.0, z + 22.0), _fit("nature/tree_pineTallA", 9.0))
	_ships(["pirate/ship_light", "pirate/ship_dark"], 3)

func _jitter(r: float) -> Vector3:
	return Vector3(_rng.randf_range(-r, r), 0, _rng.randf_range(-r, r))

# ------------------------------------------------------------- kitchen

func _kitchen() -> void:
	sea_level = -15.0
	_sea(Color("b8301a"), Color("e0582c"), Color("ffc58a"))  # tomato soup
	var counter := ["furniture/kitchenCabinet", "furniture/kitchenCabinet", "furniture/kitchenStove", "furniture/kitchenSink"]
	var w := 16.0
	var giant := ["food/tomato", "food/watermelon", "food/cheese", "food/bottleKetchup", "food/sodaCan",
		"food/loaf", "food/pie", "food/burger", "food/cupcake", "food/croissant", "food/broccoli", "food/carrot"]
	for side in [-1.0, 1.0]:
		var yaw := PI * 0.5 if side < 0 else -PI * 0.5
		for z in _span(w, 40.0, 100.0):
			var id: String = _pick(counter)
			var s := _fit(id, w)
			var base := Vector3(side * (clearance + w * 0.5), sea_level - 2.0, z)
			_put(id, base, s, yaw)
			var top := sea_level - 2.0 + Props.base_size(id).y * s
			if _rng.randf() < 0.6:
				var g: String = _pick(giant)
				_put(g, Vector3(side * (clearance + w * 0.4), top, z) + _jitter(3.0), _fit(g, _rng.randf_range(5.0, 9.0)))
		# appliances standing on the counters
		for k in 3:
			var app: String = _pick(["furniture/kitchenMicrowave", "furniture/kitchenCoffeeMachine", "furniture/kitchenBlender", "furniture/toaster"])
			var z := -length * (k + 0.5) / 3.0 + _rng.randf_range(-6, 6)
			_put(app, Vector3(side * (clearance + w * 0.45), sea_level - 2.0 + Props.base_size("furniture/kitchenCabinet").y * _fit("furniture/kitchenCabinet", w), z), _fit(app, 11.0), yaw)
	# the fridge and stove wall at the end
	for i in 5:
		var id: String = ["furniture/kitchenFridgeLarge", "furniture/kitchenStove", "furniture/kitchenFridgeLarge", "furniture/kitchenSink", "furniture/kitchenFridgeLarge"][i]
		_put(id, Vector3((i - 2) * 24.0, sea_level - 2.0, -length - 120.0), _fit(id, 24.0), 0.0)
	# bits of food floating in the soup
	for i in 30:
		var id: String = _pick(["food/tomato", "food/carrot", "food/broccoli", "food/croissant", "food/cookie"])
		var p := Vector3(_rng.randf_range(-clearance + 4, clearance - 4), sea_level - 0.4, _rng.randf_range(-length - 60, 40))
		if absf(p.x) < 8.0:
			p.x += signf(p.x + 0.01) * 8.0
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
	for z in _span(26.0, 60.0, 160.0):
		for side in [-1.0, 1.0]:
			var x: float = side * _rng.randf_range(clearance + 2.0, clearance + 70.0)
			var pos := Vector3(x, sea_level - 3.0, z + _rng.randf_range(-8, 8))
			var size := _rng.randf_range(14.0, 26.0)
			_put("pirate/formationLarge_rock", pos, _fit("pirate/formationLarge_rock", size))
			var top := sea_level - 3.0 + Props.base_size("pirate/formationLarge_rock").y * _fit("pirate/formationLarge_rock", size) * 0.35
			for k in _rng.randi_range(1, 3):
				_put("pirate/palm_detailed_long", Vector3(x, top, pos.z) + _jitter(size * 0.3), _fit("pirate/palm_detailed_long", _rng.randf_range(6.0, 9.0)))
			if _rng.randf() < 0.18:
				_put("pirate/tower", Vector3(x + side * 6.0, sea_level - 1.0, pos.z + 10.0), _fit("pirate/tower", 12.0))
	_ships(["pirate/ship_dark", "pirate/ship_light"], 6)
	for i in 14:
		var id: String = _pick(["platformer/barrel", "pirate/chest", "platformer/crate"])
		var p := Vector3(_rng.randf_range(-clearance, clearance), sea_level - 0.5, _rng.randf_range(-length - 60, 40))
		if absf(p.x) < 9.0:
			p.x += signf(p.x + 0.01) * 9.0
		var n := Props.sized(id, _rng.randf_range(1.6, 2.6))
		n.position = p
		Props.no_shadows(n)
		add_child(n)
		_drifters.append([n, p, 0.3, _rng.randf_range(0.7, 1.1), _rng.randf() * TAU, 0.4])

# ------------------------------------------------------------- shared

func _ships(ids: Array, n: int) -> void:
	for i in n:
		var side := -1.0 if i % 2 else 1.0
		var id: String = ids[i % ids.size()]
		var ship := Props.sized(id, _rng.randf_range(16.0, 22.0), 2)
		var p := Vector3(side * _rng.randf_range(clearance + 18.0, clearance + 60.0), sea_level - 1.2, _rng.randf_range(-length - 80.0, 30.0))
		if theme == "meadow":
			p.x = side * _rng.randf_range(10.0, clearance - 8.0)  # sailing up the river
		ship.position = p
		ship.rotation.y = _rng.randf_range(-0.3, 0.3) + (PI if _rng.randf() < 0.5 else 0.0)
		Props.no_shadows(ship)
		add_child(ship)
		_drifters.append([ship, p, 0.35, 0.7, _rng.randf() * TAU, 1.5])

func _clouds() -> void:
	var cloud := "models/cloud"
	for i in 26:
		var c := Props.make(cloud)
		var side := -1.0 if i % 2 else 1.0
		var p := Vector3(side * _rng.randf_range(12.0, 90.0), _rng.randf_range(6.0, 26.0), _rng.randf_range(-length - 120.0, 40.0))
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
