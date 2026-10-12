extends SceneTree
const Menu := preload("res://scripts/player_menu.gd")
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	var output := OS.get_environment("PLAYBACK_TOOLBAR_PREVIEW_DIR")
	if output.is_empty():quit(1);return
	DirAccess.make_dir_recursive_absolute(output)
	var viewport := SubViewport.new();viewport.size = Vector2i(1600,900);viewport.own_world_3d = true;viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new();camera.projection = Camera3D.PROJECTION_ORTHOGONAL;camera.size = .90;camera.position = Vector3(0,.18,1);viewport.add_child(camera)
	var state := {"has_video":true,"playing":true,"playback_state":"playing","duration_ms":600000,"position_ms":123456,
		"geometry":0,"title":"旅行记录 · Travel 2026","audio_available":true,"has_previous_video":true,"has_next_video":true,"ai_enabled":false,
		"bookmark_scope":"preview","bookmark_ready":true,"bookmark_seekable":true,"bookmarks":[]}
	var menu := Menu.new();menu.state_provider = func():return state
	viewport.add_child(menu);menu.position = Vector3.ZERO;menu.set_process(false)
	menu.toggle()
	menu.device_status.status_provider = func():return {"level":75,"charging":false,"clock24":true}
	menu.device_status.clock_provider = func():return {"hour":21,"minute":30}
	menu.device_status.refresh(true)
	for language in ["zh","en"]:
		menu.I18n.use(language)
		for page in ["bar","bookmarks","volume"]:
			state.bookmarks = [{"id":"a","position_ms":60000},{"id":"b","position_ms":240000}] if page=="bookmarks" else []
			state.bookmark_undo = page=="bookmarks"
			menu.visible = true;menu.section = 0;menu._volume_open = page=="volume";menu.refresh()
			for frame in 3:await process_frame;await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(output.path_join(language+"-"+page+".png"))
	menu.queue_free();viewport.queue_free();await process_frame;quit()
