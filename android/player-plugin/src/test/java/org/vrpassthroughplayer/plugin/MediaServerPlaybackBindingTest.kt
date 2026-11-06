package org.vrpassthroughplayer.plugin

import java.net.URI
import java.util.concurrent.CopyOnWriteArrayList
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MediaServerPlaybackBindingTest {
    @Test
    fun onlyResolvedLibraryPlaybackHasAReportContext() {
        val sent = CopyOnWriteArrayList<Pair<String, JSONObject>>()
        lateinit var reporter: MediaServerPlaybackReporter
        MediaServerClientTest.Fixture { request, _, _ ->
                if (URI(request.split(' ')[1]).path.endsWith("PlaybackInfo"))
                    MediaServerClientTest.Reply(
                        body =
                            """{"PlaySessionId":"session","MediaSources":[{"Id":"source","Protocol":"File","Size":32,"SupportsDirectPlay":true}]}"""
                                .toByteArray()
                    )
                else
                    MediaServerClientTest.Reply(
                        206,
                        "Content-Range: bytes 0-0/32\r\nContent-Type: video/mp4\r\n",
                        byteArrayOf(1),
                    )
            }
            .use { fixture ->
                LocalStreamServer().use { local ->
                    val account =
                        MediaServerAccount(
                            "server",
                            "NAS",
                            fixture.url,
                            "token",
                            "jellyfin",
                            "user",
                        )
                    val library =
                        MediaServerLibrary(
                            { null },
                            { local },
                            { 1 },
                            getAccount = { account },
                            reporterFactory = { allowed ->
                                MediaServerPlaybackReporter(
                                        allowed,
                                        send = { _, p, b -> sent += p to b },
                                    )
                                    .also { reporter = it }
                            },
                            emit = { _, _ -> },
                        )
                    val uri = MediaLibraryUri.scene("server", "film")
                    val state =
                        JSONObject()
                            .put("action", "state")
                            .put("token", "1")
                            .put("uri", uri)
                            .put("position_ms", 120000)
                            .put("paused", false)
                    try {
                        assertFalse(library.reportPlayback(state.toString()))
                        library.reportPlayback("""{"action":"privacy","enabled":true}""")
                        val playing = library.playable(uri)
                        assertTrue(library.reportPlayback(state.toString()))
                        reporter.awaitIdle()
                        assertEquals("source", sent.single().second.getString("MediaSourceId"))
                        assertFalse(
                            library.reportPlayback(
                                state.put("uri", "file:///private.strm").toString()
                            )
                        )
                        library.release(playing)
                        library.reportPlayback("""{"action":"stop","token":"1"}""")
                        reporter.awaitIdle()
                        assertEquals("Sessions/Playing/Stopped", sent.last().first)
                        assertEquals("session", sent.last().second.getString("PlaySessionId"))
                        assertEquals(1200000000L, sent.last().second.getLong("PositionTicks"))
                        library.reportPlayback("""{"action":"privacy","enabled":false}""")
                        val next = library.playable(uri)
                        library.reportPlayback(state.put("uri", uri).put("token", "2").toString())
                        reporter.awaitIdle()
                        assertEquals(2, sent.size)
                        library.release(next)
                    } finally {
                        library.close()
                    }
                }
            }
    }
}
