shader_type canvas_item;

// A single soft horizontal band that sweeps down the screen and refracts
// whatever was drawn beneath it (the ocean + everything in it). Purely visual.
// Lives on a CanvasLayer below the HUD, so the HUD is never touched.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

uniform float progress = -0.5;       // band centre in screen-V; sweeps travel_from -> travel_to
uniform float band_width = 0.16;     // vertical falloff of the band (screen-V units)
uniform float amplitude = 0.0;       // 0..1 master strength, enveloped by the script
uniform float amp_pixels = 3.5;      // peak horizontal displacement, in game pixels
uniform float surface_v = 0.15;      // screen-V of the water surface; nothing above it ripples
uniform float shimmer_time = 0.0;    // seconds, drives the along-band wobble
uniform float wobble_freq = 18.0;    // how many undulations top-to-bottom
uniform float wobble_speed = 2.4;    // how fast the undulation crawls
uniform float lens_strength = 0.30;  // slight vertical "bulge" as the band passes
uniform float glint = 0.04;          // brightness lift on the crest
uniform float chroma = 1.0;          // 0..1 amount of RGB split (0 = no colour fringing)
uniform vec2 screen_px = vec2(640.0, 360.0);

void fragment() {
	float v = SCREEN_UV.y;
	float d = v - progress;

	// Gaussian-ish envelope around the travelling band
	float env = exp(-(d * d) / (band_width * band_width));

	// Confine the effect to the water (soft edge just under the surface line)
	float ocean_mask = smoothstep(surface_v - 0.01, surface_v + 0.05, v);

	float k = env * ocean_mask * amplitude;

	if (k < 0.001) {
		COLOR = texture(screen_tex, SCREEN_UV);
	} else {
		vec2 px = 1.0 / screen_px;

		// Horizontal undulation: phase varies down the screen and crawls over time
		float wob = sin(v * wobble_freq + SCREEN_UV.x * 4.0 + shimmer_time * wobble_speed);

		vec2 offset = vec2(0.0);
		offset.x = wob * amp_pixels * px.x * k;
		// Gentle vertical lensing: samples get pulled toward the band centre
		offset.y = -d * lens_strength * k * 0.12;

		vec2 uv = SCREEN_UV + offset;

		// Faint chromatic split for the "looking through glass/water" feel
		float ca = 0.6 * amp_pixels * px.x * k * chroma;
		vec4 col;
		col.r = texture(screen_tex, uv + vec2(ca, 0.0)).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, uv - vec2(ca, 0.0)).b;
		col.a = 1.0;

		col.rgb += glint * k;
		COLOR = col;
	}
}
