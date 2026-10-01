shader_type canvas_item;

// 1px outline around the sprite's silhouette — marks the rainbow fish of the
// colour to free next without touching its own colours. RainbowFish drives
// `strength` (0 = off) to pulse it.
//
// COLOR arrives already multiplied by the texture (Godot 4), so opaque pixels
// are left exactly as they are.

uniform vec4 outline_color : source_color = vec4(1.0);
uniform float strength = 0.0;
// Sheet frame size in pixels — neighbours in another frame are ignored, so
// the next frame's art can't bleed an outline in at the frame edge
uniform vec2 frame_px = vec2(24.0, 24.0);

float neighbour_alpha(sampler2D tex, vec2 uv, vec2 offset, vec2 cell, vec2 frame) {
	vec2 n = uv + offset;
	if (floor(n / cell) != frame) {
		return 0.0;
	}
	return texture(tex, n).a;
}

void fragment() {
	if (strength > 0.0 && texture(TEXTURE, UV).a < 0.5) {
		vec2 px = TEXTURE_PIXEL_SIZE;
		vec2 cell = frame_px * px;
		vec2 frame = floor(UV / cell);
		float n = neighbour_alpha(TEXTURE, UV, vec2(px.x, 0.0), cell, frame)
			+ neighbour_alpha(TEXTURE, UV, vec2(-px.x, 0.0), cell, frame)
			+ neighbour_alpha(TEXTURE, UV, vec2(0.0, px.y), cell, frame)
			+ neighbour_alpha(TEXTURE, UV, vec2(0.0, -px.y), cell, frame);
		if (n > 0.5) {
			COLOR = vec4(outline_color.rgb, outline_color.a * strength);
		}
	}
}
