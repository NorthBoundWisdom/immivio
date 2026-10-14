extends RefCounted

const NAMES := ["Standard", "Enhanced", "High"]
const SCALES := [1.0, 1.1, 1.25]
## -1 follows the device tier: Standard on low-end GPUs, Enhanced elsewhere.
const AUTO := -1
const DEFAULT := AUTO
const TIER_DEFAULT := 1
const MSAA := [Viewport.MSAA_2X, Viewport.MSAA_2X, Viewport.MSAA_4X]
const FLAT_MSAA := [Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_4X]
const SHARPNESS := [0.0, 0.2, 0.4, 0.6]
const SHARPNESS_NAMES := ["Off", "Low", "Medium", "High"]
const DEFAULT_SHARPNESS := 0.2
## Video output width: -1 follows the device tier, 0 keeps the source size.
const AUTO_OUTPUT := -1
## XR2 Gen1 class GPUs (Quest 2/Pro, PICO Neo3/4) lack the bandwidth to resample 8K60
## RGBA per eye pixel; 4K output and no sharpening keep their frame rate.
const LOW_END_OUTPUT_WIDTH := 4096


static func load_quality(settings: ConfigFile) -> int:
	if settings.has_section_key("video", "display_quality"):
		return clampi(int(settings.get_value("video", "display_quality")), AUTO, SCALES.size() - 1)
	if settings.has_section_key("video", "render_scale"):
		var scale := float(settings.get_value("video", "render_scale"))
		return 0 if scale <= 1.0 else (1 if scale < 1.2 else 2)
	return DEFAULT


static func resolve(choice: int, low_end: bool) -> int:
	return (
		(0 if low_end else TIER_DEFAULT) if choice == AUTO else clampi(choice, 0, SCALES.size() - 1)
	)


static func render_scale(choice: int, low_end: bool) -> float:
	return SCALES[resolve(choice, low_end)]


## Adreno 6xx and older (XR2 Gen1 / XR2+) are low end; 7xx (XR2 Gen2) and unknown GPUs are not.
static func is_low_end_gpu(adapter: String) -> bool:
	var found := RegEx.create_from_string("(?i)adreno\\D*(\\d{3})").search(adapter)
	return found != null and int(found.get_string(1)) < 700


static func default_sharpness(low_end: bool) -> float:
	return 0.0 if low_end else DEFAULT_SHARPNESS


static func load_sharpness(settings: ConfigFile, low_end: bool = false) -> float:
	var fallback := default_sharpness(low_end)
	var value := float(settings.get_value("video", "sharpness", fallback))
	return clampf(value, 0.0, 0.6) if is_finite(value) else fallback


static func load_output_choice(settings: ConfigFile) -> int:
	var value := int(settings.get_value("video", "output_width", AUTO_OUTPUT))
	return value if value == AUTO_OUTPUT or value in [0, 5760, 4096] else AUTO_OUTPUT


static func output_width(choice: int, low_end: bool) -> int:
	if choice != AUTO_OUTPUT:
		return choice
	return LOW_END_OUTPUT_WIDTH if low_end else 0
