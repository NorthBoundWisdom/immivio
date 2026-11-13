extends SceneTree
## Production file-browser rendering with deterministic synthetic data only.
const Library := preload("res://scripts/library_menu.gd")
const Fixture := preload("res://tests/test_library_padding.gd")


class Catalog:
	extends RefCounted

	func list_recent() -> Array:
		var result: Array = []
		for i in 12:
			result.append(
				{
					"uri": "file:///padding/%02d.mp4" % i,
					"title": "[180 VR] 舞台演出 第%d场 — very long video title.mp4" % i,
					"position_ms": i * 61000
				}
			)
		return result


func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	_run.call_deferred()


func _run() -> void:
	var output := OS.get_environment("IMMIVIO_PADDING_DIR")
	if output.is_empty():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	preload("res://scripts/i18n.gd").use("zh")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1400, 900)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.fov = 60
	viewport.add_child(camera)
	var menu := Library.new()
	menu.browse_memory.enabled = false
	menu.browse_memory.persist = false
	camera.add_child(menu)
	menu.set_process(false)
	menu.platform = Fixture.Platform.new()
	menu.catalog = Catalog.new()
	menu._cache_usage = Vector2i.ZERO
	menu.visible = true
	for i in 40:
		menu.sources.local_entries.append(
			{
				"uri": "file:///padding/%02d.mp4" % i,
				"title": "舞台演出 第%d场 — video.mp4" % i,
				"kind": "video"
			}
		)
	menu.sources.local_stack = [{"id": "/padding", "title": "电影"}]
	var pages := [
		["recent", Library.Section.RECENT, false, "", -1],
		["local-grid", Library.Section.LOCAL, false, "", -1],
		["local-list", Library.Section.LOCAL, true, "", -1],
		["network", Library.Section.NETWORK, false, "", -1],
		["network-add", Library.Section.NETWORK, false, "add", -1],
		["settings", Library.Section.SETTINGS, false, "", Library.DISPLAY_TAB]
	]
	for page in pages:
		menu.section = page[1]
		menu.list_view = page[2]
		menu.network.mode = page[3]
		menu.scroll = 0
		if page[4] >= 0:
			menu.tab = page[4]
		menu.refresh()
		await process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(output.path_join(page[0] + ".png"))
	menu.platform = null
	viewport.queue_free()
	await process_frame
	print(
		(
			JSON
			. stringify(
				{
					"state": "passed",
					"pages_rendered": pages.size(),
					"scope":
					"Production desktop GPU layout with synthetic video entries; see test_library_padding.gd for safe-inset and ray-target assertions"
				}
			)
		)
	)
	quit(0)
