extends SceneTree
const Providers := preload("res://scripts/provider_icons.gd")


func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	call_deferred("_run")


func _run() -> void:
	for provider in ["emby", "jellyfin", "plex", "xbvr", "smb", "dlna", "local"]:
		assert(
			preload("res://scripts/menu_icons.gd").texture(Providers.key(provider)).get_width() > 0
		)
	assert(Providers.key(" PLEX ") == Providers.key("plex"))
	assert(Providers.key("115") == "server")
	var menu := preload("res://scripts/library_menu.gd").new()
	root.add_child(menu)
	var platform := preload("res://tests/test_media_servers.gd").Platform.new()
	menu.attach_platform(platform)
	var browser: RefCounted = menu.server_browser
	browser.server = {"id": "plex", "provider": "plex"}
	browser.capabilities = {"home_layout": "libraries"}
	browser.servers = [{"id": "plex", "provider": "plex", "name": "Plex"}]
	browser.view = "servers"
	assert(browser.rows()[0].icon == Providers.key("plex"))
	var home := {
		"capabilities": {"home_layout": "libraries"},
		"library_id": "1",
		"libraries": [{"id": "2", "title": "TV", "collection_type": "tvshows"}]
	}
	browser.open_home()
	platform.answer(platform.next, home.duplicate(true))
	assert(browser.view == "libraries")
	browser.open_home()
	platform.answer(platform.next, home.duplicate(true))
	assert(browser.view == "libraries")
	var row: Dictionary = browser.rows()[0]
	browser.choose(row)
	assert(
		(
			browser.query.mode == "library"
			and browser.query.collection_type == "tvshows"
			and browser.library_id == "2"
		)
	)
	browser.cancel()
	menu.queue_free()
	await process_frame
	await process_frame
	platform.free()
	preload("res://tests/support/test_result.gd").finish(self, 0)
