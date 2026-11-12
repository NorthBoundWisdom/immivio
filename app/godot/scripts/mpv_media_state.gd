extends RefCounted
# Mirrors a native session without treating a SurfaceTexture timestamp as source PTS.
var session_id := 0
var logical_session_id := 0
var generation := 0
var format_revision := 0
var presentation_revision := 0
var state := "closed"
var error := ""
var frame_counter := 0
var format := {"width": 0, "height": 0, "pixel_aspect": 1.0, "unapplied_rotation_degrees": 0}
var playback: Dictionary = {}
var decoder := ""
var last_pair: Dictionary = {}


func begin(id: int) -> void:
	session_id = id
	logical_session_id = 0
	generation = 0
	format_revision = 0
	presentation_revision = 0
	last_pair = {}
	state = "opening" if id > 0 else "failed"
	error = "" if id > 0 else "MEDIA_OPEN_REJECTED"
	frame_counter = 0
	format = {"width": 0, "height": 0, "pixel_aspect": 1.0, "unapplied_rotation_degrees": 0}
	playback = {}
	decoder = ""


func accepts(id: int) -> bool:
	return id > 0 and id == session_id and state not in ["closed", "failed"]


func frame_identity() -> Dictionary:
	if last_pair.is_empty():
		return {"source_pts_verified": false, "immutable_color_frame": false}
	var result: Dictionary = {}
	for key in [
		"session_id",
		"logical_session_id",
		"generation",
		"frame_id",
		"pts_us",
		"source_epoch",
		"contract_version",
		"format_revision",
		"presentation_revision",
		"slot_token",
		"source_pts_verified",
		"source_ticket_origin",
		"source_ticket_valid",
		"immutable_color_frame",
		"pair_identity_verified",
		"mask_kind"
	]:
		result[key] = last_pair.get(key)
	return result


func close() -> void:
	session_id = 0
	logical_session_id = 0
	generation = 0
	state = "closed"
	frame_counter = 0


func snapshot() -> Dictionary:
	return {
		"session_id": session_id,
		"state": state,
		"error": error,
		"logical_session_id": logical_session_id,
		"generation": generation,
		"presentation_identity": frame_identity(),
		"frame_counter": frame_counter,
		"format": format,
		"playback": playback,
		"decoder": decoder,
		"presentation_revision": presentation_revision,
		"backend": "Android_libmpv",
		"device_validation": "pending"
	}
