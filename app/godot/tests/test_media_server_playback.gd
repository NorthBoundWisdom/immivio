extends SceneTree
const Transport := preload("res://scripts/media_server_playback.gd")
class Platform extends RefCounted:
	var calls: Array = []
	func media_server_playback(raw: String) -> bool:
		calls.append(JSON.parse_string(raw))
		return true
func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	var video := preload("res://scripts/mpv_video_display.gd").new()
	var platform := Platform.new()
	video.platform = platform
	video.local_uri = "medialib://server/scene/movie"
	video.media.begin(1)
	video.media.generation = 2
	video.media.state = "playing"
	video.media.last_pair = {"source_pts_verified": true, "session_id": 1, "generation": 2, "pts_us": 12000000}
	var transport := Transport.new()
	transport.begin(video.local_uri)
	transport.poll(video, true)
	assert(platform.calls.back().position_ms == 12000)
	video.control.pending = true
	var count := platform.calls.size()
	transport.poll(video, true)
	assert(platform.calls.size() == count)
	video.control.pending = false
	video.history_enabled = false
	transport.poll(video, true)
	assert(platform.calls.back().action == "privacy" and not platform.calls.back().enabled)
	count = platform.calls.size()
	video.history_enabled = true
	transport.poll(video, true)
	assert(platform.calls.filter(func(c): return c.action == "state").size() == 1)
	transport.begin("file:///private.strm")
	transport.poll(video, true)
	assert(platform.calls.filter(func(c): return c.action == "state").size() == 1)
	video.free()
	preload("res://tests/support/test_result.gd").finish(self, 0)
