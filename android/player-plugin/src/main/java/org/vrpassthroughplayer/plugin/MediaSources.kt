package org.vrpassthroughplayer.plugin

import android.app.Activity
import android.content.Context
import android.net.wifi.WifiManager
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/** Library sources for the in-headset menu: local MediaStore, DLNA servers and SMB shares.
 * Every request returns an id at once; the result arrives as media_list(id, json) with
 * {source, state: ready|error|denied, entries|servers, error}. */
internal class MediaSources(
    private val host: () -> Activity?,
    private val emit: (Int, String) -> Unit,
) {
    private val ids = AtomicInteger()
    private val network = Executors.newSingleThreadExecutor { Thread(it, "QuestMediaNetwork") }
    private val local = LocalVideoLibrary(host, emit)
    @Volatile
    private var fileManagementEnabled = false
    fun setFileManagement(enabled: Boolean) {
        fileManagementEnabled = enabled
        local.setFileManagement(enabled)
    }

    private val dlna by lazy {
        val prefs = (context() ?: error("Activity unavailable")).getSharedPreferences(
            "dlna_sources",
            Context.MODE_PRIVATE
        )
        DlnaLibrary(
            { prefs.getString("catalog", "").orEmpty() },
            {
                check(
                    prefs.edit().putString("catalog", it).commit()
                ) { "Could not save DLNA server" }
            })
    }
    @Volatile
    private var server: LocalStreamServer? = null
    private val smb by lazy { SmbLibrary(context() ?: error("Activity unavailable")) { streams() } }
    private val mediaServers = MediaServerLibrary(::context, ::streams, ::nextId, emit = emit)
    fun serverRequest(json: String): Int = mediaServers.request(json)
    fun serverCancel(id: Int) = mediaServers.cancel(id)
    fun releaseMediaStream(uri: String) {
        mediaServers.release(uri)
        server?.revoke(uri)
    }

    private fun context(): Context? = host()?.applicationContext
    @Synchronized
    fun streams(): LocalStreamServer = server ?: LocalStreamServer().also { server = it }

    fun releasePhotoStream(uri: String) {
        if (uri.isNotEmpty()) server?.revoke(uri)
    }

    fun nextId(): Int = ids.incrementAndGet()

    /** Main thread: may show the media permission request. path "" lists the storage volumes. */
    fun browseLocal(id: Int, path: String) = local.browse(id, path)

    /** Main thread: requests legacy read access or opens settings, emitting local_access events. */
    fun grantAllFiles() = local.grantAllFiles()
    fun refreshLocalStorage() = local.refreshStorage()
    fun openLocalEjectSettings(id: Int, path: String) = local.openEjectSettings(id, path)
    fun onPermissionResult(requestCode: Int, granted: Boolean) =
        local.onPermissionResult(requestCode, granted)

    @Volatile
    private var stopped = false
    init {
        DlnaClient.log = { android.util.Log.i("QuestDlna", it) }
    }

    fun dlnaDiscover(): Int = run("dlna") {
        val lock =
            (context()?.getSystemService(Context.WIFI_SERVICE) as? WifiManager)?.createMulticastLock(
                "QuestDlna"
            )
        lock?.setReferenceCounted(false)
        runCatching { lock?.acquire() }
        try {
            JSONObject().put("servers", dlna.refresh())
        } finally {
            if (lock?.isHeld == true) lock.release()
        }
    }

    fun dlnaServers(): Int = run("dlna") { JSONObject().put("servers", dlna.servers()) }
    fun dlnaSave(json: String): Int = run("dlna") {
        JSONObject().put("saved_id", dlna.save(JSONObject(json))).put("servers", dlna.servers())
    }

    fun dlnaRemove(id: String): Int =
        run("dlna") { dlna.remove(id); JSONObject().put("servers", dlna.servers()) }

    fun dlnaBrowse(serverId: String, objectId: String): Int = run("dlna") {
        JSONObject().put("server_id", serverId).put("object_id", objectId)
            .put("entries", dlna.browse(serverId, objectId.ifEmpty { "0" }))
    }

    fun smbServers(): Int = run("smb") { JSONObject().put("servers", smb.serversJson()) }
    fun smbDiscover(): Int = run("smb") {
        // WS-Discovery answers arrive as multicast-addressed traffic too; Wi-Fi drops it without the lock.
        val lock =
            (context()?.getSystemService(Context.WIFI_SERVICE) as? WifiManager)?.createMulticastLock(
                "QuestSmb"
            )
        lock?.setReferenceCounted(false); lock?.acquire()
        try {
            JSONObject().put("discovered", smb.discover())
        } finally {
            lock?.release()
        }
    }

    fun smbSave(request: String): Int = run("smb") {
        JSONObject().put("saved_id", smb.save(JSONObject(request)))
            .put("servers", smb.serversJson())
    }

    fun smbRemove(id: String): Int =
        run("smb") { smb.remove(id); JSONObject().put("servers", smb.serversJson()) }

    fun smbBrowse(serverId: String, path: String): Int = run("smb") {
        JSONObject().put("server_id", serverId).put("path", path)
            .put("entries", smb.browse(serverId, path))
    }

    fun renameFile(json: String, prepare: Boolean): Int {
        val id = nextId()
        network.execute {
            var request = JSONObject()
            val result = try {
                request = JSONObject(json)
                val uri = request.getString("uri")
                check(fileManagementEnabled) { "File management is off" }
                val result = when {
                    uri.startsWith("file://") -> local.renameFile(request, prepare)
                    uri.startsWith("smb://") -> smb.renameFile(request, prepare)
                    else -> error("File deletion unavailable for this source")
                }
                if (!result.has("state")) result.put("state", "ready") else result
            } catch (error: Exception) {
                JSONObject().put("state", "error")
                    .put("error", error.message ?: "Rename failed; check the folder")
            }
            if (!stopped) emit(
                id,
                result.put("source", "file_rename").put("uri", request.optString("uri"))
                    .put("prepare", prepare).toString()
            )
        }
        return id
    }

    fun deleteFile(json: String, inspect: Boolean = false, prepare: Boolean = false): Int {
        val id = nextId()
        network.execute {
            var request = JSONObject()
            var sent = false
            val result = try {
                request = JSONObject(json)
                val uri = request.getString("uri")
                require(uri.startsWith("file://") || uri.startsWith("smb://"))
                if (!inspect) check(fileManagementEnabled) { "File management is off" }
                sent = !inspect && !prepare
                val result = when {
                    uri.startsWith("file://") -> local.deleteFile(request, inspect, prepare)
                    uri.startsWith("smb://") -> smb.deleteFile(request, inspect, prepare)
                    else -> error("File deletion unavailable for this source")
                }
                if (!result.has("state")) result.put("state", "ready") else result
            } catch (error: Exception) {
                // A transport error after dispatch is ambiguous. Never silently resend a delete.
                val smbError = error as? org.codelibs.jcifs.smb.impl.SmbException
                val definite =
                    error.message != "Delete result needs checking" && (error is IllegalArgumentException || error is IllegalStateException || error is android.system.ErrnoException ||
                            smbError?.ntStatus in setOf(
                        0xC0000022.toInt(),
                        0xC0000043.toInt(),
                        0xC0000121.toInt(),
                        0xC00000BA.toInt()
                    ))
                JSONObject().put("state", if (sent && !definite) "uncertain" else "error")
                    .put(
                        "error",
                        if (smbError != null && definite) "File deletion permission denied" else if (definite) error.message
                            ?: "File deletion failed" else "Delete result needs checking"
                    )
            }
            if (!stopped) emit(
                id,
                result.put("source", "file_delete").put("uri", request.optString("uri"))
                    .put("inspect", inspect).toString()
            )
        }
        return id
    }

    /** MPV-playable location for a library URI; blocks (SMB connects). Worker threads only. */
    fun playable(uri: String): String = when {
        uri.startsWith("medialib://") -> mediaServers.playable(uri)
        uri.startsWith("smb://") -> smb.stream(uri)
        else -> uri
    }

    /** Extra M4A tracks beside a video (clone voice first). Local files, the MediaStore library and
     * SMB; DLNA servers expose no sibling files. Blocks; worker threads only. Never throws. */
    fun sidecarAudio(uri: String): List<SidecarAudio.Track> = try {
        val source = android.net.Uri.parse(uri)
        when (source.scheme) {
            "file" -> source.path?.let { SidecarAudio.forFile(it) } ?: emptyList()
            "content" -> context()?.let { SidecarAudio.forMediaStore(it, source) } ?: emptyList()
            "smb" -> smb.sidecarAudio(uri)
            "medialib" -> mediaServers.sidecarAudio(uri)
            else -> emptyList()
        }
    } catch (error: Throwable) {
        android.util.Log.w(
            "QuestSidecarAudio",
            "Sidecar audio lookup failed: ${error.javaClass.simpleName}"
        )
        emptyList()
    }

    fun sidecarSubtitles(uri: String): List<SidecarSubtitles.Track> = try {
        when {
            uri.startsWith("smb://") -> smb.sidecarSubtitles(uri)
            uri.startsWith("medialib://") -> mediaServers.sidecarSubtitles(uri)
            uri.startsWith("http://") || uri.startsWith("https://") -> SidecarSubtitles.forDlna(
                dlna.subtitles(
                    uri
                )
            ) { source, name -> streams().publish(source, name) }

            else -> emptyList()
        }
    } catch (error: Exception) {
        android.util.Log.w(
            "QuestSubtitles",
            "Network subtitle lookup failed: ${error.javaClass.simpleName}"
        )
        emptyList()
    }

    private fun run(source: String, block: () -> JSONObject): Int {
        val id = ids.incrementAndGet()
        network.execute {
            val result = try {
                block().put("state", "ready")
            } catch (error: Throwable) {
                JSONObject().put("state", "error")
                    .put("error", error.message ?: error.javaClass.simpleName)
            }
            emit(id, result.put("source", source).toString())
        }
        return id
    }

    fun close() {
        stopped = true
        mediaServers.close()
        network.shutdownNow(); local.close()
        server?.close(); server = null
    }
}
