package org.vrpassthroughplayer.plugin

import org.junit.Assert.*
import org.junit.Test
import org.vrpassthroughplayer.plugin.MediaServerClientTest.Fixture
import org.vrpassthroughplayer.plugin.MediaServerClientTest.Reply
import java.util.concurrent.atomic.AtomicInteger

class StrmHttpTest {
    @Test fun redirectsResolveAgainstTheFinalDirectoryWithoutReadingVideo() {
        val videoReads = AtomicInteger()
        Fixture { request, _, _ ->
            when (request.split(' ')[1].substringBefore('?')) {
                "/old.strm" -> Reply(302, "Location: /index/movie.strm\r\n", byteArrayOf())
                "/index/movie.strm" -> Reply(200, body = "../video.mkv?sign=a%2Fb".toByteArray())
                else -> { videoReads.incrementAndGet(); Reply(200, body = byteArrayOf()) }
            }
        }.use { server ->
            assertEquals(server.url + "/video.mkv?sign=a%2Fb", StrmResolver(StrmHttp::read).resolve(server.url + "/old.strm"))
            assertEquals(0, videoReads.get())
        }
    }
    @Test fun boundsAndHttpFailuresAreStableAndRedacted() {
        Fixture { request, _, _ ->
            when (request.split(' ')[1].substringBefore('?')) {
                "/large.strm" -> Reply(200, body = ByteArray(StrmFile.MAX_BYTES + 1))
                "/unsafe.strm" -> Reply(302, "Location: file:///etc/passwd\r\n", byteArrayOf())
                "/loop.strm" -> Reply(302, "Location: /loop.strm\r\n", byteArrayOf())
                else -> Reply(request.split(' ')[1].substringAfter('/').substringBefore('.').toInt(), body = byteArrayOf())
            }
        }.use { server ->
            for ((path, code) in listOf("401" to "STRM_ACCESS_DENIED", "404" to "STRM_NOT_FOUND", "500" to "STRM_READ_FAILED",
                "large" to "STRM_TOO_LARGE", "unsafe" to "STRM_INVALID_ADDRESS", "loop" to "STRM_READ_FAILED")) {
                assertEquals(code, assertThrows(StrmFailure::class.java) { StrmHttp.read(server.url + "/$path.strm?secret=hidden") }.code)
            }
        }
    }
}
