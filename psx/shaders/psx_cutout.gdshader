// psx_cutout.gdshader
// ---------------------------------------------------------------------------
// WHAT: Spatial shader for alpha-scissor geometry -- railings, fences,
//   foliage, chain-link, grates.
// RESPONSIBLE FOR: everything psx_opaque does, plus a hard alpha cut.
// WHY IT EXISTS AS A SEPARATE FILE: alpha scissor forces the GPU off the
//   early-depth-test fast path, so it must not be paid for by every opaque
//   surface in the scene. It is also double-sided (`cull_disabled`), and
//   culling is a render_mode -- it cannot be switched by a uniform. Those two
//   facts, not per-object variation, are what justify a second shader.
//
// The PSX technique notes live in psx_opaque.gdshader; they are identical
// here. The only additions are:
//   * ALPHA / ALPHA_SCISSOR_THRESHOLD, giving the binary on/off transparency
//     the PS1 had. There was no blended alpha on textured world geometry.
//   * The alpha channel is deliberately NOT quantised -- rounding it would
//     shift the cutout edge unpredictably as psx_color_depth changes.
// ---------------------------------------------------------------------------

shader_type spatial;
render_mode vertex_lighting, specular_disabled, diffuse_lambert, cull_disabled;

global uniform vec2 psx_snap_resolution;
global uniform float psx_affine_strength;
global uniform float psx_color_depth;
global uniform bool psx_fog_enabled;
global uniform vec3 psx_fog_color;
global uniform float psx_fog_near;
global uniform float psx_fog_far;
global uniform bool psx_jitter_enabled;

instance uniform float psx_instance_affine : hint_range(0.0, 1.0) = 1.0;
instance uniform vec4 psx_instance_emission : source_color = vec4(0.0);

uniform sampler2D albedo_texture : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform vec4 albedo_modulate : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;

varying vec2 v_uv_times_w;
varying float v_w;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);

	if (psx_jitter_enabled) {
		vec2 grid = max(psx_snap_resolution, vec2(1.0)) * 0.5;
		clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	}
	POSITION = clip;

	v_uv_times_w = (UV * uv_scale + uv_offset) * clip.w;
	v_w = clip.w;
}

void fragment() {
	vec2 uv_correct = UV * uv_scale + uv_offset;
	vec2 uv_affine = v_uv_times_w / v_w;
	vec2 uv = mix(uv_correct, uv_affine, clamp(psx_affine_strength * psx_instance_affine, 0.0, 1.0));

	vec4 tex = texture(albedo_texture, uv);

	float levels = max(psx_color_depth, 2.0);
	tex.rgb = floor(tex.rgb * levels + 0.5) / levels;

	vec3 albedo = tex.rgb * albedo_modulate.rgb * COLOR.rgb;
	vec3 emission = psx_instance_emission.rgb * psx_instance_emission.a;

	if (psx_fog_enabled) {
		float dist = length(VERTEX);
		float fog = clamp((dist - psx_fog_near) / max(psx_fog_far - psx_fog_near, 0.001), 0.0, 1.0);
		albedo *= 1.0 - fog;
		emission = emission * (1.0 - fog) + psx_fog_color * fog;
	}

	ALBEDO = albedo;
	EMISSION = emission;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;

	// Binary transparency. Alpha is left unquantised on purpose (see header).
	ALPHA = tex.a * albedo_modulate.a * COLOR.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}
