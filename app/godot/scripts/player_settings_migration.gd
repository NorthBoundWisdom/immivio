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
