shader_type canvas_item;
render_mode unshaded;

// The CRT pass for type, run over the UI viewport before it reaches the screen.
//
// This is the aggressive one. The full-screen pass in `crt.gdshader` has to
// stay understated because it is also sitting on top of the ball, and a
// playfield that swims is a playfield you cannot judge a bounce on. Here there
// is nothing but text under the shader, so the scanlines, the bloom and the
// signal wobble can all be pushed to where they are actually visible.
//
// Everything is bounded by the alpha of what is drawn: the viewport is
// transparent everywhere except where the UI is, so every effect below lands on
// glyphs and panels and nothing else. That is the whole point of the split.

// The viewport's own resolution. Effects that should sit on the pixel grid --
// the scanlines especially -- are derived from this rather than from the
// window, so they do not get finer as the window gets bigger.
uniform vec2 resolution = vec2(640.0, 360.0);

// --- Signal wobble ------------------------------------------------------------
//
// Two frequencies, because one is not visible. A single slow wave shifts every
// row by nearly the same amount, and a block of text sliding sideways as a unit
// reads as nothing at all. The fast ripple shifts neighbouring rows by
// *different* amounts, and that relative motion is what the eye picks up as an
// unstable signal.
//
// Deliberately small: at 640px wide these amount to about a third of a pixel
// each, so the nearest-neighbour sampling only crosses into a one-pixel step
// when the two waves peak together. That is the point of the setting -- the
// type sits still most of the time and shifts by exactly one pixel now and
// then, which reads as a signal that is *nearly* locked rather than as text
// that is permanently swimming.
uniform float wave_amount : hint_range(0.0, 0.006) = 0.00055;
uniform float wave_speed : hint_range(0.0, 8.0) = 1.3;
uniform float wave_freq : hint_range(0.0, 40.0) = 4.0;
uniform float ripple_amount : hint_range(0.0, 0.004) = 0.00035;
uniform float ripple_speed : hint_range(0.0, 20.0) = 5.0;
uniform float ripple_freq : hint_range(0.0, 400.0) = 110.0;

// --- Tube ---------------------------------------------------------------------

uniform float scanline_strength : hint_range(0.0, 1.0) = 0.22;
// Off by default, and that is not timidity -- it is that this pass *cannot* do
// it subtly. The layer is sampled nearest-neighbour, so a fringe offset either
// rounds to zero or to a whole pixel; there is no in-between. A whole pixel of
// red-blue split on a twelve-pixel glyph is not a hint of a badly converged
// tube, it is a coloured outline around every letter, and it was the single
// biggest thing making the small labels hard to read. The full-screen pass
// still fringes, where it has a filtered image to do it on properly.
uniform float aberration : hint_range(0.0, 0.01) = 0.0;
uniform float gain : hint_range(0.5, 2.0) = 1.14;

// Phosphor bloom. This is the effect that does most of the work on type: a real
// beam bleeds into its neighbours, so glyphs carry a halo and thin strokes read
// as thicker and softer than the geometry. It also keeps the text legible while
// the scanlines are cutting into it, which is why it can be this strong.
//
// The halo follows alpha rather than brightness, so it spreads the *shape* of
// the glyph outwards instead of whichever channel happened to be brightest.
uniform float glow_strength : hint_range(0.0, 2.0) = 0.45;
uniform float glow_spread : hint_range(0.0, 4.0) = 1.0;
uniform float glow_threshold : hint_range(0.0, 1.0) = 0.20;

void fragment() {
	vec2 uv = UV;
	uv.x += sin(uv.y * wave_freq + TIME * wave_speed) * wave_amount;
	uv.x += sin(uv.y * ripple_freq + TIME * ripple_speed) * ripple_amount;

	// Nothing wraps: a row pushed off one edge must not reappear on the other.
	if (uv.x < 0.0 || uv.x > 1.0) {
		COLOR = vec4(0.0);
	} else {
		vec4 base = texture(TEXTURE, uv);

		// Fringing grows with distance from the centre of the tube, as a real
		// one's does. Alpha is taken from the centre tap alone -- taking it
		// from the offset taps as well would smear a coloured ghost out past
		// the edge of every glyph.
		vec2 fringe = (uv - 0.5) * aberration;
		vec3 col = vec3(
			texture(TEXTURE, uv + fringe).r,
			base.g,
			texture(TEXTURE, uv - fringe).b);

		// Eight taps around the sample point, averaged. Inlined rather than put
		// in a helper because a built-in sampler cannot be passed as a function
		// argument: Godot's shader compiler reports
		// `!actions.custom_samplers.has(...)` once per frame and carries on
		// emitting code that references a sampler it never declared.
		vec2 px = glow_spread / resolution;
		vec4 halo = (
			texture(TEXTURE, uv + vec2(px.x, 0.0)) +
			texture(TEXTURE, uv - vec2(px.x, 0.0)) +
			texture(TEXTURE, uv + vec2(0.0, px.y)) +
			texture(TEXTURE, uv - vec2(0.0, px.y)) +
			texture(TEXTURE, uv + px) +
			texture(TEXTURE, uv - px) +
			texture(TEXTURE, uv + vec2(px.x, -px.y)) +
			texture(TEXTURE, uv + vec2(-px.x, px.y))) / 8.0;
		float lift = max(halo.a - glow_threshold, 0.0) * glow_strength;
		col += halo.rgb * lift;
		// The halo has to raise alpha as well, or it is a glow multiplied into
		// transparent space and nothing reaches the screen at all.
		float alpha = clamp(base.a + lift, 0.0, 1.0);

		// Scanlines on the viewport's own grid, so they land one per pixel row
		// of the design resolution rather than one per row of the window.
		float scan = sin(uv.y * resolution.y * PI) * 0.5 + 0.5;
		col *= 1.0 - scanline_strength * scan;

		COLOR = vec4(col * gain, alpha);
	}
}
