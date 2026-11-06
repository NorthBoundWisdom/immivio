extends RefCounted
## Retire removed effect preferences while preserving ordinary playback data.

const RETIRED_KEYS := [
	["effects", "auto_3d"],
	["video", "depth_strength"],
	["video", "auto_depth"],
	["effects", "auto_depth"],
	["video", "alpha_requested"],
	["video", "depth_requested"],
	["video", "alpha_fps"],
]


static func apply(settings: ConfigFile, existing_file: bool = false) -> bool:
	var changed := false
	if existing_file and not settings.has_section_key("controls", "pinch_hand"):
		settings.set_value("controls", "pinch_hand", "both")
		changed = true
	if settings.has_section_key("display", "refresh_rate"):
		var rate: Variant = settings.get_value("display", "refresh_rate")
		if not (rate is int or rate is float) or not is_finite(float(rate)) or float(rate) <= 0.0:
			settings.set_value("display", "refresh_rate", 72.0)
			changed = true
	if (
		settings.has_section_key("video", "reuse_last_mode")
		and not settings.get_value("video", "reuse_last_mode") is bool
	):
		settings.set_value("video", "reuse_last_mode", false)
		changed = true
	if settings.has_section_key("video", "last_mode"):
		var previous: Variant = settings.get_value("video", "last_mode")
		var mode := preload("res://scripts/video_mode_default.gd").clean(previous)
		if previous != mode:
			settings.set_value("video", "last_mode", mode)
			changed = true
	if (
		settings.has_section_key("playback", "queue_shuffle")
		and not settings.get_value("playback", "queue_shuffle") is bool
	):
		settings.set_value("playback", "queue_shuffle", false)
		changed = true
	if settings.has_section_key("ui", "library_distance"):
		var distance: Variant = settings.get_value("ui", "library_distance")
		var normalized := 1.4
		if (distance is int or distance is float) and is_finite(float(distance)):
			normalized = clampf(float(distance), 0.8, 4.0)
		if distance != normalized:
			settings.set_value("ui", "library_distance", normalized)
			changed = true
	if settings.has_section_key("controls", "pinch_hand"):
		var hand: Variant = settings.get_value("controls", "pinch_hand")
		var normalized := preload("res://scripts/hand_preferences.gd").normalize(hand)
		if hand != normalized:
			settings.set_value("controls", "pinch_hand", normalized)
			changed = true
	for item in RETIRED_KEYS:
		if settings.has_section_key(item[0], item[1]):
			settings.erase_section_key(item[0], item[1])
			changed = true
	if settings.has_section("alpha"):
		settings.erase_section("alpha")
		changed = true
	for section in ["video"]:
		var previous: Variant = settings.get_value(section, "mode_lock", {})
		if previous is Dictionary and bool(previous.get("depth", false)):
			var migrated: Dictionary = previous.duplicate(true)
			migrated.depth = false
			settings.set_value(section, "mode_lock", migrated)
			changed = true
	for retired in ["photo", "photo_screen", "photo_gallery"]:
		if settings.has_section(retired):
			settings.erase_section(retired)
			changed = true
	if settings.get_value("appearance", "background", "belfast") == "custom":
		settings.set_value("appearance", "background", "belfast")
		changed = true
	for key in ["custom_path", "custom_title", "custom_orientation"]:
		if settings.has_section_key("appearance", key):
			settings.erase_section_key("appearance", key)
			changed = true
	return changed
