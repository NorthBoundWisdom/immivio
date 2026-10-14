extends SceneTree
const Main := preload("res://scripts/main.gd")
var failures: Array[String] = []
var checks := 0


class RecenterMain:
	extends Main
	var tracked := true
	var centres := 0

	func _head_tracked() -> bool:
		return tracked

	func _recenter() -> void:
		centres += 1
		super._recenter()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


func home(main: Node3D) -> void:
	# A new gesture occurs after the duplicate-notification window.
	main._presentation._system_recenter_last_notification_ms = -(
		main._presentation.SYSTEM_RECENTER_REPEAT_MS
	)
	main._on_system_recentered()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := RecenterMain.new()
	main.settings_path = "user://home-ring-%d.cfg" % Time.get_ticks_usec()
	root.add_child(main)
	main.set_process(false)
	main.report_timer.stop()
	main.menu_compositor.set_process(false)
	main.video.set_process(false)
	main.photo.set_process(false)
	main.display.preview = false
	main.display.session_state = "session_focussed"
	main._head_placed = true
	var menu: Node3D = main.recent_menu
	for pico in [false, true]:
		main._presentation._runtime_is_pico = pico
		for follow in [false, true]:
			main.view_follow.set_enabled(follow)
			for reclining in [false, true]:
				main.reclining_mode = reclining
				for pitch in [-.7, 0.0, .7]:
					var pose := Transform3D(
						Basis.from_euler(Vector3(pitch, .9, .2)), Vector3(.4, 1.7, -.3)
					)
					main.xr_camera.global_transform = pose
					var before := main.centres
					home(main)
					var centre: Vector2 = menu.capture_envelope().get_center()
					var offset: Vector3 = (
						menu.to_global(Vector3(centre.x, centre.y, 0)) - pose.origin
					)
					check(
						main.centres == before + 1 and not main._system_recenter_pending,
						"Updated tracking is used synchronously for Home"
					)
					check(
						(
							is_zero_approx(offset.y)
							and is_equal_approx(offset.length(), main.library_distance)
						),
						"Home puts the complete window on the fixed eye-height ring"
					)
					check(
						offset.normalized().is_equal_approx(-Main._upright_pose(pose).basis.z),
						"Ring direction follows horizontal gaze only"
					)
					var fixed := menu.global_transform
					main._on_system_recentered()
					main._apply_system_recenter()
					check(
						(
							main.centres == before + 1
							and menu.global_transform.is_equal_approx(fixed)
							and menu.visible
						),
						"Duplicate Home notification neither follows the head nor hides or repositions the window"
					)
	main.library_distance = 1.9
	main.display.session_state = "session_visible"
	var before := main.centres
	var fixed := menu.global_transform
	home(main)
	main._apply_system_recenter()
	check(
		(
			main._system_recenter_pending
			and main.centres == before
			and menu.global_transform.is_equal_approx(fixed)
		),
		"System focus loss defers one placement without moving content"
	)
	main.display.session_state = "session_focussed"
	main.tracked = false
	main._apply_system_recenter()
	check(
		main.centres == before and main._system_recenter_pending,
		"Tracking loss cannot use a world-origin fallback"
	)
	main.tracked = true
	main._apply_system_recenter()
	var centre: Vector2 = menu.capture_envelope().get_center()
	check(
		(
			main.centres == before + 1
			and is_equal_approx(
				menu.to_global(Vector3(centre.x, centre.y, 0)).distance_to(
					main.xr_camera.global_position
				),
				1.9
			)
		),
		"Recovered tracking applies once and retains manual distance"
	)
	main._apply_system_recenter()
	check(main.centres == before + 1, "Subsequent frames do not repeat the placement")
	main.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("System recenter: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
