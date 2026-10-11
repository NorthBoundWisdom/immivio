shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Ordinary RGBA playback is opaque. Keep the same coordinates, sharpening,
// grading and captions without entering the transparent/matting render path.
uniform sampler2D color_texture : filter_linear, repeat_disable;
#include "res://shaders/color_grade.gdshaderinc"
#include "res://shaders/video_coordinates.gdshaderinc"
#include "res://shaders/sharpness.gdshaderinc"
#include "res://shaders/projected_subtitles.gdshaderinc"
#include "res://shaders/bitmap_subtitles.gdshaderinc"
uniform bool separate_subtitles = false;

vec2 raw_eye_uv(vec2 p) {
	if (rotation_degrees == 90) { return vec2(p.y, 1.0 - p.x); }
	if (rotation_degrees == 180) { return vec2(1.0) - p; }
	if (rotation_degrees == 270) { return vec2(1.0 - p.y, p.x); }
	return p;
}

void vertex() {
	eye_index = int(VIEW_INDEX);
	media_direction = VERTEX;
}

void fragment() {
	vec2 shown_uv = aligned_eye_uv(eye_uv(UV, media_direction));
	vec2 local_uv = raw_eye_uv(shown_uv);
	int eye = source_eye();
	vec2 eye_size = view_size();
	vec2 p = clamp(local_uv, vec2(0.5) / eye_size, vec2(1.0) - vec2(0.5) / eye_size);
	if (stereo_sbs && top_bottom) { p.y = (p.y + float(eye)) * 0.5; }
	else if (stereo_sbs) { p.x = (p.x + float(eye)) * 0.5; }
	vec3 rgb = texture(color_texture, p).rgb;
	if (sharpness > 0.0) {
		vec2 lo = vec2(0.5) / source_size;
		vec2 hi = vec2(1.0) - lo;
		if (stereo_sbs && top_bottom) { lo.y += float(eye) * 0.5; hi.y -= float(1 - eye) * 0.5; }
		else if (stereo_sbs) { lo.x += float(eye) * 0.5; hi.x -= float(1 - eye) * 0.5; }
		vec2 step_uv = max(vec2(1.0) / source_size, fwidth(p));
		rgb = sharpen_rgb(rgb, texture(color_texture, clamp(p + vec2(0.0, step_uv.y), lo, hi)).rgb,
			texture(color_texture, clamp(p - vec2(0.0, step_uv.y), lo, hi)).rgb,
			texture(color_texture, clamp(p + vec2(step_uv.x, 0.0), lo, hi)).rgb,
			texture(color_texture, clamp(p - vec2(step_uv.x, 0.0), lo, hi)).rgb);
	}
	ALBEDO = (outside_lens(media_direction) || outside_alignment(shown_uv)) ? vec3(0.0) : color_grade(rgb);
	if (!separate_subtitles) {
		if (subtitle_enabled) {
			vec4 caption = projected_caption(media_direction, eye_index);
			ALBEDO = caption.rgb + ALBEDO * (1.0 - caption.a);
		}
		if (bitmap_subtitle_enabled) {
			vec4 caption = bitmap_caption(local_uv);
			ALBEDO = caption.rgb + ALBEDO * (1.0 - caption.a);
		}
	}
}
