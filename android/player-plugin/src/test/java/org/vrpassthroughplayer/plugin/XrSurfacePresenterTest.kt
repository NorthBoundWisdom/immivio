package org.vrpassthroughplayer.plugin

import org.junit.Assert.assertEquals
import org.junit.Test

class XrSurfacePresenterTest {
    @Test
    fun eyeFramesNeverReplaceEachOther() {
        val left = XrSurfaceFrames()
        val right = XrSurfaceFrames()
        left.submit(101, 1536, 1536, left.contextGeneration(), 7)
        right.submit(202, 1536, 1536, right.contextGeneration(), 8)
        assertEquals(101, left.current()?.texture)
        assertEquals(202, right.current()?.texture)
    }

    @Test
    fun contextLossRejectsFramesFromThePreviousGeneration() {
        val presenter = XrSurfaceFrames()
        val old = presenter.contextGeneration()
        presenter.submit(101, 1536, 1536, old, 7)
        presenter.contextCreated()
        presenter.submit(202, 1536, 1536, old, 8)
        assertEquals(0, presenter.current()?.texture ?: 0)
        presenter.submit(303, 1536, 1536, presenter.contextGeneration(), 9)
        assertEquals(303, presenter.current()?.texture ?: 0)
    }

    @Test
    fun invalidTextureOrSizeCannotReplaceAValidFrame() {
        val presenter = XrSurfaceFrames()
        val generation = presenter.contextGeneration()
        presenter.submit(101, 1536, 1536, generation, 7)
        presenter.submit(0, 1536, 1536, generation, 8)
        presenter.submit(202, 0, 1536, generation, 9)
        presenter.submit(303, 1536, 4097, generation, 10)
        assertEquals(101, presenter.current()?.texture ?: 0)
    }
}
