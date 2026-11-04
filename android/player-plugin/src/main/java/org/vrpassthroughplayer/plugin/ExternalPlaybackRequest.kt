package org.vrpassthroughplayer.plugin

import java.io.File
import java.net.URI

/** Narrow, transient contract adapted from Thru3D 0.16.5. Never log the request. */
internal class ExternalPlaybackRequest private constructor(val uri: String, val title: String, val scheme: String) {
    companion object {
        fun parse(action: String?, raw: String?, title: String?, mime: String?, readGranted: Boolean,
                  privateRoots: List<File> = emptyList()): ExternalPlaybackRequest {
            require(action in setOf("android.intent.action.VIEW", "android.intent.action.SEND"))
            require(raw != null && raw.length in 1..8192 && raw.none { it.isISOControl() })
            val uri = URI(raw)
            require(uri.scheme in setOf("file", "content", "http", "https") && uri.rawUserInfo == null && uri.fragment == null)
            require(if (uri.scheme in setOf("http", "https")) mime?.startsWith("video/") == true
                else mime.isNullOrEmpty() || mime.startsWith("video/") || mime == "application/octet-stream")
            when (uri.scheme) {
                "content" -> require(readGranted && !uri.rawAuthority.isNullOrBlank() && !uri.rawPath.isNullOrBlank())
                "file" -> {
                    require(uri.rawAuthority.isNullOrEmpty() && uri.query == null && uri.path.startsWith('/'))
                    val path = File(uri).canonicalFile.toPath()
                    require(privateRoots.none { path.startsWith(it.canonicalFile.toPath()) })
                }
                else -> require(!uri.host.isNullOrBlank() && uri.port in -1..65535)
            }
            val name = title.orEmpty().filterNot { it.isISOControl() }.take(256).takeUnless { it.contains("://") }.orEmpty()
            return ExternalPlaybackRequest(raw, name.ifBlank { "Video" }, uri.scheme)
        }
    }
    override fun toString() = "ExternalPlaybackRequest(scheme=$scheme)"
}

/** Own at most four leases, one pending delivery, and no persistent URI rights. */
internal class ExternalPlaybackLeases(private val clock: () -> Long = { System.nanoTime() / 1_000_000 }) {
    private class Lease(val title: String, val target: String, val origin: String, val cleanup: () -> Unit, val created: Long, var claimed: Boolean = false)
    private val leases = LinkedHashMap<String, Lease>()
    private var pending = ""
    fun offer(title: String, target: String, cleanup: () -> Unit): String = offerOrigin(title, target, "", cleanup)
    @Synchronized fun offerOrigin(title: String, target: String, origin: String, cleanup: () -> Unit): String {
        release(pending)
        leases.keys.toList().filter { !leases.getValue(it).claimed && clock() - leases.getValue(it).created > 60000 }.forEach(::release)
        if (leases.size >= 4) { cleanup(); error("External playback busy") }
        val key = "externalvideo://${java.util.UUID.randomUUID()}/video"
        leases[key] = Lease(title, target, origin, cleanup, clock()); pending = key
        return key
    }
    @Synchronized fun claim(): Pair<String, String>? {
        val key = pending; pending = ""
        val lease = leases[key] ?: return null
        if (clock() - lease.created !in 0..60000) { release(key); return null }
        lease.claimed = true
        return key to lease.title
    }
    @Synchronized fun target(uri: String): String = leases[uri]?.takeIf { it.claimed }?.target ?: error("External playback expired")
    @Synchronized fun release(uri: String) {
        if (pending == uri) pending = ""
        leases.remove(uri)?.let { runCatching { it.cleanup() } }
    }
    @Synchronized fun belongsTo(uri: String, root: String, uuid: String): Boolean {
        val origin = leases[uri]?.origin ?: return false
        val parsed = runCatching { URI(origin) }.getOrNull() ?: return false
        if (parsed.scheme == "file") return UsbAccessPolicy.inside(root, parsed.path)
        if (parsed.scheme == "content" && parsed.authority == "com.android.externalstorage.documents" && uuid.isNotEmpty()) {
            val path = parsed.path.orEmpty()
            for (marker in listOf("/document/", "/tree/")) {
                if (path.contains(marker)) return path.substringAfter(marker).substringBefore(':').equals(uuid, true)
            }
        }
        return false
    }
    @Synchronized fun expire() { leases.keys.toList().filter { !leases.getValue(it).claimed && clock() - leases.getValue(it).created >= 60000 }.forEach(::release) }
    @Synchronized fun close() { leases.keys.toList().forEach(::release) }
}
