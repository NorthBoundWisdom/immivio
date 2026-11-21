package org.vrpassthroughplayer.plugin;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.graphics.SurfaceTexture;
import android.opengl.*;
import android.view.Surface;
import android.widget.TextView;
import java.io.File;
import java.io.InputStream;
import java.io.FileOutputStream;
import java.util.concurrent.atomic.AtomicInteger;
import org.json.JSONObject;

/** Disposable emulator-only fixture; owns its files, context and decoder. */
public final class PerformanceFixtureActivity extends Activity {
  private TextView text;
  private void check(boolean value, String message) {
    if (!value)
      throw new IllegalStateException(message);
  }
  @Override
  public void onCreate(Bundle state) {
    super.onCreate(state);
    text = new TextView(this);
    text.setText("Running muted decoder fixture");
    setContentView(text);
    boolean reject = getIntent().getBooleanExtra("reject_hints", false);
    new Thread(() -> run(reject), "ImmivioFixtureGL").start();
  }
  private void run(boolean reject) {
    JSONObject report = new JSONObject();
    long handle = 0;
    EGLDisplay display = EGL14.EGL_NO_DISPLAY;
    EGLContext context = EGL14.EGL_NO_CONTEXT;
    EGLSurface window = EGL14.EGL_NO_SURFACE;
    Surface surface = null;
    SurfaceTexture texture = null;
    try {
      boolean silent = getIntent().getBooleanExtra("silent_high10", false);
      String nameOfMovie = silent ? "silent-high10.mp4" : "sample.mp4";
      File movie = new File(getFilesDir(), nameOfMovie);
      try (InputStream in = getAssets().open(nameOfMovie);
           FileOutputStream out = new FileOutputStream(movie)) {
        in.transferTo(out);
      }
      display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY);
      check(EGL14.eglInitialize(display, new int[2], 0, new int[2], 0), "EGL initialization");
      int[] attributes = {EGL14.EGL_SURFACE_TYPE,
                          EGL14.EGL_PBUFFER_BIT,
                          EGL14.EGL_RENDERABLE_TYPE,
                          0x40,
                          EGL14.EGL_RED_SIZE,
                          8,
                          EGL14.EGL_GREEN_SIZE,
                          8,
                          EGL14.EGL_BLUE_SIZE,
                          8,
                          EGL14.EGL_ALPHA_SIZE,
                          8,
                          EGL14.EGL_NONE};
      EGLConfig[] configs = new EGLConfig[1];
      int[] count = new int[1];
      check(EGL14.eglChooseConfig(display, attributes, 0, configs, 0, 1, count, 0) && count[0] > 0,
            "EGL config");
      context = EGL14.eglCreateContext(
          display, configs[0], EGL14.EGL_NO_CONTEXT,
          new int[] {EGL14.EGL_CONTEXT_CLIENT_VERSION, 3, EGL14.EGL_NONE}, 0);
      window = EGL14.eglCreatePbufferSurface(
          display, configs[0], new int[] {EGL14.EGL_WIDTH, 4, EGL14.EGL_HEIGHT, 4, EGL14.EGL_NONE},
          0);
      check(EGL14.eglMakeCurrent(display, window, window, context), "EGL owner context");
      int[] name = new int[1];
      GLES30.glGenTextures(1, name, 0);
      GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, name[0]);
      texture = new SurfaceTexture(name[0]);
      texture.setDefaultBufferSize(320, 180);
      AtomicInteger frames = new AtomicInteger();
      texture.setOnFrameAvailableListener(
          t -> frames.incrementAndGet(), new Handler(Looper.getMainLooper()));
      surface = new Surface(texture);
      check(MpvSourceNative.INSTANCE.supported(), "Native playback libraries loaded");
      MpvSourceNative.debugRejectHints(reject);
      handle = MpvSourceNative.create(this, movie.getAbsolutePath(), 0, true, true, 0,
                                      new String[0], new String[0], true, surface);
      check(handle > 0, "Source creation");
      check(MpvSourceNative.setAudio(handle, -1, 0, true), "Mute before playback");
      if (silent) {
        report.put("direct_surface", surfaceStartup(handle, texture, frames));
        check(closeSource(handle), "Silent video Surface source closed before reopening");
        handle = 0;
        handle = MpvSourceNative.create(this, movie.getAbsolutePath(), 0, true, true, 0,
                                        new String[0], new String[0], true, null);
        check(handle > 0, "Silent video opens without a decoder Surface");
        report.put("shader_frame", waitForFrame(handle)).put("passed", true);
        return;
      }
      SurfaceFrameProof proof = new SurfaceFrameProof();
      boolean early = getIntent().getBooleanExtra("early_play", false);
      boolean skipProof = getIntent().getBooleanExtra("skip_proof", false);
      if (!skipProof)
        proof.start(surface);
      if (early)
        MpvSourceNative.setPlaying(handle, true);
      long deadline = android.os.SystemClock.elapsedRealtime() + 8000;
      JSONObject status = new JSONObject();
      while (android.os.SystemClock.elapsedRealtime() < deadline) {
        status = new JSONObject(MpvSourceNative.status(handle));
        check(!status.optString("state").equals("failed"), status.toString());
        if (frames.get() > 0)
          texture.updateTexImage();
        if (status.optBoolean("surface_ready") && (skipProof ? frames.get() > 0 : proof.getReady()))
          break;
        Thread.sleep(10);
      }
      check(status.optBoolean("surface") && status.optBoolean("surface_ready") &&
                (skipProof ? frames.get() > 0 : proof.getReady()),
            "Paused startup delivers a real Surface buffer: " + status);
      report.put("paused_surface_buffer", !early);
      report.put("decoder", status.optJSONObject("details").optString("hwdec_current"));
      check(report.getString("decoder").contains("mediacodec"), "MediaCodec Surface decoder");
      long epoch = status.optLong("last_source_epoch");
      for (int step = 0; step < 6; ++step) {
        MpvSourceNative.setPlaying(handle, true);
        for (int i = 0; i < 12; ++i) {
          if (frames.get() > 0)
            texture.updateTexImage();
          Thread.sleep(10);
        }
        check(MpvSourceNative.seek(handle, step % 2 == 0 ? 300 : 600, true), "Seek request");
        long seekDeadline = android.os.SystemClock.elapsedRealtime() + 2500;
        do {
          if (frames.get() > 0)
            texture.updateTexImage();
          status = new JSONObject(MpvSourceNative.status(handle));
          check(!status.optString("state").equals("failed"), status.toString());
          if (status.optBoolean("surface_ready") && status.optLong("last_source_epoch") > epoch)
            break;
          Thread.sleep(10);
        } while (android.os.SystemClock.elapsedRealtime() < seekDeadline);
        check(status.optBoolean("surface_ready") && status.optLong("last_source_epoch") > epoch,
              "New seek epoch becomes ready");
        epoch = status.optLong("last_source_epoch");
        check(MpvSourceNative.setSpeed(handle, step % 2 == 0 ? 1.5 : 1.0), "Speed");
        MpvSourceNative.setPlaying(handle, false);
      }
      proof.cancel();
      report.put("surface_frames", frames.get());
      report.put("seek_epochs", epoch);
      report.put("reject_hints", reject);
      report.put("passed", true);
    } catch (Throwable error) {
      try {
        report.put("passed", false).put("error", error.toString());
      } catch (Exception ignored) {
      }
    } finally {
      if (handle > 0) {
        boolean closed = closeSource(handle);
        try {
          report.put("closed", closed);
          if (!closed)
            report.put("passed", false);
        } catch (Exception ignored) {
        }
      }
      try {
        MpvSourceNative.debugRejectHints(false);
      } catch (Throwable ignored) {
      }
      if (surface != null)
        surface.release();
      if (texture != null)
        texture.release();
      if (display != EGL14.EGL_NO_DISPLAY) {
        EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE,
                             EGL14.EGL_NO_CONTEXT);
        if (window != EGL14.EGL_NO_SURFACE)
          EGL14.eglDestroySurface(display, window);
        if (context != EGL14.EGL_NO_CONTEXT)
          EGL14.eglDestroyContext(display, context);
        EGL14.eglTerminate(display);
      }
      try (FileOutputStream out = new FileOutputStream(new File(getFilesDir(), "result.json"))) {
        out.write(report.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
      } catch (Exception ignored) {
      }
      String result = report.toString();
      runOnUiThread(() -> text.setText(result));
    }
  }

  private JSONObject surfaceStartup(long handle, SurfaceTexture texture, AtomicInteger frames)
      throws Exception {
    long deadline = android.os.SystemClock.elapsedRealtime() + 8000;
    do {
      JSONObject status = new JSONObject(MpvSourceNative.status(handle));
      if (status.optString("state").equals("failed"))
        return new JSONObject().put("state", "failed").put("error", status.optString("error"));
      if (frames.get() > 0) {
        texture.updateTexImage();
        if (status.optBoolean("surface_ready"))
          return new JSONObject().put("state", "ready");
      }
      Thread.sleep(10);
    } while (android.os.SystemClock.elapsedRealtime() < deadline);
    throw new IllegalStateException("Silent High 10 Surface neither presented a frame nor failed");
  }

  private JSONObject waitForFrame(long handle) throws Exception {
    long deadline = android.os.SystemClock.elapsedRealtime() + 8000;
    do {
      JSONObject status = new JSONObject(MpvSourceNative.status(handle));
      check(!status.optString("state").equals("failed"), status.toString());
      String acquired = MpvSourceNative.acquire(handle);
      if (!acquired.isEmpty()) {
        JSONObject frame = new JSONObject(acquired);
        check(MpvSourceNative.release(handle, frame.getLong("producer_token")), "Release frame");
        check(frame.getInt("width") == 320 && frame.getInt("height") == 180, "Silent video size");
        return new JSONObject()
            .put("width", frame.getInt("width"))
            .put("height", frame.getInt("height"))
            .put("decoder", status.getJSONObject("details").optString("hwdec_current"));
      }
      Thread.sleep(10);
    } while (android.os.SystemClock.elapsedRealtime() < deadline);
    throw new IllegalStateException("Silent High 10 shader path did not produce a frame");
  }

  private boolean closeSource(long handle) {
    MpvSourceNative.requestClose(handle);
    long deadline = android.os.SystemClock.elapsedRealtime() + 5000;
    do {
      if (MpvSourceNative.close(handle, false))
        return true;
      try {
        Thread.sleep(10);
      } catch (InterruptedException interrupted) {
        Thread.currentThread().interrupt();
        return false;
      }
    } while (android.os.SystemClock.elapsedRealtime() < deadline);
    return false;
  }
}
