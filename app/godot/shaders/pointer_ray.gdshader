shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
#include "res://shaders/pointer_ray.gdshaderinc"
void vertex() {
  ray_half_width_pixels = ray_core_half_width(VIEWPORT_SIZE);
  ray_side_pixels = (UV.x * 2.0 - 1.0) * (ray_half_width_pixels + 1.0);
  POSITION = ray_position(VERTEX, UV, COLOR.a, VIEW_MATRIX * MODEL_MATRIX, PROJECTION_MATRIX,
                          vec3(0.0), VIEWPORT_SIZE);
}
void fragment() {
  ALBEDO = ray_color.rgb;
  ALPHA = ray_opacity(UV);
}
