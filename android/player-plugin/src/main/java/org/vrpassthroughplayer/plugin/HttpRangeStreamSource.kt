package org.vrpassthroughplayer.plugin

import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI
import java.util.concurrent.ConcurrentHashMap

internal data class MediaSubtitleLink(
    val url: URI,
    val title: String,
    val extension: String = "srt",
)

internal data class MediaAudioLink(val url: URI, val identity: String, val title: String)

internal data class MediaStreamLink(
    val url: URI,
    val identity: String,
    val subtitles: List<MediaSubtitleLink> = emptyList(),
    val audio: List<MediaAudioLink> = emptyList(),
    val basename: String = "",
    val playback: MediaServerPlaybackContext? = null,
)

/** Authenticated, seekable original-file streaming. Only the local token is given to MPV. */
internal class HttpRangeStreamSource(
    account: MediaServerAccount,
    private val resolve: (MediaServerHttp) -> MediaStreamLink,
) : StreamSource {
    private val http = MediaServerHttp(account)
    private var link: MediaStreamLink
    override val size: Long
    @Volatile private var closed = false
    private val readers = ConcurrentHashMap.newKeySet<RemoteReader>()

    init {
        try {
            link = resolve(http)
            val c = http.open(link.url, "bytes=0-0")
            try {
                val range = validate(c, 0)
                mediaRequire(range.second == 0L, "Server does not support seeking")
                size = range.third
            } finally {
                http.release(c)
            }
        } catch (e: Exception) {
            http.close()
            throw e
        }
    }

    @Synchronized
    private fun current(failed: MediaStreamLink? = null): MediaStreamLink {
        mediaRequire(!closed, "Request cancelled")
        if (failed === link) {
            val fresh = resolve(http)
            mediaRequire(fresh.identity == link.identity, "Video changed; reopen it")
            link = fresh
        }
        return link
    }

    fun original(): MediaStreamLink = current()

    override fun open(): StreamSource.Reader =
        synchronized(this) {
            mediaRequire(!closed, "Request cancelled")
            RemoteReader().also { readers.add(it) }
        }

    override fun close() {
        closed = true
        http.close() // unblock readers before acquiring their state
        java.util.ArrayList(readers).forEach { it.close() }
    }

    private inner class RemoteReader : StreamSource.Reader {
        private var done = false
        private var connection: HttpURLConnection? = null
        private var input: InputStream? = null
        private var next = -1L
        private var end = -1L

        override fun read(offset: Long, buffer: ByteArray, length: Int): Int {
            mediaRequire(offset in 0 until size && length in 1..buffer.size)
            val cached =
                synchronized(this) {
                    mediaRequire(!closed && !done, "Request cancelled")
                    if (next != offset || offset > end) disconnect()
                    input
                }
            val stream = cached ?: connect(offset)
            val n = stream.read(buffer, 0, minOf(length.toLong(), end - offset + 1).toInt())
            mediaRequire(n > 0, "Stream interrupted")
            next = offset + n
            return n
        }

        private fun connect(offset: Long): InputStream {
            val selected = current()
            val opened =
                try {
                    http.open(selected.url, "bytes=$offset-")
                } catch (e: MediaServerFailure) {
                    if (e.code != "Server authentication required") throw e
                    http.open(current(selected).url, "bytes=$offset-")
                }
            try {
                val range = validate(opened, offset)
                mediaRequire(range.third == size, "Video changed; reopen it")
                val stream = opened.inputStream
                synchronized(this) {
                    mediaRequire(!closed && !done, "Request cancelled")
                    connection = opened
                    input = stream
                    end = range.second
                }
                return stream
            } catch (e: Exception) {
                http.release(opened)
                throw e
            }
        }

        private fun disconnect() {
            connection?.let(http::release)
            connection = null
            runCatching { input?.close() }
            input = null
        }

        override fun close() {
            synchronized(this) {
                done = true
                disconnect()
            }
            readers.remove(this)
        }
    }

    companion object {
        fun validate(c: HttpURLConnection, offset: Long): Triple<Long, Long, Long> {
            mediaRequire(c.responseCode == 206, "Server does not support seeking")
            val m =
                Regex("bytes (\\d+)-(\\d+)/(\\d+)")
                    .matchEntire(c.getHeaderField("Content-Range").orEmpty())
                    ?: throw MediaServerFailure("Invalid byte range")
            val start = m.groupValues[1].toLongOrNull() ?: -1
            val end = m.groupValues[2].toLongOrNull() ?: -1
            val total = m.groupValues[3].toLongOrNull() ?: -1
            mediaRequire(start == offset && end >= start && total > end, "Invalid byte range")
            mediaRequire(
                c.contentLengthLong == -1L || c.contentLengthLong == end - start + 1,
                "Invalid byte range",
            )
            val type = c.contentType.orEmpty().lowercase()
            mediaRequire(
                !type.contains("text/") && !type.contains("json"),
                "Invalid media response",
            )
            return Triple(start, end, total)
        }
    }
}
