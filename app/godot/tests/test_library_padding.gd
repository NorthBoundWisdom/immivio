extends SceneTree
const Library := preload("res://scripts/library_menu.gd")
var failures: Array[String] = []
var checks := 0


class Platform:
	extends RefCounted
	func account_open(_kind, _provider, _id, _defaults) -> int:
		return 1
	func media_file_delete(_raw: String) -> int:
		return 1
	func media_file_rename_prepare(_raw: String) -> int:
		return 1
	func media_file_rename(_raw: String) -> int:
		return 1


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func entries(count: int) -> Array:
	var result: Array = []
	for i in count:
		result.append({"id": str(i), "uri": "file:///padding/%02d.mp4" % i, "title": "Video %02d.mp4" % i, "kind": "video", "can_delete": true, "has_cover": false})
	return result


func verify(menu: Node3D, label: String) -> void:
	var panel: Vector2 = menu._backdrop.mesh.size
	var origin: Vector3 = menu._backdrop.position
	var left: float = origin.x - panel.x * .5
	var right: float = origin.x + panel.x * .5
	var bottom: float = origin.y - panel.y * .5
	var top: float = origin.y + panel.y * .5
	var edge_gaps := [INF, INF, INF, INF]
	for button in menu._buttons:
		if menu._side.is_ancestor_of(button.node) or not button.node.is_visible_in_tree():
			continue
		if button.target in [menu.FOLLOW, menu.TEMP_PASSTHROUGH, menu.CLOSE_MENU]:
			continue
		var at: Vector3 = menu.to_local(button.node.global_position)
		var half: Vector2 = button.node.mesh.size * .5
		var gaps := [at.x - half.x - left, right - at.x - half.x, at.y - half.y - bottom, top - at.y - half.y]
		for edge in 4:
			edge_gaps[edge] = minf(edge_gaps[edge], gaps[edge])
		check(gaps.min() >= menu.PANEL_PADDING - .003, label + " keeps all four safe insets for control " + str(button.target))
	if label.begins_with("Files"):
		check(edge_gaps.max() - edge_gaps.min() <= .003, label + " gives the complete file-browser controls equal padding on all four sides")
	if menu._grid():
		var cards: Array = menu._buttons.filter(func(button): return menu._row_target(button.target) and button.node.is_visible_in_tree())
		if cards.size() >= menu.COLS:
			var first: Vector3 = menu.to_local(cards[0].node.global_position)
			var last: Vector3 = menu.to_local(cards[menu.COLS - 1].node.global_position)
			check(is_equal_approx(first.x - menu.TILE_SIZE.x * .5 - left, right - last.x - menu.TILE_SIZE.x * .5), label + " centres the four-column grid with equal horizontal margins")
	if menu._max_scroll() > 0:
		var track: Dictionary = menu._buttons.filter(func(button): return button.target == menu.SCROLLBAR)[0]
		check(is_equal_approx(track.rect.size.x, .04), label + " preserves the scrollbar's generous ray hit area")
		var at: Vector3 = menu.to_local(track.node.global_position)
		check(is_equal_approx(right - at.x - track.node.mesh.size.x * .5, menu.PANEL_PADDING), label + " gives the visible scrollbar the same edge padding")


func _run() -> void:
	var menu := Library.new()
	menu.browse_memory.enabled = false
	menu.browse_memory.persist = false
	root.add_child(menu)
	menu.visible = true
	menu.set_process(false)
	menu.platform = Platform.new()
	menu._cache_usage = Vector2i.ZERO
	menu._cache_due_ms = Time.get_ticks_msec() + 600000
	menu._local_stack = [{"id": "/padding", "title": "Long folder name for padding"}]
	menu._local_entries = entries(40)
	menu._smb_servers = [{"id": "test", "name": "NAS", "host": "padding.invalid"}]
	menu._smb_server = "test"
	menu._smb_path = "Movies"
	menu._smb_entries = entries(40)
	menu._dlna_server = "test"
	menu._dlna_stack = [{"id": "movies", "title": "Movies"}]
	menu._dlna_entries = entries(40)
	for section in [Library.Section.LOCAL, Library.Section.SMB, Library.Section.DLNA]:
		for list_mode in [false, true]:
			menu.section = section
			menu.list_view = list_mode
			menu.scroll = 0
			menu.refresh()
			verify(menu, "Files %d list=%s" % [section, list_mode])
	menu.section = Library.Section.NETWORK
	for mode in ["", "add", "manage"]:
		menu.network.mode = mode
		menu.refresh()
		verify(menu, "Network " + mode)
	menu.section = Library.Section.SETTINGS
	menu.network.mode = ""
	for tab in menu.SETTING_ORDER:
		menu.tab = tab
		menu.refresh()
		verify(menu, "Settings " + str(tab))
	menu.section = Library.Section.MEDIA_SERVER
	menu.server_browser.server = {"id": "test", "name": "Media library", "provider": "jellyfin"}
	menu.server_browser.servers = [{"id": "test", "name": "Media library", "provider": "jellyfin"}]
	menu.server_browser.entries = entries(30)
	menu.server_browser.total = 30
	menu.server_browser.end_reached = true
	for view in ["servers", "home", "scenes", "filters"]:
		menu.server_browser.view = view
		for list_mode in [false, true]:
			menu.list_view = list_mode
			menu.status = ""
			menu.refresh()
			verify(menu, "Media library " + view + " list=" + str(list_mode))
	menu.server_browser.view = "scenes"
	menu.status = "Loading…"
	menu.refresh()
	verify(menu, "Media library loading")
	menu.section = Library.Section.LOCAL
	menu.file_actions.enabled = true
	menu.file_actions.editing = true
	menu.file_actions.selected = "file:///padding/00.mp4"
	menu.refresh()
	verify(menu, "File selection")
	menu.platform = null
	menu.free()
	for failure in failures:
		push_error(failure)
	print("Library padding: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
