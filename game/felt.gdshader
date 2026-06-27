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
	ALBEDO = felt_color * (1.0 - grain * g) * (1.0 + s) * (1.0 - e);
	ROUGHNESS = 0.95;  // matte, fabric-like
	SPECULAR = 0.08;
}
