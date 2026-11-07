shader_type canvas_item;

// Bakes one scene's low-frequency base into an equirect texture, once per selection.
// Stored gamma-encoded with a little dither so dark night gradients do not band in 8 bits.
#include "res://shaders/procedural_scenery.gdshaderinc"

uniform int scene = 0;

void fragment() {
  vec3 color = clamp(scene_base(scene, equirect_direction(UV)), 0.0, 1.0);
  float dither = (unit(hash3(ivec3(ivec2(FRAGCOORD.xy), scene))) - 0.5) / 255.0;
  COLOR = vec4(pow(color, vec3(1.0 / 2.2)) + dither, 1.0);
}
