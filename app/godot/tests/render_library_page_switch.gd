extends SceneTree
## Real GPU regression for a continuous window while its right-hand page changes.
const Library := preload("res://scripts/library_menu.gd")
const Surface := preload("res://scripts/xr_menu_compositor.gd")
var failures: Array[String] = []
var coverage: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func window_pixels(picture: Image) -> int:
	var count := 0
	for y in range(0, picture.get_height(), 4):
		for x in range(0, picture.get_width(), 4):
			var colour := picture.get_pixel(x, y)
			if maxf(colour.r, maxf(colour.g, colour.b)) > .03:
				count += 1
	return count


func _run() -> void:
	var target := SubViewport.new()
	target.size = Vector2i(720, 540)
	target.own_world_3d = true
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(target)
	var head := Camera3D.new()
	target.add_child(head)
	head.current = true
	head.environment = Environment.new()
	head.environment.background_mode = Environment.BG_COLOR
	head.environment.background_color = Color.BLACK
	var library := Library.new()
	library.browse_memory.path = "user://ui_page_switch/no_store.cfg"
	library.browse_memory.enabled = false
	library.browse_memory.persist = false
	target.add_child(library)
	library.set_process(false)
	library._cache_usage = Vector2i.ZERO
	library._cache_due_ms = Time.get_ticks_msec() + 600000
	library.position = Vector3(0, 0, -2)
	library.curve_radius = 2
	library.section = Library.Section.SETTINGS
	library.tab = Library.GENERAL_TAB
	library.visible = true
	library.refresh()
	var surface := Surface.new()
	target.add_child(surface)
	surface.configure([library], head, false)
	surface.set_process(false)
	for i in 4:
		surface._process(0)
		await process_frame
		await RenderingServer.frame_post_draw
	var initial := target.get_texture().get_image()
	var baseline := window_pixels(initial)
	if baseline < 1000:
		failures.append("Initial production settings window must actually render")
	var rect: Rect2 = surface.surface_rect
	var output := OS.get_environment("IMMIVIO_PAGE_SWITCH_DIR")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		initial.save_png(output.path_join("settings.png"))
	for destination in [Library.Section.NETWORK, Library.Section.SETTINGS, Library.Section.NETWORK, Library.Section.SETTINGS]:
		library._activate(Library.NAV_BASE + destination)
		surface._process(0)
		if surface.surface_rect != rect:
			failures.append("Library pages must retain the common capture projection")
		if not surface.curved_mesh.visible:
			failures.append("Page navigation must not hide the complete library window")
		for frame in 3:
			await process_frame
			await RenderingServer.frame_post_draw
			var picture := target.get_texture().get_image()
			var visible := window_pixels(picture)
			coverage.append(visible)
			if visible < baseline * .8:
				failures.append("A navigation frame blanked the window: %d pixels" % visible)
			if not output.is_empty():
				picture.save_png(output.path_join("switch-%02d.png" % coverage.size()))
			surface._process(0)
	print(JSON.stringify({"state": "passed" if failures.is_empty() else "failed", "failures": failures,
		"baseline_window_pixels": baseline, "frame_window_pixels": coverage,
		"scope": "Real GPU production library settings/network switching; native XR acknowledgement covered separately"}))
	target.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
