shader_type canvas_item;

// Full-screen radial vignette used as damage feedback — corners darken like an
// old photo. `intensity` is driven from script (hud.gd) and tweened from a
// peak back to 0 each time the player takes a hit; at rest it stays at 0 and
// the rect is fully transparent. SCREEN_UV (not UV) so the falloff shape
// stays centered on the viewport regardless of integer display scaling (see
// text_shine.gdshader for the same reasoning).
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float radius : hint_range(0.0, 1.0) = 0.32;
uniform float softness : hint_range(0.01, 1.5) = 0.55;
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 centered = SCREEN_UV - vec2(0.5);
	float dist = length(centered);
	float vig = smoothstep(radius, radius + softness, dist);
	COLOR = vec4(vignette_color.rgb, vig * intensity);
}
