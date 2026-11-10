package org.vrpassthroughplayer.plugin

import org.junit.Assert.*
import org.junit.Test

class HeadsetPresenceStateTest {
    @Test
    fun alreadyOffDisplayIsAbsenceWithoutWaitingForBroadcast() {
        val state = HeadsetPresenceState()
        assertEquals(false, state.screen(false))
        assertNull(state.screen(false))
        assertNull(state.proximity(true))
        assertEquals(true, state.screen(true))
    }

    @Test
    fun farSensorKeepsScreenWakeAbsentUntilNear() {
        val state = HeadsetPresenceState()
        assertEquals(false, state.proximity(false))
        assertNull(state.screen(true))
        assertEquals(true, state.proximity(true))
        assertNull(state.proximity(true))
    }

    @Test
    fun unknownSensorStillAllowsDisplayFallback() {
        val state = HeadsetPresenceState()
        assertEquals(true, state.screen(true))
        assertEquals(false, state.screen(false))
        assertEquals(true, state.screen(true))
    }

    @Test
    fun closedStateRejectsQueuedCallbacks() {
        val state = HeadsetPresenceState()
        state.screen(false)
        state.close()
        state.close()
        assertNull(state.screen(true))
        assertNull(state.proximity(true))
        assertNull(state.proximity(false))
    }
}
