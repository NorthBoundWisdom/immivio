package org.vrpassthroughplayer.plugin

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream

class SubtitleImportTest {
    @Test
    fun acceptsOnlySupportedSubtitleSuffixes() {
        for (name in listOf("日本語.SRT", "sub.ass", "a.ssa", "captions.vtt")) assertTrue(
            SubtitleImport.extension(name).isNotEmpty()
        )
        for (name in listOf("video.mp4", "sub.srt.exe", "no-extension", "a.sup")) {
            assertThrows(IllegalArgumentException::class.java) { SubtitleImport.extension(name) }
        }
    }

    @Test
    fun copiesUnicodeBytesWithoutChangingEncoding() {
        val bytes = "1\n00:00:01,000 --> 00:00:02,000\n中文字幕 😀\n".toByteArray()
        val output = ByteArrayOutputStream()
        assertEquals(bytes.size, SubtitleImport.copy(ByteArrayInputStream(bytes), output))
        assertArrayEquals(bytes, output.toByteArray())
    }

    @Test
    fun rejectsEmptyAndOversizeStreamsWithoutUnboundedCopies() {
        assertThrows(IllegalArgumentException::class.java) {
            SubtitleImport.copy(
                ByteArrayInputStream(byteArrayOf()),
                ByteArrayOutputStream()
            )
        }
        val endless = object : InputStream() {
            override fun read(): Int = 0
            override fun read(bytes: ByteArray, offset: Int, length: Int): Int = length
        }
        var copied = 0
        val sink = object : java.io.OutputStream() {
            override fun write(value: Int) {
                copied++
            }

            override fun write(bytes: ByteArray, offset: Int, length: Int) {
                copied += length
            }
        }
        assertThrows(IllegalArgumentException::class.java) { SubtitleImport.copy(endless, sink) }
        assertEquals(SubtitleImport.MAX_BYTES, copied)
    }
}
