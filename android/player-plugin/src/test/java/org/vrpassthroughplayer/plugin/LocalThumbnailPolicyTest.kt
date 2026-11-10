package org.vrpassthroughplayer.plugin

import org.junit.Assert.*
import org.junit.Test

class LocalThumbnailPolicyTest {
    @Test
    fun onlyLocalVideosAreDecoded() {
        assertEquals(
            "/storage/Movies/a b.mp4",
            LocalThumbnailPolicy.path("file:///storage/Movies/a%20b.mp4"),
        )
        for (uri in
            listOf(
                "https://host/a.mp4",
                "file://host/a.mp4",
                "file:///a.strm",
                "file:///a.jpg",
                "file:relative.mp4",
                "file:///a.mp4?url=https://host",
                "invalid%",
            )) {
            assertNull(uri, LocalThumbnailPolicy.path(uri))
        }
    }

    @Test
    fun decodingStaysBoundedAndPreservesAspect() {
        assertEquals(1280 to 640, LocalThumbnailPolicy.size(8192, 4096))
        assertEquals(720 to 720, LocalThumbnailPolicy.size(8192, 8192))
        assertEquals(405 to 720, LocalThumbnailPolicy.size(2160, 3840))
        assertEquals(320 to 180, LocalThumbnailPolicy.size(320, 180))
        assertNull(LocalThumbnailPolicy.size(0, 8192))
        assertNull(LocalThumbnailPolicy.size(Int.MAX_VALUE, 8192))
    }
}
