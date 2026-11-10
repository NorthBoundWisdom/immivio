shader_type canvas_item;

// Bakes one scene's low-frequency base into an equirect texture, once per selection.
// Stored gamma-encoded with a little dither so dark night gradients do not band in 8 bits.
#include "res://shaders/procedural_scenery.gdshaderinc"

uniform int scene = 0;
uniform bool cache_stars = false;

void fragment() {
  vec3 dir = equirect_direction(UV);
  if (cache_stars) {
    // This offscreen viewport is HDR. Keep linear light and star highlights for
    // energy-preserving mipmaps; no gamma encoding, clamping or per-frame hashes.
    COLOR = vec4(night_sky(dir, night_base(dir), star_footprint(dir)), 1.0);
  } else {
    vec3 color = clamp(scene_base(scene, dir), 0.0, 1.0);
    float dither = (unit(hash3(ivec3(ivec2(FRAGCOORD.xy), scene))) - 0.5) / 255.0;
    COLOR = vec4(pow(color, vec3(1.0 / 2.2)) + dither, 1.0);
  }
}
