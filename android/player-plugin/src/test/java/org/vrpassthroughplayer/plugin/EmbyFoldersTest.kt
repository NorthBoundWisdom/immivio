package org.vrpassthroughplayer.plugin

import java.net.URI
import java.net.URLDecoder
import java.util.concurrent.CopyOnWriteArrayList
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class EmbyFoldersTest {
    @Test
    fun folderQueriesDoNotWhitelistAwayUnknownContainers() {
        val requests = CopyOnWriteArrayList<URI>()
        MediaServerClientTest.Fixture { request, _, _ ->
                requests += URI(request.split(' ')[1])
                MediaServerClientTest.Reply(
                    body =
                        """{"Items":[{"Id":"view","Name":"Plugin folder","Type":"UserView","IsFolder":true,"ImageTags":{"Primary":"tag"}}],"TotalRecordCount":1}"""
                            .toByteArray()
                )
            }
            .use { fixture ->
                val account = MediaServerAccount("srv", "NAS", fixture.url, "key", "emby", "user")
                MediaServerHttp(account).use { http ->
                    val client = EmbyClient(account, http)
                    val entries =
                        client
                            .browse(JSONObject().put("mode", "folders").put("parent_id", "parent"))
                            .getJSONArray("entries")
                    val query =
                        requests.single().rawQuery.split('&').associate {
                            val p = it.split('=', limit = 2)
                            URLDecoder.decode(p[0], "UTF-8") to URLDecoder.decode(p[1], "UTF-8")
                        }
                    assertFalse(query.containsKey("IncludeItemTypes"))
                    assertEquals("Audio,AudioBook,Book,Game,Photo", query["ExcludeItemTypes"])
                    assertEquals("false", query["Recursive"])
                    assertEquals("parent", query["ParentId"])
                    assertTrue(entries.getJSONObject(0).getBoolean("container"))
                    assertEquals("/Items/view/Images/Primary", client.cover("view").path)
                    client.browse(JSONObject())
                    assertTrue(
                        requests
                            .last()
                            .rawQuery
                            .contains("IncludeItemTypes=Movie%2CEpisode%2CVideo")
                    )
                    assertFalse(requests.last().rawQuery.contains("ExcludeItemTypes"))
                }
            }
    }
}
