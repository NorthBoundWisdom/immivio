package org.vrpassthroughplayer.plugin

/** A validated page launch reports the actual UI-thread result, not merely queue acceptance. */
internal class ReleasePageOpener(
    private val active: () -> Boolean,
    private val post: (() -> Unit) -> Unit,
    private val launch: (String) -> Unit,
    private val report: (Int, String, Boolean) -> Unit,
) {
    private var serial = 0

    @Synchronized
    fun open(tag: String): Int {
        val url = UpdateCheck.releaseUrl(tag) ?: return -1
        if (!active()) return -1
        val id = ++serial
        try {
            post {
                if (active()) {
                    val opened = runCatching { launch(url) }.isSuccess
                    if (active()) report(id, tag, opened)
                }
            }
        } catch (_: Exception) {
            return -1
        }
        return id // Correlate the actual UI-thread completion, including repeated launches of one
        // tag.
    }
}
