// Narrow video-only adaptation of Thru3D 959abc2 OpenXR layer lifecycle/remapping.
// Godot owns the instance and frame loop; this module never calls xrEndFrame.
#include <jni.h>
#include <android/log.h>
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <array>
#include <cmath>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>
#define XR_USE_PLATFORM_ANDROID
#define XR_USE_GRAPHICS_API_OPENGL_ES
#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>
#include "layer_layout.h"

namespace {
constexpr int kLayers = 2, kStride = 28;
struct Picture {
  XrSwapchain handle = XR_NULL_HANDLE;
  std::vector<GLuint> textures;
  int width = 0, height = 0, index = -1;
  bool ready = false;
};
union Layer {
  XrCompositionLayerBaseHeader base;
  XrCompositionLayerQuad quad;
  XrCompositionLayerCylinderKHR cylinder;
  XrCompositionLayerEquirect2KHR equirect;
};
struct State {
  XrInstance instance = XR_NULL_HANDLE;
  XrSession session = XR_NULL_HANDLE;
  XrSpace space = XR_NULL_HANDLE;
  PFN_xrGetInstanceProcAddr get = nullptr;
  PFN_xrCreateSwapchainAndroidSurfaceKHR create_surface = nullptr;
  PFN_xrCreateSwapchain create = nullptr;
  PFN_xrDestroySwapchain destroy = nullptr;
  PFN_xrEnumerateSwapchainImages enumerate = nullptr;
  PFN_xrAcquireSwapchainImage acquire = nullptr;
  PFN_xrWaitSwapchainImage wait = nullptr;
  PFN_xrReleaseSwapchainImage release = nullptr;
  XrSwapchain surface_chain = XR_NULL_HANDLE;
  jobject surface = nullptr;
  int surface_width = 0, surface_height = 0, count = 0;
  uint32_t max_layers = 0, max_width = 0, max_height = 0;
  bool srgb = false;
  Picture picture;
  std::array<Layer, kLayers> layers{};
  std::array<XrCompositionLayerImageLayoutFB, kLayers> layout{};
} state;
std::mutex mutex;
GLuint program = 0, framebuffer = 0, vao = 0;
EGLContext gl_owner = EGL_NO_CONTEXT;
uint64_t image_draws = 0;
void require(bool ok, const char *message) {
  if (!ok)
    throw std::runtime_error(message);
}
void failure(JNIEnv *env, const char *message) {
  __android_log_write(ANDROID_LOG_WARN, "ImmivioVideoLayer", message);
  if (env && !env->ExceptionCheck())
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), message);
}
template <class T> T proc(const char *name, bool required = true) {
  PFN_xrVoidFunction value = nullptr;
  XrResult result = state.get(state.instance, name, &value);
  if (required)
    require(XR_SUCCEEDED(result) && value, name);
  return reinterpret_cast<T>(value);
}
void clear_referencing(XrSwapchain chain) {
  if (chain == XR_NULL_HANDLE)
    return;
  for (int i = 0; i < state.count; ++i) {
    const auto &layer = state.layers[i];
    const auto referenced = layer.base.type == XR_TYPE_COMPOSITION_LAYER_QUAD
                                ? layer.quad.subImage.swapchain
                            : layer.base.type == XR_TYPE_COMPOSITION_LAYER_CYLINDER_KHR
                                ? layer.cylinder.subImage.swapchain
                                : layer.equirect.subImage.swapchain;
    if (referenced == chain) {
      state.count = 0;
      return;
    }
  }
}
void drop_picture() {
  clear_referencing(state.picture.handle);
  if (state.picture.handle != XR_NULL_HANDLE && state.session != XR_NULL_HANDLE && state.destroy)
    state.destroy(state.picture.handle);
  state.picture = Picture{};
}
// Called before Godot tears down its session. The decoder owns its Java Surface
// until acknowledged shutdown; a new decoder cannot reuse it during that interval.
void invalidate_session() {
  state.count = 0;
  state.session = XR_NULL_HANDLE;
  state.surface_chain = XR_NULL_HANDLE;
  state.picture = Picture{};
}
void release_surface(JNIEnv *env) {
  clear_referencing(state.surface_chain);
  if (state.surface_chain != XR_NULL_HANDLE && state.session != XR_NULL_HANDLE && state.destroy)
    state.destroy(state.surface_chain);
  state.surface_chain = XR_NULL_HANDLE;
  if (state.surface)
    env->DeleteGlobalRef(state.surface);
  state.surface = nullptr;
  state.surface_width = state.surface_height = 0;
}
bool create_picture(int width, int height) {
  require(state.session != XR_NULL_HANDLE, "XR session unavailable");
  require(state.srgb && width > 0 && height > 0 && width <= 8192 && height <= 8192 &&
              int64_t(width) * height <= 35389440 && width <= int(state.max_width) &&
              height <= int(state.max_height),
          "Picture dimensions/format unsupported");
  auto &p = state.picture;
  if (p.handle != XR_NULL_HANDLE && p.width == width && p.height == height)
    return true;
  drop_picture();
  XrSwapchainCreateInfo info{};
  info.type = XR_TYPE_SWAPCHAIN_CREATE_INFO;
  info.usageFlags = XR_SWAPCHAIN_USAGE_SAMPLED_BIT | XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT;
  info.format = GL_SRGB8_ALPHA8;
  info.sampleCount = info.faceCount = info.arraySize = info.mipCount = 1;
  info.width = width;
  info.height = height;
  require(XR_SUCCEEDED(state.create(state.session, &info, &p.handle)),
          "Picture swapchain creation failed");
  uint32_t count = 0;
  require(XR_SUCCEEDED(state.enumerate(p.handle, 0, &count, nullptr)) && count > 0 && count <= 8,
          "Picture image count unsupported");
  std::vector<XrSwapchainImageOpenGLESKHR> images(count);
  for (auto &image : images) {
    image = {};
    image.type = XR_TYPE_SWAPCHAIN_IMAGE_OPENGL_ES_KHR;
  }
  require(
      XR_SUCCEEDED(state.enumerate(p.handle, count, &count,
                                   reinterpret_cast<XrSwapchainImageBaseHeader *>(images.data()))),
      "Picture images unavailable");
  for (auto &image : images)
    p.textures.push_back(image.image);
  p.width = width;
  p.height = height;
  return true;
}
bool acquire_picture() {
  auto &p = state.picture;
  require(p.handle != XR_NULL_HANDLE, "Picture swapchain unavailable");
  if (p.index < 0) {
    uint32_t index = 0;
    XrSwapchainImageAcquireInfo acquire{};
    acquire.type = XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO;
    require(XR_SUCCEEDED(state.acquire(p.handle, &acquire, &index)), "Picture acquire failed");
    require(index < p.textures.size(), "Picture index out of bounds");
    p.index = static_cast<int>(index);
  }
  XrSwapchainImageWaitInfo wait{};
  wait.type = XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO;
  wait.timeout = 0; // Never wait for the compositor on Godot's render thread.
  const auto result = state.wait(p.handle, &wait);
  if (result == XR_TIMEOUT_EXPIRED)
    return false;
  require(result == XR_SUCCESS, "Picture wait failed");
  p.ready = true;
  return true;
}
void release_picture() {
  auto &p = state.picture;
  if (p.index < 0 || !p.ready)
    return;
  glFlush();
  XrSwapchainImageReleaseInfo release{};
  release.type = XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO;
  require(XR_SUCCEEDED(state.release(p.handle, &release)), "Picture release failed");
  p.ready = false;
  p.index = -1;
}
struct GlState {
  GLint read = 0, draw = 0, active = 0, texture = 0, sampler = 0, shader = 0, array = 0,
        viewport[4]{};
  GLboolean blend, scissor, depth, cull, stencil, dither, color[4], srgb = GL_FALSE;
  static constexpr GLenum kSrgb = 0x8DB9;
  static bool srgb_control() {
    static EGLContext owner = EGL_NO_CONTEXT;
    static bool available = false;
    auto current = eglGetCurrentContext();
    if (current != owner) {
      owner = current;
      const auto *extensions = reinterpret_cast<const char *>(glGetString(GL_EXTENSIONS));
      available = extensions &&
                  std::string(extensions).find("GL_EXT_sRGB_write_control") != std::string::npos;
    }
    return available;
  }
  GlState() {
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &read);
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &draw);
    glGetIntegerv(GL_ACTIVE_TEXTURE, &active);
    glActiveTexture(GL_TEXTURE0);
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &texture);
    glGetIntegerv(GL_SAMPLER_BINDING, &sampler);
    glGetIntegerv(GL_CURRENT_PROGRAM, &shader);
    glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &array);
    glGetIntegerv(GL_VIEWPORT, viewport);
    blend = glIsEnabled(GL_BLEND);
    scissor = glIsEnabled(GL_SCISSOR_TEST);
    depth = glIsEnabled(GL_DEPTH_TEST);
    cull = glIsEnabled(GL_CULL_FACE);
    stencil = glIsEnabled(GL_STENCIL_TEST);
    dither = glIsEnabled(GL_DITHER);
    glGetBooleanv(GL_COLOR_WRITEMASK, color);
    if (srgb_control())
      srgb = glIsEnabled(kSrgb);
  }
  static void set(GLenum what, GLboolean enabled) {
    if (enabled)
      glEnable(what);
    else
      glDisable(what);
  }
  ~GlState() {
    glBindFramebuffer(GL_READ_FRAMEBUFFER, read);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, draw);
    glUseProgram(shader);
    glBindVertexArray(array);
    glBindTexture(GL_TEXTURE_2D, texture);
    glBindSampler(0, sampler);
    glActiveTexture(active);
    glViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
    set(GL_BLEND, blend);
    set(GL_SCISSOR_TEST, scissor);
    set(GL_DEPTH_TEST, depth);
    set(GL_CULL_FACE, cull);
    set(GL_STENCIL_TEST, stencil);
    set(GL_DITHER, dither);
    glColorMask(color[0], color[1], color[2], color[3]);
    if (srgb_control())
      set(kSrgb, srgb);
  }
};
GLuint compile(GLenum kind, const char *text) {
  GLuint value = glCreateShader(kind);
  glShaderSource(value, 1, &text, nullptr);
  glCompileShader(value);
  GLint ok = 0;
  glGetShaderiv(value, GL_COMPILE_STATUS, &ok);
  if (!ok) {
    glDeleteShader(value);
    throw std::runtime_error("Video picture shader compilation failed");
  }
  return value;
}
void prepare_gl() {
  EGLContext current = eglGetCurrentContext();
  require(current != EGL_NO_CONTEXT, "Video picture needs the render context");
  if (current != gl_owner || (program && !glIsProgram(program))) {
    program = framebuffer = vao = 0;
    gl_owner = current;
  }
  if (program)
    return;
  const char *vs =
      "#version 300 es\nvoid main(){vec2 "
      "p=vec2(float((gl_VertexID<<1)&2),float(gl_VertexID&2));gl_Position=vec4(p*2.-1.,0.,1.);}";
  const char *fs = R"GLSL(#version 300 es
precision highp float;
uniform sampler2D source;
uniform vec2 target, source_size, span, uv_scale;
uniform float fov;
uniform int frame_layout, half_eyes, fisheye, flip_y, raw_output;
out vec4 result;
vec3 linear_color(vec3 c){return mix(c/12.92,pow((c+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),c));}
void main(){
 vec2 uv=gl_FragCoord.xy/target;
 if(flip_y==1) uv.y=1.-uv.y;
 vec2 p=uv;
 if(fisheye==1){
  float eye=0.;vec2 local=uv;
  if(frame_layout==1){eye=step(0.5,uv.x);local.x=uv.x*2.-eye;}
  else if(frame_layout==2){eye=step(0.5,uv.y);local.y=uv.y*2.-eye;}
  float longitude=(local.x-0.5)*span.x,latitude=(0.5-local.y)*span.y;
  vec3 d=vec3(cos(latitude)*sin(longitude),sin(latitude),-cos(latitude)*cos(longitude));
  float radial=acos(clamp(-d.z,-1.,1.))/radians(fov*0.5);
  if(radial>1.){result=vec4(0.,0.,0.,1.);return;}
  vec2 axis=length(d.xy)>0.000001?vec2(d.x,-d.y)/length(d.xy):vec2(0.);
  vec2 size=source_size*(frame_layout==1?vec2(0.5,1.):frame_layout==2?vec2(1.,0.5):vec2(1.));
  p=vec2(0.5)+0.5*radial*axis*(half_eyes==1?vec2(1.):min(size.x,size.y)/size);
  p=clamp(p,vec2(0.5)/size,vec2(1.)-vec2(0.5)/size);
  if(frame_layout==1)p.x=(p.x+eye)*0.5;else if(frame_layout==2)p.y=(p.y+eye)*0.5;
 }
 vec3 c=texture(source,p*uv_scale).rgb;
 result=vec4(raw_output==1?c:linear_color(c),1.);
})GLSL";
  GLuint v = compile(GL_VERTEX_SHADER, vs), f = compile(GL_FRAGMENT_SHADER, fs);
  program = glCreateProgram();
  glAttachShader(program, v);
  glAttachShader(program, f);
  glLinkProgram(program);
  glDeleteShader(v);
  glDeleteShader(f);
  GLint ok = 0;
  glGetProgramiv(program, GL_LINK_STATUS, &ok);
  require(ok, "Video picture shader linking failed");
  glGenFramebuffers(1, &framebuffer);
  glGenVertexArrays(1, &vao);
}
bool draw_picture(GLuint texture, bool lens, const float *v) {
  auto &p = state.picture;
  require(p.ready && p.index >= 0 && glIsTexture(texture), "Video picture source unavailable");
  GlState saved;
  prepare_gl();
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, framebuffer);
  glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                         p.textures[p.index], 0);
  require(glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE,
          "Video picture framebuffer incomplete");
  glDisable(GL_BLEND);
  glDisable(GL_SCISSOR_TEST);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);
  glDisable(GL_STENCIL_TEST);
  glDisable(GL_DITHER);
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  glViewport(0, 0, p.width, p.height);
  glUseProgram(program);
  glBindVertexArray(vao);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, texture);
  glBindSampler(0, 0);
  const bool raw = GlState::srgb_control();
  if (raw)
    glDisable(GlState::kSrgb);
  glUniform1i(glGetUniformLocation(program, "raw_output"), raw);
  glUniform1i(glGetUniformLocation(program, "source"), 0);
  glUniform1i(glGetUniformLocation(program, "fisheye"), lens);
  glUniform1i(glGetUniformLocation(program, "frame_layout"), int(v[0]));
  glUniform1i(glGetUniformLocation(program, "half_eyes"), int(v[1]));
  glUniform1i(glGetUniformLocation(program, "flip_y"), int(v[9]));
  glUniform1f(glGetUniformLocation(program, "fov"), v[2]);
  glUniform2f(glGetUniformLocation(program, "span"), v[3], v[4]);
  glUniform2f(glGetUniformLocation(program, "source_size"), v[5], v[6]);
  glUniform2f(glGetUniformLocation(program, "uv_scale"), v[7], v[8]);
  glUniform2f(glGetUniformLocation(program, "target"), p.width, p.height);
  glDrawArrays(GL_TRIANGLES, 0, 3);
  const auto status = glGetError();
  glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 0, 0);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
  require(status == GL_NO_ERROR, "Video picture draw failed");
  ++image_draws;
  return true;
}
} // namespace

extern "C" JNIEXPORT jboolean JNICALL Java_org_vrpassthroughplayer_plugin_VideoLayerNative_bind(
    JNIEnv *env, jclass, jlong instance, jlong session, jlong get, jlong space) {
  std::lock_guard<std::mutex> guard(mutex);
  try {
    require(instance && session && get && space, "OpenXR handles unavailable");
    auto next = reinterpret_cast<XrSession>(uintptr_t(session));
    if (state.session != XR_NULL_HANDLE && state.session != next)
      invalidate_session();
    state.instance = reinterpret_cast<XrInstance>(uintptr_t(instance));
    state.session = next;
    state.space = reinterpret_cast<XrSpace>(uintptr_t(space));
    state.get = reinterpret_cast<PFN_xrGetInstanceProcAddr>(uintptr_t(get));
    state.create_surface =
        proc<PFN_xrCreateSwapchainAndroidSurfaceKHR>("xrCreateSwapchainAndroidSurfaceKHR", false);
    state.create = proc<PFN_xrCreateSwapchain>("xrCreateSwapchain");
    state.destroy = proc<PFN_xrDestroySwapchain>("xrDestroySwapchain");
    state.enumerate = proc<PFN_xrEnumerateSwapchainImages>("xrEnumerateSwapchainImages");
    state.acquire = proc<PFN_xrAcquireSwapchainImage>("xrAcquireSwapchainImage");
    state.wait = proc<PFN_xrWaitSwapchainImage>("xrWaitSwapchainImage");
    state.release = proc<PFN_xrReleaseSwapchainImage>("xrReleaseSwapchainImage");
    XrSystemGetInfo query{};
    query.type = XR_TYPE_SYSTEM_GET_INFO;
    query.formFactor = XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY;
    XrSystemId system = XR_NULL_SYSTEM_ID;
    require(XR_SUCCEEDED(proc<PFN_xrGetSystem>("xrGetSystem")(state.instance, &query, &system)),
            "XR system unavailable");
    XrSystemProperties info{};
    info.type = XR_TYPE_SYSTEM_PROPERTIES;
    require(XR_SUCCEEDED(proc<PFN_xrGetSystemProperties>("xrGetSystemProperties")(state.instance,
                                                                                  system, &info)),
            "XR limits unavailable");
    state.max_layers = info.graphicsProperties.maxLayerCount;
    state.max_width = info.graphicsProperties.maxSwapchainImageWidth;
    state.max_height = info.graphicsProperties.maxSwapchainImageHeight;
    auto formats = proc<PFN_xrEnumerateSwapchainFormats>("xrEnumerateSwapchainFormats");
    uint32_t n = 0;
    require(XR_SUCCEEDED(formats(state.session, 0, &n, nullptr)) && n <= 256,
            "XR formats unavailable");
    std::vector<int64_t> values(n);
    require(XR_SUCCEEDED(formats(state.session, n, &n, values.data())), "XR formats unavailable");
    state.srgb = false;
    for (auto f : values)
      if (f == GL_SRGB8_ALPHA8)
        state.srgb = true;
    return JNI_TRUE;
  } catch (const std::exception &e) {
    failure(env, e.what());
    return JNI_FALSE;
  }
}
extern "C" JNIEXPORT jobject JNICALL
Java_org_vrpassthroughplayer_plugin_VideoLayerNative_createSurface(JNIEnv *env, jclass, jint w,
                                                                   jint h) {
  std::lock_guard<std::mutex> guard(mutex);
  XrSwapchain chain = XR_NULL_HANDLE;
  jobject surface = nullptr;
  jobject retained = nullptr;
  try {
    require(state.session != XR_NULL_HANDLE && state.create_surface,
            "Surface swapchains unavailable");
    require(!state.surface && state.surface_chain == XR_NULL_HANDLE,
            "Previous decoder still owns its Surface");
    require(w > 0 && h > 0 && w <= 8192 && h <= 8192 && int64_t(w) * h <= 35389440 &&
                w <= int(state.max_width) && h <= int(state.max_height),
            "Surface dimensions unsupported");
    XrSwapchainCreateInfo info{};
    info.type = XR_TYPE_SWAPCHAIN_CREATE_INFO;
    info.usageFlags = XR_SWAPCHAIN_USAGE_SAMPLED_BIT | XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT |
                      XR_SWAPCHAIN_USAGE_MUTABLE_FORMAT_BIT;
    info.width = w;
    info.height = h;
    require(XR_SUCCEEDED(state.create_surface(state.session, &info, &chain, &surface)) &&
                chain != XR_NULL_HANDLE && surface,
            "Surface swapchain creation failed");
    retained = env->NewGlobalRef(surface);
    require(retained, "Surface reference unavailable");
    state.surface = retained;
    state.surface_chain = chain;
    state.surface_width = w;
    state.surface_height = h;
    return surface;
  } catch (const std::exception &e) {
    if (retained)
      env->DeleteGlobalRef(retained);
    if (surface)
      env->DeleteLocalRef(surface);
    if (chain != XR_NULL_HANDLE && state.destroy)
      state.destroy(chain);
    failure(env, e.what());
    return nullptr;
  }
}
extern "C" JNIEXPORT void JNICALL
Java_org_vrpassthroughplayer_plugin_VideoLayerNative_destroySurface(JNIEnv *env, jclass) {
  std::lock_guard<std::mutex> guard(mutex);
  release_surface(env);
}
extern "C" JNIEXPORT void JNICALL
Java_org_vrpassthroughplayer_plugin_VideoLayerNative_invalidate(JNIEnv *, jclass) {
  std::lock_guard<std::mutex> guard(mutex);
  invalidate_session();
}
extern "C" JNIEXPORT jstring JNICALL
Java_org_vrpassthroughplayer_plugin_VideoLayerNative_limits(JNIEnv *env, jclass) {
  std::lock_guard<std::mutex> guard(mutex);
  return env->NewStringUTF(
      (std::to_string(state.max_layers) + " " + std::to_string(state.max_width) + " " +
       std::to_string(state.max_height) + " " + (state.create_surface ? "1" : "0") + " " +
       (state.srgb ? "1" : "0") + " " + std::to_string(image_draws))
          .c_str());
}
extern "C" JNIEXPORT jboolean JNICALL
Java_org_vrpassthroughplayer_plugin_VideoLayerNative_createImage(JNIEnv *env, jclass, jint w,
                                                                 jint h) {
  std::lock_guard<std::mutex> guard(mutex);
  try {
    return create_picture(w, h);
  } catch (const std::exception &e) {
    failure(env, e.what());
    drop_picture();
    return JNI_FALSE;
  }
}
extern "C" JNIEXPORT jboolean JNICALL
Java_org_vrpassthroughplayer_plugin_VideoLayerNative_drawImage(JNIEnv *env, jclass, jint texture,
                                                               jboolean lens,
                                                               jfloatArray parameters) {
  std::lock_guard<std::mutex> guard(mutex);
  try {
    require(parameters && env->GetArrayLength(parameters) == 10, "Picture parameters invalid");
    float v[10];
    env->GetFloatArrayRegion(parameters, 0, 10, v);
    for (float f : v)
      require(std::isfinite(f), "Picture parameters invalid");
    if (!acquire_picture())
      return JNI_FALSE;
    bool ok = false;
    try {
      ok = draw_picture(texture, lens, v);
    } catch (...) {
      release_picture();
      throw;
    }
    release_picture();
    return ok;
  } catch (const std::exception &e) {
    failure(env, e.what());
    return JNI_FALSE;
  }
}
extern "C" JNIEXPORT void JNICALL
Java_org_vrpassthroughplayer_plugin_VideoLayerNative_destroyImage(JNIEnv *, jclass) {
  std::lock_guard<std::mutex> guard(mutex);
  drop_picture();
}
extern "C" JNIEXPORT jboolean JNICALL
Java_org_vrpassthroughplayer_plugin_VideoLayerNative_setLayers(JNIEnv *env, jclass, jint count,
                                                               jfloatArray array) {
  std::lock_guard<std::mutex> guard(mutex);
  try {
    require(count >= 0 && count <= kLayers &&
                count <= int(state.max_layers > 4 ? state.max_layers - 4 : 0),
            "Video layer budget exceeded");
    require(array && env->GetArrayLength(array) == count * kStride, "Layer payload invalid");
    std::array<float, kLayers * kStride> values{};
    if (count)
      env->GetFloatArrayRegion(array, 0, count * kStride, values.data());
    for (int i = 0; i < count; ++i) {
      const float *p = values.data() + i * kStride;
      for (int j = 0; j < kStride; ++j)
        require(std::isfinite(p[j]), "Layer field invalid");
      const bool image = p[19] == 1;
      const int w = image ? state.picture.width : state.surface_width,
                h = image ? state.picture.height : state.surface_height;
      require(quest::image_rect_valid(p + 9, w, h), "Layer rectangle invalid");
      require(p[0] >= 0 && p[0] <= 2 && p[0] == std::floor(p[0]) && p[1] >= 0 && p[1] <= 2 &&
                  p[1] == std::floor(p[1]),
              "Layer type/eye invalid");
      require((p[19] == 0 || p[19] == 1) && (p[17] == -1 || p[17] == 0 || p[17] == 1),
              "Layer source/layout invalid");
      if (p[0] == 1)
        require(p[14] <= 6.283186f && p[15] > 0, "Cylinder shape invalid");
      if (p[0] == 2)
        require(p[14] <= 6.283186f && p[15] <= 1.570797f && p[15] >= -1.570797f &&
                    p[16] >= -1.570797f && p[16] <= p[15],
                "Equirect shape invalid");
      if (count == 1)
        require(p[1] == 0, "A single layer must show both eyes");
      if (count == 2)
        require(p[1] == i + 1, "Stereo layers must be a complete eye pair");
      float q = 0;
      for (int j = 5; j <= 8; ++j)
        q += p[j] * p[j];
      require(std::abs(q - 1) < 0.02f && p[13] > 0 && p[14] > 0, "Layer shape/pose invalid");
      require((image ? state.picture.handle : state.surface_chain) != XR_NULL_HANDLE &&
                  state.session != XR_NULL_HANDLE,
              "Layer source unavailable");
      require(p[18] == 0 && p[26] == 0 && p[27] == 0, "Unsupported video layer options");
    }
    for (int i = 0; i < count; ++i) {
      const float *p = values.data() + i * kStride;
      auto &layer = state.layers[i];
      const bool image = p[19] == 1;
      XrSwapchainSubImage sub{image ? state.picture.handle : state.surface_chain,
                              quest::browser_image_rect(p + 9), 0};
      XrPosef pose{{p[5], p[6], p[7], p[8]}, {p[2], p[3], p[4]}};
      auto eye = p[1] == 1   ? XR_EYE_VISIBILITY_LEFT
                 : p[1] == 2 ? XR_EYE_VISIBILITY_RIGHT
                             : XR_EYE_VISIBILITY_BOTH;
      if (p[0] == 0)
        layer.quad = {XR_TYPE_COMPOSITION_LAYER_QUAD,
                      nullptr,
                      0,
                      state.space,
                      eye,
                      sub,
                      pose,
                      {p[13], p[14]}};
      else if (p[0] == 1)
        layer.cylinder = {XR_TYPE_COMPOSITION_LAYER_CYLINDER_KHR,
                          nullptr,
                          0,
                          state.space,
                          eye,
                          sub,
                          pose,
                          p[13],
                          p[14],
                          p[15]};
      else
        layer.equirect = {XR_TYPE_COMPOSITION_LAYER_EQUIRECT2_KHR,
                          nullptr,
                          0,
                          state.space,
                          eye,
                          sub,
                          pose,
                          p[13],
                          p[14],
                          p[15],
                          p[16]};
      layer.base.next = quest::image_layout_next(state.layout[i], p[17], nullptr);
    }
    state.count = count;
    return JNI_TRUE;
  } catch (const std::exception &e) {
    state.count = 0;
    failure(env, e.what());
    return JNI_FALSE;
  }
}
extern "C" JNIEXPORT jlong JNICALL
Java_org_vrpassthroughplayer_plugin_VideoLayerNative_layerAddress(JNIEnv *, jclass, jint i) {
  std::lock_guard<std::mutex> guard(mutex);
  return i >= 0 && i < state.count ? reinterpret_cast<jlong>(&state.layers[i]) : 0;
}

#include "focus_readback.h"
namespace {
FocusReadback focus_readback;
}
extern "C" JNIEXPORT jlong JNICALL
Java_org_vrpassthroughplayer_plugin_VideoLayerNative_requestReadback(JNIEnv *, jclass, jint texture,
                                                                     jint w, jint h) {
  std::lock_guard<std::mutex> guard(mutex);
  return focus_readback.request(texture, w, h);
}
extern "C" JNIEXPORT jbyteArray JNICALL
Java_org_vrpassthroughplayer_plugin_VideoLayerNative_pollReadback(JNIEnv *env, jclass,
                                                                  jlong token) {
  std::lock_guard<std::mutex> guard(mutex);
  auto pixels = focus_readback.poll(token);
  auto result = env->NewByteArray(static_cast<jsize>(pixels.size()));
  if (!pixels.empty())
    env->SetByteArrayRegion(result, 0, static_cast<jsize>(pixels.size()),
                            reinterpret_cast<const jbyte *>(pixels.data()));
  return result;
}
extern "C" JNIEXPORT void JNICALL
Java_org_vrpassthroughplayer_plugin_VideoLayerNative_cancelReadback(JNIEnv *, jclass, jlong token) {
  std::lock_guard<std::mutex> guard(mutex);
  focus_readback.cancel(token);
}
