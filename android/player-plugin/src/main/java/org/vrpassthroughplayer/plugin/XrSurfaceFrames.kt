package org.vrpassthroughplayer.plugin

import java.util.concurrent.atomic.AtomicInteger

/** Frame ownership shared by the UI and each eye presenter, independent of EGL resources. */
internal class XrSurfaceFrames {
    data class Frame(
        val texture: Int,
        val width: Int,
        val height: Int,
        val generation: Int,
        val serial: Long,
    )

    private val generation = AtomicInteger(0)
    @Volatile private var frame: Frame? = null

    fun contextGeneration(): Int = generation.get()

    fun current(): Frame? = frame

    fun clear() {
        frame = null
    }

    fun contextCreated() {
        frame = null
        generation.incrementAndGet()
    }

    fun submit(texture: Int, width: Int, height: Int, sourceGeneration: Int, serial: Long) {
        if (
            texture <= 0 ||
                width !in 1..4096 ||
                height !in 1..4096 ||
                sourceGeneration != generation.get()
        )
            return
        frame = Frame(texture, width, height, sourceGeneration, serial)
    }
}
