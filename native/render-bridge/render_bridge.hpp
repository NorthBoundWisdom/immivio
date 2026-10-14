#pragma once
#include "frame_slot.hpp"
#include "gpu_texture.hpp"
#include <sys/system_properties.h>
#include <thread>
#include <vector>

namespace immivio::render {
struct Bridge final {
  const EGLContext context = eglGetCurrentContext();
  const std::thread::id thread = std::this_thread::get_id();
  const int width, height, mask_width, mask_height;
  bool abandoned = false, borrow = false, opaque_state_fast = true;
  GLuint copy_2d = 0, vao = 0, fbo = 0;
  // Keep the existing capacity until device measurements establish a new limit.
  std::array<Slot, 7> slots;
  uint64_t copies = 0, opaque_copies = 0, opaque_uploads = 0,
           mask_refreshes = 0;
  uint64_t copy_pending_polls = 0, retire_pending_polls = 0,
           slot_exhaustions = 0, borrows = 0;
  uint64_t opaque_state_bypasses = 0, capture_state_saves = 0;
  uint64_t capture_calls = 0, capture_cpu_us = 0, capture_cpu_max_us = 0;
  Bridge(int w, int h, int mw, int mh)
      : width(w), height(h), mask_width(mw), mask_height(mh) {}
  void current() const {
    if (context == EGL_NO_CONTEXT || context != eglGetCurrentContext() ||
        thread != std::this_thread::get_id())
      throw std::runtime_error(
          "Render bridge requires its owner GL thread/context");
  }
  void allocate() {
    current();
    State state;
#ifndef NDEBUG
    char fast[PROP_VALUE_MAX] = {};
    if (__system_property_get("debug.vrpp.bridge.opaque_fast", fast) > 0)
      opaque_state_fast = std::string(fast) != "no";
#endif
    GLint maximum = 0;
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maximum);
    if (width > maximum || height > maximum)
      throw std::runtime_error("Source exceeds GL texture limit");
    copy_2d = program(copy_2d_fragment);
    glGenVertexArrays(1, &vao);
    glGenFramebuffers(1, &fbo);
    check_gl("Render bridge allocation");
  }
  ~Bridge() {
    if (abandoned || context != eglGetCurrentContext() ||
        thread != std::this_thread::get_id())
      return;
    for (auto &slot : slots) {
      if (slot.fence)
        glDeleteSync(slot.fence);
      glDeleteTextures(1, &slot.color);
      glDeleteTextures(1, &slot.alpha);
    }
    glDeleteFramebuffers(1, &fbo);
    glDeleteVertexArrays(1, &vao);
    if (copy_2d)
      glDeleteProgram(copy_2d);
  }
  void target(GLuint texture, int w, int h) {
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                           texture, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
      throw std::runtime_error("Render bridge framebuffer incomplete");
    glViewport(0, 0, w, h);
    glBindVertexArray(vao);
  }
  bool poll(Slot &slot) {
    if (!slot.fence)
      return slot.phase == Phase::held;
    const auto result = glClientWaitSync(slot.fence, 0, 0);
    if (result == GL_WAIT_FAILED)
      throw std::runtime_error("Render bridge fence failed");
    if (result != GL_ALREADY_SIGNALED && result != GL_CONDITION_SATISFIED) {
      if (slot.phase == Phase::copying)
        copy_pending_polls++;
      else if (slot.phase == Phase::retiring)
        retire_pending_polls++;
      return false;
    }
    glDeleteSync(slot.fence);
    slot.fence = nullptr;
    slot.phase = slot.phase == Phase::copying ? Phase::held : Phase::free;
    if (slot.phase == Phase::free)
      slot.borrowed = 0;
    if (slot.phase == Phase::held)
      slot.alpha_valid = true;
    return slot.phase == Phase::held;
  }
  Slot &find(jlong token) {
    for (auto &slot : slots)
      if (token > 0 && slot.token == token && slot.phase != Phase::free)
        return slot;
    throw std::runtime_error("Render bridge lease stale/unknown");
  }
  jlong capture_texture(GLuint source, jlong token, bool cache_mask) {
    current();
    CaptureTiming timing(capture_calls, capture_cpu_us, capture_cpu_max_us);
    isolate_owner_errors();
    if (!source || !glIsTexture(source))
      throw std::runtime_error("Shared MPV color texture unavailable");
    Slot *free = nullptr;
    for (auto &slot : slots) {
      if (slot.phase == Phase::free && !free)
        free = &slot;
    }
    if (!free) {
      slot_exhaustions++;
      return 0;
    }
    if (opaque_state_fast && borrow && cache_mask && free->opaque_cached) {
      check_gl("Borrowed opaque handoff");
      // No texture upload, draw, framebuffer or pixel-store mutation: both the
      // immutable producer color and this slot's cached opaque mask are already
      // available. Avoid dozens of synchronous GL state queries/restores on the
      // Godot owner thread. The caller has acquired a signalled producer fence,
      // and retirement has completed every earlier use of this mask. With no
      // GPU commands to submit, another capture fence would only delay handoff.
      // Producer leases and retirement fences still apply.
      free->alpha_valid = true;
      free->borrowed = source;
      ++borrows;
      ++opaque_copies;
      ++opaque_state_bypasses;
      free->token = token;
      free->phase = Phase::held;
      return token;
    }
    State state;
    ++capture_state_saves;
    free->alpha_valid = false;
    if (borrow) {
      // The owner keeps the producer lease until this slot retires; staging
      // samples it directly.
      free->borrowed = source;
      borrows++;
    } else {
      free->borrowed = 0;
      if (!free->color)
        image(free->color, width, height);
      target(free->color, width, height);
      glUseProgram(copy_2d);
      glBindTexture(GL_TEXTURE_2D, source);
      glUniform1i(glGetUniformLocation(copy_2d, "source"), 0);
      // The producer lease lasts until a consumer-context fence after this
      // copy. MPV FLIP_Y=0 already stores source top rows at GL y=0.
      glDrawArrays(GL_TRIANGLES, 0, 3);
      copies++;
    }
    {
      if (!cache_mask || !free->opaque_cached) {
        if (!free->alpha)
          image(free->alpha, mask_width * 2, mask_height, GL_R8);
        std::vector<unsigned char> mask(
            static_cast<size_t>(mask_width) * mask_height * 2, 255);
        glBindTexture(GL_TEXTURE_2D, free->alpha);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, mask_width * 2, mask_height,
                        GL_RED, GL_UNSIGNED_BYTE, mask.data());
        free->opaque_cached = true;
        if (cache_mask)
          opaque_uploads++;
        else
          mask_refreshes++;
      }
      opaque_copies++;
    }
    check_gl("Render bridge color/mask capture");
    free->fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
    if (!free->fence)
      throw std::runtime_error("Render bridge copy fence unavailable");
    free->token = token;
    free->phase = Phase::copying;
    glFlush();
    return token;
  }
  bool alpha_ready(const Slot &slot) const {
    return slot.phase == Phase::held && slot.alpha_valid;
  }
  void retire(jlong token) {
    current();
    auto &slot = find(token);
    if (slot.phase == Phase::retiring)
      return;
    if (slot.fence)
      glDeleteSync(slot.fence);
    slot.alpha_valid = false;
    slot.fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
    if (!slot.fence)
      throw std::runtime_error("Render bridge release fence unavailable");
    slot.phase = Phase::retiring;
    glFlush();
  }
};
} // namespace immivio::render
