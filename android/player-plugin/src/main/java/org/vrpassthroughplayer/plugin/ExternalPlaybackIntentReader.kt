package org.vrpassthroughplayer.plugin

import android.content.Intent
import android.net.Uri

/** Read only named, typed inputs; arbitrary extras never reach Godot. */
internal object ExternalPlaybackIntentReader {
    @Suppress("DEPRECATION")
    fun read(source: Intent, roots: List<java.io.File>): ExternalPlaybackRequest {
        require(source.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0)
        require((source.clipData?.itemCount ?: 0) <= 1)
        require(!source.hasExtra("headers") && !source.hasExtra("android.media.intent.extra.HTTP_HEADERS"))
        val uri = if (source.action == Intent.ACTION_SEND) source.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) else source.data
        return ExternalPlaybackRequest.parse(source.action, uri?.toString(), source.getStringExtra(Intent.EXTRA_TITLE)
            ?: source.getStringExtra("title"), source.type, source.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0, roots)
    }
}
