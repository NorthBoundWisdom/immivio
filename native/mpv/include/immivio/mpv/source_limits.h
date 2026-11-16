#pragma once
#include <cstdint>
namespace immivio {
constexpr int64_t source_max_side = 8192, source_max_pixels = 8192LL * 4320;
inline bool source_dimensions_supported(int64_t width, int64_t height) {
  return width > 0 && height > 0 && width <= source_max_side && height <= source_max_side && width * height <= source_max_pixels;
}
}
