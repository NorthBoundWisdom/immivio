extends SceneTree
const Main := preload("res://scripts/main.gd")
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
func target(menu: Node3D, kind: String, key: String) -> int:
	for id in menu.choices.targets:
		if menu.choices.targets[id].get("kind") == kind and menu.choices.targets[id].get("key") == key:
			return id
	return -1
func position(host: Node3D, menu: Node3D, id: int) -> Vector2:
	for button in menu._buttons:
		if button.target == id:
			return host.xr_camera.unproject_position(button.node.global_position)
	return Vector2.ZERO
func mouse(host: Node3D, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	host._unhandled_input(event)
func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()
func _run() -> void:
	var host := Main.new()
	host.settings_path = "user://preview-input.cfg"
	root.add_child(host)
	host.set_process(false)
	host.menu_compositor.set_process(false)
	host.video.set_process(false)
	host.report_timer.stop()
	var menu: Node3D = host.recent_menu
	menu.set_process(false)
	menu._activate(menu.NAV_BASE + menu.Section.SETTINGS)
	var at := position(host, menu, target(menu, "open", "language"))
	mouse(host, at, true)
	check(not menu.choices.capture.is_empty() and menu.choices.opened.is_empty(), "Preview mouse press captures the dropdown without committing")
	mouse(host, at, false)
	check(menu.choices.opened == "language" and not menu.choices.popup.is_empty(), "Preview mouse release opens real option rows")
	menu.choices.reset()
	menu.refresh()
	host.display.preview = false
	mouse(host, position(host, menu, target(menu, "open", "language")), true)
	check(menu.choices.capture.is_empty(), "Mouse preview routing is disabled for actual XR")
	host.display.preview = true
	menu.dismiss()
	host.player_menu.visible = true
	host.video.requested_play = true
	host.video.media.state = "playing"
	host._menu_touched_ms = Time.get_ticks_msec() - host.CONTROLS_HIDE_MS - 100
	host._show_player_menu()
	host._input._update_controls_visibility(host.player_menu)
	check(host.player_menu.visible, "Explicitly showing visible controls refreshes their idle timeout")
	host.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Preview input checks=", checks, " failures=", failures.size())
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
