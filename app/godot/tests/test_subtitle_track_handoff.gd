extends SceneTree
const Video := preload("res://scripts/mpv_video_display.gd")
const Base := preload("res://tests/test_independent_playback.gd")
var failures: Array[String] = []
var checks := 0


class Host:
	extends Base.Host
	var primary := 2
	var secondary := 8
	var reject_clear := false

	func set_mpv_subtitle(id: int, track: int) -> bool:
		calls.append(["primary", id, track])
		# Match mpv's silent collision: property dispatch succeeds without selecting.
		if track != secondary or track <= 0:
			primary = track
		return true

	func set_mpv_secondary_subtitle(id: int, track: int) -> bool:
		calls.append(["secondary", id, track])
		if reject_clear and track == 0:
			return false
		secondary = track
		return true


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func _run() -> void:
	var video := Video.new()
	root.add_child(video)
	video.set_process(false)
	var host := Host.new()
	video.platform = host
	video.media.begin(7)
	video.media.playback = {
		"details": {"subtitle_tracks": [{"id": 2, "codec": "subrip"}, {"id": 8, "codec": "ass"}]}
	}
	video.subtitles.select(2)
	video.dual_subtitles.enabled = true
	video.dual_subtitles.state.select(8)
	var accepted := video.set_subtitle_track(8, false)
	print(
		"Handoff calls=",
		host.calls,
		" native primary=",
		host.primary,
		" secondary=",
		host.secondary
	)
	check(
		accepted and host.calls == [["secondary", 7, 0], ["primary", 7, 8]],
		"Release secondary before requesting its track as primary"
	)
	check(
		host.primary == 8 and host.secondary == 0,
		"Actual slot selection agrees with desired primary"
	)
	check(
		video.subtitles.requested_track == 8 and video.dual_subtitles.state.requested_track == 0,
		"Desired slots agree after handoff"
	)
	host.calls.clear()
	host.primary = 2
	host.secondary = 8
	host.reject_clear = true
	video.subtitles.select(2)
	video.dual_subtitles.state.select(8)
	accepted = video.set_subtitle_track(8, false)
	print("Rejected clear calls=", host.calls, " accepted=", accepted)
	check(
		not accepted and host.calls == [["secondary", 7, 0]],
		"Failed secondary clear must not dispatch primary"
	)
	check(
		video.subtitles.requested_track == 2 and video.dual_subtitles.state.requested_track == 8,
		"Rejected release preserves both desired tracks"
	)
	host.reject_clear = false
	host.calls.clear()
	check(
		video.set_subtitle_track(0, false) and host.calls == [["primary", 7, 0]],
		"Primary off does not discard the retained secondary selection"
	)
	check(
		video.dual_subtitles.state.requested_track == 8, "Secondary retained while primary is off"
	)
	video.free()
	for failure in failures:
		push_error(failure)
	print("Subtitle handoff checks=", checks, " failures=", failures.size())
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
