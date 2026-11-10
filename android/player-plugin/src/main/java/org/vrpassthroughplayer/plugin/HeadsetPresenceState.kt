package org.vrpassthroughplayer.plugin

/** Android-independent transition gate; unknown proximity never invents a removal. */
internal class HeadsetPresenceState {
    private var interactive = true
    private var near: Boolean? = null
    private var last: Boolean? = null
    private var closed = false

    fun screen(value: Boolean): Boolean? {
        if (closed) return null
        interactive = value
        return changed()
    }

    fun proximity(value: Boolean): Boolean? {
        if (closed) return null
        near = value
        return changed()
    }

    private fun changed(): Boolean? {
        val present = interactive && (near ?: true)
        if (last == present) return null
        last = present
        return present
    }

    fun close() {
        closed = true
    }
}
