extends SceneTree
const Menu := preload("res://scripts/library_menu.gd")
class Platform extends RefCounted:
	signal update_check_ready(id: int, json: String)
	var requested: Array = []
	var opened: Array = []
	func request_update_check(version: String) -> int:
		requested.append(version)
		return requested.size()
	func open_update_release(tag: String) -> bool:
		opened.append(tag)
		return true
func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	call_deferred("_run")
func _run() -> void:
	var platform := Platform.new()
	var menu := Menu.new()
	root.add_child(menu)
	menu.attach_platform(platform)
	menu.section = Menu.Section.SETTINGS
	menu.tab = Menu.ABOUT_TAB
	menu.refresh()
	assert(platform.requested.is_empty(), "Displaying About never checks automatically")
	assert(menu.rows[0].title == "Immivio" and menu.rows[1].check_updates)
	menu._choose(menu.rows[1])
	assert(platform.requested.size() == 1 and menu.update_check.state == "checking")
	menu._choose(menu.rows[1])
	assert(platform.requested.size() == 1)
	var version := str(ProjectSettings.get_setting("application/config/version"))
	platform.update_check_ready.emit(99, JSON.stringify({"state": "available", "version": version, "tag": "v9.9.9"}))
	assert(menu.update_check.state == "checking")
	platform.update_check_ready.emit(1, JSON.stringify({"state": "available", "version": version, "tag": "v9.9.9"}))
	assert(menu.rows[1].detail == "v9.9.9")
	var release: Dictionary = menu.rows.filter(func(row): return row.get("open_update_release", false))[0]
	menu._choose(release)
	assert(platform.opened == ["v9.9.9"] and platform.requested.size() == 1)
	for state in ["latest", "rate_limited", "network_error", "invalid_response"]:
		menu._choose(menu.rows[1])
		platform.update_check_ready.emit(platform.requested.size(), JSON.stringify({"state": state, "version": version}))
		assert(menu.update_check.state == state)
		assert(menu.rows.filter(func(row): return row.get("open_update_release", false)).is_empty())
		if state == "latest":
			assert(menu.rows[1].detail.contains(version))
	menu._choose(menu.rows[1])
	platform.update_check_ready.emit(platform.requested.size(), JSON.stringify({"state": "available", "version": version, "tag": "https://evil.example/"}))
	assert(menu.update_check.state == "invalid_response")
	var count := platform.requested.size()
	menu.refresh()
	menu._on_android_lifecycle("resume")
	assert(platform.requested.size() == count, "Resume and redraw never initiate IO")
	menu.free()
	preload("res://tests/support/test_result.gd").finish(self, 0)
