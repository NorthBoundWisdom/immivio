package org.vrpassthroughplayer.plugin

import android.content.res.AssetManager
import java.nio.ByteBuffer

/** Realtime 2D->3D depth (Depth Anything V2 Small, MNN OpenCL) in libquest_rvm. Not thread-safe per handle. */
internal object DepthNative {
    // Loads libquest_rvm on first use of this object.
    val unavailable: String? = RvmNative.unavailable
    /** Compiled-program cache this model uses under [cacheDirectory]. */
    fun cachePath(assets: AssetManager, cacheDirectory: String?): String {
        // A readiness query may run on the UI thread; verification happens at create.
        return modelCachePath(assets, cacheDirectory)
    }
    @JvmStatic private external fun modelCachePath(assets: AssetManager, cacheDirectory: String?): String
    /** Builds the OpenCL session (a cold cache compiles for tens of seconds). */
    fun create(assets: AssetManager, cacheDirectory: String?): Long {
        BundledModels.resolve(assets, ModelTask.VIDEO_DEPTH)
        return createModel(assets, cacheDirectory)
    }
    @JvmStatic private external fun createModel(assets: AssetManager, cacheDirectory: String?): Long
    /** Independent still-photo model, same shared worker but separate compiled-program cache. */
    fun createPhoto(assets: AssetManager, cacheDirectory: String?): Long {
        BundledModels.resolve(assets, ModelTask.PHOTO_DEPTH)
        return createPhotoModel(assets, cacheDirectory)
    }
    @JvmStatic private external fun createPhotoModel(assets: AssetManager, cacheDirectory: String?): Long
    /** {"width","height","prepare_ms","gpu_ops","cpu_fallback_ops"} */
    @JvmStatic external fun describe(handle: Long): String
    /** rgb float32 CHW [0,1] -> near float32 HxW [0,1] (1 = nearest). reset restarts the shot's depth band. */
    @JvmStatic external fun process(handle: Long, rgb: ByteBuffer, near: ByteBuffer, reset: Boolean, frameStep: Int): String
    /** No temporal history; padding outside the content rectangle never contributes to near depth. */
    @JvmStatic external fun processPhoto(handle: Long, rgb: ByteBuffer, near: ByteBuffer, x: Int, y: Int, width: Int, height: Int): String
    @JvmStatic external fun close(handle: Long)

    /** Model input: 16:9 multiples of the 14 px patch, fixed in the converted graph (tools/models/prepare_depth_mnn.py). */
    const val PROFILE = "252x140"
}
