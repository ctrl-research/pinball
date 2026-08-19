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

uniform float curvature : hint_range(0.0, 0.3) = 0.058;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.26;
// Tied to the 360px design height, not the physical resolution, so the lines
// scale with the game and a bigger window does not mean finer scanlines.
uniform float scanline_count = 360.0;
uniform float mask_strength : hint_range(0.0, 0.5) = 0.12;
uniform float aberration : hint_range(0.0, 0.01) = 0.0018;
uniform float vignette : hint_range(0.0, 1.0) = 0.28;
uniform float gain : hint_range(0.5, 2.0) = 1.30;

// There is deliberately no signal wobble here. It used to live in this shader,
// and it could not work: this pass runs over the finished frame, so displacing
// the picture displaces the cabinet and the ball along with the readouts. The
// wobble now runs over the UI's own viewport in `text_crt.gdshader`, where it
// can move the type while the machine stays still.

// Phosphor glow. This is the part that actually reads on text: a CRT's beam
// blooms into its neighbours, so bright glyphs bleed a halo and thin strokes
// look thicker and softer than the geometry says. Without it, text under
// scanlines just looks like text with lines drawn over it.
uniform float glow_strength : hint_range(0.0, 1.5) = 0.55;
uniform float glow_spread : hint_range(0.0, 4.0) = 1.5;
// Only things already bright bloom, so the dark playfield stays dark instead of
// the whole picture lifting into grey.
uniform float glow_threshold : hint_range(0.0, 1.0) = 0.22;

// Barrel distortion. Mild on purpose: it sits on top of the playfield's own
// perspective warp, and two distortions arguing with each other looks like a
// mistake rather than like glass.
vec2 curve(vec2 uv) {
	uv = uv * 2.0 - 1.0;
	vec2 bend = abs(uv.yx) / vec2(6.0, 5.0);
	uv += uv * bend * bend * curvature * 6.0;
	return uv * 0.5 + 0.5;
}

// Eight taps around the sample point, bright-passed. Cheap, and at this
// resolution a wider or better-weighted kernel is not worth the samples.
vec3 phosphor(vec2 uv) {
	// Derived from the screen texture rather than SCREEN_PIXEL_SIZE, which
	// canvas_item shaders had in Godot 3 and do not have in 4. Referencing it
	// fails to compile, and a canvas_item shader that fails to compile does not
	// warn -- it silently draws the quad's flat colour over the whole game.
	vec2 px = 1.0 / vec2(textureSize(screen_tex, 0)) * glow_spread;
	vec3 sum = vec3(0.0);
	sum += texture(screen_tex, uv + vec2(px.x, 0.0)).rgb;
	sum += texture(screen_tex, uv - vec2(px.x, 0.0)).rgb;
	sum += texture(screen_tex, uv + vec2(0.0, px.y)).rgb;
	sum += texture(screen_tex, uv - vec2(0.0, px.y)).rgb;
	sum += texture(screen_tex, uv + px).rgb;
	sum += texture(screen_tex, uv - px).rgb;
	sum += texture(screen_tex, uv + vec2(px.x, -px.y)).rgb;
	sum += texture(screen_tex, uv + vec2(-px.x, px.y)).rgb;
	return max(sum / 8.0 - vec3(glow_threshold), vec3(0.0));
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

		// Glow is added before the scanlines and the mask, so the halo gets
		// striped and tinted along with everything else. Added afterwards it
		// would sit on top as a clean blur and read as a soft-focus filter
		// rather than as a phosphor.
		col += phosphor(uv) * glow_strength;

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
