package org.vrpassthroughplayer.plugin

/** Shared redaction for playback messages and retained diagnostics. */
internal object PlaybackErrors {
    private val sources = Regex("(?i)(?:https?|smb|file|content|medialib|externalvideo|user)://[^\\s\"<>]+")
    private val secrets = Regex("""(?im)((?:["']?)(?:token|access_token|refresh_token|password|passwd|pwd|pw|authorization|cookie|set-cookie|api[_-]?key|signature|username|user_name|user_id|account|account_name|email|key|secret|client_secret)(?:["']?)\s*[:=]\s*)(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\r\n,;}\]]+)""")
    fun diagnostic(message: String?): String = message.orEmpty().take(512 * 1024)
        .replace(sources, "[source]").replace(secrets, "$1[redacted]")
        .replace(Regex("""(?:/storage/|/sdcard/|/data/user/|/Users/)[^\s"<>]+"""), "[path]")
    fun safe(message: String?): String = diagnostic(message).replace(Regex("[\r\n\t]+"), " ").take(400)
}
