extends SceneTree
const Library := preload("res://scripts/library_menu.gd")
const Player := preload("res://scripts/player_menu.gd")
const Surface := preload("res://scripts/xr_menu_compositor.gd")
var checks := 0
var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func physical_point(surface: Node3D, canvas: Vector3) -> Vector3:
	var pose := Surface.capture_pose(surface.active_menu)
	var local: Vector3 = pose.affine_inverse() * canvas
	var radius: float = surface.active_menu.curve_radius
	if radius <= 0:
		return pose * Vector3(local.x, local.y, 0)
	var centre: Vector2 = surface.surface_rect.get_center()
	var angle := (local.x - centre.x) / radius
	return pose * Vector3(centre.x + sin(angle) * radius, local.y, (1 - cos(angle)) * radius)


func check_closed_companion() -> void:
	var player := Player.new()
	player.state_provider = func():
		return {"has_video": true, "duration_ms": 60000, "source_uri": "file:///synthetic.mp4"}
	root.add_child(player)
	player.set_process(false)
	player.visible = true
	player.refresh()
	var library := Library.new()
	library.browse_memory.enabled = false
	library.browse_memory.persist = false
	root.add_child(library)
	library.set_process(false)
	library.set_playback_browser(true)
	library.visible = true
	library.refresh()
	library.global_transform = Player.switcher_pose(player)
	var surface := Surface.new()
	root.add_child(surface)
	surface.active_menu = player
	surface.menus = [library, player]
	surface.native_supported = true
	player.xr_surface = surface
	library.xr_surface = surface
	surface.test_update_bounds()
	surface.presented = surface._capture_metadata(Surface.capture_pose(player))
	var point := physical_point(surface, library.to_global(Vector3(.3, .2, 0)))
	var origin := player.to_global(Vector3(.1, 0, 1))
	check(
		(
			player.ray_panel_hit(origin, point - origin).is_empty()
			and not library.ray_panel_hit(origin, point - origin).is_empty()
		),
		"Companion panel feedback cannot steal ray routing from a visible library"
	)
	library.dismiss()
	check(
		not player.ray_panel_hit(origin, point - origin).is_empty(),
		"A closing library still blocks until its last displayed pixels are replaced"
	)
	surface.presented = surface._capture_metadata(Surface.capture_pose(player))
	check(
		player.ray_panel_hit(origin, point - origin).is_empty(),
		"Acknowledging the library removal clears its visual blocker"
	)
	point = physical_point(surface, player.to_global(Vector3(.2, Player.BAR_SEEK_Y, 0)))
	player.update_pointer("right_hand", origin, point - origin, true)
	player.test_activate(12)
	check(surface.retains_toolbar(player), "A playback popup retains the displayed toolbar")
	player.position.x += .05
	origin.x += .02
	point = physical_point(surface, player.to_global(Vector3(.2, Player.BAR_SEEK_Y, 0)))
	player.update_pointer("right_hand", origin, point - origin, true)
	var pointer: Dictionary = player.pointer_snapshot().right_hand
	check(
		(
			pointer.dot.visible
			and ((pointer.world_end.distance_to(point)) < .02)
			and ((pointer.world_start.distance_to(origin)) < .0001)
		),
		"A pending playback popup updates both beam endpoints with the hand and displayed toolbar"
	)
	var close: Dictionary = player.controls_snapshot().filter(func(item): return item.target == 107)[0]
	point = physical_point(surface, close.node.global_position)
	player.update_pointer("right_hand", origin, point - origin, true)
	pointer = player.pointer_snapshot().right_hand
	check(
		pointer.dot.visible and ((pointer.world_end.distance_to(point)) < .02),
		"A floating button outside the backdrop still stops the beam during redraw"
	)
	var corner := physical_point(surface, close.node.global_transform * Vector3(.034, .034, 0))
	check(
		player.ray_panel_hit(origin, corner - origin).is_empty(),
		"Transparent corners of floating round buttons do not block the beam"
	)
	player.xr_surface = null
	library.xr_surface = null
	surface.free()
	library.free()
	player.free()


func _run() -> void:
	for radius in [0.0, 1.6]:
		var menu := Library.new()
		menu.browse_memory.enabled = false
		menu.browse_memory.persist = false
		root.add_child(menu)
		menu.set_process(false)
		menu.visible = true
		menu.global_transform = Transform3D(
			Basis(Vector3.UP, .2) * Basis.from_scale(Vector3(.8, .7, 1)), Vector3(0, 1.4, -2)
		)
		menu.curve_radius = radius
		menu.section = Library.Section.SETTINGS
		menu._cache_usage = Vector2i.ZERO
		menu._cache_due_ms = Time.get_ticks_msec() + 600000
		menu.refresh()
		var surface := Surface.new()
		root.add_child(surface)
		surface.active_menu = menu
		surface.menus = [menu]
		surface.native_supported = true
		surface.layer = OpenXRCompositionLayerQuad.new()
		surface.add_child(surface.layer)
		surface.cylinder_layer = OpenXRCompositionLayerCylinder.new()
		surface.add_child(surface.cylinder_layer)
		menu.xr_surface = surface
		surface.test_update_bounds()
		surface.presented = surface._capture_metadata(Surface.capture_pose(menu))
		surface._apply_presented_layer()
		var destination := Library.NAV_BASE + Library.Section.NETWORK
		var button: Dictionary = menu.controls_snapshot().filter(func(item): return item.target == destination)[0]
		var point := physical_point(surface, button.node.global_position)
		var origin := menu.to_global(Vector3(.1, 0, 1))
		check(
			menu.press_pointer("right_hand", origin, point - origin, true),
			"Presented navigation button accepts its click"
		)
		check(
			menu.section == Library.Section.NETWORK, "The click redraws the production library page"
		)
		check(
			(
				not surface.is_layout_presented(menu)
				and surface._can_display_capture(surface.presented)
			),
			"Old pixels remain visible while the new layout awaits GPU acknowledgement"
		)
		for frame in 3:
			origin += menu.global_basis.x.normalized() * .01
			menu.update_pointer("right_hand", origin, point - origin, true)
			var pointer: Dictionary = menu.pointer_snapshot().right_hand
			var endpoint: Vector3 = pointer.world_end
			check(
				pointer.dot.visible and endpoint.distance_to(point) < .02,
				(
					"Pending redraw keeps the beam on the visible panel: radius=%s frame=%d"
					% [radius, frame]
				)
			)
			check(
				(
					menu.ray_hit(origin, point - origin).is_empty()
					and not menu.press_pointer("right_hand", origin, point - origin, true)
				),
				"Panel feedback cannot enable a pending button"
			)
			check(
				(pointer.world_start.distance_to(origin)) < .0001,
				"A pending redraw still tracks the moving hand"
			)
		surface.presented = surface._capture_metadata(Surface.capture_pose(menu))
		check(
			menu.ray_hit(origin, point - origin).get("target") == destination,
			"The acknowledged replacement layout becomes interactive"
		)
		menu._clear_layout()
		check(
			not menu.ray_panel_hit(origin, point - origin).is_empty(),
			"Retired scene nodes cannot remove a panel still visible in the acknowledged image"
		)
		var padding := physical_point(surface, menu.to_global(Vector3(-1.15, .65, 0)))
		check(
			menu.ray_panel_hit(origin, padding - origin).is_empty(),
			"Transparent capture padding does not stop the beam"
		)
		menu.cancel_pointer("right_hand")
		check(
			(
				not menu.pointer_snapshot().right_hand.dot.visible
				and not menu.pointer_snapshot().right_hand.line.visible
			),
			"Tracking loss clears feedback during a redraw"
		)
		surface.surface_rect = surface.surface_rect.grow(.1)
		check(
			menu.ray_panel_hit(origin, point - origin).is_empty(),
			"A hidden incompatible projection cannot leave an invisible ray blocker"
		)
		menu.xr_surface = null
		surface.free()
		menu.free()
	check_closed_companion()
	for failure in failures:
		push_error(failure)
	print("Pointer redraw continuity: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
