package org.vrpassthroughplayer.plugin

import android.view.Surface

/** Godot owns OpenXR and calls these only on its render thread. */
internal object VideoLayerNative {
    val loaded =
        try {
            System.loadLibrary("immivio_video_layer")
            true
        } catch (_: UnsatisfiedLinkError) {
            false
        }

    @JvmStatic external fun requestReadback(texture: Int, width: Int, height: Int): Long

    @JvmStatic external fun pollReadback(token: Long): ByteArray

    @JvmStatic external fun cancelReadback(token: Long)

    @JvmStatic
    external fun bind(instance: Long, session: Long, getProcAddr: Long, space: Long): Boolean

    @JvmStatic external fun createSurface(width: Int, height: Int): Surface

    @JvmStatic external fun destroySurface()

    @JvmStatic external fun invalidate()

    @JvmStatic external fun limits(): String

    @JvmStatic external fun createImage(width: Int, height: Int): Boolean

    @JvmStatic
    external fun drawImage(texture: Int, fisheye: Boolean, parameters: FloatArray): Boolean

    @JvmStatic external fun destroyImage()

    @JvmStatic external fun setLayers(count: Int, values: FloatArray): Boolean

    @JvmStatic external fun layerAddress(index: Int): Long
}
