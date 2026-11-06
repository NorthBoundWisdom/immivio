shader_type spatial;
// Scene fallback keeps depth occlusion; native UI capture uses the same
// ordering.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 surface_color : source_color = vec4(0.07, 0.08, 0.10, 0.97);
uniform vec2 surface_size = vec2(1.0);
uniform float corner_radius = 0.02;
uniform float border_width = 0.0;
uniform vec4 border_color : source_color = vec4(0.36, 0.44, 0.53, 0.8);

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
  float rim = smoothstep(-border_width - edge, -border_width + edge, distance);
  float border = border_width > 0.0 ? rim * border_color.a : 0.0;
  ALBEDO = mix(surface_color.rgb, border_color.rgb, border);
  ALPHA = surface_color.a * (1.0 - smoothstep(-edge, edge, distance));
}
