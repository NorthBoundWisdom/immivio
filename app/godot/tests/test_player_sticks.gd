extends SceneTree

const Controls := preload("res://scripts/player_stick_controls.gd")
const Main := preload("res://scripts/main.gd")
var failures: Array[String] = []
var checks := 0


class Trace:
	extends Node3D
	var calls: Array = []

	func seek_relative(delta: int) -> bool:
		calls.append(["seek", delta])
		return true

	func change_volume(delta: float) -> bool:
		calls.append(["unused_volume", delta])
		return true

	func cycle_audio_track(direction: int) -> bool:
		calls.append(["audio_track", direction])
		return true

	func toggle_mute() -> bool:
		calls.append(["mute"])
		return true

	func cycle_subtitle_track(direction: int) -> bool:
		calls.append(["subtitle", direction])
		return true

	func toggle_eye_order() -> bool:
		calls.append(["swap_eyes"])
		return true

	func zoom_view(amount: float) -> void:
		calls.append(["zoom", amount])


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	var main := Main.new()
	var video := Trace.new()
	main.video = video
	var controls := Controls.new()
	check(
		controls.poll(Vector2(.8, .6), Vector2(.8, .6)).is_empty(),
		"Diagonal pushes do not issue commands"
	)
	main._apply_stick_actions(controls.poll(Vector2(.99, 0), Vector2(-.99, 0)))
	check(
		video.calls == [["seek", 10000], ["seek", -10000]],
		"Both hands dispatch the configured seek step"
	)
	main._apply_stick_actions(controls.poll(Vector2(.99, 0), Vector2(-.99, 0)))
	check(video.calls.size() == 2, "Held sticks cannot repeat seeks")
	controls.poll(Vector2.ZERO, Vector2.ZERO)
	check(
		controls.poll(Vector2(0, .99), Vector2(0, -.99)).is_empty(),
		"Vertical sticks have no volume binding"
	)
	check(
		controls.poll(Vector2(NAN, 0), Vector2(INF, 0)).is_empty(),
		"Invalid axes cannot issue commands"
	)
	controls = Controls.new()
	video.calls.clear()
	for frame in 3:
		main._apply_stick_actions(controls.poll(Vector2.ZERO, Vector2(0, .9), true), .5)
	check(
		video.calls.size() == 3 and video.calls.all(func(call): return call[0] == "zoom"),
		"Immersive right vertical zoom remains continuous"
	)
	controls.suspend()
	check(
		controls.poll(Vector2(.99, 0), Vector2(.99, 0), true).is_empty(),
		"UI capture suspends held sticks"
	)
	controls.poll(Vector2.ZERO, Vector2.ZERO)
	main._apply_stick_actions(controls.poll(Vector2(-.99, 0), Vector2(.99, 0), true))
	check(
		video.calls.slice(-2) == [["seek", -10000], ["seek", 10000]],
		"Returning to centre restores independent seeking"
	)
	controls = Controls.new()
	var held := Vector2(.99, 0)
	check(
		(
			controls.poll(held, Vector2.ZERO, false, 0.1, true).size() == 1
			and controls.seek_hand == "left"
		),
		"A compositor seek starts on the first push and owns the gesture"
	)
	for frame in 10:
		check(
			controls.poll(held, -held, false, 0.1, true, true).is_empty(),
			"Held seeks wait while a frame is outstanding, including input from the other hand"
		)
	check(
		(
			controls.poll(held, -held, false, 0.1, true)
			== [{"operation": "seek_repeat", "direction": 1}]
		),
		"A held seek submits one new step once the decoder is free"
	)
	check(
		(
			controls.poll(Vector2.ZERO, -held, false, 0.1, true).is_empty()
			and controls.seek_hand.is_empty()
		),
		"Releasing the owner does not begin a second seek with a held stick"
	)
	controls.poll(Vector2.ZERO, Vector2.ZERO)
	controls.poll(held, Vector2.ZERO, false, 0.1, true)
	controls.suspend()
	check(
		controls.poll(held, Vector2.ZERO, false, 0.1, true).is_empty(),
		"Menu capture cancels held seek and requires recentering"
	)
	main.free()
	video.free()
	for failure in failures:
		push_error(failure)
	print("Player sticks: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
