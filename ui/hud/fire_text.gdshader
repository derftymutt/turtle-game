shader_type canvas_item;

// Fiery sweep for a hot alien tech's slot label: the text keeps its normal
// tech colour (base_color), and a slanted band of flowing red/orange/yellow
// fire repeatedly sweeps across it left to right, with a flickering edge so
// it licks like a flame rather than sliding as a clean stripe. Each new band
// sets off while the previous one is still finishing its pass (see
// overlap_distance), so the sweep loops continuously. The outline (drawn
// black) stays black. Expects the Label's modulate rgb to be white — the tech
// colour comes from base_color instead, so it's applied exactly once.

uniform vec4 base_color : source_color = vec4(1.0);
uniform float text_width = 100.0;      // label width in px, set from script
uniform float sweep_speed = 95.0;      // px per second a band travels
uniform float overlap_distance = 50.0; // next band starts when the current one is this many px from finishing
uniform float band_width = 26.0;       // px, half-width of the fire band
uniform float speed = 7.0;             // flow speed of the colours inside the band
uniform float band_scale = 0.22;       // fire stripes per px inside the band
uniform float slant = 0.35;            // vertical skew so the band leans like rising flame

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

vec3 fire_colour(vec2 p, float flicker) {
	float wave = p.x * band_scale + p.y * slant - TIME * speed + flicker;
	float s = 0.5 + 0.5 * sin(wave);
	s = s * s;  // favour red, with narrower yellow crests
	vec3 red    = vec3(1.0, 0.06, 0.0);
	vec3 orange = vec3(1.0, 0.42, 0.0);
	vec3 yellow = vec3(1.0, 0.95, 0.2);
	vec3 fire = s < 0.5 ? mix(red, orange, s * 2.0) : mix(orange, yellow, (s - 0.5) * 2.0);
	return fire + vec3(0.35, 0.3, 0.2) * pow(s, 10.0);  // white-hot glint at each crest
}

// Mask for one band whose centre is at `head` (in slanted x).
float band_mask(float x, float head) {
	return 1.0 - smoothstep(band_width * 0.4, band_width, abs(x - head));
}

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;

	float flicker = sin(local_pos.y * 1.3 + TIME * 17.0) * 0.6
			+ sin(local_pos.x * 0.5 - TIME * 11.0) * 0.4;

	// A band's centre travels from just off the text's left edge to just off
	// its right edge (margin = band half-width plus slant/flicker wobble). A
	// new band launches every (path - overlap_distance) px of travel, so at
	// most two are on the text at once: the current one, and the previous one
	// finishing its last overlap_distance px.
	float margin = band_width + 10.0;
	float path = text_width + margin * 2.0;
	float launch_every = max(path - overlap_distance, 1.0);
	float travelled = mod(TIME * sweep_speed, launch_every);
	float x = local_pos.x - local_pos.y * slant + flicker * 3.0;
	float mask = band_mask(x, -margin + travelled);
	float prev_travelled = travelled + launch_every;
	if (prev_travelled <= path) {
		mask = max(mask, band_mask(x, -margin + prev_travelled));
	}

	vec3 fill_colour = mix(base_color.rgb, fire_colour(local_pos, flicker), mask);

	// Outline pixels come through as black vertex colour; keep them black.
	float fill = smoothstep(0.05, 0.25, max(COLOR.r, max(COLOR.g, COLOR.b)));
	COLOR = vec4(mix(base.rgb, fill_colour, fill), base.a);
}
