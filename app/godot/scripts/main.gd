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
const PhotoDisplay := preload("res://scripts/photo_display.gd")
const PhotoMenu := preload("res://scripts/photo_menu.gd")
const PhotoHandGestures := preload("res://scripts/photo_hand_gestures.gd")
const PhotoPalmSwipe := preload("res://scripts/photo_palm_swipe.gd")
const ImageInfo := preload("res://scripts/image_info.gd")
const PlayerMenu := preload("res://scripts/player_menu.gd")
const MediaSurface := preload("res://scripts/media_surface.gd")
const I18n := preload("res://scripts/i18n.gd")
const PlatformMethods := preload("res://scripts/platform_methods.gd")
const FpsOverlay := preload("res://scripts/fps_overlay.gd")
const Background := preload("res://scripts/app_background.gd")
const ViewFollow := preload("res://scripts/view_follow.gd")

const InputCoordinator := preload("res://scripts/input_coordinator.gd")
var _input := InputCoordinator.new(self)

const PhotoCoordinator := preload("res://scripts/photo_coordinator.gd")
var _photos := PhotoCoordinator.new(self)

const PlaybackCoordinator := preload("res://scripts/playback_coordinator.gd")
var _playback := PlaybackCoordinator.new(self)

const PlayerSettingsController := preload("res://scripts/player_settings_controller.gd")
var _preferences := PlayerSettingsController.new(self)

const XrPresentationCoordinator := preload("res://scripts/xr_presentation_coordinator.gd")
var _presentation := XrPresentationCoordinator.new(self)

var display := DisplayController.new()
var display_quality := Quality.DEFAULT
## GPU name used for the quality tier; empty reads the active renderer (tests may preset it).
var gpu_adapter := ""
var low_end_gpu := false
var status_label: Label3D
var report_timer: Timer
var platform_plugin: Object
var last_request := 0
var android_report: Dictionary = {}
var photo: Node3D
var photo_active: bool:
	get:
		return _photos.photo_active
	set(value):
		_photos.photo_active = value
var video_menu: Node3D
var photo_menu: Node3D
var video: Node3D
const PlaybackQueue := preload("res://scripts/playback_queue.gd")
var playback_queue := PlaybackQueue.new()
var video_queue: Array[Dictionary]:
	get:
		return playback_queue.items
	set(value):
		playback_queue.replace(value)
var _queue_add_mode: bool:
	get:
		return _playback._queue_add_mode
	set(value):
		_playback._queue_add_mode = value
var _queue_end_key: String:
	get:
		return _playback._queue_end_key
	set(value):
		_playback._queue_end_key = value
var calibration_board: Node3D
var right_controller: XRController3D
var left_controller: XRController3D
var hand_pointers := {}
var photo_hands := PhotoHandGestures.new()
var photo_swipe := PhotoPalmSwipe.new()
var memory_swipe := preload("res://scripts/memory_swipe.gd").new()
var _gallery_save_after: int:
	get:
		return _photos._gallery_save_after
	set(value):
		_photos._gallery_save_after = value
var _gallery_saved_state: String:
	get:
		return _photos._gallery_saved_state
	set(value):
		_photos._gallery_saved_state = value
var _photo_open_hide_controls: bool:
	get:
		return _photos._photo_open_hide_controls
	set(value):
		_photos._photo_open_hide_controls = value
var _photo_pointer_hand: String:
	get:
		return _photos._photo_pointer_hand
	set(value):
		_photos._photo_pointer_hand = value
var _inspect_hand: String:
	get:
		return _photos._inspect_hand
	set(value):
		_photos._inspect_hand = value
var _inspect_blocked: Dictionary:
	get:
		return _photos._inspect_blocked
	set(value):
		_photos._inspect_blocked = value
var _inspect_desktop_ray: Variant:
	get:
		return _photos._inspect_desktop_ray
	set(value):
		_photos._inspect_desktop_ray = value
var hand_marks := {}
var input_visuals: Node3D
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var fps_overlay: Label3D
var stick_controls := StickControls.new()
var recent_menu: Node3D
var player_menu: Node3D
var menu_compositor: Node3D
const LIBRARY_DISTANCE_LIMITS := Vector2(0.8, 3.0)
var library_distance: float:
	get:
		return _presentation.library_distance
	set(value):
		_presentation.library_distance = value
var _library_grab: Dictionary:
	get:
		return _input._library_grab
	set(value):
		_input._library_grab = value
var _system_recenter_pending: bool:
	get:
		return _presentation._system_recenter_pending
	set(value):
		_presentation._system_recenter_pending = value
var settings: ConfigFile:
	get:
		return _preferences.settings
	set(value):
		_preferences.settings = value
var settings_path: String:
	get:
		return _preferences.settings_path
	set(value):
		_preferences.settings_path = value
var background: Node
var view_follow: ViewFollow:
	get:
		return _presentation.view_follow
	set(value):
		_presentation.view_follow = value
var temporary_passthrough: bool:
	get:
		return _presentation.temporary_passthrough
	set(value):
		_presentation.temporary_passthrough = value
var reclining_mode: bool:
	get:
		return _presentation.reclining_mode
	set(value):
		_presentation.reclining_mode = value


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
	display.status_changed.connect(_update_status)
	display.status_changed.connect(_on_input_session_changed)
	_preferences.load_preferences()
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
	display.configure(get_viewport(), world.environment, XRServer.find_interface("OpenXR"), desktop)
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
	video.auto_depth = false
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
	photo = PhotoDisplay.new()
	photo.name = "PhotoDisplay"
	photo.auto_depth = false
	photo.load_mode_lock(settings.get_value("photo", "mode_lock", {}))
	photo.catalog = video.recent_files
	photo.history_enabled = video.history_enabled
	photo.changed.connect(_on_photo_changed)
	photo.mode_lock_changed.connect(_on_mode_lock_changed.bind("photo"))
	photo.restore_view_settings(settings)
	add_child(photo)
	photo.sharpness = Quality.load_sharpness(settings, low_end_gpu)
	photo.view_camera = camera
	display.set_foveation(int(settings.get_value("video", "foveation", 0)))
	recent_menu = LibraryMenu.new()
	recent_menu.catalog = video.recent_files
	recent_menu.list_view = bool(settings.get_value("library", "list_view", false))
	recent_menu.browse_memory.configure(
		bool(settings.get_value("library", "browse_memory", true)), video.history_enabled
	)
	recent_menu.layout_changed.connect(func(): _place_menu(recent_menu))
	recent_menu.file_actions.load(settings.get_value("library", "orders", {}))
	recent_menu.file_actions.set_enabled(bool(settings.get_value("library", "file_editing", false)))
	recent_menu.file_renamed.connect(_on_file_renamed)
	recent_menu.current_file_provider = func(): return _viewer().local_uri
	recent_menu.file_delete_preparing.connect(_prepare_file_delete)
	recent_menu.file_deleted.connect(_forget_deleted_file)
	recent_menu.settings_provider = _library_settings
	recent_menu.chosen.connect(_on_library_chosen)
	recent_menu.storage_eject_requested.connect(_on_storage_eject_requested)
	recent_menu.storage_removed.connect(_release_storage_readers)
	recent_menu.player_requested.connect(
		func():
			if _queue_add_mode:
				_queue_action("queue_done")
			else:
				_show_player_menu()
	)
	recent_menu.queue_requested.connect(_queue_action)
	recent_menu.setting_changed.connect(_on_setting_changed)
	recent_menu.setting_previewed.connect(_on_playback_adjustment)
	recent_menu.recenter_requested.connect(_recenter)
	_connect_session_controls(recent_menu)
	add_child(recent_menu)
	if Engine.has_singleton("QuestPlayer"):
		var plugin := Engine.get_singleton("QuestPlayer")
		recent_menu.attach_platform(plugin)
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
	player_menu.recent_requested.connect(
		func():
			recent_menu.compact = true
			_show_recent_menu()
	)
	player_menu.seek_requested.connect(_on_menu_seek)
	player_menu.bookmark_requested.connect(_on_bookmark_request)
	player_menu.setting_requested.connect(_on_player_setting)
	player_menu.adjustment_requested.connect(_on_playback_adjustment)
	player_menu.adjustment_committed.connect(_save_playback_adjustments)
	player_menu.subtitle_requested.connect(video.set_subtitle_track)
	player_menu.depth_strength_requested.connect(_on_depth_strength.bind(false))
	player_menu.depth_strength_committed.connect(_save_depth_strength)
	_connect_session_controls(player_menu)
	add_child(player_menu)
	video_menu = player_menu
	photo_menu = PhotoMenu.new()
	photo_menu.state_provider = photo.snapshot
	photo_menu.queue_provider = func(): return photo.queue
	photo_menu.action_requested.connect(_on_photo_action)
	photo_menu.adjustment_requested.connect(_on_photo_adjustment)
	photo_menu.adjustment_committed.connect(_save_photo_adjustments)
	photo_menu.depth_strength_requested.connect(_on_depth_strength.bind(true))
	photo_menu.depth_strength_committed.connect(_save_depth_strength)
	photo_menu.recent_requested.connect(_show_recent_menu)
	_connect_session_controls(photo_menu)
	add_child(photo_menu)
	menu_compositor = preload("res://scripts/xr_menu_compositor.gd").new()
	add_child(menu_compositor)
	menu_compositor.configure(
		[recent_menu, video_menu, photo_menu],
		camera,
		not display.preview and display.xr != null and display.xr.is_initialized(),
		func(): return display.session_state
	)
	background = Background.new()
	background.choice = str(settings.get_value("appearance", "background", "belfast"))
	background.custom_path = str(settings.get_value("appearance", "custom_path", ""))
	background.custom_title = str(settings.get_value("appearance", "custom_title", ""))
	background.custom_orientation = int(settings.get_value("appearance", "custom_orientation", 1))
	background.yaw = fposmod(float(settings.get_value("appearance", "background_yaw", 0.0)), 360.0)
	background.brightness = clampf(
		float(settings.get_value("appearance", "background_brightness", 1.0)), 0.5, 1.25
	)
	background.changed.connect(_on_background_changed)
	background.custom_saved.connect(_on_custom_background_saved)
	add_child(background)
	if Engine.has_singleton("QuestPlayer"):
		platform_plugin = Engine.get_singleton("QuestPlayer")
		if PlatformMethods.supports(platform_plugin, "set_ui_language"):
			platform_plugin.set_ui_language(I18n.choice)
		platform_plugin.connect("capabilities_ready", _on_capabilities_ready)
		platform_plugin.connect("android_lifecycle", _on_android_lifecycle)
		pass
		request_capabilities()
	else:
		Log.record("android_plugin_unavailable", {"desktop_preview": desktop})
	report_timer = Timer.new()
	report_timer.wait_time = 2.0
	report_timer.timeout.connect(_save_report)
	add_child(report_timer)
	report_timer.start()
	_update_status()
	if not OS.get_cmdline_user_args().has("--mpv-diagnostic-2d"):
		_show_recent_menu()
	Log.record(
		"ui_ready",
		{
			"library_visible": recent_menu.visible,
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
			if recent_menu.section == recent_menu.Section.RECENT:
				recent_menu.refresh()
	)
	recent_scan.start(video.recent_files, platform_plugin)
	# Source distribution: private capture automation is excluded.


## Desktop preview: dragging with the mouse moves the picture, the wheel zooms immersive views.
func _unhandled_input(event: InputEvent) -> void:
	_input._unhandled_input(event)


func _unhandled_key_input(event: InputEvent) -> void:
	_input._unhandled_key_input(event)


# Menus are ray + trigger only. A list row clicks on release unless the ray dragged to scroll.
# Controller grip drags placement; grip plus the same hand's stick adjusts distance.
# Optical-hand pinches retain their existing content gestures.
func _on_controller_release(action: String, hand: String = "") -> void:
	_input._on_controller_release(action, hand)


func _on_pointer_release(action: String, hand: String) -> void:
	_input._on_pointer_release(action, hand)


func _on_controller_button(action: String, hand: String = "") -> void:
	_input._on_controller_button(action, hand)


func _on_pointer_button(action: String, hand: String) -> void:
	_input._on_pointer_button(action, hand)


## Menus shown at launch are placed before the headset reports a pose (the camera is still at
## the floor origin): once the head is first tracked, recenter and place everything again.
var _head_placed: bool:
	get:
		return _presentation._head_placed
	set(value):
		_presentation._head_placed = value


func _head_tracked() -> bool:
	return _presentation._head_tracked()


func _on_system_recentered() -> void:
	_presentation._on_system_recentered()


func _apply_system_recenter() -> void:
	_presentation._apply_system_recenter()


func _process(delta: float) -> void:
	screen_layout.tick()
	if is_instance_valid(playback_feedback):
		playback_feedback.tick()
	_apply_system_recenter()
	_update_view_follow()
	_refresh_session_controls()
	if _gallery_save_after > 0 and Time.get_ticks_msec() >= _gallery_save_after:
		_gallery_save_after = 0
		_save_photo_adjustments()
	_update_hand_input(delta)
	if video and is_instance_valid(_viewer().get("panel")):
		display.set_flat_surface_visible(
			_viewer().panel.visible and _viewer().geometry == Geometry.Geometry.FLAT
		)
	if not _head_placed and _head_tracked():
		_head_placed = true
		if not view_follow.enabled:
			_recenter()
	if video and _viewer().local_uri != _screen_uri:
		_screen_uri = _viewer().local_uri
		if not _screen_uri.is_empty():
			if not photo_active and screen_layout.fixed():
				screen_layout.restore()
			if not photo_active or photo.gallery.mode == 0 or photo.placement_pending:
				_place_screen()
			if photo_active:
				photo.placement_pending = false
	_update_photo_inspect()
	_update_grab()
	_update_library_grab()
	if photo_active and not _active_menu() and not photo.inspect:
		for hand in ["left_hand", "right_hand"]:
			var ray: Variant = _ray(hand)
			photo.gallery.update_pointer(
				hand,
				ray[0] if ray != null else Vector3.ZERO,
				ray[1] if ray != null else Vector3.ZERO,
				ray != null
			)
	if photo:
		var targeted: bool = (
			photo_active
			and not _active_menu()
			and not photo.inspect
			and (photo.gallery.hover.values().has(photo.index) or photo.gallery.focus >= 0)
		)
		var held: bool = targeted and (not photo_hands.owners.is_empty() or not _grab.is_empty())
		photo.set_target_feedback(2 if held else (1 if targeted else 0))
	_update_player_menu_anchor()
	var right := _stick(right_controller)
	var left := _stick(left_controller)
	_update_corner_hover()
	_update_flat_grab_stick(left, right, delta)
	_process_sticks(left, right, delta)


func _process_sticks(left: Vector2, right: Vector2, delta: float) -> void:
	_input._process_sticks(left, right, delta)


func _update_controls_visibility(menu: Node3D) -> void:
	_input._update_controls_visibility(menu)


func _stick(controller: XRController3D) -> Vector2:
	return _input._stick(controller)


func _hand_tracker(hand: String) -> XRHandTracker:
	return _input._hand_tracker(hand)


func _hand_action_tracker(hand: String) -> XRPositionalTracker:
	return _input._hand_action_tracker(hand)


func _meta_aim_tracker(hand: String) -> XRPositionalTracker:
	return _input._meta_aim_tracker(hand)


func _input_focused() -> bool:
	return _input._input_focused()


func _controller_allowed(hand: String) -> bool:
	return _input._controller_allowed(hand)


func _controller_ray(hand: String) -> Variant:
	return _input._controller_ray(hand)


func _update_hand_input(delta: float) -> void:
	_input._update_hand_input(delta)


func _is_photo_hand(hand: String) -> bool:
	return _input._is_photo_hand(hand)


func _dispatch_hand_input(inputs: Dictionary, _delta: float = 1.0 / 72.0) -> void:
	_input._dispatch_hand_input(inputs, _delta)


func _cancel_pointer(hand: String) -> void:
	_input._cancel_pointer(hand)


func _on_input_session_changed() -> void:
	_input._on_input_session_changed()


func _hand_input_report() -> Dictionary:
	return _input._hand_input_report()


static func _input_pose_tracked(tracker: XRPositionalTracker, pose_name: String) -> bool:
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
var _grab: Dictionary:
	get:
		return _input._grab
	set(value):
		_input._grab = value
var _trigger_taps := {}


func _begin_library_grab(hand: String) -> void:
	_input._begin_library_grab(hand)


func _update_library_grab() -> void:
	_input._update_library_grab()


func _update_library_grab_stick(left: Vector2, right: Vector2, delta: float) -> void:
	_input._update_library_grab_stick(left, right, delta)


func _begin_picture_press(hand: String) -> void:
	_input._begin_picture_press(hand)


func _update_flat_grab_stick(left: Vector2, right: Vector2, delta: float) -> void:
	_input._update_flat_grab_stick(left, right, delta)


func _eye() -> Vector3:
	if is_instance_valid(_viewer().view_camera) and _viewer().view_camera.is_inside_tree():
		return _viewer().view_camera.global_position
	return Vector3(0, 1.6, 0)


func _ray(hand: String) -> Variant:
	return _input._ray(hand)


## A ray near a flat screen corner shows its bracket: pressing there resizes.
func _update_corner_hover() -> void:
	_input._update_corner_hover()


func _begin_grab(hand: String, action: String = "grip_click") -> void:
	_input._begin_grab(hand, action)


func _update_grab() -> void:
	_input._update_grab()


## Yaw (positive left) and pitch (positive up) of a direction.
static func _ray_angles(direction: Vector3) -> Vector2:
	var unit := direction.normalized()
	return Vector2(atan2(-unit.x, -unit.z), asin(clampf(unit.y, -1.0, 1.0)))


## The picture follows the pointer: immersive views turn, the flat screen moves around the head
## at its distance and keeps facing the eyes.
func _turn_picture(yaw: float, pitch: float) -> void:
	_presentation._turn_picture(yaw, pitch)


## The flat screen nearer (negative) or farther along the line from the eyes, still facing them.
func _push_screen(amount: float) -> void:
	_presentation._push_screen(amount)


func _save_screen() -> void:
	_presentation._save_screen()


## Right stick press: the picture back at its natural size and distance (the curve stays). It stays
## where it is: only the menu's recenter button brings the screen in front of the head again.
func _reset_picture() -> void:
	_presentation._reset_picture()


func _update_menu_pointer(hand: String, pressed: bool = false) -> bool:
	return _presentation._update_menu_pointer(hand, pressed)


const CONTROLS_HIDE_MS := 5000
var _menu_touched_ms: int:
	get:
		return _presentation._menu_touched_ms
	set(value):
		_presentation._menu_touched_ms = value


func _viewer() -> Node3D:
	return photo if photo_active and photo else video


func _on_library_chosen(uri: String, title: String) -> void:
	_playback._on_library_chosen(uri, title)


func _on_file_renamed(old_uri: String, new_uri: String, title: String) -> void:
	video.recent_files.relocate(old_uri, new_uri, title)
	if not video.recent_files.save():
		recent_menu.file_actions.rename.migration_failed = true
	video.mode_memory.relocate(old_uri, new_uri)
	if not video.mode_memory.save():
		recent_menu.file_actions.rename.migration_failed = true
	photo.mode_memory.relocate(old_uri, new_uri)
	if not photo.mode_memory.save():
		recent_menu.file_actions.rename.migration_failed = true
	if not video.bookmark_store.relocate(
		old_uri, new_uri, title, int(recent_menu.file_actions.target.get("size", -1))
	):
		recent_menu.file_actions.rename.migration_failed = true
	LibraryMenu.Thumbnails.relocate(old_uri, new_uri)
	playback_queue.relocate(old_uri, new_uri, title)
	_save_queue()
	_update_thumbnail_protection()


func _prepare_file_delete(uri: String) -> void:
	if video.local_uri == uri or video.local_uri.begins_with(uri.trim_suffix("/") + "/"):
		video.close_video()
	if (
		photo.local_uri == uri
		or photo.local_uri.begins_with(uri.trim_suffix("/") + "/")
		or photo.queue.any(func(item): return str(item.get("uri", "")) == uri or str(item.get("uri", "")).begins_with(uri.trim_suffix("/") + "/"))
	):
		photo.close_image()
		photo_active = false
		if photo_menu:
			photo_menu.dismiss()
		player_menu = video_menu
	_grab = {}
	stick_controls.suspend()


func _forget_deleted_file(uri: String) -> void:
	video_queue = video_queue.filter(
		func(item): return ( str(item.get("uri", "")) != uri and not str(item.get("uri", "")).begins_with(uri.trim_suffix("/") + "/") )
	)
	_save_queue()
	# Photo preload readers must be released before removing a queued image.
	if photo.queue.any(func(item): return str(item.get("uri", "")) == uri):
		photo.close_image()
		photo_active = false
		player_menu = video_menu
	for entry in video.recent_files.list_recent():
		if str(entry.uri) == uri or str(entry.uri).begins_with(uri.trim_suffix("/") + "/"):
			video.recent_files.forget(str(entry.uri))
	video.recent_files.save()
	_update_thumbnail_protection()


func _on_storage_eject_requested(volume: Dictionary) -> void:
	_release_storage_readers(volume)
	recent_menu.finish_storage_release(str(volume.get("id", "")))


func _release_storage_readers(volume: Dictionary) -> void:
	if video and StorageVolume.contains_uri(volume, video.local_uri):
		video.close_video()
	video_queue = video_queue.filter(
		func(item): return not StorageVolume.contains_uri(volume, str(item.get("uri", "")))
	)
	_save_queue()
	if photo and photo.release_storage(volume):
		photo_active = false
		if photo_menu:
			photo_menu.dismiss()
		player_menu = video_menu
	_grab = {}
	stick_controls.suspend()


func _adjacent_video(direction: int) -> Dictionary:
	return _playback._adjacent_video(direction)


func _navigate_video(direction: int) -> void:
	_playback._navigate_video(direction)


func _queue_action(operation: String) -> void:
	_playback._queue_action(operation)


func _save_queue() -> void:
	_playback._save_queue()


func _advance_queue(session_id: int, uri: String) -> void:
	_playback._advance_queue(session_id, uri)


func _on_photo_changed() -> void:
	_photos._on_photo_changed()


func _on_photo_adjustment(key: String, value: Variant) -> void:
	_photos._on_photo_adjustment(key, value)


func _save_photo_adjustments() -> void:
	_photos._save_photo_adjustments()


func _toggle_photo_inspect(hand: String = "") -> void:
	_photos._toggle_photo_inspect(hand)


func _close_photo_inspect(show_controls: bool = true) -> void:
	_photos._close_photo_inspect(show_controls)


func _update_photo_inspect() -> void:
	_photos._update_photo_inspect()


func _on_photo_action(operation: String) -> void:
	_photos._on_photo_action(operation)


var _screen_uri := ""
var _player_menu_anchor_key: Array = []
var _player_menu_anchor_eye := Vector3.ZERO


func _canvas_menu_anchor_key() -> Array:
	return _presentation._canvas_menu_anchor_key()


## Full tracked pose is retained for media follow; reclining menus also use it.
func _head_pose() -> Variant:
	return _presentation._head_pose()


## Menus use world up and the horizontal head direction. Looking straight up or
## down uses the head's right axis to avoid an undefined horizontal forward.
static func _upright_pose(head: Transform3D) -> Transform3D:
	return MediaSurface.upright_pose(head)


func _menu_head_pose(head: Transform3D) -> Transform3D:
	return _presentation._menu_head_pose(head)


## Reclining placement uses the full gaze; ordinary placement stays upright.
func _view_pose(distance: float, drop: float) -> Variant:
	return _presentation._view_pose(distance, drop)


func _place_screen(recenter: bool = false) -> void:
	_presentation._place_screen(recenter)


func _flat_followable(surface: Node3D) -> bool:
	return _presentation._flat_followable(surface)


func _surface_key(surface: Node3D) -> StringName:
	return _presentation._surface_key(surface)


func _menu_key(menu: Node3D) -> StringName:
	return _presentation._menu_key(menu)


func _follow_screen_pose(surface: Node3D, head: Transform3D, recenter: bool = false) -> Transform3D:
	return _presentation._follow_screen_pose(surface, head, recenter)


func _capture_follow_screen(surface: Node3D, head: Variant) -> void:
	_presentation._capture_follow_screen(surface, head)


func _update_view_follow() -> void:
	_presentation._update_view_follow()


func _place_menu(menu: Node3D) -> void:
	_presentation._place_menu(menu)


func _active_menu() -> Node3D:
	return _presentation._active_menu()


func _update_player_menu_anchor() -> void:
	_presentation._update_player_menu_anchor()


func _toggle_player_menu() -> void:
	_presentation._toggle_player_menu()


func _show_player_menu() -> void:
	_presentation._show_player_menu()


func _show_recent_menu(preserve_navigation: bool = false) -> void:
	_presentation._show_recent_menu(preserve_navigation)


func _canvas_controls_snapshot() -> Dictionary:
	return _presentation._canvas_controls_snapshot()


func _restore_seek_settings() -> void:
	_preferences._restore_seek_settings()


func _library_settings() -> Dictionary:
	return _preferences._library_settings()


func _on_setting_changed(key: String, value: Variant) -> void:
	_preferences._on_setting_changed(key, value)


func _on_menu_action(operation: String) -> void:
	_playback._on_menu_action(operation)


func _on_menu_seek(position_ms: int) -> void:
	_playback._on_menu_seek(position_ms)


func _on_player_setting(key: String, value: Variant) -> void:
	_playback._on_player_setting(key, value)


func _on_bookmark_request(operation: String, marker_id: String, scope: String) -> void:
	_playback._on_bookmark_request(operation, marker_id, scope)


## Persist accepted depth adjustments for the current media.
func _on_depth_strength(strength: float, for_photo: bool) -> void:
	var viewer: Node3D = photo if for_photo else video
	if viewer.set_depth_strength(strength):
		settings.set_value(
			"photo" if for_photo else "video", "depth_strength", viewer.depth_strength
		)
		_remember_auto_depth(viewer.auto_depth)


func _remember_auto_depth(enabled: bool) -> void:
	if settings.has_section_key("effects", "auto_3d"):
		settings.erase_section_key("effects", "auto_3d")
	video.auto_depth = false
	photo.auto_depth = false


func _on_mode_lock_changed(lock: Dictionary, media_kind: String) -> void:
	_preferences._on_mode_lock_changed(lock, media_kind)


func _save_depth_strength() -> void:
	# Keep dragging live without writing settings on every pointer movement.
	settings.save(settings_path)


func _menu_state() -> Dictionary:
	return _presentation._menu_state()


## Preserve native titles/IDs for sidecar recognition; localize their presentation only.
func _audio_option_label(track: Dictionary) -> String:
	return _playback._audio_option_label(track)


func _audio_track_name(details: Dictionary) -> String:
	return _playback._audio_track_name(details)


func _menu_error() -> String:
	return _playback._menu_error()


func _apply_stick_actions(actions: Array[Dictionary], delta: float = 1.0 / 72.0) -> void:
	_input._apply_stick_actions(actions, delta)


func _toggle_display() -> void:
	_presentation._toggle_display()


func _on_video_changed() -> void:
	_playback._on_video_changed()


func _on_video_thumbnail_ready(_uri: String) -> void:
	_playback._on_video_thumbnail_ready(_uri)


var _thumbnail_history_sequence := -1


func _update_thumbnail_protection() -> void:
	_playback._update_thumbnail_protection()


func _on_background_changed() -> void:
	_presentation._on_background_changed()


func _update_background() -> void:
	_presentation._update_background()


func _connect_session_controls(menu: Node3D) -> void:
	_presentation._connect_session_controls(menu)


func _on_menu_placement_changed(menu: Node3D) -> void:
	_presentation._on_menu_placement_changed(menu)


func _set_reclining_mode(enabled: bool) -> void:
	_presentation._set_reclining_mode(enabled)


func _person_passthrough() -> bool:
	return _presentation._person_passthrough()


func _session_controls_state() -> Dictionary:
	return _presentation._session_controls_state()


func _refresh_session_controls() -> void:
	_presentation._refresh_session_controls()


func _on_session_control(operation: String) -> void:
	_presentation._on_session_control(operation)


func _save_background() -> void:
	_preferences._save_background()


func _on_custom_background_saved(path: String, title: String, orientation: int) -> void:
	_preferences._on_custom_background_saved(path, title, orientation)


func _recenter() -> void:
	_presentation._recenter()


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
	_save_report()


func _on_android_lifecycle(event: String) -> void:
	Log.record("android_lifecycle", {"event": event})
	if event == "resume":
		request_capabilities()
	elif event == "pause" and video:
		video.checkpoint_playback()


func _save_report() -> void:
	var report := {
		"schema_version": 1,
		"app_version": ProjectSettings.get_setting("application/config/version"),
		"engine": Engine.get_version_info(),
		"captured_unix_seconds": Time.get_unix_time_from_system(),
		"xr": display.capabilities(),
		"android": android_report,
		"stage": "MP04_shared_MPV_RVM_display_development",
		"video_implemented": true,
		"video_device_validation": "pending",
		"media": video.media.snapshot() if video else {},
		"video_layout": video.layout_snapshot() if video else {},
		"active_media": "image" if photo_active else "video",
		"hand_input": _hand_input_report(),
		"input_visuals": input_visuals.snapshot() if input_visuals else {},
		"background": background.choice if background else "",
		"photo": photo.snapshot() if photo else {},
		"rvm_implemented": true,
		"rvm_video_integrated": true,
		"mpv_rvm_device_validation": "pending",
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
	_update_status()


func _update_status() -> void:
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
			"\n%s | %s | %s | %s\n%s | RVM %s"
			% [
				video.display_name.left(42),
				video.media.state,
				"SBS" if video.stereo_sbs else "2D",
				video.layout_snapshot().geometry,
				(
					"Alpha on"
					if video.alpha_enabled
					else ("Preparing Alpha" if video.alpha_requested else "Normal playback")
				),
				video.profile
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
	_preferences._on_playback_adjustment(key, value)


func _save_playback_adjustments() -> void:
	_preferences._save_playback_adjustments()


func _fps_sample() -> Dictionary:
	if not video or photo_active or not video.panel or not video.panel.visible:
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
		selected_features_probe_result = await probe.run(self, str(command.step), str(command.request_key))
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
	elif operation in ["restart_app", "quit_app"]:
		recent_menu._activate(
			recent_menu.RESTART_APP if operation == "restart_app" else recent_menu.QUIT_APP
		)
	elif operation == "media_library_ui" and OS.is_debug_build():
		var probe := preload("res://scripts/media_server_device_probe.gd").new()
		add_child(probe)
		probe.start(self, command)
	elif operation == "display_menu":
		_show_recent_menu()
		recent_menu.section = recent_menu.Section.SETTINGS
		recent_menu.tab = recent_menu.DISPLAY_TAB
		recent_menu.refresh()
	elif operation == "player_menu":
		_show_player_menu()


var _finishing_app := false


func _finish_app(restart: bool) -> void:
	if photo and _gallery_save_after > 0:
		_save_photo_adjustments()
	if _finishing_app:
		return
	_finishing_app = true
	_save_playback_adjustments()
	video.close_video()
	photo.close_image()
	settings.save(settings_path)
	DiagnosticLog.record("app_restart" if restart else "app_close")
	if PlatformMethods.supports(platform_plugin, "finish_app"):
		platform_plugin.finish_app(restart)
	else:
		if restart:
			OS.set_restart_on_exit(true)
		get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and photo and _gallery_save_after > 0:
		_save_photo_adjustments()
