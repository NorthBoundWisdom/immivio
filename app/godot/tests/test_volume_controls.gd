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


func _aim(host: Node3D, menu: Node3D, target: int, enabled: bool = true) -> bool:
	for button in menu.controls_snapshot():
		if button.target == target and button.node.visible and button.enabled == enabled:
			var point: Vector3 = button.node.global_position
			host.xr_camera.look_at(point)
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

	menu.test_activate(menu.FOLLOW)
	assert(host.view_follow.enabled)
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

	host.set_process(true)
	await process_frame
	var fixed_menu: Transform3D = menu.global_transform
	assert(_aim(host, menu, menu.FOLLOW, false))
	await process_frame
	assert(menu.hover_snapshot().get("gaze") == menu.FOLLOW)
	var tip: String = menu.I18n.t("Turn off volume button controls to change Follow")
	assert(
		menu.find_children("*", "Label3D", true, false).any(
			func(label): return label.is_visible_in_tree() and label.text == tip
		)
	)
	_tap(KEY_VOLUMEUP)
	assert(host.view_follow.enabled)
	var local_target: int = menu.NAV_BASE + menu.Section.LOCAL
	assert(_aim(host, menu, local_target))
	await process_frame
	assert(menu.global_transform.is_equal_approx(fixed_menu))
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
	await process_frame
	assert(menu.global_transform.is_equal_approx(fixed_menu))
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
	await process_frame
	assert(menu.global_transform.is_equal_approx(fixed_menu))
	host.xr_camera.rotate_y(0.25)
	await process_frame
	assert(not menu.global_transform.is_equal_approx(fixed_menu))
	assert(_aim(host, menu, menu.FOLLOW))
	menu.test_activate(menu.FOLLOW)
	assert(not host.view_follow.enabled)

	host.queue_free()
	await process_frame
	TestResult.finish(self, 0)
