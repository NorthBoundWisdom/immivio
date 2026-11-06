package org.vrpassthroughplayer.plugin

import org.junit.Assert.*
import org.junit.Test

class SubtitleCandidatesTest {
    @Test
    fun candidatesAreTextFilesInThisDirectoryAndRemainBounded() {
        val names =
            listOf(
                "film.ZH.SRT",
                "film.mp4",
                "folder/film.srt",
                "folder\\film.srt",
                "other.ass",
                "film.smi",
            )
        assertEquals(
            listOf("film.smi", "film.ZH.SRT", "other.ass"),
            SidecarSubtitles.candidates(names),
        )
        assertEquals(128, SidecarSubtitles.candidates((1..1000).map { "$it.srt" }).size)
        assertEquals("smi", SubtitleImport.extension("film.smi"))
    }
}
