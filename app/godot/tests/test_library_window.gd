extends SceneTree
const Main := preload("res://scripts/main.gd")
const Host := preload("res://tests/test_player_menu.gd").Host
var failures: Array[String] = []
var checks := 0


class TestInputSource:
	extends "res://scripts/input_source.gd"
	var test_ray: Variant

	func ray(_hand: String) -> Variant:
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
	var main := Main.new()
	main.input_source = TestInputSource.new(main)
	var directory := ProjectSettings.globalize_path(
		"res://../../build/tests/godot/library-window-test"
	)
	DirAccess.make_dir_recursive_absolute(directory)
	main.settings_path = directory.path_join("settings.cfg")
	var settings := ConfigFile.new()
	settings.set_value("appearance", "background", "dark")
	settings.save(main.settings_path)
	root.add_child(main)
	main.set_process(false)
	main.video.set_process(false)
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
	main.library_menu.catalog = main.video.recent_files
	var library: Node3D = main.library_menu
	library.section = library.Section.LOCAL
	library.sources.local_stack = [{"id": "/storage/emulated/0/Movies", "title": "Movies"}]
	for i in 60:
		library.sources.local_entries.append(
			{"uri": "file:///Movies/%d.mp4" % i, "title": "Video %d" % i}
		)
	library.scroll = 3.0
	library.refresh()
	main.video.open_local("file:///Movies/12.mp4", "Video 12")
	main.test_show_player_menu()
	main._on_menu_action("stop")
	check(
		main.video.local_uri.is_empty() and not main.video.panel.visible,
		"Close stops video and removes its surface"
	)
	check(
		library.visible and not main.video_menu.visible,
		"Close removes all playback controls and returns to library"
	)
	check(
		(
			library.section == library.Section.LOCAL
			and library.sources.local_stack.back().title == "Movies"
			and library.scroll == 3.0
		),
		"Return preserves directory and list position"
	)
	check(library.curve_radius > 0.0, "Library requests a curved surface")
	main.menu_compositor.test_step(0)
	check(
		main.menu_compositor.scene_curved and main.menu_compositor.curved_mesh == null,
		"Scene fallback waits for its first rendered texture before revealing the curved mesh"
	)
	for distance in [0.8, 1.4, 2.5, 4.0]:
		main.library_distance = distance
		main.test_place_menu(library)
		main.menu_compositor.test_step(0)
		var centre: Vector2 = library.capture_envelope().get_center()
		var viewing_distance := library.to_global(Vector3(centre.x, centre.y, 0)).distance_to(
			main.eye()
		)
		check(
			is_equal_approx(library.curve_radius, viewing_distance),
			"Menu curvature follows the viewing ring at " + str(distance) + "m"
		)
	main.library_distance = 1.4
	main.test_place_menu(library)
	main.menu_compositor.test_step(0)
	var held_radius: float = library.curve_radius
	library.choices.capture = {"hand": "left_hand", "item": {"kind": "open", "key": "language"}}
	main.library_distance = 2.5
	main.test_place_menu(library)
	main.menu_compositor.test_step(0)
	check(
		is_equal_approx(library.curve_radius, held_radius), "Pointer capture freezes menu curvature"
	)
	library.choices.capture.clear()
	main.menu_compositor.test_step(0)
	var lowered_distance := Vector2(2.5, main.presentation_coordinator.window_height).length()
	check(
		is_equal_approx(library.curve_radius, lowered_distance),
		"Release applies the new viewing distance"
	)
	var eye_before: Vector3 = main.xr_camera.global_position
	main.xr_camera.global_position += Vector3(0.3, 0, 0.2)
	main.menu_compositor.test_step(0)
	check(
		is_equal_approx(library.curve_radius, lowered_distance),
		"Head motion alone does not deform a placed menu"
	)
	main.xr_camera.global_position = eye_before
	main.library_distance = 1.4
	main.test_place_menu(library)
	main.menu_compositor.test_step(0)
	var pose: Transform3D = library.global_transform
	var origin: Vector3 = main.eye() + Vector3(.2, -.2, -.3)
	main.input_source.test_ray = [origin, (library.global_position - origin).normalized()]
	main.test_pointer_button("grip_click", "right_hand")
	check(
		not main.library_grab.is_empty() and main.grab.is_empty(),
		"Grip can own the library without an open video"
	)
	main.input_source.test_ray[0] = origin + Vector3.FORWARD * .35
	main._update_library_grab()
	check(
		is_equal_approx(main.library_distance, 1.4), "Controller push alone cannot change distance"
	)
	main.input_source.test_ray[0] = origin + Vector3.RIGHT * .35
	main._update_library_grab()
	check(
		(
			not is_equal_approx(library.global_position.x, pose.origin.x)
			and is_equal_approx(library.global_position.y, pose.origin.y)
		),
		"Ordinary grip moves library horizontally at the same height"
	)
	var horizontal_position: Vector3 = library.global_position
	main.input_source.test_ray[0] += Vector3.UP * .3
	main._update_library_grab()
	check(
		is_equal_approx(library.global_position.y, horizontal_position.y),
		"Upright library ignores vertical grip movement"
	)
	main.test_pointer_release("grip_click", "left_hand")
	check(not main.library_grab.is_empty(), "Other hand cannot release the library")
	main._update_library_grab_stick(Vector2(0, 1), Vector2.ZERO, .2)
	check(
		is_equal_approx(main.library_distance, 1.4), "Other hand's stick cannot move held library"
	)
	main._update_library_grab_stick(Vector2.ZERO, Vector2(0, .1), .2)
	check(is_equal_approx(main.library_distance, 1.4), "Stick dead zone prevents depth drift")
	main._update_library_grab_stick(Vector2.ZERO, Vector2(0, 1), .2)
	check(is_equal_approx(main.library_distance, 1.7), "Grip plus stick up moves library farther")
	main._update_library_grab_stick(Vector2.ZERO, Vector2(0, 1), 20)
	check(is_equal_approx(main.library_distance, 4.0), "Far distance is bounded")
	main._update_library_grab_stick(Vector2.ZERO, Vector2(0, -1), 20)
	check(is_equal_approx(main.library_distance, .8), "Near distance is bounded")
	main._update_library_grab_stick(Vector2.ZERO, Vector2(0, 1), .4666666667)
	check(
		is_equal_approx(main.library_distance, 1.5),
		"Stick can reverse immediately from a distance limit"
	)
	main.test_pointer_release("grip_click", "right_hand")
	check(
		main.library_grab.is_empty() and library.visible and not main.video_menu.visible,
		"Release retains library without opening playback controls"
	)
	settings.load(main.settings_path)
	check(
		is_equal_approx(float(settings.get_value("ui", "library_distance")), 1.5),
		"Released distance is persisted"
	)
	main.test_place_menu(library)
	var ring_centre: Vector2 = library.capture_envelope().get_center()
	check(
		is_equal_approx(
			library.to_global(Vector3(ring_centre.x, ring_centre.y, 0)).distance_to(main.eye()),
			Vector2(1.5, main.presentation_coordinator.window_height).length()
		),
		"Reopened library visual centre uses remembered ring distance"
	)
	main.reclining_mode = true
	main.test_place_menu(library)
	main.input_source.test_ray = [main.eye(), (library.global_position - main.eye()).normalized()]
	main.test_pointer_button("grip_click", "right_hand")
	var reclining_position: Vector3 = library.global_position
	main.input_source.test_ray[0] += Vector3.UP * .35
	main._update_library_grab()
	check(
		(
			library.global_position.y > reclining_position.y
			and is_equal_approx(main.library_distance, 1.5)
		),
		"Reclining grip supports vertical/global placement without changing distance"
	)
	main.test_pointer_release("grip_click", "right_hand")
	main.reclining_mode = false
	main.test_place_menu(library)
	origin = main.eye()
	main.input_source.test_ray = [origin, (library.global_position - origin).normalized()]
	main.test_pointer_button("grip_click", "left_hand")
	main.input_source.test_ray = null
	main._update_library_grab()
	check(main.library_grab.is_empty(), "Tracking loss cancels library drag")
	main.input_source.test_ray = [origin, (library.global_position - origin).normalized()]
	library._drag = {"hand": "right_hand"}
	main.test_pointer_button("grip_click", "left_hand")
	check(main.library_grab.is_empty(), "Grip cannot steal a captured row/scroll drag")
	library._drag.clear()
	main.test_pointer_button("grip_click", "left_hand")
	main._cancel_pointer("left_hand")
	check(main.library_grab.is_empty(), "Input session cancellation releases library ownership")
	main.video.open_local("file:///Movies/13.mp4", "Video 13")
	main.test_show_player_menu()
	main.menu_compositor.test_step(0)
	check(
		(
			main.menu_compositor.active_menu != library
			and (
				main.menu_compositor.curved_mesh == null
				or not main.menu_compositor.curved_mesh.visible
			)
		),
		"Opening video hides the library capture while controls await the first media frame"
	)
	main.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Library window: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
