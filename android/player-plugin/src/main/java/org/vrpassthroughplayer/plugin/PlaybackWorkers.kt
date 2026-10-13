package org.vrpassthroughplayer.plugin

import android.os.Handler
import android.os.HandlerThread

/** Process-owned workers; sessions retain no Activity through the handlers. */
internal object PlaybackWorkers {
    val video: Handler by lazy { Handler(HandlerThread("ImmivioVideo").apply { start() }.looper) }
    val subtitles: Handler by lazy { Handler(HandlerThread("ImmivioSubtitles").apply { start() }.looper) }
}
