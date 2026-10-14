package org.vrpassthroughplayer.plugin

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class OpenListListingTest {
    private val mount = "/12345678-1234-1234-1234-123456789abc"
    private fun client(
        names: List<String>,
        ids: List<String> = names.indices.map { "${9007199254740993L + it}" }
    ): CloudClient = OpenListBackend.Client(mount, CloudDrive.OPEN115) { method, route, body ->
        assertEquals("POST", method)
        assertEquals("/list115", route)
        assertEquals(mount, body!!.getString("mount"))
        val offset = body.getInt("offset")
        val items = JSONArray()
        for (i in offset until minOf(offset + CloudDrive.PAGE_SIZE, names.size)) items.put(
            JSONObject()
                .put("name", names[i]).put("id", ids[i]).put("is_dir", false)
                .put("size", 12).put("modified_ms", 10).put("can_delete", true)
        )
        JSONObject().put("code", 200)
            .put("data", JSONObject().put("total", names.size).put("content", items))
    }

    @Test
    fun similarNamesAndBothParenthesisWidthsSurviveListingSortingAndUris() {
        val names = listOf(
            "test.mp4",
            "test(2).mp4",
            "test（2）.mp4",
            "test (2).mp4",
            "test[2].mp4",
            "test.srt",
            "q.mp4"
        )
        val client = client(names)
        assertEquals(names, client.list("/").map { it.name })
        for (order in CloudSortedPages.ORDERS + "source") {
            val files = CloudSortedPages().page(client, "/", 0, false, order).files
            assertEquals(
                names.filter { it != "test.srt" }.toSet(),
                files.filter { MediaKinds.supported(it.name) }.map { it.name }.toSet()
            )
            for (file in files) {
                val path = mount + file.id
                assertEquals(path, CloudPaths.path(CloudPaths.uri(path)))
                assertEquals(file.objectId, client.find(file.id).objectId)
            }
        }
    }

    @Test
    fun exactDuplicateNamesDoNotHideOtherFilesButCannotResolveAnAmbiguousPath() {
        val client = client(listOf("test.mp4", "test.mp4", "test(2).mp4", "q.mp4"))
        assertEquals(4, client.page("/").files.size)
        val files = CloudSortedPages().page(client, "/", 0, false, "name_asc").files
        assertEquals(4, files.size)
        assertEquals(4, files.map { it.objectId }.toSet().size)
        assertEquals("q.mp4", client.find("/q.mp4").name)
        assertEquals(
            "cloud_file_ambiguous",
            assertThrows(CloudFailure::class.java) { client.find("/test.mp4") }.reason
        )
        assertThrows(CloudFailure::class.java) { client.resolve(files.first { it.name == "test.mp4" }) }
    }

    @Test
    fun duplicateNamesAcrossPagesStillAllowFullSortAndRejectAmbiguousPlayback() {
        val names = (0 until 55).map { if (it == 0 || it == 54) "test.mp4" else "test($it).mp4" }
        val client = client(names)
        assertEquals(names, client.list("/").map { it.name })
        val pages = CloudSortedPages()
        val first = pages.page(client, "/", 0, false, "name_asc")
        val second = pages.page(client, "/", 48, false, "name_asc")
        assertEquals(55, first.total)
        assertEquals(55, (first.files + second.files).map { it.objectId }.toSet().size)
        assertThrows(CloudFailure::class.java) { client.find("/test.mp4") }
    }

    @Test
    fun repeatedObjectIdsStillRejectInvalidProviderPages() {
        val repeated = client(listOf("test.mp4", "test(2).mp4"), listOf("1", "1"))
        assertThrows(CloudFailure::class.java) { repeated.page("/") }
        val names = (0 until 55).map { "test($it).mp4" }
        val ids = names.indices.map { if (it == 54) "1" else "${it + 1}" }
        assertThrows(CloudFailure::class.java) { client(names, ids).list("/") }
        assertThrows(CloudFailure::class.java) {
            CloudSortedPages().page(
                client(names, ids),
                "/",
                0,
                false,
                "name_asc"
            )
        }
    }

    @Test
    fun duplicateFolderPathsCannotSelectAnArbitraryFolderButOtherFoldersStillOpen() {
        val client = OpenListBackend.Client(mount, CloudDrive.OPEN115) { _, _, body ->
            val items = JSONArray()
            if (body!!.getString("path") == "/") {
                for ((id, name) in listOf("1" to "Folder", "2" to "Folder", "3" to "OK"))
                    items.put(
                        JSONObject().put("name", name).put("id", id).put("is_dir", true)
                            .put("can_delete", true)
                    )
            } else {
                assertEquals("/OK", body.getString("path"))
                items.put(
                    JSONObject().put("name", "q.mp4").put("id", "4").put("is_dir", false)
                        .put("size", 12)
                )
            }
            JSONObject().put("code", 200)
                .put("data", JSONObject().put("total", items.length()).put("content", items))
        }
        assertEquals(3, client.page("/").files.size)
        assertThrows(CloudFailure::class.java) { client.page("/Folder") }
        assertEquals("q.mp4", client.page("/OK").files.single().name)
    }

    @Test
    fun ambiguousSidecarPathsAreRejectedBeforePublishingAnyStream() {
        val client = client(
            listOf(
                "movie.mp4",
                "movie.srt",
                "movie.srt",
                "movie.si.mix.m4a",
                "movie.si.mix.m4a"
            )
        )
        assertTrue(SidecarSubtitles.forCloud("/movie.mp4", client) { client.resolve(it).url }
            .isEmpty())
        assertTrue(SidecarAudio.forCloud("/movie.mp4", client) { client.resolve(it).url }.isEmpty())
        assertEquals("movie.mp4", client.find("/movie.mp4").name)
    }

    @Test
    fun folderIdentityCheckDoesNotRepeatParentPaginationForEveryChildPage() {
        var parentCalls = 0
        var childCalls = 0
        val client = OpenListBackend.Client(mount, CloudDrive.OPEN115) { _, _, body ->
            val parent = body!!.getString("path") == "/"
            if (parent) parentCalls++ else childCalls++
            val total = if (parent) 55 else 100
            val offset = body.getInt("offset")
            val items = JSONArray()
            for (i in offset until minOf(offset + CloudDrive.PAGE_SIZE, total)) {
                val folder = parent && i == 0
                items.put(
                    JSONObject().put("id", "${i + 1}")
                        .put("name", if (folder) "Folder" else "test($i).mp4")
                        .put("is_dir", folder).put("size", 12)
                )
            }
            JSONObject().put("code", 200)
                .put("data", JSONObject().put("total", total).put("content", items))
        }
        assertEquals(100, CloudSortedPages().page(client, "/Folder", 0, false, "name_asc").total)
        assertEquals(2, parentCalls)
        assertEquals(3, childCalls)
    }

    @Test
    fun refreshingParentInvalidatesPreviouslyUnambiguousFolderPaths() {
        var duplicate = false
        var childCalls = 0
        val client = OpenListBackend.Client(mount, CloudDrive.OPEN115) { _, _, body ->
            val parent = body!!.getString("path") == "/"
            if (!parent) childCalls++
            val items = JSONArray()
            for (i in 1..if (parent && duplicate) 2 else 1) items.put(
                JSONObject()
                    .put("id", "$i").put("name", if (parent) "Folder" else "q.mp4")
                    .put("is_dir", parent).put("size", 12)
            )
            JSONObject().put("code", 200)
                .put("data", JSONObject().put("total", items.length()).put("content", items))
        }
        assertEquals(1, client.page("/Folder").files.size)
        duplicate = true
        assertEquals(2, client.page("/", 0, true).files.size)
        assertThrows(CloudFailure::class.java) { client.page("/Folder") }
        assertEquals(1, childCalls)
    }
}
