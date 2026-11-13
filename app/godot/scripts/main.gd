extends Node3D

const ScreenLayout := preload("res://scripts/screen_layout.gd")
var screen_layout := ScreenLayout.new(self)
var playback_feedback: Node3D

const DisplayController := preload("res://scripts/xr_display.gd")
const Board := preload("res://scripts/calibration_board.gd")
const Log := preload("res://scripts/diagnostic_log.gd")
const Video := preload("res://scripts/mpv_video_display.gd")
const StickControls := preload("res://scripts/player_stick_controls.gd")
const HandPointer := preload("res://scripts/hand_pointer.gd")
const InputVisuals := preload("res://scripts/input_visuals.gd")
const Geometry := preload("res://scripts/video_geometry.gd")
const LibraryMenu := preload("res://scripts/library_menu.gd")
const StorageVolume := preload("res://scripts/storage_volume.gd")
const Quality := preload("res://scripts/display_quality.gd")
const ThumbnailCache := preload("res://scripts/thumbnail_cache.gd")
const SETTINGS_PATH := "user://player_settings.cfg"
const PlayerMenu := preload("res://scripts/player_menu.gd")
const MediaSurface := preload("res://scripts/media_surface.gd")
const I18n := preload("res://scripts/i18n.gd")
const PlatformMethods := preload("res://scripts/platform_methods.gd")
const FpsOverlay := preload("res://scripts/fps_overlay.gd")
const Background := preload("res://scripts/app_background.gd")
const ViewFollow := preload("res://scripts/view_follow.gd")

const InputCoordinator := preload("res://scripts/input_coordinator.gd")
var input_coordinator := InputCoordinator.new(self)

const PlaybackCoordinator := preload("res://scripts/playback_coordinator.gd")
var playback_coordinator := PlaybackCoordinator.new(self)

const PlayerSettingsController := preload("res://scripts/player_settings_controller.gd")
var settings_controller := PlayerSettingsController.new(self)

const XrPresentationCoordinator := preload("res://scripts/xr_presentation_coordinator.gd")
var presentation_coordinator := XrPresentationCoordinator.new(self)

var display := DisplayController.new()
var display_quality := Quality.DEFAULT
## GPU name used for the quality tier; empty reads the active renderer (tests may preset it).
var gpu_adapter := ""
var low_end_gpu := false
var status_label: Label3D
var report_timer: Timer
var platform_plugin: Object
var _xr_wearer_present := true
var _native_wearer_present := true
var wearer_present := true
var _thumbnail_foreground := true
var last_request := 0
var android_report: Dictionary = {}
var video_menu: Node3D
var video: Node3D
const PlaybackQueue := preload("res://scripts/playback_queue.gd")
var playback_queue := PlaybackQueue.new()
var video_queue: Array[Dictionary]:
	get:
		return playback_queue.items
	set(value):
		playback_queue.replace(value)
var queue_add_mode: bool:
	get:
		return playback_coordinator._queue_add_mode
	set(value):
		playback_coordinator._queue_add_mode = value
var _queue_end_key: String:
	get:
		return playback_coordinator._queue_end_key
	set(value):
		playback_coordinator._queue_end_key = value
var calibration_board: Node3D
var right_controller: XRController3D
var left_controller: XRController3D
var hand_pointers := {}
var pinch_hand := preload("res://scripts/hand_preferences.gd").DEFAULT
var hand_marks := {}
var input_visuals: Node3D
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var fps_overlay: Label3D
var stick_controls := StickControls.new()
var library_menu: Node3D
var player_menu: Node3D
var menu_compositor: Node3D
const LIBRARY_DISTANCE_LIMITS := Vector2(0.8, 4.0)
var library_distance: float:
	get:
		return presentation_coordinator.library_distance
	set(value):
		presentation_coordinator.library_distance = value
var library_grab: Dictionary:
	get:
		return input_coordinator._library_grab
	set(value):
		input_coordinator._library_grab = value
var _system_recenter_pending: bool:
	get:
		return presentation_coordinator._system_recenter_pending
	set(value):
		presentation_coordinator._system_recenter_pending = value
var settings: ConfigFile:
	get:
		return settings_controller.settings
	set(value):
		settings_controller.settings = value
var settings_path: String:
	get:
		return settings_controller.settings_path
	set(value):
		settings_controller.settings_path = value
var background: Node
var view_follow: ViewFollow:
	get:
		return presentation_coordinator.view_follow
	set(value):
		presentation_coordinator.view_follow = value
var temporary_passthrough: bool:
	get:
		return presentation_coordinator.temporary_passthrough
	set(value):
		presentation_coordinator.temporary_passthrough = value
var reclining_mode: bool:
	get:
		return presentation_coordinator.reclining_mode
	set(value):
		presentation_coordinator.reclining_mode = value


func _ready() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	add_child(world)
	var origin := XROrigin3D.new()
	xr_origin = origin
	origin.name = "XROrigin3D"
	add_child(origin)
	var camera := XRCamera3D.new()
	xr_camera = camera
	camera.name = "XRCamera3D"
	origin.add_child(camera)
	var desktop := (
		OS.get_name() != "Android" or OS.get_cmdline_user_args().has("--mpv-diagnostic-2d")
	)
	if desktop:
		camera.position.y = 1.6
	for hand in ["left_hand", "right_hand"]:
		hand_pointers[hand] = HandPointer.new()
		var mark := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.006
		sphere.height = 0.012
		mark.mesh = sphere
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = (
			Color(0.15, 0.9, 1.0) if hand == "left_hand" else Color(1.0, 0.65, 0.15)
		)
		mark.material_override = material
		mark.visible = false
		origin.add_child(mark)
		hand_marks[hand] = mark
		var controller := XRController3D.new()
		controller.tracker = hand
		controller.pose = "aim"
		controller.button_pressed.connect(_on_controller_button.bind(hand))
		controller.button_released.connect(_on_controller_release.bind(hand))
		origin.add_child(controller)
		if hand == "right_hand":
			right_controller = controller
		else:
			left_controller = controller
	var board := Board.new()
	calibration_board = board
	board.name = "CalibrationBoard"
	add_child(board)
	status_label = Label3D.new()
	status_label.position = Vector3(0, 2.45, -2)
	status_label.font_size = 22
	status_label.pixel_size = 0.003
	status_label.outline_size = 5
	add_child(status_label)
	display.status_changed.connect(update_status)
	display.status_changed.connect(_on_input_session_changed)
	display.presence_changed.connect(_on_openxr_presence_changed)
	settings_controller.load_preferences()
	var saved_window_height := float(
		settings.get_value("ui", "window_height", XrPresentationCoordinator.WINDOW_HEIGHT_DEFAULT)
	)
	presentation_coordinator.window_height = (
		clampf(
			saved_window_height,
			XrPresentationCoordinator.WINDOW_HEIGHT_LIMITS.x,
			XrPresentationCoordinator.WINDOW_HEIGHT_LIMITS.y
		)
		if is_finite(saved_window_height)
		else XrPresentationCoordinator.WINDOW_HEIGHT_DEFAULT
	)
	pinch_hand = preload("res://scripts/hand_preferences.gd").normalize(
		settings.get_value(
			"controls", "pinch_hand", preload("res://scripts/hand_preferences.gd").DEFAULT
		)
	)
	var saved_library_distance := float(settings.get_value("ui", "library_distance", 1.4))
	library_distance = (
		clampf(saved_library_distance, LIBRARY_DISTANCE_LIMITS.x, LIBRARY_DISTANCE_LIMITS.y)
		if is_finite(saved_library_distance)
		else 1.4
	)
	var saved_queue: Variant = settings.get_value("playback", "queue", [])
	if saved_queue is Array:
		playback_queue.replace(saved_queue)
	playback_queue.custom = bool(settings.get_value("playback", "custom_queue", false))
	playback_queue.configure(
		"queue_shuffle", bool(settings.get_value("playback", "queue_shuffle", false))
	)
	playback_queue.configure(
		"queue_loop", settings.get_value("playback", "queue_loop", false) == true
	)
	reclining_mode = bool(settings.get_value("ui", "reclining_mode", false))
	I18n.use(str(settings.get_value("ui", "language", "auto")))
	fps_overlay = FpsOverlay.new()
	fps_overlay.source = _fps_sample
	camera.add_child(fps_overlay)
	fps_overlay.set_shown(bool(settings.get_value("ui", "show_fps", false)))
	# Global quality also applies to menus and backgrounds.
	display_quality = Quality.load_quality(settings)
	if gpu_adapter.is_empty():
		gpu_adapter = RenderingServer.get_video_adapter_name()
	low_end_gpu = Quality.is_low_end_gpu(gpu_adapter)
	display.render_scale = Quality.render_scale(display_quality, low_end_gpu)
	display.msaa_3d = Quality.MSAA[Quality.resolve(display_quality, low_end_gpu)]
	display.flat_msaa_3d = Quality.FLAT_MSAA[Quality.resolve(display_quality, low_end_gpu)]
	display.preferred_refresh_rate = float(settings.get_value("display", "refresh_rate", 72.0))
	display.configure(get_viewport(), world.environment, XRServer.find_interface("OpenXR"), desktop)
	immersive_overlay = preload("res://scripts/immersive_adjustment_overlay.gd").new()
	immersive_overlay.source = func():
		return input_coordinator.immersive.feedback_snapshot(video.local_uri) if video else []
	camera.add_child(immersive_overlay)
	picture_center_guide = preload("res://scripts/picture_center_guide.gd").new()
	picture_center_guide.source = _picture_center_sample
	add_child(picture_center_guide)
	input_visuals = InputVisuals.new()
	input_visuals.name = "InputVisuals"
	origin.add_child(input_visuals)
	# The runtime emits this after updating tracking; re-place content in the same frame.
	var openxr := XRServer.find_interface("OpenXR")
	if not desktop and openxr and openxr.has_signal("pose_recentered"):
		openxr.connect("pose_recentered", _on_system_recentered)
	_head_placed = desktop
	video = Video.new()
	video.reclining_mode = reclining_mode
	video.name = "VideoDisplay"
	video.changed.connect(_on_video_changed)
	video.mode_lock_changed.connect(_on_mode_lock_changed.bind("video"))
	video.thumbnail_ready.connect(_on_video_thumbnail_ready)
	video.prefer_clone_voice = bool(settings.get_value("audio", "prefer_clone_voice", false))
	video.history_enabled = bool(settings.get_value("library", "history", true))
	_restore_seek_settings()
	video.reuse_last_mode = bool(settings.get_value("video", "reuse_last_mode", false))
	video.last_video_mode = preload("res://scripts/video_mode_default.gd").clean(
		settings.get_value("video", "last_mode", {})
	)
	video.load_mode_lock(settings.get_value("video", "mode_lock", {}))
	video.subtitle_distance = float(settings.get_value("subtitles", "distance", 5.0))
	video.subtitle_position = video.SubtitleDepth.restore_position(settings)
	video.subtitle_size = clampf(float(settings.get_value("subtitles", "size", 1.0)), 0.5, 2.0)
	video.subtitle_flat_position = clampf(
		float(settings.get_value("subtitles", "flat_position", 0.0)), 0.0, 1.0
	)
	video.subtitle_palette = video.CaptionPalette.index(
		settings.get_value("subtitles", "palette", 0)
	)
	video.subtitle_direction = int(settings.get_value("subtitles", "direction", 0))
	video.color_grade.restore(settings.get_value("video", "color_grade", {}))
	# The flat screen keeps the distance, size and curve the viewer last chose.
	video.screen_distance = clampf(
		float(settings.get_value("screen", "distance", video.SCREEN_DISTANCE)),
		video.DISTANCE_LIMITS.x,
		video.DISTANCE_LIMITS.y
	)
	video.screen_scale = clampf(
		float(settings.get_value("screen", "scale", 1.0)),
		video.SCALE_LIMITS.x,
		video.SCALE_LIMITS.y
	)
	video.screen_curve = clampf(float(settings.get_value("screen", "curve", 0.0)), 0.0, 1.0)
	add_child(video)
	screen_layout.restore()
	_update_thumbnail_protection()
	video.sharpness = Quality.load_sharpness(settings, low_end_gpu)
	video.view_camera = camera
	display.set_foveation(int(settings.get_value("video", "foveation", 0)))
	library_menu = LibraryMenu.new()
	library_menu.catalog = video.recent_files
	library_menu.list_view = bool(settings.get_value("library", "list_view", false))
	library_menu.browse_memory.configure(
		bool(settings.get_value("library", "browse_memory", true)), video.history_enabled
	)
	library_menu.layout_changed.connect(func(): _place_menu(library_menu))
	library_menu.file_actions.load(settings.get_value("library", "orders", {}))
	library_menu.file_actions.set_enabled(
		bool(settings.get_value("library", "file_editing", false))
	)
	library_menu.file_renamed.connect(_on_file_renamed)
	library_menu.current_file_provider = func(): return viewer().local_uri
	library_menu.file_delete_preparing.connect(_prepare_file_delete)
	library_menu.file_deleted.connect(_forget_deleted_file)
	library_menu.settings_provider = _library_settings
	if video.platform and video.platform.has_signal("diagnostic_log_saved"):
		video.platform.connect(
			"diagnostic_log_saved",
			func(_id, raw):
				var result: Variant = JSON.parse_string(raw)
				if result is Dictionary:
					library_menu.status = (
						"Log saved to Downloads"
						if result.get("ok", false)
						else "Diagnostic log could not be saved"
					)
					library_menu.refresh()
		)
	library_menu.chosen.connect(_on_library_chosen)
	library_menu.subtitle_system_requested.connect(video.pick_external_subtitle)
	library_menu.subtitle_chosen.connect(
		func(selection):
			if (
				selection.source_uri != video.local_uri
				or int(selection.session_id) != video.media.session_id
			):
				return
			if selection.has("track_id"):
				video.set_subtitle_track(int(selection.track_id))
			else:
				video._pending_external_uri = str(selection.get("subtitle_uri", ""))
	)
	library_menu.storage_eject_requested.connect(_on_storage_eject_requested)
	library_menu.storage_removed.connect(_release_storage_readers)
	library_menu.player_requested.connect(
		func():
			if queue_add_mode:
				_queue_action("queue_done")
			else:
				presentation_coordinator._show_player_menu(false)
	)
	library_menu.queue_requested.connect(_queue_action)
	library_menu.setting_changed.connect(_on_setting_changed)
	library_menu.setting_previewed.connect(_on_playback_adjustment)
	library_menu.recenter_requested.connect(_recenter)
	_connect_session_controls(library_menu)
	add_child(library_menu)
	if Engine.has_singleton("QuestPlayer"):
		var plugin := Engine.get_singleton("QuestPlayer")
		library_menu.attach_platform(plugin)
		plugin.connect("mpv_debug_command", _on_display_debug_command)
		plugin.set_mpv_output_width(
			Quality.output_width(Quality.load_output_choice(settings), low_end_gpu)
		)
	playback_feedback = preload("res://scripts/playback_feedback.gd").new()
	playback_feedback.host = self
	add_child(playback_feedback)
	player_menu = PlayerMenu.new()
	player_menu.controls_opacity = clampf(
		float(settings.get_value("ui", "controls_opacity", 0.86)), 0, 1
	)
	player_menu.state_provider = _menu_state
	player_menu.action_requested.connect(_on_menu_action)
	# The compact browser and playback popups share one content area.
	player_menu.popup_opened.connect(
		func():
			if library_menu.visible and library_menu.playback_browser:
				presentation_coordinator._show_player_menu(false)
	)
	player_menu.recent_requested.connect(func(): _show_library_menu())
	player_menu.seek_requested.connect(_on_menu_seek)
	player_menu.bookmark_requested.connect(_on_bookmark_request)
	player_menu.setting_requested.connect(_on_player_setting)
	player_menu.adjustment_requested.connect(_on_playback_adjustment)
	player_menu.adjustment_committed.connect(_save_playback_adjustments)
	player_menu.subtitle_requested.connect(video.set_subtitle_track)
	player_menu.secondary_subtitle_requested.connect(video.dual_subtitles.select)
	_connect_session_controls(player_menu)
	add_child(player_menu)
	video_menu = player_menu
	menu_compositor = preload("res://scripts/xr_menu_compositor.gd").new()
	add_child(menu_compositor)
	menu_compositor.configure(
		[library_menu, video_menu],
		camera,
		not display.preview and display.xr != null and display.xr.is_initialized(),
		func(): return display.session_state
	)
	background = Background.new()
	background.choice = str(
		settings.get_value("appearance", "background", Background.DEFAULT_CHOICE)
	)
	background.yaw = fposmod(float(settings.get_value("appearance", "background_yaw", 0.0)), 360.0)
	background.brightness = clampf(
		float(settings.get_value("appearance", "background_brightness", 1.0)), 0.5, 1.25
	)
	background.changed.connect(_on_background_changed)
	add_child(background)
	if Engine.has_singleton("QuestPlayer"):
		platform_plugin = Engine.get_singleton("QuestPlayer")
		if PlatformMethods.supports(platform_plugin, "set_ui_language"):
			platform_plugin.set_ui_language(I18n.choice)
		platform_plugin.connect("capabilities_ready", _on_capabilities_ready)
		platform_plugin.connect("android_lifecycle", _on_android_lifecycle)
		if platform_plugin.has_signal("headset_presence_changed"):
			platform_plugin.connect("headset_presence_changed", _on_native_presence_changed)
		if PlatformMethods.supports(platform_plugin, "set_openxr_presence"):
			platform_plugin.set_openxr_presence(_xr_wearer_present)
		if PlatformMethods.supports(platform_plugin, "is_headset_present"):
			_on_native_presence_changed(platform_plugin.is_headset_present(), "initial")
		pass
		request_capabilities()
	else:
		Log.record("android_plugin_unavailable", {"desktop_preview": desktop})
	report_timer = Timer.new()
	report_timer.wait_time = 2.0
	report_timer.timeout.connect(save_report)
	add_child(report_timer)
	report_timer.start()
	update_status()
	if not OS.get_cmdline_user_args().has("--mpv-diagnostic-2d"):
		_show_library_menu()
	Log.record(
		"ui_ready",
		{
			"library_visible": library_menu.visible,
			"player_visible": player_menu.visible,
			"diagnostics_visible": status_label.visible,
			"calibration_visible": calibration_board.visible,
			"menu_selection": "controller_ray_trigger_or_hand_pinch"
		}
	)
	Log.record(
		"app_started",
		{"version": ProjectSettings.get_setting("application/config/version"), "os": OS.get_name()}
	)
	var recent_scan := preload("res://scripts/recent_scan.gd").new()
	add_child(recent_scan)
	recent_scan.changed.connect(
		func():
			_update_thumbnail_protection()
			if library_menu.section == library_menu.Section.RECENT:
				library_menu.refresh()
	)
	recent_scan.start(video.recent_files, platform_plugin)
	# Source distribution: private capture automation is excluded.


## Desktop preview: dragging with the mouse moves the picture, the wheel zooms immersive views.
func _unhandled_input(event: InputEvent) -> void:
	input_coordinator._unhandled_input(event)


func _unhandled_key_input(event: InputEvent) -> void:
	input_coordinator._unhandled_key_input(event)


# Menus are ray + trigger only. A list row clicks on release unless the ray dragged to scroll.
# Controller grip drags placement; grip plus the same hand's stick adjusts distance.
# Optical-hand pinches retain their existing content gestures.
func _on_controller_release(action: String, hand: String = "") -> void:
	input_coordinator._on_controller_release(action, hand)


func _on_pointer_release(action: String, hand: String) -> void:
	input_coordinator._on_pointer_release(action, hand)


func _on_controller_button(action: String, hand: String = "") -> void:
	input_coordinator._on_controller_button(action, hand)


func _on_pointer_button(action: String, hand: String) -> void:
	input_coordinator._on_pointer_button(action, hand)


## Menus shown at launch are placed before the headset reports a pose (the camera is still at
## the floor origin): once the head is first tracked, recenter and place everything again.
var _head_placed: bool:
	get:
		return presentation_coordinator._head_placed
	set(value):
		presentation_coordinator._head_placed = value


func _head_tracked() -> bool:
	return presentation_coordinator._head_tracked()


func _on_system_recentered() -> void:
	presentation_coordinator._on_system_recentered()


func _apply_system_recenter() -> void:
	presentation_coordinator._apply_system_recenter()


var picture_center_guide: Node3D
var immersive_overlay: Node3D
var _external_poll_ms := 0


func _process(delta: float) -> void:
	if (
		video
		and Time.get_ticks_msec() >= _external_poll_ms
		and preload("res://scripts/platform_methods.gd").supports(
			video.platform, "external_playback_poll"
		)
	):
		_external_poll_ms = Time.get_ticks_msec() + 250
		var external: Variant = JSON.parse_string(video.platform.external_playback_poll())
		if external is Dictionary and str(external.get("uri", "")).begins_with("externalvideo://"):
			playback_coordinator.open_external(external)
	screen_layout.tick()
	if is_instance_valid(playback_feedback):
		playback_feedback.tick()
	_apply_system_recenter()
	_update_view_follow()
	_refresh_session_controls()
	_update_hand_input(delta)
	if video and is_instance_valid(viewer().get("panel")):
		display.set_flat_surface_visible(
			viewer().panel.visible and viewer().geometry == Geometry.Geometry.FLAT
		)
	if not _head_placed and _head_tracked():
		_head_placed = true
		if not view_follow.enabled:
			_recenter()
	if video and viewer().local_uri != _screen_uri:
		_screen_uri = viewer().local_uri
		if not _screen_uri.is_empty():
			if screen_layout.fixed():
				screen_layout.restore()
			_place_screen()
	_update_grab()
	_update_library_grab()
	_update_player_menu_anchor()
	var right := _stick(right_controller)
	var left := _stick(left_controller)
	_update_corner_hover()
	_update_flat_grab_stick(left, right, delta)
	_process_sticks(left, right, delta)


func _picture_center_sample() -> Dictionary:
	if (
		not video
		or video.geometry == 0
		or (not video.panel)
		or (not video.panel.visible)
		or (not _input_focused())
		or (
			_active_menu()
			and (_active_menu() != player_menu or not player_menu.allows_playback_sticks())
		)
	):
		return {}
	var head: Variant = _head_pose()
	if (
		not head is Transform3D
		or (
			grab.is_empty()
			and (not picture_center_guide or picture_center_guide.identity.is_empty())
		)
	):
		return {}
	return {
		"identity": video.local_uri,
		"hand": str(grab.get("hand", "")),
		"held": not grab.is_empty(),
		"head": head,
		"centre": video.panel.to_global(Vector3(0, 0, -video.SPHERE_RADIUS))
	}


func _process_sticks(left: Vector2, right: Vector2, delta: float) -> void:
	input_coordinator._process_sticks(left, right, delta)


func _update_controls_visibility(menu: Node3D) -> void:
	input_coordinator._update_controls_visibility(menu)


func _stick(controller: XRController3D) -> Vector2:
	return input_coordinator._stick(controller)


func _input_focused() -> bool:
	return input_coordinator._input_focused()


func _controller_allowed(hand: String) -> bool:
	return input_coordinator._controller_allowed(hand)


func _controller_ray(hand: String) -> Variant:
	return input_coordinator._controller_ray(hand)


func _update_hand_input(delta: float) -> void:
	input_coordinator._update_hand_input(delta)


func picture_pinch_allowed(hand: String) -> bool:
	return (
		not (hand_pointers.has(hand) and hand_pointers[hand].source == "hand")
		or preload("res://scripts/hand_preferences.gd").allows(hand, pinch_hand)
	)


func _dispatch_hand_input(inputs: Dictionary, _delta: float = 1.0 / 72.0) -> void:
	input_coordinator._dispatch_hand_input(inputs, _delta)


func _cancel_pointer(hand: String) -> void:
	input_coordinator._cancel_pointer(hand)


func _on_input_session_changed() -> void:
	input_coordinator._on_input_session_changed()


func _hand_input_report() -> Dictionary:
	return input_coordinator._hand_input_report()


static func input_pose_tracked(tracker: XRPositionalTracker, pose_name: String) -> bool:
	if tracker == null or not tracker.has_pose(pose_name):
		return false
	var pose := tracker.get_pose(pose_name)
	return pose.has_tracking_data and pose.tracking_confidence != XRPose.XR_TRACKING_CONFIDENCE_NONE


# --- dragging the picture -------------------------------------------------------------------

const GRAB_START := 0.035  # radians the ray turns before a grip/pinch becomes a drag
const MOUSE_TURN := 0.004  # radians per pixel in the desktop preview
const ZOOM_SPEED := 0.6  # sphere radii per second at full deflection
const PUSH_SPEED := 1.5  # metres per second the held flat screen moves at full deflection
const STICK_DEADZONE := 0.2
## Grip (or optical pinch) held outside menus: action, hand, ray angles, moved; a press on a
## flat screen corner adds resize = {corner, start_length, start_scale}.
var grab: Dictionary:
	get:
		return input_coordinator._grab
	set(value):
		input_coordinator._grab = value
var trigger_taps := {}


func _update_library_grab() -> void:
	input_coordinator._update_library_grab()


func _update_library_grab_stick(left: Vector2, right: Vector2, delta: float) -> void:
	input_coordinator._update_library_grab_stick(left, right, delta)


func _update_flat_grab_stick(left: Vector2, right: Vector2, delta: float) -> void:
	input_coordinator._update_flat_grab_stick(left, right, delta)


func eye() -> Vector3:
	if is_instance_valid(viewer().view_camera) and viewer().view_camera.is_inside_tree():
		return viewer().view_camera.global_position
	return Vector3(0, 1.6, 0)


func _ray(hand: String) -> Variant:
	return input_coordinator._ray(hand)


## A ray near a flat screen corner shows its bracket: pressing there resizes.
func _update_corner_hover() -> void:
	input_coordinator._update_corner_hover()


func _begin_grab(hand: String, action: String = "grip_click") -> void:
	input_coordinator._begin_grab(hand, action)


func _update_grab() -> void:
	input_coordinator._update_grab()


## Yaw (positive left) and pitch (positive up) of a direction.
static func ray_angles(direction: Vector3) -> Vector2:
	var unit := direction.normalized()
	return Vector2(atan2(-unit.x, -unit.z), asin(clampf(unit.y, -1.0, 1.0)))


## The picture follows the pointer: immersive views turn, the flat screen moves around the head
## at its distance and keeps facing the eyes.
func _turn_picture(yaw: float, pitch: float) -> void:
	presentation_coordinator._turn_picture(yaw, pitch)


## The flat screen nearer (negative) or farther along the line from the eyes, still facing them.
func _push_screen(amount: float) -> void:
	presentation_coordinator._push_screen(amount)


func _save_screen() -> void:
	presentation_coordinator._save_screen()


## Right stick press: the picture back at its natural size and distance (the curve stays). It stays
## where it is: only the menu's recenter button brings the screen in front of the head again.
func _reset_picture() -> void:
	presentation_coordinator._reset_picture()


func _update_menu_pointer(hand: String, pressed: bool = false) -> bool:
	return presentation_coordinator._update_menu_pointer(hand, pressed)


const CONTROLS_HIDE_MS := 5000
var menu_touched_ms: int:
	get:
		return presentation_coordinator._menu_touched_ms
	set(value):
		presentation_coordinator._menu_touched_ms = value


func viewer() -> Node3D:
	return video


func _on_library_chosen(uri: String, title: String) -> void:
	playback_coordinator._on_library_chosen(uri, title)


func _on_file_renamed(old_uri: String, new_uri: String, title: String) -> void:
	video.recent_files.relocate(old_uri, new_uri, title)
	if not video.recent_files.save():
		library_menu.file_actions.rename.migration_failed = true
	video.mode_memory.relocate(old_uri, new_uri)
	if not video.mode_memory.save():
		library_menu.file_actions.rename.migration_failed = true
	LibraryMenu.Thumbnails.relocate(old_uri, new_uri)
	playback_queue.relocate(old_uri, new_uri, title)
	_save_queue()
	_update_thumbnail_protection()


func _prepare_file_delete(uri: String) -> void:
	if video.local_uri == uri or video.local_uri.begins_with(uri.trim_suffix("/") + "/"):
		video.close_video()
	grab = {}
	stick_controls.suspend()


func _forget_deleted_file(uri: String) -> void:
	video_queue = video_queue.filter(
		func(item):
			return (
				str(item.get("uri", "")) != uri
				and not str(item.get("uri", "")).begins_with(uri.trim_suffix("/") + "/")
			)
	)
	_save_queue()
	for entry in video.recent_files.list_recent():
		if str(entry.uri) == uri or str(entry.uri).begins_with(uri.trim_suffix("/") + "/"):
			video.recent_files.forget(str(entry.uri))
	video.recent_files.save()
	_update_thumbnail_protection()


func _on_storage_eject_requested(volume: Dictionary) -> void:
	_release_storage_readers(volume)
	library_menu.finish_storage_release(str(volume.get("id", "")))


func _release_storage_readers(volume: Dictionary) -> void:
	if (
		video
		and (
			StorageVolume.contains_uri(volume, video.local_uri)
			or StorageVolume.contains_external(volume, video.local_uri, video.get("platform"))
		)
	):
		video.close_video()
	video_queue = video_queue.filter(
		func(item): return not StorageVolume.contains_uri(volume, str(item.get("uri", "")))
	)
	_save_queue()
	grab = {}
	stick_controls.suspend()


func _queue_action(operation: String) -> void:
	playback_coordinator._queue_action(operation)


func _save_queue() -> void:
	playback_coordinator._save_queue()


func _advance_queue(session_id: int, uri: String) -> void:
	playback_coordinator._advance_queue(session_id, uri)


var _screen_uri := ""
var player_menu_anchor_key: Array = []
var player_menu_anchor_eye := Vector3.ZERO


## Full tracked pose is retained for media follow; reclining menus also use it.
func _head_pose() -> Variant:
	return presentation_coordinator._head_pose()


## Menus use world up and the horizontal head direction. Looking straight up or
## down uses the head's right axis to avoid an undefined horizontal forward.
static func upright_pose(head: Transform3D) -> Transform3D:
	return MediaSurface.upright_pose(head)


func _menu_head_pose(head: Transform3D) -> Transform3D:
	return presentation_coordinator._menu_head_pose(head)


## Reclining placement uses the full gaze; ordinary placement stays upright.


func _place_screen(recenter: bool = false) -> void:
	presentation_coordinator._place_screen(recenter)


func _menu_key(menu: Node3D) -> StringName:
	return presentation_coordinator._menu_key(menu)


func _update_view_follow() -> void:
	presentation_coordinator._update_view_follow()


func _place_menu(menu: Node3D) -> void:
	presentation_coordinator._place_menu(menu)


func _active_menu() -> Node3D:
	return presentation_coordinator._active_menu()


func _update_player_menu_anchor() -> void:
	presentation_coordinator._update_player_menu_anchor()


func _toggle_player_menu() -> void:
	presentation_coordinator._toggle_player_menu()


func _show_player_menu() -> void:
	presentation_coordinator._show_player_menu()


func _show_library_menu(preserve_navigation: bool = false) -> void:
	presentation_coordinator._show_library_menu(preserve_navigation)


func _canvas_controls_snapshot() -> Dictionary:
	return presentation_coordinator._canvas_controls_snapshot()


func _restore_seek_settings() -> void:
	settings_controller._restore_seek_settings()


func _library_settings() -> Dictionary:
	return settings_controller._library_settings()


func _on_setting_changed(key: String, value: Variant) -> void:
	settings_controller._on_setting_changed(key, value)


func _on_menu_action(operation: String) -> void:
	playback_coordinator._on_menu_action(operation)


func _on_menu_seek(position_ms: int) -> void:
	playback_coordinator._on_menu_seek(position_ms)


func _on_player_setting(key: String, value: Variant) -> void:
	playback_coordinator._on_player_setting(key, value)


func _on_bookmark_request(operation: String, marker_id: String, scope: String) -> void:
	playback_coordinator._on_bookmark_request(operation, marker_id, scope)


func _on_mode_lock_changed(lock: Dictionary, media_kind: String) -> void:
	settings_controller._on_mode_lock_changed(lock, media_kind)


func _menu_state() -> Dictionary:
	return presentation_coordinator._menu_state()


## Preserve native titles/IDs for sidecar recognition; localize their presentation only.
func _audio_option_label(track: Dictionary) -> String:
	return playback_coordinator._audio_option_label(track)


func _apply_stick_actions(actions: Array[Dictionary], delta: float = 1.0 / 72.0) -> void:
	input_coordinator._apply_stick_actions(actions, delta)


func capture_last_video_mode() -> void:
	if (
		not video
		or not video.reuse_last_mode
		or video.local_uri.is_empty()
		or not video._remember_file
		or video._layout_pending != null
		or video._waiting_first
		or not video.media.accepts(video.media.session_id)
	):
		return
	var mode := preload("res://scripts/video_mode_default.gd").clean(
		video.current_lock().merged({"swap_eyes": video.swap_eyes}, true)
	)
	if mode.is_empty() or mode == video.last_video_mode:
		return
	video.last_video_mode = mode
	settings.set_value("video", "last_mode", mode)
	settings.save(settings_path)


func _on_video_changed() -> void:
	capture_last_video_mode()
	playback_coordinator._on_video_changed()


func _on_video_thumbnail_ready(_uri: String) -> void:
	playback_coordinator._on_video_thumbnail_ready(_uri)


var thumbnail_history_sequence := -1


func _update_thumbnail_protection() -> void:
	playback_coordinator._update_thumbnail_protection()


func _on_background_changed() -> void:
	presentation_coordinator._on_background_changed()


func _update_background() -> void:
	presentation_coordinator._update_background()


func _connect_session_controls(menu: Node3D) -> void:
	presentation_coordinator._connect_session_controls(menu)


func _person_passthrough() -> bool:
	return presentation_coordinator._person_passthrough()


func _refresh_session_controls() -> void:
	presentation_coordinator._refresh_session_controls()


func _on_session_control(operation: String) -> void:
	presentation_coordinator._on_session_control(operation)


func _recenter() -> void:
	presentation_coordinator._recenter()


func request_capabilities() -> void:
	if platform_plugin:
		last_request = platform_plugin.request_capabilities()
		Log.record("capability_probe_requested", {"request_id": last_request})


func _on_capabilities_ready(request_id: int, json_report: String) -> void:
	if request_id != last_request:
		return
	var parsed: Variant = JSON.parse_string(json_report)
	if parsed is Dictionary:
		android_report = parsed
		Log.record("capability_probe_completed", {"request_id": request_id})
	else:
		Log.record("capability_probe_invalid", {"request_id": request_id})
	save_report()


func _on_openxr_presence_changed(present: bool) -> void:
	_xr_wearer_present = present
	if PlatformMethods.supports(platform_plugin, "set_openxr_presence"):
		platform_plugin.set_openxr_presence(present)
	_apply_wearer_presence()


func _on_native_presence_changed(present: bool, source: String) -> void:
	_native_wearer_present = present
	Log.record("headset_presence", {"present": present, "source": source})
	_apply_wearer_presence()


func _apply_wearer_presence() -> void:
	var present := _xr_wearer_present and _native_wearer_present
	if present == wearer_present:
		_update_local_thumbnail_activity()
		return
	wearer_present = present
	_update_local_thumbnail_activity()
	_queue_end_key = ""
	if video and video.media.accepts(video.media.session_id):
		# Wearer absence is a suspension, not a new play/pause choice or a seek.
		# Native gates also cover opening/first-frame work while the wearer is absent.
		if not present:
			video.checkpoint_playback()
		# Current Android bridges retain their own play/audio-focus intent behind
		# the wearer gate. Do not turn a focus-loss pause into an explicit play.
		if not PlatformMethods.supports(platform_plugin, "set_openxr_presence"):
			video.platform.set_mpv_playing(
				video.media.session_id,
				present and video.requested_play and not video._waiting_first
			)
		if present:
			_on_video_changed()


func _update_local_thumbnail_activity() -> void:
	if library_menu:
		library_menu.local_thumbnails.set_suspended(
			library_menu, not (wearer_present and _thumbnail_foreground)
		)


func _on_android_lifecycle(event: String) -> void:
	Log.record("android_lifecycle", {"event": event})
	if event in ["pause", "resume"]:
		_thumbnail_foreground = event == "resume"
		_update_local_thumbnail_activity()
	if event == "resume":
		request_capabilities()
	elif event == "pause" and video:
		video.checkpoint_playback()


func save_report() -> void:
	var report := {
		"schema_version": 1,
		"app_version": ProjectSettings.get_setting("application/config/version"),
		"engine": Engine.get_version_info(),
		"captured_unix_seconds": Time.get_unix_time_from_system(),
		"xr": display.capabilities(),
		"android": android_report,
		"stage": "MPV_shared_display",
		"video_implemented": true,
		"video_device_validation": "pending",
		"media": video.media.snapshot() if video else {},
		"video_layout": video.layout_snapshot() if video else {},
		"active_media": "video",
		"hand_input": _hand_input_report(),
		"input_visuals": input_visuals.snapshot() if input_visuals else {},
		"background": background.choice if background else "",
	}
	var encoded := JSON.stringify(report, "\t")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://diagnostics"))
	var file := FileAccess.open("user://diagnostics/capabilities_latest.json", FileAccess.WRITE)
	if file:
		file.store_string(encoded)
	if platform_plugin:
		var saved_path: String = platform_plugin.save_capability_report(encoded)
		if saved_path.begins_with("ERROR:"):
			Log.record("capability_report_save_failed", {"reason": saved_path})
	update_status()


func update_status() -> void:
	if not status_label:
		return
	var mode := "Passthrough" if display.applied_passthrough else "Opaque"
	var detail := "Desktop preview" if display.preview else display.session_state
	status_label.position.y = 2.45
	status_label.visible = OS.get_cmdline_user_args().has("--show-diagnostics")
	calibration_board.visible = (
		status_label.visible and not (video and video.panel and video.panel.visible)
	)
	if not status_label.visible:
		return
	status_label.text = (
		"Immivio - MPV\n%s | %s\nLeft Menu / Tab: player menu\nPoint with a controller and press trigger to select\nA,X / O: open file   Grip / Space: play,pause\nLeft click / P: projection   Right click: reset view\nLeft stick: seek 20s   Right stick / arrows: seek 10s\nB / R: recenter   Trigger / T: Alpha,background\nV: fixture"
		% [mode, detail]
	)
	if video:
		status_label.text += (
			"\n%s | %s | %s | %s\n%s"
			% [
				video.display_name.left(42),
				video.media.state,
				"SBS" if video.stereo_sbs else "2D",
				video.layout_snapshot().geometry,
				"Alpha on" if video.alpha_enabled else "Normal playback"
			]
		)
		status_label.text += (
			"\n%.1f / %.1f s | %s | loop %s"
			% [
				video.control.observed_position_ms / 1000.0,
				video.control.duration_ms / 1000.0,
				video.control.snapshot().state,
				"on" if video.loop_enabled else "off"
			]
		)
		status_label.text += (
			"\nAudio track: %s · System volume"
			% str(video.media.playback.get("details", {}).get("audio_track_id", "none"))
		)
		status_label.text += (
			"\nSubtitles: %s | C: track"
			% (
				"off"
				if video.subtitles.requested_track == 0
				else str(video.subtitles.requested_track)
			)
		)
		status_label.text += "\nEyes: %s | E: swap" % ("R/L" if video.swap_eyes else "L/R")
		if not video.picker_error.is_empty():
			status_label.text += "\n" + video.picker_error
		if not video.media.error.is_empty():
			status_label.text += "\n" + video.media.error
	if not display.error_code.is_empty():
		status_label.text += "\n" + display.error_code


func _on_playback_adjustment(key: String, value: Variant) -> void:
	settings_controller._on_playback_adjustment(key, value)


func _save_playback_adjustments() -> void:
	settings_controller._save_playback_adjustments()


func _fps_sample() -> Dictionary:
	if not video or not video.panel or (not video.panel.visible):
		return {}
	return {
		"frames": video.media.frame_counter, "target": 0, "active": video.media.state == "playing"
	}


var seek_policy_probe_result: Dictionary = {}
var selected_features_probe_result: Dictionary = {}


func _on_display_debug_command(_id: int, payload: String) -> void:
	var command: Variant = JSON.parse_string(payload)
	if not command is Dictionary:
		return
	var operation := str(command.get("operation", ""))
	if operation == "selected_features_ui" and OS.is_debug_build():
		var probe := preload("res://scripts/selected_features_device_probe.gd").new()
		selected_features_probe_result = await probe.run(
			self, str(command.step), str(command.request_key)
		)
		video._write_debug_report()
	elif operation == "seek_policy_ui" and OS.is_debug_build():
		var probe := preload("res://scripts/seek_policy_device_probe.gd").new()
		seek_policy_probe_result = await probe.run(
			self, str(command.step), str(command.get("marker_id", ""))
		)
		seek_policy_probe_result.request_key = str(command.request_key)
		video._write_debug_report()
	elif operation in ["display_quality", "sharpness"]:
		_on_setting_changed(operation, command.get("value", 0))
	elif operation in ["restart_app", "quit_app"] and OS.is_debug_build():
		_finish_app(operation == "restart_app")
	elif operation == "media_library_ui" and OS.is_debug_build():
		var probe := preload("res://scripts/media_server_device_probe.gd").new()
		add_child(probe)
		probe.start(self, command)
	elif operation == "display_menu":
		_show_library_menu()
		library_menu.section = library_menu.Section.SETTINGS
		library_menu.tab = library_menu.DISPLAY_TAB
		library_menu.refresh()
	elif operation == "player_menu":
		_show_player_menu()


var _finishing_app := false


func _finish_app(restart: bool) -> void:
	if _finishing_app:
		return
	_finishing_app = true
	_save_playback_adjustments()
	video.close_video()
	settings.save(settings_path)
	DiagnosticLog.record("app_restart" if restart else "app_close")
	if PlatformMethods.supports(platform_plugin, "finish_app"):
		platform_plugin.finish_app(restart)
	else:
		if restart:
			OS.set_restart_on_exit(true)
		get_tree().quit()
