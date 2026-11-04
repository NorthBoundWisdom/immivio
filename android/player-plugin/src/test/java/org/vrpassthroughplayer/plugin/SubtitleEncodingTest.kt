package org.vrpassthroughplayer.plugin

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.nio.charset.Charset

class SubtitleEncodingTest {
    // Detection fixtures adapted from Thru3D 0.16.5 (GPL-3.0).
    private fun detect(bytes: ByteArray) = SubtitleCharsetDetector.detect(bytes)
    private fun decode(bytes: ByteArray, choice: String = "auto", language: String = "") =
        SubtitleEncoding.decode(bytes, choice, language, ::detect)
    private fun smi(text: String, header: String = "") = "<SAMI><HEAD>$header</HEAD><BODY>\n" +
        (1..15).joinToString("\n") { "<SYNC Start=${it*2000}><P Class=SUBCC>$text" } + "\n<SYNC Start=32000><P>&nbsp;</BODY></SAMI>"
    @Test fun detectsKoreanChineseAndJapaneseWithoutLanguageHints() {
        val cases = listOf(
            "x-windows-949" to "안녕하세요. 오늘은 날씨가 정말 좋습니다. 우리는 함께 영화를 보고 있습니다. 괜찮아요, 내일 다시 만나요!",
            "GBK" to "你好，今天的天气真好。我们一起去看电影吧！这是一个关于朋友和家人的故事。现在开始播放中文字幕。",
            "Big5" to "你好，今天的天氣真好。我們一起去看電影吧！這是一個關於朋友和家人的故事。現在開始播放中文字幕。",
            "windows-31j" to "こんにちは。今日はとてもいい天気ですね。みんなで映画を見に行きましょう。これは友達と家族のお話です。"
        )
        for ((encoding, text) in cases) {
            for (source in listOf(smi(text), "1\n00:00:01,000 --> 00:00:05,000\n" + text.repeat(8))) {
                val result = decode(source.toByteArray(Charset.forName(encoding)))
                assertEquals("$encoding detected as ${result.charset}", source, result.bytes.toString(Charsets.UTF_8))
            }
        }
    }
    @Test fun cp949ExtensionAndSamiLanguageAreHandled() {
        val source = smi("똠방각하 뷁 쀍 똠방각하 뷁 쀍", "<STYLE>.KRCC { Name:Korean; lang:ko-KR; SAMIType:CC; }</STYLE>")
        val bytes = source.toByteArray(Charset.forName("x-windows-949"))
        assertEquals(source, decode(bytes).bytes.toString(Charsets.UTF_8))
        assertEquals(source, decode(bytes, "EUC-KR").bytes.toString(Charsets.UTF_8))
        val withoutHints = smi("똠방각하 뷁 쀍 똠방각하 뷁 쀍")
        assertEquals(withoutHints, decode(withoutHints.toByteArray(Charset.forName("x-windows-949"))).bytes.toString(Charsets.UTF_8))
    }
    @Test fun unicodeAndStaleDeclarationsNeverRegress() {
        val source = smi("한국어 中文 日本語 😀", "<meta charset=EUC-KR>")
        for (encoding in listOf("UTF-8", "UTF-16LE", "UTF-16BE")) {
            val bytes = (if (encoding == "UTF-8") "" else "\uFEFF") + source
            assertEquals(source, decode(bytes.toByteArray(Charset.forName(encoding))).bytes.toString(Charsets.UTF_8))
        }
        assertEquals(source, decode(("\uFEFF"+source).toByteArray()).bytes.toString(Charsets.UTF_8))
    }
    @Test fun explicitChoiceCorrectsAmbiguityAndDoesNotChangeOriginalBytes() {
        val source = smi("한국어 자막 테스트", "<meta charset=GBK>")
        val bytes = source.toByteArray(Charset.forName("x-windows-949")); val copy = bytes.copyOf()
        assertEquals(source, decode(bytes, "windows-949").bytes.toString(Charsets.UTF_8))
        assertArrayEquals(copy, bytes)
        assertThrows(Exception::class.java) { decode(bytes, "UTF-8") }
        assertThrows(Exception::class.java) { decode(bytes, "unknown") }
    }
    @Test fun asciiAndBinaryLimits() {
        assertEquals("UTF-8", decode(smi("Hello!").toByteArray()).charset)
        assertThrows(Exception::class.java) { decode(byteArrayOf(0, 1, 2, 0, 3)) }
        assertThrows(Exception::class.java) { decode(ByteArray(SubtitleEncoding.MAX_BYTES + 1)) }
    }

    @Test fun unicodeAndLegacyCopiesPreserveOriginals() {
        for ((encoding, text) in listOf("UTF-8" to "字幕", "UTF-16LE" to "字幕", "GB18030" to "简体中文", "Big5" to "繁體中文", "windows-31j" to "こんにちは", "x-windows-949" to "한국어", "windows-1252" to "élève")) {
            val bytes = text.toByteArray(Charset.forName(encoding)); val original = bytes.copyOf()
            val decoded = SubtitleEncoding.decode(bytes, encoding, detect = SubtitleCharsetDetector::detect)
            assertEquals(text, decoded.bytes.toString(Charsets.UTF_8)); assertArrayEquals(original, bytes)
        }
        assertEquals("UTF-8", SubtitleEncoding.decode("subtitle".toByteArray(), detect = SubtitleCharsetDetector::detect).charset)
        assertTrue(SubtitleCharsetDetector.detect("字幕内容测试".toByteArray(Charset.forName("GB18030"))).isNotEmpty())
    }
    @Test fun stagedOverridesSurviveReorderedSidecarsAndNeverRewriteTheOriginal() {
        val directory = java.nio.file.Files.createTempDirectory("stable-subtitle").toFile()
        try {
            val original = java.io.File(directory, "movie.zh.srt")
            val text = "1\n00:00:01,000 --> 00:00:02,000\n漢字字幕\n"
            val bytes = text.toByteArray(Charsets.UTF_16LE) // no BOM: explicit override is required
            original.writeBytes(bytes)
            val selected = SidecarSubtitles.Track(original.toURI().toString(), original.name)
            val choices = mapOf(SubtitleCopies.key(selected.identity) to "UTF-16LE")
            for (listing in listOf(listOf(selected), listOf(SidecarSubtitles.Track("file:///other.srt", "movie.en.srt"), selected))) {
                val track = listing.first { it.title == original.name }
                val staged = SubtitleCopies.prepare(track, directory, choices) { original.inputStream() }
                assertEquals(text, staged.file.readText(Charsets.UTF_8))
                assertArrayEquals(bytes, original.readBytes())
                staged.file.delete()
            }
            assertNotEquals(SubtitleCopies.key(SidecarSubtitles.Track("a", "English", "server-stream-1").identity),
                SubtitleCopies.key(SidecarSubtitles.Track("b", "English", "server-stream-2").identity))
        } finally { directory.deleteRecursively() }
    }
    @Test fun rejectsOversizeAndBadOverride() {
        assertThrows(IllegalArgumentException::class.java) { SubtitleCopies.read(ByteArrayInputStream(ByteArray(SubtitleEncoding.MAX_BYTES + 1))) }
        assertThrows(IllegalStateException::class.java) { SubtitleEncoding.decode(byteArrayOf(0xff.toByte()), "UTF-8", detect = SubtitleCharsetDetector::detect) }
    }
}
