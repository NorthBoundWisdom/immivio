package org.vrpassthroughplayer.plugin

import org.junit.Assert.*
import org.junit.Test

class ReleasePageOpenerTest {
    @Test
    fun actualUiLaunchFailureAndSuccessAreReportedAfterDispatch() {
        val queued = mutableListOf<() -> Unit>()
        val results = mutableListOf<Triple<Int, String, Boolean>>()
        val urls = mutableListOf<String>()
        var missingBrowser = true
        val opener =
            ReleasePageOpener(
                { true },
                { queued.add(it) },
                { url ->
                    urls.add(url)
                    if (missingBrowser)
                        throw IllegalStateException("No Activity can handle ACTION_VIEW")
                },
                { id, tag, ok -> results.add(Triple(id, tag, ok)) },
            )
        assertTrue(opener.open("v1.2.3") > 0)
        assertTrue(results.isEmpty())
        queued.removeAt(0).invoke()
        assertEquals(listOf(Triple(1, "v1.2.3", false)), results)
        missingBrowser = false
        assertTrue(opener.open("v1.2.3") > 0)
        queued.removeAt(0).invoke()
        assertEquals(Triple(2, "v1.2.3", true), results.last())
        assertTrue(
            urls.all { it == "https://github.com/NorthBoundWisdom/immivio/releases/tag/v1.2.3" }
        )
    }

    @Test
    fun invalidTagsAndClosedOwnersCannotLaunchOrReportLateResults() {
        val queued = mutableListOf<() -> Unit>()
        var active = true
        var calls = 0
        val opener =
            ReleasePageOpener({ active }, { queued.add(it) }, { calls++ }, { _, _, _ -> calls++ })
        assertEquals(-1, opener.open("https://evil.example"))
        assertTrue(queued.isEmpty())
        assertTrue(opener.open("v1.2.3") > 0)
        active = false
        queued.removeAt(0).invoke()
        assertEquals(0, calls)
        assertEquals(-1, opener.open("v1.2.3"))
        val unavailableQueue =
            ReleasePageOpener(
                { true },
                { throw IllegalStateException("No host") },
                { calls++ },
                { _, _, _ -> calls++ },
            )
        assertEquals(-1, unavailableQueue.open("v1.2.3"))
        assertEquals(0, calls)
    }
}
