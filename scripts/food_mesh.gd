class_name FoodMesh
## Hand-built smooth bodies for the skins whose kit model reads badly up
## close (the Food Kit egg and donut are 6-8 sided and look like gems):
## a lathed egg with a real egg profile, and a glazed, sprinkled donut.
## Both come back like Props.make(): a Node3D whose base sits at y = 0,
## centred on x/z, facing -z.

static var _meshes := {}

## Egg radius at `t` (0 = bottom, 1 = top), for a unit-height egg whose
## widest radius is about 0.5: fuller at the bottom, narrower at the top.
static func egg_radius(t: float) -> float:
	var u := t * 2.0 - 1.0
	return 0.5 * sqrt(maxf(1.0 - u * u, 0.0)) * (1.0 - 0.17 * u)

static func _widest() -> float:
	var w := 0.0
	for i in 41:
		w = maxf(w, egg_radius(i / 40.0))
	return w

## How far the front of a `width` wide egg sticks out at height fraction `t`.
static func egg_front(t: float, width: float) -> float:
	return egg_radius(t) / _widest() * width * 0.5

## Egg `height` tall, `width` across at its widest.
static func egg(height: float, width: float) -> Node3D:
	if not _meshes.has("egg"):
		_meshes["egg"] = _lathe(egg_radius, 48, 40)
	var root := Node3D.new()
	root.name = "egg"
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes["egg"]
	var widest := _widest()
	mi.scale = Vector3(width / (widest * 2.0), height, width / (widest * 2.0))
	mi.material_override = _mat(Color("e3c9a2"), 0.45, 0.1)
	root.add_child(mi)
	# a few freckles, like a farm egg
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var dot := SphereMesh.new()
	dot.radius = 0.5
	dot.height = 1.0
	dot.radial_segments = 8
	dot.rings = 4
	var dm := _mat(Color("c9a77f"), 0.8, 0.0)
	for k in 9:
		var t := rng.randf_range(0.62, 0.9)
		var a := rng.randf_range(-PI * 0.95, PI * 0.95)
		if absf(wrapf(a, -PI, PI)) < 0.9:
			a += PI  # keep them off the face (front is -z, angle 0 here = +z)
		var r := egg_radius(t) * mi.scale.x
		var d := MeshInstance3D.new()
		d.mesh = dot
		d.material_override = dm
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var n := Vector3(sin(a), 0, cos(a))
		d.position = n * (r - 0.004) + Vector3.UP * t * height
		d.scale = Vector3.ONE * rng.randf_range(0.025, 0.045)
		d.scale.y *= 0.6
		root.add_child(d)
	return root

## Donut standing up like a coin, `height` across, `depth` thick, facing -z.
## Glaze on the front half with sprinkles; the hole is left clear.
static func donut(height: float, depth: float) -> Node3D:
	var root := Node3D.new()
	root.name = "donut"
	var outer := height * 0.5
	var tube := outer * 0.36
	var ring := outer - tube
	var dough := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = ring - tube
	tm.outer_radius = ring + tube
	tm.rings = 48
	tm.ring_segments = 24
	dough.mesh = tm
	var zs := depth / (tube * 2.0)
	dough.rotation.x = PI * 0.5
	dough.scale = Vector3(1, zs, 1)  # torus local y = world z after the turn
	dough.position.y = outer
	dough.material_override = _mat(Color("c98f58"), 0.75, 0.06)
	root.add_child(dough)
	var glaze := MeshInstance3D.new()
	var gm := TorusMesh.new()
	gm.inner_radius = ring - tube * 1.04
	gm.outer_radius = ring + tube * 1.04
	gm.rings = 48
	gm.ring_segments = 24
	glaze.mesh = gm
	glaze.rotation.x = PI * 0.5
	glaze.scale = Vector3(0.985, zs * 0.9, 0.985)
	glaze.position = Vector3(0, outer, -depth * 0.13)
	glaze.material_override = _mat(Color("e597b6"), 0.4, 0.12)
	root.add_child(glaze)
	# sprinkles on the glaze's front face, clear of the eyes up top
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var cols := [Color("fff3c4"), Color("8fd3f4"), Color("b6e39a"), Color("f7d36b"), Color("ffffff"), Color("c9a2f0")]
	var sp := CapsuleMesh.new()
	sp.radius = 0.5
	sp.height = 3.0
	sp.radial_segments = 6
	sp.rings = 2
	var placed := 0
	var tries := 0
	while placed < 26 and tries < 400:
		tries += 1
		var th := rng.randf() * TAU
		if absf(wrapf(th - PI * 0.5, -PI, PI)) < 0.75:
			continue  # forehead: that's where the eyes go
		# tube angle: 0 = outer rim, PI/2 = front face, PI = rim of the hole
		var ph := rng.randf_range(0.35, 2.8)
		# point on the glaze surface (ring in x/y, front = -z)
		var gr := tube * 1.04 * 0.985
		var radial := Vector3(cos(th), sin(th), 0)
		var n := (radial * cos(ph) + Vector3(0, 0, -1) * sin(ph) * 1.6).normalized()
		var p := radial * ring * 0.985 + radial * cos(ph) * gr + Vector3(0, 0, -sin(ph) * gr * zs * 0.9)
		p.z -= depth * 0.13
		var s := MeshInstance3D.new()
		s.mesh = sp
		s.material_override = _mat(cols[rng.randi() % cols.size()], 0.6, 0.0)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var along := n.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))).normalized()
		if along.length() < 0.1:
			continue
		s.basis = Basis(n.cross(along), along, n).orthonormalized().scaled(Vector3.ONE * height * 0.022)
		s.position = p + n * height * 0.012 + Vector3.UP * outer
		root.add_child(s)
		placed += 1
	return root

## Banana proportions for a unit-height banana: radius and how far the
## middle bows out sideways (+x, so the curve shows from the front) at
## height fraction `t`.
static func banana_radius(t: float) -> float:
	return 0.21 * pow(maxf(sin(PI * clampf(t * 0.94 + 0.03, 0.0, 1.0)), 0.0), 0.6)

static func banana_bow(t: float) -> float:
	return 0.2 * sin(PI * t) - 0.1

## Standing banana `height` tall: a curved, softly five-ridged tube, green
## at the stem end and brown at the tips, with a stalk on top.
static func banana(height: float) -> Node3D:
	if not _meshes.has("banana"):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0)
		var rings := 40
		var segs := 30
		var yellow := Color("d8a92e")
		var green := Color("a7b04a")
		var brown := Color("5e4327")
		var pts := []
		for j in rings + 1:
			var t := float(j) / rings
			var row := []
			var c := yellow
			if t > 0.8:
				c = yellow.lerp(green, (t - 0.8) / 0.2 * 0.7)
			if t < 0.05:
				c = brown.lerp(yellow, t / 0.05)
			for i in segs + 1:
				var a := TAU * i / segs
				var r := banana_radius(t) * (1.0 + 0.07 * cos(5.0 * a))
				row.append([Vector3(banana_bow(t) + sin(a) * r, t, cos(a) * r), c])
			pts.append(row)
		for j in rings:
			for i in segs:
				var quad := [pts[j][i], pts[j + 1][i], pts[j + 1][i + 1], pts[j][i], pts[j + 1][i + 1], pts[j][i + 1]]
				for q in quad:
					st.set_color(q[1])
					st.add_vertex(q[0])
		st.index()
		st.generate_normals()
		_meshes["banana"] = st.commit()
	var root := Node3D.new()
	root.name = "banana"
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes["banana"]
	mi.scale = Vector3.ONE * height
	var m := _mat(Color.WHITE, 0.55, 0.08)
	m.vertex_color_use_as_albedo = true
	mi.material_override = m
	root.add_child(mi)
	var stalk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035 * height
	cm.bottom_radius = 0.055 * height
	cm.height = 0.12 * height
	stalk.mesh = cm
	stalk.material_override = _mat(Color("6b6a35"), 0.8, 0.0)
	stalk.position = Vector3(-0.115 * height, height * 1.02, 0)
	stalk.rotation.z = 0.6
	root.add_child(stalk)
	var tip := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035 * height
	sm.height = 0.05 * height
	tip.mesh = sm
	tip.material_override = _mat(Color("3d2a1a"), 0.8, 0.0)
	tip.position = Vector3(-0.1 * height, 0.01 * height, 0)
	root.add_child(tip)
	return root

## A splayed-open banana peel lying on the floor (base at y = 0).
static func peel(size: float) -> Node3D:
	var root := Node3D.new()
	root.name = "peel"
	var m := _mat(Color("dcb53e"), 0.6, 0.0)
	var cap := CapsuleMesh.new()
	cap.radius = 0.1 * size
	cap.height = 0.62 * size
	for k in 4:
		var petal := MeshInstance3D.new()
		petal.mesh = cap
		petal.material_override = m
		petal.basis = Basis(Vector3.UP, k * TAU / 4.0 + 0.4) * Basis(Vector3.RIGHT, PI * 0.5 - 0.22)
		petal.scale = Vector3(1.3, 1, 0.45)
		petal.position = petal.basis * Vector3(0, 0.3 * size, 0) + Vector3.UP * 0.05 * size
		root.add_child(petal)
	var stub := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.13 * size
	sm.height = 0.2 * size
	stub.mesh = sm
	stub.material_override = _mat(Color("a7b04a"), 0.7, 0.0)
	stub.position.y = 0.08 * size
	root.add_child(stub)
	return root

static func _mat(c: Color, rough: float, rim: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.rim_enabled = rim > 0.0
	m.rim = rim
	m.rim_tint = 0.6
	return m

## Surface of revolution around y, unit height, radius from `r(t)`.
static func _lathe(r: Callable, segs: int, rings: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for j in rings:
		var t0 := float(j) / rings
		var t1 := float(j + 1) / rings
		var r0: float = r.call(t0)
		var r1: float = r.call(t1)
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var p00 := Vector3(sin(a0) * r0, t0, cos(a0) * r0)
			var p01 := Vector3(sin(a1) * r0, t0, cos(a1) * r0)
			var p10 := Vector3(sin(a0) * r1, t1, cos(a0) * r1)
			var p11 := Vector3(sin(a1) * r1, t1, cos(a1) * r1)
			for p in [p00, p10, p11, p00, p11, p01]:
				st.set_uv(Vector2(atan2(p.x, p.z) / TAU + 0.5, p.y))
				st.add_vertex(p)
	st.index()
	st.generate_normals()
	return st.commit()
