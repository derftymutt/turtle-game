shader_type canvas_item;

// Colours a "♥" heart Label as a rainbow heart (HeartsDisplay): horizontal
// rainbow bands top to bottom (red → violet), with everything right of `fill`
// drawn in the empty-heart colour — fill 1 = full, 0.5 = left half only,
// 0 = empty. The black outline glyphs come through untouched.

uniform float fill = 1.0;
uniform vec4 empty_color : source_color = vec4(0.24, 0.24, 0.26, 1.0);
// The label's size, so VERTEX can be turned into 0–1 across / down the glyph
uniform vec2 label_size = vec2(16.0, 26.0);
// Where the heart sits vertically in the label, as fractions of its height
uniform float band_top = 0.32;
uniform float band_bottom = 0.80;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	// Outline glyphs are drawn with a black modulate — leave them black
	if (COLOR.r + COLOR.g + COLOR.b > 0.15) {
		vec2 size = max(label_size, vec2(1.0));
		float x = local_pos.x / size.x;
		float y = clamp((local_pos.y / size.y - band_top) / (band_bottom - band_top), 0.0, 1.0);
		// Seven distinct bands rather than a smooth blend, like the rainbow
		float band = min(floor(y * 7.0), 6.0) / 7.0;
		vec3 rainbow = hsv2rgb(vec3(band * 0.83, 0.75, 1.0));
		vec3 rgb = x < fill ? rainbow : empty_color.rgb;
		COLOR = vec4(rgb, COLOR.a);
	}
}
