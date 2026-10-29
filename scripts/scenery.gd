class_name Scenery
extends Node3D
## Sky, sun and the distant backdrop: mountain ring, floating islands with
## trees, a sea of clouds below and drifting hot-air balloons. Purely visual
## (no collision). Shared by the menu and the game.

const M := "res://assets/kenney/models/%s.glb"

## Course runs from z = 0 to z = -length; the backdrop surrounds that span.
var length := 100.0
var shadows := true
## Keep islands/balloons at least this far to the side of the course.
var clearance := 30.0

var _drifters: Array = []   # [node, base_position, amplitude, speed, phase]
var _t := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 7
	_environment()
	_mountains()
	_islands()
	_cloud_sea()
	_balloons()
	for gi in find_children("*", "GeometryInstance3D", true, false):
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("2a86f5")
	sm.sky_horizon_color = Color("bfe7ff")
	sm.sky_curve = 0.12
	sm.ground_horizon_color = Color("bfe7ff")
	sm.ground_bottom_color = Color("8fd0ff")
	sm.sun_angle_max = 12.0
	sm.sun_curve = 0.08
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.fog_enabled = true
	env.fog_light_color = Color("cbeaff")
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.2
	sun.light_color = Color("fff4e0")
	sun.shadow_enabled = shadows
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

func _span_point(spread: float) -> Vector3:
	return Vector3(0, 0, _rng.randf_range(-length - spread, spread))

# ------------------------------------------------------------- pieces

func _mountains() -> void:
	var mid := Vector3(0, 0, -length * 0.5)
	var n := 22
	for i in n:
		var a := i * TAU / n + _rng.randf_range(-0.08, 0.08)
		var d := length * 0.5 + _rng.randf_range(150.0, 190.0)
		var h := _rng.randf_range(35.0, 65.0)
		var r := h * _rng.randf_range(0.55, 0.8)
		var pos := mid + Vector3(cos(a) * d, -30.0, sin(a) * d)
		var col := Color("8f9fe8").lerp(Color("b49cf0"), _rng.randf())
		var body := _cone(r, h, col, 7)
		body.position = pos + Vector3(0, h * 0.5, 0)
		body.rotation.y = _rng.randf() * TAU
		add_child(body)
		var cap := _cone(r * 0.3, h * 0.3, Color("f4f6ff"), 7)
		cap.position = Vector3(0, h * 0.35 + 0.2, 0)
		body.add_child(cap)

func _islands() -> void:
	for i in 14:
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := _span_point(40.0) + Vector3(side * _rng.randf_range(clearance, clearance + 45.0), _rng.randf_range(-8.0, 9.0), 0)
		_island(p, _rng.randf_range(2.2, 4.5))
	# a couple far ahead, framing the horizon
	for i in 3:
		var x := (-1.0 if i % 2 else 1.0) * _rng.randf_range(20.0, 55.0)
		_island(Vector3(x, _rng.randf_range(-6, 4), -length - _rng.randf_range(95, 140)), _rng.randf_range(3.5, 5.0))

func _island(pos: Vector3, s: float) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var top := (load(M % "platform-grass-large-round") as PackedScene).instantiate()
	top.scale = Vector3.ONE * s
	root.add_child(top)
	var box := aabb(top)
	var radius := maxf(box.size.x, box.size.z) * 0.5 * s
	var top_y := box.end.y * s
	# rocky underside: two stacked inverted cones
	var rock := _cone(radius * 0.95, radius * 1.5, Color("b08a6a"), 8, true)
	rock.position.y = box.position.y * s - radius * 0.75
	root.add_child(rock)
	var rock2 := _cone(radius * 0.45, radius * 0.9, Color("8c6a55"), 7, true)
	rock2.position = Vector3(radius * 0.25, rock.position.y - radius * 0.9, -radius * 0.1)
	root.add_child(rock2)
	for t in _rng.randi_range(1, 3):
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(0.0, radius * 0.55)
		var tree := _tree(_rng.randf_range(0.8, 1.3) * s * 0.55)
		tree.position = Vector3(cos(a) * d, top_y, sin(a) * d)
		root.add_child(tree)
	_drifters.append([root, pos, _rng.randf_range(0.4, 1.0), _rng.randf_range(0.3, 0.5), _rng.randf() * TAU])

func _tree(s: float) -> Node3D:
	var t := Node3D.new()
	var trunk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18 * s
	cm.bottom_radius = 0.26 * s
	cm.height = 1.4 * s
	cm.radial_segments = 8
	trunk.mesh = cm
	trunk.material_override = Toon.mat(Color("9a6238"))
	trunk.position.y = 0.7 * s
	t.add_child(trunk)
	var greens := [Color("5ccf6a"), Color("7be07a"), Color("49b862")]
	var g: Color = greens[_rng.randi() % greens.size()]
	for k in 3:
		var leaf := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := (0.85 - k * 0.2) * s
		sm.radius = r
		sm.height = r * 1.8
		sm.radial_segments = 12
		sm.rings = 6
		leaf.mesh = sm
		leaf.material_override = Toon.mat(g.lightened(k * 0.08))
		leaf.position = Vector3(_rng.randf_range(-0.15, 0.15) * s, (1.6 + k * 0.55) * s, 0)
		t.add_child(leaf)
	return t

func _cloud_sea() -> void:
	var cloud := load(M % "cloud") as PackedScene
	for i in 46:
		var c := cloud.instantiate()
		var p := _span_point(70.0)
		p.x = _rng.randf_range(-110.0, 110.0)
		p.y = _rng.randf_range(-25.0, -19.0)
		c.position = p
		var cs := _rng.randf_range(7.0, 13.0)
		c.scale = Vector3(cs, cs * 0.45, cs)
		c.rotation.y = _rng.randf() * TAU
		add_child(c)
		_drifters.append([c, p, 0.0, 0.0, 0.0])
	# soft floor under the clouds so the horizon never shows a gap
	var base := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	base.mesh = pm
	base.material_override = Toon.mat(Color("dff1ff"), false)
	base.position = Vector3(0, -23.0, -length * 0.5)
	add_child(base)

func _balloons() -> void:
	var cols := [UI.CORAL, UI.YELLOW, UI.TEAL, UI.GRAPE]
	for i in 5:
		var b := Node3D.new()
		var side := -1.0 if i % 2 else 1.0
		var p := _span_point(20.0) + Vector3(side * _rng.randf_range(clearance * 0.6, clearance * 1.3), _rng.randf_range(6.0, 16.0), 0)
		b.position = p
		add_child(b)
		var env := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 2.0
		sm.height = 4.6
		sm.radial_segments = 10
		sm.rings = 8
		env.mesh = sm
		env.material_override = Toon.mat(cols[i % cols.size()])
		b.add_child(env)
		var band := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 2.03
		tm.bottom_radius = 2.03
		tm.height = 0.7
		tm.radial_segments = 10
		band.mesh = tm
		band.material_override = Toon.mat(UI.WHITE)
		band.position.y = 0.1
		b.add_child(band)
		var basket := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 0.7, 0.9)
		basket.mesh = bm
		basket.material_override = Toon.mat(Color("9a6238"))
		basket.position.y = -3.4
		b.add_child(basket)
		for k in 4:
			var rope := MeshInstance3D.new()
			var rm := CylinderMesh.new()
			rm.top_radius = 0.03
			rm.bottom_radius = 0.03
			rm.height = 1.5
			rope.mesh = rm
			rope.material_override = Toon.mat(UI.INK, false)
			var o := Vector3(0.4 if k % 2 else -0.4, 0, 0.4 if k < 2 else -0.4)
			rope.position = o + Vector3(0, -2.4, 0)
			b.add_child(rope)
		_drifters.append([b, p, 1.2, _rng.randf_range(0.5, 0.8), _rng.randf() * TAU])

# ------------------------------------------------------------- helpers

func _cone(r: float, h: float, col: Color, segments: int, inverted := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r if inverted else 0.0
	cm.bottom_radius = 0.0 if inverted else r
	cm.height = h
	cm.radial_segments = segments
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = Toon.mat(col, false)
	return mi

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
		if d[2] > 0.0:
			n.position.y = base.y + sin(_t * d[3] + d[4]) * d[2]
		else:
			n.position.x = base.x + sin(_t * 0.05 + base.z) * 4.0  # clouds drift
