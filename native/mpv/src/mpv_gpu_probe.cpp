#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <android/log.h>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <dlfcn.h>
#include <memory>
#include <mpv/client.h>
#include <mpv/render_gl.h>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {
void checked(int result, const char *operation) {
  if (result < 0)
    throw std::runtime_error(std::string(operation) + ": " +
                             mpv_error_string(result));
}
void require(bool condition, const char *operation) {
  if (!condition)
    throw std::runtime_error(operation);
}
std::string quoted(const std::string &value) {
  std::string out = "\"";
  for (const unsigned char c : value) {
    if (c == '"' || c == '\\') {
      out += '\\';
      out += static_cast<char>(c);
    } else if (c == '\n')
      out += "\\n";
    else if (c == '\r')
      out += "\\r";
    else if (c == '\t')
      out += "\\t";
    else if (c >= 32)
      out += static_cast<char>(c);
  }
  return out + '"';
}
std::string property(mpv_handle *core, const char *key) {
  char *value = mpv_get_property_string(core, key);
  const std::string result = value ? value : "";
  mpv_free(value);
  return result;
}
struct Target {
  EGLDisplay display = EGL_NO_DISPLAY;
  EGLContext context = EGL_NO_CONTEXT;
  EGLSurface surface = EGL_NO_SURFACE;
  GLuint texture = 0, framebuffer = 0;
  void *library = nullptr;
  int width, height;
  explicit Target(int w, int h) : width(w), height(h) {}
  void initialize() {
    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    require(display != EGL_NO_DISPLAY &&
                eglInitialize(display, nullptr, nullptr),
            "EGL display initialization");
    require(eglBindAPI(EGL_OPENGL_ES_API), "EGL GLES binding");
    const EGLint config_attributes[] = {EGL_RENDERABLE_TYPE,
                                        EGL_OPENGL_ES3_BIT_KHR,
                                        EGL_SURFACE_TYPE,
                                        EGL_PBUFFER_BIT,
                                        EGL_RED_SIZE,
                                        8,
                                        EGL_GREEN_SIZE,
                                        8,
                                        EGL_BLUE_SIZE,
                                        8,
                                        EGL_ALPHA_SIZE,
                                        8,
                                        EGL_NONE};
    EGLConfig config = nullptr;
    EGLint count = 0;
    require(eglChooseConfig(display, config_attributes, &config, 1, &count) &&
                count == 1,
            "EGL GLES3 config");
    const EGLint context_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3,
                                         EGL_NONE};
    context =
        eglCreateContext(display, config, EGL_NO_CONTEXT, context_attributes);
    require(context != EGL_NO_CONTEXT, "EGL isolated context");
    const EGLint surface_attributes[] = {EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE};
    surface = eglCreatePbufferSurface(display, config, surface_attributes);
    require(surface != EGL_NO_SURFACE &&
                eglMakeCurrent(display, surface, surface, context),
            "EGL probe current");
    library = dlopen("libGLESv3.so", RTLD_NOW | RTLD_LOCAL);
    require(library != nullptr, "GLES symbol library");
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, width, height);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                           texture, 0);
    require(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE,
            "MPV probe RGBA8 FBO");
    require(glGetError() == GL_NO_ERROR, "MPV probe GL allocation");
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
  }
  bool release() noexcept {
    bool success = true;
    if (context != EGL_NO_CONTEXT && eglGetCurrentContext() == context) {
      if (framebuffer)
        glDeleteFramebuffers(1, &framebuffer);
      if (texture)
        glDeleteTextures(1, &texture);
      success = glGetError() == GL_NO_ERROR;
      framebuffer = 0;
      texture = 0;
      success = eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                               EGL_NO_CONTEXT) &&
                success;
    }
    if (surface != EGL_NO_SURFACE) {
      success = eglDestroySurface(display, surface) && success;
      surface = EGL_NO_SURFACE;
    }
    if (context != EGL_NO_CONTEXT) {
      success = eglDestroyContext(display, context) && success;
      context = EGL_NO_CONTEXT;
    }
    if (library) {
      dlclose(library);
      library = nullptr;
    }
    // EGL_DEFAULT_DISPLAY is process-global and also belongs to Godot.
    // Do not eglTerminate it when disposing this isolated diagnostic context.
    return success;
  }
  ~Target() { release(); }
  static void *resolve(void *opaque, const char *name) {
    auto *target = static_cast<Target *>(opaque);
    void *result = reinterpret_cast<void *>(eglGetProcAddress(name));
    return result ? result : dlsym(target->library, name);
  }
  std::string samples() {
    glBindFramebuffer(GL_READ_FRAMEBUFFER, framebuffer);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glPixelStorei(GL_PACK_ROW_LENGTH, 0);
    glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
    glPixelStorei(GL_PACK_SKIP_ROWS, 0);
    std::string out = "[";
    bool first = true;
    for (const int yp : {20, 50, 80})
      for (const int xp : {8, 25, 42, 58, 75, 92}) {
        const int x = width * xp / 100, top_y = height * yp / 100;
        unsigned char pixel[4] = {};
        // With FLIP_Y=0 MPV's texture origin represents the source top row.
        glReadPixels(x, top_y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
        if (!first)
          out += ',';
        first = false;
        out += "{\"x\":" + std::to_string(x) +
               ",\"y\":" + std::to_string(top_y) + ",\"rgba\":[";
        for (int channel = 0; channel < 4; ++channel) {
          if (channel)
            out += ',';
          out += std::to_string(pixel[channel]);
        }
        out += "]}";
      }
    out += ']';
    require(glGetError() == GL_NO_ERROR, "MPV sparse GL pixel samples");
    glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
    return out;
  }
};
struct RenderWorker {
  mpv_handle *core;
  const int width, height;
  std::atomic<bool> stop{false}, pending{true}, ready{false},
      first_frame{false}, failed{false};
  std::atomic<int> renders{0}, video_frames{0}, redraws{0};
  bool context_disposed = false;
  std::mutex wait_mutex;
  std::condition_variable wake;
  // Written on render thread, read only after join.
  std::string error, gl_vendor, gl_renderer, gl_version, first_samples;
  std::thread thread;
  RenderWorker(mpv_handle *handle, int w, int h)
      : core(handle), width(w), height(h), thread([this] { run(); }) {}
  static void callback(void *opaque) noexcept {
    auto *worker = static_cast<RenderWorker *>(opaque);
    worker->pending.store(true);
    worker->wake.notify_one();
  }
  void run() noexcept {
    Target target(width, height);
    mpv_render_context *renderer = nullptr;
    try {

      target.initialize();
      gl_vendor = reinterpret_cast<const char *>(glGetString(GL_VENDOR));
      gl_renderer = reinterpret_cast<const char *>(glGetString(GL_RENDERER));
      gl_version = reinterpret_cast<const char *>(glGetString(GL_VERSION));
      mpv_opengl_init_params initialization{Target::resolve, &target};
      int advanced = 1;
      mpv_render_param initialization_params[] = {
          {MPV_RENDER_PARAM_API_TYPE,
           const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)},
          {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &initialization},
          {MPV_RENDER_PARAM_ADVANCED_CONTROL, &advanced},
          {MPV_RENDER_PARAM_INVALID, nullptr}};
      checked(mpv_render_context_create(&renderer, core, initialization_params),
              "mpv GLES render create");
      mpv_render_context_set_update_callback(renderer, callback, this);
      ready.store(true);
      while (!stop.load()) {
        if (!pending.exchange(false)) {
          std::unique_lock<std::mutex> lock(wait_mutex);
          wake.wait_for(lock, std::chrono::milliseconds(3),
                        [this] { return pending.load() || stop.load(); });
          continue;
        }
        const uint64_t update = mpv_render_context_update(renderer);
        if (!(update & MPV_RENDER_UPDATE_FRAME))
          continue;
        mpv_render_frame_info info{};
        checked(mpv_render_context_get_info(
                    renderer, {MPV_RENDER_PARAM_NEXT_FRAME_INFO, &info}),
                "next display frame info");
        mpv_opengl_fbo fbo{static_cast<int>(target.framebuffer), width, height,
                           GL_RGBA8};
        int flip = 0;
        mpv_render_param params[] = {{MPV_RENDER_PARAM_OPENGL_FBO, &fbo},
                                     {MPV_RENDER_PARAM_FLIP_Y, &flip},
                                     {MPV_RENDER_PARAM_INVALID, nullptr}};
        const int render_result = mpv_render_context_render(renderer, params);

        checked(render_result, "mpv GLES render");
        require(glGetError() == GL_NO_ERROR, "MPV render GL error");
        ++renders;
        if (info.flags & MPV_RENDER_FRAME_INFO_REDRAW)
          ++redraws;
        else if (info.flags & MPV_RENDER_FRAME_INFO_PRESENT) {
          ++video_frames;
          if (!first_frame.load()) {
            first_samples = target.samples();
            first_frame.store(true);
          }
        }
        mpv_render_context_report_swap(renderer);
      }
    } catch (const std::exception &exception) {
      error = exception.what();
      __android_log_print(ANDROID_LOG_ERROR, "QuestMpv",
                          "Isolated GLES worker: %s", error.c_str());
      failed.store(true);
      ready.store(true);
    }
    if (renderer) {
      mpv_render_context_set_update_callback(renderer, nullptr, nullptr);
      mpv_render_context_free(renderer);
    }
    context_disposed = target.release();
    if (!context_disposed) {
      failed.store(true);
      error += "; EGL/GL disposal failed";
    }
  }
  void finish() {
    stop.store(true);
    wake.notify_one();
    if (thread.joinable())
      thread.join();
  }
  ~RenderWorker() { finish(); }
};
} // namespace

std::string quest_mpv_gpu_probe(const std::string &path, bool hardware,
                                int width, int height) {
  require((width == 1920 && height == 1080) || (width == 1280 && height == 640),
          "GPU diagnostic fixture dimensions");
  std::unique_ptr<mpv_handle, decltype(&mpv_terminate_destroy)> core(
      mpv_create(), mpv_terminate_destroy);
  require(core != nullptr, "GPU mpv_create");
  const auto option = [&](const char *key, const char *value) {
    checked(mpv_set_option_string(core.get(), key, value), key);
  };
  option("config", "no");
  option("load-scripts", "no");
  option("terminal", "no");
  option("vo", "libmpv");
  option("audio", "no");
  option("hwdec", hardware ? "mediacodec" : "no");
  option("hwdec-codecs", "all");
  option("pause", "yes");
  option("keep-open", "no");
  option("idle", "yes");
  option("osd-level", "0");
  option("sub", "no");
  option("dither", "no");
  option("scale", "bilinear");
  option("cscale", "bilinear");
  option("dscale", "bilinear");
  option("interpolation", "no");
  checked(mpv_request_log_messages(core.get(), "info"), "GPU log subscription");
  checked(mpv_initialize(core.get()), "GPU mpv_initialize");
  const std::string version = property(core.get(), "mpv-version");
  RenderWorker worker(core.get(), width, height);
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(25);
  while (!worker.ready.load() && std::chrono::steady_clock::now() < deadline)
    std::this_thread::sleep_for(std::chrono::milliseconds(2));
  require(worker.ready.load() && !worker.failed.load(),
          "MPV isolated GLES worker initialization; inspect logcat");
  const char *command[] = {"loadfile", path.c_str(), nullptr};
  checked(mpv_command(core.get(), command), "GPU loadfile");
  bool loaded = false, resumed = false, ended = false;
  int end_reason = -1, playback_error = 0;
  std::string hwdec, codec, source_width, source_height, matrix, levels,
      chroma_location;
  while (std::chrono::steady_clock::now() < deadline && !ended &&
         !worker.failed.load()) {
    const auto *event = mpv_wait_event(core.get(), 0.01);
    require(event != nullptr, "GPU mpv_wait_event");
    if (event->event_id == MPV_EVENT_LOG_MESSAGE) {
      const auto *log = static_cast<const mpv_event_log_message *>(event->data);
      __android_log_print(ANDROID_LOG_INFO, "QuestMpv", "[GPU %s] %s",
                          log->prefix, log->text);
    } else if (event->event_id == MPV_EVENT_FILE_LOADED)
      loaded = true;
    else if (event->event_id == MPV_EVENT_END_FILE) {
      const auto *end = static_cast<const mpv_event_end_file *>(event->data);
      ended = true;
      end_reason = end->reason;
      playback_error = end->error;
    }
    if (!resumed && worker.first_frame.load()) {
      hwdec = property(core.get(), "hwdec-current");
      codec = property(core.get(), "video-codec");
      source_width = property(core.get(), "video-params/w");
      source_height = property(core.get(), "video-params/h");
      matrix = property(core.get(), "video-params/colormatrix");
      levels = property(core.get(), "video-params/colorlevels");
      chroma_location = property(core.get(), "video-params/chroma-location");

      checked(mpv_set_property_string(core.get(), "pause", "no"),
              "GPU resume after first FBO");
      resumed = true;
    }
  }
  if (!ended) {
    const char *stop[] = {"stop", nullptr};
    checked(mpv_command(core.get(), stop),
            "GPU stop before renderer destruction");
  }
  worker.finish();
  const bool backend_matches = hardware ? hwdec == "mediacodec" : hwdec == "no";
  const bool passed =
      loaded && resumed && ended && end_reason == MPV_END_FILE_REASON_EOF &&
      playback_error == 0 && backend_matches && !worker.failed.load() &&
      worker.video_frames.load() >= 10 &&
      source_width == std::to_string(width) &&
      source_height == std::to_string(height);
  return "{\"state\":" + quoted(passed ? "passed" : "failed") +
         ",\"detail\":" + quoted(worker.error) +
         ",\"mpv_version\":" + quoted(version) +
         ",\"requested_hardware\":" + (hardware ? "true" : "false") +
         ",\"hwdec_current\":" + quoted(hwdec) + ",\"codec\":" + quoted(codec) +
         ",\"source_width\":" + quoted(source_width) +
         ",\"source_height\":" + quoted(source_height) +
         ",\"fbo_width\":" + std::to_string(width) +
         ",\"fbo_height\":" + std::to_string(height) +
         ",\"source_colormatrix\":" + quoted(matrix) +
         ",\"source_colorlevels\":" + quoted(levels) +
         ",\"source_chroma_location\":" + quoted(chroma_location) +
         ",\"file_loaded\":" + (loaded ? "true" : "false") +
         ",\"ended\":" + (ended ? "true" : "false") +
         ",\"end_reason\":" + std::to_string(end_reason) +
         ",\"playback_error\":" + std::to_string(playback_error) +
         ",\"renders\":" + std::to_string(worker.renders.load()) +
         ",\"video_render_events\":" +
         std::to_string(worker.video_frames.load()) +
         ",\"redraw_events\":" + std::to_string(worker.redraws.load()) +
         ",\"gl_vendor\":" + quoted(worker.gl_vendor) +
         ",\"gl_renderer\":" + quoted(worker.gl_renderer) +
         ",\"gl_version\":" + quoted(worker.gl_version) +
         ",\"first_paused_samples\":" +
         (worker.first_samples.empty() ? "[]" : worker.first_samples) +
         ",\"source_pts_verified\":false,\"godot_context_shared\":false,"
         "\"audio_enabled\":false,\"vo\":\"libmpv\"" +
         ",\"context_disposed\":" +
         (worker.context_disposed ? "true" : "false") +
         std::string(",\"flip_y\":0,\"sample_coordinate\":\"source top-left; "
                     "raw GL y=y for MPV FLIP_Y=0\",\"cscale\":\"bilinear\"") +
         ",\"scope\":\"Isolated GLES FBO render/actual hwdec/EOS diagnostic; "
         "precise source PTS, Godot sharing and audio unverified\"}";
}
