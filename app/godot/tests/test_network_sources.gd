extends SceneTree
const Library := preload("res://scripts/library_menu.gd")
var checks := 0
var failures: Array[String] = []


class Platform:
	extends "res://tests/test_library_menu.gd".FakePlatform
	var requests := {}
	var cancellations: Array = []

	func media_server_request(raw: String) -> int:
		var body: Dictionary = JSON.parse_string(raw)
		next += 1
		var id := next
		requests[id] = body
		var result := {"state": "ready", "generation": body.generation, "server_id": body.server_id}
		if body.action == "servers":
			result.servers = [{"id": "jellyfin", "name": "NAS", "provider": "jellyfin"}]
		elif body.action == "home":
			result.recent = []
		(func(): media_list.emit(id, JSON.stringify(result))).call_deferred()
		return id

	func media_server_cancel(id: int) -> void:
		cancellations.append(id)

	func media_dlna_save(_raw: String) -> int:
		return media_dlna_discover()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func settle() -> void:
	await process_frame
	await process_frame


func find(menu: Node3D, key: String) -> Dictionary:
	for row in menu.rows:
		if row.has(key):
			return row
	return {}


func _run() -> void:
	var menu := Library.new()
	root.add_child(menu)
	menu.set_process(false)
	var platform := Platform.new()
	menu.attach_platform(platform)
	menu.visible = true
	menu._activate(Library.NAV_BASE + Library.Section.NETWORK)
	menu._activate(menu.network.ADD)
	await settle()
	check(
		menu.network.mode == "add" and menu.section == Library.Section.NETWORK,
		"Late background source listings must not leave the add-source chooser"
	)
	menu._activate(Library.NAV_BASE + Library.Section.NETWORK)
	await settle()
	var navigation: Array = menu._buttons.filter(
		func(button):
			return (
				button.target >= Library.NAV_BASE
				and button.target < Library.NAV_BASE + Library.NAV.size()
			)
	)
	check(navigation.size() == 4, "Only four primary navigation entries are rendered")
	check(
		not navigation.any(
			func(button):
				return (
					button.target
					in [
						Library.NAV_BASE + Library.Section.SMB,
						Library.NAV_BASE + Library.Section.DLNA,
						Library.NAV_BASE + Library.Section.MEDIA_SERVER
					]
				),
		),
		"Protocol-specific entries are absent from the sidebar"
	)
	check(
		(
			menu.rows.filter(func(row): return not row.get("group", false)).size() == 4
			and menu.rows.filter(func(row): return row.get("group", false)).size() == 2
			and menu.rows[0].get("group", false)
			and not find(menu, "smb_server").is_empty()
			and not find(menu, "dlna_server").is_empty()
			and not find(menu, "server_account").is_empty()
		),
		"Saved and discovered sources share one list under My sources / Found headings"
	)
	var smb := find(menu, "smb_server")
	var dlna := find(menu, "dlna_server")
	var account := find(menu, "server_account")
	check(
		menu._row_identity(smb) != menu._row_identity(account),
		"Identically named sources retain distinct browse identities"
	)
	menu.sources.smb_found.append({"name": "Duplicate NAS", "host": "192.168.1.9"})
	menu.refresh()
	check(
		menu.rows.filter(func(row): return not row.get("group", false)).size() == 4,
		"Discovery does not duplicate a saved SMB host"
	)
	menu._choose(smb)
	await settle()
	check(
		menu.section == Library.Section.SMB and menu.rows[0].title == "Video",
		"Selecting a shared folder source opens its shares"
	)
	check(
		menu._buttons.any(
			func(button):
				return (
					button.target == Library.NAV_BASE + Library.Section.NETWORK
					and button.base_color == menu.SELECTED
				),
		),
		"Network media stays selected inside a backend browser"
	)
	menu._choose(menu.rows[0])
	await settle()
	check(
		menu.sources.smb_path == "Video" and menu.rows[0].title == "8k.mp4",
		"Shared-folder browsing still resolves playable files"
	)
	menu.network.open()
	await settle()
	menu._choose(find(menu, "smb_server"))
	await settle()
	check(
		menu.sources.smb_path == "Video" and menu.rows[0].title == "8k.mp4",
		"Reopening a source restores its last folder"
	)
	menu._activate(Library.BACK)
	await settle()
	menu._activate(Library.BACK)
	await settle()
	check(
		menu.section == Library.Section.NETWORK,
		"Back from a source root returns to the unified list"
	)
	menu._choose(dlna)
	await settle()
	menu._choose(menu.rows[0])
	await settle()
	check(
		menu.sources.dlna_stack.size() == 1 and menu.rows[0].title == "Show",
		"DLNA containers remain browsable from the unified entry"
	)
	menu.network.open()
	await settle()
	menu._choose(find(menu, "dlna_server"))
	await settle()
	check(
		menu.sources.dlna_stack.size() == 1 and menu.rows[0].title == "Show",
		"Reopening DLNA retains its folder stack"
	)
	menu.network.open()
	await settle()
	menu._choose(account)
	await settle()
	check(
		(
			menu.section == Library.Section.MEDIA_SERVER
			and menu.server_browser.server.id == "jellyfin"
			and menu.server_browser.view == "home"
		),
		"Account sources open their existing media-server browser"
	)
	menu.server_browser.view = "scenes"
	menu.server_browser.query.q = "remember"
	menu.network.open()
	await settle()
	check(
		menu.server_browser.view == "scenes" and menu.server_browser.query.q == "remember",
		"Refreshing the hub does not reset the account browser"
	)
	menu._choose(find(menu, "server_account"))
	check(
		menu.server_browser.view == "scenes" and menu.server_browser.query.q == "remember",
		"Returning to the account source restores its browsing context"
	)
	menu.server_browser.view = "servers"
	menu.server_browser.back()
	await settle()
	check(
		menu.section == Library.Section.NETWORK,
		"Account management root can return to Network media"
	)
	for type in [Library.Section.SMB, Library.Section.DLNA, Library.Section.MEDIA_SERVER]:
		menu.network.open()
		menu._activate(menu.network.ADD)
		check(
			menu.rows.size() == 7 and menu.network.mode == "add",
			"Shared folders, DLNA and five server providers are sibling choices"
		)
		menu._choose(menu.rows.filter(func(row): return row.network_type == type)[0])
		check(
			(
				menu.section == type
				and (
					menu.account_panel.active()
					if type == Library.Section.MEDIA_SERVER
					else not menu.editor.is_empty()
				)
			),
			"Each source type opens its existing setup flow"
		)
		menu._activate(
			menu.account_panel.BASE if type == Library.Section.MEDIA_SERVER else Library.CANCEL
		)
		check(
			(
				menu.section == Library.Section.NETWORK
				and not menu.account_panel.active()
				and menu.editor.is_empty()
			),
			"Cancelling source setup returns to the unified list"
		)
	for provider in menu.account_panel.PROVIDERS:
		menu.network.open()
		menu._activate(menu.network.ADD)
		check(
			not menu.rows.any(
				func(row):
					return (
						row.get("network_type") == Library.Section.MEDIA_SERVER
						and not row.has("network_provider")
					),
			),
			"No media-server parent entry remains in the add-source chooser"
		)
		menu._choose(menu.rows.filter(func(row): return row.get("network_provider") == provider)[0])
		check(
			(
				menu.account_panel.view == "form"
				and menu.account_panel.provider == provider
				and platform.account_calls.back()[2] == provider
			),
			"Each provider opens its own setup form directly"
		)
		menu.network.open()
		menu._activate(menu.network.MANAGE)
		menu._choose(menu.rows.filter(func(row): return row.get("network_provider") == provider)[0])
		check(
			(
				menu.account_panel.view == "accounts"
				and menu.account_panel.items.all(func(item): return item.provider == provider)
			),
			"Provider management lists only the chosen provider's accounts"
		)
		menu._activate(menu.account_panel.BASE + 22)
		check(
			menu.account_panel.view == "form" and menu.account_panel.provider == provider,
			"Adding from provider management skips the removed chooser"
		)
	menu.network.open()
	menu._activate(menu.network.ADD)
	menu._activate(menu.network.DISCOVER)
	check(
		menu.account_panel.view == "discover" and menu.account_panel.kind == "server",
		"Network discovery remains available from the flat chooser"
	)
	menu._activate(menu.account_panel.BASE + 22)
	check(
		(
			menu.section == Library.Section.NETWORK
			and menu.network.mode == "add"
			and menu.rows.size() == 7
		),
		"Manual addition from discovery returns to the flat chooser"
	)
	for language in ["en", "zh", "zh_Hant", "ja"]:
		menu.I18n.use(language)
		menu.refresh()
		for index in 2:
			var label: Label3D = (
				menu
				. _buttons
				. filter(func(button): return button.target == Library.ROW_BASE + index)[0]
				. node
				. get_child(0)
			)
			check(
				label.text == menu.rows[index].title and label.text.ends_with(")"),
				"Protocol titles retain complete parentheses in each language"
			)
	menu.I18n.use("en")
	for type in [Library.Section.SMB, Library.Section.DLNA]:
		menu.network.open()
		menu._activate(menu.network.ADD)
		menu._choose(menu.rows.filter(func(row): return row.network_type == type)[0])
		menu.editor.host = "192.168.1.30"
		menu._activate(Library.SAVE)
		await settle()
		check(
			menu.section == Library.Section.NETWORK and menu.editor.is_empty(),
			"Saving a network source returns to the unified list"
		)
	menu.network.open()
	menu._activate(menu.network.ADD)
	menu._choose(
		menu.rows.filter(func(row): return row.network_type == Library.Section.MEDIA_SERVER)[0]
	)
	menu.account_panel.start("server", "jellyfin")
	platform.account_sessions[menu.account_panel.session].state = "done"
	menu.account_panel.poll()
	await settle()
	check(
		menu.section == Library.Section.NETWORK and not menu.account_panel.active(),
		"Completed account setup returns to the unified list"
	)
	menu.network.open()
	menu._activate(menu.network.MANAGE)
	menu._choose(menu.rows[0])
	await settle()
	check(
		menu.section == Library.Section.SMB and menu.sources.smb_server.is_empty(),
		"Managing shared folders opens the saved-source list"
	)
	menu.network.open()
	menu._activate(menu.network.ADD)
	menu._activate(Library.BACK)
	check(
		menu.section == Library.Section.NETWORK and menu.network.mode.is_empty(),
		"Cancelling the type chooser restores the unified list"
	)
	# A late listing from the previous section cannot replace current rows/status.
	menu.sources.request("dlna_discover", 9000)
	menu._activate(Library.NAV_BASE + Library.Section.SETTINGS)
	menu.status = "current"
	menu._on_media_list(
		9000, JSON.stringify({"state": "ready", "servers": [{"id": "late", "name": "Late"}]})
	)
	check(
		(
			menu.section == Library.Section.SETTINGS
			and menu.status == "current"
			and not menu.sources.dlna_servers.any(func(server): return server.id == "late")
		),
		"Late network results cannot redraw another section"
	)
	await settle()
	menu.free()
	platform.free()
	for failure in failures:
		push_error(failure)
	print("Network sources: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
