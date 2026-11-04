package org.vrpassthroughplayer.plugin
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class SecondarySubtitleSelectionTest {
    @Test fun validatesTextAndExternalTracksBeforeNativeDispatch() {
        val tracks = JSONArray("""[{"id":2,"codec":"subrip"},{"id":5,"codec":"hdmv_pgs_subtitle"},
            {"id":8,"codec":"ass","external":true},{"id":9,"codec":""}]""")
        val calls = mutableListOf<Int>()
        fun request(id: Int) = SecondarySubtitleSelection.request(id, tracks) { calls.add(it); 7L }
        for (id in listOf(-2, -1, 1, 5, 9, Int.MAX_VALUE)) assertEquals(0L, request(id))
        assertTrue(calls.isEmpty())
        for (id in listOf(0, 2, 8)) assertEquals(7L, request(id))
        assertEquals(listOf(0, 2, 8), calls)
        assertEquals(0L, SecondarySubtitleSelection.request(2, JSONArray()) { error("Missing track dispatched") })
        assertEquals(0L, SecondarySubtitleSelection.request(2, tracks) { 0L })
    }
}
