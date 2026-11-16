// Runs the production GLES and lifecycle code with a bounded fake XR swapchain.
// This checks GPU behavior, not headset compositor acceptance.
#include "../../native/xr-layer/video_layer.cpp"
#include <cassert>
#include <iostream>
#include <map>
#include <cstring>
namespace {
std::map<XrSwapchain, std::vector<GLuint>> chains;
uintptr_t next_chain = 10;
int acquires = 0, releases = 0, destroys = 0;
bool timeout_next = false;
bool reject_surface = false, reject_reference = false;
int global_releases = 0, local_releases = 0;
XrResult XRAPI_PTR fake_surface(XrSession, const XrSwapchainCreateInfo *, XrSwapchain *out,
                                jobject *surface) {
  *out = reinterpret_cast<XrSwapchain>(++next_chain);
  chains[*out] = {};
  *surface = reinterpret_cast<jobject>(1);
  return reject_surface ? XR_ERROR_RUNTIME_FAILURE : XR_SUCCESS;
}
jobject JNICALL keep_reference(JNIEnv *, jobject value) {
  return reject_reference ? nullptr : value;
}
void JNICALL drop_global(JNIEnv *, jobject) { ++global_releases; }
void JNICALL drop_local(JNIEnv *, jobject) { ++local_releases; }
XrResult XRAPI_PTR fake_create(XrSession, const XrSwapchainCreateInfo *info, XrSwapchain *out) {
  auto handle = reinterpret_cast<XrSwapchain>(++next_chain);
  std::vector<GLuint> textures(3);
  glGenTextures(3, textures.data());
  GLint old = 0;
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &old);
  for (auto texture : textures) {
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexStorage2D(GL_TEXTURE_2D, 1, info->format, info->width, info->height);
  }
  glBindTexture(GL_TEXTURE_2D, old);
  chains[handle] = textures;
  *out = handle;
  return XR_SUCCESS;
}
XrResult XRAPI_PTR fake_destroy(XrSwapchain handle) {
  auto it = chains.find(handle);
  if (it != chains.end()) {
    glDeleteTextures(it->second.size(), it->second.data());
    chains.erase(it);
    ++destroys;
  }
  return XR_SUCCESS;
}
XrResult XRAPI_PTR fake_images(XrSwapchain handle, uint32_t capacity, uint32_t *count,
                               XrSwapchainImageBaseHeader *images) {
  *count = chains.at(handle).size();
  if (capacity) {
    auto *gl = reinterpret_cast<XrSwapchainImageOpenGLESKHR *>(images);
    for (uint32_t i = 0; i < *count; ++i)
      gl[i].image = chains.at(handle)[i];
  }
  return XR_SUCCESS;
}
XrResult XRAPI_PTR fake_acquire(XrSwapchain, const XrSwapchainImageAcquireInfo *, uint32_t *index) {
  ++acquires;
  *index = 0;
  return XR_SUCCESS;
}
XrResult XRAPI_PTR fake_wait(XrSwapchain, const XrSwapchainImageWaitInfo *wait) {
  assert(wait->timeout == 0);
  if (timeout_next) {
    timeout_next = false;
    return XR_TIMEOUT_EXPIRED;
  }
  return XR_SUCCESS;
}
XrResult XRAPI_PTR fake_release(XrSwapchain, const XrSwapchainImageReleaseInfo *) {
  ++releases;
  return XR_SUCCESS;
}
jsize JNICALL array_length(JNIEnv *, jarray array) {
  return reinterpret_cast<std::vector<float> *>(array)->size();
}
void JNICALL array_region(JNIEnv *, jfloatArray array, jsize from, jsize count, jfloat *out) {
  auto &values = *reinterpret_cast<std::vector<float> *>(array);
  std::memcpy(out, values.data() + from, count * sizeof(float));
}
jboolean JNICALL has_exception(JNIEnv *) { return JNI_TRUE; }
void pixels(GLuint texture, int w, int h, std::vector<uint8_t> &data) {
  GLuint read = 0;
  glGenFramebuffers(1, &read);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, read);
  glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
  glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glPixelStorei(GL_PACK_ROW_LENGTH, 0);
  glPixelStorei(GL_PACK_SKIP_ROWS, 0);
  glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
  data.resize(w * h * 4);
  glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, data.data());
  glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
  glDeleteFramebuffers(1, &read);
}
} // namespace
int main() {
  EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  assert(eglInitialize(display, nullptr, nullptr));
  const EGLint attributes[] = {EGL_SURFACE_TYPE,
                               EGL_PBUFFER_BIT,
                               EGL_RENDERABLE_TYPE,
                               EGL_OPENGL_ES3_BIT,
                               EGL_RED_SIZE,
                               8,
                               EGL_GREEN_SIZE,
                               8,
                               EGL_BLUE_SIZE,
                               8,
                               EGL_ALPHA_SIZE,
                               8,
                               EGL_NONE};
  EGLConfig config;
  EGLint count;
  assert(eglChooseConfig(display, attributes, &config, 1, &count) && count);
  const EGLint version[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
  auto context = eglCreateContext(display, config, EGL_NO_CONTEXT, version);
  const EGLint dimensions[] = {EGL_WIDTH, 4, EGL_HEIGHT, 4, EGL_NONE};
  auto surface = eglCreatePbufferSurface(display, config, dimensions);
  assert(eglMakeCurrent(display, surface, surface, context));
  state.session = reinterpret_cast<XrSession>(1);
  state.space = reinterpret_cast<XrSpace>(1);
  state.max_width = 8192;
  state.max_height = 8192;
  state.max_layers = 16;
  state.srgb = true;
  state.create = fake_create;
  state.destroy = fake_destroy;
  state.enumerate = fake_images;
  state.acquire = fake_acquire;
  state.wait = fake_wait;
  state.release = fake_release;
  assert(create_picture(64, 32));
  auto chain = state.picture.handle;
  assert(create_picture(64, 32) && state.picture.handle == chain);
  timeout_next = true;
  assert(!acquire_picture());
  assert(acquires == 1);
  assert(acquire_picture());
  assert(acquires == 1);
  GLuint source = 0;
  glGenTextures(1, &source);
  glBindTexture(GL_TEXTURE_2D, source);
  std::vector<uint8_t> data(64 * 32 * 4);
  for (int y = 0; y < 32; ++y)
    for (int x = 0; x < 64; ++x) {
      auto i = (y * 64 + x) * 4;
      data[i] = x < 32 ? 128 : 64;
      data[i + 1] = y < 16 ? 180 : 32;
      data[i + 2] = 90;
      data[i + 3] = 255;
    }
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 64, 32, 0, GL_RGBA, GL_UNSIGNED_BYTE, data.data());
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  GLuint sampler = 0;
  glGenSamplers(1, &sampler);
  glBindSampler(0, sampler);
  glEnable(GL_BLEND);
  glEnable(GL_SCISSOR_TEST);
  glViewport(1, 1, 3, 3);
  if (GlState::srgb_control())
    glDisable(GlState::kSrgb);
  float params[10] = {0, 0, 180, 3.14159265f, 3.14159265f, 64, 32, 1, 1, 0};
  assert(draw_picture(source, false, params));
  release_picture();
  assert(releases == 1);
  GLint current_sampler = 0, viewport[4];
  glGetIntegerv(GL_SAMPLER_BINDING, &current_sampler);
  glGetIntegerv(GL_VIEWPORT, viewport);
  assert(current_sampler == int(sampler) && viewport[0] == 1 && glIsEnabled(GL_BLEND) &&
         glIsEnabled(GL_SCISSOR_TEST));
  if (GlState::srgb_control())
    assert(!glIsEnabled(GlState::kSrgb));
  std::vector<uint8_t> result;
  pixels(chains.at(chain)[0], 64, 32, result);
  for (size_t i = 0; i < data.size(); ++i)
    assert(std::abs(int(result[i]) - data[i]) <= 2);
  // A flipped GL upload retains both packed eye halves and the source's encoded color.
  assert(acquire_picture());
  params[9] = 1;
  assert(draw_picture(source, false, params));
  release_picture();
  pixels(chains.at(chain)[0], 64, 32, result);
  assert(result[1] == 32 && result[(31 * 64) * 4 + 1] == 180);
  // The same shader rectifies a fisheye without mixing stereo eye textures.
  assert(create_picture(64, 32));
  assert(acquire_picture());
  params[0] = 1;
  params[9] = 0;
  assert(draw_picture(source, true, params));
  release_picture();
  pixels(chains.at(chain)[0], 64, 32, result);
  assert(std::abs(int(result[(16 * 64 + 16) * 4]) - 128) <= 2 &&
         std::abs(int(result[(16 * 64 + 48) * 4]) - 64) <= 2);
  // Nonblocking PBO readback has one owner, preserves pack state, and cancels obsolete requests.
  FocusReadback readback;
  glPixelStorei(GL_PACK_ALIGNMENT, 8);
  glPixelStorei(GL_PACK_ROW_LENGTH, 80);
  glPixelStorei(GL_PACK_SKIP_ROWS, 1);
  glPixelStorei(GL_PACK_SKIP_PIXELS, 2);
  auto token = readback.request(chains.at(state.picture.handle)[0], 64, 32);
  assert(token > 0);
  assert(readback.request(source, 64, 32) == 0);
  GLint alignment = 0, row = 0;
  glGetIntegerv(GL_PACK_ALIGNMENT, &alignment);
  glGetIntegerv(GL_PACK_ROW_LENGTH, &row);
  assert(alignment == 8 && row == 80);
  glFinish();
  auto bytes = readback.poll(token);
  assert(bytes.size() == 64 * 32 * 4);
  assert(readback.poll(token).empty());
  auto cancelled = readback.request(source, 64, 32);
  readback.cancel(cancelled);
  assert(readback.poll(cancelled).empty());
  auto newer = readback.request(source, 64, 32);
  assert(newer > cancelled);
  readback.cancel(newer);
  JNINativeInterface functions{};
  functions.GetArrayLength = array_length;
  functions.GetFloatArrayRegion = array_region;
  functions.ExceptionCheck = has_exception;
  functions.NewGlobalRef = keep_reference;
  functions.DeleteGlobalRef = drop_global;
  functions.DeleteLocalRef = drop_local;
  JNIEnv env{&functions};
  state.surface_chain = reinterpret_cast<XrSwapchain>(2);
  state.surface_width = 64;
  state.surface_height = 32;
  std::vector<float> layers(56);
  for (int i = 0; i < 2; ++i) {
    float *p = layers.data() + i * 28;
    p[1] = i + 1;
    p[8] = 1;
    p[9] = i * 32;
    p[11] = 32;
    p[12] = 32;
    p[13] = 2;
    p[14] = 1;
    p[17] = -1;
    p[20] = p[21] = p[22] = 1;
  }
  auto array = reinterpret_cast<jfloatArray>(&layers);
  assert(Java_org_vrpassthroughplayer_plugin_VideoLayerNative_setLayers(&env, nullptr, 2, array));
  assert(state.layers[1].quad.subImage.imageRect.offset.x == 32);
  // Late cleanup of the old picture route must not clear the active decoder Surface.
  drop_picture();
  assert(state.count == 2);
  assert(create_picture(64, 32));
  // Conversely, releasing an old decoder Surface must not clear picture descriptors.
  for (int i = 0; i < 2; ++i)
    layers[i * 28 + 19] = 1;
  assert(Java_org_vrpassthroughplayer_plugin_VideoLayerNative_setLayers(&env, nullptr, 2, array));
  release_surface(&env);
  assert(state.count == 2);
  layers[37] = 50;
  assert(!Java_org_vrpassthroughplayer_plugin_VideoLayerNative_setLayers(&env, nullptr, 2, array));
  assert(state.count == 0);
  drop_picture();
  assert(chains.empty() && destroys >= 1);
  state.create_surface = fake_surface;
  const auto destroyed_before = destroys;
  reject_surface = true;
  assert(
      !Java_org_vrpassthroughplayer_plugin_VideoLayerNative_createSurface(&env, nullptr, 64, 32));
  assert(chains.empty() && state.surface_chain == XR_NULL_HANDLE && !state.surface);
  reject_surface = false;
  reject_reference = true;
  assert(
      !Java_org_vrpassthroughplayer_plugin_VideoLayerNative_createSurface(&env, nullptr, 64, 32));
  assert(chains.empty() && destroys == destroyed_before + 2 && local_releases == 2);
  reject_reference = false;
  assert(Java_org_vrpassthroughplayer_plugin_VideoLayerNative_createSurface(&env, nullptr, 64, 32));
  release_surface(&env);
  assert(chains.empty() && global_releases == 1);
  glDeleteTextures(1, &source);
  glDeleteSamplers(1, &sampler);
  std::cout << "Video layer GLES color, fisheye, state, timeout, stereo and PBO checks passed\n";
  eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  eglDestroySurface(display, surface);
  eglDestroyContext(display, context);
  eglTerminate(display);
}
