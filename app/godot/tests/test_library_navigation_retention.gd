extends SceneTree
const Library := preload("res://scripts/library_menu.gd")
var failures: Array[String] = []
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func navigation_ids(menu: Node3D) -> Array:
	var result: Array = []
	for button in menu._buttons:
		if button.target >= menu.NAV_BASE and button.target < menu.NAV_BASE + menu.NAV.size():
			result.append(button.node.get_instance_id())
	return result


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func _run() -> void:
	var menu := Library.new()
	menu.section = Library.Section.SETTINGS
	menu.tab = Library.ABOUT_TAB
	menu._about_page = 3
	root.add_child(menu)
	menu.set_process(false)
	menu.toggle()
	var original := navigation_ids(menu)
	var first_title: String = menu.rows[menu._first_line()].title
	menu.stick_scroll(-1, 0.5)
	check(
		menu.scroll > 0 and menu.rows[menu._first_line()].title != first_title,
		"License content actually scrolls"
	)
	check(navigation_ids(menu) == original, "License scrolling retains all left navigation nodes")
	menu.stick_scroll(1, 0.5)
	check(
		menu.scroll == 0 and navigation_ids(menu) == original,
		"Scrolling back does not rebuild left navigation"
	)
	for tab in menu.SETTING_TABS.size():
		menu._about_page = 0
		menu.tab = tab
		menu.refresh()
		check(navigation_ids(menu) == original, "Settings tabs retain unchanged left navigation")
		check(
			not menu._buttons.any(func(button): return button.target in [82, 83]),
			"Restart and Close controls are absent on every settings tab"
		)
	menu.section = Library.Section.LOCAL
	menu.refresh()
	check(
		navigation_ids(menu) == original,
		"Changing section reuses navigation and updates only selection"
	)
	var selected := menu._buttons.filter(
		func(button): return button.target == menu.NAV_BASE + menu.Section.LOCAL
	)
	check(
		selected.size() == 1 and selected[0].base_color == menu.SELECTED,
		"New section is visibly selected"
	)
	for destination in menu.NAV_ORDER:
		menu._activate(menu.NAV_BASE + destination)
		check(
			navigation_ids(menu) == original,
			"All four entry switches preserve navigation instances"
		)
		var active := menu._buttons.filter(
			func(button):
				return (
					button.target >= menu.NAV_BASE
					and button.target < menu.NAV_BASE + menu.NAV.size()
					and button.base_color == menu.SELECTED
				)
		)
		check(
			active.size() == 1 and active[0].target == menu.NAV_BASE + destination,
			"Exactly the current entry is highlighted"
		)
	menu.free()
	for failure in failures:
		push_error(failure)
	print("Library navigation checks=", checks, " failures=", failures.size())
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
