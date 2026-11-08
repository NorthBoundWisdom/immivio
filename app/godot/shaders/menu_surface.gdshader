shader_type spatial;
// Scene fallback keeps depth occlusion; native UI capture uses the same
// ordering.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 surface_color : source_color = vec4(0.07, 0.08, 0.10, 0.97);
uniform vec2 surface_size = vec2(1.0);
uniform float corner_radius = 0.02;
uniform float border_width = 0.0;
uniform vec4 border_color : source_color = vec4(0.36, 0.44, 0.53, 0.8);
// Soft top-to-bottom lift: the top edge is [sheen] lighter than the base colour.
uniform float sheen = 0.0;
// A thin light catch along the upper rim, fading towards the sides (glass edge).
uniform float rim_light = 0.0;
// Optional picture (thumbnails, covers) clipped to the same rounded shape.
uniform bool use_texture = false;
uniform sampler2D surface_texture : source_color, filter_linear_mipmap, repeat_disable;

varying vec2 surface_position;

void vertex() {
  // The SDF edge needs fragments on both sides of the logical rectangle.
  // Otherwise the quad clips its outer coverage to a jagged half-alpha edge.
  // Keep the shape and hit bounds unchanged; extend only its transparent skirt.
  VERTEX.xy += sign(VERTEX.xy) * 0.003;
  surface_position = VERTEX.xy;
}

void fragment() {
  float radius = min(corner_radius, min(surface_size.x, surface_size.y) * 0.5);
  vec2 q = abs(surface_position) - (surface_size * 0.5 - vec2(radius));
  float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
  float edge = max(fwidth(distance), 0.0003);
  vec3 base = surface_color.rgb;
  float picture_alpha = 1.0;
  if (use_texture) {
    vec2 uv = clamp(surface_position / surface_size + 0.5, 0.0, 1.0);
    vec4 picture = texture(surface_texture, vec2(uv.x, 1.0 - uv.y));
    base *= picture.rgb;
    picture_alpha = picture.a;
  }
  float height = clamp(surface_position.y / max(surface_size.y, 0.0001) + 0.5, 0.0, 1.0);
  base += vec3(sheen) * height * height;
  if (rim_light > 0.0) {
    float band = 1.0 - smoothstep(0.0, 0.006, -distance);
    float upper = smoothstep(0.15, 0.85, height);
    base = mix(base, vec3(1.0), band * upper * rim_light);
  }
  float rim = smoothstep(-border_width - edge, -border_width + edge, distance);
  float border = border_width > 0.0 ? rim * border_color.a : 0.0;
  ALBEDO = mix(base, border_color.rgb, border);
  ALPHA = surface_color.a * picture_alpha * (1.0 - smoothstep(-edge, edge, distance));
}
