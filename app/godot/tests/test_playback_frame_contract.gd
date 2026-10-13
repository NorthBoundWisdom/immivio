extends SceneTree
const Contract := preload("res://scripts/playback_frame_contract.gd")
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _initialize() -> void:
	var pair := {"contract_version": 2, "session_id": 1, "logical_session_id": 2, "generation": 3,
		"source_epoch": 4, "frame_id": 7, "pts_us": 233333, "format_revision": 1, "presentation_revision": 1,
		"slot_token": 8, "color_texture_id": 10, "alpha_texture_id": 11, "width": 64, "height": 32,
		"alpha_width": 32, "alpha_height": 16, "color_target": "texture", "mask_kind": "opaque",
		"rotation_degrees": 0, "stereo_sbs": true, "top_bottom": false, "mask_content_rect": [0, 0, 1, 1],
		"alpha_slot_token": 8, "alpha_frame_id": 7, "alpha_pts_us": 233333, "source_pts_verified": true,
		"immutable_color_frame": true, "pair_identity_verified": true, "consumer_copy_fence_ready": true,
		"alpha_fence_ready": true, "alpha_gpu_uploaded": true, "alpha_texture_format": "GL_R8_numeric"}
	check(Contract.valid(pair), "Complete v2 source color/mask pair is accepted")
	for change in [{"contract_version": 1}, {"model_generation": 1}, {"slot_token": 8.5},
		{"slot_token": 9007199254740992.0}, {"alpha_slot_token": 9}, {"alpha_pts_us": 233334},
		{"consumer_copy_fence_ready": false}, {"alpha_fence_ready": 1}, {"alpha_texture_id": 10},
		{"color_target": "external"}, {"width": 9000}, {"mask_content_rect": [0, 0, NAN, 1]}]:
		var invalid := pair.duplicate(true)
		invalid.merge(change, true)
		check(not Contract.valid(invalid), "Reject mismatched, incomplete or retired descriptor: %s" % change)
	var estimated := pair.duplicate(true)
	estimated.source_pts_verified = false
	estimated.source_ticket_origin = "standard_libmpv_render"
	estimated.source_ticket_valid = true
	check(Contract.valid(estimated), "Explicit public playback-clock provenance is accepted")
	estimated.source_ticket_valid = false
	check(not Contract.valid(estimated), "An unverified clock cannot authorize a frame")
	for failure in failures: push_error(failure)
	print("Playback frame contract: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
