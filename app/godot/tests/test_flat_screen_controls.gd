extends SceneTree

const Video := preload("res://scripts/mpv_video_display.gd")
const Menu := preload("res://scripts/player_menu.gd")
var checks := 0
var failures: Array[String] = []

class InputMain extends "res://scripts/main.gd":
	var test_ray: Variant
	func _ray(_hand: String) -> Variant: return test_ray

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var main := InputMain.new()
	main.settings_path = "user://flat-screen-test.cfg"
	var video := Video.new()
	root.add_child(video)
	video.set_process(false)
	main.video = video
	video.local_uri = "file:///flat-test.mp4"
	video.media.begin(1)
	video.media.format = {"width": 1920, "height": 1080}
	var menu := Menu.new()
	menu.state_provider = main._menu_state
	menu.adjustment_requested.connect(main._on_playback_adjustment)
	menu.adjustment_committed.connect(main._save_playback_adjustments)
	root.add_child(menu)
	menu.set_process(false)
	main.player_menu = menu
	main.recent_menu = Node3D.new()
	main.recent_menu.visible = false
	# Verify the visible per-eye aspect, including anamorphic PAR without double correction.
	for case in [[1920, 1080, 1.0, 1, 8.0/9.0], [1920, 1080, 1.0, 2, 32.0/9.0],
		[1920, 1080, 1.0, 3, 16.0/9.0], [1920, 1080, 1.0, 4, 16.0/9.0],
		[1920, 1080, 2.0, 1, 16.0/9.0], [1920, 1080, 2.0, 3, 16.0/9.0],
		[1920, 1080, 0.5, 2, 16.0/9.0], [1920, 1080, 0.5, 4, 16.0/9.0],
		[3840, 1080, 1.0, 1, 16.0/9.0], [1920, 2160, 1.0, 2, 16.0/9.0]]:
		video.media.format = {"width": case[0], "height": case[1], "pixel_aspect": case[2]}
		video.set_stereo_layout(case[3])
		video._apply_geometry()
		check(is_equal_approx(video._flat.size.x / video._flat.size.y, case[4]), "Flat visible aspect " + str(case))
	video.stereo_half = false
	video.media.format = {"width": 1920, "height": 1080}
	var eye := Vector3(0, 1.6, 0)
	for mode in ["2d", "sbs", "tb", "depth", "warped_depth"]:
		video.stereo_sbs = mode in ["sbs", "tb"]
		video.top_bottom = mode == "tb"
		video.depth_requested = mode in ["depth", "warped_depth"]
		video.depth_enabled = video.depth_requested
		video._binding.warped = mode == "warped_depth"
		for curve in [0.0, 0.7]:
			video.screen_curve = curve
			video.screen_distance = 2.0
			video.screen_scale = 1.0
			video.flat_pose = Transform3D(Basis(), eye + Vector3(0, 0, -2))
			video._apply_geometry()
			video.panel.visible = true
			var size: Vector2 = video._flat.size
			menu.toggle() if not menu.visible else menu.refresh()
			main.test_ray = [eye, Vector3.FORWARD]
			main._on_pointer_button("grip_click", "right_hand")
			check(not menu.visible and main._grab.get("action", "") == "grip_click", "%s grip closes controls" % mode)
			main._update_flat_grab_stick(Vector2(0, 1), Vector2.ZERO, 0.4)
			check(video.screen_scale == 1.0, "Other hand cannot move held screen")
			main._update_flat_grab_stick(Vector2.ZERO, Vector2(0, 1), 0.4)
			check(video.screen_scale == 1.0 and is_equal_approx(video.screen_distance,2.6), "%s grip plus stick moves farther without scaling" % mode)
			var grown: float = video.screen_scale
			video._apply_geometry() # Next native frame must retain the new mesh and pose.
			check(video._flat.size.is_equal_approx(size * grown), "%s presented frame preserves size" % mode)
			main._update_flat_grab_stick(Vector2.ZERO, Vector2(0, -1), 0.4)
			check(is_equal_approx(video.screen_distance,2.0) and video.screen_scale == 1.0, "%s grip plus stick down moves nearer symmetrically" % mode)
			main._on_pointer_release("grip_click", "right_hand")
			check(main._grab.is_empty() and not menu.visible, "Release finishes without reopening controls")
			for corner in [0, 1]:
				video.set_screen_scale(1)
				var hit: Vector3 = video.panel.to_global(video.screen_corner(corner))
				main.test_ray = [eye, (hit - eye).normalized()]
				main._begin_grab("right_hand")
				check(main._grab.has("resize"), "%s curve %s corner %s begins resize" % [mode, curve, corner])
				main._update_corner_hover()
				check(video._handles[corner].visible, "Active corner bracket is visible")
				main.test_ray = [eye, (video.panel.to_global(Vector3(video.screen_corner(corner).x * 1.5, video.screen_corner(corner).y * 1.5, 0)) - eye).normalized()]
				main._update_grab()
				check(video.screen_scale > 1 and is_equal_approx(video.screen_distance, 2), "%s corner grows without moving distance" % mode)
				main._on_pointer_release("grip_click", "right_hand")
			video.set_screen_scale(1)
			main._grab = {"hand": "right_hand", "moved": false}
			menu.toggle()
			main._update_flat_grab_stick(Vector2.ZERO, Vector2(0, 1), 1)
			check(video.screen_scale == 1, "Open menu blocks held stick playback action")
			main._grab = {}
			menu.section = 1
			menu.refresh()
			menu._activate(11)
			check(menu._adjustment == "screen", "%s opens distance editor" % mode)
			menu.press_pointer("right_hand", menu.to_global(Vector3(0.63, 0.19, 1)), -menu.global_basis.z, true)
			check(video.screen_distance == 8 and is_equal_approx(video.panel.global_position.distance_to(eye), 8) and video.screen_scale == 1, "Distance slider moves screen without scaling")
			menu.release_pointer("right_hand", Vector3.ZERO, Vector3.ZERO, true)
			var saved := ConfigFile.new()
			check(saved.load(main.settings_path) == OK and saved.get_value("screen", "distance") == 8, "Distance saves on release")
			menu.press_pointer("right_hand", menu.to_global(Vector3(0.13, 0.19, 1)), -menu.global_basis.z, true)
			menu.release_pointer("right_hand", Vector3.ZERO, Vector3.ZERO, true)
			check(is_equal_approx(video.screen_distance, 2), "2m slider restores default distance")
			menu.dismiss()
	# Translation/dragging may move the screen vertically, but not tilt its plane.
	video.global_transform = Transform3D(Basis.from_euler(Vector3(.2, .4, -.1)), Vector3(.1, .2, .3))
	var tilted := Transform3D(Basis.from_euler(Vector3(.5, .7, .3)), eye + Vector3(0, 0, -2))
	video.set_flat_world_pose(tilted)
	check(absf(video.panel.global_basis.z.y) < .00001 and video.panel.global_position.is_equal_approx(tilted.origin), "Flat-video constraint is in world space and preserves position")
	video.set_screen_rotation(25)
	check(absf(video.panel.global_basis.z.y) < .00001 and video.screen_rotation == 25, "Explicit picture rotation stays inside the vertical screen plane")
	var height := video.panel.global_position.y
	main._turn_picture(.15, .2)
	check(absf(video.panel.global_basis.z.y) < .00001 and not is_equal_approx(video.panel.global_position.y, height), "Grip pitch moves the screen up/down without leaning it")
	video.global_transform = Transform3D.IDENTITY; video.set_screen_rotation(0)
	main._grab = {"hand": "right_hand", "moved": false}
	main._update_flat_grab_stick(Vector2.ZERO, Vector2(0, 1), 10)
	check(video.screen_scale == video.SCALE_LIMITS.y, "Upper scale limit")
	main._update_flat_grab_stick(Vector2.ZERO, Vector2(0, -1), 10)
	check(video.screen_scale == video.SCALE_LIMITS.x, "Lower scale limit")
	main._grab = {}
	video.geometry = 1
	menu.toggle()
	menu.section = 1
	menu.refresh()
	menu._activate(11)
	check(menu._adjustment == "screen" and not menu._adjust_rows.values().any(func(row): return row.key == "screen_distance"), "Immersive projection disables flat distance")
	main._on_playback_adjustment("screen_distance", 5)
	check(is_equal_approx(video.screen_distance, 2), "Immersive adjustment cannot change flat screen")
	menu.dismiss(); main._grab = {"hand": "right_hand", "action": "grip_click", "moved": false}
	video.view_zoom = 0.0
	main._update_flat_grab_stick(Vector2(0, 1), Vector2.ZERO, .5)
	check(is_zero_approx(video.view_zoom), "Other hand cannot move held immersive view")
	main._update_flat_grab_stick(Vector2.ZERO, Vector2(0, 1), .5)
	check(video.view_zoom < 0, "Immersive grip plus stick up moves view farther")
	var held_zoom: float = video.view_zoom
	main._process_sticks(Vector2(1, 1), Vector2(0, 1), .5)
	check(video.view_zoom == held_zoom, "Grip blocks ordinary playback stick shortcuts")
	main._update_flat_grab_stick(Vector2.ZERO, Vector2(0, -1), .5)
	check(is_zero_approx(video.view_zoom), "Immersive grip plus stick down reverses depth movement")
	main._grab.clear(); video.geometry = 0; video.reclining_mode = true
	video.screen_distance = 2.0; video.screen_scale = 1.0
	video.flat_pose = Transform3D(Basis(Vector3.RIGHT, .6), eye + Vector3(0, .5, -1.93649))
	video._apply_geometry(); main.test_ray = [eye,(video.panel.global_position-eye).normalized()]
	main._begin_grab("right_hand")
	var old_position: Vector3 = video.panel.global_position
	main.test_ray[0] += Vector3.UP * .3; main._update_grab()
	check(video.panel.global_position.y > old_position.y and is_equal_approx(video.screen_scale,1), "Physical grip translation moves reclining picture vertically without scaling")
	main._on_pointer_release("grip_click", "right_hand")
	menu.free()
	main.recent_menu.free()
	main.free()
	video.free()
	for failure in failures: push_error(failure)
	print("Flat screen controls: %s (%d)" % ["passed" if failures.is_empty() else "failed", checks])
	quit(0 if failures.is_empty() else 1)
