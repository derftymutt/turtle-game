shader_type canvas_item;

// Replaces a flipper's accent pixels so the sprite always shows the colour of
// the input it's bound to, regardless of which side's art the scene uses.
// Both side accents are matched, so any flipper art works without knowing its
// original side. Pixel art is unfiltered, so an exact match (small tolerance
// for 8-bit rounding) is reliable. Every other pixel passes through untouched.
//
// Colours are plain vec4s (no source_color hint): 2D renders in sRGB here, so
// the raw sRGB values set from GDScript compare directly against the texture.

uniform vec4 left_accent = vec4(0.6, 0.898, 0.314, 1.0);    // #99e550
uniform vec4 right_accent = vec4(0.843, 0.482, 0.729, 1.0); // #d77bba
uniform vec4 target_accent = vec4(0.6, 0.898, 0.314, 1.0);

const float TOLERANCE = 0.01;

// Node modulate / vertex colour, captured before fragment() where COLOR
// already has the texture baked in.
varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (distance(c.rgb, left_accent.rgb) < TOLERANCE || distance(c.rgb, right_accent.rgb) < TOLERANCE) {
		c.rgb = target_accent.rgb;
	}
	COLOR = c * modulate;
}
