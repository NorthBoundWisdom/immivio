extends RefCounted
## Version 2: immutable source color and a mask completed by the same consumer fence.
const VERSION := 2
const MAX_EXACT_INTEGER := 9007199254740991.0
const RETIRED_FIELDS := [
	"effect_revision",
	"model_generation",
	"model_content_rect",
	"input_width",
	"input_height",
	"input_layout",
	"profile_key",
	"alpha_requested",
	"depth_requested",
	"inference_ran",
	"depth_ran",
	"warp_texture_id"
]
const POSITIVE_IDS := [
	"session_id",
	"logical_session_id",
	"generation",
	"source_epoch",
	"format_revision",
	"presentation_revision",
	"slot_token",
	"color_texture_id",
	"alpha_texture_id",
	"width",
	"height",
	"alpha_width",
	"alpha_height"
]


static func _integer(value: Variant, positive: bool = true) -> bool:
	if not (value is int or value is float):
		return false
	var number := float(value)
	return (
		is_finite(number)
		and absf(number) <= MAX_EXACT_INTEGER
		and number == floorf(number)
		and number >= (1.0 if positive else 0.0)
	)


static func timing_valid(pair: Dictionary) -> bool:
	return (
		pair.get("source_pts_verified", false) == false
		and pair.get("source_ticket_origin", "") == "standard_libmpv_render"
		and pair.get("source_ticket_valid", false) == true
	)


static func error(pair: Dictionary) -> String:
	if pair.get("contract_version") != VERSION:
		return "FRAME_CONTRACT_VERSION"
	for key in RETIRED_FIELDS:
		if pair.has(key):
			return "FRAME_RETIRED_FIELD"
	for key in POSITIVE_IDS:
		if not _integer(pair.get(key)):
			return "FRAME_INTEGER_ID"
	for key in ["frame_id", "pts_us", "alpha_frame_id", "alpha_pts_us"]:
		if not _integer(pair.get(key), false):
			return "FRAME_TIMESTAMP"
	if (
		int(pair.width) > 8192
		or int(pair.height) > 8192
		or int(pair.width) * int(pair.height) > 8192 * 4320
		or int(pair.alpha_width) > 1024
		or int(pair.alpha_height) > 512
	):
		return "FRAME_DIMENSIONS"
	if not timing_valid(pair):
		return "FRAME_TIMING_PROVENANCE"
	for key in [
		"immutable_color_frame",
		"pair_identity_verified",
		"consumer_copy_fence_ready",
		"alpha_fence_ready",
		"alpha_gpu_uploaded"
	]:
		if not pair.get(key) is bool or pair.get(key) != true:
			return "FRAME_FENCE"
	if pair.get("color_target") != "texture" or pair.get("alpha_texture_format") != "GL_R8_numeric":
		return "FRAME_TEXTURE_FORMAT"
	if pair.get("mask_kind") not in ["opaque", "numeric"]:
		return "FRAME_MASK_KIND"
	if pair.color_texture_id == pair.alpha_texture_id:
		return "FRAME_TEXTURE_ALIAS"
	if (
		pair.get("alpha_slot_token") != pair.slot_token
		or pair.alpha_frame_id != pair.frame_id
		or pair.alpha_pts_us != pair.pts_us
	):
		return "FRAME_MASK_IDENTITY"
	if not pair.get("stereo_sbs") is bool or not pair.get("top_bottom", false) is bool:
		return "FRAME_LAYOUT"
	if (
		int(pair.alpha_width) % 2 != 0
		or int(pair.get("rotation_degrees", -1)) not in [0, 90, 180, 270]
	):
		return "FRAME_LAYOUT"
	if (
		pair.stereo_sbs
		and int(pair.height if pair.get("top_bottom", false) else pair.width) % 2 != 0
	):
		return "FRAME_LAYOUT"
	var rect: Variant = pair.get("mask_content_rect")
	if not rect is Array or rect.size() != 4:
		return "FRAME_MASK_RECT"
	for value in rect:
		if not (value is int or value is float) or not is_finite(float(value)):
			return "FRAME_MASK_RECT"
	for axis in [0, 1]:
		var offset := float(rect[axis])
		var scale := float(rect[axis + 2])
		if offset < 0.0 or scale <= 0.0 or offset + scale > 1.000001:
			return "FRAME_MASK_RECT"
		var size := float(pair.alpha_width) * 0.5 if axis == 0 else float(pair.alpha_height)
		if ceilf(offset * size - 0.5) > floorf((offset + scale) * size - 0.5):
			return "FRAME_MASK_RECT"
	return ""


static func valid(pair: Dictionary) -> bool:
	return error(pair).is_empty()
