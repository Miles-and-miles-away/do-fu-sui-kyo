// game/wall.gdshader — circular room ambiance (DESIGN §4.5, FSD R29–R31).
// Three vertical COLUMNS around the cylinder: Fire / Waves / Wind, full height, left→right,
// the sequence repeated `repeats` times so the player sees all three forward AND back.
// Unshaded (ignores scene lighting) + cull_disabled (seen from inside). ALL motion from TIME —
// no _process, no per-frame GDScript (NFR6: GPU-only). Each fragment runs only its own column's
// motif (coherent branch per column → cheap on Quest 3).
//
// Sources copied / adapted (researched via GodotShaders):
//   • Fire  — "3D Fire Shader" by GodotShaders (MIT): plume shape + value-noise fbm + colour ramp.
//             https://godotshaders.com/shader/3d-fire-shader/
//   • fbm   — value noise / fbm from the same shader (MIT).
//   • Waves — classic iterative water-caustic technique (ShaderToy, re-implemented) under a
//             side-profile sea surface.
//   • Wind  — domain-warped fbm (fbm(p + fbm(p))) scrolled sideways = flowing gale streaks.
//
// ponytail: noise_octaves=4 + a domain-warped wind fbm on one cylinder. If Quest 3 hitches
//           (NFR6), drop noise_octaves to 2–3 first, then simplify wind, before cutting walls.
shader_type spatial;
render_mode unshaded, cull_disabled;

// ── layout / global ──────────────────────────────────────────────────────────
uniform float brightness = 0.8;      // overall level — keep cards the brightest thing in view
uniform float repeats = 2.0;         // Fire|Waves|Wind sets around the circle (2 = front + back)
uniform float column_offset = 0.0;   // rotate columns to align Fire/Waves/Wind in-headset
uniform float fire_speed = 0.6;      // per-motif animation rates
uniform float wave_speed = 1.0;
uniform float wind_speed = 1.0;

// ── fire shape (from the MIT 3D Fire Shader) ─────────────────────────────────
uniform float detail_strength = 3.0;
uniform float scroll_speed = 1.4;
uniform float fire_height = 1.0;
uniform float fire_shape = 1.8;
uniform float fire_thickness = 5.0;
uniform float fire_sharpness = 1.0;
uniform float intensity = 1.5;
uniform int noise_octaves = 4;
uniform float noise_lacunarity = 3.0;
uniform float noise_gain = 0.5;
uniform float noise_amplitude = 1.0;
uniform float noise_frequency = 1.5;

// ── value noise + fbm (MIT, from the 3D Fire Shader) ─────────────────────────
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
	float amplitude = noise_amplitude;
	float frequency = noise_frequency;
	for (int i = 0; i < noise_octaves; i++) {
		total += vnoise(p * frequency) * amplitude;
		frequency *= noise_lacunarity;
		amplitude *= noise_gain;
	}
	return total * 0.5;
}

// classic iterative water caustic (ShaderToy technique, re-implemented)
float caustic(vec2 uv, float t) {
	vec2 p = mod(uv * 6.28318, 6.28318) - 250.0;
	vec2 i = p;
	float c = 1.0;
	float inten = 0.005;
	for (int n = 0; n < 5; n++) {
		float tt = t * (1.0 - (3.5 / float(n + 1)));
		i = p + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
		c += 1.0 / length(vec2(p.x / (sin(i.x + tt) / inten), p.y / (cos(i.y + tt) / inten)));
	}
	c /= 5.0;
	c = 1.17 - pow(c, 1.4);
	return pow(abs(c), 8.0);
}

// ── Fire: a real flame plume (adapted MIT 3D Fire Shader) ─────────────────────
// uv: (local x 0..1 across the column, vertical with the bright base at uv.y = 0 = floor).
vec3 fire_motif(vec2 uv, float t) {
	vec2 m = -uv;
	m.x = mod(m.x, 1.0) - 0.5;     // centre one plume per column
	m.y = uv.y - 0.16;             // plume core just above the floor → wide base tapering UP (rises)
	float scroll = scroll_speed * detail_strength * t;
	float n = fbm(detail_strength * m - vec2(0.0, scroll));
	float fi = intensity - 16.0 * fire_sharpness * pow(
		max(0.0, length(m * vec2((1.0 / fire_thickness) + m.y * fire_shape, 1.0 / fire_height))
			- n * max(0.0, m.y + 0.25)),
		1.2);
	float fi1 = clamp(n * fi * (1.5 - pow(uv.y, 14.0)), 0.0, 1.0);
	vec3 col = vec3(1.5 * fi1, 1.5 * pow(fi1, 3.0), pow(fi1, 6.0));  // hot red→orange→yellow ramp
	float a = clamp(fi * (1.0 - pow(uv.y, 3.0)), 0.0, 1.0);
	return mix(vec3(0.0), col, a);
}

// ── Waves: the whole column is caustic-lit water, lighter up top, deeper down ─
vec3 waves_motif(float x, float h, float t) {
	float depth = clamp(1.0 - h, 0.0, 1.0);                 // 0 at ceiling (shallow) → 1 at floor (deep)
	float ca = caustic(vec2(x * 2.0, h * 2.0), t * 1.6);    // slightly higher flux
	vec3 body = mix(vec3(0.10, 0.55, 0.75), vec3(0.02, 0.18, 0.40), depth); // shallow→deep, still blue
	body += vec3(0.4, 0.8, 0.9) * ca * (1.0 - depth * 0.5);                 // caustic light
	return body * (0.85 + 0.15 * sin(t * 1.6));                             // gentle pulse
}

// ── Wind: domain-warped flowing streaks = blustering gale ────────────────────
vec3 wind_motif(float x, float h, float t) {
	vec2 q = vec2(x * 7.0, h * 1.2 - t * 0.8);          // long vertical streaks, blowing upward
	float warp = fbm(q * 0.5 + vec2(0.0, t * 0.3));
	float flow = fbm(q + warp * 1.5);                   // domain warp → curling air currents
	float streak = smoothstep(0.5, 0.85, flow);
	float gust = 0.5 + 0.5 * sin(t * 0.6) * sin(t * 0.23);  // blustering gusts swell and drop
	return vec3(0.7, 0.78, 0.9) * streak * (0.4 + 0.8 * gust);
}

void fragment() {
	float c = fract((UV.x + column_offset) * repeats);  // position within one Fire|Waves|Wind set
	float h = 1.0 - UV.y;                                // 0 = floor, 1 = ceiling
	float band = 1.0 / 3.0;

	vec3 m = vec3(0.0);
	float lx = 0.0;                                      // local x within the column, 0..1
	if (c < band) {
		lx = c / band;
		m = fire_motif(vec2(lx, h), TIME * fire_speed);
	} else if (c < 2.0 * band) {
		lx = (c - band) / band;
		m = waves_motif(lx, h, TIME * wave_speed);
	} else {
		lx = (c - 2.0 * band) / band;
		m = wind_motif(lx, h, TIME * wind_speed);
	}

	// Fade each column at its side edges → distinct blocks with dark gaps between (SVG look).
	float edge = smoothstep(0.0, 0.03, lx) * smoothstep(1.0, 0.97, lx);

	ALBEDO = (vec3(0.015) + m * edge) * brightness;     // dark base so shapes read as glow
}
