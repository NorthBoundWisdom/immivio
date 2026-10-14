extends RefCounted
## Owns XR placement, following, recentering and menu presentation.

var _host_ref: WeakRef
const Log := preload("res://scripts/diagnostic_log.gd")
const Geometry := preload("res://scripts/video_geometry.gd")
const LibraryMenu := preload("res://scripts/library_menu.gd")
const PlayerMenu := preload("res://scripts/player_menu.gd")
const MediaSurface := preload("res://scripts/media_surface.gd")
const ViewFollow := preload("res://scripts/view_follow.gd")

var _head_placed := false
var _system_recenter_pending := false
var _system_recenter_last_notification_ms := -500
const SYSTEM_RECENTER_REPEAT_MS := 500
var _runtime_is_pico := OS.has_feature("pico")
var library_distance := 1.4
var view_follow := ViewFollow.new()
var temporary_passthrough := false
var reclining_mode := false
var _menu_touched_ms := 0


func _init(host: Node3D) -> void:
	_host_ref = weakref(host)


func _head_tracked() -> bool:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return false
	var head = XRServer.get_tracker("head") as XRPositionalTracker
	if not head or not head.has_pose("default"):
		return false
	var pose = head.get_pose("default")
	return pose.has_tracking_data and pose.tracking_confidence != XRPose.XR_TRACKING_CONFIDENCE_NONE


func _on_system_recentered() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	var now := Time.get_ticks_msec()
	var repeated := now - _system_recenter_last_notification_ms < SYSTEM_RECENTER_REPEAT_MS
	_system_recenter_last_notification_ms = now
	# A held Home button can send repeated notifications. Keep one request and
	# one placement; never enter a temporary head-follow or repeated placement.
	if host._system_recenter_pending or repeated:
		return
	Log.record("system_recentered", {"runtime": "pico" if _runtime_is_pico else "openxr"})
	host._library_grab.clear()
	host._grab.clear()
	host.stick_controls.suspend()
	host._system_recenter_pending = true
	_apply_system_recenter(true)


func _apply_system_recenter(same_frame: bool = false) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if not host._system_recenter_pending:
		return
	var head: Variant = host._head_pose()
	if not host._input_focused() or head == null:
		return
	# Godot 4.7.2 publishes pose_recentered after updating the head tracker and
	# XRCamera3D. Apply in that same frame, before the new space is rendered.
	host._recenter()
	Log.record("system_recenter_applied", {"same_frame": same_frame})


func _turn_picture(yaw: float, pitch: float) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.photo_active and host.photo.inspect:
		return
	if host.view_follow.enabled and host._head_pose() == null:
		return
	if is_zero_approx(yaw) and is_zero_approx(pitch):
		return
	if host._viewer().geometry != Geometry.Geometry.FLAT:
		host._viewer().turn_view(yaw, pitch)
		return
	var head: Variant = host._head_pose()
	if host.view_follow.enabled and host._flat_followable(host._viewer()) and head != null:
		var local: Transform3D = (
			head.affine_inverse() * (host._viewer().global_transform * host._viewer().flat_pose)
		)
		var offset = local.origin
		if offset.length() < 0.1:
			return
		var angles = host._ray_angles(offset) + Vector2(yaw, pitch)
		var direction = (
			(Basis(Vector3.UP, angles.x) * Basis(Vector3.RIGHT, clampf(angles.y, -1.5, 1.5)))
			* Vector3.FORWARD
		)
		local.basis = Basis(Quaternion(offset.normalized(), direction)) * local.basis
		local.origin = direction * offset.length()
		host._viewer().set_flat_world_pose(head * local)
		host._capture_follow_screen(host._viewer(), head)
		return
	var eye = host._eye()
	var offset: Vector3 = host._viewer().panel.global_position - eye
	var distance = offset.length()
	if distance < 0.1:
		return
	var angles = host._ray_angles(offset) + Vector2(yaw, pitch)
	var facing = Basis(Vector3.UP, angles.x) * Basis(Vector3.RIGHT, clampf(angles.y, -1.3, 1.3))
	host._viewer().flat_pose = (
		host._viewer().global_transform.affine_inverse()
		* Transform3D(facing, eye + facing * Vector3(0, 0, -distance))
	)
	host._viewer()._apply_geometry()


func _push_screen(amount: float) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.view_follow.enabled and host._head_pose() == null:
		return
	var eye = host._eye()
	var offset: Vector3 = host._viewer().panel.global_position - eye
	if offset.length() < 0.1:
		return
	host._viewer().set_screen_distance(offset.length() + amount)
	var pose = Transform3D(
		host._viewer().subtitle_transform().basis,
		eye + offset.normalized() * host._viewer().screen_distance
	)
	host._viewer().flat_pose = host._viewer().global_transform.affine_inverse() * pose
	host._viewer()._apply_geometry()
	host._capture_follow_screen(host._viewer(), host._head_pose())
	if host.photo_active and host.photo.gallery.focus >= 0:
		host.photo.gallery.focus_pose = host.photo.panel.global_transform


func _save_screen() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.photo_active:
		host._save_photo_adjustments()
		return
	host.settings.set_value("screen", "distance", host.video.screen_distance)
	host.settings.set_value("screen", "scale", host.video.screen_scale)
	host.settings.set_value("screen", "curve", host.video.screen_curve)
	host.settings.save(host.settings_path)


func _reset_picture() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	host._viewer().reset_view()
	host._viewer().set_screen_scale(1.0)
	var offset: Vector3 = host._viewer().panel.global_position - host._eye()
	var distance: float = (
		host.photo.DEFAULT_DISTANCE if host.photo_active else host.video.SCREEN_DISTANCE
	)
	if host._viewer().geometry == Geometry.Geometry.FLAT and offset.length() >= 0.1:
		host._push_screen(distance - offset.length())
	host._viewer().set_screen_distance(distance)
	host._save_screen()


func _update_menu_pointer(hand: String, pressed: bool = false) -> bool:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return false
	var menu = host._active_menu()
	if not menu or hand not in ["left_hand", "right_hand"]:
		return false
	var ray: Variant = host._ray(hand)
	var tracked = ray != null
	var origin: Vector3 = ray[0] if tracked else Vector3.ZERO
	var direction: Vector3 = ray[1] if tracked else Vector3.ZERO
	if pressed:
		host._menu_touched_ms = Time.get_ticks_msec()
		var handled: bool = menu.press_pointer(hand, origin, direction, tracked)
		if (
			menu != host.player_menu
			or host.photo_active
			or not host.player_menu.allows_playback_sticks()
		):
			host.stick_controls.suspend()
		return handled
	menu.update_pointer(hand, origin, direction, tracked)
	return true


func _canvas_menu_anchor_key() -> Array:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return []
	var viewer = host._viewer()
	# Content owns placement. Head pitch/roll/yaw must not rotate idle controls.
	# Immersive translation is handled separately; capture freezes the plane.
	var pose: Variant = (
		viewer.panel.global_transform
		if viewer.geometry == Geometry.Geometry.FLAT
		else viewer.subtitle_transform().basis
	)
	return [
		viewer.local_uri,
		viewer.geometry,
		pose,
		host.player_menu.section,
		host.photo_active,
		host.reclining_mode,
		(
			host.menu_compositor.native_placement_available()
			if is_instance_valid(host.menu_compositor)
			else false
		)
	]


func _head_pose() -> Variant:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return null
	var camera: Camera3D = host.xr_camera
	if not is_instance_valid(camera) and (host.video or host.photo):
		camera = host._viewer().view_camera
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return null
	if not host.display.preview and not host._head_tracked():
		return null
	var pose = camera.global_transform
	if not pose.is_finite():
		return null
	return Transform3D(pose.basis.orthonormalized(), pose.origin)


func _menu_head_pose(head: Transform3D) -> Transform3D:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return Transform3D.IDENTITY
	return head if host.reclining_mode else host._upright_pose(head)


func _view_pose(distance: float, drop: float) -> Variant:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return null
	var head: Variant = host._head_pose()
	if head == null:
		return null
	return host._menu_head_pose(head) * Transform3D(Basis.IDENTITY, Vector3(0, -drop, -distance))


func _place_screen(recenter: bool = false) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	var head: Variant = host._head_pose()
	var pose: Variant = host._view_pose(host._viewer().screen_distance, 0.0)
	if host.view_follow.enabled and host._flat_followable(host._viewer()) and head != null:
		pose = host._follow_screen_pose(host._viewer(), head, recenter)
	if pose != null:
		host._viewer().set_flat_world_pose(pose)
		if host._viewer().geometry == Geometry.Geometry.FLAT:
			host._viewer()._apply_geometry()


func _flat_followable(surface: Node3D) -> bool:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return false
	return (
		surface != null
		and surface.geometry == Geometry.Geometry.FLAT
		and (surface != host.photo or host.photo.gallery.mode == 0 or host.photo.portrait_requested)
	)


func _surface_key(surface: Node3D) -> StringName:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return StringName()
	return &"photo" if surface == host.photo else &"video"


func _menu_key(menu: Node3D) -> StringName:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return StringName()
	return StringName("menu_%d" % menu.get_instance_id())


func _follow_screen_pose(surface: Node3D, head: Transform3D, recenter: bool = false) -> Transform3D:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return Transform3D.IDENTITY
	var key = host._surface_key(surface)
	var saved: Variant = null if recenter else host.view_follow.pose(key, head)
	if saved != null:
		return saved
	var pose = head * Transform3D(Basis.IDENTITY, Vector3(0, 0, -surface.screen_distance))
	host.view_follow.capture(key, head, pose)
	return pose


func _capture_follow_screen(surface: Node3D, head: Variant) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if head != null and host.view_follow.enabled and host._flat_followable(surface):
		host.view_follow.capture(
			host._surface_key(surface), head, surface.global_transform * surface.flat_pose
		)


func _update_view_follow() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host._system_recenter_pending:
		return
	if not host.view_follow.enabled:
		return
	var head: Variant = host._head_pose()
	if head == null:
		return
	var menu_head = host._menu_head_pose(head)
	for menu in [host.recent_menu, host.video_menu, host.photo_menu]:
		if not menu or not menu.visible:
			continue
		# Immersive controls belong to the reset/content sphere, even in follow mode.
		if menu == host.player_menu and host._viewer().geometry != Geometry.Geometry.FLAT:
			continue
		var pose: Variant = host.view_follow.pose(host._menu_key(menu), menu_head)
		if pose == null:
			host.view_follow.capture(host._menu_key(menu), menu_head, menu.global_transform)
		else:
			menu.global_transform = pose
	var surface = host._viewer() if host.video or host.photo else null
	if (
		surface
		and host._flat_followable(surface)
		and (not surface.local_uri.is_empty() or (surface == host.photo and host.photo.loading))
	):
		surface.set_flat_world_pose(host._follow_screen_pose(surface, head))


func _place_menu(menu: Node3D) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	# A temporary tracking loss must not relocate menus to a world-origin fallback.
	var head: Variant = host._head_pose()
	if not host.display.preview and head == null:
		return
	var ui_scale = PlayerMenu.PANEL_SCALE if menu is PlayerMenu else Vector3.ONE
	if (
		menu == host.player_menu
		and not host._viewer().local_uri.is_empty()
		and is_instance_valid(host._viewer().get("panel"))
		and host._viewer().panel.visible
	):
		host.player_menu.lift_panels = true
		host.player_menu.panel_lift = 0.0 if host.photo_active else PlayerMenu.BAR_SEEK_Y
		host.player_menu.max_ray_metres = MediaSurface.DISTANCE_LIMITS.y + 1.0
		var pose: Transform3D
		var eye = host._eye()
		if host._viewer().geometry == Geometry.Geometry.FLAT:
			if menu is PlayerMenu:
				# Lower the transport bar while keeping expanded panels centred.
				host.player_menu.panel_lift += PlayerMenu.EXTRA_DROP / ui_scale.y
			pose = host._viewer().subtitle_transform()
			var toward_eye = eye - pose.origin
			var facing = pose.basis.orthonormalized()
			if not host.reclining_mode:
				var horizontal = Vector3(toward_eye.x, 0, toward_eye.z)
				facing = host._upright_pose(head).basis if head != null else Basis.IDENTITY
				if horizontal.length_squared() > .0001:
					facing = Basis.looking_at(-horizontal.normalized(), Vector3.UP)
			if toward_eye.length() > 0.1:
				var normal = toward_eye.normalized()
				# Native overlays keep readable distance; scene fallback needs clearance.
				var canvas_normal = pose.basis.z.normalized()
				var clearance = (
					.025
					+ absf(canvas_normal.dot(facing.x)) * .9 * ui_scale.x
					+ absf(canvas_normal.dot(facing.y)) * 1.1 * ui_scale.y
				)
				var offset = clearance / maxf(.1, absf(canvas_normal.dot(normal)))
				if (
					is_instance_valid(host.menu_compositor)
					and host.menu_compositor.native_placement_available()
				):
					offset = maxf(.025, toward_eye.length() - 1.4)
				if menu is PlayerMenu:
					offset += (toward_eye.length() - offset) * (1.0 - PlayerMenu.DISTANCE_SCALE)
				pose.origin += normal * minf(offset, maxf(.025, toward_eye.length() - .4))
			pose.basis = facing
		else:
			# Use the reset/content gaze, including pitch, but never later head tilt.
			pose = Transform3D(host._viewer().subtitle_transform().basis.orthonormalized(), eye)
			var distance: float = PlayerMenu.IMMERSIVE_DISTANCE if menu is PlayerMenu else 1.4
			var drop: float = PlayerMenu.IMMERSIVE_DROP if menu is PlayerMenu else 0.28
			pose.origin += pose.basis * Vector3(0, -drop, -distance)
		pose.basis *= Basis.from_scale(ui_scale)
		var bar_offset: float = (
			-host.player_menu.panel_lift if host.player_menu.section == 0 else 0.0
		)
		menu.global_transform = pose * Transform3D(Basis.IDENTITY, Vector3(0, bar_offset, 0))
		host._player_menu_anchor_key = host._canvas_menu_anchor_key()
		host._player_menu_anchor_eye = eye
		if head != null:
			host.view_follow.capture(
				host._menu_key(menu), host._menu_head_pose(head), menu.global_transform
			)
		return
	var drop = (
		(0.45 if host.player_menu.section == 0 else 0.0)
		if menu == host.player_menu
		else (0.0 if menu == host.recent_menu else 0.05)
	)
	if menu == host.player_menu:
		host.player_menu.lift_panels = true
		host.player_menu.panel_lift = 0.45
		host.player_menu.max_ray_metres = host.player_menu.MAX_RAY_METRES
	var distance = host.library_distance if menu == host.recent_menu else 1.4
	var pose: Variant = host._view_pose(distance, drop)
	if menu == host.recent_menu and head != null:
		# Keep the complete browser centre on an eye-height horizontal ring.
		# Pitch/roll affect orientation in reclining mode, never placement radius.
		var centre: Vector2 = menu.capture_envelope().get_center()
		var horizontal: Basis = host._upright_pose(head).basis
		pose = Transform3D(host._menu_head_pose(head).basis, head.origin - horizontal.z * distance)
		pose.origin -= pose.basis * Vector3(centre.x, centre.y, 0)
	if pose == null:
		menu.transform = Transform3D(Basis.from_scale(ui_scale), Vector3(0, 1.6 - drop, -1.55))
	else:
		pose.basis *= Basis.from_scale(ui_scale)
		menu.global_transform = pose
		host.view_follow.capture(host._menu_key(menu), host._menu_head_pose(head), pose)


func _active_menu() -> Node3D:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return null
	if host.recent_menu and host.recent_menu.visible:
		return host.recent_menu
	if host.player_menu and host.player_menu.visible:
		return host.player_menu
	return null


func _update_player_menu_anchor() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host._system_recenter_pending:
		return
	# Explicit head-follow owns menu placement, including captured interactions.
	if host.view_follow.enabled and host._viewer().geometry == Geometry.Geometry.FLAT:
		return
	# Keep controls attached when projection/distance/content changes. Freeze
	# the plane during a captured slider drag so its target cannot move away.
	if (
		host.player_menu
		and host._active_menu() == host.player_menu
		and not host.player_menu.has_pointer_capture()
		and not host._viewer().local_uri.is_empty()
		and is_instance_valid(host._viewer().get("panel"))
		and host._viewer().panel.visible
	):
		if host._canvas_menu_anchor_key() != host._player_menu_anchor_key:
			host._place_menu(host.player_menu)
		elif host._viewer().geometry != Geometry.Geometry.FLAT:
			var eye = host._eye()
			host.player_menu.global_position += eye - host._player_menu_anchor_eye
			host._player_menu_anchor_eye = eye


func _toggle_player_menu() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if (
		host.recent_menu
		and host.recent_menu.visible
		and host.recent_menu.get("allow_user_dismiss") == false
	):
		return
	host._trigger_taps.clear()
	if host.photo_active and host.photo.inspect:
		host._close_photo_inspect()
		return
	if host.player_menu and host.player_menu.visible:
		host.player_menu.dismiss()
	else:
		host._show_player_menu()


func _show_player_menu() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	host._library_grab.clear()
	host._queue_add_mode = false
	if host.recent_menu is LibraryMenu:
		host.recent_menu.queue_add_mode = false
	host.memory_swipe.cancel()
	if host.photo:
		host.photo.gallery.cancel_all()
	host._trigger_taps.clear()
	if host.recent_menu:
		host.recent_menu.dismiss()
	if host.player_menu and not host.player_menu.visible:
		host._place_menu(host.player_menu)
		host._menu_touched_ms = Time.get_ticks_msec()
		host.player_menu.toggle()


func _show_recent_menu(preserve_navigation: bool = false) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	host.memory_swipe.cancel()
	if host.photo:
		host.photo.gallery.cancel_all()
	host._trigger_taps.clear()
	if host.photo_active and host.photo.inspect:
		host._close_photo_inspect(false)
	if host.player_menu:
		host.player_menu.dismiss()
	if host.recent_menu and not host.recent_menu.visible:
		host._place_menu(host.recent_menu)
		if preserve_navigation:
			host.recent_menu.visible = true
			host.recent_menu.refresh()
		else:
			host.recent_menu.toggle()


func _canvas_controls_snapshot() -> Dictionary:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return {}
	var viewer = host._viewer()
	if not viewer or not is_instance_valid(viewer.get("panel")) or not host.player_menu:
		return {}
	var centre: Vector3 = viewer.panel.global_position
	var normal: Vector3 = viewer.subtitle_transform().basis.z
	var timeline: Vector3 = host.player_menu.to_global(Vector3(0, PlayerMenu.BAR_SEEK_Y, 0))
	var toward_eye = (host._eye() - timeline).normalized()
	var content_offset: Vector3 = (
		viewer.subtitle_transform().basis.orthonormalized().inverse() * (timeline - host._eye())
	)
	var view_normal: Vector3 = (
		viewer.view_camera.global_basis.z.normalized()
		if is_instance_valid(viewer.view_camera)
		else toward_eye
	)
	return {
		"grab_action": "grip_click",
		"controls_action": "trigger_click",
		"grab_hand": str(host._grab.get("hand", "")),
		"menu_visible": host.player_menu.visible,
		"canvas_origin": [centre.x, centre.y, centre.z],
		"canvas_normal": [normal.x, normal.y, normal.z],
		"timeline_centre": [timeline.x, timeline.y, timeline.z],
		"menu_section": host.player_menu.section,
		"menu_page": host.player_menu._adjustment,
		"menu_normal":
		[
			host.player_menu.global_basis.z.x,
			host.player_menu.global_basis.z.y,
			host.player_menu.global_basis.z.z
		],
		"menu_facing_eye_dot": host.player_menu.global_basis.z.normalized().dot(toward_eye),
		"menu_facing_view_dot": host.player_menu.global_basis.z.normalized().dot(view_normal),
		"menu_world_up_dot": host.player_menu.global_basis.y.normalized().dot(Vector3.UP),
		"menu_scale":
		[host.player_menu.global_basis.x.length(), host.player_menu.global_basis.y.length()],
		"menu_facing_content_dot":
		host.player_menu.global_basis.z.normalized().dot(normal.normalized()),
		"canvas_normal_up_dot": viewer.panel.global_basis.z.normalized().dot(Vector3.UP),
		"timeline_content_offset": [content_offset.x, content_offset.y, content_offset.z],
		"ui_compositor":
		host.menu_compositor.snapshot() if is_instance_valid(host.menu_compositor) else {},
		"canvas_horizontal_up_dot": viewer.panel.global_basis.x.normalized().dot(Vector3.UP),
		"scope":
		"Application pose/input state; physical button presses are not independently certified"
	}


func _menu_state() -> Dictionary:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return {}
	if not host.video:
		return {}
	var details: Dictionary = host.video.media.playback.get("details", {})
	var audio_options: Array = [{"value": -1, "label": "Auto"}]
	for track in details.get("audio_tracks", []):
		if track is Dictionary and int(track.get("id", 0)) > 0:
			var label = host._audio_option_label(track)
			var option = {"value": int(track.id), "label": label, "hint": label}
			if track.get("external", false) and str(track.get("title", "")) == "Clone voice":
				audio_options.insert(1, option)
			else:
				audio_options.append(option)
	audio_options.append({"value": 0, "label": "Off"})
	var text_tracks: Array = host.video.subtitle_tracks()
	var result = {
		"has_video":
		(
			not host.video.local_uri.is_empty()
			and host.video.media.accepts(host.video.media.session_id)
		),
		"has_previous_video": not host._adjacent_video(-1).is_empty(),
		"has_next_video": not host._adjacent_video(1).is_empty(),
		"playing": host.video.requested_play,
		"playback_state": host.video.media.state,
		"ai_enabled": false,
		"packed_file": host.video.packed_file,
		"alpha_requested": host.video.alpha_wanted(),
		"alpha_enabled": host.video.alpha_enabled,
		"loop": host.video.loop_enabled,
		"stereo": host.video.stereo_sbs,
		"swap_eyes": host.video.swap_eyes,
		"viewing_eye": host.video.viewing_eye,
		"stereo_horizontal": host.video.stereo_horizontal,
		"stereo_vertical": host.video.stereo_vertical,
		"top_bottom": host.video.stereo_sbs and host.video.top_bottom,
		"stereo_half": host.video.stereo_sbs and host.video.stereo_half,
		"fisheye_fov": host.video.fisheye_fov,
		"projection": ["Flat", "VR180", "Fisheye", "360"][host.video.geometry],
		"geometry": host.video.geometry,
		"profile": host.video.profile,
		"mode_lock": host.video.mode_lock,
		"spatial_video": host.video.is_spatial_video(),
		"audio_available": details.get("audio_tracks", []).size() > 0,
		"audio_options": audio_options,
		"audio_track_id": host.video.audio_track_id,
		"subtitle_delay_ms": host.video.subtitle_delay_ms,
		"audio_delay_ms": host.video.audio_delay_ms,
		"external_subtitle": not host.video.external_subtitle_uri.is_empty(),
		"subtitle_loading": host.video._subtitle_loading or host.video._subtitle_pick > 0,
		"queue_items": host.video_queue,
		"queue_revision": host.playback_queue.revision,
		"queue_shuffle": host.playback_queue.shuffle,
		"audio_tracks": details.get("audio_tracks", []).size(),
		"audio_track": host._audio_track_name(details),
		"clone_voice": host.video.clone_voice_track() > 0,
		"clone_voice_active": host.video.clone_voice_active(),
		"depth_requested": host.video.depth_requested,
		"depth_enabled": host.video.depth_enabled,
		"depth_strength": host.video.depth_strength,
		"screen_curve": host.video.screen_curve,
		"screen_distance": host.video.screen_distance,
		"screen_scale": host.video.screen_scale * 100.0,
		"screen_rotation": host.video.screen_rotation,
		"playback_speed": host.video.playback_speed,
		"show_fps": host.fps_overlay != null and host.fps_overlay.visible,
		"subtitle_palette": host.video.subtitle_palette,
		"subtitle_size": host.video.subtitle_size * 100,
		"subtitle_flat_position": host.video.subtitle_flat_position * 100,
		"subtitle_distance": host.video.subtitle_distance,
		"color_grade": host.video.color_grade.snapshot(),
		"subtitle_position": host.video.subtitle_position,
		"subtitle_direction": host.video.subtitle_direction,
		"grade_values": host.video.color_grade.values(),
		"depth_error": str(host.video.media.playback.get("depth_error", "")),
		"text_subtitle_tracks": text_tracks.size(),
		"subtitle_options": text_tracks,
		"subtitle_track": host.video.subtitles.requested_track,
		"source_uri": host.video.local_uri,
		"title": host.video.display_name,
		"source_size":
		(
			"%s x %s"
			% [
				host.video.media.format.get("width", "?"),
				host.video.media.format.get("height", "?")
			]
		),
		"codec": details.get("codec", "Unknown codec"),
		"position_ms": host.video.control.display_position_ms(),
		"duration_ms": host.video.control.duration_ms,
		"xr_state": "Desktop preview" if host.display.preview else host.display.session_state,
		"capabilities_available": host.platform_plugin != null,
		"error": host._menu_error()
	}
	result.merge(host.video.bookmarks_snapshot())
	return result


func _toggle_display() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.photo_active:
		host._on_photo_action("photo_portrait")
		return
	if not host.video.local_uri.is_empty():
		host.video.set_alpha(not host.video.alpha_wanted())
	else:
		host.background.select("dark" if host.background.choice == "passthrough" else "passthrough")
		host._save_background()
	host._save_report()


func _on_background_changed() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	host._update_background()
	if (
		host.recent_menu
		and host.recent_menu.visible
		and host.recent_menu.section == host.recent_menu.Section.SETTINGS
		and host.recent_menu.tab == host.recent_menu.BACKGROUND_TAB
	):
		host.recent_menu.refresh()


func _update_background() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if not host.background or not host.display.environment:
		return
	var immersive = false
	var alpha = false
	if host.photo_active and host.photo:
		immersive = (
			not host.photo.local_uri.is_empty() and host.photo.geometry != Geometry.Geometry.FLAT
		)
		alpha = host.photo.portrait_requested or host.photo.portrait_enabled
	elif host.video:
		var active: bool = host.video.has_active_presentation()
		alpha = active and (host.video.alpha_wanted() or host.video.alpha_enabled)
		immersive = active and host.video.geometry != Geometry.Geometry.FLAT
	# Alpha temporarily overrides the saved scenery. An explicit passthrough choice
	# also applies behind immersive media, including the unused half of VR180.
	var wants_passthrough: bool = (
		alpha or host.temporary_passthrough or host.background.choice == "passthrough"
	)
	host.display.set_scenery(
		null if immersive or wants_passthrough else host.background.ready_sky(), host.background.yaw
	)
	var passthrough: bool = wants_passthrough and host.display.supports_passthrough()
	if (
		host.display.applied_passthrough != passthrough
		or host.display.requested_passthrough != passthrough
	):
		host.display.set_passthrough(passthrough)
	host._refresh_session_controls()


func _connect_session_controls(menu: Node3D) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	menu.session_controls_provider = host._session_controls_state
	menu.session_control_requested.connect(host._on_session_control)
	menu.placement_changed.connect(host._on_menu_placement_changed.bind(menu))


func _on_menu_placement_changed(menu: Node3D) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	var head: Variant = host._head_pose()
	if head != null:
		host.view_follow.capture(
			host._menu_key(menu), host._menu_head_pose(head), menu.global_transform
		)


func _set_reclining_mode(enabled: bool) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	if host.reclining_mode == enabled:
		return
	host._update_view_follow()
	host.reclining_mode = enabled
	host.video.reclining_mode = enabled
	var head: Variant = host._head_pose()
	if host.video.geometry == Geometry.Geometry.FLAT:
		if enabled and not host.video.local_uri.is_empty() and head != null:
			# Face the current gaze immediately, without enabling continuous follow.
			host.video.set_flat_world_pose(
				head * Transform3D(Basis.IDENTITY, Vector3(0, 0, -host.video.screen_distance))
			)
		else:
			host.video._apply_flat_pose()
		host._capture_follow_screen(host.video, head)
	for menu in [host.recent_menu, host.video_menu, host.photo_menu]:
		if menu and menu.visible:
			host._place_menu(menu)


func _person_passthrough() -> bool:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return false
	if host.photo_active and host.photo:
		return host.photo.portrait_requested or host.photo.portrait_enabled
	return (
		not host.photo_active
		and host.video != null
		and host.video.has_active_presentation()
		and (host.video.alpha_wanted() or host.video.alpha_enabled)
	)


func _session_controls_state() -> Dictionary:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return {}
	return {
		"follow": host.view_follow.enabled,
		"passthrough_visible":
		(
			host.background != null
			and host.background.choice != "passthrough"
			and host.display.supports_passthrough()
		),
		"passthrough": host.display.applied_passthrough,
		"alpha": host._person_passthrough()
	}


func _refresh_session_controls() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	for menu in [host.recent_menu, host.video_menu, host.photo_menu]:
		if menu and menu.visible:
			menu.refresh_session_controls()


func _on_session_control(operation: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	host._menu_touched_ms = Time.get_ticks_msec()
	if operation == "temporary_passthrough":
		if (
			host._person_passthrough()
			or not host.background
			or host.background.choice == "passthrough"
			or not host.display.supports_passthrough()
		):
			return
		var previous = host.temporary_passthrough
		host.temporary_passthrough = not previous
		host._update_background()
		if host.temporary_passthrough and not host.display.applied_passthrough:
			host.temporary_passthrough = previous
			host._update_background()
	elif operation == "follow":
		host._update_view_follow()
		host.view_follow.set_enabled(not host.view_follow.enabled)
		host._library_grab.clear()
		host._grab.clear()
		host.photo_hands.cancel()
		host.photo_swipe.cancel()
		host.memory_swipe.cancel()
		host.stick_controls.suspend()
		var head: Variant = host._head_pose()
		if host.view_follow.enabled and head != null:
			for menu in [host.recent_menu, host.video_menu, host.photo_menu]:
				if menu and menu.visible:
					host.view_follow.capture(
						host._menu_key(menu), host._menu_head_pose(head), menu.global_transform
					)
			var surface = host._viewer()
			if host._flat_followable(surface) and not surface.local_uri.is_empty():
				var local: Vector3 = (
					head.affine_inverse() * (surface.global_transform * surface.flat_pose).origin
				)
				if (
					local.z < -0.1
					and absf(local.x / local.z) < 1.0
					and absf(local.y / local.z) < 0.9
				):
					host._capture_follow_screen(surface, head)
				else:
					host._place_screen(true)
		Log.record("view_follow_changed", {"enabled": host.view_follow.enabled})
	host._refresh_session_controls()


func _recenter() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host):
		return
	host._system_recenter_pending = false
	host._library_grab.clear()
	host._grab.clear()
	host.photo_hands.cancel()
	host.photo_swipe.cancel()
	host.memory_swipe.cancel()
	if not host._viewer().local_uri.is_empty():
		host._place_screen(true)
		if host._viewer().geometry != Geometry.Geometry.FLAT:
			host._viewer().reset_view()
	if host.photo_active:
		host.photo.gallery.recenter()
		if host.photo.inspect:
			host.photo._place_detail()
	for menu in [host.recent_menu, host.player_menu]:
		if menu and menu.visible:
			host._place_menu(menu)
	if is_instance_valid(host.menu_compositor):
		host.menu_compositor.refresh_placement()
	Log.record("recenter_requested")
