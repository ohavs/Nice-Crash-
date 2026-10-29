class_name Adventure
extends Level
## The open world: big zones you roam freely, one per island on the world
## map. Each is a valley of rolling ground (terrain.gd) ringed by mountains
## or sea, dressed with Quaternius' Stylized Nature MegaKit (trees, bushes,
## grass, flowers, rocks) and KayKit buildings, ruins and graveyards, with
## KayKit skeletons roaming about. Every zone has three missions (= three
## stars): find golden eggs, smash a skeleton camp, light lanterns, reach a
## summit, jam cannons... Skeleton hits, saws, spikes, hammers, cannonballs,
## rolling barrels and falling in the river each cost a heart; camps
## (campfires) are checkpoints that heal you. Play alone, with bot buddies or
## with friends online (see net.gd).

signal mission_changed(i: int)
signal all_done

const LEVELS := [
	{"id": "meadow", "name": "GREEN VALLEY", "theme": "meadow", "color": Color("6fd36b"),
		"blurb": "Golden eggs, a skeleton camp and Lookout Hill", "landmark": "nature/tree_oak"},
	{"id": "forest", "name": "MUSHROOM WOODS", "theme": "forest", "color": Color("b06ad8"),
		"blurb": "Bouncy mushrooms, lost lanterns, the Bone Chief", "landmark": "nature/mushroom_red"},
	{"id": "graveyard", "name": "SPOOKY HOLLOW", "theme": "graveyard", "color": Color("ff9b42"),
		"blurb": "Skeletons rise from their graves. Light the pumpkins!", "landmark": "kaykit/halloween/pumpkin_orange_jackolantern"},
	{"id": "cove", "name": "CANNON COVE", "theme": "pirate", "color": Color("4ea8ff"),
		"blurb": "Jam the cannons, beat the skeleton crew", "landmark": "pirate/ship_light"},
	{"id": "peaks", "name": "FROSTY PEAKS", "theme": "snow", "color": Color("9fe4ff"),
		"blurb": "Ice lakes, toy trains and a summit to climb", "landmark": "holiday/snowmanFancy"},
]

## Playable radius; mountains (or the sea) start here.
const R := 70.0
const Q := "quaternius/nature/"
const TREES := {
	"meadow": ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5", "Birch_1", "Birch_3"],
	"forest": ["GiantPine_1", "GiantPine_3", "Pine_1", "Pine_2", "Pine_3", "TwistedTree_1", "TallThick_1"],
	"graveyard": ["DeadTree_1", "DeadTree_2", "DeadTree_3", "TwistedTree_3"],
	"pirate": ["CommonTree_3", "CommonTree_5", "Birch_3"],
	"snow": ["Pine_1", "Pine_2", "Pine_3", "Pine_5"],
}
const GROUND := {
	"meadow": ["Grass_Common_Short", "Grass_Common_Tall", "Grass_Wispy_Tall", "Clover_1", "Flower_3_Group", "Flower_4_Group", "Flower_1_Group", "Flower_7_Group"],
	"forest": ["Fern_1", "Fern_2", "Grass_Wispy_Tall", "Grass_Common_Short", "Mushroom_Common", "Mushroom_RedCap", "Clover_1"],
	"graveyard": ["Grass_Wispy_Tall", "Grass_Wheat", "Fern_2", "Mushroom_Laetiporus", "Grass_Common_Short"],
	"pirate": ["Grass_Common_Short", "Grass_Wispy_Tall", "Fern_1", "Flower_4_Group"],
	"snow": ["Grass_Wheat", "Pebble_Round_1", "Pebble_Round_3"],
}
const BUSHES := {
	"meadow": ["Bush_Common", "Bush_Common_Flowers", "Bush_Large", "Plant_1_Big", "Bush_Long_1"],
	"forest": ["Bush_Large", "Plant_1_Big", "Fern_1", "Bush_Common"],
	"graveyard": ["Bush_Long_1", "Plant_7_Big", "Bush_Common"],
	"pirate": ["Bush_Common_Flowers", "Plant_1_Big", "Bush_Large"],
	"snow": ["Bush_Common", "Rock_Medium_2"],
}
const PALETTE := {
	"meadow": [Color(0.38, 0.56, 0.23), Color(0.52, 0.6, 0.27)],
	"forest": [Color(0.27, 0.44, 0.2), Color(0.36, 0.47, 0.22)],
	"graveyard": [Color(0.3, 0.34, 0.22), Color(0.38, 0.36, 0.25)],
	"pirate": [Color(0.4, 0.58, 0.25), Color(0.55, 0.6, 0.3)],
	"snow": [Color(0.88, 0.92, 0.97), Color(0.8, 0.86, 0.94)],
}
const DIRT := Color(0.55, 0.45, 0.31)
const SAND := Color(0.82, 0.73, 0.52)
const ROCK := Color(0.47, 0.46, 0.42)

var terrain: Terrain
var water_y := 0.0
## [{title, icon, need, got, done, spots: Array[Node3D]}]
var missions: Array = []
var enemies: Array[Enemy] = []
## Where we start (world) and the camps (checkpoints).
var spawn := Vector3.ZERO
var island := false

# height features (declared before the ground is built)
var _hills: Array = []    # [Vector2 centre, radius, height, flat top 0..1]
var _flats: Array = []    # [Vector2 centre, radius, height]
var _rivers: Array = []   # [PackedVector2Array, width]
var _lakes: Array = []    # [Vector2 centre, radius]
var _paths: Array = []    # [PackedVector2Array, width]
var _clear: Array = []    # [Vector2, radius]: keep plants away
var _noise := FastNoiseLite.new()
var _amp := 2.2
var _batch := {}          # "id|cx|cz" -> [id, Array[Transform3D], vis, shadows]
var _trunks: StaticBody3D
var _spikes: Array = []   # [node, area, phase, up]
var _hearts: Array = []   # [node, area, base_y, cooldown]
var _eggs: Array = []     # [node, base_y]

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
	id = info(level_id).id
	mode = "world"
	theme = info(id).theme
	_rng.seed = hash(id)
	_noise.seed = hash(id) + 3
	_noise.frequency = 0.012
	_noise.fractal_octaves = 3
	section(Vector3.ZERO)
	_trunks = StaticBody3D.new()
	_trunks.collision_layer = 1
	add_child(_trunks)
	match id:
		"forest":
			_forest_zone()
		"graveyard":
			_graveyard_zone()
		"cove":
			_cove_zone()
		"peaks":
			_peaks_zone()
		_:
			_meadow_zone()
	_flush()
	_walls()
	bounds = AABB(Vector3(-R, water_y - 2.0, -R), Vector3(R * 2.0, 30.0, R * 2.0))
	kill_y = water_y - 0.9
	center = spawn
	radius = R

# ================================================================ ground

func _height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := 2.4 + _noise.get_noise_2d(x, z) * _amp
	for hl in _hills:
		var d := p.distance_to(hl[0])
		h += hl[2] * (1.0 - smoothstep(hl[1] * hl[3], hl[1], d))
	for f in _flats:
		var d := p.distance_to(f[0])
		h = lerpf(h, f[2], 1.0 - smoothstep(f[1] * 0.75, f[1], d))
	var bed := water_y - 1.8
	for r in _rivers:
		var d := _line_dist(p, r[0])
		h = minf(h, lerpf(bed, h, smoothstep(r[1] * 0.35, r[1] * 0.5 + 4.0, d)))
	for l in _lakes:
		var d := p.distance_to(l[0])
		h = minf(h, lerpf(bed, h, smoothstep(l[1] * 0.75, l[1] + 4.0, d)))
	var out := p.length() - R
	if island:
		h = lerpf(h, bed - 2.0, smoothstep(-14.0, 6.0, out))
	elif out > -6.0:
		var ridge := absf(_noise.get_noise_2d(x * 0.6 + 400.0, z * 0.6)) * 10.0
		h += pow(maxf(out + 6.0, 0.0) / 14.0, 1.5) * 9.0 + ridge * smoothstep(-6.0, 20.0, out)
	return h

func _color(x: float, z: float, h: float, slope: float) -> Color:
	var p := Vector2(x, z)
	var pal: Array = PALETTE.get(theme, PALETTE.meadow)
	var c: Color = (pal[0] as Color).lerp(pal[1], clampf(_noise.get_noise_2d(x * 0.5 + 99.0, z * 0.5) * 1.5 + 0.5, 0.0, 1.0))
	var snow := theme == "snow"
	for pa in _paths:
		var d := _line_dist(p, pa[0])
		var k := 1.0 - smoothstep(pa[1] * 0.3, pa[1] * 0.5 + 0.8, d)
		if k > 0.0:
			c = c.lerp(Color(0.72, 0.75, 0.82) if snow else DIRT, k * 0.85)
	if h < water_y + 0.9:
		c = c.lerp(Color(0.6, 0.66, 0.74) if snow else SAND, smoothstep(water_y + 0.9, water_y + 0.2, h))
	if slope > 0.3:
		c = c.lerp(ROCK if not snow else Color(0.62, 0.66, 0.74), smoothstep(0.3, 0.55, slope))
	if not island and p.length() > R + 8.0 and h > 16.0 and not snow:
		c = c.lerp(ROCK, smoothstep(16.0, 22.0, h))
	if h > 24.0:
		c = c.lerp(Color(0.93, 0.95, 0.99), smoothstep(24.0, 28.0, h))
	return c

static func _line_dist(p: Vector2, line: PackedVector2Array) -> float:
	var best := INF
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best

func _make_ground() -> void:
	terrain = Terrain.new()
	terrain.size = (R + 50.0) * 2.0
	terrain.cell = 2.0
	terrain.height_fn = _height
	terrain.color_fn = _color
	add_child(terrain)
	terrain.build()
	var scenery_sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	pm.subdivide_width = 40
	pm.subdivide_depth = 40
	scenery_sea.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/water.gdshader")
	var cols := {"graveyard": [Color("1d3a3a"), Color("2f6b5f")], "snow": [Color("2a5d8f"), Color("7fc8e8")]}
	var wc: Array = cols.get(theme, [Color("1670b8"), Color("2fa9dc")])
	mat.set_shader_parameter("deep", wc[0])
	mat.set_shader_parameter("shallow", wc[1])
	mat.set_shader_parameter("foam", Color("e8fbff"))
	mat.set_shader_parameter("wave_height", 0.12)
	scenery_sea.material_override = mat
	scenery_sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scenery_sea.position.y = water_y - 0.35
	add_child(scenery_sea)

func ground(x: float, z: float) -> Vector3:
	return terrain.ground(x, z)

## Invisible ring wall just inside the mountains / out in the sea.
func _walls() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var n := 48
	var wr := R + (14.0 if island else 4.0)
	for i in n:
		var a := i * TAU / n
		var c := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(wr * TAU / n + 1.0, 80.0, 2.0)
		c.shape = bs
		c.position = Vector3(cos(a) * wr, 20.0, sin(a) * wr)
		c.rotation.y = -a + PI * 0.5
		body.add_child(c)

func _v2(x: float, z: float) -> Vector2:
	return Vector2(x, z)

func _line(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in pts:
		out.append(Vector2(q[0], q[1]))
	return out

## Is (x, z) fine for a plant: dry, not on a path, not somewhere kept clear?
func _free(x: float, z: float, slope_max := 0.4, path_gap := 1.5) -> bool:
	var p := Vector2(x, z)
	if p.length() > R + 4.0:
		return false
	if terrain.height_at(x, z) < water_y + 0.5 or terrain.slope_at(x, z) > slope_max:
		return false
	for pa in _paths:
		if _line_dist(p, pa[0]) < pa[1] * 0.5 + path_gap:
			return false
	for c in _clear:
		if p.distance_to(c[0]) < c[1]:
			return false
	return true

# ================================================================ batching

func _add(id_: String, pos: Vector3, s: float, yaw := -1.0, vis := 150.0, shadows := true, tilt := 0.0) -> void:
	var b := Basis(Vector3.UP, _rng.randf() * TAU if yaw < 0.0 else yaw)
	if tilt > 0.0:
		b = Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.0, tilt)) * b
	var cx := floori(pos.x / 40.0)
	var cz := floori(pos.z / 40.0)
	var key := "%s|%d|%d" % [id_, cx, cz]
	if not _batch.has(key):
		_batch[key] = [id_, [], vis, shadows]
	_batch[key][1].append(Transform3D(b.scaled(Vector3.ONE * s), pos))

func _flush() -> void:
	for key in _batch:
		var e: Array = _batch[key]
		add_child(Props.multi(e[0], e[1], e[3], e[2]))
	_batch.clear()

func _fit(id_: String, size_: float, axis := -1) -> float:
	var s := Props.base_size(id_)
	var ref: float = maxf(s.x, s.z) if axis < 0 else s[axis]
	return size_ / maxf(ref, 0.001)

## A tree you bump into (trunk collider), drawn in a batch.
func _tree(name_: String, x: float, z: float, height: float) -> void:
	var id_ := Q + name_
	var s := height / Props.base_size(id_).y
	var g := ground(x, z)
	_add(id_, g - Vector3(0, 0.15, 0), s, -1.0, 160.0, true)
	var c := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = clampf(height * 0.04, 0.3, 0.8)
	cs.height = 4.0
	c.shape = cs
	c.position = g + Vector3(0, 2.0, 0)
	_trunks.add_child(c)

func _woods(cx: float, cz: float, r: float, n: int, hmin := 6.0, hmax := 10.0, names: Array = []) -> void:
	var ids: Array = names if not names.is_empty() else TREES.get(theme, TREES.meadow)
	var placed := 0
	var tries := 0
	while placed < n and tries < n * 8:
		tries += 1
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * r
		var x := cx + cos(a) * d
		var z := cz + sin(a) * d
		if not _free(x, z, 0.35, 2.5):
			continue
		_tree(ids[_rng.randi() % ids.size()], x, z, _rng.randf_range(hmin, hmax))
		placed += 1

## Ground cover all over the zone: grass, flowers, ferns (near only) and
## bushes (a bit further).
func _cover(grass: int, bushes: int) -> void:
	var g: Array = GROUND.get(theme, GROUND.meadow)
	var b: Array = BUSHES.get(theme, BUSHES.meadow)
	for i in grass:
		var x := _rng.randf_range(-R, R)
		var z := _rng.randf_range(-R, R)
		if not _free(x, z, 0.45, 0.3):
			continue
		var id_: String = Q + g[_rng.randi() % g.size()]
		_add(id_, ground(x, z) - Vector3(0, 0.05, 0), _rng.randf_range(0.7, 1.25), -1.0, 34.0, false)
	for i in bushes:
		var x := _rng.randf_range(-R, R)
		var z := _rng.randf_range(-R, R)
		if not _free(x, z, 0.4, 1.0):
			continue
		var id_: String = Q + b[_rng.randi() % b.size()]
		_add(id_, ground(x, z) - Vector3(0, 0.1, 0), _rng.randf_range(0.8, 1.4), -1.0, 70.0, false)

## Boulder: solid (convex collider), sits a little into the ground.
func _rock(name_: String, x: float, z: float, size_: float, yaw := -1.0) -> StaticBody3D:
	var id_ := Q + name_
	var g := ground(x, z)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	body.position = g - Vector3(0, size_ * 0.12, 0)
	body.rotation.y = _rng.randf() * TAU if yaw < 0.0 else yaw
	var m := Props.make(id_)
	m.scale = Vector3.ONE * _fit(id_, size_)
	body.add_child(m)
	for mi: MeshInstance3D in Props.meshes(m):
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_convex_shape(true, true)
		body.add_child(cs)
		cs.transform = _rel(body, mi)
	_clear.append([Vector2(x, z), size_ * 0.5])
	return body

## Transform of `n` relative to `ancestor` (works before entering the tree).
func _rel(ancestor: Node3D, n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != null and p != ancestor and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t

func _rocks(n: int, smin := 1.5, smax := 4.0) -> void:
	var ids := ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3", "Rock_Big_1", "Rock_Big_2"]
	var placed := 0
	var tries := 0
	while placed < n and tries < n * 10:
		tries += 1
		var x := _rng.randf_range(-R, R)
		var z := _rng.randf_range(-R, R)
		if not _free(x, z, 0.35, 3.0):
			continue
		_rock(ids[_rng.randi() % ids.size()], x, z, _rng.randf_range(smin, smax))
		placed += 1

## Static prop with an exact (trimesh) collider: buildings, ruins, bridges.
## `pos` is world, base on the ground.
func _build(id_: String, pos: Vector3, size_: float, yaw := 0.0, solid := true, axis := -1) -> Node3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	body.position = pos
	body.rotation.y = yaw
	var m := Props.make(id_)
	m.scale = Vector3.ONE * _fit(id_, size_, axis)
	body.add_child(m)
	if solid:
		for mi: MeshInstance3D in Props.meshes(m):
			var cs := CollisionShape3D.new()
			cs.shape = mi.mesh.create_trimesh_shape()
			body.add_child(cs)
			cs.transform = _rel(body, mi)
	var bs := Props.base_size(id_) * m.scale.x
	_clear.append([Vector2(pos.x, pos.z), maxf(bs.x, bs.z) * 0.6])
	return body

## Decoration without collision, on the ground at x/z.
func _put(id_: String, x: float, z: float, size_: float, yaw := -1.0) -> Node3D:
	var n := Props.sized(id_, size_)
	n.position = ground(x, z)
	n.rotation.y = _rng.randf() * TAU if yaw < 0.0 else yaw
	add_child(n)
	return n

func _start(x: float, z: float, facing: float) -> void:
	spawn = ground(x, z)
	for i in 5:
		var off := Vector3((i - 2) * 1.9, 0, 0).rotated(Vector3.UP, facing)
		starts.append(ground(x + off.x, z + off.z) + Vector3(0, 0.1, 0))
	start_dir = Vector3.FORWARD.rotated(Vector3.UP, facing)
	path.append(spawn + Vector3.UP * 0.5)
	path.append(spawn + start_dir * 10.0 + Vector3.UP * 0.5)
	_clear.append([Vector2(x, z), 7.0])
	_camp(x + 5.0, z + 2.0, false)

# ================================================================ things

## Campfire: a checkpoint that patches you up.
func _camp(x: float, z: float, tent := true) -> void:
	_checkpoints += 1
	var idx := _checkpoints
	var g := ground(x, z)
	var fire := Props.sized("nature/campfire_logs", 1.6)
	fire.position = g
	add_child(fire)
	_flame(g + Vector3(0, 0.35, 0), 0.9)
	if tent:
		_put("kaykit/medieval/tent", x + 2.6, z - 1.2, 3.2, _rng.randf() * TAU)
	var light := OmniLight3D.new()
	light.light_color = Color("ffb35c")
	light.light_energy = 1.4 if theme == "graveyard" else 0.7
	light.omni_range = 7.0
	light.position = g + Vector3(0, 1.0, 0)
	add_child(light)
	_clear.append([Vector2(x, z), 4.0])
	var area := _area(g + Vector3(0, 1.0, 0), _cyl(3.6, 3.0))
	area.body_entered.connect(func(b):
		if not b is Player or b.is_enemy or b.puppet:
			return
		var p := b as Player
		var healed := p.max_hp > 0 and p.hp < p.max_hp
		if healed:
			p.heal(p.max_hp)
		if p.checkpoint_i != idx:
			p.checkpoint_i = idx
			p.checkpoint = g + Vector3(1.8, 0, 1.8)
			if p.is_human:
				Game.play("coin")
				Fx.word(self, g + Vector3.UP * 2.0, "CAMP!", UI.YELLOW, 1.1)
		elif healed and p.is_human:
			Game.play("powerup", 0.05, -6.0))

## Flickering flame from Kenney's particle pack.
func _flame(pos: Vector3, size_: float) -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size_
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/kenney/particles/light_02.png")
	m.albedo_color = Color(1.0, 0.62, 0.25)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.mesh = q
	p.amount = 10
	p.lifetime = 0.8
	p.direction = Vector3.UP
	p.spread = 15.0
	p.gravity = Vector3(0, 1.5, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = size_ * 0.2
	add_child(p)
	p.global_position = pos

func _mission(title: String, icon: String, need: int) -> int:
	missions.append({"title": title, "icon": icon, "need": need, "got": 0, "done": false, "spots": []})
	return missions.size() - 1

func advance(mi: int, n := 1) -> void:
	if mi < 0 or mi >= missions.size() or missions[mi].done:
		return
	var m: Dictionary = missions[mi]
	m.got = mini(m.got + n, m.need)
	if m.got >= m.need:
		m.done = true
	mission_changed.emit(mi)
	if missions.all(func(x): return x.done):
		all_done.emit()

## Sets a mission's progress (network clients follow the host).
func set_progress(mi: int, got: int) -> void:
	if mi < 0 or mi >= missions.size():
		return
	var m: Dictionary = missions[mi]
	if got <= m.got:
		return
	advance(mi, got - m.got)

func stars() -> int:
	return missions.filter(func(m): return m.done).size()

## Nearest thing still to do (compass): [position, mission index] or [].
func next_target(from: Vector3) -> Array:
	var best := []
	var best_d := INF
	for i in missions.size():
		var m: Dictionary = missions[i]
		if m.done:
			continue
		for s in m.spots:
			if not is_instance_valid(s) or not (s as Node3D).is_inside_tree():
				continue
			if s is Enemy and (s as Enemy).is_dead():
				continue
			var d := from.distance_to((s as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = [(s as Node3D).global_position, i]
	return best

## Golden egg: collect them all.
func _golden_egg(pos: Vector3, mi: int) -> void:
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = pos + Vector3.UP * 0.7
	var egg := Props.sized("food/egg", 0.75, 1)
	Props.tint(egg, Color("ffc430"), 0.85)
	holder.add_child(egg)
	_beam(holder, Color("ffd23f"))
	missions[mi].spots.append(holder)
	_eggs.append([holder, holder.position.y])
	var area := _area(holder.global_position, _sphere(0.9))
	area.body_entered.connect(func(b):
		if not b is Player or b.is_enemy or b.puppet or not holder.visible:
			return
		_take_egg(holder, mi, true))
	holder.set_meta("area", area)

func _take_egg(holder: Node3D, mi: int, local: bool) -> void:
	if not holder.visible:
		return
	holder.visible = false
	(holder.get_meta("area") as Area3D).set_deferred("monitoring", false)
	missions[mi].spots.erase(holder)
	Fx.burst(self, holder.global_position, "food/egg", 8, 0.2, 5.0)
	Fx.word(self, holder.global_position + Vector3.UP * 0.8, "GOLDEN EGG!", UI.YELLOW, 1.1)
	Game.play("powerup", 0.05, -2.0)
	if local:
		Net.world_event("egg", [_eggs.find_custom(func(e): return e[0] == holder)])
		advance(mi)

## Network: someone else picked up egg `i`.
func remote_egg(i: int) -> void:
	if i < 0 or i >= _eggs.size():
		return
	var holder: Node3D = _eggs[i][0]
	for mi in missions.size():
		if holder in missions[mi].spots:
			_take_egg(holder, mi, false)
			return

## Soft light shaft over mission things, seen from far away.
func _beam(parent: Node3D, color: Color) -> void:
	var s := Sprite3D.new()
	s.texture = load("res://assets/kenney/particles/light_02.png")
	s.modulate = Color(color, 0.55)
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.shaded = false
	s.no_depth_test = false
	s.pixel_size = 0.012
	s.scale = Vector3(1.0, 8.0, 1.0)
	s.position.y = 6.0
	s.render_priority = -1
	(s as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(s)

func spawn_enemy(kind: String, x: float, z: float, mi := -1, awake := true, leash := 16.0) -> Enemy:
	var e := Enemy.new()
	e.kind = kind
	e.mission = mi
	e.awake = awake
	e.leash = leash
	e.net_id = enemies.size()
	var g := ground(x, z)
	e.home = g
	add_child(e)
	e.global_position = g + Vector3.UP * 0.2
	e.rotation.y = _rng.randf() * TAU
	enemies.append(e)
	if mi >= 0:
		missions[mi].spots.append(e)
	e.died.connect(_on_enemy_died)
	return e

func _on_enemy_died(e: Enemy, _by: Player) -> void:
	if e.mission >= 0:
		missions[e.mission].spots.erase(e)
		if not Net.is_client():
			advance(e.mission)
	if not Net.is_client() and randf() < 0.3:
		_heart(e.global_position.x, e.global_position.z, false)

## Lantern / jack-o'-lantern: touch it to light it up.
func _lantern(x: float, z: float, mi: int, unlit := "kaykit/halloween/lantern_standing", lit := "", size_ := 2.2) -> void:
	var g := ground(x, z)
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = g
	var m := Props.sized(unlit, size_, 1)
	holder.add_child(m)
	Props.tint(m, Color("4a4550"), 0.35)
	_beam(holder, Color("ffb35c"))
	missions[mi].spots.append(holder)
	_clear.append([Vector2(x, z), 2.0])
	var body := StaticBody3D.new()
	body.collision_layer = 1
	holder.add_child(body)
	_cyl_col(body, size_ * 0.18, size_, Vector3(0, size_ * 0.5, 0))
	var area := _area(g + Vector3(0, 1.0, 0), _cyl(1.8, 3.0))
	holder.set_meta("idx", _switches.size())
	_switches.append([holder, mi, lit, size_])
	area.body_entered.connect(func(b):
		if b is Player and not b.is_enemy and not b.puppet and missions[mi].spots.has(holder):
			_light(holder, true))

var _switches: Array = []  # [holder, mission, lit model, size]

func _light(holder: Node3D, local: bool) -> void:
	var e: Array = _switches[holder.get_meta("idx")]
	var mi: int = e[1]
	if not missions[mi].spots.has(holder):
		return
	missions[mi].spots.erase(holder)
	for c in holder.get_children():
		if c is Sprite3D:
			c.queue_free()
	var m: Node3D = holder.get_child(0)
	if e[2] != "":
		m.queue_free()
		var lit := Props.sized(e[2], e[3], 1)
		holder.add_child(lit)
	else:
		Props.tint(m, Color.WHITE, 0.0)
	_flame(holder.global_position + Vector3(0, e[3] * (0.55 if e[2] != "" else 0.75), 0), 0.6)
	var light := OmniLight3D.new()
	light.light_color = Color("ffb35c")
	light.light_energy = 1.6
	light.omni_range = 8.0
	light.position.y = e[3] * 0.7
	holder.add_child(light)
	Game.play("ding", 0.05, -2.0)
	var word := "LIT!"
	if e.size() > 4:
		# a cannon's fuse: it droops and stops firing
		var c: Array = _cannons[e[4]]
		c[4] = 0.0
		var pivot: Node3D = c[0]
		pivot.create_tween().tween_property(pivot, "rotation:x", -0.5, 0.4)
		word = "JAMMED!"
	Fx.word(self, holder.global_position + Vector3.UP * 2.6, word, UI.YELLOW, 1.1)
	if local:
		Net.world_event("light", [holder.get_meta("idx")])
		advance(mi)

func remote_light(i: int) -> void:
	if i >= 0 and i < _switches.size():
		_light(_switches[i][0], false)

## Get here to complete mission `mi` (summit flag, crypt door, chest).
func _goal(pos: Vector3, mi: int, model := "models/flag", size_ := 2.4) -> void:
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = pos
	var m := Props.sized(model, size_, 1)
	holder.add_child(m)
	_beam(holder, UI.TEAL)
	missions[mi].spots.append(holder)
	holder.set_meta("idx", _goals.size())
	_goals.append([holder, mi])
	var area := _area(pos + Vector3(0, 1.0, 0), _cyl(2.4, 3.5))
	area.body_entered.connect(func(b):
		if b is Player and not b.is_enemy and not b.puppet and missions[mi].spots.has(holder):
			_reach(holder, true))

var _goals: Array = []

func _reach(holder: Node3D, local: bool) -> void:
	var mi: int = _goals[holder.get_meta("idx")][1]
	if not missions[mi].spots.has(holder):
		return
	missions[mi].spots.erase(holder)
	for c in holder.get_children():
		if c is Sprite3D:
			c.queue_free()
	Fx.burst(self, holder.global_position + Vector3.UP * 1.5, "models/coin", 16, 0.3, 7.0)
	Game.play("vo_congratulations", 0.0, -2.0)
	var tw := holder.create_tween()
	tw.tween_property(holder, "scale", Vector3.ONE * 1.4, 0.15)
	tw.tween_property(holder, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC)
	if local:
		Net.world_event("reach", [holder.get_meta("idx")])
		advance(mi)

func remote_reach(i: int) -> void:
	if i >= 0 and i < _goals.size():
		_reach(_goals[i][0], false)

## Heart pickup: +1 heart (grows back after a while unless `regrow` is off).
func _heart(x: float, z: float, regrow := true, y := -INF) -> void:
	var g := ground(x, z)
	if y > -INF:
		g.y = y
	var h := Props.sized("platformer/heart", 0.7)
	add_child(h)
	h.global_position = g + Vector3.UP * 0.8
	var area := _area(h.global_position, _sphere(0.8))
	var entry := [h, area, h.position.y, 0.0, regrow]
	_hearts.append(entry)
	area.body_entered.connect(func(b):
		if not b is Player or b.is_enemy or not h.visible or b.puppet:
			return
		if (b as Player).heal(1):
			h.visible = false
			entry[3] = 25.0
			area.set_deferred("monitoring", false)
			Fx.burst(self, h.global_position, "platformer/heart", 6, 0.2, 4.0)
			Game.play("powerup", 0.05, -4.0 if b.is_human else -16.0))

## Spike trap: KayKit floor spikes that shoot up every few seconds.
func _spike_trap(x: float, z: float, phase := 0.0) -> void:
	var g := ground(x, z)
	var tile := Props.sized("kaykit/dungeon/floor_tile_big_spikes", 3.0)
	tile.position = g - Vector3(0, 0.05, 0)
	add_child(tile)
	var spikes: Node3D = tile
	var area := _area(g + Vector3(0, 0.5, 0), _box(Vector3(2.6, 1.0, 2.6)))
	_spikes.append([spikes, area, phase, false, g.y - 0.05])
	_clear.append([Vector2(x, z), 2.2])

func _box(size_: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size_
	return b

## Coins along the ground from a to b (x/z pairs).
func _coin_trail(a: Vector2, b: Vector2, n: int) -> void:
	for i in n:
		var p := a.lerp(b, i / maxf(n - 1.0, 1.0))
		_coin(ground(p.x, p.y) + Vector3.UP * 0.7)

## Plank bridge between two ground points (world x/z), `w` wide.
func _plank_bridge(a: Vector2, b: Vector2, w := 3.0) -> void:
	var ga := ground(a.x, a.y) + Vector3.UP * 0.25
	var gb := ground(b.x, b.y) + Vector3.UP * 0.25
	var top := maxf(maxf(ga.y, gb.y), water_y + 0.6)
	_ramp(Vector3(ga.x, top, ga.z), Vector3(gb.x, top, gb.z), w, "planks")

# ================================================================ update

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	for s in _spikes:
		var node: Node3D = s[0]
		var c := fmod(_t * 0.5 + s[2], 1.0)
		var up := c > 0.55 and c < 0.85
		var target_y: float = s[4] + (0.0 if up else -1.2)
		node.position.y = lerpf(node.position.y, target_y, minf(delta * (18.0 if up else 4.0), 1.0))
		if up and not s[3]:
			Game.play("chop", 0.2, -16.0)
			for b in (s[1] as Area3D).get_overlapping_bodies():
				if b is Player and not b.puppet and not b.is_crashed:
					(b as Player).hit(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 3.0 + Vector3.UP * 8.0)
					Fx.word(self, b.global_position + Vector3.UP, "OUCH!", UI.CORAL)
		s[3] = up

func _process(delta: float) -> void:
	super._process(delta)
	for e in _eggs:
		var n: Node3D = e[0]
		if n.visible:
			n.rotation.y += delta * 2.0
			n.position.y = e[1] + sin(_t * 2.2 + n.position.x) * 0.15
	for e in _hearts:
		var h: Node3D = e[0]
		if e[3] > 0.0:
			e[3] -= delta
			if e[3] <= 0.0 and e[4]:
				h.visible = true
				(e[1] as Area3D).monitoring = true
		h.rotation.y += delta * 2.5
		h.position.y = e[2] + sin(_t * 3.0) * 0.12

# ================================================================ 1 meadow

func _meadow_zone() -> void:
	# lookout hill (NE), the farm (SW), skeleton camp (W), a river with a
	# bridge across the middle, a lake with an island (SE)
	_hills.append([_v2(34, -36), 30.0, 8.0, 0.25])
	_hills.append([_v2(-48, -46), 16.0, 4.0, 0.2])
	_hills.append([_v2(-52, 22), 18.0, 3.0, 0.3])
	_flats.append([_v2(0, 50), 12.0, 2.6])
	_flats.append([_v2(-30, 36), 18.0, 2.6])
	_flats.append([_v2(-38, -26), 16.0, 3.0])
	_flats.append([_v2(0, -14), 10.0, 2.4])
	_rivers.append([_line([[-80, -14], [-40, -6], [-12, 4], [8, 6], [30, -4], [80, 8]]), 9.0])
	_lakes.append([_v2(36, 34), 13.0])
	_hills.append([_v2(36, 34), 4.5, 3.6, 0.5])  # the island
	_paths.append([_line([[0, 54], [0, 24], [0, 5], [0, -14]]), 3.2])
	_paths.append([_line([[0, -14], [-14, -20], [-30, -24]]), 2.8])
	_paths.append([_line([[0, -14], [12, -22], [24, -30], [34, -36]]), 2.8])
	_paths.append([_line([[0, 26], [-14, 32], [-26, 36]]), 2.8])
	_paths.append([_line([[0, 26], [14, 30], [22, 32]]), 2.6])
	_make_ground()
	_start(0, 50, 0.0)
	var m_eggs := _mission("Find the golden eggs", "coin", 6)
	var m_camp := _mission("Smash the skeleton camp", "act", 6)
	var m_hill := _mission("Climb Lookout Hill", "flag", 1)

	# bridge over the river on the main path
	_build("kaykit/medieval/building_bridge_A", ground(0, 4) + Vector3(0, -0.4, 0), 9.0, 0.0, true, 2)
	_clear.append([_v2(0, 4), 7.0])
	# farm village
	var farm := [["building_home_A_blue", -36, 30, 6.0, 0.6], ["building_home_B_red", -24, 42, 6.5, -2.4],
		["building_windmill_red", -40, 44, 7.5, 0.9], ["building_well_blue", -28, 31, 3.2, 0.0],
		["building_market_red", -18, 40, 6.0, 2.6]]
	for f in farm:
		_build("kaykit/medieval/" + f[0], ground(f[1], f[2]), f[3], f[4])
	for k in 6:
		_build("kaykit/medieval/fence_wood_straight", ground(-44 + k * 3.4, 22), 3.4, 0.0)
	_put("kaykit/medieval/wheelbarrow", -30, 39, 1.6)
	_put("kaykit/medieval/sack", -33, 35, 0.9)
	_put("kaykit/medieval/crate_A_big", -21, 33, 1.2)
	_put("kaykit/medieval/resource_lumber", -42, 36, 2.4)
	_camp(-26, 26)
	_bounce_pad(ground(-14, 44) + Vector3.UP * 0.05, Vector3(0, 14, 0))
	_golden_egg(ground(-14, 44) + Vector3.UP * 9.0, m_eggs)
	_crates(ground(-22, 30), 3)
	# lake + island (stepping stones)
	for st in [[26, 28], [29, 31], [32, 33.5]]:
		_rock("Rock_Medium_2", st[0], st[1], 2.6, 0.0)
	_golden_egg(ground(36, 34), m_eggs)
	_tree("CommonTree_4", 37.5, 35.5, 6.0)
	_heart(34, 32)
	# the skeleton camp
	var cx := -38.0
	var cz := -26.0
	for t in [[cx - 6, cz - 4], [cx + 5, cz - 6], [cx - 2, cz + 6]]:
		_put("kaykit/medieval/tent", t[0], t[1], 3.4)
	_build("kaykit/dungeon/wall_broken", ground(cx - 9, cz + 1), 5.0, PI * 0.5)
	_build("kaykit/dungeon/wall_arched", ground(cx + 1, cz - 11), 5.0, 0.0)
	_build("kaykit/dungeon/column", ground(cx + 8, cz + 4), 1.4, 0.0)
	_build("kaykit/dungeon/crates_stacked", ground(cx + 7, cz - 1), 2.2, 0.4)
	_put("kaykit/dungeon/banner_patternA_red", cx + 3, cz + 8, 2.0, PI)
	_put("kaykit/dungeon/barrel_large", cx - 7, cz + 4, 1.3)
	var fire := Props.sized("nature/campfire_logs", 1.6)
	fire.position = ground(cx, cz)
	add_child(fire)
	_flame(ground(cx, cz) + Vector3.UP * 0.35, 0.9)
	for e in [["minion", -2, 2], ["minion", 3, -2], ["minion", -4, -5], ["minion", 5, 4], ["warrior", 0, -2], ["rogue", -6, 1]]:
		spawn_enemy(e[0], cx + e[1], cz + e[2], m_camp, true, 14.0)
	_golden_egg(ground(cx - 4, cz - 12), m_eggs)
	_item_box(ground(-22, -20) + Vector3.UP * 1.0)
	_item_box(ground(-24, -16) + Vector3.UP * 1.0)
	_camp(-16, -14)
	# spikes guarding the old ruins north of the hub
	for k in 3:
		_spike_trap(-8 + k * 3.2, -30, k * 0.2)
	_build("kaykit/dungeon/pillar", ground(-12, -32), 1.4, 0.0)
	_build("kaykit/dungeon/pillar", ground(6, -32), 1.4, 0.0)
	_golden_egg(ground(-1.6, -36), m_eggs)
	# lookout hill: barrels roll down the path, hammers on the way up
	_camp(10, -18)
	var top := ground(34, -36)
	_build("kaykit/medieval/building_tower_A_red", ground(39, -40), 5.0, 0.6)
	_goal(top + Vector3(0, 0, 3), m_hill)
	_roller_spawn(top + Vector3(-4, 1.5, 3), 2.0, 2.4, "barrel", 4.0)
	_rollers[-1][5] = (ground(12, -22) - top).normalized() * 4.5
	_hammer(ground(22, -29) + Vector3(0, 6.5, 0), 0.0, 1.7)
	_golden_egg(ground(44, -30), m_eggs)
	_heart(20, -26)
	# wanderers by the river
	spawn_enemy("minion", 14, 14)
	spawn_enemy("minion", -12, 12)
	spawn_enemy("rogue", 24, -12)
	# a forest up north, groves around, pines in the west
	_woods(0, -54, 16, 26)
	_woods(-56, 4, 12, 12, 6.0, 9.0, ["Pine_1", "Pine_2", "Pine_3"])
	_woods(54, 2, 12, 10)
	_woods(-12, 30, 6, 4)
	_woods(50, 48, 12, 8)
	_woods(-50, 50, 12, 10, 6.0, 9.0, ["Birch_1", "Birch_3"])
	_rocks(14)
	_cover(3800, 260)
	_coin_trail(_v2(0, 40), _v2(0, 14), 6)
	_coin_trail(_v2(-4, -16), _v2(-24, -22), 5)
	_coin_trail(_v2(4, 28), _v2(18, 31), 4)

# ================================================================ 2 forest

func _forest_zone() -> void:
	_amp = 3.4
	_hills.append([_v2(-38, -20), 18.0, 7.0, 0.75])  # the mushroom ledge (steep: bounce up)
	_hills.append([_v2(30, -40), 22.0, 6.0, 0.3])
	_flats.append([_v2(0, 50), 10.0, 2.6])
	_flats.append([_v2(6, -6), 16.0, 2.8])   # the ruins clearing
	_flats.append([_v2(40, 22), 12.0, 3.0])  # archers' den
	_rivers.append([_line([[-80, 30], [-40, 26], [-10, 22], [20, 30], [80, 20]]), 10.0])
	_paths.append([_line([[0, 54], [0, 32], [0, 18], [4, -6]]), 3.0])
	_paths.append([_line([[4, -6], [-20, -12], [-28, -14]]), 2.6])
	_paths.append([_line([[4, -6], [20, 8], [38, 20]]), 2.6])
	_paths.append([_line([[4, -6], [18, -28], [30, -40]]), 2.6])
	_make_ground()
	_start(0, 50, 0.0)
	var m_lamps := _mission("Light the lost lanterns", "flag", 4)
	var m_chief := _mission("Defeat the Bone Chief", "act", 1)
	var m_eggs := _mission("Find the golden eggs", "coin", 5)
	# log bridge with a saw over the ravine, or ride the raft
	_plank_bridge(_v2(0, 32), _v2(0, 14), 3.2)
	_saw(Vector3(0, ground(0, 23).y + 0.9, 23).max(Vector3(0, water_y + 1.5, 23)), 2.6, 0.0, 1.4)
	_ferry(Vector3(-14, water_y + 0.1, 32), Vector3(-14, water_y + 0.1, 14), Vector2(3.6, 3.6), 7.0)
	_camp(6, 10)
	# giant mushroom trampolines up to the ledge
	var ledge := ground(-38, -20)
	for mp in [[-22, -12], [-24, -24]]:
		var g := ground(mp[0], mp[1])
		var to := (ledge - g)
		to.y = 0
		_mushroom(g, 2.2, 4.0, Vector3(to.normalized().x * 5.0, 15.0, to.normalized().z * 5.0))
		_clear.append([_v2(mp[0], mp[1]), 3.0])
	_lantern(-40, -22, m_lamps)
	_golden_egg(ledge + Vector3(4, 0, 6), m_eggs)
	_camp(-34, -14)
	# mushroom tops hold eggs too
	for mp in [[24, 40], [-46, 40]]:
		var g := ground(mp[0], mp[1])
		_mushroom(g, 2.0, 4.0, Vector3(0, 15.0, 0))
		_golden_egg(g + Vector3.UP * 9.5, m_eggs)
		_clear.append([_v2(mp[0], mp[1]), 3.0])
	# the ruins and the Bone Chief
	for c in [[-4, -14], [16, -14], [-4, 2], [16, 2]]:
		_build("kaykit/dungeon/pillar", ground(c[0], c[1]), 1.6, 0.0)
	_build("kaykit/dungeon/wall_arched", ground(6, -18), 6.0, 0.0)
	_build("kaykit/dungeon/rubble_large", ground(-2, -10), 3.0, 0.5)
	var chief := spawn_enemy("chief", 6, -8, m_chief, true, 16.0)
	chief.aggro = 12.0
	spawn_enemy("warrior", 2, -4)
	spawn_enemy("warrior", 10, -4)
	_item_box(ground(-2, 6) + Vector3.UP)
	_item_box(ground(14, 6) + Vector3.UP)
	_lantern(6, -24, m_lamps)
	# archers' den in the east, lantern behind it
	for e in [[36, 18], [44, 24], [40, 26]]:
		spawn_enemy("rogue", e[0], e[1])
	spawn_enemy("minion", 38, 22)
	_build("kaykit/dungeon/crates_stacked", ground(42, 18), 2.4, 0.3)
	_lantern(46, 20, m_lamps)
	_golden_egg(ground(34, 26), m_eggs)
	_camp(24, 10)
	# the hill: logs (barrels) rolling down, spikes, lantern on top
	var hill := ground(30, -40)
	_roller_spawn(hill + Vector3(-3, 1.6, 2), 2.5, 2.2, "barrel", 4.0)
	_rollers[-1][5] = (ground(18, -26) - hill).normalized() * 4.5
	for k in 3:
		_spike_trap(18 + k * 3.0, -27 - k * 2.2, k * 0.25)
	_lantern(32, -42, m_lamps)
	_golden_egg(ground(40, -46), m_eggs)
	_heart(24, -32)
	_heart(-30, -8)
	spawn_enemy("minion", -10, 36)
	spawn_enemy("mage", 20, -18)
	# deep woods
	_woods(-30, 0, 30, 46, 9.0, 16.0)
	_woods(34, -4, 18, 18, 9.0, 15.0)
	_woods(-30, 50, 20, 18, 8.0, 14.0)
	_woods(40, 48, 14, 12, 8.0, 14.0)
	_woods(-10, -50, 18, 20, 9.0, 16.0)
	_rocks(16)
	_cover(3400, 300)
	_coin_trail(_v2(0, 46), _v2(0, 34), 4)
	_coin_trail(_v2(8, -2), _v2(34, 18), 6)

# ================================================================ 3 graveyard

func _graveyard_zone() -> void:
	_amp = 1.8
	_flats.append([_v2(0, 50), 10.0, 2.4])
	_flats.append([_v2(0, 6), 26.0, 2.6])     # the graveyard
	_flats.append([_v2(0, -40), 14.0, 4.5])   # the crypt mound
	_hills.append([_v2(0, -40), 22.0, 2.0, 0.5])
	_lakes.append([_v2(-42, -18), 14.0])
	_paths.append([_line([[0, 54], [0, 30], [0, -30]]), 3.4])
	_paths.append([_line([[0, 6], [-24, 6]]), 2.6])
	_paths.append([_line([[0, 6], [26, 6]]), 2.6])
	_make_ground()
	_start(0, 50, 0.0)
	var m_pump := _mission("Light the jack-o'-lanterns", "flag", 5)
	var m_bones := _mission("Smash the risen skeletons", "act", 10)
	var m_crypt := _mission("Open the crypt", "lock", 1)
	var H := "kaykit/halloween/"
	# fenced graveyard with an arched gate
	_build(H + "arch_gate", ground(0, 26), 6.0, 0.0)
	for k in 5:
		_build(H + "fence", ground(-6.5 - k * 4.0, 26), 4.0, 0.0)
		_build(H + "fence" if k % 2 == 0 else H + "fence_broken", ground(6.5 + k * 4.0, 26), 4.0, 0.0)
	var graves := [H + "grave_A", H + "grave_B", H + "gravestone", H + "gravemarker_A", H + "gravemarker_B", H + "grave_A_destroyed"]
	var risen := 0
	for gx in range(-20, 24, 6):
		for gz in range(-8, 22, 6):
			if absf(gx) < 4.0:
				continue
			var x := gx + _rng.randf_range(-1.0, 1.0)
			var z := gz + _rng.randf_range(-1.0, 1.0)
			_build(graves[_rng.randi() % graves.size()], ground(x, z), _rng.randf_range(1.6, 2.4), _rng.randf_range(-0.2, 0.2), true, 0)
			if _rng.randf() < 0.32 and risen < 10:
				risen += 1
				spawn_enemy("minion" if risen % 3 else "warrior", x + 1.6, z + 1.6, m_bones, false, 12.0)
	while risen < 10:
		risen += 1
		spawn_enemy("minion", _rng.randf_range(-16, 16), _rng.randf_range(-4, 18), m_bones, false, 12.0)
	_put(H + "shrine_candles", 0, 10, 3.0, PI)
	_put(H + "bench_decorated", -8, 14, 2.6, PI * 0.5)
	_item_box(ground(-3, 18) + Vector3.UP)
	_item_box(ground(3, 18) + Vector3.UP)
	_camp(6, 34)
	# pumpkins to light, around the zone
	for p in [[-28, 6], [28, 6], [-24, -30], [30, -24], [-30, 36]]:
		_lantern(p[0], p[1], m_pump, H + "pumpkin_orange", H + "pumpkin_orange_jackolantern", 1.8)
		spawn_enemy("mage" if p[1] < 0 else "minion", p[0] + 3.0, p[1] + 2.0, -1, false)
	# the crypt: spikes and mages on the way
	var crypt := ground(0, -44)
	_build(H + "crypt", crypt, 9.0, 0.0)
	_goal(ground(0, -37), m_crypt, "kaykit/dungeon/key", 1.2)
	for k in 4:
		_spike_trap(-3.2 + (k % 2) * 6.4, -22 - k * 3.2, k * 0.2)
	spawn_enemy("mage", -6, -32)
	spawn_enemy("mage", 6, -32)
	spawn_enemy("warrior", 0, -30)
	_camp(-8, -16)
	for c in [[-4, -36], [4, -36]]:
		_put(H + "post_lantern", c[0], c[1], 3.0, 0.0)
	_heart(-14, -10)
	_heart(16, 30)
	_heart(20, -30)
	# dead woods, pumpkins and candles about
	_woods(-40, 30, 20, 16, 7.0, 12.0)
	_woods(40, 30, 20, 16, 7.0, 12.0)
	_woods(40, -30, 18, 14, 7.0, 12.0)
	_woods(-20, -50, 16, 10, 7.0, 12.0)
	for i in 26:
		var x := _rng.randf_range(-R, R)
		var z := _rng.randf_range(-R, R)
		if _free(x, z, 0.3, 2.0):
			_add(H + ["pumpkin_orange_small", "pumpkin_yellow_small", "pumpkin_yellow", "candle_triple", "skull", "ribcage"][_rng.randi() % 6],
				ground(x, z), _rng.randf_range(1.6, 2.4), -1.0, 70.0, true)
	for i in 10:
		var x := _rng.randf_range(-R, R)
		var z := _rng.randf_range(-R, R)
		if _free(x, z, 0.3, 2.0):
			_add(H + ["tree_dead_large", "tree_dead_medium", "tree_pine_orange_large", "tree_pine_yellow_medium"][_rng.randi() % 4],
				ground(x, z), _rng.randf_range(2.5, 3.5), -1.0, 140.0, true)
	_rocks(10)
	_cover(2600, 160)
	_coin_trail(_v2(0, 44), _v2(0, 30), 4)

# ================================================================ 4 cove

func _cove_zone() -> void:
	island = true
	_amp = 1.6
	_flats.append([_v2(0, 46), 10.0, 2.2])
	_hills.append([_v2(-10, -18), 26.0, 6.0, 0.4])
	_hills.append([_v2(30, -36), 12.0, 4.0, 0.4])
	_flats.append([_v2(34, 18), 14.0, 2.2])   # the crew's beach camp
	_lakes.append([_v2(-34, 20), 10.0])
	_paths.append([_line([[0, 50], [0, 26], [-6, 0], [-10, -18]]), 3.0])
	_paths.append([_line([[0, 26], [20, 20], [34, 18]]), 2.6])
	_paths.append([_line([[-6, 0], [-30, -4], [-44, -16]]), 2.4])
	_make_ground()
	_start(0, 46, 0.0)
	var m_cannons := _mission("Jam the cannons", "bang", 3)
	var m_crew := _mission("Beat the skeleton crew", "act", 7)
	var m_eggs := _mission("Find the golden eggs", "coin", 5)
	# cannons on the hills: run up and jam the fuse (touch the flag by it)
	for c in [[-10, -18], [30, -36], [-44, -16]]:
		var g := ground(c[0], c[1])
		_cannon(g + Vector3(0, 0.6, 0), 30.0, 2.8)
		_lantern(c[0] + 2.4, c[1] + 2.4, m_cannons, "models/flag", "", 2.2)
		_switches[-1].append(_cannons.size() - 1)
		_clear.append([_v2(c[0], c[1]), 5.0])
	# beach camp and moored ships
	for e in [[30, 14], [36, 22], [40, 14], [28, 22], [34, 18], [38, 10], [32, 26]]:
		spawn_enemy(["minion", "rogue", "minion", "warrior"][_rng.randi() % 4], e[0], e[1], m_crew, true, 14.0)
	_build("pirate/ship_dark", Vector3(56, water_y - 1.0, 24), 20.0, 1.9, true, 2)
	_build("pirate/ship_light", Vector3(-48, water_y - 1.0, 48), 18.0, -0.6, true, 2)
	_build("kaykit/dungeon/crates_stacked", ground(42, 20), 2.4, 0.3)
	_put("pirate/chest", 38, 24, 1.4)
	_put("kaykit/dungeon/barrel_large", 26, 16, 1.3)
	_item_box(ground(18, 22) + Vector3.UP)
	_item_box(ground(-4, 14) + Vector3.UP)
	_camp(14, 24)
	_camp(-8, -2)
	# a dock out into the sea with an egg at the end
	_ramp(ground(-2, 60) + Vector3(0, 0.3, 0), Vector3(-2, water_y + 1.0, 78), 3.0, "planks")
	_golden_egg(Vector3(-2, water_y + 1.0, 76), m_eggs)
	_golden_egg(ground(-34, 20) + Vector3(0, 0, 0), m_eggs)
	for st in [[-28, 18], [-31, 22], [-36, 17]]:
		_rock("Rock_Medium_1", st[0], st[1], 2.4, 0.0)
	_golden_egg(ground(-10, -26), m_eggs)
	_golden_egg(ground(48, -10), m_eggs)
	_golden_egg(ground(10, -48), m_eggs)
	_roller_spawn(ground(-10, -18) + Vector3(2, 1.4, 4), 2.0, 2.6, "barrel", 4.0)
	_rollers[-1][5] = (ground(-6, 0) - ground(-10, -18)).normalized() * 4.5
	_heart(-20, -4)
	_heart(24, -20)
	spawn_enemy("rogue", 20, -30)
	spawn_enemy("minion", -30, -10)
	spawn_enemy("minion", 10, -40)
	# palms on the beach, trees inland
	for i in 40:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(R - 18.0, R - 6.0)
		var x := cos(a) * d
		var z := sin(a) * d
		if _free(x, z, 0.35, 2.0):
			var pid: String = ["pirate/palm_detailed_long", "nature/tree_palm", "nature/tree_palmTall"][_rng.randi() % 3]
			_add(pid, ground(x, z), _fit(pid, _rng.randf_range(6.0, 9.0), 1), -1.0, 150.0, true)
	_woods(-16, -40, 16, 12)
	_woods(20, -10, 12, 8)
	_rocks(12)
	_cover(2400, 180)
	_coin_trail(_v2(0, 42), _v2(0, 28), 4)
	_coin_trail(_v2(4, 24), _v2(28, 19), 5)

# ================================================================ 5 peaks

func _peaks_zone() -> void:
	_amp = 3.0
	_flats.append([_v2(0, 50), 10.0, 2.6])
	_hills.append([_v2(-20, -36), 34.0, 16.0, 0.12])  # the big mountain
	_flats.append([_v2(-20, -36), 5.0, 18.6])         # its summit
	_hills.append([_v2(36, -10), 14.0, 4.0, 0.3])
	_lakes.append([_v2(26, 30), 14.0])
	_paths.append([_line([[0, 54], [0, 30], [6, 8], [0, -6], [-14, -18], [-4, -28], [-14, -32], [-20, -36]]), 3.0])
	_paths.append([_line([[6, 8], [30, 6], [36, -10]]), 2.6])
	_make_ground()
	_start(0, 50, 0.0)
	var m_summit := _mission("Climb to the summit", "flag", 1)
	var m_eggs := _mission("Find the golden eggs", "coin", 5)
	var m_bones := _mission("Smash the skeletons", "act", 6)
	# the frozen lake: slippery ice you skate across
	var ice := StaticBody3D.new()
	ice.collision_layer = 1
	ice.set_meta("ice", true)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.02
	ice.physics_material_override = pm
	add_child(ice)
	ice.position = Vector3(26, water_y + 0.2, 30)
	var cs := CollisionShape3D.new()
	cs.shape = _cyl(16.0, 0.4)
	cs.position.y = -0.2
	ice.add_child(cs)
	var slab := Props.make("platformer/blockSnowLarge")
	var bs := Props.base_size("platformer/blockSnowLarge")
	slab.scale = Vector3(30.0 / bs.x, 0.4 / bs.y, 30.0 / bs.z)
	slab.position.y = -0.4
	Props.tint(slab, Color("9fe4ff"), 0.5)
	ice.add_child(slab)
	_golden_egg(Vector3(26, water_y + 0.2, 30), m_eggs)
	# toy trains across the valley
	_train(ground(0, 18), -40.0, 40.0, 7.0)
	# the climb: barrels and snowmen
	var summit := ground(-20, -36)
	_goal(summit, m_summit)
	_put("holiday/snowmanFancy", -17, -34, 2.4)
	_roller_spawn(summit + Vector3(6, 1.5, 4), 2.0, 2.4, "barrel", 4.5)
	_rollers[-1][5] = (ground(-4, -28) - summit).normalized() * 4.0
	_camp(4, -4)
	_camp(-8, -24)
	_heart(-10, -20)
	_heart(-6, -30)
	guards.append([ground(-12, -20) + Vector3.UP * 0.6, 5.0, "snowman"])
	guards.append([ground(-2, -10) + Vector3.UP * 0.6, 5.0, "snowman"])
	# skeleton outpost on the east hill
	for e in [[32, -8], [38, -14], [40, -6], [34, -16], [30, -12], [42, -10]]:
		spawn_enemy(["minion", "warrior", "rogue", "minion"][_rng.randi() % 4], e[0], e[1], m_bones, true, 14.0)
	_build("kaykit/medieval/building_tower_B_blue", ground(44, -16), 4.5, 0.4)
	_item_box(ground(24, 2) + Vector3.UP)
	_item_box(ground(20, -4) + Vector3.UP)
	_golden_egg(ground(44, -20), m_eggs)
	_golden_egg(ground(-46, 20), m_eggs)
	_golden_egg(ground(-34, -14), m_eggs)
	_golden_egg(ground(50, 40), m_eggs)
	_build("holiday/snowFort", ground(-44, 24), 6.0, 0.6)
	# snowy pines
	var snowy := ["holiday/treePineSnow", "holiday/treePineSnowRound"]
	for i in 90:
		var x := _rng.randf_range(-R, R)
		var z := _rng.randf_range(-R, R)
		if _free(x, z, 0.4, 2.5) and Vector2(x + 20, z + 36).length() > 10.0:
			var tid: String = snowy[_rng.randi() % 2]
			var h := _rng.randf_range(5.0, 9.0)
			_add(tid, ground(x, z), _fit(tid, h, 1), -1.0, 150.0, true)
			var c := CollisionShape3D.new()
			c.shape = _cyl(0.5, 4.0)
			c.position = ground(x, z) + Vector3(0, 2.0, 0)
			_trunks.add_child(c)
	_woods(40, 46, 12, 8, 6.0, 9.0)
	for i in 30:
		var x := _rng.randf_range(-R, R)
		var z := _rng.randf_range(-R, R)
		if _free(x, z, 0.35, 2.0):
			_add(["holiday/snowPatch", "holiday/rockFormationMedium", "holiday/present", "holiday/candyCane"][_rng.randi() % 4],
				ground(x, z), _rng.randf_range(1.0, 2.0) * 2.0, -1.0, 80.0, true)
	_rocks(12)
	_cover(1400, 120)
	_coin_trail(_v2(0, 44), _v2(2, 26), 5)
