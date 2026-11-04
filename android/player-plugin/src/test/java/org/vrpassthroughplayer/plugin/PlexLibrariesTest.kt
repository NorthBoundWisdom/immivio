package org.vrpassthroughplayer.plugin
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.net.URI
import java.util.concurrent.CopyOnWriteArrayList
class PlexLibrariesTest {
    @Test fun libraryPresentationIdentifiesTvAndUsesSeriesNavigationWithoutChangingTheConnection() {
        val requests = CopyOnWriteArrayList<URI>()
        MediaServerClientTest.Fixture { request, headers, _ ->
            assertEquals("token", headers["x-plex-token"])
            val uri = URI(request.split(' ')[1]); requests += uri
            MediaServerClientTest.Reply(body = if (uri.path == "/library/sections")
                """{"MediaContainer":{"Directory":[{"key":"1","title":"Films","type":"movie"},{"key":"2","title":"TV","type":"show"},{"key":"3","title":"Music","type":"artist"}]}}""".toByteArray()
            else """{"MediaContainer":{"Metadata":[],"size":0,"totalSize":0}}""".toByteArray())
        }.use { fixture ->
            val account = MediaServerAccount("client", "Plex", fixture.url, "token", "plex")
            MediaServerHttp(account).use { http ->
                val client = PlexClient(account, http)
                val home = client.home(JSONObject())
                assertEquals("libraries", home.getJSONObject("capabilities").getString("home_layout"))
                assertEquals(2, home.getJSONArray("libraries").length())
                assertEquals("tvshows", home.getJSONArray("libraries").getJSONObject(1).getString("collection_type"))
                client.browse(JSONObject().put("library_id", "2").put("mode", "library"))
                assertTrue(requests.last().path == "/library/sections/2/all" && requests.last().rawQuery.contains("type=2"))
                client.browse(JSONObject().put("library_id", "1").put("mode", "library"))
                assertTrue(requests.last().rawQuery.contains("type=1"))
            }
        }
    }
}
