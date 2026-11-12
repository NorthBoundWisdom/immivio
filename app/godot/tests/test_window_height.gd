extends SceneTree
const Main := preload("res://scripts/main.gd")
const Geometry := preload("res://scripts/video_geometry.gd")
var failures: Array[String] = []
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func _run() -> void:
	var host := Main.new()
	host.settings_path = "user://height.cfg"
	root.add_child(host)
	host.set_process(false)
	host.menu_compositor.set_process(false)
	host.video.set_process(false)
	host.report_timer.stop()
	var presentation = host._presentation
	check(
		is_equal_approx(presentation.window_height, -.12),
		"Fresh windows default slightly below the previous height"
	)
	var library: Node3D = host.library_menu
	var centre: Vector2 = library.capture_envelope().get_center()
	check(
		is_equal_approx(library.to_global(Vector3(centre.x, centre.y, 0)).y, host._eye().y - .12),
		"Startup library applies the default height"
	)
	library.section = library.Section.SETTINGS
	library.tab = library.DISPLAY_TAB
	library.refresh()
	check(
		library.rows.any(
			func(row):
				return (
					row.get("key") == "window_height"
					and row.get("slider", false)
					and row.has("reset_value")
				),
		),
		"Display settings expose a resettable height slider"
	)
	var before: Transform3D = library.global_transform
	host._on_playback_adjustment("window_height", -30.0)
	check(
		library.global_transform == before and is_equal_approx(presentation.window_height, -.12),
		"Slider preview cannot move the captured rail"
	)
	host._on_setting_changed("window_height", -30.0)
	check(
		is_equal_approx(library.position.y, before.origin.y - .18),
		"Release moves the current window immediately"
	)
	var saved := ConfigFile.new()
	check(
		(
			saved.load(host.settings_path) == OK
			and is_equal_approx(saved.get_value("ui", "window_height"), -.3)
		),
		"Height is persisted in metres"
	)
	host._place_menu(library)
	check(
		is_equal_approx(library.to_global(Vector3(centre.x, centre.y, 0)).y, host._eye().y - .3),
		"Reopening applies the same height once"
	)
	host.video.local_uri = "file:///height.mp4"
	host.video.panel.visible = true
	host.video._waiting_first = false
	for reclining in [false, true]:
		host.reclining_mode = reclining
		if reclining:
			host.xr_camera.rotation.x = .4
		for geometry in [
			Geometry.Geometry.FLAT, Geometry.Geometry.HALF_EQUIRECT, Geometry.Geometry.EQUIRECT_360
		]:
			host.video.geometry = geometry
			host._show_player_menu()
			presentation.window_height = 0
			host._place_menu(host.video_menu)
			var zero: Transform3D = host.video_menu.global_transform
			presentation.window_height = -.3
			host._place_menu(host.video_menu)
			check(
				host.video_menu.global_position.is_equal_approx(
					zero.origin - zero.basis.y.normalized() * .3
				),
				(
					"Video controls lower consistently for geometry %d, reclining %s"
					% [geometry, reclining]
				)
			)
			host.library_menu.compact = true
			host._show_library_menu()
			var compact: Transform3D = library.global_transform
			host._place_menu(library)
			check(
				library.global_transform.is_equal_approx(compact),
				"Compact library never accumulates the height offset"
			)
	for invalid in [NAN, INF, "bad", true]:
		host._on_setting_changed("window_height", invalid)
		check(is_equal_approx(presentation.window_height, -.3), "Invalid height is rejected")
	host._on_setting_changed("window_height", 200.0)
	check(is_equal_approx(presentation.window_height, .3), "Height is bounded above")
	host._on_setting_changed("window_height", -200.0)
	check(is_equal_approx(presentation.window_height, -.6), "Height is bounded below")
	host.queue_free()
	await process_frame
	var restored := Main.new()
	restored.settings_path = "user://height.cfg"
	root.add_child(restored)
	check(
		is_equal_approx(restored._presentation.window_height, -.6),
		"Restart restores the saved height"
	)
	restored.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Window height: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
