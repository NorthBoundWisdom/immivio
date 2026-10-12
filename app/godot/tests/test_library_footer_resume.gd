extends SceneTree
const Main := preload("res://scripts/main.gd")
const Library := preload("res://scripts/library_menu.gd")
const Surface := preload("res://scripts/xr_menu_compositor.gd")
var failures: Array[String] = []
var checks := 0
class ResumeMain extends Main:
	var tracked := true
	func _head_tracked() -> bool: return tracked
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var directory := ProjectSettings.globalize_path("res://../../build/output/footer-resume-test")
	DirAccess.make_dir_recursive_absolute(directory)
	var settings := ConfigFile.new(); settings.set_value("appearance","background","dark"); settings.save(directory.path_join("settings.cfg"))
	var main := ResumeMain.new(); main.settings_path = directory.path_join("settings.cfg")
	root.add_child(main); main.set_process(false); main.video.set_process(false); main.photo.set_process(false); main.menu_compositor.set_process(false); main.report_timer.stop()
	var menu: Node3D = main.recent_menu
	menu.session_controls_provider = func(): return {"follow":false,"passthrough_visible":true,"passthrough":false,"alpha":false}
	menu.refresh()
	var footer: Array = menu._buttons.filter(func(button):return int(button.target) in [menu.FOLLOW, menu.TEMP_PASSTHROUGH])
	check(footer.size()==2,"Footer retains exactly follow and temporary passthrough")
	for target in [menu.CLOSE,menu.PLAYER,menu.RECENTER,menu.CLOSE_MENU]:
		check(not menu._buttons.any(func(button):return button.target==target),"Retired floating actions have no ray targets")
	for button in footer: check(is_equal_approx(button.node.position.y,menu.device_status.position.y),"Footer actions and battery are on a single row")
	var clicked := []
	menu.session_control_requested.connect(func(operation):clicked.append(operation))
	var compositor := Surface.new(); root.add_child(compositor); compositor.active_menu = menu
	compositor._update_bounds(); var original_rect := compositor.surface_rect
	for target in [menu.FOLLOW,menu.TEMP_PASSTHROUGH]:
		var button: Dictionary = menu._buttons.filter(func(b):return b.target==target)[0]
		for repeat in 12:
			menu.update_pointer("right_hand",button.node.global_position+button.node.global_basis.z*.5,-button.node.global_basis.z,true)
			compositor._update_bounds()
			check(menu._tooltip.visible and compositor.surface_rect==original_rect,"Hover tooltip cannot grow or recenter the projection")
			menu.cancel_pointer("right_hand"); compositor._update_bounds()
			check(compositor.surface_rect==original_rect,"Hover leave cannot change projection")
	check(clicked.is_empty(),"Hover alone cannot activate temporary passthrough")
	main._on_pointer_button("by_button","right_hand"); main._toggle_player_menu()
	menu._activate(menu.CLOSE); menu._activate(menu.PLAYER); menu._activate_footer(menu.CLOSE_MENU)
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true; main._unhandled_key_input(escape)
	check(menu.visible and not main.player_menu.visible,"User input cannot close the file manager")
	main._head_placed = true; main.display.preview = false; main.display.session_state = "session_focussed"; main._on_input_session_changed()
	for follow in [false,true]:
		for reclining in [false,true]:
			main.view_follow.set_enabled(follow); main.reclining_mode = reclining
			menu.global_position = Vector3(5,3,4)
			main.video.flat_pose = Transform3D(Basis(Vector3.UP, .7), Vector3(2, 1.8, -3))
			main.view_follow.capture(main._menu_key(menu), main._menu_head_pose(main.xr_camera.global_transform), menu.global_transform)
			var before := menu.global_transform
			var video_before: Transform3D = main.video.flat_pose
			var offsets: Dictionary = main.view_follow._poses.duplicate(true)
			main._notification(Main.NOTIFICATION_APPLICATION_PAUSED)
			main.display.session_state = "session_visible"; main._on_input_session_changed()
			main.tracked = false
			main._apply_system_recenter()
			check(menu.global_transform.is_equal_approx(before) and main.video.flat_pose.is_equal_approx(video_before), "System overlay and tracking loss preserve menu and screen placement")
			main.xr_camera.global_transform = Transform3D(Basis.from_euler(Vector3(.6,.9,.2)),Vector3(1,1.7,-.3))
			main.tracked = true
			main.display.session_state = "session_focussed"; main._on_input_session_changed()
			main._notification(Main.NOTIFICATION_APPLICATION_RESUMED)
			for frame in 5: main._apply_system_recenter()
			check(menu.global_transform.is_equal_approx(before) and main.video.flat_pose.is_equal_approx(video_before), "Returning from system dialog never centres content in upright/reclining and follow modes")
			check(main.view_follow._poses == offsets, "Resume preserves saved follow offsets")
	main.view_follow.set_enabled(false)
	main._recenter()
	check(not menu.global_position.is_equal_approx(Vector3(5,3,4)), "Explicit in-app recenter remains available")
	compositor.free(); main.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	print("Library footer and resume: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
