extends RefCounted
## Owns photo interactions, inspect state and gallery persistence.

var _host_ref: WeakRef
const Log := preload("res://scripts/diagnostic_log.gd")
const Geometry := preload("res://scripts/video_geometry.gd")

var photo_active := false
var _gallery_save_after := 0
var _gallery_saved_state := ""
var _photo_open_hide_controls := false
var _photo_pointer_hand := ""
var _inspect_hand := ""
var _inspect_blocked := {}
var _inspect_desktop_ray: Variant


func _init(host: Node3D) -> void:
	_host_ref = weakref(host)


func _on_photo_changed() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if not host.photo_active:
		return
	var gallery_state = (
		"%d/%s/%s/%d"
		% [
			host.photo.gallery.mode,
			str(host.photo.gallery._scales),
			str(host.photo.gallery._distances),
			host.photo.gallery.wall_rows
		]
	)
	if gallery_state != host._gallery_saved_state:
		host._gallery_saved_state = gallery_state
		host._gallery_save_after = Time.get_ticks_msec() + 450
	if host._photo_open_hide_controls and not host.photo.loading and host.photo.panel.visible:
		host._photo_open_hide_controls = false
		if host.photo.geometry == Geometry.Geometry.FLAT:
			host.photo_menu.dismiss()
	host._update_thumbnail_protection()
	host._update_background()
	if host.player_menu and host.player_menu.visible:
		host.player_menu.refresh_values()
	if host.calibration_board:
		host.calibration_board.visible = false


func _on_photo_adjustment(key: String, value: Variant) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if not host.photo_active or not is_finite(float(value)):
		return
	host._menu_touched_ms = Time.get_ticks_msec()
	match key:
		"gallery_scale":
			host.photo.gallery.set_view_scale(float(value))
			host.photo.changed.emit()
		"wall_rows":
			host.photo.gallery.set_wall_rows(int(value))
			host.photo.changed.emit()
		"gallery_distance":
			host.photo.gallery.set_view_distance(float(value))
			host.photo.changed.emit()
		"screen_distance":
			if host.photo.geometry != Geometry.Geometry.FLAT:
				return
			if host.photo.gallery.focus >= 0:
				host.photo.gallery.set_focus_distance(float(value))
			else:
				host._push_screen(
					(
						clampf(
							float(value),
							host.photo.PHOTO_DISTANCE_LIMITS.x,
							host.photo.PHOTO_DISTANCE_LIMITS.y
						)
						- host.photo.panel.global_position.distance_to(host._eye())
					)
				)
			host.photo.changed.emit()
		"screen_scale":
			if host.photo.geometry != Geometry.Geometry.FLAT:
				return
			host.photo.set_screen_scale(float(value))
			host.photo.changed.emit()
		"inspect_magnification":
			host.photo.set_inspect_magnification(float(value))


func _save_photo_adjustments() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	host.settings.set_value("photo_screen", "distance", host.photo.screen_distance)
	host.settings.set_value("photo_screen", "scale", host.photo.screen_scale)
	host.settings.set_value(
		"photo_screen",
		"curve",
		host.photo._portrait_curve if host.photo.portrait_requested else host.photo.screen_curve
	)
	host.settings.set_value("photo_screen", "magnification", host.photo.inspect_magnification)
	host.photo.gallery.save_settings(host.settings)
	host._gallery_save_after = 0
	host._gallery_saved_state = (
		"%d/%s/%s/%d"
		% [
			host.photo.gallery.mode,
			str(host.photo.gallery._scales),
			str(host.photo.gallery._distances),
			host.photo.gallery.wall_rows
		]
	)
	host.settings.save(host.settings_path)


func _toggle_photo_inspect(hand: String = "") -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if not host.photo.panel.visible or host.photo.portrait_requested:
		return
	host.photo.gallery.cancel_all()
	if host.photo.inspect:
		host._close_photo_inspect()
		return
	host._grab = {}
	host.photo_hands.cancel()
	host.photo_swipe.cancel()
	host.memory_swipe.cancel()
	host.stick_controls.suspend()
	host._inspect_hand = hand if hand in ["left_hand", "right_hand"] else host._photo_pointer_hand
	host._inspect_desktop_ray = null
	host.photo.toggle_inspect()
	if host.player_menu:
		host.player_menu.dismiss()
	host._update_photo_inspect()


func _close_photo_inspect(show_controls: bool = true) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	for hand in host.hand_pointers:
		if host.hand_pointers[hand].source == "hand" and host.hand_pointers[hand].down:
			host._inspect_blocked[hand] = true
	host._grab = {}
	host.photo_hands.cancel()
	host.photo_swipe.cancel()
	host.memory_swipe.cancel()
	host.stick_controls.suspend()
	host._inspect_hand = ""
	host._inspect_desktop_ray = null
	host.photo.close_inspect()
	if show_controls:
		host._show_player_menu()


func _update_photo_inspect() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if (
		not host.photo_active
		or not host.photo.inspect
		or not host._input_focused()
		or host._active_menu()
	):
		if host.photo:
			host.photo.hide_inspect_pointer()
		return
	var ray: Variant = (
		host._ray(host._inspect_hand) if host._inspect_hand in ["left_hand", "right_hand"] else null
	)
	if ray == null:
		for hand in ["right_hand", "left_hand"]:
			ray = host._ray(hand)
			if ray != null:
				host._inspect_hand = hand
				break
	if ray == null and host.display.preview:
		ray = host._inspect_desktop_ray
	if ray == null:
		host.photo.hide_inspect_pointer()
	else:
		host.photo.update_inspect_pointer(ray[0], ray[1], host._inspect_hand)


func _on_photo_action(operation: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if operation.begins_with("photo_layout_"):
		host._grab = {}
		host.photo_hands.cancel()
		host.photo_swipe.cancel()
		host.memory_swipe.cancel()
		host.stick_controls.suspend()
		host.photo.set_layout_mode(int(operation.trim_prefix("photo_layout_")))
		host._save_photo_adjustments()
		return
	host._menu_touched_ms = Time.get_ticks_msec()
	match operation:
		"photo_shuffle":
			if host.photo.gallery.mode == 2:
				host.photo.gallery.change_batch(1)
			elif host.photo.gallery.shuffle_fragments():
				Log.record("memory_shuffle", {"input": "menu"})
		"photo_portrait":
			host._grab = {}
			host.photo_hands.cancel()
			host.memory_swipe.cancel()
			host.stick_controls.suspend()
			host.photo.set_portrait(not host.photo.portrait_requested)
		"photo_return":
			if host.photo.portrait_requested:
				host.photo.set_portrait(false)
			else:
				host.photo.gallery.return_focus()
		"photo_previous":
			if host.photo.gallery.mode == 2 and host.photo.gallery.overview():
				host.photo.gallery.change_batch(-1)
			else:
				host.photo.navigate(-1)
		"photo_next":
			if host.photo.gallery.mode == 2 and host.photo.gallery.overview():
				host.photo.gallery.change_batch(1)
			else:
				host.photo.navigate(1)
		"photo_inspect":
			host._toggle_photo_inspect()
		"photo_fit":
			host._close_photo_inspect()
		"stop":
			host.photo.close_image()
			host._show_recent_menu()
		"recenter":
			host._recenter()
		"depth":
			if host.photo.set_depth(not host.photo.depth_requested):
				host._remember_auto_depth(host.photo.auto_depth)
		"depth_strength":
			host.photo.cycle_depth_strength()
		"projection_0", "projection_1", "projection_2", "projection_3":
			host.photo.set_projection(int(operation.right(1)))
		"lock_mode":
			host.photo.toggle_mode_lock()
		"stereo_2d":
			host._remember_auto_depth(false)
			host.photo.set_depth(false)
			host.photo.set_stereo_layout(0)
		"stereo_sbs":
			host.photo.set_stereo_layout(1)
		"stereo_tb":
			host.photo.set_stereo_layout(2)
		"eyes":
			host.photo.toggle_eye_order()
		"fov_180", "fov_190", "fov_200", "fov_220":
			host.photo.set_fisheye_fov(int(operation.right(3)))
		"screen_curve":
			host.photo.cycle_screen_curve()
			host._save_screen()
			host.photo.changed.emit()
		"photo_background":
			if host.background.import_photo(
				host.photo.background_source(), host.photo.display_name
			):
				host._show_recent_menu()
				host.recent_menu.section = host.recent_menu.Section.SETTINGS
				host.recent_menu.tab = host.recent_menu.BACKGROUND_TAB
				host.recent_menu.refresh()
		_:
			if operation.begins_with("photo_index_"):
				host.photo.select_image(int(operation.trim_prefix("photo_index_")))
