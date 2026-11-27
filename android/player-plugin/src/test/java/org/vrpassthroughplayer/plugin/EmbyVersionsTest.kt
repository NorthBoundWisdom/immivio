package org.vrpassthroughplayer.plugin

import java.net.URI
import java.util.concurrent.CopyOnWriteArrayList
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class EmbyVersionsTest {
    @Test
    fun selectedVersionControlsRequestStreamAndReportingContext() {
        val requests = CopyOnWriteArrayList<String>()
        val sources =
            """[{"Id":"a","Name":"1080p","Protocol":"File","Path":"/video/a.mp4"},{"Id":"b","Name":"4K","Protocol":"File","Path":"/video/b.mp4"}]"""
        MediaServerClientTest.Fixture { request, _, _ ->
                requests += request
                val body =
                    if (URI(request.split(' ')[1]).path.endsWith("PlaybackInfo"))
                        """{"PlaySessionId":"session-b","MediaSources":$sources}"""
                    else """{"Id":"film","Name":"Film","Type":"Movie","MediaSources":$sources}"""
                MediaServerClientTest.Reply(body = body.toByteArray())
            }
            .use { fixture ->
                val account =
                    MediaServerAccount("srv", "NAS", fixture.url, "secret", "emby", "user")
                MediaServerHttp(account).use { http ->
                    val client = EmbyClient(account, http)
                    val detail = client.detail("film")
                    assertEquals("medialib://srv/scene/film", detail.getString("uri"))
                    val versions = detail.getJSONArray("versions")
                    assertEquals(2, versions.length())
                    assertEquals(
                        "b",
                        MediaLibraryUri.sourceId(versions.getJSONObject(1).getString("uri")),
                    )
                    val selected = client.stream("film", "b")
                    assertTrue(requests.last().contains("MediaSourceId=b"))
                    assertTrue(selected.url.rawQuery.contains("MediaSourceId=b"))
                    assertEquals("b", selected.playback!!.mediaSourceId)
                    assertEquals("session-b", selected.playback.playSessionId)
                    assertThrows(MediaServerFailure::class.java) {
                        client.stream("film", "missing")
                    }
                }
            }
    }

    @Test
    fun jellyfinStackUsesOrderedItemIdsForPlayback() {
        val requests = CopyOnWriteArrayList<String>()
        MediaServerClientTest.Fixture { request, _, _ ->
                val path = request.split(' ')[1]
                requests += path
                val body =
                    when (path.substringBefore('?')) {
                        "/Users/user/Items/film" ->
                            """{"Id":"film","Name":"Film","Path":"/movies/Film-disk_03.mkv"}"""
                        "/Videos/film/AdditionalParts" ->
                            """{"Items":[{"Id":"extra1"},{"Id":"a","Path":"/movies/Film-CD10.mkv"},{"Id":"z","Name":"CD8","MediaSources":[{"Path":"Film.PART-02.mkv"}],"UserData":{"PlaybackPositionTicks":25000000}},{"Id":"film"},{"Id":"extra2","Name":"Film 180"},{"Id":"tie","Name":"Film pt2"},{"Id":"first","Name":"Film Disc 1"}]}"""
                        "/Items/z/PlaybackInfo" ->
                            """{"PlaySessionId":"session2","MediaSources":[{"Id":"source2","Protocol":"File"}]}"""
                        "/Users/user/Items/plain" ->
                            """{"Id":"plain","Name":"Film","PartCount":2}"""
                        "/Videos/plain/AdditionalParts" ->
                            """{"Items":[{"Id":"two","Name":"CD2"}]}"""
                        "/Users/user/Items/alone" ->
                            """{"Id":"alone","Path":"/movies/Film-cd1.mkv"}"""
                        "/Videos/alone/AdditionalParts" -> """{"Items":[]}"""
                        "/Users/user/Items/versions" ->
                            """{"Id":"versions","Path":"/movies/disc2/Vr180_podcast2.mkv","MediaSources":[{"Id":"cut1"},{"Id":"cut2"}]}"""
                        "/Users/user/Items/unavailable" -> """{"Id":"unavailable","PartCount":2}"""
                        else ->
                            return@Fixture MediaServerClientTest.Reply(404, body = byteArrayOf())
                    }
                MediaServerClientTest.Reply(body = body.toByteArray())
            }
            .use { fixture ->
                val account = MediaServerAccount("srv", "NAS", fixture.url, "", "jellyfin", "user")
                MediaServerHttp(account).use { http ->
                    val client = EmbyClient(account, http)
                    val parts = client.detail("film").getJSONArray("parts").objects()
                    assertEquals(
                        listOf("first", "z", "tie", "film", "a", "extra1", "extra2"),
                        parts.map { it.getString("id") },
                    )
                    assertEquals(10, parts[4].getInt("part_number"))
                    assertEquals(2500, parts[1].getInt("position_ms"))
                    val (server, id) = MediaLibraryUri.parse(parts[1].getString("uri"))
                    assertEquals("srv", server)
                    val stream = client.stream(id)
                    assertEquals("/Videos/z/stream", stream.url.path)
                    assertEquals("z", stream.playback!!.itemId)
                    assertEquals("source2", stream.playback.mediaSourceId)
                    assertEquals(
                        listOf("plain", "two"),
                        client.detail("plain").getJSONArray("parts").objects().map {
                            it.getString("id")
                        },
                    )
                    assertFalse(client.detail("alone").has("parts"))
                    val versions = client.detail("versions")
                    assertFalse(versions.has("parts"))
                    assertEquals(2, versions.getJSONArray("versions").length())
                    assertFalse(requests.any { it.startsWith("/Videos/versions/AdditionalParts") })
                    val partial = client.detail("unavailable")
                    assertEquals("medialib://srv/scene/unavailable", partial.getString("uri"))
                    assertTrue(partial.has("parts_error"))
                }
            }
    }

    @Test
    fun opaqueSourceIdentityRoundTripsWithoutAcceptingCredentialsOrExtraQueries() {
        val legacy = MediaLibraryUri.scene("srv", "film")
        val version = MediaLibraryUri.scene("srv", "film", "source /?&b")
        assertEquals("source /?&b", MediaLibraryUri.sourceId(version))
        assertEquals("srv" to "film", MediaLibraryUri.parse(version))
        assertEquals("", MediaLibraryUri.sourceId(legacy))
        assertThrows(MediaServerFailure::class.java) {
            MediaLibraryUri.parse("$version&token=secret")
        }
        assertThrows(MediaServerFailure::class.java) { MediaLibraryUri.parse("$legacy?source=") }
    }
}
