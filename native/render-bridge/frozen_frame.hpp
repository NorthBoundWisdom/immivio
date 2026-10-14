#pragma once
#include "render_bridge.hpp"

namespace immivio::render {
struct FrozenFrame final {
  const EGLContext context = eglGetCurrentContext();
  const std::thread::id thread = std::this_thread::get_id();
  GLuint color = 0, alpha = 0;
  ~FrozenFrame() {
    if (context != eglGetCurrentContext() ||
        thread != std::this_thread::get_id())
      return;
    glDeleteTextures(1, &color);
    glDeleteTextures(1, &alpha);
  }
};
} // namespace immivio::render
