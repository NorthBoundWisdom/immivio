extends Label3D
## Presented video frames, application render rate, and the active OpenXR display rate.

const WINDOW := 0.5  # seconds per sample

## The display rate is optional when the XR runtime is unavailable.
var source: Callable
var _elapsed := 0.0
var _frames := -1


func _ready() -> void:
	position = Vector3(-0.17, 0.15, -0.75)
	pixel_size = 0.0007
	font_size = 32
	outline_size = 8
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	no_depth_test = true
	render_priority = 120
	outline_render_priority = 119
	modulate = Color(0.75, 1.0, 0.8)


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	if _elapsed < WINDOW:
		return
	var sample: Dictionary = source.call() if source.is_valid() else {}
	var frames := int(sample.get("frames", 0))
	var video := float(frames - _frames) / _elapsed if _frames >= 0 and frames >= _frames else 0.0
	_frames = frames
	_elapsed = 0.0
	var render := "XR %d FPS" % roundi(Engine.get_frames_per_second())
	var refresh := float(sample.get("refresh_hz", 0))
	if is_finite(refresh) and refresh > 0:
		render += " · %d Hz" % roundi(refresh)
	if not sample.get("active", false):
		text = render
		return
	var target := int(sample.get("target", 0))
	text = (
		"%s %.1f%s · %s"
		% [
			"Alpha" if target > 0 else "Video",
			video,
			" / %d" % target if target > 0 else "",
			render
		]
	)


func set_shown(shown: bool) -> void:
	visible = shown
	_elapsed = 0.0
	_frames = -1
	text = ""
