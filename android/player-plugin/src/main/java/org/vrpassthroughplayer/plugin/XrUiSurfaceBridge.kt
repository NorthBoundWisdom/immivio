package org.vrpassthroughplayer.plugin

import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES30
import android.view.Surface
import androidx.annotation.Keep
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicInteger

/** GPU-only UI texture presentation into an OpenXR-owned Android Surface.
 * Godot keeps its ordinary viewport/texture ownership; XR owns the Surface.
 * JavaClassWrapper can pass the Surface without exposing a native pointer. */
@Keep
object XrUiSurfaceBridge {
    private data class Frame(val texture: Int, val width: Int, val height: Int, val generation: Int)
    private val generation = AtomicInteger(0)
    private val revision = AtomicInteger(0)
    @Volatile private var requestedSurface: Surface? = null
    @Volatile private var frame: Frame? = null
    @Volatile private var enabled = false
    @Volatile private var presentedRevision = -1
    @Volatile private var blits = 0L
    @Volatile private var copyCpuUs = 0L
    @Volatile private var copyMaxUs = 0L
    @Volatile private var failure = ""
    private var attachedRevision = -1
    private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var context: EGLContext = EGL14.EGL_NO_CONTEXT
    private var window: EGLSurface = EGL14.EGL_NO_SURFACE
    private var readFbo = 0

    @JvmStatic fun contextGeneration(): Int = generation.get()
    @JvmStatic fun attachSurface(surface: Surface?) {
        if (surface === requestedSurface) return
        requestedSurface = surface; frame = null; enabled = false
        presentedRevision = -1; failure = ""; revision.incrementAndGet()
    }
    @JvmStatic fun submitTexture(texture: Int, width: Int, height: Int, sourceGeneration: Int) {
        if (texture <= 0 || width !in 1..4096 || height !in 1..4096 || sourceGeneration != generation.get()) return
        frame = Frame(texture, width, height, sourceGeneration)
    }
    @JvmStatic fun setEnabled(value: Boolean) { enabled = value }
    @JvmStatic fun status(): String = JSONObject().put("generation", generation.get())
        .put("ready", presentedRevision == revision.get() && presentedRevision >= 0 && requestedSurface?.isValid == true)
        .put("enabled", enabled).put("surface", requestedSurface != null).put("frame_texture", frame?.texture ?: 0)
        .put("copy_cpu_us", copyCpuUs).put("copy_max_us", copyMaxUs)
        .put("blits", blits).put("error", failure).put("cpu_readback", false).toString()

    /** Render-thread context notification; never delete names owned by a lost context. */
    fun contextCreated() {
        enabled = false; frame = null; presentedRevision = -1
        generation.incrementAndGet()
        if (window != EGL14.EGL_NO_SURFACE && display != EGL14.EGL_NO_DISPLAY) EGL14.eglDestroySurface(display, window)
        window = EGL14.EGL_NO_SURFACE; display = EGL14.EGL_NO_DISPLAY; context = EGL14.EGL_NO_CONTEXT
        readFbo = 0; attachedRevision = -1
    }

    private fun releaseWindow() {
        if (window != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, window)
        if (readFbo != 0 && context == EGL14.eglGetCurrentContext()) GLES30.glDeleteFramebuffers(1, intArrayOf(readFbo), 0)
        window = EGL14.EGL_NO_SURFACE; readFbo = 0; attachedRevision = -1
    }

    private fun currentConfig(d: EGLDisplay, c: EGLContext): EGLConfig {
        val id = IntArray(1); check(EGL14.eglQueryContext(d, c, EGL14.EGL_CONFIG_ID, id, 0))
        val count = IntArray(1); check(EGL14.eglGetConfigs(d, null, 0, 0, count, 0))
        val configs = arrayOfNulls<EGLConfig>(count[0]); check(EGL14.eglGetConfigs(d, configs, 0, configs.size, count, 0))
        val value = IntArray(1)
        return configs.filterNotNull().first { EGL14.eglGetConfigAttrib(d, it, EGL14.EGL_CONFIG_ID, value, 0) && value[0] == id[0] }
    }

    /** Called after Godot draws, with its owner context current. No pixel readback. */
    fun draw() {
        val target = requestedSurface
        if (target == null) { if (window != EGL14.EGL_NO_SURFACE) releaseWindow(); return }
        val source = frame ?: return
        if (!enabled || source.generation != generation.get() || !target.isValid) return
        val currentDisplay = EGL14.eglGetCurrentDisplay()
        val currentContext = EGL14.eglGetCurrentContext()
        if (currentContext == EGL14.EGL_NO_CONTEXT) return
        val previousDraw = EGL14.eglGetCurrentSurface(EGL14.EGL_DRAW)
        val previousRead = EGL14.eglGetCurrentSurface(EGL14.EGL_READ)
        val bindings = IntArray(2)
        GLES30.glGetIntegerv(GLES30.GL_READ_FRAMEBUFFER_BINDING, bindings, 0)
        GLES30.glGetIntegerv(GLES30.GL_DRAW_FRAMEBUFFER_BINDING, bindings, 1)
        val scissor = GLES30.glIsEnabled(GLES30.GL_SCISSOR_TEST)
        val serial = revision.get()
        val started = System.nanoTime()
        try {
            if (attachedRevision != serial || context != currentContext) {
                releaseWindow()
                display = currentDisplay; context = currentContext
                window = EGL14.eglCreateWindowSurface(display, currentConfig(display, context), target, intArrayOf(EGL14.EGL_NONE), 0)
                check(window != EGL14.EGL_NO_SURFACE) { "UI_EGL_WINDOW_CREATE" }
                val names = IntArray(1); GLES30.glGenFramebuffers(1, names, 0); readFbo = names[0]
                attachedRevision = serial
            }
            check(GLES30.glIsTexture(source.texture)) { "UI_TEXTURE_UNAVAILABLE" }
            check(EGL14.eglMakeCurrent(display, window, window, context)) { "UI_EGL_MAKE_CURRENT" }
            EGL14.eglSwapInterval(display, 0)
            GLES30.glBindFramebuffer(GLES30.GL_READ_FRAMEBUFFER, readFbo)
            GLES30.glFramebufferTexture2D(GLES30.GL_READ_FRAMEBUFFER, GLES30.GL_COLOR_ATTACHMENT0, GLES30.GL_TEXTURE_2D, source.texture, 0)
            check(GLES30.glCheckFramebufferStatus(GLES30.GL_READ_FRAMEBUFFER) == GLES30.GL_FRAMEBUFFER_COMPLETE) { "UI_READ_FRAMEBUFFER" }
            GLES30.glBindFramebuffer(GLES30.GL_DRAW_FRAMEBUFFER, 0)
            GLES30.glDisable(GLES30.GL_SCISSOR_TEST)
            // Ordinary Godot GLES viewports are rendered upside down (their texture
            // UV origin is top-left). EGL window buffers use bottom-left: flip
            // once while copying, before Android/XR consumes the Surface.
            GLES30.glBlitFramebuffer(0, source.height, source.width, 0, 0, 0, source.width, source.height,
                GLES30.GL_COLOR_BUFFER_BIT, GLES30.GL_NEAREST)
            val error = GLES30.glGetError(); check(error == GLES30.GL_NO_ERROR) { "UI_BLIT_GL_$error" }
            check(EGL14.eglSwapBuffers(display, window)) { "UI_EGL_SWAP" }
            val elapsed = (System.nanoTime() - started) / 1000L
            copyCpuUs += elapsed; copyMaxUs = maxOf(copyMaxUs, elapsed)
            blits++; presentedRevision = serial; failure = ""
        } catch (error: Exception) {
            failure = error.message?.takeIf { it.startsWith("UI_") } ?: "UI_SURFACE_PRESENT_FAILED"
            presentedRevision = -1
        } finally {
            EGL14.eglMakeCurrent(currentDisplay, previousDraw, previousRead, currentContext)
            GLES30.glBindFramebuffer(GLES30.GL_READ_FRAMEBUFFER, bindings[0])
            GLES30.glBindFramebuffer(GLES30.GL_DRAW_FRAMEBUFFER, bindings[1])
            if (scissor) GLES30.glEnable(GLES30.GL_SCISSOR_TEST) else GLES30.glDisable(GLES30.GL_SCISSOR_TEST)
        }
    }
}
