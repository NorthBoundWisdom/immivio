extends SceneTree
const Video := preload("res://scripts/mpv_video_display.gd")
const Host := preload("res://tests/test_file_mode_memory.gd").Host
var failures: Array[String] = []


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _run() -> void:
	var video := Video.new()
	root.add_child(video)
	video.set_process(false)
	video.platform = Host.new()
	video.history_enabled = false
	check(
		video.open_local("http://127.0.0.1/dlna/scene/1", "Generated scene title", 0, false),
		"Open untagged DLNA scene"
	)
	check(not video.packed_file and not video.alpha_wanted(), "Untagged scene defaults to opaque")
	video._layout_pending = null
	video.geometry = 2
	video.stereo_sbs = true
	video.media.format = {
		"width": 1280, "height": 640, "pixel_aspect": 1.0, "unapplied_rotation_degrees": 0
	}
	video.media.last_pair = {"fixture": true}
	video.media.state = "paused"
	check(
		video.alpha_available() and video.set_alpha(true),
		"Compatible untagged fisheye accepts manual alpha while paused"
	)
	check(
		(
			video.alpha_wanted()
			and video.alpha_ready()
			and video.material.get_shader_parameter("packed_alpha")
		),
		"Manual mask becomes active without renaming or playback"
	)
	check(
		video.set_alpha(false) and not video.alpha_wanted() and not video.alpha_ready(),
		"Manual switch disables the mask"
	)
	for change in [
		{"top_bottom": true}, {"stereo_half": true}, {"geometry": 1}, {"stereo_sbs": false}
	]:
		var key: String = change.keys()[0]
		var before: Variant = video.get(key)
		video.set(key, change[key])
		check(not video.set_alpha(true), "Reject incompatible layout: " + key)
		video.set(key, before)
	video.media.format.unapplied_rotation_degrees = 90
	check(not video.set_alpha(true), "Reject unapplied rotation")
	check(
		video.open_local(
			"file:///tagged_fisheye190_alpha.mp4", "tagged_fisheye190_alpha.mp4", 0, false
		),
		"Open tagged file"
	)
	check(video.packed_file and video.alpha_wanted(), "Naming still supplies the automatic default")
	check(
		video.open_local("http://127.0.0.1/dlna/scene/2", "Next scene", 0, false), "Open next scene"
	)
	check(not video.alpha_wanted(), "Manual alpha does not leak into the next untagged file")
	video.free()
	for failure in failures:
		push_error(failure)
	print("Manual packed alpha failures: ", failures.size())
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
