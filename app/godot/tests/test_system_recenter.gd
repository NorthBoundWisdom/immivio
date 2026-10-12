extends SceneTree

const Main := preload("res://scripts/main.gd")
var failures: Array[String] = []
var checks := 0

class RecenterMain extends Main:
	var tracked := true
	var centres := 0
	func _head_tracked() -> bool: return tracked
	func _recenter() -> void:
		centres += 1
		super._recenter()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var folder := ProjectSettings.globalize_path("res://../../build/output/system-recenter")
	DirAccess.make_dir_recursive_absolute(folder)
	var main := RecenterMain.new(); main.settings_path = folder.path_join("settings-%d.cfg" % Time.get_ticks_usec())
	root.add_child(main); main.set_process(false); main.report_timer.stop(); main.menu_compositor.set_process(false)
	main.video.set_process(false); main.photo.set_process(false)
	main.display.preview = false; main.display.session_state = "session_focussed"; main._head_placed = true
	var menu: Node3D = main.recent_menu
	var old_head := Transform3D(Basis(Vector3.UP, .25), Vector3(.5, 1.7, .2))
	var new_head := Transform3D(Basis.from_euler(Vector3(.45, .25 + PI, .2)), Vector3(-.3, 1.8, .4))
	for follow in [false, true]:
		for reclining in [false, true]:
			main.view_follow.set_enabled(follow); main.reclining_mode = reclining; main.video.reclining_mode = reclining
			main.xr_camera.global_transform = old_head
			main.video.local_uri = "file:///synthetic-recenter.mp4"
			main.video.geometry = 0; main.video._apply_geometry()
			main._recenter()
			var before := menu.global_transform
			var calls := main.centres
			main._on_system_recentered()
			check(main._system_recenter_pending and main.centres == calls and menu.global_transform.is_equal_approx(before), "Long Home notification cannot use the old camera pose synchronously")
			main._apply_system_recenter()
			main.xr_camera.global_transform = new_head
			main._apply_system_recenter()
			check(main.centres == calls, "Recenter waits for subsequent tracked scene frames")
			main._apply_system_recenter()
			var expected := main._menu_head_pose(new_head) * Transform3D(Basis.IDENTITY, Vector3(0, -.05, -main.library_distance))
			check(not main._system_recenter_pending and main.centres == calls + 1 and menu.global_transform.is_equal_approx(expected), "Long Home centres the menu using the new reference-space head pose")
			check((menu.global_position - new_head.origin).dot(-new_head.basis.z) > 0, "A 180-degree reference-space change puts the window in front, never behind")
			var screen: Transform3D = main.video.global_transform * main.video.flat_pose
			check((screen.origin-new_head.origin).dot(-new_head.basis.z) > 0 and is_equal_approx(screen.origin.distance_to(new_head.origin), main.video.screen_distance), "Flat video returns in front at its remembered distance")
			if follow:
				check(main.view_follow.pose(main._menu_key(menu), main._menu_head_pose(new_head)).is_equal_approx(expected), "Long Home replaces stale follow offsets with centred placement")
			before = menu.global_transform
			main._notification(Main.NOTIFICATION_APPLICATION_PAUSED)
			main.display.session_state = "session_visible"; main._on_input_session_changed()
			main.display.session_state = "session_focussed"; main._on_input_session_changed()
			main._notification(Main.NOTIFICATION_APPLICATION_RESUMED)
			for frame in 5: main._apply_system_recenter()
			check(main.centres == calls + 1 and menu.global_transform.is_equal_approx(before), "Short Home dialog/focus recovery does not request another recenter")
	main.view_follow.set_enabled(false); main.reclining_mode = false; main.video.reclining_mode = false
	var calls := main.centres
	main._on_system_recentered(); main.display.session_state = "session_visible"
	for frame in 5: main._apply_system_recenter()
	check(main.centres == calls and main._system_recenter_pending, "A long Home request waits while the system owns focus")
	main.display.session_state = "session_focussed"; main.tracked = false
	for frame in 5: main._apply_system_recenter()
	check(main.centres == calls and main._system_recenter_frames == 0, "Missing tracking cannot centre at a world-origin fallback")
	main.tracked = true
	for frame in 2: main._apply_system_recenter()
	main._on_system_recentered() # Coalesce another reset while camera updates are pending.
	main._apply_system_recenter()
	check(main.centres == calls, "Duplicate system resets restart the camera-update wait")
	for frame in 2: main._apply_system_recenter()
	check(main.centres == calls + 1 and not main._system_recenter_pending, "Multiple reset notifications apply exactly one centred placement")
	main._on_system_recentered(); main._recenter(); calls = main.centres
	for frame in 5: main._apply_system_recenter()
	check(main.centres == calls and not main._system_recenter_pending, "Manual recenter consumes a pending system request")
	# Playback controls stay aligned to recentered flat and immersive content.
	menu.visible = false; main.player_menu.visible = true
	main.video.media.begin(1); main.video.media.state = "playing"
	for projection in [0, 1, 2, 3]:
		main.video.geometry = projection; main.video.view_yaw = .7; main.video.view_pitch = .2; main.video.view_zoom = .3
		main.video._apply_geometry(); main.video.panel.visible = true
		main.xr_camera.global_transform = new_head
		main._on_system_recentered()
		for frame in 3: main._apply_system_recenter()
		check((main.player_menu.global_position-new_head.origin).dot(-new_head.basis.z) > 0, "Long Home centres playback controls in front for projection %d" % projection)
		if projection != 0:
			check(main.video.view_yaw == 0 and main.video.view_pitch == 0 and main.video.view_zoom == 0, "Long Home resets immersive view offsets")
	main.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	print("System recenter: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
