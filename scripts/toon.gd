class_name Toon
## Shared cartoon materials: toon shading + black outline (inverted hull).

static var _outline: StandardMaterial3D
static var _cache := {}

static func mat(color: Color, outline := true) -> StandardMaterial3D:
	var key := "%s_%s" % [color.to_html(), outline]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = 0.6
	m.rim_enabled = true
	m.rim = 0.18
	m.rim_tint = 0.6
	if outline:
		m.next_pass = outline_mat()
	_cache[key] = m
	return m

static func outline_mat() -> StandardMaterial3D:
	if _outline == null:
		_outline = StandardMaterial3D.new()
		_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline.albedo_color = Color(0.08, 0.06, 0.1)
		_outline.cull_mode = BaseMaterial3D.CULL_FRONT
		_outline.grow = true
		_outline.grow_amount = 0.025
	return _outline

static func unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m
