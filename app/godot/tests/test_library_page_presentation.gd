extends SceneTree
const Library := preload("res://scripts/library_menu.gd")
const Surface := preload("res://scripts/xr_menu_compositor.gd")
var failures: Array[String] = []
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func _run() -> void:
	var library := Library.new()
	library.browse_memory.enabled = false
	library.browse_memory.persist = false
	root.add_child(library)
	library.set_process(false)
	library.visible = true
	library.position = Vector3(0, 1.4, -1.6)
	library._cache_usage = Vector2i.ZERO
	library._cache_due_ms = Time.get_ticks_msec() + 600000
	var surface := Surface.new()
	root.add_child(surface)
	surface.active_menu = library
	surface.menus = [library]
	surface.native_supported = true
	surface.layer = OpenXRCompositionLayerQuad.new()
	surface.add_child(surface.layer)
	surface.cylinder_layer = OpenXRCompositionLayerCylinder.new()
	surface.add_child(surface.cylinder_layer)
	for radius in [0.0, 1.6]:
		library.curve_radius = radius
		library.test_activate(Library.NAV_BASE + Library.Section.SETTINGS)
		surface.test_update_bounds()
		var rect: Rect2 = surface.surface_rect
		surface.presented = surface._capture_metadata(Surface.capture_pose(library))
		for destination in [
			Library.Section.NETWORK,
			Library.Section.SETTINGS,
			Library.Section.NETWORK,
			Library.Section.SETTINGS
		]:
			library.test_activate(Library.NAV_BASE + destination)
			surface.test_update_bounds()
			check(
				surface.surface_rect == rect,
				"Settings and network sources share their physical projection"
			)
			check(
				not surface._matches_capture(surface.presented),
				"New page awaits its own capture acknowledgement"
			)
			check(
				surface._can_display_capture(surface.presented),
				"An unchanged window retains its preceding image during the redraw"
			)
			check(
				not surface.is_layout_presented(library),
				"Retaining the window cannot activate unacknowledged controls"
			)
			surface._apply_presented_layer()
			check(
				(
					surface.layer.quad_size == rect.size
					if radius == 0
					else surface.cylinder_layer.central_angle > .001
				),
				"Native quad and cylinder remain visible across page navigation"
			)
			surface.presented = surface._capture_metadata(Surface.capture_pose(library))
			check(
				surface.is_layout_presented(library),
				"Acknowledging the new capture enables its own controls"
			)
		library.test_activate(Library.NAV_BASE + Library.Section.NETWORK)
		var pose: Transform3D = library.global_transform
		library.position.y += .1
		check(
			not surface._can_display_capture(surface.presented),
			"A new page cannot retain pixels at a different placement"
		)
		library.global_transform = pose
		surface.surface_rect = rect.grow(.1)
		check(
			not surface._can_display_capture(surface.presented),
			"A different capture projection must await matching pixels"
		)
		surface.surface_rect = rect
		library.curve_radius += .2
		check(
			not surface._can_display_capture(surface.presented),
			"A different curve cannot reuse the previous page image"
		)
		library.curve_radius = radius
		var extra := Library.new()
		root.add_child(extra)
		extra.visible = true
		surface.menus.append(extra)
		check(
			not surface._can_display_capture(surface.presented),
			"A different set of visible menus still requires a fresh capture"
		)
		surface.menus.erase(extra)
		extra.free()
	surface.free()
	library.free()
	for failure in failures:
		push_error(failure)
	print("Library page presentation: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
