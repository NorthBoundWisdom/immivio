extends SceneTree
const Menu := preload("res://scripts/library_menu.gd")
const Accounts := preload("res://scripts/account_panel.gd")
class Platform:
	extends "res://tests/account_platform_fixture.gd"
	signal media_list(id: int, payload: String)
	signal android_lifecycle(state: String)

var checks := 0
var failures: Array[String] = []


class JavaMethods:
	extends Object

	func has_java_method(method: String) -> bool:
		return method in ["account_open", "license_text"]


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	call_deferred("_run")


func _run() -> void:
	var platform := Platform.new()
	var menu := Menu.new()
	root.add_child(menu)
	menu.attach_platform(platform)
	menu.visible = true
	menu.section = Menu.Section.MEDIA_SERVER
	var panel: RefCounted = menu.account_panel
	var java := JavaMethods.new()
	menu.platform = java
	check(
		not java.has_method("account_open") and panel.supported(),
		"JNI account methods are supported through the Java method registry"
	)
	check(
		Menu.PlatformMethods.supports(java, "license_text"),
		"JNI license method is detected through the Java method registry"
	)
	menu.platform = null
	check(not panel.supported(), "missing account plugin remains unavailable")
	menu.platform = platform
	java.free()
	menu.section = Menu.Section.SETTINGS
	menu.tab = Menu.ABOUT_TAB
	menu.refresh()
	menu._open_licenses()
	check(
		not menu.rows.any(func(row): return row.license_id in ["115", "openlist", "openlist-dependencies"]), "Removed cloud components are absent from About"
	)
	check(
		menu._engine_notices().contains("Permission is hereby granted"),
		"engine third-party notices include full license texts"
	)
	menu._choose(menu.rows[0])
	check(
		panel.view == "license" and panel.license_lines.size() > 10,
		"full engine license has scrollable text"
	)
	check(not menu._grid() and menu._max_scroll() > 0, "license is a scrolling reader")
	for button in menu._buttons:
		if button.target >= Menu.ROW_BASE and button.target < Menu.ROW_BASE + menu._drawn_slots():
			var row: Dictionary = menu.rows[button.target - Menu.ROW_BASE]
			check(
				button.node.get_child(0).text == row.title,
				"license lines retain full text without ellipsis"
			)
	panel.action(Accounts.BASE)
	check(
		menu._about_page == 3 and menu.rows.size() >= 9,
		"reader back returns to global license list"
	)
	panel.open("server")
	check(menu.rows.size() == 6, "server chooser includes discovery and five types")
	panel.choose(menu.rows[1])
	check(
		panel.fields.has("base") and panel.fields.has("password"),
		"server editor includes address and transient secret"
	)
	var id: int = panel.session
	platform.android_lifecycle.emit("pause")
	platform.android_lifecycle.emit("resume")
	check(panel.session == id and panel.view == "form" and not id in platform.account_cancels, "Pause retains the media server form")
	panel.field = "password"
	panel.input("append", "private-secret")
	check(not JSON.stringify(panel.data).contains("private-secret") and panel.data.password_length == 14, "Secret input returns only its mask length")
	var labels := "\n".join(menu.find_children("*", "Label3D", true, false).map(func(label): return label.text))
	check(not labels.contains("private-secret") and labels.contains("••••"), "Secret does not appear in VR labels")
	panel.action(Accounts.BASE + 6)
	check(platform.account_calls.back()[1] == "save_server", "server test and save uses backend")
	menu.dismiss()
	check(not panel.active() and panel.session == 0, "close explicitly cancels form")
	menu.free()
	platform.free()
	print("in-app account checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures:
		push_error(failure)
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
