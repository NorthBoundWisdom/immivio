package org.vrpassthroughplayer.plugin

import android.opengl.*

internal class OffscreenGlOwner {
    val display: EGLDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
    var context: EGLContext = EGL14.EGL_NO_CONTEXT
    var surface: EGLSurface = EGL14.EGL_NO_SURFACE
    fun start() {
        check(display != EGL14.EGL_NO_DISPLAY)
        val version = IntArray(2); check(EGL14.eglInitialize(display, version, 0, version, 1))
        check(EGL14.eglBindAPI(EGL14.EGL_OPENGL_ES_API))
        val attributes = intArrayOf(
            EGL14.EGL_RENDERABLE_TYPE,
            0x40,
            EGL14.EGL_SURFACE_TYPE,
            EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_RED_SIZE,
            8,
            EGL14.EGL_GREEN_SIZE,
            8,
            EGL14.EGL_BLUE_SIZE,
            8,
            EGL14.EGL_ALPHA_SIZE,
            8,
            EGL14.EGL_NONE
        )
        val configs = arrayOfNulls<EGLConfig>(1);
        val count = IntArray(1)
        check(
            EGL14.eglChooseConfig(
                display,
                attributes,
                0,
                configs,
                0,
                1,
                count,
                0
            ) && count[0] == 1
        )
        context = EGL14.eglCreateContext(
            display, configs[0], EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 3, EGL14.EGL_NONE), 0
        )
        check(context != EGL14.EGL_NO_CONTEXT)
        surface = EGL14.eglCreatePbufferSurface(
            display,
            configs[0],
            intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE),
            0
        )
        check(
            surface != EGL14.EGL_NO_SURFACE && EGL14.eglMakeCurrent(
                display,
                surface,
                surface,
                context
            )
        )
    }

    fun close(): Boolean {
        var ok = EGL14.eglMakeCurrent(
            display,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_CONTEXT
        )
        if (surface != EGL14.EGL_NO_SURFACE) {
            ok = EGL14.eglDestroySurface(display, surface) && ok; surface = EGL14.EGL_NO_SURFACE
        }
        if (context != EGL14.EGL_NO_CONTEXT) {
            ok = EGL14.eglDestroyContext(display, context) && ok; context = EGL14.EGL_NO_CONTEXT
        }
        return EGL14.eglReleaseThread() && ok // Never terminate Godot's process-global display.
    }
}
