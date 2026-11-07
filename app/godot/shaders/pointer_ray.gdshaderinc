uniform vec4 ray_color : source_color = vec4(1.0, 1.0, 1.0, 0.5);
uniform vec3 ray_start;
uniform vec3 ray_end;
varying float ray_side_pixels;
varying flat float ray_half_width_pixels;

float ray_core_half_width(vec2 viewport_size) { return max(0.35, viewport_size.y * 0.0004); }

// Expand in each eye's projected space, so distance never makes the line bulky
// or subpixel-thin. Mono projection stays anchored to the hand and the reticle.
vec4 ray_position(vec3 vertex, vec2 uv, float weight, mat4 view_model, mat4 projection,
                  vec3 eye_offset, vec2 viewport_size) {
  vec3 start = (view_model * vec4(ray_start, 1.0)).xyz;
  vec3 end = (view_model * vec4(ray_end, 1.0)).xyz + eye_offset;
  vec4 a = projection * vec4(start, 1.0);
  vec4 b = projection * vec4(end, 1.0);
  // Homogeneous direction avoids dividing by a hand origin on/behind the eye
  // plane. Let normal clipping retain the visible part of a forward-pointing ray.
  if (a.w <= 0.0 && b.w <= 0.0)
    return vec4(0.0, 0.0, 0.0, 1.0);
  vec2 along = (b.xy * a.w - a.xy * b.w) * viewport_size;
  float projected_length = length(along);
  if (projected_length < 0.000001)
    return vec4(0.0, 0.0, 0.0, 1.0);
  vec2 side = vec2(-along.y, along.x) / projected_length;
  vec3 point = (view_model * vec4(vertex, 1.0)).xyz + eye_offset * weight;
  vec4 clip = projection * vec4(point, 1.0);
  // The extra pixel is transparent antialiasing coverage, not part of the stroke width.
  float half_width = ray_core_half_width(viewport_size) + 1.0;
  clip.xy += side * (uv.x * 2.0 - 1.0) * half_width * 2.0 / viewport_size * clip.w;
  return clip;
}

float ray_opacity(vec2 uv) {
  float pixel = max(fwidth(ray_side_pixels), 0.0001);
  float edge = 1.0 - smoothstep(ray_half_width_pixels - pixel * 0.5,
                                ray_half_width_pixels + pixel * 0.5, abs(ray_side_pixels));
  float fade = smoothstep(0.0, 0.03, uv.y) * (1.0 - smoothstep(0.05, 1.0, uv.y));
  return ray_color.a * edge * fade;
}
