package org.vrpassthroughplayer.plugin

import java.io.ByteArrayInputStream
import java.io.IOException
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class SubtitleFallbackTest {
    @Test
    fun undecodableOversizeAndUnreadableSidecarsRemainPlayableTracks() {
        val directory = Files.createTempDirectory("subtitle-fallback").toFile()
        val track = SidecarSubtitles.Track("http://127.0.0.1/caption.srt", "Caption")
        try {
            val failures: List<() -> java.io.InputStream> =
                listOf(
                    { ByteArrayInputStream(byteArrayOf(0, 1, 2, 0, 3)) },
                    { ByteArrayInputStream(ByteArray(SubtitleEncoding.MAX_BYTES + 1)) },
                    { throw IOException("Read timed out") },
                )
            for (open in failures) {
                val result = SubtitleCopies.prepare(track, directory, emptyMap()) { open() }
                assertEquals(
                    "The original track must still be submitted to mpv",
                    track,
                    result.track,
                )
                assertNull("Fallback must not own a partial converted file", result.file)
                assertTrue(directory.listFiles()!!.isEmpty())
            }
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun invalidExplicitEncodingFallsBackToTheOriginalWithoutChangingBytes() {
        val directory = Files.createTempDirectory("subtitle-override-fallback").toFile()
        try {
            val original =
                java.io.File(directory, "caption.srt").apply {
                    writeBytes(byteArrayOf(0xff.toByte()))
                }
            val track = SidecarSubtitles.Track(original.toURI().toString(), "Caption")
            val result =
                SubtitleCopies.prepare(
                    track,
                    directory,
                    mapOf(SubtitleCopies.key(track.identity) to "UTF-8"),
                ) {
                    original.inputStream()
                }
            assertEquals(track, result.track)
            assertNull(result.file)
            assertTrue(result.encodingInvalid)
            assertArrayEquals(byteArrayOf(0xff.toByte()), original.readBytes())
            assertEquals(listOf(original), directory.listFiles()!!.toList())
        } finally {
            directory.deleteRecursively()
        }
    }
}
