// psx_opaque.gdshader
// ---------------------------------------------------------------------------
// WHAT: The workhorse spatial shader for all opaque world geometry.
// RESPONSIBLE FOR: reproducing the four defining PlayStation 1 rasteriser
//   artefacts -- vertex snapping, affine texture mapping, per-vertex lighting
//   with no specular, and colour quantisation -- plus distance fade.
// WHY IT EXISTS: every opaque surface in a project built from this template
//   should look consistent. Per-object variation is handled by `instance
//   uniform`s below, NOT by forking this file.
//
// -- Technique notes, so this file teaches rather than just works ------------
//
// 1. VERTEX SNAPPING
//    The PS1 GTE had no floating-point vertex output. Screen positions were
//    computed as integers, so vertices visibly jump between whole pixels as
//    the camera moves. We reproduce this by doing the model-view-projection
//    transform ourselves, dividing by w to reach normalised device coords,
//    rounding xy onto a grid the size of the target framebuffer, then
//    multiplying back by w so the hardware's own perspective divide lands on
//    the value we chose. Writing to POSITION overrides Godot's own transform.
//
// 2. AFFINE TEXTURE MAPPING
//    The PS1 interpolated texture coordinates linearly in SCREEN space, with
//    no perspective correction, which makes textures visibly swim and warp on
//    large polygons at shallow angles. Modern GPUs always interpolate
//    perspective-correctly and there is no switch to turn that off. The trick:
//    a varying premultiplied by w survives perspective-correct interpolation
//    as a screen-linear value, because the rasteriser's own 1/w weighting
//    cancels the w we baked in. Pass (UV * w) and (w) as varyings, divide one
//    by the other in fragment(), and the result is the affine UV. We then
//    blend toward the perspective-correct built-in UV so the artefact is a
//    dial, not a switch.
//
// 3. LIGHTING
//    `vertex_lighting` evaluates lights per-vertex (as the PS1's Gouraud
//    shading did) and `specular_disabled` removes highlights the console
//    could not produce. VERTEX and NORMAL are untouched by the snapping above,
//    so lighting stays stable while the silhouette jitters -- which is what
//    the real hardware did.
//
// 4. COLOUR QUANTISATION
//    Applied to the sampled albedo, because that reproduces the PS1's 15-bit
//    texture memory. Quantisation of the finished *frame* is a separate
//    concern and belongs to psx_dither.gdshader, on the post-process layer.
//
// 5. FOG
//    Written as an albedo fade plus matching EMISSION rather than by writing
//    the FOG built-in. This keeps the fade independent of scene lighting and
//    behaves identically under the Compatibility renderer, which is the only
//    renderer this template supports.
// ---------------------------------------------------------------------------

shader_type spatial;
render_mode vertex_lighting, specular_disabled, diffuse_lambert, cull_back;

// --- Global look parameters. Owned by PSXLook, set via RenderingServer. -----
global uniform vec2 psx_snap_resolution;
global uniform float psx_affine_strength;
global uniform float psx_color_depth;
global uniform bool psx_fog_enabled;
global uniform vec3 psx_fog_color;
global uniform float psx_fog_near;
global uniform float psx_fog_far;
global uniform bool psx_jitter_enabled;

// --- Per-object variation. Set with GeometryInstance3D.set_instance_shader_
// --- parameter(). This is why there is no psx_opaque_variant.gdshader. ------
instance uniform float psx_instance_affine : hint_range(0.0, 1.0) = 1.0;
instance uniform vec4 psx_instance_emission : source_color = vec4(0.0);

// --- Per-material surface parameters. --------------------------------------
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform vec4 albedo_modulate : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);

varying vec2 v_uv_times_w;
varying float v_w;

void vertex() {
	// Do the transform by hand so we can quantise the result (note 1).
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);

	if (psx_jitter_enabled) {
		// NDC spans -1..1, so a framebuffer of N pixels is a grid of N/2 units.
		vec2 grid = max(psx_snap_resolution, vec2(1.0)) * 0.5;
		clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	}
	POSITION = clip;

	// Premultiply by w so perspective-correct interpolation yields a
	// screen-linear value in fragment() (note 2).
	v_uv_times_w = (UV * uv_scale + uv_offset) * clip.w;
	v_w = clip.w;
}

void fragment() {
	vec2 uv_correct = UV * uv_scale + uv_offset;
	vec2 uv_affine = v_uv_times_w / v_w;
	vec2 uv = mix(uv_correct, uv_affine, clamp(psx_affine_strength * psx_instance_affine, 0.0, 1.0));

	vec4 tex = texture(albedo_texture, uv);

	// Quantise the texture read, not the lit result (note 4).
	float levels = max(psx_color_depth, 2.0);
	tex.rgb = floor(tex.rgb * levels + 0.5) / levels;

	// COLOR carries baked vertex lighting -- the lighting model this template
	// is built around. Multiply it in rather than relying on a render_mode so
	// the interaction stays visible in the code.
	vec3 albedo = tex.rgb * albedo_modulate.rgb * COLOR.rgb;
	vec3 emission = psx_instance_emission.rgb * psx_instance_emission.a;

	if (psx_fog_enabled) {
		float dist = length(VERTEX); // VERTEX is view space in fragment().
		float fog = clamp((dist - psx_fog_near) / max(psx_fog_far - psx_fog_near, 0.001), 0.0, 1.0);
		albedo *= 1.0 - fog;
		emission = emission * (1.0 - fog) + psx_fog_color * fog;
	}

	ALBEDO = albedo;
	EMISSION = emission;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
