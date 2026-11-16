shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform sampler2D color_texture : filter_linear, repeat_disable;
uniform vec2 source_size = vec2(1920.0, 1080.0);
uniform vec2 color_uv_scale = vec2(1.0);
uniform vec2 gaze = vec2(0.0);
uniform bool top_bottom = false;
uniform bool swap_eyes = false;
uniform bool stereo_half = false;
uniform int geometry = 1;
uniform float fisheye_fov = 180.0;
uniform int rotation_degrees = 0;
void fragment() {
  float eye = floor(UV.x * 2.0);
  vec2 angle = gaze + radians(vec2((fract(UV.x * 2.0) - 0.5) * 29.0, (0.5 - UV.y) * 12.0));
  vec3 d = vec3(sin(angle.x) * cos(angle.y), sin(angle.y), -cos(angle.x) * cos(angle.y));
  vec2 p = vec2(angle.x / (geometry == 3 ? 2.0 * PI : PI) + 0.5, 0.5 - angle.y / PI);
  if (geometry == 3) p.x = fract(p.x);
  if (geometry == 2) {
    float radial = acos(clamp(-d.z, -1.0, 1.0)) / radians(fisheye_fov * 0.5);
    vec2 axis = length(d.xy) > 0.000001 ? vec2(d.x, -d.y) / length(d.xy) : vec2(0.0);
    vec2 size = source_size / (top_bottom ? vec2(1.0, 2.0) : vec2(2.0, 1.0));
    p = vec2(0.5) + 0.5 * radial * axis * (stereo_half ? vec2(1.0) : min(size.x, size.y) / size);
  }
  if (rotation_degrees == 90) p = vec2(p.y, 1.0 - p.x);
  else if (rotation_degrees == 180) p = vec2(1.0) - p;
  else if (rotation_degrees == 270) p = vec2(1.0 - p.y, p.x);
  if (swap_eyes) eye = 1.0 - eye;
  if (top_bottom) p.y = (p.y + eye) * 0.5;
  else p.x = (p.x + eye) * 0.5;
  ALBEDO = texture(color_texture, p * color_uv_scale).rgb;
}
