package org.vrpassthroughplayer.plugin

/** Only videos and STRM shortcuts are selectable media. Covers are fetched separately. */
internal object MediaKinds {
    fun supported(name: String) = StrmFile.named(name) || DlnaClient.isVideoName(name)
}
