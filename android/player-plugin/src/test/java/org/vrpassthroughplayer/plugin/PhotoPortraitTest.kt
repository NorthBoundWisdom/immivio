package org.vrpassthroughplayer.plugin

import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files
import java.io.File

class PhotoPortraitTest {
    @Test fun quantizationPreservesTransparentOpaqueAndSoftEdges() {
        assertEquals(0, PhotoPortrait.alphaByte(0f))
        assertEquals(255, PhotoPortrait.alphaByte(1f))
        assertEquals(128, PhotoPortrait.alphaByte(0.5f))
        assertEquals(1, PhotoPortrait.alphaByte(1f/255))
        assertEquals(254, PhotoPortrait.alphaByte(254f/255))
    }
    @Test fun invalidModelOutputsAreRejected() {
        for (value in listOf(Float.NaN,Float.POSITIVE_INFINITY,-0.01f,1.01f)) {
            try { PhotoPortrait.alphaByte(value); fail("invalid alpha $value") }
            catch (_: IllegalArgumentException) { }
        }
    }
    @Test fun liveAdjustmentsKeepOnlyThreeMatteFilesAndPreserveSourceMask() {
        val directory = Files.createTempDirectory("photo-portrait-cache").toFile()
        try {
            val source = File(directory,"mask.png").apply { writeBytes(byteArrayOf(1)) }
            val unrelated = File(directory,"other.r8").apply { writeBytes(byteArrayOf(2)) }
            val mattes = (0..5).map { value ->
                File(directory,"matte-$value-2x1.r8").apply {
                    writeBytes(byteArrayOf(1,2)); assertTrue(setLastModified(1000L+value))
                }
            }
            // The active pair stays alive even when its timestamp is older than cached pairs.
            PhotoPortrait.retainRecentMattes(directory,mattes.first())
            assertEquals(listOf(mattes[0],mattes[4],mattes[5]).toSet(),mattes.filter { it.exists() }.toSet())
            assertTrue(source.exists()); assertTrue(unrelated.exists())
        } finally { directory.deleteRecursively() }
    }

}
