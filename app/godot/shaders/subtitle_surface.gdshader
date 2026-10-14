shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled,
    blend_mix;
#include "res://shaders/projected_subtitles.gdshaderinc"
varying vec3 subtitle_direction;
varying flat int physical_eye;
void vertex() {
  subtitle_direction = VERTEX;
  physical_eye = int(VIEW_INDEX);
}
void fragment() {
  vec4 result = caption_composite(
      vec3(0.0), 0.0, projected_caption(subtitle_direction, physical_eye));
  ALBEDO = result.rgb;
  ALPHA = result.a;
}
