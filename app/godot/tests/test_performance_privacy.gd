extends SceneTree
## A generated metadata fixture verifies performance mode never requests pixels.
const Video := preload("res://scripts/mpv_video_display.gd")


class Host:
	extends RefCounted
	var pins := 0

	func pin_mpv_pair(_session: int, _slot: int) -> bool:
		pins += 1
		return false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var video := Video.new()
	root.add_child(video)
	video.set_process(false)
	var host := Host.new()
	video.platform = host
	video.media.state = "playing"
	video.media.last_pair = {"pts_us": 0, "session_id": 1, "slot_token": 1}
	video._binding.material = ShaderMaterial.new()
	video._thumb_after_ms = 0
	video._debug_benchmark = true
	video._maybe_capture_thumbnail()
	var guarded: bool = (
		host.pins == 0 and not video._thumbnail_busy and video._thumbnail_result.is_empty()
	)
	video._debug_benchmark = false
	video._maybe_capture_thumbnail()
	var ordinary: bool = host.pins == 1  # Refused before any capture; proves other gates were ready.
	video.queue_free()
	await process_frame
	if not guarded:
		push_error("Performance mode attempted a thumbnail/pixel capture")
	if not ordinary:
		push_error("Privacy guard fixture did not exercise a ready thumbnail path")
	print("Performance privacy: %s" % ("passed" if guarded and ordinary else "failed"))
	quit(0 if guarded and ordinary else 1)
