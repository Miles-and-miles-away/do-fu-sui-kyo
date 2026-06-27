// game/felt.gdshader — the luxurious red felt target disc in the middle of the table.
// Marks where the player must throw (its radius matches the PlayZone trigger cylinder).
// Matte crimson with fine fabric grain + a soft radial plush sheen (brighter centre, dark
// inset rim) so it reads as rich felt, not flat plastic. Procedural like wall/wood — no texture.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 felt_color : source_color = vec3(0.42, 0.02, 0.05);  // deep crimson
uniform float felt_radius = 0.25;  // keep in step with the disc mesh + PlayZone radius
uniform float grain = 0.07;  // fabric fibre speckle
uniform float sheen = 0.16;  // centre plush glow
uniform float rim = 0.55;  // darkening toward the edge (inset look)
uniform float active = 0.0;  // 0..1 — PlayZone lights this when a card lands; gilds the rim

varying vec3 v_local;


float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


void vertex() {
	v_local = VERTEX;  // local space; the disc cap is centred on the origin
}


void fragment() {
	float r = clamp(length(v_local.xz) / felt_radius, 0.0, 1.0);
	float g = hash(floor(v_local.xz * 900.0));
	float s = smoothstep(1.0, 0.0, r) * sheen;  // centre sheen
	float e = smoothstep(0.82, 1.0, r) * rim;  // edge inset
	vec3 base = felt_color * (1.0 - grain * g) * (1.0 + s) * (1.0 - e);
	// Gilded perimeter when active: a shiny gold band on the outer rim signals "card in place".
	float ring = smoothstep(0.8, 0.9, r) * active;
	vec3 gold = vec3(1.0, 0.78, 0.28);
	ALBEDO = mix(base, gold, ring);
	METALLIC = ring;  // polished metal at the rim only when lit
	ROUGHNESS = mix(0.95, 0.12, ring);  // matte felt → mirror gold
	SPECULAR = mix(0.08, 0.9, ring);
	EMISSION = gold * ring * 0.4;  // a touch of glow so it reads as "shiny" even in dim light
}
