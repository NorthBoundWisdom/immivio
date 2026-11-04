package org.vrpassthroughplayer.plugin

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Validate before launching Godot. The ingress Activity owns temporary grants until FD handoff. */
class ExternalPlaybackActivity : Activity() {
    private val finished = AtomicBoolean(false)
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable { reject() }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState != null) { finish(); return }
        try {
            val app = applicationContext
            val roots = listOfNotNull(app.dataDir, app.createDeviceProtectedStorageContext().dataDir) +
                app.getExternalFilesDirs(null).filterNotNull() + app.externalCacheDirs.filterNotNull()
            val request = ExternalPlaybackIntentReader.read(intent, roots)
            if (request.scheme == "content") {
                val provider = packageManager.resolveContentProvider(Uri.parse(request.uri).authority!!, 0)
                require(provider != null && provider.applicationInfo.uid != applicationInfo.uid)
            }
            setContentView(android.widget.ProgressBar(this))
            handler.postDelayed(timeout, 8000)
            worker.execute { prepare(request) }
        } catch (_: Exception) { reject() }
    }
    private fun prepare(request: ExternalPlaybackRequest) {
        var cleanup: () -> Unit = {}
        try {
            var name = request.title
            var target = request.uri
            val origin = request.uri
            if (request.scheme in setOf("content", "file")) {
                val uri = Uri.parse(request.uri)
                val descriptor = if (request.scheme == "content") {
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                        if (it.moveToFirst()) name = it.getString(0).orEmpty().filterNot(Char::isISOControl).take(256)
                    }
                    contentResolver.openFileDescriptor(uri, "r") ?: error("Provider unavailable")
                } else {
                    val file = File(java.net.URI(request.uri))
                    if (name == "Video") name = file.name.take(256)
                    ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                }
                cleanup = { descriptor.close() }
                if (request.scheme == "file") {
                    // Check the opened descriptor, closing the symlink race after URI validation.
                    val real = android.system.Os.readlink("/proc/self/fd/${descriptor.fd}")
                    val app = applicationContext
                    ExternalPlaybackRequest.parse(Intent.ACTION_VIEW, Uri.fromFile(File(real)).toString(), name, null, false,
                        listOfNotNull(app.dataDir, app.createDeviceProtectedStorageContext().dataDir) + app.getExternalFilesDirs(null).filterNotNull() + app.externalCacheDirs.filterNotNull())
                }
                if (StrmFile.named(name)) {
                    val bytes = ParcelFileDescriptor.AutoCloseInputStream(descriptor).use(StrmFile::read)
                    // Opaque document URIs cannot provide a relative directory identity.
                    val resolved = StrmFile.target(request.uri, StrmFile.parse(bytes))
                    val copy = File.createTempFile("external-", ".strm", cacheDir)
                    cleanup = { copy.delete(); Unit }
                    copy.writeText(resolved + "\n", Charsets.UTF_8)
                    target = Uri.fromFile(copy).toString()
                } else target = "fd://${descriptor.fd}"
            }
            val owned = cleanup
            runOnUiThread {
                if (!finished.compareAndSet(false, true)) { owned(); return@runOnUiThread }
                handler.removeCallbacks(timeout)
                var key = ""
                try {
                    key = ExternalPlaybackPending.offer(name.ifBlank { "Video" }, target, origin, owned)
                    startActivity(ImmivioLauncherActivity.playerIntent(this))
                } catch (_: Exception) {
                    if (key.isNotEmpty()) ExternalPlaybackPending.leases.release(key) else owned()
                } finally { finish() }
            }
        } catch (_: Exception) { runCatching { cleanup() }; runOnUiThread { reject() } }
    }
    private fun reject() {
        if (finished.compareAndSet(false, true)) {
            handler.removeCallbacks(timeout)
            android.widget.Toast.makeText(this, UiLanguage.tr(this, "External video unavailable", "无法打开外部视频"), android.widget.Toast.LENGTH_SHORT).show()
            finish()
        }
    }
    override fun onDestroy() {
        finished.set(true); handler.removeCallbacks(timeout); super.onDestroy()
    }
    companion object {
        private val worker = ThreadPoolExecutor(1, 1, 0, TimeUnit.MILLISECONDS, ArrayBlockingQueue(1),
            { Thread(it, "ImmivioExternalInput").apply { isDaemon = true } })
    }
}
internal object ExternalPlaybackPending {
    val leases = ExternalPlaybackLeases()
    private val handler = Handler(Looper.getMainLooper())
    private val expiry = Runnable { leases.expire() }
    @Synchronized fun offer(title: String, target: String, origin: String, cleanup: () -> Unit): String {
        val key = leases.offerOrigin(title, target, origin, cleanup)
        handler.removeCallbacks(expiry); handler.postDelayed(expiry, 60000)
        return key
    }
    fun poll(): String = leases.claim()?.let { (uri, title) -> JSONObject().put("uri", uri).put("title", title).toString() } ?: "{}"
}
