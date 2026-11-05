extends SceneTree
const Library := preload("res://scripts/library_menu.gd")
const Surface := preload("res://scripts/xr_menu_compositor.gd")
const Warmup := preload("res://scripts/ui_warmup.gd")
var failures: Array[String] = []


class SourceProbe:
	extends RefCounted
	var calls := 0
	func media_local_browse(_path: String) -> int:
		calls += 1
		return 1
	func media_smb_servers() -> int:
		calls += 1
		return 2
	func media_dlna_servers() -> int:
		calls += 1
		return 3
	func media_dlna_discover() -> int:
		calls += 1
		return 4
	func media_server_request(_body: String) -> int:
		calls += 1
		return 5


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
	var host := RefCounted.new()
	library.platform = host
	library._activate(Library.NAV_BASE + Library.Section.SETTINGS)
	check(
		(
			library.section == Library.Section.SETTINGS
			and library.tab == Library.GENERAL_TAB
			and library._cache_usage == null
		),
		"First settings entry returns before thumbnail statistics are collected"
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
		"Pending cache statistics do not block settings navigation"
	)
	while library._cache_thread and library._cache_thread.is_alive():
		await process_frame
	library._poll_cache_usage()
	check(
		library._cache_usage.y >= 0,
		"Worker publishes video thumbnail statistics after completion"
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
	var synthetic := Library.new()
	synthetic.browse_memory.path = "user://warmup-test/no_store.cfg"
	synthetic.browse_memory.enabled = false
	synthetic.browse_memory.persist = false
	root.add_child(synthetic)
	synthetic.set_process(false)
	synthetic.visible = true
	var sources := SourceProbe.new()
	synthetic.platform = sources
	var emitted: Array = []
	synthetic.setting_changed.connect(func(key, value): emitted.append([key, value]))
	var visited: Array = []
	for destination in Library.NAV_ORDER:
		for variant in ["empty", "populated", "list"]:
			var populated: bool = variant != "empty"
			warmer.prepare_navigation(synthetic, destination, populated, variant == "list")
			check(synthetic.section == destination and not synthetic._buttons.is_empty(), "Every navigation entry has prepared controls")
			if populated:
				check(not synthetic.rows.is_empty(), "Populated navigation variants prepare real row geometry")
		visited.append(destination)
	for required in [Library.Section.RECENT, Library.Section.LOCAL, Library.Section.NETWORK, Library.Section.SETTINGS]:
		check(visited.count(required) == 1, "Each of the four entry types is warmed exactly once")
	check(sources.calls == 0 and synthetic._pending.is_empty() and synthetic.server_browser.pending.is_empty(), "Preparing source UI never invokes local/network browsing or server discovery")
	check(emitted.is_empty() and not synthetic.browse_memory.dirty, "Warmup cannot change settings or directory history")
	synthetic.free()
	warmer.free()
	compositor.free()
	library.free()
	for failure in failures:
		push_error(failure)
	print("Library settings preparation: ", "passed" if failures.is_empty() else failures)
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
