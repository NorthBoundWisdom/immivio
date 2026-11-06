package org.vrpassthroughplayer.plugin

import java.io.File
import org.junit.Assert.*
import org.junit.Test

class ExternalPlaybackTest {
    @Test
    fun validatesIngressBeforeAnyEngineOrProviderWork() {
        fun parse(
            uri: String,
            action: String = "android.intent.action.VIEW",
            grant: Boolean = false,
        ) =
            ExternalPlaybackRequest.parse(
                action,
                uri,
                "Film",
                "video/mp4",
                grant,
                listOf(File("/private/app")),
            )
        assertEquals(
            "content",
            parse("content://provider/document/film", "android.intent.action.SEND", true).scheme,
        )
        for (uri in
            listOf(
                "http://user:secret@host/film",
                "javascript:run()",
                "file:///private/app/token",
                "content://provider/document/film",
                "https://host/video\ncommand",
            )) assertThrows(Exception::class.java) { parse(uri) }
        assertThrows(Exception::class.java) {
            parse("https://host/video", "android.intent.action.SEND_MULTIPLE")
        }
        assertFalse(parse("https://host/video?token=secret").toString().contains("secret"))
        assertThrows(Exception::class.java) {
            ExternalPlaybackRequest.parse(
                "android.intent.action.VIEW",
                "https://host/film",
                "Film",
                "application/pdf",
                false,
            )
        }
    }

    @Test
    fun binaryAndTextAssociationsCannotOpenNetworkDownloads() {
        fun parse(uri: String, mime: String) =
            ExternalPlaybackRequest.parse(
                "android.intent.action.VIEW",
                uri,
                "film.strm",
                mime,
                true,
            )
        assertEquals(
            "content",
            parse("content://provider/document/film", "application/octet-stream").scheme,
        )
        assertEquals("https", parse("https://host/film", "video/mp4").scheme)
        for (mime in listOf("application/octet-stream", "text/plain")) assertThrows(
            Exception::class.java
        ) {
            parse("https://host/film.strm", mime)
        }
        assertThrows(Exception::class.java) {
            parse("content://provider/document/film.strm", "text/plain")
        }
    }

    @Test
    fun replacementExpiryCapacityAndReleaseCloseExactlyOnce() {
        var clock = 0L
        var closed = 0
        val leases = ExternalPlaybackLeases { clock }
        val stale = leases.offer("Old", "fd://1") { closed++ }
        val current = leases.offer("New", "fd://2") { closed++ }
        assertEquals(1, closed)
        assertThrows(Exception::class.java) { leases.target(stale) }
        assertEquals(current, leases.claim()!!.first)
        assertEquals("fd://2", leases.target(current))
        leases.release(current)
        leases.release(current)
        assertEquals(2, closed)
        leases.offer("Expires", "fd://3") { closed++ }
        clock = 60001
        assertNull(leases.claim())
        assertEquals(3, closed)
        repeat(4) {
            leases.offer("$it", "fd://$it") { closed++ }
            leases.claim()
        }
        assertThrows(Exception::class.java) { leases.offer("Overflow", "fd://9") { closed++ } }
        leases.close()
        leases.close()
        assertEquals(8, closed)
    }
}
