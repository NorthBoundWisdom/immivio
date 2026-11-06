package org.vrpassthroughplayer.plugin

import java.io.File
import java.io.InputStream

/** Originals remain untouched. Session-owned copies have stable non-secret title keys. */
internal object SubtitleCopies {
    fun key(title: String): String =
        java.security.MessageDigest.getInstance("SHA-256")
            .digest(title.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    data class Prepared(
        val track: SidecarSubtitles.Track,
        val file: File?,
        val key: String,
        val encodingInvalid: Boolean = false,
    )

    fun prepare(
        track: SidecarSubtitles.Track,
        directory: File,
        choices: Map<String, String>,
        open: (String) -> InputStream,
    ): Prepared {
        val key = key(track.identity)
        val selected = choices[key] ?: "auto"
        var file: File? = null
        return try {
            val extension =
                java.net.URI(track.location).path.orEmpty().substringAfterLast('.', "srt").takeIf {
                    it.lowercase() in setOf("srt", "ass", "ssa", "vtt", "smi", "sami", "sub")
                } ?: "srt"
            val staged = File.createTempFile("subtitle-", ".$extension", directory)
            file = staged
            open(track.location).use { write(it, staged, selected) }
            Prepared(
                SidecarSubtitles.Track(staged.absolutePath, track.title, track.identity),
                staged,
                key,
            )
        } catch (_: Exception) {
            file?.delete()
            // Discovery owns the original lease. mpv retains its pre-transcoding fallback.
            Prepared(track, null, key, encodingInvalid = selected != "auto")
        } catch (error: Throwable) {
            file?.delete()
            throw error
        }
    }

    fun read(input: InputStream): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            if (count == 0) continue
            require(count <= SubtitleEncoding.MAX_BYTES - output.size()) {
                "Subtitle exceeds 8 MiB"
            }
            output.write(buffer, 0, count)
        }
        require(output.size() > 0) { "Subtitle file is empty" }
        return output.toByteArray()
    }

    fun write(input: InputStream, destination: File, encoding: String) {
        val decoded =
            SubtitleEncoding.decode(read(input), encoding, detect = SubtitleCharsetDetector::detect)
        destination.writeBytes(decoded.bytes)
    }
}
