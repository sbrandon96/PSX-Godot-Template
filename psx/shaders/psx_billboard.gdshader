// psx_billboard.gdshader
// ---------------------------------------------------------------------------
// WHAT: Spatial shader for camera-facing sprite quads -- props, pickups,
//   particles, distant entities drawn as 2D stand-ins.
// RESPONSIBLE FOR: orienting a quad toward the camera in the vertex shader,
//   then applying the same PSX snapping / affine / quantisation / fog rules
//   as the rest of the pipeline.
//
// -- Why this is a separate shader ------------------------------------------
// Billboarding is a rewrite of MODELVIEW_MATRIX. It cannot be expressed as an
// instance uniform on psx_opaque, because the transform must happen before the
// projection we do by hand. That is a structural difference, not a parameter.
//
// -- Design decision: this shader is `unshaded` ------------------------------
// Not specified by the blueprint. PS1 sprites were pre-lit -- their brightness
// was baked into the texture or the vertex colours, because a flat quad that
// always faces the camera has no meaningful surface normal to light. Running
// it through the vertex-lighting path would produce a normal that swings as
// the camera orbits, making sprites pulse. So: COLOR is the prelight, and
// fog is mixed straight into ALBEDO (EMISSION is ignored when unshaded).
//
// -- Billboard maths ---------------------------------------------------------
// INV_VIEW_MATRIX's basis is the camera's world-space orientation. Building a
// model matrix from that basis plus the object's own world position gives a
// quad that always faces the viewer. Scale is re-applied separately because
// the camera basis is orthonormal and would otherwise discard it.
// `y_billboard` keeps the quad upright (a tree, a standing figure) instead of
// tilting to face a camera looking down.
//
// Snapping and affine mapping are explained in psx_opaque.gdshader.
// ---------------------------------------------------------------------------

shader_type spatial;
render_mode unshaded, cull_disabled;

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

uniform sampler2D albedo_texture : source_color, hint_default_white, filter_nearest_mipmap, repeat_disable;
uniform vec4 albedo_modulate : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;
uniform bool y_billboard = false;

varying vec2 v_uv_times_w;
varying float v_w;

void vertex() {
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;
	vec3 cam_forward = INV_VIEW_MATRIX[2].xyz;

	if (y_billboard) {
		// Lock the up axis to world +Y and rebuild an orthogonal basis around it.
		cam_up = vec3(0.0, 1.0, 0.0);
		cam_right = normalize(cross(cam_up, cam_forward));
		cam_forward = normalize(cross(cam_right, cam_up));
	}

	// Camera-aligned basis + the object's own world position.
	mat4 billboard = mat4(
			vec4(cam_right, 0.0),
			vec4(cam_up, 0.0),
			vec4(cam_forward, 0.0),
			MODEL_MATRIX[3]);

	// The camera basis is orthonormal, so re-apply the node's own scale.
	mat4 rescale = mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));

	MODELVIEW_MATRIX = VIEW_MATRIX * billboard * rescale;

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

	// COLOR is the prelight (see header). Emission is added, not lit.
	vec3 albedo = tex.rgb * albedo_modulate.rgb * COLOR.rgb
			+ psx_instance_emission.rgb * psx_instance_emission.a;

	if (psx_fog_enabled) {
		float dist = length(VERTEX);
		float fog = clamp((dist - psx_fog_near) / max(psx_fog_far - psx_fog_near, 0.001), 0.0, 1.0);
		// Unshaded: mix straight to fog colour, since EMISSION is not applied.
		albedo = mix(albedo, psx_fog_color, fog);
	}

	ALBEDO = albedo;
	ALPHA = tex.a * albedo_modulate.a * COLOR.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}
