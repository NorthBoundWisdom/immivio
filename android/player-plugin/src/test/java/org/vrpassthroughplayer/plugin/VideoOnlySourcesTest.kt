package org.vrpassthroughplayer.plugin

import org.junit.Assert.*
import org.junit.Test

class VideoOnlySourcesTest {
    @Test
    fun fileSourcesExposeVideosAndShortcutsOnly() {
        for (name in listOf("movie.MP4", "movie.mkv", "movie.strm", "movie.SBS.STRM")) {
            assertTrue(name, MediaKinds.supported(name))
        }
        for (name in
            listOf(
                "photo.jpg",
                "image.PNG",
                "spatial.HEIC",
                "camera.heif?token=1",
                "cover.webp",
                "audio.m4a",
                "captions.srt",
            )) {
            assertFalse(name, MediaKinds.supported(name))
        }
        assertThrows(IllegalArgumentException::class.java) {
            MediaDeletePolicy.smbPath("share/still.jpg")
        }
    }

    @Test
    fun dlnaExcludesImageItemsWhileKeepingVideoCovers() {
        val entries =
            DlnaClient.didl(
                """<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
            <container id="folder"><dc:title>Movies</dc:title></container>
            <item id="still"><dc:title>Still</dc:title><upnp:class>object.item.imageItem.photo</upnp:class>
              <res protocolInfo="http-get:*:image/jpeg:*">http://host/full.jpg</res>
              <res protocolInfo="http-get:*:video/mp4:*">http://host/incorrect.mp4</res></item>
            <item id="film"><dc:title>Film</dc:title><upnp:class>object.item.videoItem</upnp:class>
              <res protocolInfo="http-get:*:image/jpeg:*">http://host/cover.jpg</res>
              <res protocolInfo="http-get:*:video/mp4:*">http://host/video</res></item>
        </DIDL-Lite>"""
            )
        assertEquals(2, entries.length())
        assertTrue(entries.getJSONObject(0).getBoolean("container"))
        val film = entries.getJSONObject(1)
        assertEquals("video", film.getString("kind"))
        assertEquals("http://host/video", film.getString("uri"))
        assertEquals("http://host/cover.jpg", film.getString("cover"))
    }
}
