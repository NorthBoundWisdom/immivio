package org.vrpassthroughplayer.plugin

/** Never expose signed URLs, credentials or local paths through playback diagnostics. */
internal object PlaybackErrors {
    fun safe(message: String?): String = message.orEmpty()
        .replace(Regex("(?i)(?:https?|smb|file|content|medialib)://[^\\s\"<>]+"), "[source]")
        .replace(Regex("(?i)(token|password|authorization|api_key|signature)\\s*[:=]\\s*[^\\s,;]+"), "$1=[redacted]")
        .replace(Regex("[\\r\\n\\t]+"), " ").take(400)
}
