extends SceneTree

const Video := preload("res://scripts/mpv_video_display.gd")


class Host:
	extends RefCounted
	var accepted := true
	var calls: Array = []

	func set_mpv_audio(id: int, track: int, volume: float, muted: bool) -> bool:
		calls.append([id, track, volume, muted])
		return accepted


var failures: Array[String] = []


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	var video := Video.new()
	var host := Host.new()
	video.platform = host
	video.media.begin(7)
	video.media.generation = 3
	video.media.playback = {
		"details": {"audio_track_id": "1", "audio_tracks": [{"id": 1}, {"id": 2}]}
	}
	check(video.cycle_audio_track(), "Actual enumerated next track must be selectable")
	check(host.calls.back()[1] == 2, "Track selection uses MPV track id")
	video.media.playback.details.audio_track_id = "2"
	check(
		video.cycle_audio_track() and host.calls.back()[1] == 0,
		"Track cycle includes disabled audio"
	)
	check(video._apply_audio_track(-1), "Automatic track selection is retained")
	check(
		host.calls.all(func(call): return call[2] == 100.0 and call[3] == false),
		"Every audio request uses unity gain and leaves volume to the system"
	)
	check(
		video.media.session_id == 7 and video.media.generation == 3,
		"Track selection preserves the decoder generation"
	)
	host.accepted = false
	var track := video.audio_track_id
	check(
		not video._apply_audio_track(1) and video.audio_track_id == track,
		"Rejected native request leaves the current track intact"
	)
	var before := host.calls.size()
	check(
		not video._apply_audio_track(-2) and host.calls.size() == before,
		"Invalid track cannot reach the host"
	)
	video.media.playback = {"details": {"audio_tracks": []}}
	check(not video.cycle_audio_track(), "Silent source has no audio choice")
	video.requested_play = true
	video._on_state(6, JSON.stringify({"state": "paused", "audio_focus_change": "loss"}))
	check(video.requested_play, "Old source focus loss cannot pause the current source")
	video._on_state(7, JSON.stringify({"state": "paused", "audio_focus_change": "loss"}))
	check(
		not video.requested_play and video.media.session_id == 7 and video.media.generation == 3,
		"Permanent focus loss requires a fresh play request without resetting RVM"
	)
	video.free()
	if failures.is_empty():
		print("MPV audio host checks passed")
		preload("res://tests/support/test_result.gd").finish(self, 0)
	else:
		for failure in failures:
			push_error(failure)
		preload("res://tests/support/test_result.gd").finish(self, 1)
