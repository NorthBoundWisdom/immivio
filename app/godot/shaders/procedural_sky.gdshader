shader_type sky;

// Procedural scenery: the baked low-frequency base plus per-pixel sharp details.
#include "res://shaders/procedural_scenery.gdshaderinc"

uniform int scene = 0;
uniform float energy = 1.0;
uniform sampler2D baked : filter_linear, repeat_enable;

void sky() {
  vec3 dir = normalize(EYEDIR);
  vec3 base = pow(texture(baked, equirect_uv(dir)).rgb, vec3(2.2));
  COLOR = scene_detail(scene, dir, base) * energy;
}
