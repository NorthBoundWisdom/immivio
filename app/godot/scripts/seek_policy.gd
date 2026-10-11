extends RefCounted
## Preferences change seek precision, never the timestamps stored in bookmarks.
const SPEED := "speed"
const EXACT := "exact"
const GLOBAL := "global"
const DEFAULT := SPEED

static func normalize(value: Variant) -> String:
	return EXACT if value is String and value == EXACT else DEFAULT

static func bookmark_override(value: Variant) -> String:
	return value if value is String and value in [SPEED, EXACT] else GLOBAL

static func effective(global_mode: Variant, override_mode: Variant = GLOBAL) -> String:
	var choice := bookmark_override(override_mode)
	return normalize(global_mode) if choice == GLOBAL else choice

static func caption(mode: Variant) -> String:
	return "Exact seek" if normalize(mode) == EXACT else "Fast seek"

static func choices() -> Array:
	return [{"value": SPEED, "label": caption(SPEED), "hint": "Faster jumps, less precise"},
		{"value": EXACT, "label": caption(EXACT), "hint": "Accurate jumps, may take longer"}]
