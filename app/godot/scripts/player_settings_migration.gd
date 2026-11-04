extends RefCounted
## Retire removed effect preferences while preserving ordinary playback data.

const RETIRED_KEYS := [
	["effects", "auto_3d"],
	["video", "depth_strength"],
	["photo", "depth_strength"],
	["video", "alpha_fps"],
]


static func apply(settings: ConfigFile) -> bool:
	var changed := false
	if settings.has_section_key("display", "refresh_rate"):
		var rate: Variant = settings.get_value("display", "refresh_rate")
		if not (rate is int or rate is float) or not is_finite(float(rate)) or float(rate) <= 0.0:
			settings.set_value("display", "refresh_rate", 72.0)
			changed = true
	if settings.has_section_key("video", "reuse_last_mode") and not settings.get_value("video", "reuse_last_mode") is bool:
		settings.set_value("video", "reuse_last_mode", false)
		changed = true
	if settings.has_section_key("video", "last_mode"):
		var previous: Variant = settings.get_value("video", "last_mode")
		var mode := preload("res://scripts/video_mode_default.gd").clean(previous)
		if previous != mode:
			settings.set_value("video", "last_mode", mode)
			changed = true
	for item in RETIRED_KEYS:
		if settings.has_section_key(item[0], item[1]):
			settings.erase_section_key(item[0], item[1])
			changed = true
	if settings.has_section("alpha"):
		settings.erase_section("alpha")
		changed = true
	for section in ["video", "photo"]:
		var previous: Variant = settings.get_value(section, "mode_lock", {})
		if previous is Dictionary and bool(previous.get("depth", false)):
			var migrated: Dictionary = previous.duplicate(true)
			migrated.depth = false
			settings.set_value(section, "mode_lock", migrated)
			changed = true
	return changed
