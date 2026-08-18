shader_type canvas_item;
render_mode unshaded;

// A CRT pass over the finished frame: curvature, scanlines, an aperture mask,
// chromatic fringing and a vignette.
//
// It samples the screen rather than living on the playfield's SubViewport,
// because a monitor is in front of *everything*. Applying it to the playfield
// alone would put the panels and the cabinet outside the glass, which reads as
// a game with a filter on part of it rather than a game on a CRT.
//
// Every effect here is deliberately understated. The panels carry 7pt text, and
// a shader that makes the score unreadable has bought atmosphere with the one
// thing the player actually needs.
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

uniform float curvature : hint_range(0.0, 0.3) = 0.045;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.18;
// Tied to the 360px design height, not the physical resolution, so the lines
// scale with the game and a bigger window does not mean finer scanlines.
uniform float scanline_count = 360.0;
uniform float mask_strength : hint_range(0.0, 0.5) = 0.07;
uniform float aberration : hint_range(0.0, 0.01) = 0.0012;
uniform float vignette : hint_range(0.0, 1.0) = 0.22;
uniform float gain : hint_range(0.5, 2.0) = 1.16;

// Barrel distortion. Mild on purpose: it sits on top of the playfield's own
// perspective warp, and two distortions arguing with each other looks like a
// mistake rather than like glass.
vec2 curve(vec2 uv) {
	uv = uv * 2.0 - 1.0;
	vec2 bend = abs(uv.yx) / vec2(6.0, 5.0);
	uv += uv * bend * bend * curvature * 6.0;
	return uv * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = curve(SCREEN_UV);

	// Outside the curved glass is the inside of the bezel, not the game.
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		// Fringing grows with distance from centre, as a real tube's does.
		vec2 fringe = (uv - 0.5) * aberration;
		vec3 col = vec3(
			texture(screen_tex, uv + fringe).r,
			texture(screen_tex, uv).g,
			texture(screen_tex, uv - fringe).b);

		float scan = sin(uv.y * scanline_count * TAU) * 0.5 + 0.5;
		col *= 1.0 - scanline_strength * scan;

		// Aperture grille, in device pixels: it is a property of the glass, so
		// unlike the scanlines it should not scale with the game's resolution.
		float triad = mod(FRAGCOORD.x, 3.0);
		vec3 mask = vec3(1.0 - mask_strength);
		if (triad < 1.0) {
			mask.r = 1.0;
		} else if (triad < 2.0) {
			mask.g = 1.0;
		} else {
			mask.b = 1.0;
		}
		col *= mask;

		vec2 edge = uv * (1.0 - uv);
		col *= clamp(pow(edge.x * edge.y * 16.0, vignette), 0.0, 1.0);

		// Scanlines and the mask both only ever remove light, so without a gain
		// the whole picture just gets darker.
		COLOR = vec4(col * gain, 1.0);
	}
}
