extends SceneTree
const Browser := preload("res://scripts/media_server_browser.gd")
const Menu := preload("res://scripts/library_menu.gd")


func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	call_deferred("_run")


func _run() -> void:
	var menu := Menu.new()
	root.add_child(menu)
	var platform := preload("res://tests/test_media_servers.gd").Platform.new()
	menu.attach_platform(platform)
	menu.catalog = preload("res://scripts/recent_files.gd").new()
	var legacy := "medialib://srv/scene/movie"
	var first := legacy + "?source=source%2FA"
	var second := legacy + "?source=source%2FB"
	for uri in [legacy, first, second, "medialib://other/scene/movie?source=foreign"]:
		assert(menu.catalog.opened(uri, uri, false))
		menu.catalog.progress(uri, 12000, 120000, false)
	var browser: RefCounted = menu.server_browser
	browser.server = {"id": "srv", "provider": "emby"}
	var resumes: Array = browser._local_resume()
	assert(resumes.size() == 3)
	for item in resumes:
		assert(item.id == "movie", "A source query must never become part of scene_id")
	var version: Dictionary = resumes.filter(func(item): return item.uri == first)[0]
	assert(version.source_id == "source/A")
	var unique: Array = []
	browser._append_unique(unique, resumes)
	assert(
		unique.size() == 3,
		"Versions retain separate identities before the existing one-row home limit"
	)
	browser.choose({"scene": version})
	assert(platform.requests[platform.next].scene_id == "movie")
	assert(platform.requests[platform.next].source_id == "source/A")
	var versions := [
		{
			"id": "movie",
			"uri": first,
			"source_id": "source/A",
			"title": "Version A",
			"version_name": "A"
		},
		{
			"id": "movie",
			"uri": second,
			"source_id": "source/B",
			"title": "Version B",
			"version_name": "B"
		}
	]
	platform.answer(
		platform.next,
		{
			"detail":
			{"id": "movie", "uri": legacy, "title": "Movie", "position_ms": 0, "versions": versions}
		}
	)
	var action: Dictionary = browser.rows().filter(func(row): return row.has("play_scene"))[0]
	assert(
		action.play_scene.uri == first, "Details from a version resume must preselect that version"
	)
	browser.choose(action)
	assert(browser.selection.uri == first and browser.selection.start_ms == -1)
	# A removed version renders its actual source-unavailable status through I18n.t.
	menu.section = Menu.Section.MEDIA_SERVER
	menu.visible = true
	browser.choose({"scene": version})
	platform.answer(
		platform.next, {"detail": {"id": "movie", "uri": legacy, "title": "Movie", "versions": []}}
	)
	assert(menu.status == "Original stream unavailable")
	var i18n := preload("res://scripts/i18n.gd")
	var translations := {"zh": "原始媒体流不可用", "zh_Hant": "無法使用原始串流", "ja": "元のストリームを利用できません"}
	for language in translations:
		i18n.use(language)
		menu.refresh()
		assert(
			menu.text_snapshot().contains(translations[language]),
			"The displayed status is translated in " + language
		)
		assert(not menu.text_snapshot().contains("Original stream unavailable"))
	i18n.use("en")
	browser.cancel()
	menu.free()
	platform.free()
	preload("res://tests/support/test_result.gd").finish(self, 0)
