package org.vrpassthroughplayer.plugin

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File

/** Source IO is released only after native playback stops reading it.
 * Closing prevents late resolver results from attaching fresh leases to a dead host. */
internal class PlaybackSourceResources(private val releaseNetwork: (String) -> Unit) {
    private var closed = false
    private var descriptor: ParcelFileDescriptor? = null
    private var sidecars: List<ParcelFileDescriptor> = emptyList()
    private var networkLease: String? = null
    private var subtitleLeases: List<String> = emptyList()
    private var audioLeases: List<String> = emptyList()
    val importedSubtitles = mutableListOf<File>() // accessed under the playback host lock

    fun resolve(context: Context, uri: String, network: (String) -> String): String {
        val source = Uri.parse(uri)
        return when (source.scheme) {
            "file" -> source.path ?: error("Local file path unavailable")
            "smb", "cloud", "medialib", "http", "https" -> network(uri).also { location ->
                if (source.scheme in setOf("medialib", "cloud", "smb")) synchronized(this) {
                    if (closed) {
                        releaseNetwork(location); error("Playback source closed")
                    }
                    networkLease = location
                }
            }

            else -> {
                val fd = context.contentResolver.openFileDescriptor(source, "r")
                    ?: error("Local document descriptor unavailable")
                synchronized(this) {
                    if (closed) {
                        fd.close(); error("Playback source closed")
                    }
                    descriptor = fd
                }
                "fd://${fd.fd}"
            }
        }
    }

    @Synchronized
    fun adoptAudio(tracks: List<SidecarAudio.Track>) {
        val descriptors = tracks.mapNotNull { it.descriptor }
        val leases =
            tracks.filter { it.location.startsWith("http://127.0.0.1:") }.map { it.location }
        if (closed) {
            descriptors.forEach { runCatching { it.close() } }; leases.forEach(releaseNetwork)
            error("Playback source closed")
        }
        sidecars = descriptors; audioLeases = leases
    }

    @Synchronized
    fun adoptSubtitles(tracks: List<SidecarSubtitles.Track>) {
        val leases = tracks.map { it.location }
        if (closed) {
            leases.forEach(releaseNetwork); error("Playback source closed")
        }
        subtitleLeases = leases
    }

    /** Called under the host lock; repeat calls retry network releases that threw. */
    @Synchronized
    fun close() {
        closed = true
        networkLease?.let(releaseNetwork); networkLease = null
        subtitleLeases.forEach(releaseNetwork); subtitleLeases = emptyList()
        audioLeases.forEach(releaseNetwork); audioLeases = emptyList()
        importedSubtitles.forEach { it.delete() }; importedSubtitles.clear()
        descriptor?.close(); descriptor = null
        sidecars.forEach { runCatching { it.close() } }; sidecars = emptyList()
    }
}
