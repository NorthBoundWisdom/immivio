#include "render_bridge.hpp"
#include "frozen_frame.hpp"
#include <limits>
#include <memory>
#include <mutex>
#include <unordered_map>

using namespace immivio::render;
namespace {
std::mutex registry_mutex;
std::unordered_map<jlong, std::unique_ptr<Bridge>> registry;
std::unordered_map<jlong, std::unique_ptr<FrozenFrame>> frozen_frames;
jlong sequence = 0, token_sequence = 0;
Bridge &find(jlong handle) {
  const auto it = registry.find(handle);
  if (it == registry.end())
    throw std::runtime_error("Render bridge closed/unknown handle");
  it->second->current();
  return *it->second;
}
void error(JNIEnv *env, const char *message) {
  if (!env->ExceptionCheck()) {
    const auto type = env->FindClass("java/lang/IllegalStateException");
    if (type)
      env->ThrowNew(type, message);
  }
}
void *direct_buffer(JNIEnv *env, jobject buffer, size_t bytes, bool writable) {
  if (!buffer ||
      env->GetDirectBufferCapacity(buffer) != static_cast<jlong>(bytes))
    throw std::runtime_error(
        "Render bridge exact-size direct mask buffer required");
  auto *address = env->GetDirectBufferAddress(buffer);
  if (!address)
    throw std::runtime_error("Render bridge direct buffer address invalid");
  const auto type = env->GetObjectClass(buffer);
  const auto method =
      type ? env->GetMethodID(type, "isReadOnly", "()Z") : nullptr;
  const bool readonly =
      method && env->CallBooleanMethod(buffer, method) == JNI_TRUE;
  if (type)
    env->DeleteLocalRef(type);
  if (!method || env->ExceptionCheck() || (writable && readonly))
    throw std::runtime_error("Render bridge direct output must be writable");
  return address;
}
} // namespace

extern "C" JNIEXPORT jlongArray JNICALL
Java_org_vrpassthroughplayer_plugin_RenderBridgeNative_freezePair(JNIEnv *env,
                                                                  jclass,
                                                                  jlong id,
                                                                  jlong token) {
  try {
    std::lock_guard<std::mutex> guard(registry_mutex);
    auto &b = find(id);
    auto &slot = b.find(token);
    if (slot.phase != Phase::held || !slot.alpha_valid ||
        !frozen_frames.empty())
      throw std::runtime_error("Freeze requires one complete held display pair "
                               "and no previous snapshot");
    const int width = b.width;
    const auto started = std::chrono::steady_clock::now();
    State state;
    auto frozen = std::make_unique<FrozenFrame>();
    image(frozen->color, width, b.height);
    image(frozen->alpha, b.mask_width * 2, b.mask_height, GL_R8);
    glBindFramebuffer(GL_FRAMEBUFFER, b.fbo);
    glBindVertexArray(b.vao);
    glActiveTexture(GL_TEXTURE0);
    auto copy = [&](GLuint source, GLenum target, GLuint destination, int w,
                    int h, GLuint prog) {
      glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                             GL_TEXTURE_2D, destination, 0);
      if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
        throw std::runtime_error("Freeze framebuffer incomplete");
      glViewport(0, 0, w, h);
      glUseProgram(prog);
      glBindTexture(target, source);
      glUniform1i(glGetUniformLocation(prog, "source"), 0);
      glDrawArrays(GL_TRIANGLES, 0, 3);
      check_gl("Freeze frame GPU copy");
    };
    copy(slot.source(), GL_TEXTURE_2D, frozen->color, width, b.height,
         b.copy_2d);
    copy(slot.alpha, GL_TEXTURE_2D, frozen->alpha, b.mask_width * 2,
         b.mask_height, b.copy_2d);
    // A seek may flush MediaCodec on a different context/thread as soon as
    // this callback returns. Complete this one transition copy before it.
    glFinish();
    check_gl("Freeze frame GPU completion");
    if (sequence == std::numeric_limits<jlong>::max())
      throw std::runtime_error("Frozen handle space exhausted");
    const jlong handle = ++sequence;
    const jlong values[] = {
        handle,
        frozen->color,
        frozen->alpha,
        width,
        b.height,
        std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now() - started)
            .count()};
    auto result = env->NewLongArray(6);
    if (!result)
      return nullptr;
    env->SetLongArrayRegion(result, 0, 6, values);
    if (env->ExceptionCheck())
      return nullptr;
    frozen_frames.emplace(handle, std::move(frozen));
    return result;
  } catch (const std::exception &e) {
    error(env, e.what());
    return nullptr;
  }
}
extern "C" JNIEXPORT void JNICALL
Java_org_vrpassthroughplayer_plugin_RenderBridgeNative_releaseFrozen(JNIEnv *,
                                                                     jclass,
                                                                     jlong id) {
  std::lock_guard<std::mutex> guard(registry_mutex);
  // After the caller detached its wrappers/last draw, GL deletion preserves
  // in-flight GPU uses. A lost context's names must never be deleted in a new
  // one.
  frozen_frames.erase(id);
}

extern "C" JNIEXPORT jlong JNICALL
Java_org_vrpassthroughplayer_plugin_RenderBridgeNative_createLayout(
    JNIEnv *env, jclass, jint w, jint h, jint iw, jint ih, jint layout) {
  try {
    if (w < 1 || h < 1 || w > 8192 || h > 8192 ||
        static_cast<int64_t>(w) * h > 8192LL * 4320 || iw < 1 || ih < 1 ||
        iw > 512 || ih > 512 || layout < 0 || layout > 2 ||
        (layout == 1 && w % 2 != 0) || (layout == 2 && h % 2 != 0))
      throw std::runtime_error("Render bridge dimensions unsupported");
    std::lock_guard<std::mutex> guard(registry_mutex);
    if (registry.size() >= 2 || sequence == std::numeric_limits<jlong>::max())
      throw std::runtime_error("Render bridge instance capacity exhausted");
    auto bridge = std::make_unique<Bridge>(w, h, iw, ih);
    bridge->allocate();
    const auto id = ++sequence;
    registry.emplace(id, std::move(bridge));
    return id;
  } catch (const std::exception &e) {
    error(env, e.what());
    return 0;
  }
}
extern "C" JNIEXPORT jboolean JNICALL
Java_org_vrpassthroughplayer_plugin_RenderBridgeNative_ready(JNIEnv *env,
                                                             jclass, jlong id,
                                                             jlong token) {
  try {
    std::lock_guard<std::mutex> guard(registry_mutex);
    auto &bridge = find(id);
    return bridge.poll(bridge.find(token)) ? JNI_TRUE : JNI_FALSE;
  } catch (const std::exception &e) {
    error(env, e.what());
    return JNI_FALSE;
  }
}
extern "C" JNIEXPORT jlong JNICALL
Java_org_vrpassthroughplayer_plugin_RenderBridgeNative_captureTexture(
    JNIEnv *env, jclass, jlong id, jint texture) {
  try {
    if (texture <= 0)
      throw std::runtime_error("Shared MPV texture name invalid");
    std::lock_guard<std::mutex> guard(registry_mutex);
    if (token_sequence == std::numeric_limits<jlong>::max())
      throw std::runtime_error("Render bridge lease space exhausted");
    return find(id).capture_texture(static_cast<GLuint>(texture),
                                    ++token_sequence, false);
  } catch (const std::exception &e) {
    error(env, e.what());
    return 0;
  }
}
// EGLImage of a held decoder-buffer slot (0 for copied/borrowed RGBA colors).
// Borrowed color: captures keep the producer texture (no full-resolution copy).
// The caller must hold the producer lease until retired() reports the slot
// free.
extern "C" JNIEXPORT jboolean JNICALL
Java_org_vrpassthroughplayer_plugin_RenderBridgeNative_enableBorrowedColor(
    JNIEnv *env, jclass, jlong id) {
  try {
    std::lock_guard<std::mutex> guard(registry_mutex);
    find(id).borrow = true;
    return JNI_TRUE;
  } catch (const std::exception &e) {
    error(env, e.what());
    return JNI_FALSE;
  }
}
extern "C" JNIEXPORT jint JNICALL
Java_org_vrpassthroughplayer_plugin_RenderBridgeNative_texture(JNIEnv *env,
                                                               jclass, jlong id,
                                                               jlong token) {
  try {
    std::lock_guard<std::mutex> guard(registry_mutex);
    auto &slot = find(id).find(token);
    if (slot.phase != Phase::held)
      throw std::runtime_error("Render bridge color not ready");
    return slot.source();
  } catch (const std::exception &e) {
    error(env, e.what());
    return 0;
  }
}
extern "C" JNIEXPORT jlong JNICALL
Java_org_vrpassthroughplayer_plugin_RenderBridgeNative_captureOpaqueTexture(
    JNIEnv *env, jclass, jlong id, jint texture) {
  try {
    if (texture <= 0)
      throw std::runtime_error("Shared MPV texture name invalid");
    std::lock_guard<std::mutex> guard(registry_mutex);
    if (token_sequence == std::numeric_limits<jlong>::max())
      throw std::runtime_error("Render bridge lease space exhausted");
    return find(id).capture_texture(static_cast<GLuint>(texture),
                                    ++token_sequence, true);
  } catch (const std::exception &e) {
    error(env, e.what());
    return 0;
  }
}
extern "C" JNIEXPORT jstring JNICALL
Java_org_vrpassthroughplayer_plugin_RenderBridgeNative_stats(JNIEnv *env,
                                                             jclass, jlong id) {
  try {
    std::lock_guard<std::mutex> guard(registry_mutex);
    auto &b = find(id);
    std::array<int, 4> phases{};
    uint64_t color_textures = 0;
    for (const auto &s : b.slots) {
      phases[static_cast<size_t>(s.phase)]++;
      color_textures += s.color != 0;
    }
    auto json =
        "{\"copies\":" + std::to_string(b.copies) +
        ",\"opaque_copies\":" + std::to_string(b.opaque_copies) +
        ",\"opaque_state_bypasses\":" +
        std::to_string(b.opaque_state_bypasses) +
        ",\"opaque_state_fast\":" + (b.opaque_state_fast ? "true" : "false") +
        ",\"capture_state_saves\":" + std::to_string(b.capture_state_saves) +
        ",\"capture_calls\":" + std::to_string(b.capture_calls) +
        ",\"capture_cpu_us\":" + std::to_string(b.capture_cpu_us) +
        ",\"capture_cpu_max_us\":" + std::to_string(b.capture_cpu_max_us) +
        ",\"owner_gl_errors\":" + std::to_string(owner_gl_errors) +
        ",\"owner_gl_last_error\":" + std::to_string(owner_gl_last_error) +
        ",\"borrow_color\":" + (b.borrow ? "true" : "false") +
        ",\"color_texture_count\":" + std::to_string(color_textures) +
        ",\"color_texture_bytes\":" +
        std::to_string(color_textures * b.width * b.height * 4) +
        ",\"opaque_initial_uploads\":" + std::to_string(b.opaque_uploads) +
        ",\"regular_alpha_uploads\":" + std::to_string(b.mask_refreshes) +
        ",\"input_stages\":0,\"zero_copy\":false,\"zero_copy_commits\":0,"
        "\"decoder_captures\":0,\"warp_frames\":0,\"warp_maps\":0" +
        ",\"copy_pending_polls\":" + std::to_string(b.copy_pending_polls) +
        ",\"retire_pending_polls\":" + std::to_string(b.retire_pending_polls) +
        ",\"slot_exhaustions\":" + std::to_string(b.slot_exhaustions) +
        ",\"borrowed_captures\":" + std::to_string(b.borrows) +
        ",\"free_slots\":" + std::to_string(phases[0]) +
        ",\"copying_slots\":" + std::to_string(phases[1]) +
        ",\"held_slots\":" + std::to_string(phases[2]) +
        ",\"retiring_slots\":" + std::to_string(phases[3]) + "}";
    return env->NewStringUTF(json.c_str());
  } catch (const std::exception &e) {
    error(env, e.what());
    return nullptr;
  }
}
extern "C" JNIEXPORT void JNICALL
Java_org_vrpassthroughplayer_plugin_RenderBridgeNative_retire(JNIEnv *env,
                                                              jclass, jlong id,
                                                              jlong token) {
  try {
    std::lock_guard<std::mutex> guard(registry_mutex);
    find(id).retire(token);
  } catch (const std::exception &e) {
    error(env, e.what());
  }
}
extern "C" JNIEXPORT jboolean JNICALL
Java_org_vrpassthroughplayer_plugin_RenderBridgeNative_retired(JNIEnv *env,
                                                               jclass, jlong id,
                                                               jlong token) {
  try {
    std::lock_guard<std::mutex> guard(registry_mutex);
    auto &bridge = find(id);
    for (auto &slot : bridge.slots)
      if (token > 0 && slot.token == token) {
        if (slot.phase == Phase::retiring)
          bridge.poll(slot);
        return slot.phase == Phase::free ? JNI_TRUE : JNI_FALSE;
      }
    throw std::runtime_error("Render bridge retirement token unknown");
  } catch (const std::exception &e) {
    error(env, e.what());
    return JNI_FALSE;
  }
}
extern "C" JNIEXPORT jboolean JNICALL
Java_org_vrpassthroughplayer_plugin_RenderBridgeNative_alphaReady(JNIEnv *env,
                                                                  jclass,
                                                                  jlong id,
                                                                  jlong token) {
  try {
    std::lock_guard<std::mutex> guard(registry_mutex);
    auto &bridge = find(id);
    return bridge.alpha_ready(bridge.find(token)) ? JNI_TRUE : JNI_FALSE;
  } catch (const std::exception &e) {
    error(env, e.what());
    return JNI_FALSE;
  }
}
extern "C" JNIEXPORT jint JNICALL
Java_org_vrpassthroughplayer_plugin_RenderBridgeNative_alphaTexture(
    JNIEnv *env, jclass, jlong id, jlong token) {
  try {
    std::lock_guard<std::mutex> guard(registry_mutex);
    auto &slot = find(id).find(token);
    if (slot.phase != Phase::held || !slot.alpha_valid)
      throw std::runtime_error("Alpha texture not ready");
    return slot.alpha;
  } catch (const std::exception &e) {
    error(env, e.what());
    return 0;
  }
}
extern "C" JNIEXPORT jboolean JNICALL
Java_org_vrpassthroughplayer_plugin_RenderBridgeNative_readAlpha(
    JNIEnv *env, jclass, jlong id, jlong token, jobject output) {
  try {
    std::lock_guard<std::mutex> guard(registry_mutex);
    auto &bridge = find(id);
    auto &slot = bridge.find(token);
    if (slot.phase != Phase::held || !slot.alpha_valid)
      return JNI_FALSE;
    const size_t pixels =
        static_cast<size_t>(bridge.mask_width) * bridge.mask_height * 2;
    auto *destination =
        static_cast<unsigned char *>(direct_buffer(env, output, pixels, true));
    State state;
    bridge.target(slot.alpha, bridge.mask_width * 2, bridge.mask_height);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    // ES3 guarantees RGBA/UNSIGNED_BYTE readback for normalized attachments.
    std::vector<unsigned char> rgba(pixels * 4);
    glReadPixels(0, 0, bridge.mask_width * 2, bridge.mask_height, GL_RGBA,
                 GL_UNSIGNED_BYTE, rgba.data());
    if (glGetError() != GL_NO_ERROR)
      throw std::runtime_error("Alpha readback GL error");
    for (size_t i = 0; i < pixels; ++i)
      destination[i] = rgba[i * 4];
    return JNI_TRUE;
  } catch (const std::exception &e) {
    error(env, e.what());
    return JNI_FALSE;
  }
}
extern "C" JNIEXPORT void JNICALL
Java_org_vrpassthroughplayer_plugin_RenderBridgeNative_close(JNIEnv *, jclass,
                                                             jlong id) {
  std::lock_guard<std::mutex> guard(registry_mutex);
  registry.erase(id);
}
extern "C" JNIEXPORT void JNICALL
Java_org_vrpassthroughplayer_plugin_RenderBridgeNative_abandon(JNIEnv *, jclass,
                                                               jlong id) {
  std::lock_guard<std::mutex> guard(registry_mutex);
  const auto it = registry.find(id);
  if (it != registry.end()) {
    it->second->abandoned = true;
    registry.erase(it);
  }
}
