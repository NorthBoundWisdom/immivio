extends SceneTree

const Video := preload("res://scripts/mpv_video_display.gd")
const Menu := preload("res://scripts/player_menu.gd")
const RayMenu := preload("res://scripts/ray_menu.gd")
var failures: Array[String] = []
var checks := 0

class InputMain extends "res://scripts/main.gd":
	var test_ray: Variant
	func _ray(_hand: String) -> Variant: return test_ray

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var main := InputMain.new()
	main.settings_path = "user://controller-canvas-%d.cfg" % Time.get_ticks_usec()
	var video := Video.new()
	root.add_child(video); video.set_process(false)
	main.video = video
	video.local_uri = "file:///canvas.mp4"
	video.media.begin(1); video.media.state = "playing"
	video.media.format = {"width": 1920, "height": 1080}
	video.control.duration_ms = 10000
	video.requested_play = true
	var camera := Camera3D.new()
	root.add_child(camera); camera.position = Vector3(0, 1.6, 0)
	camera.rotation.y = 1.2 # The viewer is looking away from the relocated canvas.
	video.view_camera = camera
	video.flat_pose = Transform3D(Basis(Vector3.UP, -.6) * Basis(Vector3.RIGHT, .2), Vector3(1.2, 2.1, -2.4))
	video.screen_rotation = 20
	video._apply_geometry(); video.panel.visible = true
	var menu := Menu.new()
	menu.state_provider = main._menu_state
	root.add_child(menu); menu.set_process(false)
	main.player_menu = menu
	var library := RayMenu.new()
	root.add_child(library); main.recent_menu = library
	main.test_ray = [camera.global_position, (video.panel.global_position - camera.global_position).normalized()]
	var before := video.flat_pose
	main._on_pointer_button("trigger_click", "right_hand")
	main.test_ray[1] = Vector3.RIGHT
	main._update_grab()
	check(main._grab.is_empty() and video.flat_pose.is_equal_approx(before), "Holding/moving trigger cannot drag canvas")
	main._on_pointer_release("trigger_click", "right_hand")
	check(menu.visible, "Trigger tap opens controls on release")
	var centre := video.subtitle_transform()
	check(menu.to_global(Vector3(0, Menu.BAR_SEEK_Y, 0)).is_equal_approx(centre.origin + centre.basis.z * .025), "Timeline centre overlays relocated canvas, not head forward")
	check(menu.global_basis.is_equal_approx(centre.basis), "Controls follow canvas facing without image roll")
	menu.section = 1
	check(menu.global_position.is_equal_approx(centre.origin + centre.basis.z * .025), "Expanded settings remain centred on canvas")
	menu.section = 0
	main.test_ray = [camera.global_position, (video.panel.global_position - camera.global_position).normalized()]
	main._on_pointer_button("grip_click", "right_hand")
	check(not menu.visible and main._grab.get("action") == "grip_click", "Grip dismisses controls and owns canvas movement")
	main.test_ray[1] = Basis(Vector3.UP, .25) * main.test_ray[1]
	main._update_grab()
	check(not video.flat_pose.is_equal_approx(before), "Grip motion moves the canvas")
	main._on_pointer_release("trigger_click", "right_hand")
	main._on_pointer_release("grip_click", "left_hand")
	check(not main._grab.is_empty() and not menu.visible, "Trigger or other-hand release cannot finish grip")
	main._on_pointer_release("grip_click", "right_hand")
	check(main._grab.is_empty() and not menu.visible and video.requested_play, "Grip release neither opens controls nor pauses playback")
	main._on_pointer_button("grip_click", "right_hand")
	main._on_pointer_release("grip_click", "right_hand")
	check(not menu.visible and video.requested_play, "Stationary grip tap has no playback/menu side effect")
	main._on_pointer_button("trigger_click", "right_hand")
	main._on_pointer_button("grip_click", "right_hand")
	main._on_pointer_release("trigger_click", "right_hand")
	check(not menu.visible and not main._grab.is_empty(), "Starting a grip cancels a pending trigger tap")
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
	check(menu.ray_hit(main.test_ray[0], main.test_ray[1]).get("target", -1) == Menu.SEEK, "Timeline remains selectable at maximum canvas distance")
	main._on_pointer_button("trigger_click", "right_hand")
	check(menu.has_pointer_capture(), "Trigger still captures the timeline slider")
	main._on_pointer_button("grip_click", "left_hand")
	check(main._grab.is_empty() and menu.visible, "Grip cannot steal a captured slider")
	var captured_pose := menu.global_transform
	video.flat_pose.origin.x += .3
	video._apply_geometry()
	main._update_player_menu_anchor()
	check(menu.global_transform.is_equal_approx(captured_pose), "Captured slider plane stays fixed when the canvas changes")
	main._on_pointer_release("trigger_click", "right_hand")
	check(not menu.has_pointer_capture(), "Trigger release ends slider capture")
	main._update_player_menu_anchor()
	check(menu.to_global(Vector3(0, Menu.BAR_SEEK_Y, 0)).is_equal_approx(video.panel.global_position + video.subtitle_transform().basis.z * .025), "Released controls reattach to the changed canvas")
	video.geometry = 1; video.view_yaw = .6; video.view_pitch = .1
	video._apply_geometry()
	main._update_player_menu_anchor()
	var forward := -video.subtitle_transform().basis.z
	check((menu.to_global(Vector3(0, Menu.BAR_SEEK_Y, -.025)) - camera.global_position).normalized().is_equal_approx(forward), "Immersive controls align with picture centre, not current head yaw")
	menu.free(); library.free(); camera.free(); main.free(); video.free()
	for failure in failures: push_error(failure)
	print("Controller canvas: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
