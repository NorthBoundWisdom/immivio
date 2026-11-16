package org.vrpassthroughplayer.plugin

import android.graphics.Bitmap
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.view.PixelCopy
import android.view.Surface

/** One tiny asynchronous startup check; no repeating playback readback. */
internal class SurfaceFrameProof {
    @Volatile
    var ready = false
        private set

    @Volatile
    var timedOut = false
        private set

    @Volatile private var cancelled = false
    private var started = 0L

    companion object {
        private val callbacks by lazy {
            Handler(HandlerThread("ImmivioSurfaceProof").apply { start() }.looper)
        }
    }

    fun start(surface: Surface) {
        if (cancelled || started > 0L) return
        started = SystemClock.elapsedRealtime()
        request(surface)
    }

    private fun request(surface: Surface) {
        if (cancelled) return
        if (SystemClock.elapsedRealtime() - started > 2500) {
            timedOut = true
            return
        }
        val bitmap = Bitmap.createBitmap(8, 8, Bitmap.Config.ARGB_8888)
        try {
            PixelCopy.request(
                surface,
                bitmap,
                { result ->
                    bitmap.recycle()
                    if (!cancelled) {
                        if (result == PixelCopy.SUCCESS) ready = true
                        else callbacks.postDelayed({ request(surface) }, 100)
                    }
                },
                callbacks,
            )
        } catch (_: Exception) {
            bitmap.recycle()
            if (!cancelled) callbacks.postDelayed({ request(surface) }, 100)
        }
    }

    fun cancel() {
        cancelled = true
    }
}
