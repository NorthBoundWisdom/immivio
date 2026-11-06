package org.vrpassthroughplayer.plugin

import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class CrashRecordsTest {
    @Test
    fun privateTrailSurvivesReopenAndExceptionDelegationDoesNotExport() {
        val folder = Files.createTempDirectory("crash-records").toFile()
        try {
            val ring = java.io.File(folder, "trail.bin")
            assertNull(CrashTrail.open(ring, 1, 100))
            CrashTrail.mark(
                "source.open",
                "https://user:pass@host/file?signature=secret username=private",
            )
            repeat(600) { CrashTrail.mark("frame.stage", "count=$it") }
            CrashTrail.detach()
            val previous = CrashTrail.open(ring, 2, 200)!!
            assertEquals(512, previous.lines.size)
            assertTrue(previous.lines.last().contains("count=599"))
            var delegated = false
            val handler =
                CrashRecords.handler(
                    folder,
                    Thread.UncaughtExceptionHandler { _, _ -> delegated = true },
                )
            handler.uncaughtException(
                Thread.currentThread(),
                IllegalStateException("token=topsecret password=hidden"),
            )
            assertTrue(delegated)
            assertTrue(CrashRecords.recover(folder, previous, "native crash reason=5"))
            val report = java.io.File(folder, "last-report.txt").readText()
            assertFalse(report.contains("topsecret"))
            assertFalse(report.contains("hidden"))
            assertTrue(report.contains("native crash reason=5"))
            assertTrue(
                folder.listFiles()!!.all { it.name in setOf("trail.bin", "last-report.txt") }
            )
            CrashTrail.cleanExit()
            CrashTrail.detach()
            assertTrue(CrashTrail.open(ring, 3, 300)!!.clean)
        } finally {
            CrashTrail.detach()
            folder.deleteRecursively()
        }
    }
}
