package org.vrpassthroughplayer.plugin

import java.io.File
import java.net.URI
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicLong
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * Explicit opt-in for an owned, loopback-only synthetic Jellyfin server; never prints credentials.
 */
class JellyfinLivePortsTest {
    @Test
    fun foldersVersionsPlaybackLifecycleAndHistoryPrivacyOnLocalJellyfin() {
        val path = System.getenv("IMMIVIO_JELLYFIN_LIVE_JSON").orEmpty()
        assumeTrue(
            "Optional owned local Jellyfin integration: set IMMIVIO_JELLYFIN_LIVE_JSON",
            path.isNotEmpty(),
        )
        val config = JSONObject(File(path).readText())
        val address = config.getString("url")
        require(URI(address).host in setOf("127.0.0.1", "localhost"))
        val anonymous =
            MediaServerAccount(
                UUID.randomUUID().toString(),
                "Synthetic Jellyfin",
                address,
                "",
                "jellyfin",
            )
        val account =
            MediaServerHttp(anonymous).use {
                EmbyClient(anonymous, it)
                    .login(config.getString("username"), config.getString("password"))
            }
        val movieId = config.getString("movie_id")
        val libraryId = config.getString("library_id")
        MediaServerHttp(account).use { http ->
            val client = EmbyClient(account, http)
            assertTrue(client.probe().isNotBlank())
            val folders =
                client
                    .browse(JSONObject().put("mode", "folders").put("library_id", libraryId))
                    .getJSONArray("entries")
                    .objects()
            assertTrue(
                "The nested directory must remain in folder browsing",
                folders.any { it.optBoolean("container") },
            )
            val detail = client.detail(movieId)
            val versions = detail.getJSONArray("versions").objects()
            assertEquals("The synthetic movie exposes both versions", 2, versions.size)
            // Exercise the alternate item, independent of server ordering after playback.
            val source =
                versions.first { it.getString("source_id") != movieId }.getString("source_id")
            val stream = client.stream(movieId, source)
            assertEquals(source, stream.playback!!.mediaSourceId)
            println(
                "Live Jellyfin: folder container retained; two versions; selected PlaybackInfo source matched"
            )
            val positions = mutableListOf<Long>()
            for (pausedStart in listOf(true, false)) LocalStreamServer().use { local ->
                val clock = AtomicLong(1000)
                val accepted = CopyOnWriteArrayList<String>()
                val failures = CopyOnWriteArrayList<String>()
                lateinit var reporter: MediaServerPlaybackReporter
                val library =
                    MediaServerLibrary(
                        { null },
                        { local },
                        { 1 },
                        getAccount = { account },
                        reporterFactory = { allowed ->
                            MediaServerPlaybackReporter(
                                    allowed,
                                    clock::get,
                                    { a, endpoint, body ->
                                        try {
                                            MediaServerHttp(a).use { transport ->
                                                transport.bytes(a.endpoint(endpoint), 65536, body)
                                            }
                                            accepted.add(endpoint)
                                            println(
                                                "Live Jellyfin scenario=${if (pausedStart) "A-paused-start" else "B-pause-exit"} accepted $endpoint body=$body"
                                            )
                                        } catch (error: Exception) {
                                            failures.add(error.javaClass.simpleName)
                                        }
                                    },
                                )
                                .also { reporter = it }
                        },
                        emit = { _, _ -> },
                    )
                val uri = MediaLibraryUri.scene(account.id, movieId, source)
                var lease = ""
                try {
                    lease =
                        library.playable(
                            uri
                        ) // Real authenticated Range read establishes the binding.
                    assertTrue(library.reportPlayback("""{"action":"privacy","enabled":true}"""))
                    val state =
                        JSONObject()
                            .put("action", "state")
                            .put("token", "1")
                            .put("uri", uri)
                            .put("position_ms", 60000)
                            .put("paused", pausedStart)
                            .put("can_seek", true)
                    assertTrue(library.reportPlayback(state.toString()))
                    reporter.awaitIdle()
                    // A progress readback prevents pre-existing resume from masking a failure.
                    clock.addAndGet(10001)
                    assertTrue(library.reportPlayback(state.toString()))
                    reporter.awaitIdle()
                    val startedPosition = client.detail(source).getLong("position_ms")
                    println(
                        "Live Jellyfin selected-version after start position_ms=$startedPosition"
                    )
                    assertEquals(
                        "Progress must persist the actual position, including paused state",
                        60000L,
                        startedPosition,
                    )
                    clock.addAndGet(10001)
                    assertTrue(library.reportPlayback(state.put("position_ms", 120000).toString()))
                    reporter.awaitIdle()
                    if (!pausedStart) {
                        reporter.pause()
                        reporter.awaitIdle()
                    }
                    assertTrue(library.reportPlayback("""{"action":"stop","token":"1"}"""))
                    reporter.awaitIdle()
                    assertTrue("Playback API calls must all succeed: $failures", failures.isEmpty())
                    assertEquals(
                        listOf(
                            "Sessions/Playing",
                            "Sessions/Playing/Progress",
                            "Sessions/Playing/Progress",
                        ) +
                            (if (pausedStart) emptyList()
                            else listOf("Sessions/Playing/Progress")) +
                            listOf("Sessions/Playing/Stopped"),
                        accepted.toList(),
                    )
                    // Jellyfin stores resume on the selected version item, which may differ from
                    // the grouped movie ID. Never change the selected fixture version to mask this.
                    val groupedPosition = client.detail(movieId).getLong("position_ms")
                    val savedPosition = client.detail(source).getLong("position_ms")
                    positions.add(savedPosition)
                    println(
                        "Live Jellyfin scenario=${if (pausedStart) "A-paused-start" else "B-pause-exit"} server selected-version position_ms=$savedPosition grouped position_ms=$groupedPosition"
                    )
                    assertTrue(library.reportPlayback("""{"action":"privacy","enabled":false}"""))
                    clock.addAndGet(10001)
                    library.reportPlayback(
                        state.put("token", "2").put("position_ms", 180000).toString()
                    )
                    reporter.awaitIdle()
                    assertEquals(
                        "History-disabled playback cannot send more reports",
                        if (pausedStart) 4 else 5,
                        accepted.size,
                    )
                    assertEquals(
                        "History-disabled playback cannot change server progress",
                        savedPosition,
                        client.detail(source).getLong("position_ms"),
                    )
                    println(
                        "Live Jellyfin: Playing/Progress/Stopped accepted; history-off sent zero additional reports"
                    )
                } finally {
                    if (lease.isNotEmpty()) library.release(lease)
                    library.close()
                }
            }
            assertTrue(
                "Both paused-start and pause-before-exit must retain resume: $positions",
                positions.all { it >= 120000 },
            )
        }
    }
}
