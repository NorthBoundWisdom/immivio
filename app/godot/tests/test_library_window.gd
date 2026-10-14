extends SceneTree
const Host := preload("res://tests/test_player_menu.gd").Host
var failures: Array[String] = []
var checks := 0


class InputMain:
	extends "res://scripts/main.gd"
	var test_ray: Variant

	func _ray(_hand: String) -> Variant:
		return test_ray


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func _run() -> void:
	var main := InputMain.new()
	var directory := ProjectSettings.globalize_path("res://../../build/output/library-window-test")
	DirAccess.make_dir_recursive_absolute(directory)
	main.settings_path = directory.path_join("settings.cfg")
	var settings := ConfigFile.new()
	settings.set_value("appearance", "background", "dark")
	settings.save(main.settings_path)
	root.add_child(main)
	main.set_process(false)
	main.video.set_process(false)
	main.photo.set_process(false)
	main.menu_compositor.set_process(false)
	main.report_timer.stop()
	var host := Host.new()
	main.video.platform = host
	main.video.recent_files = preload("res://scripts/recent_files.gd").new(
		directory.path_join("recent")
	)
	main.video.mode_memory = preload("res://scripts/file_mode_memory.gd").new(
		directory.path_join("modes")
	)
	main.recent_menu.catalog = main.video.recent_files
	var library: Node3D = main.recent_menu
	library.section = library.Section.LOCAL
	library._local_stack = [{"id": "/storage/emulated/0/Movies", "title": "Movies"}]
	for i in 60:
		library._local_entries.append({"uri": "file:///Movies/%d.mp4" % i, "title": "Video %d" % i})
	library.scroll = 3.0
	library.refresh()
	main.video.open_local("file:///Movies/12.mp4", "Video 12")
	main._show_player_menu()
	main._on_menu_action("stop")
	check(
		main.video.local_uri.is_empty() and not main.video.panel.visible,
		"Close stops video and removes its surface"
	)
	check(
		library.visible and not main.video_menu.visible and not main.photo_menu.visible,
		"Close removes all playback controls and returns to library"
	)
	check(
		(
			library.section == library.Section.LOCAL
			and library._local_stack.back().title == "Movies"
			and library.scroll == 3.0
		),
		"Return preserves directory and list position"
	)
	check(library.curve_radius > 0.0, "Library requests a curved surface")
	main.menu_compositor._process(0)
	check(
		main.menu_compositor.scene_curved and main.menu_compositor.curved_mesh.visible,
		"Unsupported native layers use a curved texture mesh"
	)
	var pose: Transform3D = library.global_transform
	var origin: Vector3 = main._eye() + Vector3(.2, -.2, -.3)
	main.test_ray = [origin, (library.global_position - origin).normalized()]
	main._on_pointer_button("grip_click", "right_hand")
	check(
		not main._library_grab.is_empty() and main._grab.is_empty(),
		"Grip can own the library without an open video"
	)
	main.test_ray[0] = origin + Vector3.FORWARD * .35
	main._update_library_grab()
	check(
		is_equal_approx(main.library_distance, 1.4), "Controller push alone cannot change distance"
	)
	main.test_ray[0] = origin + Vector3.RIGHT * .35
	main._update_library_grab()
	check(
		(
			not is_equal_approx(library.global_position.x, pose.origin.x)
			and is_equal_approx(library.global_position.y, pose.origin.y)
		),
		"Ordinary grip moves library horizontally at the same height"
	)
	var horizontal_position: Vector3 = library.global_position
	main.test_ray[0] += Vector3.UP * .3
	main._update_library_grab()
	check(
		is_equal_approx(library.global_position.y, horizontal_position.y),
		"Upright library ignores vertical grip movement"
	)
	main._on_pointer_release("grip_click", "left_hand")
	check(not main._library_grab.is_empty(), "Other hand cannot release the library")
	main._update_library_grab_stick(Vector2(0, 1), Vector2.ZERO, .2)
	check(
		is_equal_approx(main.library_distance, 1.4), "Other hand's stick cannot move held library"
	)
	main._update_library_grab_stick(Vector2.ZERO, Vector2(0, .1), .2)
	check(is_equal_approx(main.library_distance, 1.4), "Stick dead zone prevents depth drift")
	main._update_library_grab_stick(Vector2.ZERO, Vector2(0, 1), .2)
	check(is_equal_approx(main.library_distance, 1.7), "Grip plus stick up moves library farther")
	main._update_library_grab_stick(Vector2.ZERO, Vector2(0, 1), 20)
	check(is_equal_approx(main.library_distance, 3.0), "Far distance is bounded")
	main._update_library_grab_stick(Vector2.ZERO, Vector2(0, -1), 20)
	check(is_equal_approx(main.library_distance, .8), "Near distance is bounded")
	main._update_library_grab_stick(Vector2.ZERO, Vector2(0, 1), .4666666667)
	check(
		is_equal_approx(main.library_distance, 1.5),
		"Stick can reverse immediately from a distance limit"
	)
	main._on_pointer_release("grip_click", "right_hand")
	check(
		main._library_grab.is_empty() and library.visible and not main.video_menu.visible,
		"Release retains library without opening playback controls"
	)
	settings.load(main.settings_path)
	check(
		is_equal_approx(float(settings.get_value("ui", "library_distance")), 1.5),
		"Released distance is persisted"
	)
	main._place_menu(library)
	var ring_centre: Vector2 = library.capture_envelope().get_center()
	check(
		is_equal_approx(
			library.to_global(Vector3(ring_centre.x, ring_centre.y, 0)).distance_to(main._eye()),
			1.5
		),
		"Reopened library visual centre uses remembered ring distance"
	)
	main.reclining_mode = true
	main._place_menu(library)
	main.test_ray = [main._eye(), (library.global_position - main._eye()).normalized()]
	main._on_pointer_button("grip_click", "right_hand")
	var reclining_position: Vector3 = library.global_position
	main.test_ray[0] += Vector3.UP * .35
	main._update_library_grab()
	check(
		(
			library.global_position.y > reclining_position.y
			and is_equal_approx(main.library_distance, 1.5)
		),
		"Reclining grip supports vertical/global placement without changing distance"
	)
	main._on_pointer_release("grip_click", "right_hand")
	main.reclining_mode = false
	main._place_menu(library)
	origin = main._eye()
	main.test_ray = [origin, (library.global_position - origin).normalized()]
	main._on_pointer_button("grip_click", "left_hand")
	main.test_ray = null
	main._update_library_grab()
	check(main._library_grab.is_empty(), "Tracking loss cancels library drag")
	main.test_ray = [origin, (library.global_position - origin).normalized()]
	library._drag = {"hand": "right_hand"}
	main._on_pointer_button("grip_click", "left_hand")
	check(main._library_grab.is_empty(), "Grip cannot steal a captured row/scroll drag")
	library._drag.clear()
	main._on_pointer_button("grip_click", "left_hand")
	main._cancel_pointer("left_hand")
	check(main._library_grab.is_empty(), "Input session cancellation releases library ownership")
	main.video.open_local("file:///Movies/13.mp4", "Video 13")
	main._show_player_menu()
	main.menu_compositor._process(0)
	check(
		not main.menu_compositor.scene_curved and not main.menu_compositor.curved_mesh.visible,
		"Returning to video hides curved library capture"
	)
	main.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Library window: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
