extends RefCounted
## Owns controller/hand routing and drag state; the host supplies scene objects.

var _host_ref: WeakRef
const Log := preload("res://scripts/diagnostic_log.gd")
const HandPointer := preload("res://scripts/hand_pointer.gd")
const Geometry := preload("res://scripts/video_geometry.gd")
const LibraryMenu := preload("res://scripts/library_menu.gd")

var _grab := {}
var _library_grab := {}


func _init(host: Node3D) -> void:
	_host_ref = weakref(host)


func _unhandled_input(event: InputEvent) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.photo_active and host.photo.inspect:
		if event is InputEventMouseMotion:
			host._inspect_desktop_ray = [
				host.photo.view_camera.project_ray_origin(event.position),
				host.photo.view_camera.project_ray_normal(event.position)
			]
			host._update_photo_inspect()
		elif (
			event is InputEventMouseButton
			and event.pressed
			and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
		):
			host._close_photo_inspect()
		return
	if host._active_menu() or not host.video or host._viewer().local_uri.is_empty():
		return
	if host.photo_active and host.photo.gallery.mode != 0 and event is InputEventMouse:
		var origin: Vector3 = host.photo.view_camera.project_ray_origin(event.position)
		var direction: Vector3 = host.photo.view_camera.project_ray_normal(event.position)
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if host.photo.gallery.press_pointer("desktop", origin, direction):
					return
			elif host.photo.gallery.release_pointer("desktop", origin, direction):
				return
		elif event is InputEventMouseMotion:
			host.photo.gallery.update_pointer("desktop", origin, direction)
			if host.photo.gallery.has_capture():
				return
		elif (
			event is InputEventMouseButton
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
			and host.photo.gallery.overview()
		):
			host.photo.zoom_picture(0.08 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.08)
			return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		host._turn_picture(-event.relative.x * host.MOUSE_TURN, -event.relative.y * host.MOUSE_TURN)
	elif (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
	):
		var forward = 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		if host.photo_active:
			host._toggle_photo_inspect()
			if host.display.preview:
				host._inspect_desktop_ray = [
					host.photo.view_camera.project_ray_origin(event.position),
					host.photo.view_camera.project_ray_normal(event.position)
				]
			host._update_photo_inspect()
		elif host._viewer().geometry != Geometry.Geometry.FLAT:
			host._viewer().zoom_view(0.05 * forward)
		else:
			host._push_screen(0.1 * forward)
			host._save_screen()


func _unhandled_key_input(event: InputEvent) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if host.photo_active and host.photo.inspect and event.keycode in [KEY_ESCAPE, KEY_SPACE]:
			host._close_photo_inspect()
			return
		if event.keycode == KEY_TAB:
			host._toggle_player_menu()
			return
		var menu = host._active_menu()
		if menu:
			if OS.get_name() == "Android":
				return
			if event.keycode == KEY_ESCAPE:
				if menu.get("allow_user_dismiss") != false:
					menu.dismiss()
			elif menu == host.recent_menu:
				match event.keycode:
					KEY_UP:
						host.recent_menu.move_focus(-1)
					KEY_DOWN:
						host.recent_menu.move_focus(1)
					KEY_ENTER:
						host.recent_menu.activate_desktop()
			return
		if host.photo_active:
			match event.keycode:
				KEY_LEFT:
					if not host.photo.inspect:
						host.photo.navigate(-1)
				KEY_RIGHT:
					if not host.photo.inspect:
						host.photo.navigate(1)
				KEY_SPACE:
					host._toggle_photo_inspect()
				KEY_R:
					host._reset_picture()
				KEY_P:
					host.photo.cycle_projection()
				KEY_S:
					host.photo.toggle_stereo()
				KEY_E:
					host.photo.toggle_eye_order()
				KEY_O:
					host._show_recent_menu()
			return
		match event.keycode:
			KEY_T:
				host._toggle_display()
			KEY_R:
				host._recenter()
			KEY_D:
				host.request_capabilities()
			KEY_O:
				host._show_recent_menu()
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
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if not host._controller_allowed(hand):
		return
	host._on_pointer_release(action, hand)


func _on_pointer_release(action: String, hand: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if action == "grip_click" and host._library_grab.get("hand", "") == hand:
		if host._library_grab.get("moved", false):
			host.settings.set_value("ui", "library_distance", host.library_distance)
			host.settings.save(host.settings_path)
		host._library_grab.clear()
		return
	if action == "trigger_click" and host._inspect_blocked.has(hand):
		host._inspect_blocked.erase(hand)
		return
	if action in ["trigger_click", "grip_click"] and host._ray(hand) == null:
		host._cancel_pointer(hand)
		return
	if (
		action == "trigger_click"
		and host.photo_active
		and host.photo.gallery.capture.get("hand", "") == hand
	):
		var ray: Variant = host._ray(hand)
		host.photo.gallery.release_pointer(
			hand,
			ray[0] if ray != null else Vector3.ZERO,
			ray[1] if ray != null else Vector3.ZERO,
			ray != null
		)
		host.stick_controls.suspend()
		return
	if action == "trigger_click" and host._trigger_taps.has(hand):
		var tap: Dictionary = host._trigger_taps[hand]
		host._trigger_taps.erase(hand)
		if tap.uri == host._viewer().local_uri and tap.photo == host.photo_active:
			host._toggle_player_menu()
		return
	if (
		not host._grab.is_empty()
		and host._grab.hand == hand
		and action == host._grab.get("action", "trigger_click")
	):
		var grab = host._grab
		host._grab = {}
		host._viewer().set_corner_hover(-1)
		if (
			grab.moved
			and not grab.has("inspect")
			and host._viewer().geometry == Geometry.Geometry.FLAT
		):
			host._save_screen()
		if action == "trigger_click" and not grab.moved:
			if host.player_menu.visible:
				host.player_menu.dismiss()
			elif not grab.get("hid_menu", false):
				host._show_player_menu()
		return
	var menu = host._active_menu()
	if action != "trigger_click" or not menu or not menu.has_method("release_pointer"):
		return
	var ray: Variant = host._ray(hand)
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
	if not host._controller_allowed(hand):
		return
	host._on_pointer_button(action, hand)


func _on_pointer_button(action: String, hand: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host._inspect_blocked.has(hand):
		return
	if hand in ["left_hand", "right_hand"]:
		host._photo_pointer_hand = hand
	if host.photo_active and host.photo.inspect:
		if action in ["trigger_click", "by_button", "grip_click", "menu_button"]:
			if action == "trigger_click":
				host._inspect_blocked[hand] = true
			host._close_photo_inspect()
		elif action == "ax_button":
			host._close_photo_inspect(false)
			host._show_recent_menu()
		return
	if action == "menu_button":
		host._toggle_player_menu()
		return
	var menu = host._active_menu()
	if action == "grip_click":
		if menu == host.recent_menu and menu is LibraryMenu:
			host._begin_library_grab(hand)
			return
		if (
			not host._viewer().local_uri.is_empty()
			and host._ray(hand) != null
			and (menu == null or (menu == host.player_menu and not menu.has_pointer_capture()))
		):
			host._trigger_taps.clear()
			if menu == host.player_menu:
				menu.dismiss()
			host._begin_grab(hand, "grip_click")
		return
	if (
		action == "trigger_click"
		and (not host._library_grab.is_empty() or host._grab.get("action", "") == "grip_click")
	):
		return
	if menu:
		match action:
			"trigger_click":
				# An outside trigger tap dismisses controls without moving the picture.
				if not host._update_menu_pointer(hand, true) and menu == host.player_menu:
					var ray: Variant = host._ray(hand)
					# A slider owned by the other hand rejects this press; it is not a screen drag.
					if ray != null and menu.ray_hit(ray[0], ray[1]).is_empty():
						host._begin_picture_press(hand)
			"by_button":
				if menu.get("allow_user_dismiss") != false:
					menu.dismiss()
		return
	if host.photo_active:
		match action:
			"trigger_click":
				if host.photo.local_uri.is_empty():
					host._show_recent_menu()
				elif not host._grab.is_empty():
					return
				else:
					var ray: Variant = host._ray(hand)
					if ray != null and host.photo.gallery.press_pointer(hand, ray[0], ray[1]):
						host.stick_controls.suspend()
					else:
						host._begin_picture_press(hand)
			"ax_button":
				host._show_recent_menu()
			"primary_click":
				if hand == "left_hand":
					host.photo.cycle_projection()
				else:
					host._reset_picture()
		return
	match action:
		"trigger_click":
			if host._viewer().local_uri.is_empty():
				host._show_recent_menu()
			else:
				host._begin_picture_press(hand)
		"ax_button":
			host._show_recent_menu()
		"primary_click":
			if hand == "left_hand":
				host.video.cycle_projection()
			else:
				host._reset_picture()


func _process_sticks(left: Vector2, right: Vector2, delta: float) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if not host._library_grab.is_empty():
		host._update_library_grab_stick(left, right, delta)
		host._update_menu_pointer("left_hand")
		host._update_menu_pointer("right_hand")
		host.stick_controls.suspend()
		return
	if host._grab.get("action", "") == "grip_click":
		host.stick_controls.suspend()
		return
	if host.photo_active and host.photo.gallery.has_capture():
		host.stick_controls.suspend()
		return
	if host.photo_active and host.photo.inspect:
		host.stick_controls.suspend()
		return
	var menu = host._active_menu()
	if menu:
		host._update_menu_pointer("left_hand")
		host._update_menu_pointer("right_hand")
	if not host._input_focused():
		host.stick_controls.suspend()
		return
	if (
		host.photo_active
		and host.photo.geometry == Geometry.Geometry.FLAT
		and not host.photo_hands.owners.is_empty()
	):
		host.stick_controls.suspend()
		return
	if (
		menu
		and (
			menu != host.player_menu
			or host.photo_active
			or not host.player_menu.allows_playback_sticks()
		)
	):
		host.stick_controls.suspend()
		# Either stick scrolls a list, never selects or controls playback at the same time.
		if (
			menu.has_method("stick_scroll")
			and (menu != host.player_menu or not host.player_menu.has_pointer_capture())
		):
			menu.stick_scroll(left.y if absf(left.y) > absf(right.y) else right.y, delta)
		host._update_controls_visibility(menu)
		return
	var actions = host.stick_controls.poll(
		left,
		right,
		(
			host.video != null
			and (host.photo_active or host._viewer().geometry != Geometry.Geometry.FLAT)
		)
	)
	if not host._grab.is_empty():
		# Holding the picture: only zoom; other stick shortcuts wait for the stick to recenter.
		actions = actions.filter(func(action): return action.operation == "zoom")
	host._apply_stick_actions(actions, delta)
	if menu == host.player_menu and menu != null:
		if not actions.is_empty():
			host._menu_touched_ms = Time.get_ticks_msec()
			host.player_menu.refresh_values()
		host._update_controls_visibility(menu)


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
		host._menu_touched_ms = now
		return
	# Keep popups, sliders and pending seeks visible; use media state, not the seek queue's state.
	if (
		menu.section != 0
		or menu._mode_open
		or not menu._quick_open.is_empty()
		or not menu._adjustment.is_empty()
		or menu._depth_open
	):
		return
	if host.photo_active and host.photo_menu._layout_open:
		return
	if host.photo_active:
		if host.photo_menu._gallery_open:
			return
	else:
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
	if now - host._menu_touched_ms > host.CONTROLS_HIDE_MS:
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
			and host._controller_allowed(str(controller.tracker))
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


func _input_focused() -> bool:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return false
	return host.display.preview or host.display.session_state == "session_focussed"


func _controller_allowed(hand: String) -> bool:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return false
	if not host._input_focused():
		return false
	# Query current data too: XR input signals may arrive before our process callback.
	return (
		not HandPointer.is_optical(host._hand_tracker(hand))
		and not HandPointer.is_hand_profile(host._hand_action_tracker(hand))
		and not (host.hand_pointers.has(hand) and host.hand_pointers[hand].source == "hand")
	)


func _controller_ray(hand: String) -> Variant:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return null
	var controller = host.left_controller if hand == "left_hand" else host.right_controller
	if not controller or not controller.get_is_active() or not controller.get_has_tracking_data():
		return null
	var pose = controller.get_pose()
	if not pose or pose.tracking_confidence == XRPose.XR_TRACKING_CONFIDENCE_NONE:
		return null
	return [controller.global_position, -controller.global_basis.z]


func _update_hand_input(delta: float) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.input_visuals:
		host.input_visuals.update_visibility(host._input_focused() and host._head_tracked())
	var inputs = {}
	var wave_enabled: bool = (
		host.photo_active
		and host.photo.gallery.mode in [2, 3]
		and host.photo.gallery.focus < 0
		and not host.photo.portrait_requested
		and not host._active_menu()
		and host._input_focused()
	)
	for hand in host.hand_pointers:
		var sample = {}
		var point: Variant = null
		var palm = {}
		if host._input_focused():
			var tracker = host._hand_tracker(hand)
			if (
				HandPointer.is_optical(tracker)
				and host.xr_camera
				and host.xr_origin
				and host._head_tracked()
			):
				sample = HandPointer.sample(
					tracker,
					hand,
					host.xr_camera.global_transform,
					host.xr_origin.global_transform * XRServer.get_reference_frame(),
					XRServer.world_scale,
					host._meta_aim_tracker(hand),
					host._hand_action_tracker(hand)
				)
				point = HandPointer.pinch_position(
					tracker,
					host.xr_origin.global_transform * XRServer.get_reference_frame(),
					XRServer.world_scale
				)
				if wave_enabled:
					palm = HandPointer.sweep_sample(
						tracker,
						host.xr_camera.global_transform,
						host.xr_origin.global_transform * XRServer.get_reference_frame(),
						XRServer.world_scale,
						host._meta_aim_tracker(hand),
						host._hand_action_tracker(hand)
					)
			elif HandPointer.is_hand_profile(host._hand_action_tracker(hand)):
				# Action aim/select is independent of the optional hand-joint stream.
				# Runtimes may also expose controllers through a hand interaction profile.
				if host.xr_origin:
					sample = HandPointer.runtime_sample(
						host._hand_action_tracker(hand),
						host.xr_origin.global_transform * XRServer.get_reference_frame(),
						XRServer.world_scale,
						false
					)
			elif not HandPointer.is_optical(tracker):
				var ray: Variant = host._controller_ray(hand)
				if ray != null:
					sample = {"source": "controller", "ray": ray}
		var event: Dictionary = host.hand_pointers[hand].update(sample, delta)
		if event.cancelled:
			host._cancel_pointer(hand)
		if event.menu and hand == "left_hand":
			host._on_pointer_button("menu_button", hand)
		var pointer: RefCounted = host.hand_pointers[hand]
		inputs[hand] = event.merged(
			{
				"source": pointer.source,
				"tracked": pointer.ray != null,
				"down": pointer.down,
				"position": point,
				"palm": palm
			}
		)
		if host.hand_marks.has(hand):
			var mark: MeshInstance3D = host.hand_marks[hand]
			mark.visible = (
				pointer.source == "hand"
				and pointer.ray != null
				and not host._active_menu()
				and not host.photo_active
			)
			if mark.visible:
				mark.global_position = pointer.ray[0]
				mark.scale = Vector3.ONE * XRServer.world_scale * (0.65 if pointer.down else 1.0)
	host._dispatch_hand_input(inputs, delta)


func _is_photo_hand(hand: String) -> bool:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return false
	return (
		host.photo_active
		and host.photo != null
		and host.photo.geometry == Geometry.Geometry.FLAT
		and host.hand_pointers.has(hand)
		and host.hand_pointers[hand].source == "hand"
	)


func _dispatch_hand_input(inputs: Dictionary, _delta: float = 1.0 / 72.0) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.photo_active:
		inputs = inputs.duplicate(true)
		var overview_enabled: bool = (
			(
				host.photo.gallery.overview()
				or (
					host.photo.gallery.focus >= 0
					and host.photo.geometry == 0
					and host.photo.panel.visible
				)
			)
			and not host.photo.inspect
			and not host._active_menu()
			and host._input_focused()
			and host.photo_hands.owners.is_empty()
		)
		var zoom: Dictionary = host.photo.gallery.hand_zoom(inputs, overview_enabled)
		for hand in zoom.consumed:
			inputs.erase(hand)
		if not zoom.consumed.is_empty():
			host.stick_controls.suspend()
			host._grab = {}
		if zoom.finished:
			host._save_photo_adjustments()
		var wave_enabled: bool = (
			host.photo.gallery.overview()
			and overview_enabled
			and host.photo.gallery._swap_phase == 0
		)
		var head = host.xr_camera.global_transform if host.xr_camera else Transform3D.IDENTITY
		var waves: Array = host.memory_swipe.update(
			inputs,
			wave_enabled,
			(
				host.photo.gallery.has_capture()
				or inputs.values().any(func(input): return input.get("down", false))
			),
			head,
			XRServer.world_scale,
			_delta
		)
		for detail in host.memory_swipe.diagnostics:
			Log.record("memory_wave", detail)
		host.memory_swipe.diagnostics.clear()
		if not waves.is_empty():
			if host.photo.gallery.change_batch(int(waves[0].direction)):
				Log.record(
					"photo_batch",
					{"input": "wave", "hand": waves[0].hand, "layout": host.photo.gallery.mode}
				)
	if (
		host.photo_active
		and host.photo.gallery.mode != 0
		and not host.photo.inspect
		and not host._active_menu()
		and host._input_focused()
		and host.photo_hands.owners.is_empty()
	):
		inputs = inputs.duplicate(true)
		for hand in inputs.keys():
			if inputs[hand].get("source") != "hand":
				continue
			var ray: Variant = host._ray(hand)
			var reserved: bool = host.photo.gallery.capture.get("hand", "") == hand
			var hit: Dictionary = host.photo.gallery.ray_hit(ray[0], ray[1]) if ray != null else {}
			if (
				inputs[hand].get("pressed", false)
				and not hit.is_empty()
				and (
					host.photo.gallery.cards.has(int(hit.index))
					or int(hit.index) == host.photo.gallery.focus
				)
			):
				host.photo_hands.cancel()
				host._on_pointer_button("trigger_click", hand)
				reserved = true
			if reserved:
				if inputs[hand].get("released", false):
					host._on_pointer_release("trigger_click", hand)
				inputs.erase(hand)
	var flat_photo: bool = (
		host.photo_active and host.photo != null and host.photo.geometry == Geometry.Geometry.FLAT
	)
	var inspecting: bool = host.photo_active and host.photo != null and host.photo.inspect
	if inspecting:
		for hand in inputs:
			if inputs[hand].get("source") == "hand" and inputs[hand].get("pressed", false):
				for side in inputs:
					if inputs[side].get("down", false) or inputs[side].get("pressed", false):
						host._inspect_blocked[side] = true
				host._close_photo_inspect()
				break
	var enabled: bool = (
		flat_photo
		and (host.photo.panel.visible or host.photo.placeholder_visible())
		and host._input_focused()
		and not host._active_menu()
		and host._grab.is_empty()
		and not inspecting
		and not host.photo.inspect
		and host._inspect_blocked.is_empty()
	)
	var pose = host.xr_camera.global_basis if host.xr_camera else Basis.IDENTITY
	var result: Dictionary = host.photo_hands.update(
		inputs,
		enabled,
		host.photo.screen_scale if flat_photo else 1.0,
		pose,
		XRServer.world_scale,
		host.photo._serial if host.photo else -1
	)
	for action in result.actions:
		match action.operation:
			"tap":
				host._show_player_menu()
			"navigate":
				var accepted: bool = host.photo.navigate(int(action.direction))
				if action.has("hand"):
					Log.record(
						"photo_pinch_navigation",
						{"hand": action.hand, "direction": action.direction, "accepted": accepted}
					)
			"zoom":
				host.photo.finish_transition()
				host.photo.set_hand_scale(float(action.value))
			"finish":
				host._save_screen()
	if flat_photo and not result.actions.any(func(action): return action.operation == "navigate"):
		host.photo.preview_navigation(float(result.get("preview", 0.0)))
	for hand in inputs:
		if host._inspect_blocked.has(hand):
			if (
				inputs[hand].get("released", false)
				or inputs[hand].get("cancelled", false)
				or not inputs[hand].get("tracked", false)
				or not inputs[hand].get("down", false)
			):
				host._inspect_blocked.erase(hand)
			continue
		if hand in result.consumed:
			continue
		if inputs[hand].get("pressed", false):
			host._on_pointer_button("trigger_click", hand)
		if inputs[hand].get("released", false):
			host._on_pointer_release("trigger_click", hand)


func _cancel_pointer(hand: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host._library_grab.get("hand", "") == hand:
		host._library_grab.clear()
	if host.photo:
		host.photo.gallery.cancel_pointer(hand)
	host._inspect_blocked.erase(hand)
	host._trigger_taps.erase(hand)
	if not host._grab.is_empty() and host._grab.hand == hand:
		if (
			host._grab.moved
			and not host._grab.has("inspect")
			and host._viewer().geometry == Geometry.Geometry.FLAT
		):
			host._save_screen()
		host._grab = {}
		host._viewer().set_corner_hover(-1)
	# Cancellation never becomes a tap, row selection, or fling.
	for menu in [host.recent_menu, host.video_menu, host.photo_menu]:
		if is_instance_valid(menu) and menu.has_method("cancel_pointer"):
			menu.cancel_pointer(hand)


func _on_input_session_changed() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host._input_focused():
		return
	host._trigger_taps.clear()
	host.photo_hands.cancel()
	host.photo_swipe.cancel()
	host.memory_swipe.cancel()
	for hand in host.hand_pointers:
		host.hand_pointers[hand].update({}, 0)
		host._cancel_pointer(hand)
		if host.hand_marks.has(hand):
			host.hand_marks[hand].visible = false


func _hand_input_report() -> Dictionary:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return {}
	var report = {}
	for hand in host.hand_pointers:
		var pointer: RefCounted = host.hand_pointers[hand]
		var action = host._hand_action_tracker(hand)
		var joints = host._hand_tracker(hand)
		report[hand] = {
			"source": pointer.source,
			"provider": pointer.provider,
			"tracked": pointer.ray != null,
			"pinching": pointer.down,
			"profile": str(action.get_tracker_profile()) if action else "",
			"action_aim_tracked": host._input_pose_tracked(action, "aim"),
			"action_grip_tracked": host._input_pose_tracked(action, "grip"),
			"joint_tracking": joints != null and joints.has_tracking_data,
			"joint_source": int(joints.hand_tracking_source) if joints else -1
		}
	return report


func _begin_library_grab(hand: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if not host._library_grab.is_empty() or host.recent_menu.has_pointer_capture():
		return
	var ray: Variant = host._ray(hand)
	if ray == null:
		return
	var point: Variant = host.recent_menu._plane_point(ray[0], ray[1])
	if point == null or not Rect2(-1.1, -0.85, 2.05, 1.5).has_point(Vector2(point.x, point.y)):
		return
	var offset: Vector3 = host.recent_menu.global_position - host._eye()
	if offset.length() < .1:
		return
	host._trigger_taps.clear()
	host.stick_controls.suspend()
	host.recent_menu._fling = 0.0
	var ray_length: float = ray[0].distance_to(host.recent_menu.to_global(point))
	var direction: Vector3 = (ray[0] + ray[1] * ray_length - host._eye()).normalized()
	host._library_grab = {
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
	if host._library_grab.is_empty():
		return
	var ray: Variant = host._ray(host._library_grab.hand)
	if ray == null or not host.recent_menu.visible:
		host._library_grab.clear()
		return
	host.recent_menu._stick_ms = Time.get_ticks_msec()
	var direction: Vector3 = (
		(ray[0] + ray[1] * float(host._library_grab.ray_length) - host._eye()).normalized()
	)
	var head: Variant = host._head_pose()
	var frame: Basis = (
		host._menu_head_pose(head).basis
		if head != null and (host.view_follow.enabled or host.reclining_mode)
		else Basis.IDENTITY
	)
	var angles = host._ray_angles(frame.inverse() * direction)
	if not host._library_grab.dragged:
		var turned = angles - host._ray_angles(frame.inverse() * host._library_grab.start_direction)
		turned.x = wrapf(turned.x, -PI, PI)
		if not host.reclining_mode:
			turned.y = 0.0
		if turned.length() < host.GRAB_START:
			return
		host._library_grab.dragged = true
	var previous = host._ray_angles(frame.inverse() * host._library_grab.last_direction)
	host._library_grab.last_direction = direction
	host._library_grab.moved = true
	var pose = Transform3D(frame, host._eye()).affine_inverse() * host.recent_menu.global_transform
	var offset = pose.origin
	var placement = (
		host._ray_angles(offset)
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
	host.recent_menu.global_transform = Transform3D(frame, host._eye()) * pose
	host._on_menu_placement_changed(host.recent_menu)


func _update_library_grab_stick(left: Vector2, right: Vector2, delta: float) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if (
		host._library_grab.is_empty()
		or not host.recent_menu.visible
		or host._ray(host._library_grab.hand) == null
	):
		return
	var held = left if host._library_grab.hand == "left_hand" else right
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
	var offset = host.recent_menu.global_position - host._eye()
	if host.reclining_mode:
		host.recent_menu.global_position = host._eye() + offset.normalized() * distance
	else:
		var horizontal = Vector3(offset.x, 0, offset.z).normalized()
		host.recent_menu.global_position = (
			host._eye() + horizontal * distance + Vector3.UP * offset.y
		)
	host.library_distance = distance
	host._library_grab.moved = true
	host._on_menu_placement_changed(host.recent_menu)


func _begin_picture_press(hand: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host._ray(hand) == null:
		return
	if host.hand_pointers.has(hand) and host.hand_pointers[hand].source == "hand":
		host._begin_grab(hand, "trigger_click")
	else:
		host._trigger_taps[hand] = {"uri": host._viewer().local_uri, "photo": host.photo_active}


func _update_flat_grab_stick(left: Vector2, right: Vector2, delta: float) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if (
		host._active_menu()
		or host._grab.is_empty()
		or host._grab.has("resize")
		or host._grab.has("inspect")
		or host._grab.get("tap_only", false)
	):
		return
	var held = left if host._grab.hand == "left_hand" else right
	if not is_finite(held.y) or absf(held.y) <= host.STICK_DEADZONE:
		return
	var amount = (
		signf(held.y) * (absf(held.y) - host.STICK_DEADZONE) / (1.0 - host.STICK_DEADZONE) * delta
	)
	host._grab.moved = true
	if host._viewer().geometry != Geometry.Geometry.FLAT:
		host._viewer().zoom_view(-amount * host.ZOOM_SPEED)
	elif host._grab.get("action", "") == "grip_click" or host.photo_active:
		host._push_screen(amount * host.PUSH_SPEED)
	else:
		host.video.set_screen_scale(host.video.screen_scale * exp(amount * 0.8))


func _ray(hand: String) -> Variant:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return null
	if not host._input_focused():
		return null
	if host.hand_pointers.has(hand) and host.hand_pointers[hand].source == "hand":
		return host.hand_pointers[hand].ray
	if HandPointer.is_optical(host._hand_tracker(hand)):
		return null
	return host._controller_ray(hand)


func _update_corner_hover() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.photo_active and host.photo.gallery.overview():
		host.photo.set_corner_hover(-1)
		return
	if not host.video or not host._viewer().has_method("corner_at"):
		return
	var corner = -1
	if host._grab.has("resize"):
		corner = int(host._grab.resize.corner)
	elif (
		host._grab.is_empty()
		and not host.recent_menu.visible
		and not host._viewer().local_uri.is_empty()
		and not (host.photo_active and host.photo.inspect)
	):
		for hand in ["right_hand", "left_hand"]:
			if host._is_photo_hand(hand):
				continue
			var ray: Variant = host._ray(hand)
			if (
				ray != null
				and not (host.player_menu.visible and host.player_menu._hover.get(hand, -1) != -1)
			):
				corner = host._viewer().corner_at(ray[0], ray[1])
				if corner >= 0:
					break
	host._viewer().set_corner_hover(corner)


func _begin_grab(hand: String, action: String = "grip_click") -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if not host._grab.is_empty() or (host.photo_active and host.photo.inspect):
		return
	if host.view_follow.enabled and host._head_pose() == null:
		return
	var ray: Variant = host._ray(hand)
	if ray == null:
		if host.player_menu.visible:
			host.player_menu.dismiss()
		return
	var angles = host._ray_angles(ray[1])
	host._grab = {
		"hand": hand,
		"action": action,
		"start": angles,
		"last": angles,
		"moved": false,
		"start_direction": ray[1],
		"last_direction": ray[1]
	}
	if action == "grip_click":
		host._grab.ray_length = (
			maxf(.25, ray[0].distance_to(host._viewer().panel.global_position))
			if host._viewer().geometry == Geometry.Geometry.FLAT
			else 2.0
		)
		var direction: Vector3 = (
			(ray[0] + ray[1] * float(host._grab.ray_length) - host._eye()).normalized()
		)
		host._grab.start = host._ray_angles(direction)
		host._grab.last = host._grab.start
		host._grab.start_direction = direction
		host._grab.last_direction = direction
	if host._is_photo_hand(hand) or (host.photo_active and host.photo.gallery.overview()):
		host._grab["tap_only"] = true
		return
	var corner: int = host._viewer().corner_at(ray[0], ray[1])
	var point: Variant = host._viewer().screen_point(ray[0], ray[1]) if corner >= 0 else null
	if point != null and Vector2(point.x, point.y).length() > 0.05:
		host._grab["resize"] = {
			"corner": corner,
			"start_length": Vector2(point.x, point.y).length(),
			"start_scale": host._viewer().screen_scale
		}
	# A deliberate screen press leaves the controls before sticks may affect playback.
	# Remember this on release so a tap does not immediately reopen the controls.
	if (
		not host.photo_active
		and host._viewer().geometry == Geometry.Geometry.FLAT
		and host._viewer().panel.visible
		and host.player_menu.visible
	):
		if point == null:
			point = host._viewer().screen_point(ray[0], ray[1])
		if (
			point != null
			and (
				corner >= 0
				or (
					absf(point.x) <= host._viewer()._flat.size.x / 2
					and absf(point.y) <= host._viewer()._flat.size.y / 2
				)
			)
		):
			host._grab["hid_menu"] = true
			host.player_menu.dismiss()


func _update_grab() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host._grab.is_empty():
		return
	if host.view_follow.enabled and host._head_pose() == null:
		host._grab.clear()
		return
	if host._grab.get("tap_only", false):
		return
	var ray: Variant = host._ray(host._grab.hand)
	if (
		ray == null
		or not host.video
		or host._viewer().local_uri.is_empty()
		or host.recent_menu.visible
	):
		host._grab = {}
		return
	if host._grab.has("inspect"):
		host.photo.inspect_ray(ray[0], ray[1], true)
		return
	var direction: Vector3 = ray[1]
	if host._grab.has("ray_length"):
		direction = (ray[0] + ray[1] * float(host._grab.ray_length) - host._eye()).normalized()
	var angles = host._ray_angles(direction)
	var head: Variant = host._head_pose()
	var local_drag: bool = (
		host.view_follow.enabled and host._flat_followable(host._viewer()) and head != null
	)
	if local_drag:
		angles = host._ray_angles(head.basis.inverse() * direction)
	if not host._grab.moved:
		var start_angles: Vector2 = (
			host._ray_angles(head.basis.inverse() * host._grab.start_direction)
			if local_drag
			else host._grab.start
		)
		var turned: Vector2 = angles - start_angles
		turned.x = wrapf(turned.x, -PI, PI)
		if turned.length() < host.GRAB_START:
			return
		host._grab.moved = true
	if host._grab.has("resize"):
		# The corner follows the ray: the screen grows or shrinks about its centre.
		var point: Variant = host._viewer().screen_point(ray[0], ray[1])
		if point != null:
			host._viewer().set_screen_scale(
				(
					float(host._grab.resize.start_scale)
					* Vector2(point.x, point.y).length()
					/ float(host._grab.resize.start_length)
				)
			)
		return
	var last_angles: Vector2 = (
		host._ray_angles(head.basis.inverse() * host._grab.last_direction)
		if local_drag
		else host._grab.last
	)
	var step: Vector2 = angles - last_angles
	host._grab.last = angles
	host._grab.last_direction = direction
	host._turn_picture(wrapf(step.x, -PI, PI), step.y)


func _apply_stick_actions(actions: Array[Dictionary], delta: float = 1.0 / 72.0) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.photo_active:
		if host.photo.inspect:
			return
		for action in actions:
			if action.operation == "zoom":
				if (
					host.photo.geometry != Geometry.Geometry.FLAT
					and not host.photo.gallery.overview()
				):
					host._toggle_photo_inspect(
						"left_hand" if action.get("hand") == "left" else "right_hand"
					)
				else:
					host.photo.zoom_picture(float(action.amount) * host.ZOOM_SPEED * delta)
			elif (
				action.operation == "seek"
				and action.get("hand", "right") == "right"
				and not host.photo.inspect
			):
				host.photo.navigate(int(action.direction))
		return
	for action in actions:
		match action.operation:
			"zoom":
				host.video.zoom_view(float(action.amount) * host.ZOOM_SPEED * delta)
			"seek":
				host.video.seek_relative(int(action.get("delta_ms", int(action.direction) * 10000)))
			"audio_track":
				host.video.cycle_audio_track(int(action.direction))
			"subtitle":
				host.video.cycle_subtitle_track(int(action.direction))
			"swap_eyes":
				host.video.toggle_eye_order()
