package org.vrpassthroughplayer.plugin

import android.opengl.EGLContext
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/** Decoder lifetime and playback controls, distinct from each presentation generation. */
internal class PlaybackHost(
    val uri: String,
    val startMs: Int,
    val hardware: Boolean,
    val audio: Boolean,
    val exactStart: Boolean,
    releaseNetwork: (String) -> Unit
) {
    private val openNs = System.nanoTime()
    val startup = ConcurrentHashMap<String, Double>()
    fun markStartup(stage: String) {
        startup.putIfAbsent(stage, (System.nanoTime() - openNs) / 1_000_000.0)
    }

    @Volatile
    var handle = 0L
    @Volatile
    var owner: EGLContext? = null
    @Volatile
    var closing = false
    @Volatile
    var playing = true
    var speed = 1.0 // synchronized(host), retained across processing revisions
    var subtitleMs = 0
    var audioMs = 0
    val importingSubtitle = AtomicBoolean(false)
    @Volatile
    var audioEnabled = audio
    @Volatile
    var audioAvailable = audio
    val resources = PlaybackSourceResources(releaseNetwork)
    fun closeDescriptors() = synchronized(this) { resources.close() }
    @Volatile
    var subtitleCommand = 0L
    var nextStatusNs = 0L // GL only
}
