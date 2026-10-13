extends SceneTree
const Main := preload("res://scripts/main.gd")
const Menu := preload("res://scripts/ray_menu.gd")
const PlayerMenu := preload("res://scripts/player_menu.gd")
const HostTest := preload("res://tests/test_player_menu.gd")
const Memory := preload("res://scripts/file_mode_memory.gd")
const Catalog := preload("res://scripts/recent_files.gd")
const I18n := preload("res://scripts/i18n.gd")
var checks := 0
var failures: Array[String] = []
var directory := ProjectSettings.globalize_path("res://../../build/output/view-follow")

class SupportedDisplay extends XrDisplay:
	var supported := true
	var reject := false
	func supports_passthrough() -> bool: return supported
	func set_passthrough(enabled: bool) -> bool:
		if reject and enabled:
			requested_passthrough = true # A runtime rejects applying the requested blend mode.
			return false
		return super.set_passthrough(enabled)

class FollowMain extends Main:
	var tracked := true
	func _head_tracked() -> bool: return tracked
	var test_ray: Variant
	func _ray(hand: String) -> Variant:
		return test_ray if test_ray != null else super._ray(hand)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void: _run.call_deferred()

func button(menu: Node3D, target: int) -> Dictionary:
	for item in menu._buttons:
		if item.target == target: return item
	return {}

func click(menu: Node3D, target: int) -> bool:
	var item := button(menu, target)
	if item.is_empty(): return false
	var origin: Vector3 = item.node.global_position + item.node.global_basis.z * 0.25
	return menu.press_pointer("right_hand", origin, -item.node.global_basis.z, true)

func placement(main: Node3D, surface: Node3D) -> Transform3D:
	return main.xr_camera.global_transform.affine_inverse() * (surface.global_transform * surface.flat_pose)

func footer_check(menu: Node3D, name: String) -> void:
	var close := button(menu, Menu.CLOSE_MENU)
	var follow := button(menu, Menu.FOLLOW)
	var pass_button := button(menu, Menu.TEMP_PASSTHROUGH)
	if menu is PlayerMenu:
		check(follow.is_empty() and pass_button.is_empty(), name + " omits session toggles during video playback")
		check(menu.device_status.position.y > (menu.BAR_SEEK_Y if menu.section == 0 else menu._backdrop.position.y), name + " status is above playback content")
		return
	check(not follow.is_empty() and not pass_button.is_empty(), name + " includes both global footer controls")
	if follow.is_empty() or pass_button.is_empty(): return
	check(close.is_empty(), name + " footer omits the duplicate close control")
	check(not follow.rect.intersects(pass_button.rect), name + " has separate ray targets")
	check(is_equal_approx(follow.node.position.y, pass_button.node.position.y) and is_equal_approx(follow.node.position.y, menu.device_status.position.y), name + " footer and status use one row")
	check(is_equal_approx(follow.node.mesh.size.y, menu.device_status.HEIGHT), name + " controls and status have matching heights")
	check(follow.node.position.y + Menu.FOOTER_HIT_SIZE / 2 < menu._backdrop.position.y - menu._backdrop.mesh.size.y / 2,
		name + " controls clear the panel")
	for other in menu._buttons:
		if other.target in [Menu.CLOSE_MENU, Menu.FOLLOW, Menu.TEMP_PASSTHROUGH] or other.node.get_parent() != menu: continue
		check(not follow.rect.intersects(other.rect) and not pass_button.rect.intersects(other.rect), name + " footer does not overlap target " + str(other.target))
		if not close.is_empty(): check(not close.rect.intersects(other.rect), name + " close target does not overlap " + str(other.target))

func close_menu_check(main: Node3D, menu: Node3D, name: String) -> void:
	check(button(menu, Menu.CLOSE_MENU).is_empty(), name + " omits close menu button")
	var state: bool = main.view_follow.enabled
	var poses: Dictionary = main.view_follow._poses.duplicate()
	var passthrough: bool = main.temporary_passthrough
	var alpha: bool = main.video.alpha_wanted()
	var video_state: String = main.video.media.state
	var photo_uri: String = main.photo.local_uri
	main._on_pointer_button("by_button", "right_hand")
	if menu == main.recent_menu:
		check(menu.visible and main._active_menu() == menu, name + " cannot dismiss library with a controller button")
		main._toggle_player_menu()
		check(menu.visible, name + " menu button cannot replace library with empty controls")
	else:
		check(not menu.visible and main._active_menu() == null and menu._hover.is_empty(), name + " playback controls still dismiss via controller")
	check(main._grab.is_empty(), name + " dismissal cannot start a screen drag")
	check(main.view_follow.enabled == state and main.view_follow._poses == poses and main.temporary_passthrough == passthrough,
		name + " retains session choices and saved head offsets")
	check(main.video.media.state == video_state and main.video.alpha_wanted() == alpha and main.photo.local_uri == photo_uri,
		name + " does not close or change media")
	main.test_ray = null

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var config := ConfigFile.new()
	config.set_value("appearance", "background", "dark")
	config.set_value("ui", "language", "en")
	config.set_value("ui", "follow", true) # Legacy/foreign state must never enable it at startup.
	config.save(directory.path_join("settings.cfg"))
	var main := FollowMain.new()
	main.settings_path = directory.path_join("settings.cfg")
	main.display = SupportedDisplay.new()
	root.add_child(main)
	main.set_process(false); main.video.set_process(false); main.photo.set_process(false)
	main.report_timer.stop()
	main.video.platform = HostTest.Host.new()
	main.video.mode_memory = Memory.new(directory.path_join("modes.cfg"))
	main.video.recent_files = Catalog.new(directory.path_join("recent.cfg"))
	main.video.load_mode_lock({})
	check(not main.view_follow.enabled and not main.temporary_passthrough, "Every startup disables session modes")
	check(not main.reclining_mode and not main.video.reclining_mode and not main._library_settings().reclining_mode,
		"Reclining mode is off by default in settings and video placement")
	check(button(main.recent_menu, Menu.FOLLOW).base_color == Menu.TILE, "Initial follow button is off")
	footer_check(main.recent_menu, "Empty library")
	check(click(main.recent_menu, Menu.TEMP_PASSTHROUGH) and main.temporary_passthrough and main.display.applied_passthrough,
		"Empty library can enable temporary passthrough")
	check(main.background.choice == "dark" and main.settings.get_value("appearance", "background") == "dark", "Temporary passthrough does not save background")
	click(main.recent_menu, Menu.TEMP_PASSTHROUGH)
	check(not main.temporary_passthrough and not main.display.applied_passthrough, "Temporary passthrough disables independently")
	click(main.recent_menu, Menu.FOLLOW)
	check(main.view_follow.enabled and not main.temporary_passthrough, "Follow can enable without media/background coupling")
	var upright_library := main.recent_menu.global_transform
	main.xr_camera.rotation.x += .8; main.xr_camera.rotation.z += .4
	main._update_view_follow()
	check(main.recent_menu.global_transform.is_equal_approx(upright_library), "Pitch and roll cannot move or tilt a following library")
	var menu_local: Transform3D = Main._upright_pose(main.xr_camera.global_transform).affine_inverse() * main.recent_menu.global_transform
	main.xr_camera.transform = Transform3D(Basis.from_euler(Vector3(1.55, .4, .6)), Vector3(1, .4, 2))
	main._update_view_follow()
	check((Main._upright_pose(main.xr_camera.global_transform).affine_inverse() * main.recent_menu.global_transform).is_equal_approx(menu_local), "Library follows horizontal head direction/translation while retaining its upright pose")
	main._on_library_chosen("file:///follow/first_2D.mp4", "first_2D.mp4")
	main._place_screen()
	check(placement(main, main.video).origin.is_equal_approx(Vector3(0,0,-main.video.screen_distance)) and absf(main.video.panel.global_basis.z.y) < .00001, "Opening flat video follows gaze position with a world-vertical screen")
	main._turn_picture(.25, -.15)
	main._push_screen(.6)
	main.video.set_screen_scale(1.4); main.video.set_screen_curve(.7); main.video.set_screen_rotation(25)
	main.video.panel.visible = true # A decoded frame has now been presented.
	var screen_local := placement(main, main.video)
	var scale: float = main.video.screen_scale
	main.video.subtitles.text = "Head-relative caption"
	main.video.caption.text = main.video.subtitles.text
	main.video.caption.visible = true
	main.video._place_caption()
	var caption_local: Transform3D = main.video.subtitle_transform().affine_inverse() * main.video.caption.global_transform
	main.video.material.set_shader_parameter("bitmap_subtitle_enabled", true)
	main.video._sync_subtitle_surface()
	for pose in [Transform3D(Basis.from_euler(Vector3(0,0,0)),Vector3(0,1.6,0)),
		Transform3D(Basis.from_euler(Vector3(PI/2, .8, PI/2)),Vector3(4,.3,2)),
		Transform3D(Basis.from_euler(Vector3(-1.55,-.5,-.8)),Vector3(-3,1,-4))]:
		main.xr_camera.transform = pose
		main._update_view_follow()
		check(placement(main, main.video).origin.is_equal_approx(screen_local.origin) and absf(main.video.panel.global_basis.z.y) < .00001, "Video position follows the head while its screen remains world-vertical")
		check((main.video.subtitle_transform().affine_inverse() * main.video.caption.global_transform).is_equal_approx(caption_local), "Flat text subtitle follows its screen")
		check(main.video._subtitle_surface.global_transform.is_equal_approx(main.video.subtitle_transform()), "Rotated content's separate subtitle surface follows")
		check(main.video.screen_scale == scale and main.video.screen_curve == .7 and main.video.screen_rotation == 25, "Head movement preserves size/curve/content rotation")
	main._show_recent_menu()
	var before := placement(main, main.video)
	main._show_player_menu()
	check(placement(main, main.video).is_equal_approx(before), "Menu summons do not move screen")
	check(main.video_menu.global_basis.y.normalized().is_equal_approx(Vector3.UP), "Player summon remains vertical with head tilt and roll")
	footer_check(main.video_menu, "Player bar")
	var bar_local: Transform3D = Main._upright_pose(main.xr_camera.global_transform).affine_inverse() * main.video_menu.global_transform
	for target in [main.video_menu.QUICK_SPEED, main.video_menu.QUICK_COLOR, main.video_menu.SYNC_SETTINGS, main.video_menu.QUEUE_SETTINGS, 12]:
		main.video_menu._activate(target); main._update_view_follow()
		check((Main._upright_pose(main.xr_camera.global_transform).affine_inverse() * main.video_menu.global_transform).is_equal_approx(bar_local), "Popup switching does not lift or move the toolbar")
		footer_check(main.video_menu, "Player popup")
	main.video_menu._activate(main.video_menu.QUICK_CLOSE)
	main.video_menu._seek_hand = "left_hand"
	var captured_menu: Transform3D = Main._upright_pose(main.xr_camera.global_transform).affine_inverse() * main.video_menu.global_transform
	var captured_screen := placement(main,main.video)
	main.xr_camera.rotate_z(.2); main._update_view_follow(); main._update_player_menu_anchor()
	check((Main._upright_pose(main.xr_camera.global_transform).affine_inverse() * main.video_menu.global_transform).is_equal_approx(captured_menu)
		and placement(main,main.video).origin.is_equal_approx(captured_screen.origin) and absf(main.video.panel.global_basis.z.y) < .00001, "Timeline capture keeps strict menu/screen follow during head movement")
	check(main.video_menu.global_basis.y.normalized().is_equal_approx(Vector3.UP), "Follow cannot tilt a captured playback panel")
	main.video_menu._seek_hand = ""
	main._recenter()
	check(placement(main, main.video).origin.is_equal_approx(Vector3(0,0,-main.video.screen_distance)) and main.view_follow.enabled,
		"Follow recenter updates only screen's local placement")
	check(main.video.screen_scale == scale and main.video.screen_rotation == 25, "Recenter preserves size and content rotation")
	screen_local = placement(main, main.video)
	main._on_library_chosen("file:///follow/next_2D.mp4", "next_2D.mp4")
	main._place_screen()
	check(main.view_follow.enabled and placement(main, main.video).origin.is_equal_approx(screen_local.origin) and absf(main.video.panel.global_basis.z.y) < .00001, "Changing flat media preserves follow pose")
	main.video.set_projection(3)
	var sphere_basis: Basis = main.video.panel.global_basis
	main.xr_camera.rotate_y(.4); main._update_view_follow(); main.video._process(0)
	check(main.view_follow.enabled and main.video.panel.global_basis.is_equal_approx(sphere_basis), "Immersive media is not head-locked, mode stays on")
	main.video.set_projection(0); main._update_view_follow()
	check(placement(main, main.video).origin.is_equal_approx(screen_local.origin) and absf(main.video.panel.global_basis.z.y) < .00001, "Returning flat restores saved position with upright orientation")
	main._on_session_control("temporary_passthrough")
	main._on_menu_action("stop")
	main._show_recent_menu()
	check(main.view_follow.enabled and main.temporary_passthrough, "Stopping and browsing retain both session choices")
	for section in range(main.recent_menu.NAV.size()):
		main.recent_menu.section = section; main.recent_menu.refresh()
		footer_check(main.recent_menu, "Library section " + str(section))
	main.recent_menu.file_actions.modal = "delete"
	main.recent_menu.file_actions.target = {"title":"Example.mp4", "uri":"file:///Example.mp4"}
	main.recent_menu.refresh()
	footer_check(main.recent_menu, "File confirmation")
	main.recent_menu.file_actions.modal = ""
	main.recent_menu.refresh()
	main._on_library_chosen("file:///follow/clip_LR_180_FISHEYE_F180_alpha.mp4", "clip_LR_180_FISHEYE_F180_alpha.mp4")
	for original in [false,true]:
		main.temporary_passthrough = original
		main.video.set_alpha(true)
		check(main._person_passthrough() and main.display.applied_passthrough, "Person passthrough forces actual transparent state")
		main._show_recent_menu(); main.recent_menu.refresh()
		var item := button(main.recent_menu, Menu.TEMP_PASSTHROUGH)
		check(not item.enabled and not item.node.visible, "Person mode hides the unavailable temporary passthrough button")
		var origin: Vector3 = item.node.global_position + item.node.global_basis.z * .25
		main.recent_menu.update_pointer("right_hand", origin, -item.node.global_basis.z, true)
		check(main.recent_menu._hover.right_hand == Menu.NONE and (not main.recent_menu._tooltip or not main.recent_menu._tooltip.visible), "Hidden unavailable button has no ray hover or tooltip")
		click(main.recent_menu, Menu.TEMP_PASSTHROUGH)
		main._on_session_control("temporary_passthrough")
		check(main.temporary_passthrough == original and main.video.alpha_wanted(), "Neither click nor direct action changes temporary request or Alpha")
		var follow: bool = main.view_follow.enabled
		click(main.recent_menu, Menu.FOLLOW)
		check(main.view_follow.enabled != follow, "Follow remains operable during person passthrough")
		main.video.set_alpha(false)
		check(main.temporary_passthrough == original and main.display.applied_passthrough == original and button(main.recent_menu, Menu.TEMP_PASSTHROUGH).enabled,
			"Leaving person mode restores original temporary choice and operability")
	main.temporary_passthrough = false; main._update_background()
	main.display.reject = true
	main._on_session_control("temporary_passthrough")
	check(not main.temporary_passthrough and not main.display.applied_passthrough and not main.display.requested_passthrough, "Rejected passthrough cancels pending runtime request and cannot show false success")
	main.display._on_session_event("session_focussed")
	check(not main.display.applied_passthrough, "Session resume cannot retry a rejected temporary request")
	main.display.reject = false
	main._on_setting_changed("background", "passthrough")
	check(button(main.recent_menu, Menu.TEMP_PASSTHROUGH).is_empty() and not button(main.recent_menu, Menu.FOLLOW).is_empty(), "Saved passthrough hides only temporary control")
	main._on_setting_changed("background", "dark")
	main.display.supported = false; main._update_background()
	check(button(main.recent_menu, Menu.TEMP_PASSTHROUGH).is_empty(), "Unsupported platforms hide passthrough control")
	main.display.supported = true; main._update_background()
	if not main.view_follow.enabled: main._on_session_control("follow")
	main.display.preview = false; main.tracked = false
	var frozen: Transform3D = main.recent_menu.global_transform
	main.xr_camera.position += Vector3(4,0,0); main._update_view_follow(); main._recenter()
	check(main.recent_menu.global_transform.is_equal_approx(frozen), "Invalid head tracking does not recapture or move panels")
	main.tracked = true
	main._presentation._system_recenter_last_notification_ms = -main._presentation.SYSTEM_RECENTER_REPEAT_MS
	main._on_system_recentered()
	check(not main._system_recenter_pending and not main.recent_menu.global_transform.is_equal_approx(frozen), "System reset uses the already-updated tracked pose in the same frame")
	main.display.preview = true
	main._on_session_control("follow")
	var world: Transform3D = main.video.global_transform * main.video.flat_pose
	main.xr_camera.rotate_z(.4); main.xr_camera.position += Vector3(0,0,3)
	main._update_view_follow()
	check((main.video.global_transform * main.video.flat_pose).is_equal_approx(world), "Disabling follow leaves media in its current world pose")
	main._recenter()
	check(main.video.flat_pose.basis.y.is_equal_approx(Vector3.UP), "Standard recenter returns upright theater screen")
	main._show_recent_menu()
	check(main.recent_menu.global_basis.y.is_equal_approx(Vector3.UP), "Standard menus summon upright with horizontal head direction")
	main.recent_menu.refresh()
	var control_position: Vector3 = button(main.recent_menu, Menu.FOLLOW).node.position
	main.recent_menu.device_status.status_provider = func(): return {"level":100,"charging":true,"clock24":false}
	main.recent_menu.device_status.clock_provider = func(): return {"hour":23,"minute":59}
	main.recent_menu.device_status.refresh(true)
	check(button(main.recent_menu, Menu.FOLLOW).node.position == control_position, "Changing battery/time cannot shift ray controls")
	# Flat photos, placeholders, transition/departure and detail window travel together.
	main.photo_active = true; main.player_menu = main.photo_menu
	main.photo.local_uri = "file:///follow/photo.jpg"; main.photo.geometry = 0; main.photo.gallery.mode = 0
	main.photo._apply_geometry(); main.photo.panel.visible = true
	main._place_screen(); main._show_player_menu()
	main._on_session_control("follow")
	var photo_local := placement(main, main.photo)
	main.photo.set_screen_rotation(15)
	main.photo._departing = main.photo.panel.duplicate(); main.photo.add_child(main.photo._departing)
	main.photo._departing_pose = main.photo.flat_pose
	main.photo._transition_active = true; main.photo._transition_time = .08; main.photo._transition_width = 1.0
	var departing_local: Transform3D = main.xr_camera.global_transform.affine_inverse() * (main.photo.global_transform * main.photo._departing_pose)
	main.xr_camera.transform = Transform3D(Basis.from_euler(Vector3(1.4,.8,1.5)),Vector3(2,.3,-1))
	main._update_view_follow()
	check(placement(main, main.photo).is_equal_approx(photo_local), "Single flat photo follows complete head pose")
	check((main.xr_camera.global_transform.affine_inverse() * (main.photo.global_transform * main.photo._departing_pose)).is_equal_approx(departing_local), "Departing photo retains head-relative placement during transition")
	check(main.photo.panel.basis.is_equal_approx(main.photo.flat_pose.basis * Basis(Vector3.FORWARD,deg_to_rad(15))), "Photo transition preserves content rotation while following")
	main.photo.finish_transition()
	check(main.photo.panel.basis.is_equal_approx(main.photo.flat_pose.basis * Basis(Vector3.FORWARD,deg_to_rad(15))), "Finishing transition preserves photo content rotation")
	footer_check(main.photo_menu, "Photo controls")
	main.photo_menu._adjustment = "photo_view"; main.photo_menu.refresh()
	footer_check(main.photo_menu, "Photo adjustment")
	main.photo.gallery.mode = 2
	main.photo_menu.refresh()
	footer_check(main.photo_menu, "Gallery adjustment")
	var gallery_pose: Transform3D = main.photo.flat_pose
	main.xr_camera.rotate_y(.5); main._update_view_follow()
	check(main.photo.flat_pose.is_equal_approx(gallery_pose) and main.view_follow.enabled, "Multi-object photo layout does not inherit flat-screen follow")
	main.photo.gallery.mode = 0; main._update_view_follow()
	check(placement(main, main.photo).is_equal_approx(photo_local), "Returning to single photo resumes follow pose")
	# Exercise Main's real ray press/release and each menu's dismiss/cleanup path.
	I18n.use("zh")
	main._on_session_control("temporary_passthrough")
	main._show_recent_menu()
	close_menu_check(main,main.recent_menu,"Library")
	main._show_recent_menu()
	main.recent_menu.section = main.recent_menu.Section.SETTINGS; main.recent_menu.refresh()
	close_menu_check(main,main.recent_menu,"Settings")
	main._show_recent_menu()
	main.recent_menu.file_actions.modal = "delete"
	main.recent_menu.file_actions.target = {"title":"Example.mp4", "uri":"file:///Example.mp4"}
	main.recent_menu.refresh()
	close_menu_check(main,main.recent_menu,"File confirmation")
	check(not main.recent_menu.file_actions.modal.is_empty(), "Dismissal cannot hide a file confirmation; its own cancel action remains available")
	main.recent_menu.file_actions.reset()
	main.photo_active = false; main.player_menu = main.video_menu
	main._show_player_menu(); main.video_menu._mode_open = true; main.video_menu.refresh()
	close_menu_check(main,main.video_menu,"Video popup")
	main.video.set_alpha(true); main._show_player_menu()
	close_menu_check(main,main.video_menu,"Person passthrough")
	main.video.set_alpha(false)
	main.photo_active = true; main.player_menu = main.photo_menu
	main._show_player_menu(); main.photo_menu._adjustment = "photo_view"; main.photo_menu.refresh()
	close_menu_check(main,main.photo_menu,"Photo adjustments")
	_check_reclining(main)
	main.settings.save(main.settings_path)
	var restarted := FollowMain.new()
	restarted.settings_path = main.settings_path; restarted.display = SupportedDisplay.new()
	root.add_child(restarted); restarted.set_process(false); restarted.report_timer.stop()
	check(not restarted.view_follow.enabled and not restarted.temporary_passthrough, "Restart ignores previous runtime selections")
	check(restarted.reclining_mode and restarted.video.reclining_mode and restarted._library_settings().reclining_mode,
		"Restart restores reclining preference without enabling session follow")
	I18n.use("zh")
	check(I18n.t("Cannot switch during person passthrough") == "人像透视开启时不可切换", "Restriction hover is localized")
	restarted.queue_free(); main.queue_free(); await process_frame
	var report := {"state":"passed" if failures.is_empty() else "failed", "checks":checks, "failures":failures,
		"scope":"Production placement/menu/background paths with simulated head poses and Android/XR backends; headset ergonomics pending"}
	FileAccess.open(directory.path_join("verification.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for failure in failures: push_error(failure)
	print("View follow checks: %s (%d)" % [report.state,checks])
	quit(0 if failures.is_empty() else 1)

func _choose_reclining(main: Node3D, enabled: bool) -> void:
	var menu: Node3D = main.recent_menu
	for target in menu.choices.targets:
		var item: Dictionary = menu.choices.targets[target]
		if item.get("kind") == "open" and item.get("key") == "reclining_mode":
			menu.choices.action(target)
			break
	for target in menu.choices.targets:
		var item: Dictionary = menu.choices.targets[target]
		if item.get("kind") == "choose" and item.get("key") == "reclining_mode" and item.value == enabled:
			menu.choices.action(target)
			return
	check(false, "Reclining mode choice is reachable from General settings")

func _check_reclining(main: Node3D) -> void:
	I18n.use("en")
	main.photo_active = false; main.player_menu = main.video_menu
	main.video.geometry = 0; main.video.panel.visible = true
	main.video.set_alpha(false)
	if main.view_follow.enabled: main._on_session_control("follow")
	main.xr_camera.transform = Transform3D(Basis.from_euler(Vector3(1.45, .3, .2)), Vector3(0, 1.6, 0))
	main._show_recent_menu()
	main.recent_menu._activate(main.recent_menu.NAV_BASE + main.recent_menu.Section.SETTINGS)
	check(main.recent_menu.rows.any(func(row): return row.get("key", "") == "reclining_mode" and row.value == false),
		"General settings expose the disabled reclining mode")
	_choose_reclining(main, true)
	check(main.reclining_mode and main.video.reclining_mode and not main.view_follow.enabled,
		"Settings enables reclining immediately without enabling follow")
	check(main.settings.get_value("ui", "reclining_mode", false), "Reclining choice is saved")
	check(main.video.flat_pose.basis.is_equal_approx(main.xr_camera.global_basis), "Enabling reclining faces the lying viewer immediately")
	check(main.recent_menu.global_basis.is_equal_approx(main.xr_camera.global_basis), "Reclining settings menu faces the lying viewer")
	main._recenter()
	check(main.video.flat_pose.basis.is_equal_approx(main.xr_camera.global_basis), "Recenter preserves full reclining gaze without follow")
	main._turn_picture(.1, -.2)
	check(absf(main.video.panel.global_basis.z.y) > .5, "Reclining drag permits a tilted video screen")
	main._show_player_menu()
	check(main.video_menu.global_basis.orthonormalized().is_equal_approx(main.video.subtitle_transform().basis),
		"Reclining playback controls share the screen placement plane")
	main._on_session_control("follow")
	main._recenter()
	var local := placement(main, main.video)
	var menu_local: Transform3D = main.xr_camera.global_transform.affine_inverse() * main.video_menu.global_transform
	for pitch in [PI / 2, -1.45, .7]:
		main.xr_camera.transform = Transform3D(Basis.from_euler(Vector3(pitch, -.4, .6)), Vector3(2, 1, -3))
		main._update_view_follow()
		main.video._apply_flat_pose() # Presented-frame updates must not restore the upright constraint.
		check(placement(main, main.video).is_equal_approx(local), "Reclining video follows full head pose at pitch " + str(pitch))
		check((main.xr_camera.global_transform.affine_inverse() * main.video_menu.global_transform).is_equal_approx(menu_local),
			"Reclining controls follow full head pose at pitch " + str(pitch))
	main._show_recent_menu()
	_choose_reclining(main, false)
	check(not main.reclining_mode and not main.video.reclining_mode and main.view_follow.enabled,
		"Disabling reclining preserves the independent follow switch")
	check(absf(main.video.panel.global_basis.z.y) < .00001 and main.recent_menu.global_basis.y.is_equal_approx(Vector3.UP),
		"Disabling reclining restores upright video and menus immediately")
	main.xr_camera.rotation = Vector3(1.2, .8, -.6)
	main._update_view_follow()
	check(absf(main.video.panel.global_basis.z.y) < .00001, "Following after disabling reclining cannot restore stale tilt")
	main._on_session_control("follow")
	_choose_reclining(main, true) # Retain this preference for the restart check.
	for locale in ["zh", "zh_Hant", "ja"]:
		I18n.use(locale)
		check(I18n.t("Reclining mode") != "Reclining mode", "Reclining mode label is localized for " + locale)
