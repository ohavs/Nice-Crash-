// Toon water / soup: flat colour bands, drifting foam lines, gentle swell.
shader_type spatial;
render_mode cull_disabled, specular_toon, diffuse_toon;

uniform vec4 deep : source_color = vec4(0.13, 0.55, 0.85, 1.0);
uniform vec4 shallow : source_color = vec4(0.35, 0.82, 0.95, 1.0);
uniform vec4 foam : source_color = vec4(0.92, 0.98, 1.0, 1.0);
uniform float wave_height = 0.35;
uniform float foam_amount = 0.06;

varying vec3 wpos;

float h(vec2 p, float t) {
	return sin(p.x * 0.11 + t * 0.9) * 0.6 + sin(p.y * 0.07 - t * 0.7) * 0.4
		+ sin((p.x + p.y) * 0.19 + t * 1.3) * 0.25;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += h(wpos.xz, TIME) * wave_height;
}

void fragment() {
	float t = TIME;
	float w = h(wpos.xz * 1.7, t * 1.2);
	vec3 col = mix(deep.rgb, shallow.rgb, smoothstep(-0.4, 0.9, w));
	// foam: thin bands where two slow sine fields cross
	float f = sin(wpos.x * 0.35 + sin(wpos.z * 0.21 + t * 0.6) * 2.2 + t * 0.8)
		* sin(wpos.z * 0.29 - t * 0.5 + sin(wpos.x * 0.17) * 1.7);
	float fm = step(1.0 - foam_amount, f);
	ALBEDO = mix(col, foam.rgb, fm * 0.85);
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
}
