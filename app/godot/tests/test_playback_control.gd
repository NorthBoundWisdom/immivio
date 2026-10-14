extends SceneTree
const PlaybackControl := preload("res://scripts/playback_control.gd")
var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	var control := PlaybackControl.new()
	control.observe(4000, 2000000)
	for _request in 100:
		control.seek_relative(10000)
	check(
		control.display_position_ms() == 1004000,
		"Rapid relative seeks accumulate from the pending target"
	)
	check(
		control.take_pending() == {"request_id": 100, "target_ms": 1004000},
		"Only the latest request is submitted"
	)
	check(control.take_pending().is_empty(), "A submitted request cannot be submitted twice")
	control.observe(0, -1)
	check(
		control.display_position_ms() == 1004000 and control.observed_position_ms == 4000,
		"Old decoder status cannot replace an in-flight target"
	)
	control.seek_relative(-10000)
	check(not control.first_frame(5000), "An old completion cannot satisfy a newer queued seek")
	check(
		control.take_pending() == {"request_id": 101, "target_ms": 994000},
		"New request supersedes the in-flight seek"
	)
	check(control.first_frame(990000), "The latest request accepts its observed landing position")
	check(
		control.display_position_ms() == 990000 and control.target_ms == 994000,
		"A keyframe landing updates the clock without rewriting user intent"
	)
	check(
		not control.first_frame(1) and control.display_position_ms() == 990000,
		"Duplicate completion cannot rewind playback"
	)
	for requested in [-40000, 3000000]:
		control.seek_absolute(requested)
		check(
			control.target_ms == (0 if requested < 0 else 1999999),
			"Seek is bounded by the known duration"
		)
	control.close()
	check(
		control.take_pending().is_empty() and not control.first_frame(7),
		"Close discards both queued and in-flight work"
	)
	for delta in [9223372036854775807, -9223372036854775807]:
		control.seek_relative(delta)
		check(
			control.target_ms == (2147483647 if delta > 0 else 0),
			"Extreme deltas cannot overflow the JNI position range"
		)
	control.reject()
	control.observe(7200, 12000)
	check(
		control.take_pending().is_empty() and control.display_position_ms() == 7200,
		"Rejected seek releases the timeline for fresh observations"
	)
	for failure in failures:
		push_error(failure)
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
