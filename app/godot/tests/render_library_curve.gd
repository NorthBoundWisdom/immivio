extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output := OS.get_environment("LIBRARY_CURVE_PREVIEW_DIR")
	if output.is_empty():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1440, 1000)
	var main := preload("res://scripts/main.gd").new()
	main.settings_path = output.path_join("settings.cfg")
	var settings := ConfigFile.new()
	settings.set_value("ui", "language", "zh")
	settings.set_value("appearance", "background", "dark")
	settings.save(main.settings_path)
	root.add_child(main)
	main.report_timer.stop()
	var menu: Node3D = main.recent_menu
	menu.session_controls_provider = func():
		return {"follow": false, "passthrough_visible": true, "passthrough": false, "alpha": false}
	menu.device_status.status_provider = func():
		return {"level": 75, "charging": false, "clock24": true}
	menu.device_status.refresh(true)
	menu.section = menu.Section.LOCAL
	menu._local_all_files = true
	menu._local_stack = [{"id": "/storage/emulated/0/Movies", "title": "视频 Movies"}]
	for i in 15:
		menu._local_entries.append(
			{"title": "旅行视频 %02d.mp4" % i, "uri": "file:///Movies/%02d.mp4" % i, "size": 104857600}
		)
	menu.refresh()
	for angle in ["front", "side", "hover"]:
		if angle == "side":
			main.xr_camera.position.x = .55
		if angle == "hover":
			main.xr_camera.position.x = 0
			menu._hover["preview"] = menu.TEMP_PASSTHROUGH
			menu._update_highlights()
		for frame in 5:
			await process_frame
			await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(angle + ".png"))
	FileAccess.open(output.path_join("surface.json"), FileAccess.WRITE).store_string(
		JSON.stringify(main.menu_compositor.snapshot(), "\t")
	)
	main.queue_free()
	await process_frame
	quit()
