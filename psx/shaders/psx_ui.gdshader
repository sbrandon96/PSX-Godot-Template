// psx_ui.gdshader
// ---------------------------------------------------------------------------
// WHAT: Optional canvas_item shader for Control nodes -- HUD, menus, the
//   loading screen.
// RESPONSIBLE FOR: holding UI to the same colour budget as the world, so text
//   and panels do not look like a modern overlay pasted onto a PS1 game.
//
// -- Why UI needs its own shader --------------------------------------------
// psx_dither.gdshader reads `hint_screen_texture`, which is the composited
// frame. UI drawn ABOVE that pass never passes through it and would keep its
// full 24-bit colour. Rather than forcing all UI underneath the post stack --
// which would also curve and scanline the menus -- this shader applies the
// same quantisation to a Control's own texture, in place.
//
// It reads the same psx_color_depth and psx_dither_strength globals as the
// framebuffer pass, so UI and world always agree on the palette, and both
// respond to a single PSXLook change.
//
// Optional by design: assign it as a Control's material where you want it.
// Alpha is passed through untouched so panels and fades still composite.
// ---------------------------------------------------------------------------

shader_type canvas_item;
render_mode unshaded;

global uniform float psx_color_depth;
global uniform float psx_dither_strength;

uniform float palette_bias : hint_range(0.0, 1.0) = 1.0;

// Same matrix as psx_dither.gdshader; see that file for the explanation.
const mat4 BAYER_4X4 = mat4(
		vec4(-0.5000, 0.2500, -0.3125, 0.4375),
		vec4( 0.0000, -0.2500, 0.1875, -0.0625),
		vec4(-0.3750, 0.3750, -0.4375, 0.3125),
		vec4( 0.1250, -0.1250, 0.0625, -0.1875));

void fragment() {
	vec4 source = texture(TEXTURE, UV) * COLOR;

	float levels = max(psx_color_depth, 2.0);
	ivec2 cell = ivec2(mod(FRAGCOORD.xy, 4.0));
	float threshold = BAYER_4X4[cell.x][cell.y];

	vec3 quantised = source.rgb + threshold * psx_dither_strength / levels;
	quantised = floor(quantised * levels + 0.5) / levels;

	// palette_bias lets a single Control opt part-way out without a second material.
	COLOR = vec4(mix(source.rgb, quantised, palette_bias), source.a);
}
