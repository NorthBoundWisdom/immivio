extends SceneTree
const Main := preload("res://scripts/main.gd")
const Host := preload("res://tests/test_player_menu.gd").Host
var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)


func _initialize() -> void:
	if preload("res://tests/support/test_result.gd").prepare(self):
		_run.call_deferred()


func _run() -> void:
	var main := Main.new()
	root.add_child(main)
	var host := Host.new()
	main.video.platform = host
	main.video.open_local("file:///presence.mp4", "Presence")
	main.video.test_set_waiting_for_frame(false)
	main.video.requested_play = true
	var count := host.calls.size()
	main.display._on_presence_changed(false)
	check(
		not main.wearer_present and main.video.requested_play and host.calls.size() == count,
		"OpenXR absence leaves the active playback request alone"
	)
	main.display._on_presence_changed(false)
	check(host.calls.size() == count, "Duplicate absence is idempotent")
	main._on_native_presence_changed(false, "proximity")
	main.display._on_presence_changed(true)
	check(not main.wearer_present, "XR presence cannot override confirmed native absence")
	main._on_native_presence_changed(true, "proximity")
	check(
		not main.library_menu.local_thumbnails._suspended,
		"Wearer return enables idle-library previews"
	)
	main._on_android_lifecycle("pause")
	check(
		main.library_menu.local_thumbnails._suspended,
		"Activity pause also suspends library previews"
	)
	main._on_native_presence_changed(false, "proximity")
	main._on_android_lifecycle("resume")
	check(
		main.library_menu.local_thumbnails._suspended,
		"Activity resume cannot generate previews while the wearer is absent"
	)
	main._on_native_presence_changed(true, "proximity")
	check(
		main.wearer_present and main.video.requested_play and host.calls.size() == count,
		"A native presence round-trip issues no playback commands"
	)
	main._on_native_presence_changed(false, "proximity")
	main.video.toggle_play()
	main.video.toggle_play()
	check(
		not main.wearer_present and host.calls.back() == ["play", 7, true],
		"An explicit Play request still reaches the player during reported absence"
	)
	main.video.toggle_play()
	count = host.calls.size()
	main.display._on_presence_changed(false)
	main.display._on_presence_changed(true)
	main._on_native_presence_changed(true, "proximity")
	check(
		not main.video.requested_play and host.calls.size() == count,
		"A manually paused video remains paused on return"
	)
	main.video.close_video()
	count = host.calls.size()
	main.display._on_presence_changed(false)
	main.display._on_presence_changed(true)
	check(
		host.calls.size() == count and main.video.local_uri.is_empty(),
		"Presence cannot revive a closed video"
	)
	main.queue_free()
	await process_frame
	print("Headset presence failures: %d" % failures.size())
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
