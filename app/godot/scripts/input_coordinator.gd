extends RefCounted
## Owns controller/hand routing and drag state; the host supplies scene objects.

var _host_ref: WeakRef
var immersive := preload("res://scripts/immersive_adjustments.gd").new()
var immersive_grips := {}
const Log := preload("res://scripts/diagnostic_log.gd")
const HandPointer := preload("res://scripts/hand_pointer.gd")
const Geometry := preload("res://scripts/video_geometry.gd")
const LibraryMenu := preload("res://scripts/library_menu.gd")

var _grab := {}
var _library_grab := {}


func _init(host: Node3D) -> void:
	_host_ref = weakref(host)


## Desktop and the explicit 2D diagnostic entry share the real 3D menu path.
## Pointer release/capture ownership stays the same as controller interaction.
func _preview_menu_input(event: InputEvent) -> bool:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host) or not host.display.preview or not event is InputEventMouse:
		return false
	var menu: Node3D = host.input_source.active_menu()
	for candidate in [host.library_menu, host.player_menu]:
		if (
			is_instance_valid(candidate)
			and candidate.visible
			and candidate.has_method("has_pointer_capture")
			and candidate.has_pointer_capture()
		):
			menu = candidate
			break
	if not menu or not is_instance_valid(host.xr_camera):
		return false
	var origin: Vector3 = host.xr_camera.project_ray_origin(event.position)
	var direction: Vector3 = host.xr_camera.project_ray_normal(event.position)
	if (
		menu == host.library_menu
		and host.player_menu
		and host.player_menu.visible
		and not menu.has_pointer_capture()
	):
		var controls: Dictionary = host.player_menu.ray_hit(origin, direction)
		if controls.is_empty():
			controls = host.player_menu.ray_panel_hit(origin, direction)
		var library: Dictionary = menu.ray_panel_hit(origin, direction)
		if (
			not controls.is_empty()
			and (library.is_empty() or float(controls.distance) < float(library.distance))
		):
			menu = host.player_menu
	for other in [host.library_menu, host.player_menu]:
		if is_instance_valid(other) and other != menu:
			other.update_pointer("desktop", origin, direction, false)
	if event is InputEventMouseMotion:
		menu.update_pointer("desktop", origin, direction, true)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		host.menu_touched_ms = Time.get_ticks_msec()
		if event.pressed:
			menu.press_pointer("desktop", origin, direction, true)
		else:
			menu.release_pointer("desktop", origin, direction, true)
	elif (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
		and menu.has_method("stick_scroll")
	):
		menu.stick_scroll(1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0, 0.12)
	else:
		return false
	host.get_viewport().set_input_as_handled()
	return true


func _unhandled_input(event: InputEvent) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if _preview_menu_input(event):
		return
	if host.input_source.active_menu() or not host.video or host.viewer().local_uri.is_empty():
		return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		host.presentation_coordinator._turn_picture(
			-event.relative.x * host.MOUSE_TURN, -event.relative.y * host.MOUSE_TURN
		)
	elif (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
	):
		var forward = 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		if host.viewer().geometry != Geometry.Geometry.FLAT:
			host.viewer().zoom_view(0.05 * forward)
		else:
			host.presentation_coordinator._push_screen(0.1 * forward)
			host.presentation_coordinator._save_screen()


func _unhandled_key_input(event: InputEvent) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			host.presentation_coordinator._toggle_player_menu()
			return
		var menu = host.input_source.active_menu()
		if menu:
			if OS.get_name() == "Android":
				return
			if event.keycode == KEY_ESCAPE:
				if menu.get("allow_user_dismiss") != false:
					menu.dismiss()
			elif menu == host.library_menu:
				match event.keycode:
					KEY_UP:
						host.library_menu.move_focus(-1)
					KEY_DOWN:
						host.library_menu.move_focus(1)
					KEY_ENTER:
						host.library_menu.activate_desktop()
			return
		match event.keycode:
			KEY_T:
				host.presentation_coordinator._toggle_display()
			KEY_R:
				host.input_source.recenter()
			KEY_D:
				host.request_capabilities()
			KEY_O:
				host.presentation_coordinator._show_library_menu()
			KEY_SPACE:
				host.video.toggle_play()
			KEY_S:
				host.video.toggle_stereo()
			KEY_P:
				host.video.cycle_projection()
			KEY_LEFT:
				host.video.seek_relative(-10000)
			KEY_RIGHT:
				host.video.seek_relative(10000)
			KEY_H:
				host.video.cycle_audio_track()
			KEY_C:
				host.video.cycle_subtitle_track()
			KEY_E:
				host.video.toggle_eye_order()
			KEY_V:
				host.video.play_calibration_clip()


func _on_controller_release(action: String, hand: String = "") -> void:
	if action == "grip_click":
		immersive_grips.erase(hand)
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if (
		action == "grip_click"
		and host.video
		and host.video.has_method("commit_immersive_adjustments")
	):
		host.video.commit_immersive_adjustments()
	if not host.input_source.controller_allowed(hand):
		return
	if host.input_visuals:
		host.input_visuals.controller_activity(hand)
	_on_pointer_release(action, hand)


func _on_pointer_release(action: String, hand: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if action == "grip_click" and _library_grab.get("hand", "") == hand:
		if _library_grab.get("moved", false):
			host.settings.set_value("ui", "library_distance", host.library_distance)
			host.settings.save(host.settings_path)
		_library_grab.clear()
		return
	if action in ["trigger_click", "grip_click"] and host.input_source.ray(hand) == null:
		_cancel_pointer(hand)
		return
	if action == "trigger_click" and host.trigger_taps.has(hand):
		var tap: Dictionary = host.trigger_taps[hand]
		host.trigger_taps.erase(hand)
		if tap.uri == host.viewer().local_uri:
			if host.input_source.active_menu() or host.picture_pinch_allowed(hand):
				host.presentation_coordinator._toggle_player_menu()
		return
	if (
		not _grab.is_empty()
		and _grab.hand == hand
		and action == _grab.get("action", "trigger_click")
	):
		var grab = _grab
		if host.picture_center_guide:
			host.picture_center_guide.release(hand)
		_grab = {}
		host.viewer().set_corner_hover(-1)
		if grab.moved and host.viewer().geometry == Geometry.Geometry.FLAT:
			host.presentation_coordinator._save_screen()
		if action == "trigger_click" and not grab.moved:
			if host.player_menu.visible:
				host.player_menu.dismiss()
			elif not grab.get("hid_menu", false) and host.picture_pinch_allowed(hand):
				host.presentation_coordinator._show_player_menu()
		return
	var menu = host.input_source.active_menu()
	if host.player_menu and host.player_menu.visible and host.player_menu.has_pointer_capture():
		menu = host.player_menu
	if action != "trigger_click" or not menu or not menu.has_method("release_pointer"):
		return
	var ray: Variant = host.input_source.ray(hand)
	menu.release_pointer(
		hand,
		ray[0] if ray != null else Vector3.ZERO,
		ray[1] if ray != null else Vector3.ZERO,
		ray != null
	)


func _on_controller_button(action: String, hand: String = "") -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if not host.input_source.controller_allowed(hand):
		return
	if host.input_visuals:
		host.input_visuals.controller_activity(hand)
	if action == "grip_click":
		immersive_grips[hand] = true
	_on_pointer_button(action, hand)


func _on_pointer_button(action: String, hand: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if (
		action == "trigger_click"
		and not host.picture_pinch_allowed(hand)
		and not host.input_source.active_menu()
	):
		return
	if action == "menu_button":
		host.presentation_coordinator._toggle_player_menu()
		return
	var menu = host.input_source.active_menu()
	if action == "grip_click":
		if menu == host.library_menu and menu is LibraryMenu:
			_begin_library_grab(hand)
			return
		if (
			not host.viewer().local_uri.is_empty()
			and host.input_source.ray(hand) != null
			and (
				menu == null
				or (
					menu == host.player_menu
					and (not menu.has_pointer_capture())
					and (
						host.viewer().geometry == Geometry.Geometry.FLAT
						or menu.allows_playback_sticks()
					)
				)
			)
		):
			host.trigger_taps.clear()
			if menu == host.player_menu:
				menu.dismiss()
			_begin_grab(hand, "grip_click")
		return
	if (
		action == "trigger_click"
		and (not _library_grab.is_empty() or _grab.get("action", "") == "grip_click")
	):
		return
	if menu:
		match action:
			"trigger_click":
				# An outside trigger tap dismisses controls without moving the picture.
				if (
					not host.presentation_coordinator._update_menu_pointer(hand, true)
					and menu == host.player_menu
				):
					var ray: Variant = host.input_source.ray(hand)
					# A slider owned by the other hand rejects this press; it is not a screen drag.
					if (
						ray != null
						and menu.ray_hit(ray[0], ray[1]).is_empty()
						and menu.ray_panel_hit(ray[0], ray[1]).is_empty()
					):
						_begin_picture_press(hand)
			"by_button":
				if menu.get("allow_user_dismiss") != false:
					menu.dismiss()
		return
	match action:
		"trigger_click":
			if host.viewer().local_uri.is_empty():
				host.presentation_coordinator._show_library_menu()
			else:
				_begin_picture_press(hand)
		"ax_button":
			host.presentation_coordinator._show_library_menu()
		"primary_click":
			if hand == "left_hand":
				host.video.cycle_projection()
			else:
				host.presentation_coordinator._reset_picture()


func _process_sticks(left: Vector2, right: Vector2, delta: float) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.input_visuals and host.input_source.input_focused():
		if left.length() >= 0.3:
			host.input_visuals.controller_activity("left_hand")
		if right.length() >= 0.3:
			host.input_visuals.controller_activity("right_hand")
	if _process_immersive(left, right, delta):
		return
	if not _library_grab.is_empty():
		_update_library_grab_stick(left, right, delta)
		host.presentation_coordinator._update_menu_pointer("left_hand")
		host.presentation_coordinator._update_menu_pointer("right_hand")
		host.stick_controls.suspend()
		return
	if _grab.get("action", "") == "grip_click":
		host.stick_controls.suspend()
		return
	var menu = host.input_source.active_menu()
	if menu:
		host.presentation_coordinator._update_menu_pointer("left_hand")
		host.presentation_coordinator._update_menu_pointer("right_hand")
	if not host.input_source.input_focused():
		host.stick_controls.suspend()
		return
	if menu and (menu != host.player_menu or not host.player_menu.allows_playback_sticks()):
		host.stick_controls.suspend()
		# Either stick scrolls a list, never selects or controls playback at the same time.
		if (
			menu.has_method("stick_scroll")
			and (menu != host.player_menu or not host.player_menu.has_pointer_capture())
		):
			menu.stick_scroll(left.y if absf(left.y) > absf(right.y) else right.y, delta)
		_update_controls_visibility(menu)
		return
	var actions = host.stick_controls.poll(
		left, right, host.video != null and (host.viewer().geometry != Geometry.Geometry.FLAT)
	)
	if not _grab.is_empty():
		# Holding the picture: only zoom; other stick shortcuts wait for the stick to recenter.
		actions = actions.filter(func(action): return action.operation == "zoom")
	_apply_stick_actions(actions, delta)
	if menu == host.player_menu and menu != null:
		if not actions.is_empty():
			host.menu_touched_ms = Time.get_ticks_msec()
			host.player_menu.refresh_values()
		_update_controls_visibility(menu)


func _process_immersive(left: Vector2, right: Vector2, delta: float) -> bool:
	var host := _host_ref.get_ref() as Node3D
	if (
		not is_instance_valid(host)
		or not host.video
		or host.video.geometry == Geometry.Geometry.FLAT
		or host.video.local_uri.is_empty()
	):
		immersive.suspend()
		immersive.clear_feedback()
		return false
	var menu: Node3D = host.input_source.active_menu()
	if (
		not host.input_source.input_focused()
		or not _library_grab.is_empty()
		or (menu and (menu != host.player_menu or not menu.allows_playback_sticks()))
		or (not _grab.is_empty() and _grab.get("action") != "grip_click")
	):
		immersive.suspend()
		immersive.clear_feedback()
		if not host.input_source.input_focused():
			immersive_grips.clear()
		return false
	var held := false
	var changed := false
	for hand in ["left_hand", "right_hand"]:
		var pressed: bool = (
			immersive_grips.get(hand, false)
			and host.input_source.controller_allowed(hand)
			and host.input_source.ray(hand) != null
		)
		held = held or pressed
		var axis: Vector2 = left if hand == "left_hand" else right
		var action: Dictionary = immersive.poll(hand, axis, pressed)
		if action.is_empty():
			continue
		var key: String = action.key
		if key == "stereo_horizontal":
			if is_nan(immersive.alignment_value):
				immersive.alignment_value = host.video.stereo_horizontal
			immersive.alignment_value = clampf(
				(
					immersive.alignment_value
					+ float(action.amount) * immersive.ALIGNMENT_SPEED * minf(delta, 0.1)
				),
				-10,
				10
			)
			changed = host.video.set_stereo_alignment(key, immersive.alignment_value) or changed
		else:
			changed = (
				host.video.set_immersive_adjustment(
					key,
					(
						float(host.video.get(key))
						+ float(action.amount) * immersive.MOVE_SPEED * minf(delta, 0.1)
					)
				)
				or changed
			)
		if changed:
			immersive.show_feedback(key, float(host.video.get(key)), host.video.local_uri)
	if left.length() < 0.3 and right.length() < 0.3:
		host.video.commit_immersive_adjustments()
	if held:
		host.stick_controls.suspend()
	return held


func _update_controls_visibility(menu: Node3D) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if menu != host.player_menu or menu == null or not menu.visible:
		return
	var now = Time.get_ticks_msec()
	if (
		menu.has_pointer_capture()
		or menu._hover.values().any(func(target): return int(target) != menu.NONE)
	):
		host.menu_touched_ms = now
		return
	# Keep popups, sliders and pending seeks visible; use media state, not the seek queue's state.
	if (
		menu.section != 0
		or menu._mode_open
		or not menu._quick_open.is_empty()
		or not menu._adjustment.is_empty()
	):
		return
	if (
		not menu.choices.opened.is_empty()
		or menu._subtitle_open
		or menu.bookmarks.opened
		or not host.video.requested_play
		or host.video.media.state != "playing"
		or host.video.control.pending
		or host.video.control.in_flight > 0
	):
		return
	if now - host.menu_touched_ms > host.CONTROLS_HIDE_MS:
		menu.dismiss()


func _stick(controller: XRController3D) -> Vector2:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return Vector2.ZERO
	return (
		controller.get_vector2("primary")
		if (
			controller
			and controller.get_is_active()
			and host.input_source.controller_allowed(str(controller.tracker))
		)
		else Vector2.ZERO
	)


func _hand_tracker(hand: String) -> XRHandTracker:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return null
	return (
		XRServer.get_tracker("/user/hand_tracker/" + ("left" if hand == "left_hand" else "right"))
		as XRHandTracker
	)


func _hand_action_tracker(hand: String) -> XRPositionalTracker:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return null
	return XRServer.get_tracker(hand) as XRPositionalTracker


func _meta_aim_tracker(hand: String) -> XRPositionalTracker:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return null
	return (
		XRServer.get_tracker("/user/fbhandaim/" + ("left" if hand == "left_hand" else "right"))
		as XRPositionalTracker
	)


func _update_hand_input(delta: float) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.input_visuals:
		host.input_visuals.update_visibility(
			host.input_source.input_focused() and host.input_source.head_tracked(),
			delta,
			host.video != null and not host.video.local_uri.is_empty(),
			(
				host.input_source.active_menu() != null
				or not _grab.is_empty()
				or not _library_grab.is_empty()
				or not host.trigger_taps.is_empty()
			)
		)
	var inputs = {}
	for hand in host.hand_pointers:
		var sample = {}
		if host.input_source.input_focused():
			var tracker = _hand_tracker(hand)
			if (
				HandPointer.is_optical(tracker)
				and host.xr_camera
				and host.xr_origin
				and host.input_source.head_tracked()
			):
				sample = HandPointer.sample(
					tracker,
					hand,
					host.xr_camera.global_transform,
					host.xr_origin.global_transform * XRServer.get_reference_frame(),
					XRServer.world_scale,
					_meta_aim_tracker(hand),
					_hand_action_tracker(hand)
				)
			elif HandPointer.is_hand_profile(_hand_action_tracker(hand)):
				# Action aim/select is independent of the optional hand-joint stream.
				# Runtimes may also expose controllers through a hand interaction profile.
				if host.xr_origin:
					sample = HandPointer.runtime_sample(
						_hand_action_tracker(hand),
						host.xr_origin.global_transform * XRServer.get_reference_frame(),
						XRServer.world_scale,
						false
					)
			elif not HandPointer.is_optical(tracker):
				var ray: Variant = host.input_source.controller_ray(hand)
				if ray != null:
					sample = {"source": "controller", "ray": ray}
		var event: Dictionary = host.hand_pointers[hand].update(sample, delta)
		if event.cancelled:
			_cancel_pointer(hand)
		if event.menu and hand == "left_hand":
			_on_pointer_button("menu_button", hand)
		var pointer: RefCounted = host.hand_pointers[hand]
		inputs[hand] = event.merged(
			{"source": pointer.source, "tracked": pointer.ray != null, "down": pointer.down}
		)
		if host.hand_marks.has(hand):
			var mark: MeshInstance3D = host.hand_marks[hand]
			mark.visible = (
				pointer.source == "hand"
				and pointer.ray != null
				and not host.input_source.active_menu()
			)
			if mark.visible:
				mark.global_position = pointer.ray[0]
				mark.scale = Vector3.ONE * XRServer.world_scale * (0.65 if pointer.down else 1.0)
	_dispatch_hand_input(inputs, delta)


func _dispatch_hand_input(inputs: Dictionary, _delta: float = 1.0 / 72.0) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	for hand in inputs:
		if inputs[hand].get("pressed", false):
			_on_pointer_button("trigger_click", hand)
		if inputs[hand].get("released", false):
			_on_pointer_release("trigger_click", hand)


func _cancel_pointer(hand: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if _library_grab.get("hand", "") == hand:
		_library_grab.clear()
	host.trigger_taps.erase(hand)
	if not _grab.is_empty() and _grab.hand == hand:
		if _grab.moved and host.viewer().geometry == Geometry.Geometry.FLAT:
			host.presentation_coordinator._save_screen()
		_grab = {}
		host.viewer().set_corner_hover(-1)
	# Cancellation never becomes a tap, row selection, or fling.
	for menu in [host.library_menu, host.video_menu]:
		if is_instance_valid(menu) and menu.has_method("cancel_pointer"):
			menu.cancel_pointer(hand)


func _on_input_session_changed() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.input_source.input_focused():
		return
	host.trigger_taps.clear()
	for hand in host.hand_pointers:
		host.hand_pointers[hand].update({}, 0)
		_cancel_pointer(hand)
		if host.hand_marks.has(hand):
			host.hand_marks[hand].visible = false


func _hand_input_report() -> Dictionary:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return {}
	var report = {}
	for hand in host.hand_pointers:
		var pointer: RefCounted = host.hand_pointers[hand]
		var action = _hand_action_tracker(hand)
		var joints = _hand_tracker(hand)
		report[hand] = {
			"source": pointer.source,
			"provider": pointer.provider,
			"tracked": pointer.ray != null,
			"pinching": pointer.down,
			"profile": str(action.get_tracker_profile()) if action else "",
			"action_aim_tracked": host.input_pose_tracked(action, "aim"),
			"action_grip_tracked": host.input_pose_tracked(action, "grip"),
			"joint_tracking": joints != null and joints.has_tracking_data,
			"joint_source": int(joints.hand_tracking_source) if joints else -1
		}
	return report


func _begin_library_grab(hand: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if not _library_grab.is_empty() or host.library_menu.has_pointer_capture():
		return
	var ray: Variant = host.input_source.ray(hand)
	if ray == null:
		return
	var point: Variant = host.library_menu._plane_point(ray[0], ray[1])
	if point == null or not Rect2(-1.1, -0.85, 2.05, 1.5).has_point(Vector2(point.x, point.y)):
		return
	var offset: Vector3 = host.library_menu.global_position - host.eye()
	if offset.length() < .1:
		return
	host.trigger_taps.clear()
	host.stick_controls.suspend()
	host.library_menu._fling = 0.0
	var ray_length: float = ray[0].distance_to(host.library_menu.to_global(point))
	var direction: Vector3 = (ray[0] + ray[1] * ray_length - host.eye()).normalized()
	_library_grab = {
		"hand": hand,
		"ray_length": ray_length,
		"start_direction": direction,
		"last_direction": direction,
		"dragged": false,
		"moved": false
	}


func _update_library_grab() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if _library_grab.is_empty():
		return
	var ray: Variant = host.input_source.ray(_library_grab.hand)
	if ray == null or not host.library_menu.visible:
		_library_grab.clear()
		return
	host.library_menu._stick_ms = Time.get_ticks_msec()
	var direction: Vector3 = (
		(ray[0] + ray[1] * float(_library_grab.ray_length) - host.eye()).normalized()
	)
	var head: Variant = host.presentation_coordinator._head_pose()
	var frame: Basis = (
		host.presentation_coordinator._menu_head_pose(head).basis
		if head != null and (host.view_follow.enabled or host.reclining_mode)
		else Basis.IDENTITY
	)
	var angles = host.ray_angles(frame.inverse() * direction)
	if not _library_grab.dragged:
		var turned = angles - host.ray_angles(frame.inverse() * _library_grab.start_direction)
		turned.x = wrapf(turned.x, -PI, PI)
		if not host.reclining_mode:
			turned.y = 0.0
		if turned.length() < host.GRAB_START:
			return
		_library_grab.dragged = true
	var previous = host.ray_angles(frame.inverse() * _library_grab.last_direction)
	_library_grab.last_direction = direction
	_library_grab.moved = true
	var pose = Transform3D(frame, host.eye()).affine_inverse() * host.library_menu.global_transform
	var offset = pose.origin
	var placement = (
		host.ray_angles(offset)
		+ Vector2(
			wrapf(angles.x - previous.x, -PI, PI),
			angles.y - previous.y if host.reclining_mode else 0.0
		)
	)
	if host.reclining_mode:
		var target = (
			(Basis(Vector3.UP, placement.x) * Basis(Vector3.RIGHT, clampf(placement.y, -1.5, 1.5)))
			* Vector3.FORWARD
		)
		pose.basis = Basis(Quaternion(offset.normalized(), target)) * pose.basis
		pose.origin = target * offset.length()
	else:
		pose.basis = Basis(Vector3.UP, placement.x)
		pose.origin = (
			pose.basis * Vector3(0, 0, -Vector2(offset.x, offset.z).length())
			+ Vector3.UP * offset.y
		)
	host.library_menu.global_transform = Transform3D(frame, host.eye()) * pose
	host.presentation_coordinator._on_menu_placement_changed(host.library_menu)


func _update_library_grab_stick(left: Vector2, right: Vector2, delta: float) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if (
		_library_grab.is_empty()
		or not host.library_menu.visible
		or host.input_source.ray(_library_grab.hand) == null
	):
		return
	var held = left if _library_grab.hand == "left_hand" else right
	if not is_finite(held.y) or absf(held.y) <= host.STICK_DEADZONE:
		return
	var amount = (
		signf(held.y)
		* (absf(held.y) - host.STICK_DEADZONE)
		/ (1.0 - host.STICK_DEADZONE)
		* delta
		* host.PUSH_SPEED
	)
	var distance = clampf(
		host.library_distance + amount,
		host.LIBRARY_DISTANCE_LIMITS.x,
		host.LIBRARY_DISTANCE_LIMITS.y
	)
	var offset = host.library_menu.global_position - host.eye()
	if host.reclining_mode:
		host.library_menu.global_position = host.eye() + offset.normalized() * distance
	else:
		var horizontal = Vector3(offset.x, 0, offset.z).normalized()
		host.library_menu.global_position = (
			host.eye() + horizontal * distance + Vector3.UP * offset.y
		)
	host.library_distance = distance
	_library_grab.moved = true
	host.presentation_coordinator._on_menu_placement_changed(host.library_menu)


func _begin_picture_press(hand: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.input_source.ray(hand) == null:
		return
	if host.hand_pointers.has(hand) and host.hand_pointers[hand].source == "hand":
		_begin_grab(hand, "trigger_click")
	else:
		host.trigger_taps[hand] = {"uri": host.viewer().local_uri}


func _update_flat_grab_stick(left: Vector2, right: Vector2, delta: float) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if (
		host.input_source.active_menu()
		or _grab.is_empty()
		or _grab.has("resize")
		or _grab.get("tap_only", false)
	):
		return
	var held = left if _grab.hand == "left_hand" else right
	if not is_finite(held.y) or absf(held.y) <= host.STICK_DEADZONE:
		return
	var amount = (
		signf(held.y) * (absf(held.y) - host.STICK_DEADZONE) / (1.0 - host.STICK_DEADZONE) * delta
	)
	_grab.moved = true
	if host.viewer().geometry != Geometry.Geometry.FLAT:
		host.viewer().zoom_view(-amount * host.ZOOM_SPEED)
	elif _grab.get("action", "") == "grip_click":
		host.presentation_coordinator._push_screen(amount * host.PUSH_SPEED)
	else:
		host.video.set_screen_scale(host.video.screen_scale * exp(amount * 0.8))


func _update_corner_hover() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if not host.video or not host.viewer().has_method("corner_at"):
		return
	var corner = -1
	if _grab.has("resize"):
		corner = int(_grab.resize.corner)
	elif (
		_grab.is_empty()
		and (not host.library_menu.visible)
		and (not host.viewer().local_uri.is_empty())
	):
		for hand in ["right_hand", "left_hand"]:
			var ray: Variant = host.input_source.ray(hand)
			if (
				ray != null
				and not (host.player_menu.visible and host.player_menu._hover.get(hand, -1) != -1)
			):
				corner = host.viewer().corner_at(ray[0], ray[1])
				if corner >= 0:
					break
	host.viewer().set_corner_hover(corner)


func _begin_grab(hand: String, action: String = "grip_click") -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if not host.picture_pinch_allowed(hand):
		return
	if not _grab.is_empty():
		return
	if host.view_follow.enabled and host.presentation_coordinator._head_pose() == null:
		return
	var ray: Variant = host.input_source.ray(hand)
	if ray == null:
		if host.player_menu.visible:
			host.player_menu.dismiss()
		return
	var angles = host.ray_angles(ray[1])
	_grab = {
		"hand": hand,
		"action": action,
		"start": angles,
		"last": angles,
		"moved": false,
		"start_direction": ray[1],
		"last_direction": ray[1]
	}
	if action == "grip_click":
		_grab.ray_length = (
			maxf(.25, ray[0].distance_to(host.viewer().panel.global_position))
			if host.viewer().geometry == Geometry.Geometry.FLAT
			else 2.0
		)
		var direction: Vector3 = (
			(ray[0] + ray[1] * float(_grab.ray_length) - host.eye()).normalized()
		)
		_grab.start = host.ray_angles(direction)
		_grab.last = _grab.start
		_grab.start_direction = direction
		_grab.last_direction = direction
	var corner: int = host.viewer().corner_at(ray[0], ray[1])
	var point: Variant = host.viewer().screen_point(ray[0], ray[1]) if corner >= 0 else null
	if point != null and Vector2(point.x, point.y).length() > 0.05:
		_grab["resize"] = {
			"corner": corner,
			"start_length": Vector2(point.x, point.y).length(),
			"start_scale": host.viewer().screen_scale
		}
	# A deliberate screen press leaves the controls before sticks may affect playback.
	# Remember this on release so a tap does not immediately reopen the controls.
	if (
		host.viewer().geometry == Geometry.Geometry.FLAT
		and host.viewer().panel.visible
		and host.player_menu.visible
	):
		if point == null:
			point = host.viewer().screen_point(ray[0], ray[1])
		if (
			point != null
			and (
				corner >= 0
				or (
					absf(point.x) <= host.viewer()._flat.size.x / 2
					and absf(point.y) <= host.viewer()._flat.size.y / 2
				)
			)
		):
			_grab["hid_menu"] = true
			host.player_menu.dismiss()


func _update_grab() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if _grab.is_empty():
		return
	if host.view_follow.enabled and host.presentation_coordinator._head_pose() == null:
		_grab.clear()
		return
	if _grab.get("tap_only", false):
		return
	var ray: Variant = host.input_source.ray(_grab.hand)
	if (
		ray == null
		or not host.video
		or host.viewer().local_uri.is_empty()
		or host.library_menu.visible
	):
		_grab = {}
		return
	var direction: Vector3 = ray[1]
	if _grab.has("ray_length"):
		direction = (ray[0] + ray[1] * float(_grab.ray_length) - host.eye()).normalized()
	var angles = host.ray_angles(direction)
	var head: Variant = host.presentation_coordinator._head_pose()
	var local_drag: bool = (
		host.view_follow.enabled
		and host.presentation_coordinator._flat_followable(host.viewer())
		and head != null
	)
	if local_drag:
		angles = host.ray_angles(head.basis.inverse() * direction)
	if not _grab.moved:
		var start_angles: Vector2 = (
			host.ray_angles(head.basis.inverse() * _grab.start_direction)
			if local_drag
			else _grab.start
		)
		var turned: Vector2 = angles - start_angles
		turned.x = wrapf(turned.x, -PI, PI)
		if turned.length() < host.GRAB_START:
			return
		_grab.moved = true
	if _grab.has("resize"):
		# The corner follows the ray: the screen grows or shrinks about its centre.
		var point: Variant = host.viewer().screen_point(ray[0], ray[1])
		if point != null:
			host.viewer().set_screen_scale(
				(
					float(_grab.resize.start_scale)
					* Vector2(point.x, point.y).length()
					/ float(_grab.resize.start_length)
				)
			)
		return
	var last_angles: Vector2 = (
		host.ray_angles(head.basis.inverse() * _grab.last_direction) if local_drag else _grab.last
	)
	var step: Vector2 = angles - last_angles
	_grab.last = angles
	_grab.last_direction = direction
	host.presentation_coordinator._turn_picture(wrapf(step.x, -PI, PI), step.y)


func _apply_stick_actions(actions: Array[Dictionary], delta: float = 1.0 / 72.0) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	for action in actions:
		match action.operation:
			"zoom":
				host.video.zoom_view(float(action.amount) * host.ZOOM_SPEED * delta)
				if host.video.has_method("set_immersive_adjustment"):
					immersive.show_feedback("view_zoom", host.video.view_zoom, host.video.local_uri)
			"seek":
				host.video.seek_relative(int(action.get("delta_ms", int(action.direction) * 10000)))
			"audio_track":
				host.video.cycle_audio_track(int(action.direction))
			"subtitle":
				host.video.cycle_subtitle_track(int(action.direction))
			"swap_eyes":
				host.video.toggle_eye_order()
