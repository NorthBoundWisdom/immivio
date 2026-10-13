package org.vrpassthroughplayer.plugin

import java.nio.ByteBuffer

/** Owner-thread GPU color/mask leases and frozen transition frames. */
internal object RenderBridgeNative {
    init { System.loadLibrary("quest_render_bridge") }
    fun create(width: Int, height: Int, inputWidth: Int, inputHeight: Int, stereo: Boolean, topBottom: Boolean = false): Long =
        createLayout(width, height, inputWidth, inputHeight, if (!stereo) 0 else if (topBottom) 2 else 1)
    @JvmStatic external fun createLayout(width: Int, height: Int, inputWidth: Int, inputHeight: Int, layout: Int): Long
    @JvmStatic external fun captureTexture(handle: Long, texture: Int): Long
    @JvmStatic external fun captureOpaqueTexture(handle: Long, texture: Int): Long
    @JvmStatic external fun stats(handle: Long): String
    @JvmStatic external fun ready(handle: Long, token: Long): Boolean
    @JvmStatic external fun texture(handle: Long, token: Long): Int
    @JvmStatic external fun enableBorrowedColor(handle: Long): Boolean
    @JvmStatic external fun colorImage(handle: Long, token: Long): Long
    @JvmStatic external fun freezePair(handle: Long, token: Long, warped: Boolean): LongArray
    @JvmStatic external fun releaseFrozen(handle: Long)
    @JvmStatic external fun uploadAlpha(handle: Long, token: Long, left: ByteBuffer, right: ByteBuffer): Boolean
    @JvmStatic external fun alphaReady(handle: Long, token: Long): Boolean
    @JvmStatic external fun alphaTexture(handle: Long, token: Long): Int
    @JvmStatic external fun readAlpha(handle: Long, token: Long, output: ByteBuffer): Boolean
    @JvmStatic external fun retire(handle: Long, token: Long)
    @JvmStatic external fun retired(handle: Long, token: Long): Boolean
    @JvmStatic external fun close(handle: Long)
    @JvmStatic external fun abandon(handle: Long)
}
