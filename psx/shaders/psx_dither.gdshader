// psx_dither.gdshader
// ---------------------------------------------------------------------------
// WHAT: Full-screen framebuffer quantisation with ordered dithering.
// RESPONSIBLE FOR: crushing the finished frame down to a low bit depth while
//   using a 4x4 Bayer pattern to fake the intermediate shades that were just
//   thrown away.
// WHERE IT LIVES: on a full-rect ColorRect inside a CanvasLayer, above the 3D
//   world. See ui/post_process/ (Phase 6).
//
// -- Why a canvas_item shader and not a CompositorEffect ---------------------
// This template is locked to the Compatibility renderer, because that is the
// only rendering method Godot 4 supports for web export. CompositorEffect is
// a RenderingDevice feature and does not exist under Compatibility. The
// classic full-rect ColorRect reading `hint_screen_texture` is the portable
// approach, and the only one that will survive an HTML5 build.
//
// -- Technique ---------------------------------------------------------------
// The PS1 output a 15-bit framebuffer (5 bits per channel, 32 levels) and had
// dedicated hardware to dither the 24-bit result of its blending down to that
// depth. Ordered (Bayer) dithering adds a small, spatially varying offset
// before rounding, so a colour that sits between two representable levels
// becomes a stable checkerboard of both rather than a flat band.
//
// The threshold matrix is applied in FRAGCOORD space, so the pattern is
// locked to framebuffer pixels. Because the root viewport is 320x240 and the
// project uses `viewport` stretch with integer scaling, one framebuffer pixel
// is one fat on-screen pixel and the pattern reads as intended. Sampling the
// screen texture with `filter_nearest` matters for the same reason.
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

global uniform float psx_color_depth;
global uniform float psx_dither_strength;

// Ordered 4x4 Bayer threshold matrix, pre-divided by 16 and biased to -0.5..0.5.
// Stored as columns; index as BAYER[x][y].
const mat4 BAYER_4X4 = mat4(
		vec4(-0.5000, 0.2500, -0.3125, 0.4375),
		vec4( 0.0000, -0.2500, 0.1875, -0.0625),
		vec4(-0.3750, 0.3750, -0.4375, 0.3125),
		vec4( 0.1250, -0.1250, 0.0625, -0.1875));

void fragment() {
	vec3 color = texture(screen_texture, SCREEN_UV).rgb;

	float levels = max(psx_color_depth, 2.0);
	ivec2 cell = ivec2(mod(FRAGCOORD.xy, 4.0));
	float threshold = BAYER_4X4[cell.x][cell.y];

	// Offset by up to one quantisation step before rounding. At strength 0
	// this collapses to plain banding; at 1 it is full hardware-style dither.
	color += threshold * psx_dither_strength / levels;
	color = floor(color * levels + 0.5) / levels;

	COLOR = vec4(color, 1.0);
}
