extends SceneTree
## Synthetic bilingual previews for settings actions, choices and information.
const Menu := preload("res://scripts/player_menu.gd")
const Library := preload("res://scripts/library_menu.gd")
const Photo := preload("res://scripts/photo_menu.gd")
const Warmup := preload("res://scripts/ui_warmup.gd")

func _initialize() -> void: _run.call_deferred()

func _save(viewport: SubViewport, path: String) -> void:
	for frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(path)

func _run() -> void:
	var output := OS.get_environment("SETTINGS_STYLE_PREVIEW_DIR")
	if output.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(output)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440, 1080); viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.35; camera.position.z = 2; viewport.add_child(camera)
	var menu := Menu.new(); viewport.add_child(menu); menu.position = Vector3.ZERO
	menu.set_process(false); menu.visible = true
	var warmer := Warmup.new()
	var library := Library.new(); viewport.add_child(library); library.position = Vector3.ZERO
	library.set_process(false); library._cache_usage = Vector2i(2, 1024)
	var photo := Photo.new(); viewport.add_child(photo); photo.position = Vector3.ZERO; photo.set_process(false)
	photo.state_provider = func(): return {"has_image": true, "count": 1, "geometry": 0,
		"depth_available": true, "depth_strength": 1.0, "can_background": true}
	for language in ["en", "zh"]:
		menu.I18n.use(language); library.visible = false; photo.visible = false; menu.visible = true
		camera.size = 1.35; camera.position.x = 0
		for page in ["screen", "playback", "sync", "queue_populated", "info_available", "color0", "stereo", "audio"]:
			warmer.prepare(menu, page)
			if page == "audio":
				for id in range(2, 8):
					menu._state.audio_options.append({"id": id, "value": id, "label": "Synthetic audio " + str(id)})
				menu._draw()
			await _save(viewport, output.path_join(language + "-" + page + ".png"))
		menu.visible = false; library.visible = true
		camera.size = 1.75; camera.position.x = -0.15
		library.section = Library.Section.SETTINGS
		for tab in [Library.GENERAL_TAB, Library.VIDEO_TAB, Library.ABOUT_TAB]:
			library.tab = tab; library.refresh()
			await _save(viewport, output.path_join(language + "-library-" + str(tab) + ".png"))
		library.visible = false; photo.visible = true; photo.section = 1; photo.refresh()
		camera.size = 1.35; camera.position.x = 0
		await _save(viewport, output.path_join(language + "-photo.png"))
	warmer.free(); viewport.queue_free(); await process_frame
	quit()
