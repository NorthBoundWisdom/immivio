extends SceneTree
const Policy := preload("res://scripts/video_mode_default.gd")
func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	call_deferred("_run")
func _run() -> void:
	var last := {"geometry": 1, "layout": 1, "fisheye_fov": 180, "swap_eyes": true, "depth": true}
	assert(not Policy.clean(last).has("depth"))
	assert(Policy.resolve({}, 1920, 1080, {}, "film.mp4", last, false).geometry == 0)
	assert(Policy.resolve({}, 1920, 1080, {}, "film.mp4", last, true).geometry == 1)
	assert(Policy.resolve({"geometry": 2, "stereo": false}, 1920, 1080, {}, "film_360.mp4", last, true).geometry == 2)
	assert(Policy.resolve({}, 1920, 1080, {"stereo_mode": "sbsl"}, "film.mp4", last, true).geometry == 0)
	assert(Policy.resolve({}, 3840, 1080, {}, "film.mp4", last, true).geometry == 0)
	var video := preload("res://scripts/mpv_video_display.gd").new()
	root.add_child(video)
	video.set_process(false)
	video.platform = preload("res://tests/test_file_mode_memory.gd").Host.new()
	video.reuse_last_mode = true
	video.last_video_mode = Policy.clean(last)
	assert(video.open_local("file:///unrecognized.mp4", "unrecognized.mp4"))
	video.media.format = {"width": 1920, "height": 1080}
	video._complete_layout()
	assert(video.geometry == 1 and video.stereo_sbs and video.swap_eyes)
	video._remember_mode()
	assert(video.open_local("file:///unrecognized.mp4", "unrecognized.mp4"))
	assert(video._layout_pending == null and video.geometry == 1)
	var host := preload("res://scripts/main.gd").new()
	host.video = video
	video.last_video_mode = {}
	video._waiting_first = false
	host._capture_last_video_mode()
	assert(host.settings.get_value("video", "last_mode").geometry == 1)
	assert(not host.settings.get_value("video", "last_mode").has("depth"))
	host.video = null
	host.free()
	video.free()
	preload("res://tests/support/test_result.gd").finish(self, 0)
