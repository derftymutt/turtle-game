shader_type canvas_item;

// Applied to the found-tech name Label so it reads as something special
// rather than just another blinking label — a bright band sweeps left to
// right through the text, like a flashlight passing over something
// reflective, repeating on a loop. Keeps the label's own color (set via
// modulate from script, one per tech) everywhere except under the band.
//
// band_left_uv/band_right_uv are the actual rendered text's horizontal
// bounds (not the whole, wider, centered Label control), normalized to
// 0..1 across the viewport — the script side recomputes them every frame
// from the label's font metrics divided by viewport width. Normalized
// (SCREEN_UV) rather than raw pixels because the game window can render at
// several times the project's logical 640x360 design resolution (integer
// display scaling), so FRAGCOORD's physical pixel coordinates don't match
// Control.get_global_rect()'s logical ones — SCREEN_UV sidesteps that.

uniform float band_left_uv = 0.0;
uniform float band_right_uv = 1.0;
uniform float shine_speed : hint_range(0.05, 3.0) = 0.7; // sweeps per second
uniform float shine_width_uv : hint_range(0.001, 0.1) = 0.02;
uniform float shine_strength : hint_range(0.0, 1.0) = 0.9;
uniform vec3 shine_color : source_color = vec3(1.0); // color the band mixes toward (default white)
// Seconds, fed by the script every frame rather than using the builtin TIME
// directly, so a caller juggling multiple targets (e.g. a menu where focus
// moves between options) can reset the sweep to start-of-band by resetting
// its own clock, instead of the band jumping to wherever a shared global
// TIME happens to be when it's handed to a newly-focused target.
uniform float shine_time = 0.0;

void fragment() {
	// COLOR arrives already set to texture(TEXTURE, UV) * the vertex color
	// (which bakes in the Label's modulate — its per-tech color) — the
	// engine's normal default before any custom fragment code runs. Mix
	// from that instead of resampling TEXTURE ourselves, which would
	// discard that tint and leave the raw (near-white) glyph color.
	if (COLOR.a > 0.001) {
		// Run-up/run-out padding so the band visibly enters and exits past
		// the text edges instead of popping in/out right at the letters.
		float pad = shine_width_uv * 1.5;
		float t = fract(shine_time * shine_speed);
		float band_x = mix(band_left_uv - pad, band_right_uv + pad, t);
		float dist = abs(SCREEN_UV.x - band_x);
		float shine = smoothstep(shine_width_uv, 0.0, dist);
		COLOR.rgb = mix(COLOR.rgb, shine_color, shine * shine_strength);
	}
}
