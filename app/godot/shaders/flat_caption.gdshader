shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_premul_alpha;
uniform sampler2D caption_texture : source_color, filter_linear, repeat_disable;
void fragment() {
  vec4 c = texture(caption_texture, UV);
  ALBEDO = c.rgb;
  ALPHA = c.a;
}
