package org.vrpassthroughplayer.plugin

import android.content.res.AssetManager
import java.util.WeakHashMap
import java.lang.ref.WeakReference

/** Model source for this phase: a build-selected, verified APK asset pack.
 * Weak references avoid retaining a destroyed host's AssetManager through the opener.
 */
internal object BundledModels {
    private val repositories = WeakHashMap<AssetManager, ModelRepository>()
    fun resolve(assets: AssetManager, task: ModelTask): ModelDescriptor {
        check(BuildConfig.ENABLE_AI) { "AI_DISABLED" }
        val repository = synchronized(repositories) {
            repositories.getOrPut(assets) {
                val owner = WeakReference(assets)
                ModelRepository { path -> checkNotNull(owner.get()) { "Model assets released" }.open(path) }
            }
        }
        return repository.resolve(task)
    }
}
