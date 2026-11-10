package org.vrpassthroughplayer.plugin

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.util.Base64
import java.io.ByteArrayOutputStream
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.json.JSONObject

/** One bounded decoder, no second disk cache. Godot owns crop, storage and eviction. */
internal class LocalVideoThumbnails(
    private val canDecode: () -> Boolean,
    private val emit: (Int, String) -> Unit,
) {
    private val generation = AtomicInteger()
    @Volatile private var closed = false
    private val worker =
        ThreadPoolExecutor(
            1,
            1,
            0,
            TimeUnit.MILLISECONDS,
            ArrayBlockingQueue(1),
            { Thread(it, "ImmivioLocalThumbnail") },
            ThreadPoolExecutor.DiscardOldestPolicy(),
        )

    fun cancel() {
        generation.incrementAndGet()
        worker.queue.clear()
    }

    fun request(id: Int, uri: String) {
        if (closed) return
        val ticket = generation.get()
        worker.execute {
            if (closed || ticket != generation.get()) return@execute
            val result =
                JSONObject().put("source", "local_thumbnail").put("uri", uri).put("state", "error")
            val path = LocalThumbnailPolicy.path(uri)
            if (!canDecode()) result.put("state", "busy")
            else if (path != null) {
                val retriever = MediaMetadataRetriever()
                var frame: Bitmap? = null
                try {
                    retriever.setDataSource(path)
                    val width =
                        retriever
                            .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                            ?.toIntOrNull() ?: 0
                    val height =
                        retriever
                            .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                            ?.toIntOrNull() ?: 0
                    val size = LocalThumbnailPolicy.size(width, height)
                    if (size != null && canDecode() && ticket == generation.get()) {
                        frame =
                            retriever.getScaledFrameAtTime(
                                1_000_000,
                                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                                size.first,
                                size.second,
                            )
                        if (frame != null && frame.width.toLong() * frame.height <= 1280L * 1280) {
                            val bytes = ByteArrayOutputStream()
                            frame.compress(Bitmap.CompressFormat.JPEG, 85, bytes)
                            if (bytes.size() <= 768 * 1024) {
                                val rotation =
                                    retriever
                                        .extractMetadata(
                                            MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION,
                                        )
                                        ?.toIntOrNull() ?: 0
                                result
                                    .put("width", if (rotation % 180 == 0) width else height)
                                    .put("height", if (rotation % 180 == 0) height else width)
                                    .put(
                                        "jpeg",
                                        Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP),
                                    )
                                    .put("state", "ready")
                            }
                        }
                    }
                } catch (_: Exception) {
                    // Unsupported media and permission failures keep the normal video icon.
                } finally {
                    frame?.recycle()
                    runCatching { retriever.release() }
                }
            }
            if (!closed && ticket == generation.get()) emit(id, result.toString())
        }
    }

    fun close() {
        closed = true
        cancel()
        worker.shutdownNow()
    }
}
