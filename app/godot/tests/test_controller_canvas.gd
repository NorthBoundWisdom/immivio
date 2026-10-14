extends SceneTree

const Video := preload("res://scripts/mpv_video_display.gd")
const Menu := preload("res://scripts/player_menu.gd")
const RayMenu := preload("res://scripts/ray_menu.gd")
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
	call_deferred("_run")


func _run() -> void:
	var main := InputMain.new()
	main.settings_path = "user://controller-canvas-%d.cfg" % Time.get_ticks_usec()
	var video := Video.new()
	root.add_child(video)
	video.set_process(false)
	main.video = video
	main.display.preview = true
	video.local_uri = "file:///canvas.mp4"
	video.media.begin(1)
	video.media.state = "playing"
	video.media.format = {"width": 1920, "height": 1080}
	video.control.duration_ms = 10000
	video.requested_play = true
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 1.6, 0)
	camera.rotation.y = .12  # Canvas is off-centre: eye-to-centre is not gaze direction.
	camera.rotation.x = -.15
	video.view_camera = camera
	video.flat_pose = Transform3D(
		Basis(Vector3.UP, -.6) * Basis(Vector3.RIGHT, .2), Vector3(1.2, 2.1, -2.4)
	)
	video.screen_rotation = 20
	video._apply_geometry()
	video.panel.visible = true
	var menu := Menu.new()
	menu.state_provider = main._menu_state
	root.add_child(menu)
	menu.set_process(false)
	main.player_menu = menu
	var library := RayMenu.new()
	root.add_child(library)
	main.recent_menu = library
	main.test_ray = [
		camera.global_position, (video.panel.global_position - camera.global_position).normalized()
	]
	var before := video.flat_pose
	main._on_pointer_button("trigger_click", "right_hand")
	main.test_ray[1] = Vector3.RIGHT
	main._update_grab()
	check(
		main._grab.is_empty() and video.flat_pose.is_equal_approx(before),
		"Holding/moving trigger cannot drag canvas"
	)
	main._on_pointer_release("trigger_click", "right_hand")
	check(menu.visible, "Trigger tap opens controls on release")
	var centre := video.subtitle_transform()
	var timeline := menu.to_global(Vector3(0, Menu.BAR_SEEK_Y, 0))
	check(
		(
			(timeline + Vector3.UP * Menu.EXTRA_DROP - camera.global_position)
			. normalized()
			. is_equal_approx((centre.origin - camera.global_position).normalized())
		),
		"Timeline sits below the relocated canvas centre, not head forward"
	)
	check(
		(
			menu.global_basis.y.normalized().is_equal_approx(Vector3.UP)
			and absf(menu.global_basis.z.y) < .00001
		),
		"Controls are vertical relative to the floor despite head/canvas tilt"
	)
	var horizontal_eye := camera.global_position - centre.origin
	horizontal_eye.y = 0
	check(
		menu.global_basis.z.is_equal_approx(horizontal_eye.normalized()),
		"Controls face the eye horizontally"
	)
	check(
		(
			is_equal_approx(
				menu._backdrop.mesh.size.x * menu._backdrop.global_basis.x.length(), .87
			)
			and is_equal_approx(
				menu._backdrop.mesh.size.y * menu._backdrop.global_basis.y.length(), .20 * 2.0 / 3.0
			)
		),
		"Visible playback backdrop measures 3/4 width and 2/3 height"
	)
	var stable_pose := menu.global_transform
	camera.rotation.z = .2
	camera.position.x += .02
	main._update_player_menu_anchor()
	check(
		menu.global_transform.is_equal_approx(stable_pose),
		"Idle controls ignore head roll and translation"
	)
	camera.rotation.x = .8
	camera.rotation.y += .6
	main._update_player_menu_anchor()
	check(
		menu.global_transform.is_equal_approx(stable_pose),
		"Head pitch and yaw cannot rotate controls away from their canvas"
	)
	menu.section = 1
	main._update_player_menu_anchor()
	check(
		(menu.global_position - camera.global_position).normalized().is_equal_approx(
			(centre.origin - camera.global_position).normalized()
		),
		"Expanded settings remain visually centred on canvas"
	)
	var clear := true
	for corner in [
		Vector3(-.8, -.5, 0), Vector3(.8, -.5, 0), Vector3(-.8, .9, 0), Vector3(.8, .9, 0)
	]:
		clear = clear and (menu.to_global(corner) - centre.origin).dot(centre.basis.z) > 0.0
	check(clear, "Oblique canvas cannot depth-clip the viewer-facing controls")
	menu.section = 0
	main.test_ray = [
		camera.global_position, (video.panel.global_position - camera.global_position).normalized()
	]
	main._on_pointer_button("grip_click", "right_hand")
	check(
		not menu.visible and main._grab.get("action") == "grip_click",
		"Grip dismisses controls and owns canvas movement"
	)
	main.test_ray[1] = Basis(Vector3.UP, .25) * main.test_ray[1]
	main._update_grab()
	check(not video.flat_pose.is_equal_approx(before), "Grip motion moves the canvas")
	main._on_pointer_release("trigger_click", "right_hand")
	main._on_pointer_release("grip_click", "left_hand")
	check(
		not main._grab.is_empty() and not menu.visible,
		"Trigger or other-hand release cannot finish grip"
	)
	main._on_pointer_release("grip_click", "right_hand")
	check(
		main._grab.is_empty() and not menu.visible and video.requested_play,
		"Grip release neither opens controls nor pauses playback"
	)
	main._on_pointer_button("grip_click", "right_hand")
	main._on_pointer_release("grip_click", "right_hand")
	check(
		not menu.visible and video.requested_play,
		"Stationary grip tap has no playback/menu side effect"
	)
	main._on_pointer_button("trigger_click", "right_hand")
	main._on_pointer_button("grip_click", "right_hand")
	main._on_pointer_release("trigger_click", "right_hand")
	check(
		not menu.visible and not main._grab.is_empty(),
		"Starting a grip cancels a pending trigger tap"
	)
	main._on_pointer_release("grip_click", "right_hand")
	main._on_pointer_button("trigger_click", "right_hand")
	main.test_ray = null
	main._on_pointer_release("trigger_click", "right_hand")
	check(main._trigger_taps.is_empty() and not menu.visible, "Tracking loss cancels trigger tap")
	main.test_ray = [camera.global_position, Vector3.FORWARD]
	main._on_pointer_button("trigger_click", "right_hand")
	video.local_uri = "file:///other.mp4"
	main._on_pointer_release("trigger_click", "right_hand")
	check(not menu.visible, "Content change cancels a pending trigger tap")
	video.screen_rotation = 0
	video.screen_distance = 8
	video.flat_pose = Transform3D(Basis.IDENTITY, camera.global_position + Vector3(0, 0, -8))
	video._apply_geometry()
	main._show_player_menu()
	var target := menu.to_global(Vector3(0, Menu.BAR_SEEK_Y, .01))
	main.test_ray = [camera.global_position, (target - camera.global_position).normalized()]
	check(
		menu.ray_hit(main.test_ray[0], main.test_ray[1]).get("target", -1) == Menu.SEEK,
		"Timeline remains selectable at maximum canvas distance"
	)
	main._on_pointer_button("trigger_click", "right_hand")
	check(menu.has_pointer_capture(), "Trigger still captures the timeline slider")
	main._on_pointer_button("grip_click", "left_hand")
	check(main._grab.is_empty() and menu.visible, "Grip cannot steal a captured slider")
	var captured_pose := menu.global_transform
	camera.rotation.x += .2
	video.flat_pose.origin.x += .3
	video._apply_geometry()
	main._update_player_menu_anchor()
	check(
		menu.global_transform.is_equal_approx(captured_pose),
		"Captured slider plane stays fixed when the canvas or gaze changes"
	)
	main._on_pointer_release("trigger_click", "right_hand")
	check(not menu.has_pointer_capture(), "Trigger release ends slider capture")
	main._update_player_menu_anchor()
	check(
		(
			(
				menu.to_global(Vector3(0, Menu.BAR_SEEK_Y, 0))
				+ Vector3.UP * Menu.EXTRA_DROP
				- camera.global_position
			)
			. normalized()
			. is_equal_approx((video.panel.global_position - camera.global_position).normalized())
		),
		"Released controls reattach below the changed canvas centre in view"
	)
	video.geometry = 1
	video.view_yaw = .6
	video.view_pitch = .1
	video._apply_geometry()
	main._update_player_menu_anchor()
	var content := video.subtitle_transform().basis.orthonormalized()
	var in_content := (
		content.inverse()
		* (menu.to_global(Vector3(0, Menu.BAR_SEEK_Y, 0)) - camera.global_position)
	)
	check(
		in_content.is_equal_approx(Vector3(0, -Menu.IMMERSIVE_DROP, -Menu.IMMERSIVE_DISTANCE)),
		"Immersive timeline sits below the content/reset gaze centre"
	)
	check(
		menu.global_basis.orthonormalized().is_equal_approx(content),
		"Immersive controls are perpendicular to the reset/content gaze"
	)
	check(
		(
			is_equal_approx(menu.global_basis.x.length(), .75)
			and is_equal_approx(menu.global_basis.y.length(), 2.0 / 3.0)
		),
		"Playback panel has the requested width/height ratios"
	)
	stable_pose = menu.global_transform
	camera.rotation.x += .4
	camera.rotation.z += .3
	main._update_player_menu_anchor()
	check(
		menu.global_transform.is_equal_approx(stable_pose),
		"Immersive controls do not chase later head tilt"
	)
	video.reset_view()
	main._update_player_menu_anchor()
	check(
		menu.global_basis.z.is_equal_approx(camera.global_basis.z),
		"Immersive reset aligns the control plane with current gaze, including pitch"
	)
	stable_pose = menu.global_transform
	camera.position += Vector3(.03, .01, -.02)
	main._update_player_menu_anchor()
	check(
		(
			menu.global_basis.is_equal_approx(stable_pose.basis)
			and menu.global_position.is_equal_approx(stable_pose.origin + Vector3(.03, .01, -.02))
		),
		"Immersive head translation preserves content direction and stable menu orientation"
	)
	video.geometry = 0
	video.flat_pose = Transform3D(Basis.IDENTITY, camera.global_position + Vector3.UP * 2)
	video._apply_geometry()
	main._place_menu(menu)
	timeline = menu.to_global(Vector3(0, Menu.BAR_SEEK_Y, 0))
	check(
		(
			menu.global_basis.is_finite()
			and menu.global_basis.y.normalized().is_equal_approx(Vector3.UP)
		),
		"An overhead canvas retains a finite upright control plane"
	)
	video.flat_pose.origin = camera.global_position
	video._apply_geometry()
	main._place_menu(menu)
	check(
		menu.global_basis.y.normalized().is_equal_approx(Vector3.UP),
		"Coincident eye/canvas cannot inherit tilted content axes"
	)
	# Non-playback reset must stay at eye height and horizontal viewing distance.
	video.local_uri = ""
	menu.visible = false
	library.visible = true
	for yaw in [-2.4, -.7, 0.0, 1.9]:
		for pitch in [-1.2, .9]:
			camera.rotation = Vector3(pitch, yaw, .65)
			main._recenter()
			var delta := library.global_position - camera.global_position
			check(
				library.global_basis.y.is_equal_approx(Vector3.UP),
				"Library reset filters head pitch and roll"
			)
			check(
				(
					is_equal_approx(delta.y, 0.0)
					and absf(Vector2(delta.x, delta.z).length() - 1.4) < .0001
				),
				"Library reset uses fixed horizontal distance and eye-relative height"
			)
			check(
				delta.normalized().dot(-camera.global_basis.z) > 0,
				"Library reset chooses the current horizontal direction"
			)
	for pitch in [-PI / 2, PI / 2]:
		camera.rotation = Vector3(pitch, .7, .8)
		main._recenter()
		check(
			(
				library.global_transform.is_finite()
				and library.global_basis.y.is_equal_approx(Vector3.UP)
			),
			"Vertical gaze has a finite upright reset heading"
		)
	menu.free()
	library.free()
	camera.free()
	main.free()
	video.free()
	for failure in failures:
		push_error(failure)
	print("Controller canvas: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
