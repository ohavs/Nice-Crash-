class_name Props
## Loads Kenney models (assets/kenney/<kit>/<name>.glb|gltf) and gives them the
## game's candy look: the packs' muted flat colours get a saturation/brightness
## lift and toon shading. Also: size helpers so callers can say "make this 6 m
## long" instead of guessing scale factors.

static var _scenes := {}
static var _mats := {}
static var _boxes := {}

static func path(id: String) -> String:
	var p := "res://assets/kenney/%s.glb" % id
	if ResourceLoader.exists(p):
		return p
	return "res://assets/kenney/%s.gltf" % id

## New instance of `id` ("food/egg", "nature/tree_oak", ...). The model is
## re-centred so its footprint is centred on x/z and its base sits at y = 0.
static func make(id: String, candy := true) -> Node3D:
	if not _scenes.has(id):
		_scenes[id] = load(path(id))
	var inner: Node3D = _scenes[id].instantiate()
	var root := Node3D.new()
	root.name = id.get_file()
	root.add_child(inner)
	var box := local_aabb(id, inner)
	inner.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z)
	if candy:
		_candy(inner)
	return root

## Instance scaled so its largest horizontal side (or `axis`) is `size` metres.
static func sized(id: String, size: float, axis := -1) -> Node3D:
	var n := make(id)
	var s := base_size(id)
	var ref: float = maxf(s.x, s.z) if axis < 0 else s[axis]
	n.scale = Vector3.ONE * (size / maxf(ref, 0.001))
	return n

## Unscaled bounding box size of a model.
static func base_size(id: String) -> Vector3:
	if not _boxes.has(id):
		make(id).free()
	return _boxes[id].size

static func local_aabb(id: String, inner: Node3D) -> AABB:
	if _boxes.has(id):
		return _boxes[id]
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in inner.find_children("*", "MeshInstance3D", true, false):
		# accumulate transforms up to `inner` (nodes may not be in the tree yet)
		var t := mi.transform
		var p := mi.get_parent()
		while p != null and p != inner and p is Node3D:
			t = (p as Node3D).transform * t
			p = p.get_parent()
		t = inner.transform * t
		var b: AABB = t * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	_boxes[id] = box
	return box

static func meshes(n: Node) -> Array:
	return n.find_children("*", "MeshInstance3D", true, false)

static func _candy(n: Node) -> void:
	for mi: MeshInstance3D in meshes(n):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is StandardMaterial3D:
				mi.set_surface_override_material(i, candy_mat(m))

## Saturated, toon-shaded copy of a model material (cached).
static func candy_mat(m: StandardMaterial3D) -> StandardMaterial3D:
	if _mats.has(m):
		return _mats[m]
	var c := m.duplicate() as StandardMaterial3D
	var col := c.albedo_color
	# the packs' foliage is teal; push it towards a juicy grass green
	if col.h > 0.38 and col.h < 0.56 and col.s > 0.15:
		col.h = lerpf(col.h, 0.31, 0.6)
	col.s = minf(col.s * 1.35 + 0.04, 1.0)
	col.v = minf(col.v * 1.04, 1.0)
	c.albedo_color = col
	c.metallic = 0.0
	c.roughness = 0.75
	c.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	c.specular_mode = BaseMaterial3D.SPECULAR_TOON
	c.rim_enabled = true
	c.rim = 0.25
	c.rim_tint = 0.7
	_mats[m] = c
	return c

## Recolour every surface of a model instance (per-instance materials).
static func tint(n: Node, color: Color, amount := 1.0) -> void:
	for mi: MeshInstance3D in meshes(n):
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is StandardMaterial3D:
				var c := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				c.albedo_color = c.albedo_color.lerp(color, amount)
				mi.set_surface_override_material(i, c)

static var _candy_meshes := {}

## Many copies of one model as MultiMeshes (one draw call per mesh part).
## `xforms` place the re-centred model (base at y = 0), like make().
static func multi(id: String, xforms: Array) -> Node3D:
	var holder := Node3D.new()
	holder.name = "multi_" + id.get_file()
	if xforms.is_empty():
		return holder
	var probe := make(id, false)
	var inner: Node3D = probe.get_child(0)
	for mi: MeshInstance3D in meshes(inner):
		var t := mi.transform
		var p := mi.get_parent()
		while p != null and p != probe and p is Node3D:
			t = (p as Node3D).transform * t
			p = p.get_parent()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _candy_mesh(mi.mesh)
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i] * t)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mmi)
	probe.free()
	return holder

static func _candy_mesh(mesh: Mesh) -> Mesh:
	if _candy_meshes.has(mesh):
		return _candy_meshes[mesh]
	var m := mesh.duplicate() as Mesh
	for i in m.get_surface_count():
		var sm := m.surface_get_material(i)
		if sm is StandardMaterial3D:
			m.surface_set_material(i, candy_mat(sm))
	_candy_meshes[mesh] = m
	return m

static func no_shadows(n: Node) -> void:
	for mi: MeshInstance3D in meshes(n):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
