// psx_crt.gdshader
// ---------------------------------------------------------------------------
// WHAT: Optional display emulation -- scanlines, mild barrel curvature, edge
//   vignette. Applied full-screen above the dither pass.
// RESPONSIBLE FOR: suggesting a CRT without becoming the look.
//
// -- Deliberately conservative -----------------------------------------------
// This pass is a garnish and ships DISABLED. It is not part of the PSX look;
// it is a filter over it. No aperture grille, no phosphor bloom, no chromatic
// aberration, no rolling flicker -- those read as "shader demo", not as a
// game, and they fight the 320x240 integer-scaled pixel grid this template
// exists to protect. Everything here is a local uniform rather than a global
// because nothing else in the pipeline needs to know a CRT filter exists;
// PSXLook toggles the pass by node visibility (Phase 6).
//
// -- Technique ---------------------------------------------------------------
// Curvature: push SCREEN_UV outward from centre proportionally to the square
// of its distance from centre, which is the cheap standard approximation of a
// barrel lens. Sampling outside 0..1 after that would wrap or clamp, so we
// discard to black instead -- that black border IS the tube edge.
// Scanlines: darken alternate framebuffer rows. Tied to FRAGCOORD, not UV, so
// the lines stay one framebuffer pixel apart at any window size.
//
// -- VERIFIED GOTCHA: chaining two screen-reading passes ---------------------
// Measured on Godot 4.7.1, Compatibility/GLES3. Two full-rect ColorRects that
// both read `hint_screen_texture` as plain siblings in one CanvasLayer do NOT
// chain: both sample the same pre-post-process backbuffer, and whichever draws
// last simply overwrites the other. The fix is one node -- put a
// BackBufferCopy (copy_mode = Viewport) BETWEEN them, which forces the
// backbuffer to be re-captured so the second pass sees the first pass's
// output. Giving each pass its own CanvasLayer also works, because Godot
// inserts the copy at the layer boundary. SubViewport chaining is NOT needed.
// ---------------------------------------------------------------------------

shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

uniform float curvature : hint_range(0.0, 0.30) = 0.04;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.15;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.20;

void fragment() {
	vec2 uv = SCREEN_UV;

	// Barrel distortion around the centre of the screen.
	vec2 centered = uv * 2.0 - 1.0;
	centered += centered * curvature * dot(centered, centered);
	uv = centered * 0.5 + 0.5;

	// Outside the tube.
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		vec3 color = texture(screen_texture, uv).rgb;

		// Darken every other framebuffer row.
		float row = mod(FRAGCOORD.y, 2.0);
		color *= 1.0 - scanline_strength * row;

		// Soft falloff toward the corners.
		float vignette = 1.0 - vignette_strength * dot(centered, centered) * 0.5;
		color *= clamp(vignette, 0.0, 1.0);

		COLOR = vec4(color, 1.0);
	}
}
