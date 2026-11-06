extends RefCounted
## Invoked only by the Debug/DUMP receiver. Exercises real Android IO and rendered XR menus.
const BASE := "/storage/emulated/0/Movies/ImmivioAcceptance20261024"
var checks: Array = []


func check(value: bool, title: String, details: Variant = null) -> void:
	checks.append({"passed": value, "title": title, "details": details})


func settle(host: Node, seconds: float = 0.4) -> void:
	host._menu_touched_ms = Time.get_ticks_msec()
	await host.get_tree().create_timer(seconds).timeout


func presented(menu: Node3D) -> bool:
	for i in 120:
		menu.get_parent()._menu_touched_ms = Time.get_ticks_msec()
		if (
			not menu.xr_surface
			or not menu.xr_surface.native_supported
			or menu.xr_surface.is_layout_presented(menu)
		):
			return true
		await menu.get_tree().process_frame
	return false


func ray_for(menu: Node3D, point: Vector3) -> Array:
	var world: Vector3 = menu.to_global(point)
	var normal: Vector3 = menu.global_basis.z.normalized()
	var compositor: Node3D = menu.xr_surface
	if compositor and compositor.native_supported and compositor.active_menu:
		var pose: Transform3D = compositor.capture_pose(compositor.active_menu)
		var local: Vector3 = pose.affine_inverse() * world
		var radius: float = compositor.active_menu.curve_radius
		if radius > 0:
			var centre: Vector2 = compositor.surface_rect.get_center()
			var angle := (local.x - centre.x) / radius
			world = (
				pose * Vector3(centre.x + sin(angle) * radius, local.y, radius * (1.0 - cos(angle)))
			)
			normal = pose.basis * Vector3(-sin(angle), 0, cos(angle))
	return [world + normal * 0.5, -normal]


func tap(menu: Node3D, target: int) -> bool:
	if not await presented(menu):
		return false
	for button in menu._buttons:
		if button.target != target or not button.enabled or not button.node.visible:
			continue
		var ray := ray_for(menu, menu.to_local(button.node.global_position))
		if int(menu.ray_hit(ray[0], ray[1]).get("target", -1)) != target:
			return false
		if not menu.press_pointer("left_hand", ray[0], ray[1], true):
			return false
		menu.release_pointer("left_hand", ray[0], ray[1], true)
		return true
	return false


func choice_target(menu: Node3D, key: String, kind: String, value: Variant = null) -> int:
	for target in menu.choices.targets:
		var item: Dictionary = menu.choices.targets[target]
		if (
			item.get("key") == key
			and item.get("kind") == kind
			and (kind == "open" or menu.choices.same(item.get("value"), value))
		):
			return int(target)
	return -1


# A separate capture owner keeps live controller motion from changing injected rays.
func held_choice_tap(menu: Node3D, target: int) -> bool:
	if target < 0 or not await presented(menu):
		return false
	for button in menu._buttons:
		if button.target != target or not button.enabled:
			continue
		var radial := ray_for(menu, menu.to_local(button.node.global_position))
		var point: Vector3 = radial[0] + radial[1] * 0.5
		var pose: Transform3D = menu.xr_surface.capture_pose(menu)
		var origin := pose * Vector3(-0.25, -0.45, 1.5)
		var direction := (point - origin).normalized()
		if int(menu.ray_hit(origin, direction).get("target", -1)) != target:
			return false
		if not menu.press_pointer("diagnostic_choice", origin, direction, true):
			return false
		for frame in 4:
			await menu.get_tree().process_frame
			menu.get_parent()._menu_touched_ms = Time.get_ticks_msec()
			menu.update_pointer("diagnostic_choice", origin, direction, true)
		var valid: bool = (
			not menu.choices.capture.is_empty() and not menu.choices.capture.get("moved", false)
		)
		menu.release_pointer("diagnostic_choice", origin, direction, true)
		menu.cancel_pointer("diagnostic_choice")
		return valid
	return false


func navigation_ids(menu: Node3D) -> Array:
	var ids: Array = []
	for button in menu._buttons:
		if button.target >= menu.NAV_BASE and button.target < menu.NAV_BASE + menu.NAV.size():
			ids.append(button.node.get_instance_id())
	return ids


func choose(menu: Node3D, key: String, value: Variant) -> bool:
	for target in menu.choices.targets:
		var item: Dictionary = menu.choices.targets[target]
		if item.key == key and item.kind == "open":
			if not await tap(menu, target):
				return false
			break
	for target in menu.choices.targets:
		var item: Dictionary = menu.choices.targets[target]
		if item.key == key and item.kind == "choose" and menu.choices.same(item.value, value):
			return await tap(menu, target)
	return false


func slide(menu: Node3D, key: String, fraction: float) -> bool:
	if not await presented(menu):
		return false
	for target in menu.choices.sliders:
		if menu.choices.targets[target].key != key:
			continue
		var slider: Dictionary = menu.choices.sliders[target]
		var local: Vector3 = menu.to_local(
			slider.node.to_global(
				Vector3(slider.left + slider.width * fraction, slider.knob.position.y, 0.01)
			)
		)
		var ray := ray_for(menu, local)
		if not menu.press_pointer("left_hand", ray[0], ray[1], true):
			return false
		menu.release_pointer("left_hand", ray[0], ray[1], true)
		return true
	return false


func open_folder(host: Node) -> void:
	var menu: Node3D = host.recent_menu
	host._show_recent_menu(true)
	menu.section = menu.Section.LOCAL
	menu._local_stack = [
		{"id": "/storage/emulated/0", "title": "Internal storage"},
		{"id": "/storage/emulated/0/Movies", "title": "Movies"},
		{"id": BASE, "title": "Immivio acceptance"}
	]
	menu._local_entries = []
	menu._load_section()
	menu.refresh()
	for i in 100:
		if menu.status != "Loading…" and menu.rows.size() > 0:
			break
		await settle(host, 0.1)


func run(host: Node, step: String, request: String) -> Dictionary:
	var menu: Node3D = host.recent_menu
	var bar: Node3D = host.video_menu
	var video: Node3D = host.video
	if step == "setup":
		# Keep the user's real settings/history untouched while exercising persistence on-device.
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://acceptance"))
		host.settings_path = "user://acceptance/player_settings.cfg"
		if FileAccess.file_exists(host.settings_path):
			host.settings.load(host.settings_path)
		host.settings.save(host.settings_path)
		video.history_enabled = false
		video.mode_memory.directory = "user://acceptance/settings"
		video.recent_files.directory = "user://acceptance/settings"
		video.bookmark_store.directory = "user://acceptance/bookmarks"
		menu.browse_memory.path = "user://acceptance/directory.cfg"
		menu.browse_memory.session.clear()
		menu.browse_memory.disk.clear()
		menu.browse_memory.load_file()
		menu.browse_memory.configure(true, true)
		menu.list_view = bool(host.settings.get_value("library", "list_view", false))
		host.screen_layout.restore()
		check(not host.display.preview and host._head_tracked(), "Live OpenXR head tracking")
	elif step == "browse":
		await open_folder(host)
		check(menu.rows.size() >= 30, "Android directory contains STRM entries", menu.rows.size())
		menu._set_scroll(5)
		menu.remember_browse()
		var index: int = menu._first_line() * menu._cols()
		check(await tap(menu, menu.VIEW_MODE), "Ray selects list/icon view")
		check(
			menu._first_line() * menu._cols() == index,
			"View switch retains the visible item",
			[index, menu._first_line() * menu._cols()]
		)
		menu.remember_browse()
		menu.browse_memory.flush()
		check(
			FileAccess.file_exists(menu.browse_memory.path),
			"Directory position persisted on Android"
		)
	elif step == "restore":
		await open_folder(host)
		check(
			menu.list_view and menu._first_line() > 0,
			"Directory and list preference restored after process restart",
			[menu.list_view, menu._first_line()]
		)
	elif step == "controls":
		host._show_player_menu()
		await settle(host)
		check(await tap(bar, bar.SPACE_LOCK), "Ray toggles spatial lock")
		var pose: Transform3D = bar.global_transform
		var original: float = video.screen_distance
		host._on_playback_adjustment("screen_distance", original + 1.0)
		host._place_menu(bar)
		check(
			bar.space_locked and bar.global_transform.is_equal_approx(pose),
			"Control bar stays fixed while screen moves"
		)
		bar.dismiss()
		host._show_player_menu()
		check(
			bar.global_transform.is_equal_approx(pose), "Control bar stays fixed after hide/reopen"
		)
		check(await tap(bar, bar.SPACE_LOCK), "Ray unlocks controls")
		host._show_recent_menu()
		menu.section = menu.Section.SETTINGS
		menu.tab = menu.DISPLAY_TAB
		menu.refresh()
		check(await slide(menu, "controls_opacity", 0.25), "Ray adjusts opacity slider")
		check(
			is_equal_approx(bar.controls_opacity, 0.25),
			"Opacity reaches the requested value",
			bar.controls_opacity
		)
	elif step == "cinema":
		host._on_playback_adjustment("screen_fixed", false)
		host._show_player_menu()
		check(await tap(bar, bar.QUICK_SCREEN), "Ray opens screen layout")
		check(await choose(bar, "screen_preset", "home150"), "Ray selects 150-inch preset")
		await settle(host)
		check(
			is_equal_approx(video.screen_distance, 4.6),
			"Cinema preset distance",
			video.screen_distance
		)
		check(
			absf(video._flat.size.x - 3.320703) < 0.02,
			"Cinema preset preserves 16:9 size",
			video._flat.size
		)
		check(await choose(bar, "screen_fixed", true), "Ray fixes viewing defaults")
		check(await slide(bar, "screen_distance", 0.5), "Ray adjusts large-range distance slider")
		check(
			absf(video.screen_distance - 7.05) < 0.1,
			"Distance slider uses logarithmic scale",
			video.screen_distance
		)
		host._save_playback_adjustments()
		check(
			is_equal_approx(float(host.settings.get_value("screen", "distance")), 4.6),
			"Temporary adjustment preserves fixed default"
		)
		host._recenter()
		check(is_equal_approx(video.screen_distance, 4.6), "Recenter restores fixed default")
	elif step == "library":
		host._show_player_menu()
		check(await tap(bar, bar.BROWSE), "Ray opens compact library")
		await settle(host)
		check(
			menu.visible and bar.visible and menu.compact,
			"Library and playback controls remain visible"
		)
		check(await presented(bar), "Playback controls are present in the native UI capture")
		if host.menu_compositor.viewport:
			await RenderingServer.frame_post_draw
			host.menu_compositor.viewport.get_texture().get_image().save_png(
				"user://diagnostics/acceptance_" + request + "_compact.png"
			)
		check(
			await tap(bar, bar.SPACE_LOCK), "Playback controls remain ray-selectable beside library"
		)
		check(await tap(menu, menu.BROWSER_SIZE), "Ray expands library")
		await settle(host)
		check(
			not menu.compact and menu.visible and bar.visible, "Expanded library retains playback"
		)
		check(await tap(menu, menu.PLAYER), "Ray returns from library to video")
	elif step == "menus":
		host._show_recent_menu(true)
		menu.compact = false
		menu.section = menu.Section.SETTINGS
		menu.tab = menu.GENERAL_TAB
		menu.scroll = 0
		menu.refresh()
		await settle(host)
		check(
			not menu._buttons.any(func(button): return button.target in [82, 83]),
			"Restart/Close buttons removed"
		)
		var centre: Vector2 = menu.capture_envelope().get_center()
		var distance := menu.to_global(Vector3(centre.x, centre.y, 0)).distance_to(
			host.xr_camera.global_position
		)
		check(
			absf(menu.curve_radius - distance) < 0.02,
			"Curved menu matches viewing distance",
			{"radius": menu.curve_radius, "distance": distance}
		)
		var language_rows: Array = menu.rows.filter(
			func(row): return row.get("key", "") == "language"
		)
		var current_language: Variant = (
			language_rows[0].value if not language_rows.is_empty() else null
		)
		var events: Array = []
		var observer := func(key, value):
			if key == "language":
				events.append(value)
		menu.setting_changed.connect(observer)
		check(
			await held_choice_tap(menu, choice_target(menu, "language", "open")),
			"Stationary angled trigger hold survives four XR frames"
		)
		check(
			menu.choices.opened == "language" and not menu.choices.popup.is_empty(),
			"Language dropdown visibly opens"
		)
		await settle(host)
		if host.menu_compositor.viewport:
			await RenderingServer.frame_post_draw
			host.menu_compositor.viewport.get_texture().get_image().save_png(
				"user://diagnostics/acceptance_" + request + "_dropdown.png"
			)
		check(
			await held_choice_tap(
				menu, choice_target(menu, "language", "choose", current_language)
			),
			"Current language option is ray-selectable"
		)
		check(
			(
				events.size() == 1
				and menu.choices.same(events[0], current_language)
				and menu.choices.opened.is_empty()
			),
			"Selection commits once without changing language"
		)
		menu.setting_changed.disconnect(observer)
		menu.tab = menu.ABOUT_TAB
		menu._about_page = 2
		menu.scroll = 0
		menu.refresh()
		await settle(host)
		var ids := navigation_ids(menu)
		var title: String = menu.rows[menu._first_line()].title
		for frame in 10:
			menu.stick_scroll(-1.0, 0.05)
			await host.get_tree().process_frame
		check(
			menu.scroll > 0 and menu.rows[menu._first_line()].title != title,
			"Credits scroll through actual rows"
		)
		check(
			navigation_ids(menu) == ids,
			"Credits keep the same left navigation nodes through scrolling"
		)
		menu.scroll = 0
		menu.refresh()
		check(navigation_ids(menu) == ids, "Restoring credits position retains navigation")
		menu.tab = menu.DISPLAY_TAB
		menu._about_page = 0
		menu.scroll = 0
		menu.refresh()
		await settle(host)
		if host.menu_compositor.viewport:
			await RenderingServer.frame_post_draw
			host.menu_compositor.viewport.get_texture().get_image().save_png(
				"user://diagnostics/acceptance_" + request + "_closed.png"
			)
		check(
			await held_choice_tap(menu, choice_target(menu, "display_quality", "open")),
			"Quality dropdown opener remains ray-selectable"
		)
		check(
			menu.choices.opened == "display_quality" and not menu.choices.popup.is_empty(),
			"Quality dropdown shows filled option rows"
		)
	elif step == "snapshot":
		check(not host.display.preview and host._head_tracked(), "Live XR session")
	elif step == "error":
		check(
			video.media.state == "failed",
			"Invalid STRM reports playback failure",
			video.media.error
		)
		check(bar.visible and bar._quick_open == "info", "Failure opens readable Info panel")
		check(
			not host._menu_error().contains("MPV_"),
			"Failure message is user-readable",
			host._menu_error()
		)
	await settle(host)
	var compositor: Node3D = host.menu_compositor
	if compositor.viewport and compositor.viewport.get_texture():
		await RenderingServer.frame_post_draw
		compositor.viewport.get_texture().get_image().save_png(
			"user://diagnostics/acceptance_" + request + ".png"
		)
	return {
		"request_key": request,
		"step": step,
		"checks": checks,
		"passed": checks.all(func(item): return item.passed),
		"xr": host.display.capabilities(),
		"ui": compositor.snapshot(),
		"media_state": video.media.state,
		"frames": video.media.frame_counter,
		"source_uri": video.local_uri,
		"loading_message": host.playback_feedback.message,
		"menu_visible": bar.visible,
		"library_visible": menu.visible,
		"list_view": menu.list_view,
		"library_scroll": menu.scroll,
		"screen_distance": video.screen_distance,
		"screen_size": video._flat.size,
		"scope":
		(
			"Physical XR menu capture with software-generated rays; no media or physical controller actuation"
			if step == "menus"
			else "Physical PICO/OpenXR/native playback with software-generated ray events; physical controller ergonomics require wearer confirmation"
		)
	}
