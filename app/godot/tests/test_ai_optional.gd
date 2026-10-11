extends SceneTree

const Video := preload("res://scripts/mpv_video_display.gd")
const Photo := preload("res://scripts/photo_display.gd")
const Player := preload("res://scripts/player_menu.gd")
var failures: Array[String] = []

class BaseHost extends RefCounted:
	var opens: Array = []
	var revisions: Array = []
	func ai_enabled() -> bool: return false
	func mpv_supported() -> bool: return true
	func open_mpv_video(uri: String, start: int, stereo: bool, profile: String, alpha: bool, vulkan: bool,
		depth: bool, tb: bool, exact: bool) -> int:
		opens.append([alpha, depth, stereo, tb]); return 7
	func revise_mpv_video(id: int, stereo: bool, alpha: bool, profile: String, target: int,
		depth: bool, tb: bool, exact: bool) -> int:
		revisions.append([alpha, depth]); return 0
	func set_mpv_playing(id: int, playing: bool) -> void: pass
	func close_mpv_video(id: int) -> void: pass

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var timing := preload("res://scripts/pair_texture_binding.gd")
	var standard := {"source_pts_verified": false, "source_ticket_origin": "standard_libmpv_render",
		"source_ticket_valid": true, "alpha_requested": false, "depth_requested": false, "inference_ran": false}
	check(timing.timing_valid(standard), "Public libmpv timing is usable for opaque playback")
	standard.alpha_requested = true
	check(not timing.timing_valid(standard), "Estimated timing cannot authorize live matting")
	standard.alpha_requested = false; standard.depth_requested = true
	check(not timing.timing_valid(standard), "Estimated timing cannot authorize depth inference")
	standard.depth_requested = false; standard.inference_ran = true
	check(not timing.timing_valid(standard), "Estimated timing cannot claim inferred frame pairs")
	check(not timing.timing_valid({}), "Unknown timing provenance stays rejected")
	var host := BaseHost.new()
	var video := Video.new()
	root.add_child(video); video.set_process(false); video.platform = host
	video.auto_depth = true # A setting saved by an earlier AI-enabled build.
	check(video.open_local("https://fixture.example/movie.mp4", "Movie", 0, false, true), "Normal playback opens despite an Alpha request")
	check(host.opens[0] == [false, false, false, false], "Neither model is requested on the native playback path")
	check(not video.set_alpha(true) and not video.set_depth(true), "Unavailable effects are rejected")
	video.set_projection(1); video.set_projection(0)
	check(not video.depth_requested, "Projection changes do not reactivate saved automatic depth")
	video.alpha_requested = true; video.depth_requested = true
	video._request_revision(12000)
	check(host.revisions.back() == [false, false], "Seeking/revision strips stale AI requests")
	var menu := Player.new()
	menu._state = {"has_video": true, "ai_enabled": false, "geometry": 1}
	check(not menu._enabled("alpha"), "AI Alpha control is disabled")
	menu._state.packed_file = true
	check(menu._enabled("alpha"), "Precomputed packed masks remain usable without AI")
	menu._state.geometry = 0
	check(not menu._enabled("depth") and not menu._can_depth(), "Video depth button and slider are disabled")
	check(menu._enabled("play") and menu._enabled("subtitles"), "Base controls remain available")
	var photo := Photo.new()
	photo.platform = host; photo.auto_depth = true
	check(not photo.set_depth(true), "Photo depth is rejected without inference")
	check(not photo.snapshot().depth_available, "Photo UI reports depth unavailable")
	photo.free(); menu.free(); video.queue_free()
	for failure in failures: printerr(failure)
	print("Optional AI checks: ", "passed" if failures.is_empty() else "failed")
	quit(0 if failures.is_empty() else 1)
