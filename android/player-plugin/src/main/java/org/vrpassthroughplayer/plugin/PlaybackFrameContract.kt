package org.vrpassthroughplayer.plugin

import org.json.JSONObject

/** Versioned opaque playback descriptor. Texture lifetime belongs to display leases. */
internal object PlaybackFrameContract {
    const val VERSION = 2
    const val MASK_FORMAT = "GL_R8_numeric"
    const val INVALID_SOURCE = "MPV_FRAME_CONTRACT_INVALID"
    private val retired = listOf("model_generation", "effect_revision", "model_content_rect", "input_width",
        "input_height", "input_layout", "profile_key", "alpha_requested", "depth_requested", "inference_ran", "depth_ran", "warp_texture_id")

    fun color(source: JSONObject, scope: MediaSessionGate.Scope, token: Long, host: Long, stereo: Boolean, topBottom: Boolean): JSONObject {
        check(source.getBoolean("source_ticket_valid") && source.getBoolean("producer_fence_ready") && source.getBoolean("owner_context_shared")) { INVALID_SOURCE }
        check(source.getLong("frame_id") >= 0 && source.getLong("pts_us") >= 0 && source.getLong("source_epoch") > 0) { INVALID_SOURCE }
        retired.forEach(source::remove)
        return source.put("contract_version", VERSION).put("presentation_revision", 1).put("format_revision", 1)
            .put("producer_color_texture_id", source.getInt("color_texture_id")).put("mpv_source_handle", host)
            .put("godot_context_shared", true).put("slot_token", token).put("session_id", scope.decoderId)
            .put("logical_session_id", scope.logicalSessionId).put("generation", scope.generation)
            .put("color_target", "texture").put("mask_kind", "opaque").put("stereo_sbs", stereo)
            .put("top_bottom", topBottom).put("immutable_color_frame", true)
    }
    fun complete(pair: JSONObject, texture: Int, mask: Int, maskWidth: Int, maskHeight: Int): JSONObject =
        pair.put("color_texture_id", texture).put("consumer_copy_fence_ready", true).put("pair_identity_verified", true)
            .put("alpha_texture_id", mask).put("alpha_width", maskWidth * 2).put("alpha_height", maskHeight)
            .put("mask_content_rect", org.json.JSONArray(listOf(0.0, 0.0, 1.0, 1.0)))
            .put("alpha_texture_format", MASK_FORMAT).put("alpha_gpu_uploaded", true).put("alpha_fence_ready", true)
            .put("alpha_slot_token", pair.getLong("slot_token")).put("alpha_frame_id", pair.getLong("frame_id"))
            .put("alpha_pts_us", pair.getLong("pts_us"))

    fun identity(pair: JSONObject): FramePairGate.Identity {
        check(pair.getInt("contract_version") == VERSION) { INVALID_SOURCE }
        return FramePairGate.Identity(pair.getInt("session_id"), pair.getInt("logical_session_id"),
            pair.getInt("generation"), pair.getLong("frame_id"), pair.getLong("pts_us"), pair.getInt("format_revision"),
            pair.getLong("presentation_revision"), pair.getLong("slot_token"),
            !pair.optBoolean("source_pts_verified") && pair.optString("source_ticket_origin") == "standard_libmpv_render" && pair.optBoolean("source_ticket_valid"))
    }
}
