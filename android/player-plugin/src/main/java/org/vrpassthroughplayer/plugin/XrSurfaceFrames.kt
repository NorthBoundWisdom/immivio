package org.vrpassthroughplayer.plugin

import java.util.concurrent.atomic.AtomicInteger

/** UI capture ownership and successful-copy acknowledgement, independent of EGL resources. */
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
    @Volatile private var presented: Frame? = null

    fun contextGeneration(): Int = generation.get()

    fun current(): Frame? = frame

    /** An Android Surface retains its last buffer; unchanged captures need no new blit. */
    fun pending(): Frame? = frame?.takeUnless { it == presented }

    fun acknowledge(source: Frame) {
        if (source.generation == generation.get()) presented = source
    }

    fun clear() {
        frame = null
        presented = null
    }

    fun contextCreated() {
        clear()
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
