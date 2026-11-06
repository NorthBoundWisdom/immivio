package org.vrpassthroughplayer.plugin

import org.json.JSONArray

/** Validate at the platform boundary and again against the native current track list. */
internal object SecondarySubtitleSelection {
    private val codecs =
        setOf(
            "subrip",
            "ass",
            "ssa",
            "webvtt",
            "mov_text",
            "text",
            "sami",
            "microdvd",
            "subviewer",
            "ttml",
        )

    fun request(id: Int, tracks: JSONArray, select: (Int) -> Long): Long {
        if (
            id < 0 ||
                (id > 0 &&
                    tracks.objects().none {
                        it.optInt("id") == id && it.optString("codec") in codecs
                    })
        )
            return 0
        return select(id)
    }
}
