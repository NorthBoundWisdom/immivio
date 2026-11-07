package org.vrpassthroughplayer.plugin

import android.view.Surface
import org.json.JSONArray
import org.json.JSONObject

/** One Android Surface per eye; Godot retains ordinary GLES render-target ownership. */
object XrPointerSurfaceBridge {
    private val eyes = Array(2) { XrUiSurfacePresenter() }

    @JvmStatic fun contextGeneration(): Int = eyes[0].contextGeneration()

    @JvmStatic
    fun attachSurface(eye: Int, surface: Surface?) {
        eyes.getOrNull(eye)?.attachSurface(surface)
    }

    @JvmStatic
    fun submitTexture(
        eye: Int,
        texture: Int,
        width: Int,
        height: Int,
        generation: Int,
        serial: Long,
    ) {
        eyes.getOrNull(eye)?.submitTexture(texture, width, height, generation, serial)
    }

    @JvmStatic
    fun setEnabled(enabled: Boolean) {
        eyes.forEach { it.setEnabled(enabled) }
    }

    @JvmStatic fun status(): String = JSONArray(eyes.map { JSONObject(it.status()) }).toString()

    fun contextCreated() = eyes.forEach { it.contextCreated() }

    fun draw() = eyes.forEach { it.draw() }
}
