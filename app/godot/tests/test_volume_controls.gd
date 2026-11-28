extends SceneTree

const TestResult := preload("res://tests/support/test_result.gd")
const Main := preload("res://scripts/main.gd")
const Probe := preload("res://scripts/selected_features_device_probe.gd")


class TestInputSource:
	extends "res://scripts/input_source.gd"

	func head_tracked() -> bool:
		return true


class TestPlatform:
	extends RefCounted
	var overriding_volume := false

	func set_volume_key_override(enabled: bool) -> void:
		overriding_volume = enabled


func _initialize() -> void:
	if TestResult.prepare(self):
		call_deferred("_run")


func _key(key: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	event.echo = echo
	root.push_input(event)


func _tap(key: Key) -> void:
	_key(key, true)
	_key(key, false)


func _aim(host: Node3D, menu: Node3D, target: int) -> bool:
	for button in menu.controls_snapshot():
		if button.target == target and button.enabled:
			var point: Vector3 = button.node.global_position
			host.xr_camera.look_at_from_position(point + menu.global_basis.z, point)
			return true
	return false


func _run() -> void:
	create_timer(10.0).timeout.connect(func(): TestResult.finish(self, 1))
	var host := Main.new()
	host.input_source = TestInputSource.new(host)
	root.add_child(host)
	host.set_process(false)
	host.report_timer.stop()
	var platform := TestPlatform.new()
	host.platform_plugin = platform
	host.display.preview = false
	host.display.session_state = "session_focussed"
	var menu := host.library_menu
	var settings_target: int = menu.NAV_BASE + menu.Section.SETTINGS
	assert(_aim(host, menu, settings_target))
	_tap(KEY_VOLUMEUP)
	assert(menu.section == menu.Section.RECENT and not platform.overriding_volume)

	menu.test_activate(settings_target)
	var rows: Array = menu.rows.filter(func(row): return row.get("key") == "volume_controls")
	assert(rows.size() == 1 and rows[0].value == false)
	var probe := Probe.new()
	assert(await probe.choose(menu, "volume_controls", true))
	assert(platform.overriding_volume and not host.input_source.controller_allowed("right_hand"))
	var saved := ConfigFile.new()
	assert(saved.load(host.settings_path) == OK)
	assert(saved.get_value("controls", "volume_controls") == true)
	_tap(KEY_VOLUMEDOWN)
	assert(menu.section == menu.Section.RECENT and menu.visible)

	var local_target: int = menu.NAV_BASE + menu.Section.LOCAL
	assert(_aim(host, menu, local_target))
	host.test_process_sticks(Vector2.ZERO, Vector2.ZERO, 0.01)
	assert(menu.hover_snapshot().get("gaze") == local_target)
	var pointer: Dictionary = menu.pointer_snapshot().gaze
	assert(pointer.dot.visible and not pointer.line.visible)
	_tap(KEY_VOLUMEUP)
	assert(menu.section == menu.Section.LOCAL)
	menu.sources.local_stack = [{"id": "/Movies", "title": "Movies"}]
	_key(KEY_VOLUMEDOWN, true)
	_key(KEY_VOLUMEDOWN, true, true)
	_key(KEY_VOLUMEDOWN, false)
	assert(menu.sources.local_stack.is_empty() and menu.section == menu.Section.LOCAL)

	assert(_aim(host, menu, settings_target))
	_tap(KEY_VOLUMEUP)
	assert(menu.section == menu.Section.SETTINGS)
	var off := probe.choice_target(menu, "volume_controls", "choose", false)
	assert(_aim(host, menu, off))
	_key(KEY_VOLUMEUP, true)
	assert(platform.overriding_volume)
	host.display.session_state = "session_visible"
	host.display.status_changed.emit()
	assert(not platform.overriding_volume)
	host.display.session_state = "session_focussed"
	host.display.status_changed.emit()
	assert(platform.overriding_volume)
	_key(KEY_VOLUMEUP, false)
	assert(platform.overriding_volume)
	_key(KEY_VOLUMEUP, true)
	_key(KEY_VOLUMEUP, true, true)
	_key(KEY_VOLUMEUP, false, true)
	assert(not platform.overriding_volume and host.input_source.controller_allowed("right_hand"))
	assert(saved.load(host.settings_path) == OK)
	assert(saved.get_value("controls", "volume_controls") == false)
	_tap(KEY_VOLUMEDOWN)
	assert(menu.section == menu.Section.SETTINGS)

	host.queue_free()
	await process_frame
	TestResult.finish(self, 0)
