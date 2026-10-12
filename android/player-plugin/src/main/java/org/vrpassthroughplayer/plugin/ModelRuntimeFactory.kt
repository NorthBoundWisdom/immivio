package org.vrpassthroughplayer.plugin

import android.content.res.AssetManager

/** Production task entry point. The build-selected pack currently admits only the
 * MNN RVM adapter; effect queues do not construct its concrete session themselves.
 * Other tensor contracts/backends need an explicit adapter before being admitted.
 */
internal object ModelRuntimeFactory {
    fun matting(assets: AssetManager, profile: String, sessionId: Long, generation: Long): MattingRuntime =
        RvmRuntime.prepare(assets, true, profile, sessionId, generation)
}
