// Open-world ground: per-vertex colour (grass / dirt path / sand / rock /
// snow, painted by terrain.gd) broken up by Quaternius' Perlin noise at two
// scales, soft wrapped light like the painted trees standing on it.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float variation = 0.22;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float big = texture(noise, wpos.xz * 0.011).r;
	float small = texture(noise, wpos.xz * 0.09).r;
	float k = (big - 0.5) * 1.3 + (small - 0.5) * 0.7;
	vec3 c = COLOR.rgb * (1.0 + k * variation);
	// sunlit patches lean warm, shaded ones cool
	c = mix(c, c * vec3(1.06, 1.03, 0.9), clamp(big - 0.45, 0.0, 1.0));
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
