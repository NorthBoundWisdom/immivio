extends SceneTree
const Menu := preload("res://scripts/player_menu.gd")
const Warmup := preload("res://scripts/ui_warmup.gd")
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	var output := OS.get_environment("IPD_SETTINGS_PREVIEW_DIR")
	if output.is_empty():quit(1);return
	DirAccess.make_dir_recursive_absolute(output)
	var viewport := SubViewport.new();viewport.size = Vector2i(1600,1100);viewport.own_world_3d = true;viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera := Camera3D.new();camera.projection = Camera3D.PROJECTION_ORTHOGONAL;camera.size = 1.10;camera.position = Vector3(0,.05,1);viewport.add_child(camera)
	var menu := Menu.new();viewport.add_child(menu);menu.position = Vector3.ZERO;menu.visible = true;menu.set_process(false)
	var warmer := Warmup.new()
	for language in ["zh","en"]:
		menu.I18n.use(language)
		for page in ["stereo","ipd_mono","sync","queue"]:
			warmer.prepare(menu,page)
			menu._state["stereo_horizontal"] = 1.25;menu._state["stereo_vertical"] = -.15;menu._refresh_adjustments()
			for frame in 3:await process_frame;await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(output.path_join(language+"-"+page+"-synthetic.png"))
	warmer.free();menu.queue_free();viewport.queue_free();await process_frame;quit()
