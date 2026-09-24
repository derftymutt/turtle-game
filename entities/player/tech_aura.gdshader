shader_type canvas_item;

// Alien-tech aura around the turtle: a half-moon of glow radiating into the
// water on the screen-left side when slot A holds a tech, screen-right for
// slot B — both together make a full ring. Purple/pink "radiation" that
// pulses outward with a wobbling cartoon-smell edge; a hot side alternates
// its pulse rings with red/yellow fire. Drawn on a square ColorRect centred
// on the turtle; the node keeps itself screen-aligned (global_rotation = 0),
// so left/right here are always screen left/right.

uniform float half_size = 20.0;     // px from centre to the rect's edge (set from script)
uniform float solid_radius = 10.0;  // px — glow is at full strength out to here (turtle shell is ~8px)
uniform float outer_radius = 16.0;  // px — glow has faded out by here (before wobble)
uniform float base_strength = 0.5;   // peak opacity while a side's tech is equipped but idle
uniform float active_strength = 1.0; // peak opacity while it's actually in effect

// 0..1, faded in/out from script so equipping/removing/going hot eases in.
uniform float left_on = 0.0;
uniform float right_on = 0.0;
uniform float left_hot = 0.0;
uniform float right_hot = 0.0;
uniform float left_active = 0.0;
uniform float right_active = 0.0;

void fragment() {
	// px from centre, +x right, +y down — snapped to whole game pixels so the
	// glow is as chunky as the pixel art around it.
	vec2 p = floor((UV - 0.5) * 2.0 * half_size) + 0.5;
	float r = length(p);
	float a = atan(p.y, p.x);

	// Which half: cos(angle) is -1 on the far left, +1 on the far right. The
	// soft overlap across the top/bottom seam lets the halves fuse into one
	// ring when both are on, and lets a lone half taper off at its ends.
	float side = p.x / max(r, 0.001);
	float wl = smoothstep(0.3, -0.3, side) * left_on;
	float wr = smoothstep(-0.3, 0.3, side) * right_on;
	float coverage = clamp(wl + wr, 0.0, 1.0);

	// Wobbling outer edge — like a cartoon smell cloud.
	float wobble = sin(a * 7.0 + TIME * 3.0) * 1.6 + sin(a * 12.0 - TIME * 5.0) * 0.9;
	float radial = 1.0 - smoothstep(solid_radius, outer_radius + wobble, r);

	// Pulse rings travelling outward — radiation.
	float ring_phase = r * 1.3 - TIME * 7.0;
	float ripple = 0.7 + 0.3 * sin(ring_phase);

	// Alien palette: violet and magenta swirling around the ring — deep and
	// saturated so they stand out against the bright cyan water.
	vec3 purple = vec3(0.5, 0.08, 0.95);
	vec3 pink   = vec3(0.95, 0.12, 0.7);
	vec3 alien = mix(purple, pink, 0.5 + 0.5 * sin(a * 3.0 + TIME * 2.0 + r * 0.4));

	// Fire palette for a hot side, flickering red↔yellow.
	vec3 red    = vec3(1.0, 0.12, 0.0);
	vec3 yellow = vec3(1.0, 0.9, 0.15);
	vec3 fire = mix(red, yellow, 0.5 + 0.5 * sin(a * 5.0 - TIME * 9.0 + r * 0.8));

	// How hot this pixel's side is; hot sides alternate pulse rings between
	// alien and fire (offset half a ring so they interleave).
	float hot = (wl * left_hot + wr * right_hot) / max(wl + wr, 0.001);
	float fire_ring = smoothstep(0.2, 0.8, 0.5 + 0.5 * sin(ring_phase * 0.5));
	vec3 colour = mix(alien, fire, hot * fire_ring);

	float active = (wl * left_active + wr * right_active) / max(wl + wr, 0.001);
	float strength = mix(base_strength, active_strength, active);

	COLOR = vec4(colour, radial * ripple * coverage * strength);
}
