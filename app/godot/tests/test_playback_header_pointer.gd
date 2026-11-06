extends SceneTree
const Main := preload("res://scripts/main.gd")
const Surface := preload("res://scripts/xr_menu_compositor.gd")
var checks := 0
var failures: Array[String] = []


class InputMain:
	extends Main
	var test_ray: Variant

	func _ray(_hand: String) -> Variant:
		return test_ray


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func ray_to(host: Node3D, point: Vector3, curved: bool) -> Array:
	var origin: Vector3 = host._eye() + Vector3(.10, .04, .20)
	var physical := point
	if curved:
		var surface: Node3D = host.menu_compositor
		var pose := Surface.capture_pose(surface.active_menu)
		var local: Vector3 = pose.affine_inverse() * point
		var centre: Vector2 = surface.surface_rect.get_center()
		var radius: float = surface.active_menu.curve_radius
		var angle: float = (local.x - centre.x) / radius
		physical = (
			pose * Vector3(centre.x + sin(angle) * radius, local.y, (1 - cos(angle)) * radius)
		)
	return [origin, (physical - origin).normalized(), physical]


func _run() -> void:
	var host := InputMain.new()
	host.settings_path = "user://header-pointer.cfg"
	root.add_child(host)
	host.set_process(false)
	host.menu_compositor.set_process(false)
	host.video.set_process(false)
	host.report_timer.stop()
	host.video.local_uri = "file:///header-SBS.mp4"
	host.video.media.begin(1)
	host.video.media.state = "paused"
	host.video.media.frame_counter = 1
	host.video._waiting_first = false
	host.video.control.duration_ms = 60000
	host.video._apply_geometry()
	host.video.panel.visible = true
	host._show_player_menu()
	var menu: Node3D = host.player_menu
	for curved in [false, true]:
		if curved:
			host.menu_compositor._process(0)
		for name in ["title", "status"]:
			host._show_player_menu()
			if curved:
				host.menu_compositor._process(0)
			var panel: MeshInstance3D = (
				menu._title_pill if name == "title" else menu.device_status._pill
			)
			var ray := ray_to(host, panel.global_position, curved)
			check(
				menu.ray_hit(ray[0], ray[1]).is_empty(), "Information stays non-actionable: " + name
			)
			var hit: Dictionary = menu.ray_panel_hit(ray[0], ray[1])
			check(
				not hit.is_empty(), "Visible header accepts surface feedback: " + name + str(curved)
			)
			menu.update_pointer("right_hand", ray[0], ray[1], true)
			check(
				menu._pointers.right_hand.dot.visible and menu._hover.right_hand == menu.NONE,
				"Header shows a neutral reticle: " + name
			)
			if curved and not hit.is_empty():
				check(
					hit.world_point.distance_to(ray[2]) < .0001,
					"Curved header laser ends on the visible cylinder"
				)
			host.test_ray = ray
			host._on_pointer_button("trigger_click", "right_hand")
			host._on_pointer_release("trigger_click", "right_hand")
			check(
				menu.visible and host._trigger_taps.is_empty() and host._grab.is_empty(),
				"Header press does not click through or dismiss controls: " + name
			)
	# Rounded transparent corners and gaps outside the header remain non-surfaces.
	host._show_player_menu()
	host.menu_compositor._process(0)
	var title: MeshInstance3D = menu._title_pill
	var corner := title.to_global(
		Vector3(title.mesh.size.x / 2 - .0005, title.mesh.size.y / 2 - .0005, 0)
	)
	var ray := ray_to(host, corner, true)
	check(
		menu.ray_panel_hit(ray[0], ray[1]).is_empty(),
		"Transparent pill corner does not stop the ray"
	)
	menu.device_status.visible = false
	ray = ray_to(host, menu.device_status._pill.global_position, true)
	check(
		menu.ray_panel_hit(ray[0], ray[1]).is_empty(), "Hidden status panel cannot intercept rays"
	)
	menu.device_status.visible = true
	# A compact browser must not steal feedback from the visible playback header.
	host.recent_menu.compact = true
	host._show_recent_menu()
	host.menu_compositor._process(0)
	ray = ray_to(host, menu._title_pill.global_position, true)
	host.test_ray = ray
	host._update_menu_pointer("right_hand")
	check(
		(
			menu._pointers.right_hand.dot.visible
			and not host.recent_menu._pointers.right_hand.dot.visible
		),
		"Controller routes informational header feedback beside the browser"
	)
	var event := InputEventMouseMotion.new()
	event.position = host.xr_camera.unproject_position(ray[2])
	host._unhandled_input(event)
	check(
		menu._pointers.get("desktop", {}).get("dot") != null and menu._pointers.desktop.dot.visible,
		"Preview pointer also reaches the informational header"
	)
	# Outside taps retain their existing dismissal behavior.
	host._show_player_menu()
	host.menu_compositor._process(0)
	host.test_ray = ray_to(host, menu.to_global(Vector3(.78, .38, 0)), true)
	host._on_pointer_button("trigger_click", "right_hand")
	host._on_pointer_release("trigger_click", "right_hand")
	check(not menu.visible, "A tap outside all UI still dismisses controls")
	host.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Playback header pointer checks=", checks, " failures=", failures.size())
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
