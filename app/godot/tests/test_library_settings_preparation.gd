extends SceneTree
const Library := preload("res://scripts/library_menu.gd")
const Surface := preload("res://scripts/xr_menu_compositor.gd")
const Warmup := preload("res://scripts/ui_warmup.gd")
var failures: Array[String] = []


class CacheHost:
	extends RefCounted
	var gate := Semaphore.new()
	var started := Semaphore.new()

	func photo_cache_usage() -> String:
		started.post()
		gate.wait()
		return '{"files":2,"bytes":10485760}'


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func _run() -> void:
	var library := Library.new()
	root.add_child(library)
	library.set_process(false)
	library.visible = true
	var host := CacheHost.new()
	library.platform = host
	library._activate(Library.NAV_BASE + Library.Section.SETTINGS)
	check(
		(
			library.section == Library.Section.SETTINGS
			and library.tab == Library.GENERAL_TAB
			and library._cache_usage == null
		),
		"First settings entry returns before blocked disk scan completes"
	)
	var row: Dictionary = library.rows.filter(func(item): return item.has("clear_cache"))[0]
	check(
		row.empty and row.detail == library.I18n.t("Loading…"),
		"Pending statistics show a loading value without enabling deletion"
	)
	# The worker remains blocked while a different settings tab is usable.
	library._activate(Library.TAB_BASE + Library.DISPLAY_TAB)
	check(
		library.tab == Library.DISPLAY_TAB and not library.rows.is_empty(),
		"Slow cache scan cannot block settings navigation"
	)
	host.gate.post()
	while library._cache_thread and library._cache_thread.is_alive():
		await process_frame
	library._poll_cache_usage()
	check(
		library._cache_usage.y >= 10485760,
		"Worker publishes Android and local statistics after completion"
	)
	library._activate(Library.TAB_BASE + Library.GENERAL_TAB)
	check(library._cache_thread == null, "Switching tabs reuses the completed count")
	var usage: Vector2i = library._cache_usage
	var warmer := Warmup.new()
	var compositor := Surface.new()
	root.add_child(compositor)
	compositor.active_menu = library
	library.section = Library.Section.LOCAL
	library._cache_usage = usage
	library.refresh()
	compositor._update_bounds()
	var rect := compositor.surface_rect
	var events := []
	library.setting_changed.connect(func(key, value): events.append([key, value]))
	for tab in Warmup.LIBRARY_TABS:
		warmer.prepare_library(library, tab)
		compositor._update_bounds()
		check(not library._buttons.is_empty(), "Warmup prepares real settings controls")
		check(
			compositor.surface_rect == rect,
			"Settings keep the browsing projection from first entry, tab %d" % tab
		)
	check(
		events.is_empty() and library.platform == host,
		"Synthetic page preparation cannot activate settings or replace its platform"
	)
	warmer.free()
	compositor.free()
	library.free()
	for failure in failures:
		push_error(failure)
	print("Library settings preparation: ", "passed" if failures.is_empty() else failures)
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
