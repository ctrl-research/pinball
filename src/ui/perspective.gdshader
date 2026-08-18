shader_type canvas_item;
render_mode unshaded;

// Warps the playfield -- rendered flat into a SubViewport -- into the trapezoid
// you see when you stand at a real cabinet: full width at the near end, and
// narrower and vertically compressed as it recedes.
//
// Doing it here rather than in the drawing code is what keeps the physics
// honest. The simulation stays a plain top-down 2D world with no idea any of
// this is happening; only the last step before the screen knows about
// perspective. Nothing about a ball's motion depends on where it is being
// drawn, which is exactly the property a pinball game cannot afford to lose.

// Width of the far (top) edge as a fraction of the near (bottom) edge.
uniform float top_scale : hint_range(0.4, 1.0) = 0.82;

void fragment() {
	// Straight edges in *screen* space, so the cabinet's rails stay straight
	// lines: the trapezoid's relative width is linear in screen y.
	float half_width = mix(top_scale, 1.0, UV.y);
	float u = 0.5 + (UV.x - 0.5) / half_width;

	if (u < 0.0 || u > 1.0) {
		// Outside the trapezoid. Transparent so the cabinet shows through.
		COLOR = vec4(0.0);
	} else {
		// Projective rather than linear in v. A linear map would give a
		// trapezoid that someone has merely drawn; dividing by the same
		// interpolant that narrows the row is what makes the far end compress
		// and the near end stretch, which is the part the eye reads as depth.
		//
		// Derived from y = v*s / (1 - v*(1 - s)), inverted for v.
		float v = UV.y / (top_scale + UV.y * (1.0 - top_scale));
		COLOR = texture(TEXTURE, vec2(u, v));
	}
}
