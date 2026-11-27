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
                    when (path) {
                        "/Users/user/Items/film" -> """{"Id":"film","Name":"Film","PartCount":3}"""
                        "/Videos/film/AdditionalParts?UserId=user" ->
                            """{"Items":[{"Id":"z","Name":"CD2","UserData":{"PlaybackPositionTicks":25000000}},{"Id":"a","Name":"CD3"}]}"""
                        "/Items/z/PlaybackInfo?UserId=user" ->
                            """{"PlaySessionId":"session2","MediaSources":[{"Id":"source2","Protocol":"File"}]}"""
                        "/Users/user/Items/versions" ->
                            """{"Id":"versions","MediaSources":[{"Id":"cut1"},{"Id":"cut2"}]}"""
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
                    val parts = client.detail("film").getJSONArray("additional_parts").objects()
                    assertEquals(listOf("z", "a"), parts.map { it.getString("id") })
                    assertEquals(2500, parts.first().getInt("position_ms"))
                    val (server, id) = MediaLibraryUri.parse(parts.first().getString("uri"))
                    assertEquals("srv", server)
                    val stream = client.stream(id)
                    assertEquals("/Videos/z/stream", stream.url.path)
                    assertEquals("z", stream.playback!!.itemId)
                    assertEquals("source2", stream.playback.mediaSourceId)
                    val versions = client.detail("versions")
                    assertFalse(versions.has("additional_parts"))
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
