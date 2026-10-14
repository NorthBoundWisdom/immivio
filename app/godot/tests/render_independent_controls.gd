extends SceneTree


## Synthetic UI previews; no media, user settings or headset capture.
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output := ProjectSettings.globalize_path("res://../../build/output/independent-previews")
	DirAccess.make_dir_recursive_absolute(output)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1200, 1000)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(0, 0.4, 2)
	camera.size = 1.2
	viewport.add_child(camera)
	var menu := preload("res://scripts/player_menu.gd").new()
	viewport.add_child(menu)
	var state := {
		"has_video": true,
		"geometry": 0,
		"audio_available": true,
		"muted": true,
		"subtitle_options": [{"id": 1, "title": "English", "codec": "subrip"}],
		"subtitle_track": 1,
		"subtitle_palette": 2,
		"title": "Synthetic media",
		"source_uri": "file:///synthetic.mp4"
	}
	menu.state_provider = func(): return state
	var photo := preload("res://scripts/photo_menu.gd").new()
	viewport.add_child(photo)
	photo.state_provider = func():
		return {
			"has_image": true,
			"layout": 2,
			"gallery_focus": -1,
			"wall_rows": 3,
			"gallery_scale": 1.0,
			"gallery_distance": 4.0
		}
	for language in ["en", "zh"]:
		menu.I18n.use(language)
		photo.visible = false
		menu.visible = true
		menu._subtitle_open = true
		menu.refresh()
		camera.position.y = 0.4
		camera.size = 1.2
		await _save(viewport, output.path_join(language + "-captions.png"))
		menu.visible = false
		photo.visible = true
		photo._adjustment = "photo_view"
		photo.refresh()
		camera.position.y = -0.1
		camera.size = 1.65
		await _save(viewport, output.path_join(language + "-wall.png"))
	viewport.queue_free()
	await process_frame
	quit()


func _save(viewport: SubViewport, path: String) -> void:
	for frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(path)
