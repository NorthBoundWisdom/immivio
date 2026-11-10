shader_type sky;

#include "res://shaders/procedural_scenery.gdshaderinc"

uniform sampler2D baked : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float energy = 1.0;

void sky() {
  vec3 dir = normalize(EYEDIR);
  // The static 8K star field and Milky Way are sampled in linear HDR. Only the
  // hill silhouette remains analytic, so its edge stays sharp at any eye size.
  COLOR = night_terrain(dir, texture(baked, equirect_uv(dir)).rgb) * energy;
}
