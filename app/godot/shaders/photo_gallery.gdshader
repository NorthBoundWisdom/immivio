shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform sampler2D picture : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_picture = false;
uniform vec4 crop_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 eye_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform int geometry = 0;
uniform float brightness = 1.0;
uniform float opacity = 1.0;
void fragment() {
  vec2 p = crop_rect.xy + UV * crop_rect.zw;
  if (geometry > 0) {
    vec3 ray = normalize(vec3((p.x - 0.5) * 1.5, (0.5 - p.y) * 1.125, -1.0));
    if (geometry == 2) {
      float angle = acos(clamp(-ray.z, -1.0, 1.0));
      vec2 radial = length(ray.xy) > 0.0001 ? normalize(ray.xy) : vec2(0.0);
      p = vec2(0.5) + radial * vec2(1.0, -1.0) * angle / 3.14159265;
    } else {
      p = vec2(0.5 + atan(ray.x, -ray.z) /
                         (geometry == 3 ? 6.2831853 : 3.14159265),
               0.5 - asin(ray.y) / 3.14159265);
    }
  }
  vec4 color = has_picture ? texture(picture, eye_rect.xy + p * eye_rect.zw)
                           : vec4(0.075, 0.12, 0.14, 1.0);
  ALBEDO = color.rgb * brightness;
  ALPHA = color.a * opacity;
}
