package org.vrpassthroughplayer.plugin

import java.io.InputStream
import java.io.OutputStream

/** Bounded, session-owned copies allow document-provider subtitles to outlive its picker. */
internal object SubtitleImport {
    const val MAX_BYTES = 16 * 1024 * 1024
    fun extension(name: String): String = name.substringAfterLast('.', "").lowercase().also {
        require(it in setOf("srt", "ass", "ssa", "vtt")) { "Choose an SRT, ASS, SSA or VTT subtitle" }
    }
    fun copy(input: InputStream, output: OutputStream): Int {
        val buffer = ByteArray(8192)
        var total = 0
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            if (count == 0) continue
            require(count <= MAX_BYTES - total) { "Subtitle exceeds 16 MiB" }
            output.write(buffer, 0, count); total += count
        }
        require(total > 0) { "Subtitle file is empty" }
        return total
    }
}
