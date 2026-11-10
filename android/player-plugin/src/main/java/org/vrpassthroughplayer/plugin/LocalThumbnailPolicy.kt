package org.vrpassthroughplayer.plugin

import java.net.URI
import kotlin.math.max
import kotlin.math.min

/** Thumbnail requests never resolve shortcuts or open network sources. */
internal object LocalThumbnailPolicy {
    fun path(uri: String): String? = runCatching {
        val parsed = URI(uri)
        val path = parsed.path ?: return@runCatching null
        if (
            uri.length > 8192 ||
                parsed.scheme != "file" ||
                !parsed.rawAuthority.isNullOrEmpty() ||
                parsed.query != null ||
                parsed.fragment != null ||
                !DlnaClient.isVideoName(path) ||
                StrmFile.named(path)
        )
            null
        else path.takeIf { it.startsWith("/") }
    }
        .getOrNull()

    fun size(width: Int, height: Int): Pair<Int, Int>? {
        if (width <= 0 || height <= 0 || width > 65536 || height > 65536) return null
        val scale = min(1.0, min(1280.0 / width, 720.0 / height))
        return max(1, (width * scale).toInt()) to max(1, (height * scale).toInt())
    }
}
