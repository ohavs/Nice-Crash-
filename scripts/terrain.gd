class_name Terrain
extends Node3D
## Rolling ground for the open world: a height grid sampled from
## `height_fn(x, z)`, coloured per vertex by `color_fn(x, z, h, slope)`
## (grass, dirt paths, sand, rock, snow) and drawn with ground.gdshader.
## Built in chunks (each one mesh + one collision shape) so the renderer can
## skip what's off screen. height_at() gives the ground height anywhere, for
## placing trees, rocks, buildings and enemies.

## Side of the square grid (metres), centred on the origin.
var size := 200.0
## Grid spacing (metres).
var cell := 2.0
## Grid cells per chunk side.
var chunk_cells := 10
var height_fn: Callable
var color_fn: Callable

var _n := 0
var _h := PackedFloat32Array()

func build() -> void:
	_n = int(size / cell) + 1
	_h.resize(_n * _n)
	for iz in _n:
		for ix in _n:
			_h[iz * _n + ix] = height_fn.call(_x(ix), _x(iz))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/ground.gdshader")
	mat.set_shader_parameter("noise", load("res://assets/quaternius/noise_perlin.png"))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.name = "Ground"
	add_child(body)
	var chunks := ceili(float(_n - 1) / chunk_cells)
	for cz in chunks:
		for cx in chunks:
			_chunk(cx * chunk_cells, cz * chunk_cells, mat, body)

func _x(i: int) -> float:
	return -size * 0.5 + i * cell

func _hi(ix: int, iz: int) -> float:
	return _h[clampi(iz, 0, _n - 1) * _n + clampi(ix, 0, _n - 1)]

func _normal(ix: int, iz: int) -> Vector3:
	var dx := _hi(ix + 1, iz) - _hi(ix - 1, iz)
	var dz := _hi(ix, iz + 1) - _hi(ix, iz - 1)
	return Vector3(-dx, cell * 2.0, -dz).normalized()

func _chunk(x0: int, z0: int, mat: Material, body: StaticBody3D) -> void:
	var x1 := mini(x0 + chunk_cells, _n - 1)
	var z1 := mini(z0 + chunk_cells, _n - 1)
	var w := x1 - x0 + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	for iz in range(z0, z1 + 1):
		for ix in range(x0, x1 + 1):
			var h := _hi(ix, iz)
			var nrm := _normal(ix, iz)
			verts.append(Vector3(_x(ix), h, _x(iz)))
			norms.append(nrm)
			cols.append(color_fn.call(_x(ix), _x(iz), h, 1.0 - nrm.y))
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	for iz in z1 - z0:
		for ix in x1 - x0:
			var a := iz * w + ix
			var b := a + 1
			var c := a + w
			var d := c + 1
			# split each quad along the shorter diagonal: smoother ridges
			if absf(verts[a].y - verts[d].y) < absf(verts[b].y - verts[c].y):
				idx.append_array([a, b, d, a, d, c])
			else:
				idx.append_array([a, b, c, b, d, c])
	for i in idx:
		faces.append(verts[i])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)

## Ground height at world x/z (bilinear between grid points).
func height_at(x: float, z: float) -> float:
	var fx := (x + size * 0.5) / cell
	var fz := (z + size * 0.5) / cell
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(_hi(ix, iz), _hi(ix + 1, iz), tx)
	var b := lerpf(_hi(ix, iz + 1), _hi(ix + 1, iz + 1), tx)
	return lerpf(a, b, tz)

## 0 = flat, 1 = vertical.
func slope_at(x: float, z: float) -> float:
	var e := cell * 0.5
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return 1.0 - Vector3(-dx, e * 2.0, -dz).normalized().y

func ground(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)
