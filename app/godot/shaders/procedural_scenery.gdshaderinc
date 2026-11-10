// Shared procedural scenery. The night sky, including stars, is cached once in an 8K
// linear HDR texture with mipmaps. Daytime scenes bake their smooth base only.
// The hill ridge and sun disc remain analytic. Nothing depends on TIME.
// scene 0: starry night over low hills; 1: beach with sea and sand; 2: sea of clouds.

vec3 linear(vec3 srgb) { return pow(srgb, vec3(2.2)); }

uint pcg(uint v) {
  uint state = v * 747796405u + 2891336453u;
  uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
  return (word >> 22u) ^ word;
}

uint hash3(ivec3 c) { return pcg(uint(c.x) + pcg(uint(c.y) + pcg(uint(c.z)))); }

float unit(uint h) { return float(h & 65535u) / 65535.0; }

float value_noise(vec3 p) {
  ivec3 i = ivec3(floor(p));
  vec3 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = unit(hash3(i));
  float b = unit(hash3(i + ivec3(1, 0, 0)));
  float c = unit(hash3(i + ivec3(0, 1, 0)));
  float d = unit(hash3(i + ivec3(1, 1, 0)));
  float e = unit(hash3(i + ivec3(0, 0, 1)));
  float g = unit(hash3(i + ivec3(1, 0, 1)));
  float h = unit(hash3(i + ivec3(0, 1, 1)));
  float k = unit(hash3(i + ivec3(1, 1, 1)));
  return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), mix(mix(e, g, f.x), mix(h, k, f.x), f.y),
             f.z);
}

float fbm(vec3 p, int octaves) {
  float sum = 0.0;
  float amplitude = 0.5;
  for (int i = 0; i < octaves; i++) {
    sum += amplitude * value_noise(p);
    p = p * 2.03 + vec3(17.1, 3.7, 9.2);
    amplitude *= 0.5;
  }
  return sum;
}

const vec3 MILKY_WAY_NORMAL = vec3(0.4234, 0.6250, 0.6653);
const vec3 BEACH_SUN = vec3(0.2491, 0.4185, -0.8733);
const vec3 CLOUD_SEA_SUN = vec3(-0.3538, 0.2224, -0.9085);

// Equirect mapping shared by the bake and the lookup: u is azimuth, v is the polar angle.
vec3 equirect_direction(vec2 uv) {
  float azimuth = (uv.x - 0.5) * 6.2831853;
  float polar = uv.y * 3.14159265;
  return vec3(sin(azimuth) * sin(polar), cos(polar), cos(azimuth) * sin(polar));
}

vec2 equirect_uv(vec3 dir) {
  return vec2(atan(dir.x, dir.z) / 6.2831853 + 0.5, acos(clamp(dir.y, -1.0, 1.0)) / 3.14159265);
}

float milky_way_band(vec3 dir) {
  float across = dot(dir, MILKY_WAY_NORMAL);
  return exp(-across * across / 0.018);
}

vec3 night_base(vec3 dir) {
  float up = max(dir.y, 0.0);
  vec3 sky = mix(linear(vec3(0.13, 0.17, 0.30)), linear(vec3(0.025, 0.035, 0.08)), sqrt(up));
  sky += linear(vec3(0.22, 0.26, 0.34)) * exp(-up * 10.0);
  float across = dot(dir, MILKY_WAY_NORMAL);
  float band = milky_way_band(dir);
  if (band > 0.01) {
    float cloud = fbm(dir * 5.0, 4);
    float dust = smoothstep(0.45, 0.62, fbm(dir * 11.0 + 4.0, 3)) * exp(-across * across / 0.004);
    vec3 core = mix(linear(vec3(0.62, 0.70, 0.92)), linear(vec3(0.96, 0.90, 0.82)), band * band);
    sky += core * band * cloud * cloud * 1.1 * (1.0 - 0.75 * dust);
  }
  return sky;
}

vec3 day_gradient(vec3 dir, vec3 sun, vec3 zenith, vec3 horizon) {
  float up = max(dir.y, 0.0);
  vec3 sky = mix(horizon, zenith, pow(up, 0.45));
  float facing = max(dot(dir, sun), 0.0);
  return sky + linear(vec3(1.0, 0.92, 0.75)) * (pow(facing, 64.0) * 0.6 + pow(facing, 6.0) * 0.12);
}

vec3 cumulus(vec3 dir, vec3 sky, vec3 sun, float height, float cover) {
  if (dir.y <= 0.02) {
    return sky;
  }
  vec2 plane = dir.xz * (height / dir.y);
  float shape = fbm(vec3(plane * 0.0016, 0.0), 5);
  float amount = smoothstep(cover, cover + 0.18, shape) * smoothstep(0.02, 0.18, dir.y);
  float lit = 0.75 + 0.25 * max(dot(dir, sun), 0.0);
  vec3 cloud =
      mix(linear(vec3(0.70, 0.75, 0.84)), vec3(1.0), smoothstep(cover, cover + 0.35, shape)) * lit;
  return mix(sky, cloud, amount * 0.9);
}

vec3 beach_base(vec3 dir) {
  vec3 zenith = linear(vec3(0.16, 0.40, 0.80));
  vec3 horizon = linear(vec3(0.72, 0.84, 0.94));
  vec3 sky = cumulus(dir, day_gradient(dir, BEACH_SUN, zenith, horizon), BEACH_SUN, 1500.0, 0.52);
  if (dir.y >= 0.0) {
    return sky;
  }
  // Ground plane 1.6 m below the eye; the sea lies ahead (-z), the sand behind.
  float dist = min(1.6 / max(-dir.y, 1e-4), 4000.0);
  vec2 p = dir.xz * dist;
  float shore = -14.0 + 1.2 * sin(p.x * 0.07) + 0.9 * sin(p.x * 0.03);
  float sea = smoothstep(shore + 0.3, shore - 0.3, p.y);
  float haze = 1.0 - exp(-dist * 0.0025);
  vec2 ripple = vec2(value_noise(vec3(p * 0.35, 0.0)), value_noise(vec3(p * 0.35, 7.0))) - 0.5;
  float detail = 1.0 / (1.0 + dist * 0.02);
  vec3 normal = normalize(vec3(ripple.x * 0.25 * detail, 1.0, ripple.y * 0.25 * detail));
  vec3 reflected = reflect(dir, normal);
  float fresnel = 0.03 + 0.97 * pow(1.0 - max(dot(-dir, normal), 0.0), 5.0);
  vec3 water = mix(linear(vec3(0.02, 0.24, 0.32)),
                   day_gradient(reflected, BEACH_SUN, zenith, horizon), fresnel);
  water += vec3(3.0) * pow(max(dot(reflected, BEACH_SUN), 0.0), 900.0) * detail;
  float foam =
      smoothstep(2.2, 0.0, abs(p.y - shore)) * (0.55 + 0.45 * value_noise(vec3(p * 0.8, 0.0)));
  water = mix(water, vec3(0.92), foam * 0.75 * sea);
  float ripples =
      sin(p.y * 2.2 + value_noise(vec3(p * 0.25, 3.0)) * 6.0) * smoothstep(25.0, 4.0, dist);
  vec3 sand = linear(vec3(0.95, 0.89, 0.76)) * (0.94 + 0.04 * ripples);
  sand *= 1.0 - 0.25 * smoothstep(shore + 6.0, shore, p.y);
  return mix(mix(sand, water, sea), horizon, haze);
}

vec3 cloud_sea_base(vec3 dir) {
  vec3 zenith = linear(vec3(0.12, 0.34, 0.72));
  vec3 horizon = linear(vec3(0.80, 0.88, 0.96));
  vec3 sky = day_gradient(dir, CLOUD_SEA_SUN, zenith, horizon);
  // The cloud tops sit 300 m below the viewer; billows are lit from the low sun.
  float top = -0.012;
  if (dir.y >= top) {
    return sky;
  }
  float dist = min(300.0 / max(top - dir.y, 1e-4), 20000.0);
  vec2 p = dir.xz * dist;
  vec3 q = vec3(p * 0.0022, 0.0);
  float billow = smoothstep(0.25, 0.75, fbm(q, 5));
  float lit =
      smoothstep(0.25, 0.75, fbm(q + vec3(CLOUD_SEA_SUN.x, 0.0, CLOUD_SEA_SUN.z) * 0.08, 4));
  float shade = clamp((billow - lit) * 3.0 + 0.55, 0.0, 1.0);
  vec3 light = mix(linear(vec3(0.58, 0.66, 0.82)), linear(vec3(1.0, 0.97, 0.92)), shade);
  vec3 clouds = light * (0.72 + 0.4 * billow);
  float haze = 1.0 - exp(-dist * 0.00018);
  return mix(sky, mix(clouds, horizon, haze), smoothstep(top, top - 0.01, dir.y));
}

vec3 scene_base(int scene, vec3 dir) {
  if (scene == 1) {
    return beach_base(dir);
  }
  if (scene == 2) {
    return cloud_sea_base(dir);
  }
  return night_base(dir);
}

// One star per grid cell at most, kept away from cell borders so a single lookup suffices.
// Stars never shrink below ~1.2 pixels; smaller ones dim instead, so they do not shimmer.
vec3 star_layer(vec3 dir, float cells, float density, float radius, float pixel) {
  vec3 p = dir * cells;
  float size = max(radius, pixel * 1.2);
  // Every centre lies within the middle 40% of its cell. Outside this expanded
  // box the star contributes exactly zero, so do not calculate its random data.
  vec3 nearest = max(abs(fract(p) - 0.5) - 0.2, vec3(0.0));
  if (dot(nearest, nearest) >= size * size) {
    return vec3(0.0);
  }
  ivec3 cell = ivec3(floor(p));
  uint h = hash3(cell);
  if (unit(h) > density) {
    return vec3(0.0);
  }
  vec3 jitter = vec3(unit(pcg(h)), unit(pcg(h + 1u)), unit(pcg(h + 2u))) - 0.5;
  vec3 centre = vec3(cell) + 0.5 + jitter * 0.4;
  vec3 offset = p - centre;
  float distance_squared = dot(offset, offset);
  // Most candidate pixels still miss the star. Skip colour/magnitude hashes
  // and the square root for these, retaining the original footprint and AA.
  if (distance_squared >= size * size) {
    return vec3(0.0);
  }
  float core =
      smoothstep(size, size * 0.35, sqrt(distance_squared)) * (radius * radius) / (size * size);
  float magnitude = pow(unit(pcg(h + 3u)), 3.0);
  vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.88, 0.72), unit(pcg(h + 5u)));
  return tint * core * (0.5 + 4.0 * magnitude);
}

float hills(vec3 dir) {
  float azimuth = atan(dir.x, dir.z);
  return 0.035 + 0.022 * sin(azimuth * 3.0 + 1.3) + 0.014 * sin(azimuth * 7.0 + 0.4) +
         0.006 * sin(azimuth * 17.0 + 2.1);
}

vec3 star_footprint(vec3 dir) {
  return max(vec3(length(fwidth(dir * 60.0)), length(fwidth(dir * 140.0)),
                  length(fwidth(dir * 300.0))), vec3(1e-5));
}

vec3 night_sky(vec3 dir, vec3 base, vec3 pixel) {
  vec3 stars = star_layer(dir, 60.0, 0.30, 0.07, pixel.x) * 1.6 +
               star_layer(dir, 140.0, 0.45, 0.07, pixel.y) +
               star_layer(dir, 300.0, 0.6, 0.08, pixel.z) * (0.5 + 1.5 * milky_way_band(dir));
  return base + stars * smoothstep(0.0, 0.08, dir.y);
}

vec3 night_terrain(vec3 dir, vec3 sky) {
  float ridge = dir.y - hills(dir);
  float edge = max(fwidth(ridge), 1e-5);
  vec3 land = mix(linear(vec3(0.07, 0.08, 0.11)), linear(vec3(0.025, 0.028, 0.04)),
                  clamp(-dir.y * 3.0, 0.0, 1.0));
  return mix(sky, land, smoothstep(edge, -edge, ridge));
}

// Per-pixel details composed over the baked base.
vec3 scene_detail(int scene, vec3 dir, vec3 base) {
  if (scene == 0) {
    // Derivatives must be evaluated before any per-pixel early exit, including
    // the terrain mask, so neighbouring fragments retain the same AA footprint.
    vec3 pixel = star_footprint(dir);
    float ridge = dir.y - hills(dir);
    float edge = max(fwidth(ridge), 1e-5);
    vec3 land = mix(linear(vec3(0.07, 0.08, 0.11)), linear(vec3(0.025, 0.028, 0.04)),
                    clamp(-dir.y * 3.0, 0.0, 1.0));
    // Preserve the antialiased ridge, but do not shade stars behind solid land.
    if (ridge <= -edge) {
      return land;
    }
    vec3 sky = night_sky(dir, base, pixel);
    return mix(sky, land, smoothstep(edge, -edge, ridge));
  }
  vec3 sun = scene == 1 ? BEACH_SUN : CLOUD_SEA_SUN;
  float facing = dot(dir, sun);
  float disc_edge = fwidth(facing) * 1.5 + 1e-5;
  return base + vec3(6.0, 5.6, 4.8) * smoothstep(0.99955 - disc_edge, 0.99955 + disc_edge, facing);
}
