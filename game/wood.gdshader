// game/wood.gdshader — procedural wood for the central table (no image asset needed).
// Concentric tree-rings in model space: length(pos.xz) reads as a cross-cut log on the round
// top, and as vertical grain down the pedestal (a touch of pos.y warps the rings so the column
// isn't a flat band). Lit normally (StandardMaterial-style) so the DirectionalLight shapes it,
// unlike the unshaded walls. Noise helpers adapted from wall.gdshader (MIT 3D Fire Shader).
//
// ponytail: 3-octave fbm + per-pixel rings on a 3-piece table — trivial on Quest 3. If grain
//           looks too busy in-headset, drop ring_density first, then noise_warp.
shader_type spatial;

uniform vec3 light_wood : source_color = vec3(0.52, 0.36, 0.20);
uniform vec3 dark_wood : source_color = vec3(0.28, 0.17, 0.09);
uniform float ring_density = 14.0;   // tree-rings per metre of radius
uniform float noise_warp = 0.7;      // how much the rings wobble (organic, not perfect circles)
uniform float roughness_val = 0.65;

varying vec3 local_pos;

float hash(vec2 p) {
	p = fract(p * 0.3183099 + vec2(0.1, 0.1));
	p *= 17.0;
	return fract(p.x * p.y * (p.x + p.y));
}

float vnoise(vec2 x) {
	vec2 p = floor(x);
	vec2 f = fract(x);
	return hash(p) * (1.0 - f.x) * (1.0 - f.y)
		+ hash(p + vec2(1.0, 0.0)) * f.x * (1.0 - f.y)
		+ hash(p + vec2(0.0, 1.0)) * (1.0 - f.x) * f.y
		+ hash(p + vec2(1.0, 1.0)) * f.x * f.y;
}

float fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		total += vnoise(p) * amp;
		p *= 2.0;
		amp *= 0.5;
	}
	return total;
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float warp = fbm(local_pos.xz * 6.0 + local_pos.y * 2.0) * noise_warp;
	float rings = length(local_pos.xz) * ring_density + local_pos.y * 1.5 + warp;
	float t = sin(rings * 6.2831853) * 0.5 + 0.5;             // smooth ring bands
	float fiber = fbm(local_pos.xz * 60.0 + local_pos.y * 8.0);  // fine lengthwise fibre
	ALBEDO = mix(dark_wood, light_wood, t) * (0.9 + 0.1 * fiber);
	ROUGHNESS = roughness_val;
}
