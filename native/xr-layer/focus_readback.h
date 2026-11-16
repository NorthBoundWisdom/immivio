#pragma once
#include <chrono>
#include <cstring>
#include <vector>

// One small asynchronous readback. Cancellation or a missed deadline discards its
// buffer instead of waiting for the GPU; no glFinish or positive fence wait exists.
struct FocusReadback {
  EGLContext owner = EGL_NO_CONTEXT;
  GLuint buffer = 0, fbo = 0;
  GLsync fence = nullptr;
  int width = 0, height = 0;
  int64_t sequence = 0, pending = 0;
  std::chrono::steady_clock::time_point started;
  void context() {
    auto current = eglGetCurrentContext();
    if (owner != current) {
      owner = current;
      buffer = fbo = 0;
      fence = nullptr;
      pending = 0;
    }
  }
  void cancel(int64_t token) {
    context();
    if (token != pending || !pending)
      return;
    if (fence)
      glDeleteSync(fence);
    if (buffer)
      glDeleteBuffers(1, &buffer);
    fence = nullptr;
    buffer = 0;
    pending = 0;
  }
  int64_t request(GLuint texture, int w, int h) {
    context();
    if (owner == EGL_NO_CONTEXT || pending || w <= 0 || h <= 0 || w > 256 || h > 128 ||
        !glIsTexture(texture))
      return 0;
    GLint old_read = 0, old_pack = 0, alignment = 0, row = 0, skip_row = 0, skip_pixel = 0;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &old_read);
    glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &old_pack);
    glGetIntegerv(GL_PACK_ALIGNMENT, &alignment);
    glGetIntegerv(GL_PACK_ROW_LENGTH, &row);
    glGetIntegerv(GL_PACK_SKIP_ROWS, &skip_row);
    glGetIntegerv(GL_PACK_SKIP_PIXELS, &skip_pixel);
    if (!fbo)
      glGenFramebuffers(1, &fbo);
    if (!buffer)
      glGenBuffers(1, &buffer);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    bool complete = glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
    if (complete) {
      glBindBuffer(GL_PIXEL_PACK_BUFFER, buffer);
      glBufferData(GL_PIXEL_PACK_BUFFER, static_cast<GLsizeiptr>(w * h * 4), nullptr,
                   GL_STREAM_READ);
      glPixelStorei(GL_PACK_ALIGNMENT, 1);
      glPixelStorei(GL_PACK_ROW_LENGTH, 0);
      glPixelStorei(GL_PACK_SKIP_ROWS, 0);
      glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
      glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
      fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
      glFlush();
    }
    glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 0, 0);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, old_read);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, old_pack);
    glPixelStorei(GL_PACK_ALIGNMENT, alignment);
    glPixelStorei(GL_PACK_ROW_LENGTH, row);
    glPixelStorei(GL_PACK_SKIP_ROWS, skip_row);
    glPixelStorei(GL_PACK_SKIP_PIXELS, skip_pixel);
    if (!complete || !fence || glGetError() != GL_NO_ERROR) {
      if (fence)
        glDeleteSync(fence);
      fence = nullptr;
      return 0;
    }
    width = w;
    height = h;
    pending = ++sequence;
    started = std::chrono::steady_clock::now();
    return pending;
  }
  std::vector<uint8_t> poll(int64_t token) {
    context();
    if (!pending || pending != token)
      return {};
    if (std::chrono::steady_clock::now() - started > std::chrono::milliseconds(200)) {
      cancel(token);
      return {};
    }
    const auto status = glClientWaitSync(fence, 0, 0);
    if (status == GL_TIMEOUT_EXPIRED)
      return {};
    if (status == GL_WAIT_FAILED) {
      cancel(token);
      return {};
    }
    GLint previous = 0;
    glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &previous);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, buffer);
    const auto size = static_cast<size_t>(width * height * 4);
    auto *data = glMapBufferRange(GL_PIXEL_PACK_BUFFER, 0, size, GL_MAP_READ_BIT);
    std::vector<uint8_t> pixels;
    if (data) {
      pixels.resize(size);
      std::memcpy(pixels.data(), data, size);
      glUnmapBuffer(GL_PIXEL_PACK_BUFFER);
    }
    glBindBuffer(GL_PIXEL_PACK_BUFFER, previous);
    glDeleteSync(fence);
    fence = nullptr;
    pending = 0;
    return pixels;
  }
};
