extends RefCounted
## Debug-only caller: exercise production ray/trigger methods on the real device.
static func tap(menu: Node3D, target: int) -> bool:
	# Exercise the pixels the headset is displaying, not an unpresented page.
	for frame in 120:
		if not menu.xr_surface or not menu.xr_surface.native_supported or menu.xr_surface.is_layout_presented(menu): break
		await menu.get_tree().process_frame
	for button in menu._buttons:
		if button.target != target or not button.enabled or not button.node.visible: continue
		var origin: Vector3 = button.node.global_position + button.node.global_basis.z
		var direction: Vector3 = -button.node.global_basis.z
		if menu.xr_surface and menu.xr_surface.native_supported and menu.xr_surface.active_menu == menu:
			var pose: Transform3D = menu.xr_surface.layer.global_transform
			var local: Vector3 = pose.affine_inverse() * button.node.global_position
			origin = pose * Vector3(local.x, local.y, 1)
			direction = -pose.basis.z
		if not menu.press_pointer("left_hand", origin, direction, true): return false
		menu.release_pointer("left_hand", origin, direction, true)
		return true
	return false

func run(host: Node, step: String, marker_id: String) -> Dictionary:
	var result := {"step": step, "accepted": false, "scope": "Actual production ray-menu software route on Quest; no physical controller injection"}
	if step == "ui_reset_stats":
		host.menu_compositor.reset_metrics(); result.accepted = true
	elif step in ["player_settings", "player_playback", "player_screen", "player_bar"]:
		host._show_player_menu()
		var target: int = {"player_settings": 11, "player_playback": host.player_menu.PLAYBACK_SETTINGS, "player_screen": 11, "player_bar": 10}[step]
		result.accepted = await tap(host.player_menu, target)
	elif step == "recenter":
		host._show_player_menu()
		host.player_menu.section = 0; host.player_menu.refresh()
		result.accepted = await tap(host.player_menu, 108)
	elif step in ["global_speed", "global_exact", "bookmark_global", "bookmark_speed", "bookmark_exact", "bookmark_add"]:
		result["error"] = "Control removed"
	elif step in ["bookmark_seek", "bookmark_delete"]:
		host._show_player_menu()
		var menu: Node3D = host.player_menu
		menu.section = 0; menu.bookmarks.opened = true
		menu.bookmarks.subset.clear(); menu.bookmarks.offset = 0; menu.refresh()
		for target in menu.bookmarks.targets:
			var item: Dictionary = menu.bookmarks.targets[target]
			if item.get("id", "") == marker_id and item.get("kind") == ("seek" if step == "bookmark_seek" else "delete"):
				result.accepted = await tap(menu, target); break
	result.global_mode = host.video.seek_mode
	result.bookmark_mode = host.video.bookmark_seek_mode
	result.bookmarks = host.video.bookmarks_snapshot().get("bookmarks", []).duplicate(true)
	return result
