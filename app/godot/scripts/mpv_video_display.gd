extends "res://scripts/media_surface.gd"

signal changed
signal thumbnail_ready(uri: String)

const PlatformMethods := preload("res://scripts/platform_methods.gd")
const State := preload("res://scripts/mpv_media_state.gd")
const Thumbnails := preload("res://scripts/thumbnail_cache.gd")
const Binding := preload("res://scripts/pair_texture_binding.gd")
const PlaybackControl := preload("res://scripts/playback_control.gd")
const SeekPolicy := preload("res://scripts/seek_policy.gd")
var seek_mode := SeekPolicy.DEFAULT
var bookmark_seek_mode := SeekPolicy.GLOBAL
var _last_seek_mode := SeekPolicy.DEFAULT
const Log := preload("res://scripts/diagnostic_log.gd")
const SubtitleState := preload("res://scripts/mpv_subtitle_state.gd")
const ModeMemory := preload("res://scripts/file_mode_memory.gd")
const StereoView := preload("res://scripts/stereo_view.gd")
var viewing_eye := 0  # 0 binocular; 1/2 duplicate the logical left/right view after eye swap.
var stereo_horizontal := 0.0
var stereo_vertical := 0.0
var _stereo_view_dirty := false
var _immersive_dirty := false
const RecentFiles := preload("res://scripts/recent_files.gd")
const BookmarkStore := preload("res://scripts/bookmark_store.gd")
var bookmark_store := BookmarkStore.new()
var _bookmark_metadata: Dictionary = {}
var _bookmark_media_id := ""
var _bookmark_scope_sequence := 0
var _bookmark_cache_revision := -1
var _bookmark_rows: Array = []
const Naming := preload("res://scripts/media_naming.gd")
const StereoDetection := preload("res://scripts/stereo_detection.gd")
var _auto_stereo := true
var _stereo_detection := StereoDetection.new()
var _stereo_detection_busy := false
var _stereo_capture_busy := false
var _stereo_thread: Thread
var _stereo_pin: Dictionary = {}
var _stereo_capture_binding: RefCounted

var media := State.new()
var control := PlaybackControl.new()
var diagnostics: Node
var diagnostic_ui_provider: Callable
var platform: Object
var alpha_encoding := 1
var alpha_enabled := false
## Pick the clone-voice track (an extra M4A beside the video) whenever a video has one.
var prefer_clone_voice := false
## Naming supplies the initial packed-mask preference; users can override it for untagged media.
var packed_file := false
var packed_alpha := false
var packed_alpha_forced := false
var reclining_mode := false
## What the file name left open; filled from the first frame's shape, then cleared.
var _layout_pending: Variant = null
var _layout_basename := ""
var reuse_last_mode := false
var last_video_mode: Dictionary = {}
var _clone_applied := false
var loop_enabled := false
var requested_play := true
const TrackPreference := preload("res://scripts/track_preference.gd")
var _track_choices := {}
var _tracks_pending := {}
var audio_track_id := -1
var subtitle_delay_ms := 0
var audio_delay_ms := 0
var external_subtitle_uri := ""
var subtitle_encodings: Dictionary = {}
var _sync_pending := false
var _subtitle_pick := 0
var _subtitle_pick_session := 0
var _pending_external_uri := ""
var _subtitle_import_command := 0
var _subtitle_import_uri := ""
var _subtitle_loading := false
var _subtitle_requested_uri := ""
var _subtitle_import_floor := 0
var subtitles := SubtitleState.new()
var dual_subtitles := preload("res://scripts/dual_subtitles.gd").new(self)
## Text subtitles: on the flat screen near its lower edge; in immersive modes floating at
## a video-local projection with stereo disparity controlled by [subtitle_distance].
var playback_speed := 1.0
var hdr_to_sdr := false
var layer_shown := false
var layer_controller: RefCounted
var surface_requested := false
var force_shader_output := false
var output_width_choice := -1
var _surface_context := {}
var _surface_eof_ms := -1
var _fallback_queued := false
var _fallback_pending := false
var _next_layout_override := {}
const StereoFocus := preload("res://scripts/stereo_focus.gd")
var autofocus := StereoFocus.new()
var _focus_probe := StereoFocus.Probe.new()
var low_end_gpu := false
var _focus_last_frame: Array = []
var stereo_focus_mode := 0  # Off, Auto, Manual
var stereo_focus := 1.5
var _focus_due_ms := 0
var _focus_busy := false
var _focus_thread: Thread
var _focus_pin := {}
var _focus_binding: RefCounted
var _focus_generation := 0
var _focus_dirty := false
var _focus_parameters: Array = []
var subtitle_transparency := 0.0:
	set(value):
		subtitle_transparency = preload("res://scripts/playback_preferences.gd").transparency(value)
var subtitle_follow_view := false
var subtitle_follow := preload("res://scripts/subtitle_follow.gd").new()
var _flat_caption_canvas: Node
var _faded_caption: MeshInstance3D
var subtitle_size := 1.0:
	set(value):
		subtitle_size = clampf(value, 0.5, 2.0) if is_finite(value) else 1.0
const SUBTITLE_BELOW_GAP := 0.02  # Fixed metres, independent of screen size/distance.
var subtitle_below_screen := false
var subtitle_flat_position := 0.0:
	set(value):
		subtitle_flat_position = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
var _subtitle_surface: MeshInstance3D
var _subtitle_material: ShaderMaterial
var caption: Label3D
const ColorGrade := preload("res://scripts/color_grade.gd")
var color_grade := ColorGrade.new()
var default_color_grade: Dictionary = {}
var _color_grade_changed := false
const SubtitleDepth := preload("res://scripts/subtitle_depth.gd")
var subtitle_distance := 5.0:
	set(value):
		subtitle_distance = SubtitleDepth.distance(value)
var subtitle_position := SubtitleDepth.DEFAULT_POSITION:
	set(value):
		subtitle_position = SubtitleDepth.position(value)
var subtitle_direction := 0:
	set(value):
		subtitle_direction = clampi(value, 0, 1)
const CaptionPalette := preload("res://scripts/caption_palette.gd")
var subtitle_palette := 0
const ProjectedSubtitles := preload("res://scripts/projected_subtitles.gd")
var projected_subtitles: Node
const CAPTION_DROP := 0.244  # radians below the line of sight (14 degrees)
var _subtitle_poll_ms := 0
var _subtitle_received_ms := 0
var mode_memory := ModeMemory.new()
var _remember_file := false
var recent_files := RecentFiles.new()
## Settings: when off, nothing new is recorded and videos start from the beginning.
var server_playback := preload("res://scripts/media_server_playback.gd").new()
var history_enabled := true:
	set(value):
		history_enabled = value
		server_playback.configure(platform, value)
var _history_started := false
var _file_permission_persisted := false
var _history_save_ms := 0
var _access_request := 0
var _access_pending: Dictionary = {}
var _audio_pending := false
var local_uri := ""
var display_name := ""
var picker_error := ""
var playback_error_detail := ""
var _picker_request := 0
var _binding := Binding.new()
var _pending_pair: Dictionary = {}
var _pending_revision: Dictionary = {}
var _fixture := -1
var _recover := false
var _recover_ms := 0
var _waiting_first := false
var _thumbnail_busy := false
var _thumbnail_sequence := 0
var _thumbnail_result: Dictionary = {}
var _library_cover := ""
var _freeze_sequence := 0
var _freeze_request := 0
var _seek_freeze_failed := false
var stick_scrubbing := false


func _init(enable_diagnostics: bool = true) -> void:
	if OS.is_debug_build() and enable_diagnostics:
		diagnostics = load("res://scripts/mpv_video_debug.gd").new(self)
		diagnostics.name = "PlaybackDiagnostics"
		add_child(diagnostics)


func _ready() -> void:
	mode_memory.load_saved()
	recent_files.load_saved()
	initialize_surface(load("res://shaders/video_pair.gdshader"))
	color_grade.apply(material)
	caption = Label3D.new()
	caption.name = "Subtitles"
	caption.font_size = 40
	caption.pixel_size = 0.0015
	caption.outline_size = 8
	caption.no_depth_test = true
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	caption.width = 700
	caption.visible = false
	add_child(caption)
	projected_subtitles = ProjectedSubtitles.new()
	add_child(projected_subtitles)
	_subtitle_surface = MeshInstance3D.new()
	_subtitle_material = ShaderMaterial.new()
	_subtitle_material.shader = preload("res://shaders/subtitle_surface.gdshader")
	_subtitle_material.render_priority = 1
	_subtitle_surface.material_override = _subtitle_material
	_subtitle_surface.visible = false
	add_child(_subtitle_surface)
	if OS.get_name() == "Android" and Engine.has_singleton("QuestPlayer"):
		platform = Engine.get_singleton("QuestPlayer")
		platform.connect("local_video_selected", _on_selected)
		if platform.has_signal("local_subtitle_selected"):
			platform.connect("local_subtitle_selected", _on_subtitle_selected)
		if platform.has_signal("mpv_subtitle_import"):
			platform.connect("mpv_subtitle_import", _on_subtitle_import)
		platform.connect("local_video_access", _on_local_access)
		platform.connect("mpv_pair_available", _on_pair)
		platform.connect("mpv_state", _on_state)
		platform.connect("mpv_error", _on_error)
		platform.connect("mpv_detach", _on_detach)
		platform.connect("mpv_released", _on_released)
		if diagnostics:
			diagnostics.connect_platform(platform)
		platform.connect("mpv_frozen_pair", _on_frozen_pair)
	_apply_geometry()


## First usable displayed source frame, for every stable library URI. No second video decoder.
var _thumb_after_ms := -1  # media position to try; -1: already cached/not wanted
var _thumb_tries := 0


static func _thumbnail_source(uri: String) -> bool:
	return not ModeMemory.key_for(uri).is_empty()


func _maybe_capture_thumbnail() -> void:
	if (
		(diagnostics != null and diagnostics.benchmark)
		or _thumb_after_ms < 0
		or _thumbnail_busy
		or _stereo_capture_busy
		or (diagnostics != null and diagnostics.pixel_busy)
		or _waiting_first
		or not _pending_revision.is_empty()
		or media.state not in ["playing", "paused", "ended"]
		or not _binding.material
		or media.last_pair.is_empty()
	):
		return
	if int(media.last_pair.get("pts_us", 0)) / 1000 < _thumb_after_ms:
		return
	var uri := local_uri
	var sequence := _thumbnail_sequence
	var pair := media.last_pair.duplicate(true)
	if not platform.pin_mpv_pair(int(pair.session_id), int(pair.slot_token)):
		return
	_thumbnail_busy = true
	_thumb_after_ms = -1
	# Own wrappers/ExternalTexture, so a close cannot detach/rebind our readback source.
	var binding := Binding.new()
	var target := ShaderMaterial.new()
	if not binding.bind(target, pair):
		platform.release_mpv_pair_pin(int(pair.session_id), int(pair.slot_token))
		_thumbnail_busy = false
		return
	var stereo := bool(pair.get("stereo_sbs", false)) or false
	var tb := stereo and bool(pair.get("top_bottom", false))
	var eye := Vector2(
		float(pair.width) * (2.0 if false else 1.0) * (0.5 if stereo and not tb else 1.0),
		float(pair.height) * (0.5 if tb else 1.0)
	)
	var scale: Array = pair.get("color_uv_scale", [1.0, 1.0])
	var image: Image = await Thumbnails.capture(
		self,
		binding.color_texture(),
		str(binding.ticket.get("color_target", "")) == "external",
		stereo,
		Thumbnails.crop_for(geometry, eye),
		Vector2(float(scale[0]), float(scale[1])),
		tb
	)
	binding.unbind()
	platform.release_mpv_pair_pin(int(pair.session_id), int(pair.slot_token))
	_thumbnail_busy = false
	if sequence != _thumbnail_sequence or uri != local_uri:
		return
	if not image or image.is_empty():
		_thumbnail_result = {"state": "capture_failed"}
		_thumb_after_ms = int(pair.pts_us) / 1000 + 2000
		return
	# A fade or a black opening says nothing about the video: try again a little later.
	var small := image.duplicate() as Image
	small.resize(16, 9, Image.INTERPOLATE_BILINEAR)
	var light := 0.0
	for y in 9:
		for x in 16:
			light += small.get_pixel(x, y).get_luminance()
	_thumb_tries += 1
	if light / 144.0 < 0.06 and _thumb_tries < 3:
		_thumb_after_ms = int(pair.pts_us) / 1000 + 2000
		return
	var stored := Thumbnails.store(uri, image)
	_thumbnail_result = {
		"state": "stored" if stored else "store_failed",
		"pts_us": int(pair.pts_us),
		"width": image.get_width(),
		"height": image.get_height(),
		"source_epoch": int(pair.source_epoch)
	}
	if stored:
		thumbnail_ready.emit(uri)
	if diagnostics:
		diagnostics.write_report()


func pick_file() -> void:
	cancel_pending_open()
	picker_error = ""
	if platform:
		_picker_request = platform.pick_local_video()
		if _picker_request <= 0:
			picker_error = "File picker unavailable"
	else:
		picker_error = "Quest local playback required"
	changed.emit()


func _on_selected(payload: String) -> void:
	var result: Variant = JSON.parse_string(payload)
	if (
		not result is Dictionary
		or _picker_request <= 0
		or result.get("picker_request", -1) != _picker_request
	):
		return
	if result.get("state") == "selected":
		_picker_request = 0
		requested_play = true
		var uri := str(result.uri)
		if open_local(
			uri,
			str(result.get("display_name", "Local video")),
			_resume(uri),
			true,
			"",
			{"basename": result.get("display_name", "")}
		):
			_file_permission_persisted = bool(result.get("persisted_permission", false))
	elif result.get("state") == "error":
		_picker_request = 0
		picker_error = str(result.get("error", "Local file unavailable"))
	elif result.get("state") == "cancelled":
		_picker_request = 0
		picker_error = ""
	elif result.get("state") == "checking":
		picker_error = "Checking file access..."
	changed.emit()


func cancel_pending_open() -> void:
	var picker := _picker_request
	_picker_request = 0
	if picker > 0 and platform:
		platform.cancel_local_video_pick(picker)
	var previous := _access_request
	_access_request = 0
	_access_pending = {}
	if previous > 0 and platform:
		platform.cancel_local_video_access(previous)


# Library selection: MediaStore content URIs are readable through the media permission;
# network URIs (smb://, DLNA http) have no document grant to check.
func open_library(
	uri: String, title: String, metadata: Dictionary = {}, from_start: bool = false
) -> bool:
	var cover := str(metadata.get("cover", recent_files.lookup(uri).get("cover", "")))
	var opened := false
	if from_start:
		requested_play = true
		if uri.begins_with("content://") and not recent_files.lookup(uri).is_empty():
			opened = open_recent(uri, true, metadata)
		else:
			opened = open_local(uri, title, 0, true, str(metadata.get("basename", "")), metadata)
	elif uri.begins_with("medialib://") and not metadata.is_empty():
		requested_play = true
		var start: int = int(metadata.get("start_ms", -1))
		opened = open_local(
			uri,
			title,
			_resume(uri) if start < 0 else start,
			true,
			str(metadata.get("basename", "")),
			metadata
		)
	elif not recent_files.lookup(uri).is_empty():
		opened = open_recent(uri, false, metadata)
	else:
		requested_play = true
		opened = open_local(uri, title, 0, true, "", metadata)
	if opened and RecentFiles.valid_cover(cover):
		_library_cover = cover
	return opened


func open_recent(uri: String, from_start: bool = false, metadata: Dictionary = {}) -> bool:
	var entry := recent_files.lookup(uri)
	if entry.is_empty() or not platform:
		return false
	if not uri.begins_with("content://"):
		requested_play = true
		return open_local(
			uri, str(entry.title), 0 if from_start else _resume(uri), true, "", metadata
		)
	cancel_pending_open()
	_access_pending = {
		"uri": uri,
		"title": str(entry.title),
		"start_ms": 0 if from_start else _resume(uri),
		"metadata": metadata.duplicate(true)
	}
	_access_request = platform.request_local_video_access(uri)
	if _access_request <= 0:
		_access_pending = {}
		picker_error = "File access check busy or unavailable"
		changed.emit()
		return false
	picker_error = "Checking file access..."
	changed.emit()
	return true


func _on_local_access(id: int, payload: String) -> void:
	if id != _access_request or _access_pending.is_empty():
		return
	var parser := JSON.new()
	if parser.parse(payload) != OK or not parser.data is Dictionary:
		return
	var result: Dictionary = parser.data
	if result.get("uri") != _access_pending.uri:
		return
	var pending := _access_pending.duplicate(true)
	_access_pending = {}
	_access_request = 0
	if result.get("state") != "readable" or not result.get("persisted_permission") is bool:
		picker_error = preload("res://scripts/playback_errors.gd").summary(
			str(result.get("error", "File unavailable; select it again"))
		)
		changed.emit()
		return
	requested_play = true
	var metadata: Dictionary = pending.get("metadata", {}).duplicate(true)
	if not str(result.get("display_name", "")).is_empty():
		metadata.basename = result.display_name
	if open_local(str(pending.uri), str(pending.title), int(pending.start_ms), true, "", metadata):
		_file_permission_persisted = result.persisted_permission


func play_calibration_clip() -> void:
	_fixture = (_fixture + 1) % 3
	var filename: String = ["mp03_frame_identity", "c03_sbs_grid", "mp06_audio_clock"][_fixture]
	var source := FileAccess.open("res://media/%s.mp4" % filename, FileAccess.READ)
	if not source:
		picker_error = "Calibration video unavailable"
		changed.emit()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://fixtures"))
	var path := "user://fixtures/%s.mp4" % filename
	var target := FileAccess.open(path, FileAccess.WRITE)
	if not target:
		return
	while source.get_position() < source.get_length():
		target.store_buffer(source.get_buffer(65536))
	target.close()
	source.close()
	stereo_sbs = true
	geometry = Geometry.Geometry.FLAT
	requested_play = true
	open_local("file://" + ProjectSettings.globalize_path(path), filename, 0, false)


func open_local(
	uri: String,
	title: String,
	start_ms: int = 0,
	restore_mode: bool = true,
	basename: String = "",
	metadata: Dictionary = {},
	shader_only: bool = false
) -> bool:
	if diagnostics:
		diagnostics.open_requested(start_ms)
	if not platform or not platform.mpv_supported():
		picker_error = "MPV playback backend unavailable"
		changed.emit()
		return false
	cancel_pending_open()
	close_video()
	force_shader_output = shader_only
	playback_error_detail = ""
	# Alpha-packed and Alpha-wanted files say so in their names (PTMediaServer / DeoVR markers).
	_layout_basename = (
		basename
		if not basename.is_empty()
		else (title if not title.is_empty() else uri.uri_decode().get_file())
	)
	var stated := Naming.from_name(_layout_basename)
	if uri.begins_with("medialib://"):
		stated.erase("alpha")
	packed_file = bool(stated.get("packed", false))
	packed_alpha = packed_file
	packed_alpha_forced = false
	_layout_pending = null
	var saved_sync := mode_memory.lookup(uri) if restore_mode else {}
	if not _next_layout_override.is_empty():
		saved_sync = _next_layout_override.duplicate(true)
	var playback_grade: Variant = (
		saved_sync.get("color_grade", default_color_grade)
		if history_enabled
		else default_color_grade
	)
	playback_grade = _next_layout_override.get("live_color_grade", playback_grade)
	color_grade.restore(playback_grade)
	color_grade.apply(material)
	_color_grade_changed = bool(_next_layout_override.get("live_color_grade_changed", false))
	stereo_focus_mode = int(saved_sync.get("stereo_focus_mode", 0)) if history_enabled else 0
	stereo_focus = float(saved_sync.get("stereo_focus", 1.5)) if history_enabled else 1.5
	_focus_generation += 1
	_focus_dirty = false
	autofocus.reset()
	subtitle_below_screen = (
		bool(saved_sync.get("subtitle_below_screen", false)) if history_enabled else false
	)
	subtitle_encodings = saved_sync.get("subtitle_encodings", {}).duplicate(true)
	if PlatformMethods.supports(platform, "configure_subtitle_encodings"):
		platform.configure_subtitle_encodings(uri, JSON.stringify(subtitle_encodings))
	dual_subtitles.reset()
	_track_choices = saved_sync.get("track_choices", {}).duplicate(true)
	_tracks_pending = _track_choices.duplicate(true)
	if not history_enabled:
		_tracks_pending.erase("secondary_subtitle")
	subtitle_delay_ms = int(saved_sync.get("subtitle_delay_ms", 0))
	audio_delay_ms = int(saved_sync.get("audio_delay_ms", 0))
	external_subtitle_uri = str(saved_sync.get("external_subtitle_uri", ""))
	_pending_external_uri = external_subtitle_uri
	if restore_mode:
		var saved := mode_memory.lookup(uri)
		if not saved.is_empty():
			# The user's own choice for this file wins over its name and shape.
			geometry = int(saved.geometry)
			stereo_sbs = bool(saved.stereo_sbs)
			top_bottom = stereo_sbs and bool(saved.get("top_bottom", false))
			stereo_half = stereo_sbs and bool(saved.get("stereo_half", false))
			fisheye_fov = (
				int(saved.get("fisheye_fov", 180))
				if int(saved.get("fisheye_fov", 180)) in FISHEYE_FOVS
				else 180
			)
			swap_eyes = bool(saved.swap_eyes)
			viewing_eye = int(saved.get("viewing_eye", 0))
			stereo_horizontal = float(saved.get("stereo_horizontal", 0.0))
			stereo_vertical = float(saved.get("stereo_vertical", 0.0))
		elif (
			not mode_lock.is_empty()
			and not stated.has("geometry")
			and not stated.has("stereo")
			and (not reuse_last_mode or last_video_mode.is_empty())
		):
			geometry = int(mode_lock.geometry)
			stereo_sbs = int(mode_lock.layout) != 0
			top_bottom = int(mode_lock.layout) in [2, 4]
			stereo_half = int(mode_lock.layout) in [3, 4]
			fisheye_fov = int(mode_lock.fisheye_fov)
			swap_eyes = false
		else:
			geometry = int(stated.get("geometry", Geometry.Geometry.FLAT))
			stereo_sbs = bool(
				stated.get(
					"stereo",
					geometry in [Geometry.Geometry.HALF_EQUIRECT, Geometry.Geometry.FISHEYE]
				)
			)
			top_bottom = stereo_sbs and bool(stated.get("top_bottom", false))
			stereo_half = stereo_sbs and bool(stated.get("stereo_half", false))
			fisheye_fov = int(stated.get("fisheye_fov", 180))
			swap_eyes = bool(stated.get("swap", false))
			if (
				not stated.has("geometry")
				or not stated.has("stereo")
				or (
					geometry in [Geometry.Geometry.FLAT, Geometry.Geometry.FISHEYE]
					and not stated.has("stereo_half")
				)
			):
				_layout_pending = stated
	_thumb_tries = 0
	if not _next_layout_override.is_empty():
		geometry = int(_next_layout_override.geometry)
		stereo_sbs = bool(_next_layout_override.stereo_sbs)
		top_bottom = bool(_next_layout_override.top_bottom)
		stereo_half = bool(_next_layout_override.stereo_half)
		fisheye_fov = int(_next_layout_override.fisheye_fov)
		swap_eyes = bool(_next_layout_override.swap_eyes)
		_next_layout_override.clear()
	_thumbnail_result = {}
	_thumb_after_ms = -1
	if (
		not (diagnostics != null and diagnostics.benchmark)
		and _thumbnail_source(uri)
		and (Thumbnails.is_preview(uri) or Thumbnails.texture(uri) == null)
	):
		_thumb_after_ms = 0
	local_uri = uri
	_auto_stereo = (
		restore_mode
		and (saved_sync.is_empty() or bool(saved_sync.get("layout_auto", false)))
		and mode_lock.is_empty()
	)
	_stereo_detection.begin(_auto_stereo)
	display_name = title
	_bookmark_metadata = metadata.duplicate(true)
	if not basename.is_empty():
		_bookmark_metadata.basename = basename
	if str(_bookmark_metadata.get("basename", "")).is_empty():
		if uri.begins_with("file://") or uri.begins_with("smb://"):
			_bookmark_metadata.basename = uri.uri_decode().get_file()
		elif uri.begins_with("content://"):
			_bookmark_metadata.basename = title
	if uri.begins_with("file://"):
		var source := FileAccess.open(uri.trim_prefix("file://").uri_decode(), FileAccess.READ)
		if source:
			_bookmark_metadata.size = source.get_length()
	_bookmark_resolve()
	_last_seek_mode = SeekPolicy.normalize(seek_mode)
	surface_requested = (
		layer_controller != null
		and layer_controller.direct_wanted(self, uri)
		and PlatformMethods.supports(platform, "open_mpv_video_surface")
	)
	var method := "open_mpv_video_surface" if surface_requested else "open_mpv_video"
	var id: int = platform.call(
		method,
		uri,
		maxi(start_ms, 0),
		stereo_sbs,
		true,
		stereo_sbs and top_bottom,
		SeekPolicy.normalize(seek_mode) == SeekPolicy.EXACT
	)
	media.begin(id)
	set_hdr_to_sdr(hdr_to_sdr)
	subtitle_follow.reset()
	server_playback.begin(uri, history_enabled)
	playback_speed = preload("res://scripts/playback_preferences.gd").speed(playback_speed)
	screen_rotation = 0.0
	if PlatformMethods.supports(platform, "set_mpv_speed"):
		platform.set_mpv_speed(id, playback_speed)
	if diagnostics:
		diagnostics.open_dispatched(id)
	_remember_file = restore_mode and id > 0
	_history_started = false
	_file_permission_persisted = false
	audio_track_id = -1
	_clone_applied = false
	subtitles.select(0)
	_clear_subtitle_text(true)
	if _subtitle_surface:
		_subtitle_surface.visible = false
	reset_view()  # Orientation starts at the current gaze; per-file translations are independent.
	if geometry != Geometry.Geometry.FLAT:
		for key in preload("res://scripts/immersive_adjustments.gd").KEYS:
			set(key, float(saved_sync.get(key, 0.0)))
		_center_on_view()
	_audio_pending = id > 0
	_sync_pending = id > 0
	if id <= 0:
		picker_error = "Player resources are still closing"
	else:
		_waiting_first = true
		platform.set_mpv_playing(id, false)
		picker_error = ""
	changed.emit()
	return id > 0


func _unbind() -> void:
	var previous: Dictionary = _binding.unbind()
	if platform and not previous.is_empty():
		if int(previous.get("frozen_frame_id", 0)) > 0:
			platform.release_mpv_frozen_frame(int(previous.frozen_frame_id))
		else:
			platform.detach_mpv_pair(int(previous.session_id), int(previous.slot_token))
	alpha_enabled = false
	panel.visible = false
	if caption:
		caption.visible = false


func close_video() -> void:
	_record_history(true)
	_focus_probe.cancel()
	_focus_last_frame.clear()
	if layer_controller:
		layer_controller.release(self)
	surface_requested = false
	_fallback_queued = false
	_fallback_pending = false
	_surface_context.clear()
	_surface_eof_ms = -1
	_stereo_detection.cancel()
	server_playback.poll(self, true)
	server_playback.finish(platform)
	if _subtitle_pick > 0 and PlatformMethods.supports(platform, "cancel_local_subtitle_pick"):
		platform.cancel_local_subtitle_pick(_subtitle_pick)
	_subtitle_pick = 0
	_subtitle_pick_session = 0
	_pending_external_uri = ""
	_subtitle_import_uri = ""
	_subtitle_import_command = 0
	_subtitle_loading = false
	_sync_pending = false
	commit_immersive_adjustments()
	viewing_eye = 0
	stereo_horizontal = 0.0
	stereo_vertical = 0.0
	_apply_stereo_view()
	_bookmark_scope_sequence += 1
	_bookmark_media_id = ""
	_bookmark_metadata.clear()
	_bookmark_rows.clear()
	_bookmark_cache_revision = -1
	_thumbnail_sequence += 1
	_library_cover = ""
	cancel_pending_open()
	if mode_memory.dirty:
		mode_memory.save()
	if recent_files.dirty:
		recent_files.save()
	_unbind()
	if platform and media.session_id > 0:
		platform.close_mpv_video(media.session_id)
	media.close()
	_pending_pair = {}
	_pending_revision = {}
	_freeze_request = 0
	_seek_freeze_failed = false
	if diagnostics:
		diagnostics.seek_delay_until_ms = 0
	_waiting_first = false
	stick_scrubbing = false
	_audio_pending = false
	control.close()
	_remember_file = false
	_color_grade_changed = false
	color_grade.restore(default_color_grade)
	color_grade.apply(material)
	dual_subtitles.reset()
	_track_choices.clear()
	_tracks_pending.clear()
	local_uri = ""
	display_name = ""
	set_corner_hover(-1)
	_clear_subtitle_text(true)
	if _subtitle_surface:
		_subtitle_surface.visible = false
	changed.emit()


func checkpoint_playback() -> void:
	_record_history(true)


func clear_history() -> void:
	if recent_files.clear_all() and not recent_files.save():
		Log.record("recent_file_save_failed", {"error": recent_files.last_error})
	_history_started = false


func _resume(uri: String) -> int:
	return recent_files.resume_position(uri) if history_enabled else 0


func _record_history(force: bool = false) -> void:
	if (
		not history_enabled
		or not _remember_file
		or not media.accepts(media.session_id)
		or not is_instance_valid(panel)
		or not panel.visible
	):
		return
	var now := Time.get_ticks_msec()
	if not force and _history_started and now < _history_save_ms:
		return
	var position_ms := _history_position_ms()
	if position_ms < 0:
		return
	if not _history_started:
		if not recent_files.opened(local_uri, display_name, _file_permission_persisted):
			return
		_history_started = true
		recent_files.set_cover(local_uri, _library_cover)
	recent_files.progress(local_uri, position_ms, control.duration_ms, media.state == "ended")
	_history_save_ms = now + 5000
	if not recent_files.save():
		Log.record("recent_file_save_failed", {"error": recent_files.last_error})


func _history_position_ms() -> int:
	if surface_requested:
		if (
			not layer_shown
			or _waiting_first
			or int(_surface_context.get("session_id", 0)) != media.session_id
			or int(_surface_context.get("generation", 0)) != media.generation
			or media.playback.get("surface_context") != _surface_context
		):
			return -1
		return _surface_position_ms(media.playback)
	var pair: Dictionary = media.last_pair
	if (
		int(pair.get("session_id", 0)) != media.session_id
		or int(pair.get("generation", 0)) != media.generation
		or not Binding.timing_valid(pair)
	):
		return -1
	return clampi(int(float(pair.pts_us) / 1000.0), 0, 2147483647)


func _request_revision(position_ms: int = -1, mode: String = "") -> void:
	if not platform or not media.accepts(media.session_id):
		return
	_pending_revision = {
		"stereo": stereo_sbs,
		"position_ms": position_ms,
		"top_bottom": stereo_sbs and top_bottom,
		"seek_mode": SeekPolicy.normalize(seek_mode if mode.is_empty() else mode)
	}
	platform.set_mpv_playing(media.session_id, false)
	_waiting_first = true
	_clear_subtitle_text()
	if _subtitle_surface:
		_subtitle_surface.visible = false
	if caption:
		caption.visible = false
	if position_ms >= 0:
		if diagnostics:
			diagnostics.record_seek("requested")
	_try_revision()


func _start_seek_freeze() -> bool:
	# Capture exactly once before seek/flush; rapid requests share this frame.
	if not _seek_freeze_failed and not _binding.ticket.is_empty() and not _is_frozen():
		var capable := Engine.has_singleton("QuestPlayer") or platform.has_method("freeze_mpv_pair")
		if capable:
			_freeze_sequence += 1
			_freeze_request = _freeze_sequence
			if platform.freeze_mpv_pair(
				media.session_id, int(_binding.ticket.slot_token), _freeze_request
			):
				return true
			_skip_seek_freeze("Frame capture request rejected")
	return false


func _is_frozen() -> bool:
	return int(_binding.ticket.get("frozen_frame_id", 0)) > 0


func _skip_seek_freeze(reason: String) -> void:
	_freeze_request = 0
	_seek_freeze_failed = true
	Log.record(
		"mpv_seek_freeze_failed",
		{"session_id": media.session_id, "target_ms": control.target_ms, "reason": reason}
	)
	if diagnostics:
		diagnostics.record_seek("capture_failed")


func _on_frozen_pair(id: int, payload: String) -> void:
	var report: Variant = JSON.parse_string(payload)
	if not report is Dictionary:
		return
	var pair: Dictionary = report.get("pair", {})
	if (
		id != media.session_id
		or int(report.get("request_id", 0)) != _freeze_request
		or _pending_revision.is_empty()
		or int(_pending_revision.position_ms) < 0
	):
		if int(pair.get("frozen_frame_id", 0)) > 0:
			platform.release_mpv_frozen_frame(int(pair.frozen_frame_id))
		if int(report.get("request_id", 0)) == _freeze_request:
			_freeze_request = 0
		return
	if report.get("state") != "ready":
		_skip_seek_freeze(str(report.get("error", "Frame capture failed")))
		_try_revision()
		return
	# Preserve visibility, shader parameters and effect state during replacement.
	var previous := _binding.unbind()
	if not _binding.bind(material, pair):
		_binding.bind(material, previous)
		platform.release_mpv_frozen_frame(int(pair.frozen_frame_id))
		_skip_seek_freeze("Frozen video frame could not be bound")
		_try_revision()
		return
	platform.detach_mpv_pair(int(previous.session_id), int(previous.slot_token))
	_freeze_request = 0
	if diagnostics:
		diagnostics.record_seek("frozen")
	_try_revision()


func _try_revision() -> void:
	if (
		_pending_revision.is_empty()
		or _freeze_request > 0
		or (diagnostics != null and diagnostics.pixel_busy)
		or _thumbnail_busy
		or _stereo_capture_busy
	):
		return
	if int(_pending_revision.position_ms) >= 0 and _start_seek_freeze():
		return
	if (
		int(_pending_revision.position_ms) >= 0
		and diagnostics != null
		and Time.get_ticks_msec() < diagnostics.seek_delay_until_ms
	):
		return
	var request := _pending_revision
	var id: int = platform.revise_mpv_video(
		media.session_id,
		request.stereo,
		request.position_ms,
		request.top_bottom,
		request.seek_mode == SeekPolicy.EXACT
	)
	if id <= 0:
		return
	if not surface_requested and (int(request.position_ms) < 0 or not _is_frozen()):
		_unbind()
	_pending_pair = {}
	_pending_revision = {}
	_seek_freeze_failed = false
	var held_format := media.format.duplicate()
	_surface_context.clear()
	_surface_eof_ms = -1
	media.begin(id)
	set_hdr_to_sdr(hdr_to_sdr)
	subtitle_follow.reset()
	if _is_frozen() or surface_requested:
		media.format = held_format
	_tracks_pending = _track_choices.duplicate(true)
	if not history_enabled:
		_tracks_pending.erase("secondary_subtitle")
	platform.set_mpv_playing(id, false)
	if int(request.position_ms) >= 0:
		_last_seek_mode = request.seek_mode
		control.take_pending()
		if diagnostics:
			diagnostics.seek_delay_until_ms = 0
		if diagnostics:
			diagnostics.record_seek("seek_started")
	changed.emit()


## Alpha is the precomputed mask packed in this file.
func alpha_wanted() -> bool:
	return packed_alpha


## The URI/effect preferences survive close for history; they are not playback state.
func has_active_presentation() -> bool:
	if local_uri.is_empty() or not media.accepts(media.session_id):
		return false
	return (
		media.state != "ended"
		or (loop_enabled and requested_play)
		or _waiting_first
		or not _pending_revision.is_empty()
	)


func alpha_available() -> bool:
	return (
		media.accepts(media.session_id)
		and not top_bottom
		and not stereo_half
		and Geometry.legacy_compatible(media.format, stereo_sbs, geometry)
	)


## Explicit user intent is accepted independently of automatic detection confidence.
## Layout/frame checks stay at presentation time and are exposed to the UI.
func set_alpha(enabled: bool) -> bool:
	packed_alpha = enabled
	packed_alpha_forced = enabled
	_apply_packed()
	changed.emit()
	return true


func packed_alpha_blocker() -> String:
	if not material:
		return "Packed alpha: renderer is not ready"
	if media.last_pair.is_empty():
		return "Packed alpha: waiting for a decoded frame"
	if geometry != Geometry.Geometry.FISHEYE:
		return "Packed alpha: select Fisheye"
	if not stereo_sbs or top_bottom or stereo_half:
		return "Packed alpha: select full SBS"
	if int(media.format.get("width", 0)) < 10 or int(media.format.get("height", 0)) < 10:
		return "Packed alpha: decoded frame is too small"
	# Force On interprets the displayed texture as packed media even when metadata
	# or its aspect ratio is inconclusive. Automatic detection keeps its old gate.
	if (
		not packed_alpha_forced
		and not Geometry.legacy_compatible(media.format, stereo_sbs, geometry)
	):
		return "Packed alpha: unsupported frame metadata"
	return ""


func packed_alpha_feedback() -> String:
	return packed_alpha_blocker() if packed_alpha else ""


## The extra track titled "Clone voice" (see SidecarAudio.kt); 0 when this video has none.
func clone_voice_track() -> int:
	for track in media.playback.get("details", {}).get("audio_tracks", []):
		if (
			track is Dictionary
			and bool(track.get("external", false))
			and str(track.get("title", "")) == "Clone voice"
		):
			return int(track.get("id", 0))
	return 0


func clone_voice_active() -> bool:
	var clone := clone_voice_track()
	return (
		clone > 0 and str(media.playback.get("details", {}).get("audio_track_id", "")) == str(clone)
	)


## Clone voice <-> the video's own audio. The choice carries over to the next video with a clone voice.
func toggle_clone_voice() -> bool:
	var clone := clone_voice_track()
	if clone <= 0:
		return false
	var active := clone_voice_active()
	if not select_audio_track(-1 if active else clone):
		return false
	prefer_clone_voice = not active
	return true


func alpha_ready() -> bool:
	return alpha_enabled and not media.last_pair.is_empty()


func suspend_focus() -> void:
	_focus_generation += 1
	_focus_probe.cancel()
	_focus_last_frame.clear()
	autofocus.reset()


func auto_layout_pending() -> bool:
	return _auto_stereo and _stereo_detection.pending


func layout_basename() -> String:
	return _layout_basename


func borrowed_color() -> RID:
	return _binding.color_texture()


func surface_context() -> Dictionary:
	return _surface_context.duplicate(true)


func presentation_context() -> Dictionary:
	return _surface_context if surface_requested else media.last_pair


static func _surface_position_ms(report: Dictionary) -> int:
	var seconds := str(report.get("details", {}).get("position_seconds", ""))
	if not seconds.is_valid_float():
		return -1
	var position := seconds.to_float()
	return (
		int(minf(position * 1000.0, 2147483647.0)) if is_finite(position) and position >= 0 else -1
	)


func _accept_surface_state(report: Dictionary) -> void:
	surface_requested = true
	if not report.get("surface_ready", false):
		_surface_context.clear()
		return
	var context: Variant = report.get("surface_context", {})
	var format: Variant = report.get("surface_format", {})
	if (
		not context is Dictionary
		or not format is Dictionary
		or int(context.get("session_id", -1)) != media.session_id
	):
		return
	if (
		int(context.get("source_epoch", 0)) <= 0
		or int(context.get("generation", 0)) <= 0
		or int(format.get("width", 0)) <= 0
		or int(format.get("height", 0)) <= 0
	):
		return
	_surface_context = context.duplicate(true)
	media.generation = int(context.generation)
	media.logical_session_id = int(context.get("logical_session_id", 0))
	media.format = format.duplicate(true)
	media.format["unapplied_rotation_degrees"] = int(format.get("source_rotation_degrees", 0))
	if _waiting_first:
		_waiting_first = false
		media.frame_counter = 1
		if control.in_flight > 0:
			control.first_frame(_surface_position_ms(report))
		_complete_layout()
		_apply_geometry()
		panel.visible = true
		_remember_mode()
		platform.set_mpv_playing(media.session_id, requested_play and not stick_scrubbing)
	if media.state == "ended":
		if _surface_eof_ms < 0:
			_surface_eof_ms = Time.get_ticks_msec()
	else:
		_surface_eof_ms = -1


func request_shader_fallback() -> void:
	if layer_controller and not layer_controller.runtime_running():
		_fallback_pending = true
		return
	if _fallback_queued or force_shader_output or local_uri.is_empty():
		return
	_fallback_queued = true
	call_deferred("_fallback_from_surface", local_uri, media.session_id)


func _fallback_from_surface(uri: String, session_id: int) -> void:
	if uri.is_empty() or local_uri != uri or media.session_id != session_id:
		return
	var title := display_name
	var basename := _layout_basename
	var metadata := _bookmark_metadata.duplicate(true)
	var alpha := packed_alpha
	var alpha_forced := packed_alpha_forced
	var position := control.display_position_ms()
	var playing := requested_play
	var remember := _remember_file
	var permission := _file_permission_persisted
	var pose := flat_pose
	var size := screen_scale
	var distance := screen_distance
	var curve := screen_curve
	var rotation := screen_rotation
	var eye := viewing_eye
	var alignment := Vector2(stereo_horizontal, stereo_vertical)
	var snapshot := {
		"geometry": geometry,
		"stereo_sbs": stereo_sbs,
		"top_bottom": top_bottom,
		"stereo_half": stereo_half,
		"swap_eyes": swap_eyes,
		"fisheye_fov": fisheye_fov,
		"subtitle_encodings": subtitle_encodings.duplicate(true),
		"track_choices": _track_choices.duplicate(true),
		"subtitle_delay_ms": subtitle_delay_ms,
		"audio_delay_ms": audio_delay_ms,
		"external_subtitle_uri": external_subtitle_uri,
		"stereo_focus_mode": stereo_focus_mode,
		"stereo_focus": stereo_focus,
		"subtitle_below_screen": subtitle_below_screen,
		"live_color_grade": color_grade.snapshot(),
		"live_color_grade_changed": _color_grade_changed
	}
	for key in preload("res://scripts/immersive_adjustments.gd").KEYS:
		snapshot[key] = get(key)
	_next_layout_override = snapshot.duplicate(true)
	var saved_seek_mode := seek_mode
	seek_mode = SeekPolicy.EXACT
	var reopened := open_local(uri, title, position, false, basename, metadata, true)
	seek_mode = saved_seek_mode
	if reopened:
		packed_alpha = alpha
		packed_alpha_forced = alpha_forced
		_remember_file = remember
		_file_permission_persisted = permission
		_track_choices = snapshot.track_choices.duplicate(true)
		_tracks_pending = _track_choices.duplicate(true)
		viewing_eye = eye
		stereo_horizontal = alignment.x
		stereo_vertical = alignment.y
		stereo_focus_mode = int(snapshot.stereo_focus_mode)
		stereo_focus = float(snapshot.stereo_focus)
		flat_pose = pose
		screen_scale = size
		screen_distance = distance
		screen_curve = curve
		screen_rotation = rotation
		for key in preload("res://scripts/immersive_adjustments.gd").KEYS:
			set(key, snapshot[key])
		requested_play = playing
		_apply_stereo_view()
		_apply_geometry()
	_fallback_queued = false


func set_stereo_focus(key: String, value: Variant, persist: bool = true) -> void:
	if key == "stereo_focus_mode":
		if (
			not (value is int or value is float)
			or not is_finite(float(value))
			or float(value) != floorf(float(value))
			or int(value) not in [0, 1, 2]
		):
			return
		stereo_focus_mode = int(value)
		if stereo_focus_mode != 1:
			_focus_probe.cancel()
		_focus_generation += 1
		autofocus.reset()
	else:
		if not (value is int or value is float) or not is_finite(float(value)):
			return
		stereo_focus = clampf(float(value), StereoFocus.LIMITS.x, StereoFocus.LIMITS.y)
	_focus_dirty = true
	_apply_stereo_focus()
	if persist:
		commit_stereo_focus()
	changed.emit()


func commit_stereo_focus() -> void:
	if _focus_dirty and history_enabled:
		_remember_mode()
	_focus_dirty = false


func _apply_stereo_focus() -> void:
	if not material or not panel:
		return
	var distance := (
		autofocus.distance
		if stereo_focus_mode == 1
		else (stereo_focus if stereo_focus_mode == 2 else 0.0)
	)
	var active := (
		distance > 0 and stereo_sbs and viewing_eye == 0 and geometry != Geometry.Geometry.FLAT
	)
	var units := XRServer.world_scale / maxf(panel.global_basis.get_scale().x, 0.0001)
	var scale := distance * units / SPHERE_RADIUS if active else 1.0
	var axis := Vector3.RIGHT
	if active and geometry == Geometry.Geometry.EQUIRECT_360 and view_camera:
		axis = panel.global_basis.orthonormalized().inverse() * view_camera.global_basis.x
		axis.y = 0
		axis = axis.normalized() if axis.length() > 0.01 else Vector3.RIGHT
	var parameters := [
		material.get_rid(), scale, axis, units, active, view_horizontal, view_vertical, view_zoom
	]
	if parameters == _focus_parameters:
		return
	_focus_parameters = parameters
	material.set_shader_parameter("focus_scale", scale)
	material.set_shader_parameter(
		"focus_offset",
		axis * ProjectedSubtitles.runtime_ipd() * 0.5 * units if active else Vector3.ZERO
	)
	material.set_shader_parameter(
		"focus_centre",
		Vector3(view_horizontal, view_vertical, -view_zoom) * SPHERE_RADIUS * (scale - 1.0)
	)


func _maybe_focus() -> void:
	if (
		stereo_focus_mode != 1
		or not stereo_sbs
		or viewing_eye != 0
		or geometry == Geometry.Geometry.FLAT
	):
		return
	if (
		_focus_busy
		or _stereo_capture_busy
		or _thumbnail_busy
		or _waiting_first
		or not _pending_revision.is_empty()
	):
		return
	if (
		not view_camera
		or not panel
		or not panel.visible
		or media.state != "playing"
		or not requested_play
		or media.last_pair.is_empty()
	):
		return
	if Time.get_ticks_msec() < _focus_due_ms or not _binding.material:
		return
	var forward := panel.global_basis.inverse() * -view_camera.global_basis.z
	# From the displaced viewing position, sample the actual point on the unit sphere.
	var seat := -Vector3(view_horizontal, view_vertical, -view_zoom)
	var along := seat.dot(forward.normalized())
	var direction := (
		(
			seat
			+ (
				forward.normalized()
				* (-along + sqrt(maxf(along * along - seat.length_squared() + 1, 0)))
			)
		)
		. normalized()
	)
	var angles := StereoFocus.gaze(direction)
	if not StereoFocus.measurable(angles, geometry, fisheye_fov):
		return
	_focus_due_ms = Time.get_ticks_msec() + (1000 if low_end_gpu else StereoFocus.INTERVAL_MS)
	var pair := media.last_pair.duplicate(true)
	var frame_key := [media.session_id, pair.get("source_epoch", 0), pair.get("frame_id", 0)]
	if frame_key == _focus_last_frame:
		return
	_focus_last_frame = frame_key
	if not platform.pin_mpv_pair(int(pair.session_id), int(pair.slot_token)):
		return
	_focus_busy = true
	_focus_pin = pair
	var generation := _focus_generation
	var settings_key := [
		geometry, top_bottom, swap_eyes, stereo_half, fisheye_fov, stereo_horizontal
	]
	var binding := Binding.new()
	_focus_binding = binding
	var target := ShaderMaterial.new()
	if not binding.bind(target, pair):
		platform.release_mpv_pair_pin(int(pair.session_id), int(pair.slot_token))
		_focus_pin = {}
		_focus_binding = null
		_focus_busy = false
		return
	var uv: Array = pair.get("color_uv_scale", [1.0, 1.0])
	var image: Image = await _focus_probe.capture(
		self,
		binding.color_texture(),
		{
			"source_size": Vector2(pair.width, pair.height),
			"gaze": angles,
			"geometry": geometry,
			"top_bottom": top_bottom,
			"swap_eyes": swap_eyes,
			"stereo_half": stereo_half,
			"fisheye_fov": float(fisheye_fov),
			"rotation_degrees": int(pair.rotation_degrees),
			"color_uv_scale": Vector2(uv[0], uv[1])
		},
		platform
	)
	binding.unbind()
	platform.release_mpv_pair_pin(int(pair.session_id), int(pair.slot_token))
	_focus_pin = {}
	_focus_binding = null
	if (
		image == null
		or generation != _focus_generation
		or not requested_play
		or media.state != "playing"
		or not panel.visible
	):
		_focus_busy = false
		return
	var worker := Thread.new()
	_focus_thread = worker
	var result := {}
	if worker.start(StereoFocus.measure.bind(image), Thread.PRIORITY_LOW) == OK:
		while worker.is_alive():
			await get_tree().process_frame
		result = worker.wait_to_finish()
	_focus_thread = null
	_focus_busy = false
	if (
		generation != _focus_generation
		or stereo_focus_mode != 1
		or not requested_play
		or media.state != "playing"
		or not panel.visible
		or not media.accepts(int(pair.session_id))
	):
		return
	if int(pair.source_epoch) != int(media.last_pair.get("source_epoch", -1)):
		return
	if (
		settings_key
		!= [geometry, top_bottom, swap_eyes, stereo_half, fisheye_fov, stereo_horizontal]
	):
		return
	autofocus.observe(
		result,
		ProjectedSubtitles.runtime_ipd(),
		angles,
		geometry == Geometry.Geometry.EQUIRECT_360,
		stereo_horizontal / 100.0,
		Time.get_ticks_msec()
	)


func set_hdr_to_sdr(enabled: bool) -> void:
	hdr_to_sdr = enabled
	if media.accepts(media.session_id) and PlatformMethods.supports(platform, "set_mpv_hdr_to_sdr"):
		platform.set_mpv_hdr_to_sdr(media.session_id, enabled)


func set_playback_speed(value: float) -> bool:
	if not is_finite(value) or value < 0.25 or value > 3.0 or not media.accepts(media.session_id):
		return false
	if (
		not PlatformMethods.supports(platform, "set_mpv_speed")
		or not platform.set_mpv_speed(media.session_id, value)
	):
		return false
	playback_speed = value
	changed.emit()
	return true


func toggle_play() -> void:
	if media.state == "ended":
		requested_play = true
		seek_absolute(0)
		return
	requested_play = not requested_play
	if not requested_play:
		_record_history(true)
	if platform and media.accepts(media.session_id):
		platform.set_mpv_playing(
			media.session_id, requested_play and not _waiting_first and not stick_scrubbing
		)
	changed.emit()


func set_sync_delay(key: String, value: float) -> bool:
	if (
		key not in ["subtitle_delay_ms", "audio_delay_ms"]
		or not is_finite(value)
		or value < -10000
		or value > 10000
	):
		return false
	var sub := roundi(value) if key == "subtitle_delay_ms" else subtitle_delay_ms
	var audio := roundi(value) if key == "audio_delay_ms" else audio_delay_ms
	if (
		not PlatformMethods.supports(platform, "set_mpv_sync")
		or not media.accepts(media.session_id)
	):
		return false
	if not platform.set_mpv_sync(media.session_id, sub, audio):
		return false
	subtitle_delay_ms = sub
	audio_delay_ms = audio
	_clear_subtitle_text()
	changed.emit()
	return true


func commit_sync() -> void:
	_remember_mode()


func pick_external_subtitle() -> void:
	if _subtitle_pick > 0 or _subtitle_loading or not media.accepts(media.session_id):
		return
	if not PlatformMethods.supports(platform, "pick_local_subtitle"):
		picker_error = "Subtitle picker unavailable"
		changed.emit()
		return
	_subtitle_pick_session = media.session_id
	_subtitle_pick = platform.pick_local_subtitle()


func _on_subtitle_selected(payload: String) -> void:
	var result: Variant = JSON.parse_string(payload)
	if (
		not result is Dictionary
		or _subtitle_pick <= 0
		or int(result.get("picker_request", 0)) != _subtitle_pick
	):
		return
	if _subtitle_pick_session != media.session_id:
		_subtitle_pick = 0
		changed.emit()
		return
	if result.get("state") in ["cancelled", "error"]:
		_subtitle_pick = 0
		if result.state == "error":
			picker_error = "Unable to read subtitle. Select it again."
	elif result.get("state") == "selected":
		_subtitle_pick = 0
		_pending_external_uri = str(result.get("uri", ""))
	changed.emit()


func _on_subtitle_import(id: int, payload: String) -> void:
	if id != media.session_id or not _subtitle_loading:
		return
	var result: Variant = JSON.parse_string(payload)
	if not result is Dictionary:
		return
	if result.get("state") == "queued":
		_subtitle_import_command = int(result.get("command", 0))
		_subtitle_import_uri = str(result.get("uri", ""))
		subtitles.select(-1)
	elif result.get("state") == "error":
		_subtitle_loading = false
		picker_error = "Unable to load text subtitle. Select it again."
	changed.emit()


func forget_external_subtitle() -> void:
	if _subtitle_loading or _subtitle_pick > 0:
		return
	external_subtitle_uri = ""
	_pending_external_uri = ""
	if picker_error.contains("subtitle"):
		picker_error = ""
	_remember_mode()
	changed.emit()


## Keep MPV at unity gain and unmuted; Android's media stream owns volume.
func _apply_audio_track(track_id: int) -> bool:
	if track_id < -1 or not platform or not media.accepts(media.session_id):
		return false
	if not platform.set_mpv_audio(media.session_id, track_id, 100.0, false):
		return false
	audio_track_id = track_id
	_audio_pending = false
	changed.emit()
	return true


## An explicit menu choice wins over automatic dubbing, including before the first frame.
func select_audio_track(track_id: int) -> bool:
	if not _apply_audio_track(track_id):
		return false
	_remember_track("audio", track_id)
	_clone_applied = true
	prefer_clone_voice = clone_voice_track() > 0 and track_id == clone_voice_track()
	return true


func _remember_track(kind: String, id: int) -> void:
	if kind == "secondary_subtitle" and (not history_enabled or not _remember_file):
		return
	var tracks: Array = (
		subtitle_tracks()
		if kind in ["subtitle", "secondary_subtitle"]
		else media.playback.get("details", {}).get("audio_tracks", [])
	)
	var choice := TrackPreference.capture(id, tracks)
	if choice.is_empty():
		return
	_track_choices[kind] = choice
	if (
		kind in ["subtitle", "secondary_subtitle"]
		and (_subtitle_loading or not _pending_external_uri.is_empty())
	):
		_tracks_pending[kind] = choice.duplicate(true)
	else:
		_tracks_pending.erase(kind)
	_remember_mode()


func _restore_track_choices() -> void:
	if not media.accepts(media.session_id):
		return
	var details: Dictionary = media.playback.get("details", {})
	for kind in ["audio", "subtitle", "secondary_subtitle"]:
		if not _tracks_pending.has(kind):
			continue
		if (
			kind in ["subtitle", "secondary_subtitle"]
			and (_subtitle_loading or not _pending_external_uri.is_empty())
		):
			continue
		var track_kind: String = "subtitle" if kind == "secondary_subtitle" else kind
		if not details.has(track_kind + "_tracks"):
			continue
		var tracks: Array = subtitle_tracks() if track_kind == "subtitle" else details.audio_tracks
		var id: Variant = TrackPreference.resolve(_tracks_pending[kind], tracks)
		if id == null:
			continue
		var accepted: bool
		if kind == "secondary_subtitle":
			accepted = dual_subtitles.select(int(id), false)
		elif kind == "subtitle":
			accepted = set_subtitle_track(int(id), false)
		else:
			accepted = _apply_audio_track(int(id))
		if accepted:
			_tracks_pending.erase(kind)
			if kind == "audio":
				_clone_applied = true


func cycle_audio_track(direction: int = 1) -> bool:
	var details: Dictionary = media.playback.get("details", {})
	var tracks: Array = details.get("audio_tracks", [])
	if tracks.is_empty():
		return false
	var choices: Array[int] = [0]
	for track in tracks:
		if track is Dictionary and int(track.get("id", 0)) > 0:
			choices.append(int(track.id))
	var current := int(details.get("audio_track_id", 0))
	var index := choices.find(current)
	return select_audio_track(choices[posmod(index + direction, choices.size())])


func seek_absolute(position_ms: int, mode: String = "") -> bool:
	if not platform or not media.accepts(media.session_id):
		return false
	control.seek_absolute(position_ms)
	_request_revision(control.target_ms, mode)
	return true


func _bookmark_resolve() -> void:
	_bookmark_media_id = bookmark_store.resolve(
		local_uri, str(_bookmark_metadata.get("basename", "")), _bookmark_metadata.get("size", -1)
	)
	_bookmark_cache_revision = -1


func bookmark_seekable() -> bool:
	var details: Dictionary = media.playback.get("details", {})
	return (
		media.accepts(media.session_id)
		and control.duration_ms > 0
		and details.get("seekable", "") == "yes"
		and details.get("partially_seekable", "no") != "yes"
		and media.state not in ["failed", "closed"]
	)


func bookmark_scope() -> String:
	return str(_bookmark_scope_sequence) + "|" + _bookmark_media_id


func bookmark_snapshot() -> Dictionary:
	if (
		not bookmark_seekable()
		or _waiting_first
		or control.pending
		or control.in_flight > 0
		or not _pending_revision.is_empty()
		or _is_frozen()
		or not panel
		or not panel.visible
	):
		return {}
	var pair: Dictionary = _binding.ticket
	if (
		not preload("res://scripts/pair_texture_binding.gd").timing_valid(pair)
		or int(pair.get("session_id", -1)) != media.session_id
		or int(pair.get("generation", -1)) != media.generation
		or int(pair.get("pts_us", -1)) < 0
	):
		return {}
	var time := int(pair.pts_us) / 1000
	if time >= control.duration_ms:
		return {}
	return {"scope": bookmark_scope(), "position_ms": time}


func bookmarks_snapshot() -> Dictionary:
	if _bookmark_cache_revision != bookmark_store.revision:
		_bookmark_rows = bookmark_store.list_markers(_bookmark_media_id)
		_bookmark_cache_revision = bookmark_store.revision
	return {
		"bookmark_scope": bookmark_scope(),
		"bookmarks": _bookmark_rows,
		"bookmark_revision": bookmark_store.revision,
		"bookmark_undo": bookmark_store.can_undo(),
		"bookmark_ready": false,
		"bookmark_seekable": bookmark_seekable(),
		"seek_mode": SeekPolicy.normalize(seek_mode),
		"bookmark_seek_mode": SeekPolicy.bookmark_override(bookmark_seek_mode),
		"bookmark_effective_seek_mode": SeekPolicy.effective(seek_mode, bookmark_seek_mode)
	}


func bookmark_action(operation: String, marker_id: String, scope: String) -> String:
	if scope != bookmark_scope():
		return ""
	match operation:
		"delete":
			return (
				"Bookmark deleted"
				if bookmark_store.remove(_bookmark_media_id, marker_id)
				else "Bookmark save failed"
			)
		"undo":
			return "Bookmark restored" if bookmark_store.restore() else "Bookmark save failed"
		"seek":
			if not bookmark_seekable():
				return ""
			for marker in bookmark_store.list_markers(_bookmark_media_id):
				if marker.id == marker_id and int(marker.position_ms) < control.duration_ms:
					return (
						""
						if seek_absolute(
							int(marker.position_ms),
							SeekPolicy.effective(seek_mode, bookmark_seek_mode)
						)
						else "Bookmark jump failed"
					)
	return ""


func _clear_subtitle_text(reset_sequence: bool = false) -> void:
	subtitles.clear(reset_sequence)
	dual_subtitles.state.clear(reset_sequence)


func set_subtitle_track(track_id: int, remember: bool = true) -> bool:
	if track_id < -1 or not platform or not media.accepts(media.session_id):
		return false
	if track_id > 0 and not subtitle_tracks().any(func(t): return int(t.id) == track_id):
		return false
	if track_id > 0 and track_id == dual_subtitles.state.requested_track:
		if not dual_subtitles.select(0):
			return false
	if not platform.set_mpv_subtitle(media.session_id, track_id):
		return false
	subtitles.select(track_id)
	dual_subtitles.primary_changed()
	if remember:
		_remember_track("subtitle", track_id)
	if _subtitle_surface:
		_subtitle_surface.visible = false
	if caption:
		caption.visible = false
	if projected_subtitles:
		projected_subtitles.clear(material)
	changed.emit()
	return true


func set_subtitle_encoding(value: Variant) -> bool:
	if (
		not value is Dictionary
		or not preload("res://scripts/file_subtitle_encoding.gd").valid(
			{value.get("track_key", ""): value.get("encoding", "")}
		)
	):
		return false
	if not subtitle_tracks().any(
		func(t):
			return t.get("external", false) and str(t.get("encoding_key", "")) == value.track_key
	):
		return false
	if subtitle_encodings.size() >= 16 and not subtitle_encodings.has(value.track_key):
		return false
	subtitle_encodings[value.track_key] = value.encoding
	_remember_mode()
	changed.emit()
	return true


func subtitle_encoding_row(secondary: bool = false) -> Dictionary:
	return preload("res://scripts/file_subtitle_encoding.gd").row(
		subtitle_tracks(),
		dual_subtitles.state.requested_track if secondary else subtitles.requested_track,
		subtitle_encodings
	)


func subtitle_tracks() -> Array[Dictionary]:
	var tracks: Array[Dictionary] = []
	var details: Dictionary = media.playback.get("details", {})
	for track in details.get("subtitle_tracks", []):
		if (
			track is Dictionary
			and int(track.get("id", 0)) > 0
			and SubtitleState.text_codec(str(track.get("codec", "")))
		):
			tracks.append(track)
	return tracks


func cycle_subtitle_track(direction: int = 1) -> bool:
	var choices: Array[int] = [0]
	for track in subtitle_tracks():
		choices.append(int(track.id))
	if choices.size() == 1:
		return false
	return set_subtitle_track(
		choices[posmod(choices.find(subtitles.requested_track) + direction, choices.size())]
	)


func _poll_subtitles() -> void:
	if not caption:
		return
	var ready := (
		platform != null
		and media.accepts(media.session_id)
		and not presentation_context().is_empty()
		and not _waiting_first
		and _pending_revision.is_empty()
		and panel.visible
	)
	if not ready:
		dual_subtitles.state.clear()
		caption.visible = false
		projected_subtitles.clear(material)
		if _subtitle_surface:
			_subtitle_surface.visible = false
		return
	var now := Time.get_ticks_msec()
	if now >= _subtitle_poll_ms:
		_subtitle_poll_ms = now + 50
		var payload: String = platform.get_mpv_subtitles(media.session_id, subtitles.sequence)
		var snapshot: Variant = JSON.parse_string(payload) if not payload.is_empty() else null
		if snapshot is Dictionary:
			if subtitles.observe(snapshot, media.session_id, presentation_context()):
				_subtitle_received_ms = now
			dual_subtitles.observe(snapshot)
	if now - _subtitle_received_ms > 1000:
		_clear_subtitle_text()
	caption.text = dual_subtitles.compose()
	caption.visible = not caption.text.is_empty()
	if caption.visible:
		_place_caption()
	else:
		projected_subtitles.clear(material)
	_sync_subtitle_surface()


func set_subtitle_below_screen(value: bool) -> bool:
	if geometry != Geometry.Geometry.FLAT or not media.accepts(media.session_id):
		return false
	subtitle_below_screen = value
	if history_enabled:
		_remember_mode()
	if caption and caption.visible:
		_place_caption()
	changed.emit()
	return true


func _place_caption_below(pose: Transform3D) -> void:
	caption.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	caption.global_transform = Transform3D(pose.basis, pose * Vector3(0, 0, 0.01))
	# Work in the caption plane, not gravity coordinates. Reclining placement must
	# move along the screen's down axis while retaining its normal/depth offset.
	var to_plane := pose.affine_inverse()
	var panel_in_plane := to_plane * panel.global_transform
	var caption_in_plane := to_plane * caption.global_transform
	var screen_bounds := panel.get_aabb()
	var text_bounds := caption.get_aabb()
	var screen_bottom := INF
	var text_top := -INF
	for index in 8:
		screen_bottom = minf(screen_bottom, (panel_in_plane * screen_bounds.get_endpoint(index)).y)
		text_top = maxf(text_top, (caption_in_plane * text_bounds.get_endpoint(index)).y)
	# Label3D bounds omit the outline; project its extent onto this plane's up axis.
	var basis := caption_in_plane.basis
	var outline := caption.outline_size * caption.pixel_size * (absf(basis.x.y) + absf(basis.y.y))
	caption.global_position += (
		pose.basis.y * (screen_bottom - SUBTITLE_BELOW_GAP - text_top - outline)
	)


func _place_caption() -> void:
	caption.modulate = CaptionPalette.INK[CaptionPalette.index(subtitle_palette)]
	caption.outline_modulate = CaptionPalette.outline(subtitle_palette)
	caption.modulate.a = 1.0 - subtitle_transparency / 100.0
	caption.outline_modulate.a = caption.modulate.a
	if geometry == Geometry.Geometry.FLAT:
		# Ordinary video captions stay on the screen, independent of immersive preferences.
		var pose := subtitle_transform()
		caption.font_size = roundi(40 * subtitle_size)
		caption.outline_size = maxi(2, roundi(8 * subtitle_size))
		var pixel_size := 0.0016 * screen_scale
		caption.pixel_size = pixel_size
		var margin := minf(0.06 * screen_scale, _flat.size.y * 0.1)
		# Include the actual multiline text height in the usable travel range.
		caption.width = _flat.size.x * 0.9 / pixel_size
		caption.vertical_alignment = (
			VERTICAL_ALIGNMENT_TOP if subtitle_below_screen else VERTICAL_ALIGNMENT_BOTTOM
		)
		var available_height := maxf(0.001, _flat.size.y - 2 * margin)
		var fit := minf(1.0, available_height / maxf(0.001, caption.get_aabb().size.y))
		caption.pixel_size = pixel_size * fit
		var text_height := caption.get_aabb().size.y
		var y := lerpf(
			-_flat.size.y * 0.5 + margin,
			_flat.size.y * 0.5 - margin - maxf(0.064 * subtitle_size * screen_scale, text_height),
			subtitle_flat_position
		)
		var anchor := pose * Vector3(0, y, 0.01)
		caption.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		caption.layers = 1
		projected_subtitles.clear(material)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		caption.global_transform = Transform3D(pose.basis, anchor)
		if subtitle_below_screen:
			_place_caption_below(pose)
		return
	# Anchor in the video's coordinates, like burned-in captions. Head pose never changes it.
	# Direction/recenter/zoom move captions with the video; roll is excluded by the independent surface.
	var anchor_basis := SubtitleDepth.anchor(subtitle_position, subtitle_direction == 1)
	if subtitle_follow_view:
		anchor_basis = (
			Basis.looking_at(subtitle_follow.direction(subtitle_follow.centre), Vector3.UP)
			* anchor_basis
		)
	caption.layers = 0  # The live text patch is drawn only by the video's shader.
	projected_subtitles.update_patch(
		caption,
		material,
		anchor_basis,
		subtitle_distance,
		ProjectedSubtitles.runtime_ipd(),
		subtitle_direction == 1,
		subtitle_size
	)


func seek_relative(delta_ms: int) -> bool:
	if not platform or not media.accepts(media.session_id):
		return false
	control.seek_relative(delta_ms)
	_request_revision(control.target_ms)
	return true


func stick_scrub_available() -> bool:
	return (
		surface_requested
		and not _fallback_queued
		and not _fallback_pending
		and (
			stick_scrubbing
			or (
				layer_shown
				and not _waiting_first
				and bookmark_seekable()
				and (
					local_uri.begins_with("file://")
					or local_uri.begins_with("content://")
					or local_uri.begins_with("smb://")
				)
			)
		)
	)


func set_stick_scrubbing(held: bool) -> void:
	if stick_scrubbing == held:
		return
	stick_scrubbing = held
	if (
		not held
		and platform
		and media.accepts(media.session_id)
		and not _waiting_first
		and not control.pending
		and control.in_flight == 0
		and media.state != "ended"
	):
		platform.set_mpv_playing(media.session_id, requested_play)


func repeat_stick_seek(delta_ms: int) -> void:
	var target := clampi(control.target_ms + delta_ms, 0, maxi(0, control.duration_ms - 1))
	if stick_scrubbing and target != control.target_ms:
		seek_absolute(target)


## The current projection and layout as a lock.
func current_lock() -> Dictionary:
	return {
		"geometry": geometry, "layout": stereo_layout(), "depth": false, "fisheye_fov": fisheye_fov
	}


## Locks the current mode, or unlocks when it is the locked one.
func toggle_mode_lock() -> void:
	_auto_stereo = false
	_stereo_detection.cancel()
	_layout_pending = null
	var current := current_lock()
	mode_lock = {} if mode_lock == current else current
	_remember_mode()
	mode_lock_changed.emit(mode_lock.duplicate())
	changed.emit()


## A stored lock, checked; anything malformed leaves the player unlocked.
func load_mode_lock(value: Variant) -> void:
	mode_lock = {}
	if not value is Dictionary:
		return
	var numbers := ["geometry", "layout", "fisheye_fov"].all(
		func(k): return value.get(k) is int or value.get(k) is float
	)
	if (
		not numbers
		or not value.get("depth") is bool
		or int(value.geometry) not in [0, 1, 2, 3]
		or int(value.layout) not in [0, 1, 2, 3, 4]
		or int(value.fisheye_fov) not in FISHEYE_FOVS
	):
		return
	mode_lock = {
		"geometry": int(value.geometry),
		"layout": int(value.layout),
		"depth": false,
		"fisheye_fov": int(value.fisheye_fov)
	}


## 2D -> side by side -> top-bottom -> 2D.
func toggle_stereo() -> void:
	set_stereo_layout(0 if stereo_sbs and top_bottom else (2 if stereo_sbs else 1))


## 0 mono, 1 full SBS, 2 full TB, 3 half SBS, 4 half TB.
func set_stereo_layout(layout: int) -> void:
	if layout < 0 or layout > 4:
		return
	_auto_stereo = false
	_stereo_detection.cancel()
	_layout_pending = null  # The same manual 2D value must also stop first-frame inference.
	if layout == stereo_layout():
		_remember_mode()
		return
	_unlock_mode()
	var repack := (layout != 0) != stereo_sbs or (layout in [2, 4]) != top_bottom
	stereo_sbs = layout != 0
	top_bottom = layout in [2, 4]
	stereo_half = layout in [3, 4]
	_remember_mode()
	if repack:
		_request_revision()
	_apply_geometry()
	changed.emit()


func stereo_layout() -> int:
	return (
		0
		if not stereo_sbs
		else ((4 if top_bottom else 3) if stereo_half else (2 if top_bottom else 1))
	)


func set_fisheye_fov(value: int) -> void:
	if not value in FISHEYE_FOVS or value == fisheye_fov:
		return
	_unlock_mode()
	fisheye_fov = value
	_apply_geometry()
	_remember_mode()
	changed.emit()


func cycle_projection() -> void:
	set_projection((geometry + 1) % 4)


func set_projection(value: int) -> void:
	if value < 0 or value > 3:
		return
	_auto_stereo = false
	_stereo_detection.cancel()
	if value != geometry:
		_unlock_mode()
	geometry = value
	if _layout_pending is Dictionary:
		_layout_pending.geometry = value
	# Fisheye is a projection, independent of mono/SBS/TB. Preserve the chosen eye layout.
	var stereo := (
		stereo_sbs
		if geometry == Geometry.Geometry.FISHEYE
		else geometry == Geometry.Geometry.HALF_EQUIRECT
	)
	var revise := false
	if geometry != Geometry.Geometry.FLAT and stereo != stereo_sbs:
		stereo_sbs = stereo
		revise = true
	if revise:
		_request_revision()
	_apply_geometry()
	_remember_mode()
	changed.emit()


func toggle_eye_order() -> bool:
	if not stereo_sbs:
		return false
	_auto_stereo = false
	_stereo_detection.cancel()
	swap_eyes = not swap_eyes
	_apply_geometry()
	_remember_mode()
	changed.emit()
	return true


func set_viewing_eye(value: int) -> bool:
	if not stereo_sbs or value not in [0, 1, 2]:
		return false
	viewing_eye = value
	_apply_stereo_view()
	_remember_mode()
	changed.emit()
	return true


func set_stereo_alignment(key: String, value: float) -> bool:
	if not stereo_sbs or viewing_eye != 0 or not is_finite(value):
		return false
	if key not in ["stereo_horizontal", "stereo_vertical"]:
		return false
	var limit := (
		10.0
		if key == "stereo_horizontal" and geometry != Geometry.Geometry.FLAT
		else StereoView.LIMIT
	)
	set(key, clampf(snappedf(value, StereoView.STEP), -limit, limit))
	_stereo_view_dirty = true
	_apply_stereo_view()
	return true


func zoom_view(amount: float) -> void:
	super(amount)
	if geometry != Geometry.Geometry.FLAT:
		_immersive_dirty = true


func set_immersive_adjustment(key: String, value: float) -> bool:
	var policy := preload("res://scripts/immersive_adjustments.gd")
	if geometry == Geometry.Geometry.FLAT or key not in policy.KEYS or not is_finite(value):
		return false
	var limits: Vector2 = policy.limits(key)
	set(key, clampf(value, limits.x, limits.y))
	_immersive_dirty = true
	_center_on_view()
	return true


func commit_immersive_adjustments() -> void:
	if _immersive_dirty:
		_immersive_dirty = false
		_remember_mode()
	commit_stereo_view()


func reset_immersive_adjustments() -> void:
	if geometry == Geometry.Geometry.FLAT:
		return
	for key in preload("res://scripts/immersive_adjustments.gd").KEYS:
		set(key, 0.0)
	_center_on_view()
	_immersive_dirty = true
	commit_immersive_adjustments()


func reset_stereo_alignment() -> void:
	stereo_horizontal = 0.0
	stereo_vertical = 0.0
	_stereo_view_dirty = true
	_apply_stereo_view()
	commit_stereo_view()
	changed.emit()


func commit_stereo_view() -> void:
	if not _stereo_view_dirty:
		return
	_stereo_view_dirty = false
	_remember_mode()


func _apply_stereo_view() -> void:
	if geometry == Geometry.Geometry.FLAT:
		stereo_horizontal = clampf(stereo_horizontal, -StereoView.LIMIT, StereoView.LIMIT)
	if not material:
		return
	# Native stereo only: mono and generated 2D->3D never inherit these corrections.
	material.set_shader_parameter("viewing_eye", viewing_eye if stereo_sbs else 0)
	material.set_shader_parameter(
		"stereo_offset",
		Vector2(stereo_horizontal, stereo_vertical) * 0.01 if stereo_sbs else Vector2.ZERO
	)


func enable_auto_stereo() -> void:
	_unlock_mode()
	_auto_stereo = true
	var stated := Naming.from_name(_layout_basename)
	if not stated.has("geometry"):
		stated.geometry = geometry
	_layout_pending = stated
	if int(media.format.get("width", 0)) > 0:
		_complete_layout()
	_stereo_detection.begin(true)
	_remember_mode()
	changed.emit()


func _apply_automatic_stereo(chosen: Dictionary, source: String) -> void:
	if (
		not _auto_stereo
		or not media.accepts(media.session_id)
		or not bool(chosen.get("stereo", false))
	):
		return
	_stereo_detection.cancel()
	var stacked := bool(chosen.get("top_bottom", false))
	var half := bool(chosen.get("stereo_half", false))
	# Image matching identifies the packing axis, not which view is the left eye.
	var swapped := swap_eyes if source == "image" else bool(chosen.get("swap", false))
	var repack := not stereo_sbs or top_bottom != stacked
	var layout_changed := repack or stereo_half != half or swap_eyes != swapped
	stereo_sbs = true
	top_bottom = stacked
	stereo_half = half
	swap_eyes = swapped
	_remember_mode()
	if repack:
		_request_revision()
	_apply_geometry()
	if layout_changed:
		_thumb_after_ms = 0
	Log.record(
		"auto_stereo", {"source": source, "top_bottom": top_bottom, "stereo_half": stereo_half}
	)
	changed.emit()


func _accept_stereo_detection(request: int, result: Dictionary) -> void:
	if not _auto_stereo:
		return
	var axis := _stereo_detection.accept(request, result)
	if axis.is_empty():
		return
	var chosen := Naming.complete(
		{"geometry": geometry, "stereo": true, "top_bottom": axis == "tb"},
		int(media.format.width),
		int(media.format.height)
	)
	_apply_automatic_stereo(chosen, "image")


## A tiny full-frame GPU sample; pin ownership and independent wrappers match thumbnail capture.
## CPU matching runs off the render/main thread, and stale/manual requests cannot apply results.
func _maybe_detect_stereo() -> void:
	if (
		not _auto_stereo
		or not _stereo_detection.pending
		or (diagnostics != null and diagnostics.benchmark)
	):
		return
	if Naming.has_layout_marker(_layout_basename):
		_stereo_detection.cancel()
		return
	if (
		_stereo_detection_busy
		or _thumbnail_busy
		or (diagnostics != null and diagnostics.pixel_busy)
		or _waiting_first
		or not _pending_revision.is_empty()
		or media.state not in ["playing", "paused", "ended"]
		or media.last_pair.is_empty()
		or not _binding.material
	):
		return
	if Naming.has_stereo_metadata(media.format):
		var stated := Naming.from_name(_layout_basename)
		stated.geometry = geometry
		var explicit := Naming.complete(
			stated,
			int(media.format.width),
			int(media.format.height),
			media.format,
			_layout_basename
		)
		_apply_automatic_stereo(explicit, "metadata")
		return
	var pair := media.last_pair.duplicate(true)
	if not _stereo_detection.wants(int(pair.frame_id), media.state in ["paused", "ended"]):
		return
	if not platform.pin_mpv_pair(int(pair.session_id), int(pair.slot_token)):
		return
	var request := _stereo_detection.started(int(pair.frame_id))
	_stereo_detection_busy = true
	_stereo_capture_busy = true
	_stereo_pin = pair
	var binding := Binding.new()
	_stereo_capture_binding = binding
	var target := ShaderMaterial.new()
	if not binding.bind(target, pair):
		platform.release_mpv_pair_pin(int(pair.session_id), int(pair.slot_token))
		_stereo_pin = {}
		_stereo_capture_binding = null
		_stereo_capture_busy = false
		_stereo_detection_busy = false
		_stereo_detection.accept(request, {})
		return
	var scale: Array = pair.get("color_uv_scale", [1.0, 1.0])
	var image: Image = await Thumbnails.capture(
		self,
		binding.color_texture(),
		false,
		false,
		Vector4(0, 0, 1, 1),
		Vector2(float(scale[0]), float(scale[1])),
		false,
		Vector2i(192, 108)
	)
	binding.unbind()
	platform.release_mpv_pair_pin(int(pair.session_id), int(pair.slot_token))
	_stereo_pin = {}
	_stereo_capture_binding = null
	_stereo_capture_busy = false
	if request != _stereo_detection.token or not image or image.is_empty():
		_stereo_detection_busy = false
		_stereo_detection.accept(request, {})
		return
	var worker := Thread.new()
	_stereo_thread = worker
	if worker.start(StereoDetection.classify.bind(image), Thread.PRIORITY_LOW) != OK:
		_stereo_thread = null
		_stereo_detection_busy = false
		_stereo_detection.accept(request, {})
		return
	while worker.is_alive():
		await get_tree().process_frame
	var result: Variant = worker.wait_to_finish()
	_stereo_thread = null
	_stereo_detection_busy = false
	_accept_stereo_detection(request, result if result is Dictionary else {})


## Names/metadata/shape resolve first; ambiguous packed stereo is checked from image samples.
func _complete_layout() -> void:
	if _layout_pending == null:
		return
	var chosen := preload("res://scripts/video_mode_default.gd").resolve(
		_layout_pending,
		int(media.format.width),
		int(media.format.height),
		media.format,
		_layout_basename,
		last_video_mode,
		reuse_last_mode
	)
	_layout_pending = null
	if chosen.has("fisheye_fov"):
		fisheye_fov = int(chosen.fisheye_fov)
	swap_eyes = chosen.swap
	stereo_half = chosen.stereo_half
	var tb := bool(chosen.stereo) and bool(chosen.top_bottom)
	if int(chosen.geometry) != geometry or bool(chosen.stereo) != stereo_sbs or tb != top_bottom:
		geometry = int(chosen.geometry)
		var revise := bool(chosen.stereo) != stereo_sbs or tb != top_bottom
		stereo_sbs = chosen.stereo
		top_bottom = tb
		if revise:
			_request_revision()
	_apply_geometry()
	Log.record(
		"auto_layout",
		{
			"geometry": geometry,
			"stereo_sbs": stereo_sbs,
			"swap_eyes": swap_eyes,
			"width": media.format.width,
			"height": media.format.height
		}
	)


## Packed masks show only on the layout they were made for (fisheye side by side).
func _apply_packed() -> void:
	if not material:
		alpha_enabled = false
		return
	var shown := packed_alpha and packed_alpha_blocker().is_empty()
	_binding.set_opaque(not shown)
	material.set_shader_parameter("packed_alpha", shown)
	if shown:
		material.set_shader_parameter(
			"packed_size",
			Vector2(Geometry.packed_dimensions(int(media.format.width), int(media.format.height)))
		)
	alpha_enabled = shown


func _remember_mode() -> void:
	if not _remember_file or not media.accepts(media.session_id):
		return
	var mode := {
		"layout_auto": _auto_stereo,
		"geometry": geometry,
		"stereo_sbs": stereo_sbs,
		"swap_eyes": swap_eyes,
		"viewing_eye": viewing_eye,
		"stereo_horizontal": stereo_horizontal,
		"stereo_vertical": stereo_vertical,
		"view_horizontal": view_horizontal,
		"view_vertical": view_vertical,
		"view_zoom": view_zoom,
		"top_bottom": stereo_sbs and top_bottom,
		"stereo_half": stereo_sbs and stereo_half,
		"fisheye_fov": fisheye_fov,
		"subtitle_delay_ms": subtitle_delay_ms,
		"audio_delay_ms": audio_delay_ms,
		"external_subtitle_uri": external_subtitle_uri,
		"subtitle_encodings": subtitle_encodings.duplicate(true)
	}
	var previous := mode_memory.lookup(local_uri)
	if previous.has("color_grade"):
		mode["color_grade"] = previous.color_grade
	if history_enabled:
		mode["stereo_focus_mode"] = stereo_focus_mode
		mode["stereo_focus"] = stereo_focus
		mode["subtitle_below_screen"] = subtitle_below_screen
	else:
		# Other allowed mode changes must not persist this private session's preference.
		for key in ["stereo_focus_mode", "stereo_focus"]:
			if previous.has(key):
				mode[key] = previous[key]
		if previous.has("subtitle_below_screen"):
			mode["subtitle_below_screen"] = previous.subtitle_below_screen
	if not _track_choices.is_empty():
		mode["track_choices"] = _track_choices.duplicate(true)
	if mode_memory.remember(local_uri, mode) and not mode_memory.save():
		Log.record("file_mode_save_failed", {"error": mode_memory.last_error})


func can_remember_color_grade() -> bool:
	return (
		history_enabled
		and _remember_file
		and media.accepts(media.session_id)
		and not ModeMemory.key_for(local_uri).is_empty()
	)


func has_file_color_grade() -> bool:
	return can_remember_color_grade() and mode_memory.lookup(local_uri).has("color_grade")


func preview_color_grade() -> void:
	_color_grade_changed = true
	color_grade.apply(material)


func commit_color_grade(clear: bool = false) -> void:
	if clear and not has_file_color_grade():
		return
	if not clear and not _color_grade_changed:
		return
	_color_grade_changed = false
	if not can_remember_color_grade():
		return
	var mode := mode_memory.lookup(local_uri)
	if mode.is_empty():
		_remember_mode()
		mode = mode_memory.lookup(local_uri)
	if clear:
		mode.erase("color_grade")
		color_grade.restore(default_color_grade)
		color_grade.apply(material)
	else:
		mode["color_grade"] = color_grade.snapshot()
	if mode_memory.remember(local_uri, mode) and not mode_memory.save():
		Log.record("file_mode_save_failed", {"error": mode_memory.last_error})


func _on_pair(id: int, payload: String) -> void:
	if id != media.session_id:
		return
	var pair: Variant = JSON.parse_string(payload)
	if pair is Dictionary:
		_pending_pair = pair


func _present_pending() -> void:
	if (
		(diagnostics != null and diagnostics.pixel_busy)
		or _thumbnail_busy
		or _stereo_capture_busy
		or _pending_pair.is_empty()
		or not _pending_revision.is_empty()
	):
		return
	var offered := _pending_pair
	_pending_pair = {}
	var claimed: Variant = JSON.parse_string(
		platform.claim_mpv_pair(media.session_id, int(offered.slot_token))
	)
	if not claimed is Dictionary:
		return
	_unbind()
	_binding.opaque = not alpha_wanted() and claimed.get("mask_kind") == "opaque"
	if not _binding.bind(material, claimed):
		platform.detach_mpv_pair(media.session_id, int(claimed.slot_token))
		picker_error = "Complete video frame could not be bound"
		changed.emit()
		return
	media.last_pair = claimed
	media.logical_session_id = int(claimed.logical_session_id)
	media.generation = int(claimed.generation)
	media.format_revision = int(claimed.format_revision)
	media.presentation_revision = int(claimed.presentation_revision)
	media.frame_counter += 1
	var par := float(claimed.get("pixel_aspect", 1.0))
	media.format = {
		"width": int(claimed.width),
		"height": int(claimed.height),
		"pixel_aspect": par if is_finite(par) and par > 0.0 and par <= 16.0 else 1.0,
		"stereo_mode": str(claimed.get("stereo_mode", "")),
		"unapplied_rotation_degrees": 0
	}
	_apply_packed()
	material.set_shader_parameter("alpha_enabled", false)
	_apply_geometry()
	panel.visible = true
	if not platform.acknowledge_mpv_pair(media.session_id, int(claimed.slot_token)):
		_unbind()
		return
	if _waiting_first:
		if control.in_flight > 0:
			if diagnostics:
				diagnostics.record_seek("target_presented")
		_waiting_first = false
		var actual_position_ms := int(int(claimed.pts_us) / 1000)
		if control.in_flight > 0:
			control.first_frame(actual_position_ms)
		else:
			control.observe(actual_position_ms, control.duration_ms)
		platform.set_mpv_playing(media.session_id, requested_play and not stick_scrubbing)
	else:
		control.observe(int(int(claimed.pts_us) / 1000), control.duration_ms)
	if media.frame_counter == 1:
		if diagnostics:
			diagnostics.first_pair_bound(claimed)
		_complete_layout()
		_remember_mode()
		Log.record("mpv_pair_bound", media.frame_identity())
	_record_history()
	if diagnostics:
		diagnostics.record_pair(claimed)
	changed.emit()


func _on_state(id: int, payload: String) -> void:
	if id != media.session_id:
		return
	var report: Variant = JSON.parse_string(payload)
	if not report is Dictionary:
		return
	if report.get("audio_focus_change", "") == "loss":
		requested_play = false
	media.playback = report
	var details: Dictionary = report.get("details", {})
	if (
		_subtitle_loading
		and _subtitle_import_command == 0
		and int(details.get("subtitle_import_command", 0)) > _subtitle_import_floor
	):
		# A processing revision can supersede the queued callback while retaining the same MPV host.
		_subtitle_import_command = int(details.subtitle_import_command)
		_subtitle_import_uri = _subtitle_requested_uri
		subtitles.select(-1)
	if (
		_subtitle_import_command > 0
		and int(details.get("subtitle_import_command", 0)) >= _subtitle_import_command
	):
		if str(details.get("subtitle_import_error", "")).is_empty():
			external_subtitle_uri = _subtitle_import_uri
			_remember_mode()
			picker_error = ""
		else:
			picker_error = "Unable to load text subtitle. Select it again."
		_subtitle_import_command = 0
		_subtitle_import_uri = ""
		_subtitle_loading = false
	dual_subtitles.primary_changed()
	_restore_track_choices()
	var size := str(details.get("file_size", ""))
	if (
		not BookmarkStore.integer(_bookmark_metadata.get("size", -1), 1, 9007199254740991)
		and size.is_valid_int()
		and BookmarkStore.integer(int(size), 1, 9007199254740991)
	):
		# Native metadata fills gaps for recent/SAF opens, without hashing or reading the video.
		_bookmark_metadata.size = int(size)
		_bookmark_resolve()
	if details.has("position_seconds"):
		var position_ms := int(float(details.position_seconds) * 1000)
		control.observe(position_ms, int(float(details.get("duration_seconds", "-1")) * 1000))
		media.decoder = (
			str(details.get("codec", "")) + " / " + str(details.get("hwdec_current", ""))
		)
	media.state = str(report.get("state", "opening"))
	if bool(report.get("surface", false)):
		_accept_surface_state(report)
	elif report.has("surface"):
		surface_requested = false
	if surface_requested or media.state == "ended":
		_record_history(media.state == "ended")
	if diagnostics:
		diagnostics.record_state(report)
	changed.emit()


func _on_error(id: int, payload: String) -> void:
	if id != media.session_id:
		return
	if surface_requested and not force_shader_output:
		request_shader_fallback()
		return
	_thumbnail_sequence += 1
	var report: Variant = JSON.parse_string(payload)
	media.error = (
		str(report.get("code", "MPV playback failed"))
		if report is Dictionary
		else "MPV playback failed"
	)
	playback_error_detail = str(report.get("message", "")) if report is Dictionary else ""
	media.state = "failed"
	_freeze_request = 0
	_pending_revision = {}
	_seek_freeze_failed = false
	_waiting_first = false
	control.reject()
	_clear_subtitle_text()
	_recover = media.error == "MPV_GL_CONTEXT_RECREATED"
	_recover_ms = control.observed_position_ms
	_unbind()
	Log.record("mpv_error", {"session_id": id, "report": report})
	if diagnostics:
		diagnostics.flush_report()
	changed.emit()


func _on_detach(id: int, _payload: String) -> void:
	if int(_binding.ticket.get("session_id", 0)) == id and not _is_frozen():
		_unbind()


func _on_released(id: int, _payload: String) -> void:
	if id == media.session_id and _recover:
		_recover = false
		call_deferred(
			"_reopen_after_context_loss", local_uri, display_name, _recover_ms, _remember_file
		)
	if diagnostics:
		diagnostics.write_report()


func _reopen_after_context_loss(
	uri: String, title: String, position_ms: int, remember_file: bool
) -> void:
	# Retain live user choices even if the last disk save failed.
	var persisted := _file_permission_persisted
	var eye := viewing_eye
	var alignment := Vector2(stereo_horizontal, stereo_vertical)
	var adjustment := Vector3(view_horizontal, view_vertical, view_zoom)
	var live_grade := color_grade.snapshot()
	var grade_changed := _color_grade_changed
	if open_local(uri, title, position_ms, false):
		_remember_file = remember_file
		_file_permission_persisted = persisted
		viewing_eye = eye
		stereo_horizontal = alignment.x
		stereo_vertical = alignment.y
		view_horizontal = adjustment.x
		view_vertical = adjustment.y
		view_zoom = adjustment.z
		_immersive_dirty = true
		color_grade.restore(live_grade)
		color_grade.apply(material)
		_color_grade_changed = grade_changed
		_apply_stereo_view()
		if geometry != Geometry.Geometry.FLAT:
			_center_on_view()


func _source_size() -> Vector2:
	return Vector2(float(media.format.width), float(media.format.height))


func output_size() -> Vector2i:
	if layer_shown and not surface_requested and layer_controller:
		return layer_controller.image_size
	return Vector2i(int(media.format.width), int(media.format.height))


func _sync_subtitle_surface() -> void:
	if caption:
		var faded := false
		if geometry == Geometry.Geometry.FLAT and caption.visible and subtitle_transparency > 0:
			if not _flat_caption_canvas:
				_flat_caption_canvas = preload("res://scripts/flat_subtitle_canvas.gd").new()
				add_child(_flat_caption_canvas)
			if not _faded_caption:
				_faded_caption = preload("res://scripts/faded_caption.gd").new()
				caption.add_child(_faded_caption)
			faded = _faded_caption.show_caption(caption, _flat_caption_canvas)
		elif _faded_caption:
			_faded_caption.visible = false
		if geometry == Geometry.Geometry.FLAT:
			caption.layers = 0 if faded else 1
	if not _subtitle_surface or not material:
		return
	var separate := layer_shown or not is_zero_approx(screen_rotation)
	material.set_shader_parameter("separate_subtitles", separate)
	_subtitle_surface.visible = (
		separate and panel.visible and material.get_shader_parameter("subtitle_enabled") == true
	)
	if not _subtitle_surface.visible:
		return
	_subtitle_surface.mesh = panel.mesh
	_subtitle_surface.global_transform = subtitle_transform()
	for key in [
		"subtitle_opacity",
		"subtitle_texture",
		"subtitle_enabled",
		"subtitle_anchor_inverse",
		"subtitle_parallax",
		"subtitle_patch_half_extent"
	]:
		_subtitle_material.set_shader_parameter(key, material.get_shader_parameter(key))


func _pixel_aspect() -> float:
	return float(media.format.get("pixel_aspect", 1.0))


func _apply_flat_pose() -> void:
	# Reclining mode permits full placement tilt, including follow and recenter.
	if not reclining_mode:
		flat_pose = global_transform.affine_inverse() * upright_pose(global_transform * flat_pose)
	super._apply_flat_pose()
	if caption and caption.visible:
		_place_caption()
	_sync_subtitle_surface()


func _apply_geometry() -> void:
	super._apply_geometry()
	_apply_stereo_view()
	_apply_packed()
	if caption and caption.visible:
		_place_caption()
	_sync_subtitle_surface()
	material.set_shader_parameter("stereo_sbs", stereo_sbs or false)
	material.set_shader_parameter("depth_enabled", false)
	_apply_stereo_focus()


func layout_snapshot() -> Dictionary:
	var playback := control.snapshot()
	playback["seek_method"] = (
		"mpv_absolute_"
		+ ("exact" if _last_seek_mode == SeekPolicy.EXACT else "keyframes")
		+ "_and_processing_generation"
	)
	playback["seek_mode"] = SeekPolicy.normalize(seek_mode)
	playback["active_seek_mode"] = _last_seek_mode
	playback["bookmark_seek_mode"] = SeekPolicy.bookmark_override(bookmark_seek_mode)
	playback["source_frame_pts_verified"] = media.last_pair.get("source_pts_verified", false)
	return {
		"video_layers": layer_controller.snapshot() if layer_controller else {},
		"surface_context": surface_context(),
		"stereo_auto": _auto_stereo,
		"stereo_detection":
		{
			"pending": _stereo_detection.pending,
			"samples": _stereo_detection.samples,
			"captures": _stereo_detection.captures
		},
		"geometry": ["flat", "half_equirect_180", "fisheye_180", "equirect_360"][geometry],
		"stereo_sbs": stereo_sbs,
		"viewing_eye": viewing_eye,
		"stereo_horizontal": stereo_horizontal,
		"stereo_vertical": stereo_vertical,
		"opaque_rendering": material != null and material.shader == Binding.OPAQUE_SHADER,
		"top_bottom": stereo_sbs and top_bottom,
		"stereo_half": stereo_sbs and stereo_half,
		"fisheye_fov": fisheye_fov,
		"alpha_enabled": alpha_enabled,
		"packed_alpha_forced": packed_alpha_forced,
		"packed_alpha_blocker": packed_alpha_feedback(),
		"screen_rotation": screen_rotation,
		"playback_speed": playback_speed,
		"alpha_ready": alpha_ready(),
		"backend": "Android_libmpv",
		"loop_enabled": loop_enabled,
		"playback_control": playback,
		"subtitles":
		{
			"requested_track": subtitles.requested_track,
			"cue": subtitles.cue,
			"text": subtitles.text,
			"render_layer":
			(
				"independent_Label3D"
				if geometry == Geometry.Geometry.FLAT
				else "video_projection_overlay"
			),
			"size": subtitle_size,
			"flat_position": subtitle_flat_position,
			"rotation_independent": true,
			"distance_m": subtitle_distance,
			"position": subtitle_position,
			"direction": subtitle_direction,
			"runtime_ipd_m": ProjectedSubtitles.runtime_ipd(),
			"angular_parallax_rad": material.get_shader_parameter("subtitle_parallax"),
			"anchor_space": "screen" if geometry == Geometry.Geometry.FLAT else "video_local",
			"anchor_direction": _subtitle_anchor_direction(),
			"source_frame_sync_verified": false,
			"device_validation": "pending"
		},
		"frame_hold":
		{
			"visible": panel.visible,
			"frozen": _is_frozen(),
			"capture_pending": _freeze_request > 0,
			"frame_id": int(_binding.ticket.get("frame_id", -1)),
			"pts_us": int(_binding.ticket.get("pts_us", -1)),
			"frozen_frame_id": int(_binding.ticket.get("frozen_frame_id", 0)),
			"freeze_copy_us": int(_binding.ticket.get("freeze_copy_us", 0))
		},
		"device_validation": "pending"
	}


func _subtitle_anchor_direction() -> Array:
	var anchor := SubtitleDepth.anchor(subtitle_position, subtitle_direction == 1) * Vector3.FORWARD
	return [anchor.x, anchor.y, anchor.z]


func completed_presentation() -> bool:
	if (
		not requested_play
		or media.state != "ended"
		or _waiting_first
		or not _pending_revision.is_empty()
	):
		return false
	if surface_requested:
		var details: Dictionary = media.playback.get("details", {})
		var fps := str(details.get("container_fps", "0")).to_float() * playback_speed
		var settle := clampi(ceili(2000.0 / fps), 60, 2000) if fps > 0 else 500
		return (
			_surface_eof_ms >= 0
			and Time.get_ticks_msec() - _surface_eof_ms >= settle
			and not _surface_context.is_empty()
		)
	var end: Dictionary = media.playback
	var final_pair: Dictionary = media.last_pair
	var target: Variant = end.get("eof_source_ticket")
	if (
		not end.get("eof_source_resolved", false)
		or not end.get("eof_pair_post_draw", false)
		or not target is Dictionary
		or final_pair.is_empty()
	):
		return false
	return (
		int(end.get("eof_presented_slot", 0)) == int(final_pair.get("slot_token", -1))
		and int(target.source_epoch) == int(final_pair.get("source_epoch", -1))
		and int(target.frame_id) == int(final_pair.get("frame_id", -1))
		and int(target.pts_us) == int(final_pair.get("pts_us", -1))
		and final_pair.get("contract_version") == 2
	)


func _can_loop() -> bool:
	return loop_enabled and completed_presentation()


func _process(_delta: float) -> void:
	if (
		is_instance_valid(_focus_probe.viewport)
		and (
			not requested_play
			or media.state != "playing"
			or not panel.visible
			or _waiting_first
			or not _pending_revision.is_empty()
		)
	):
		suspend_focus()
	if _fallback_pending and layer_controller and layer_controller.runtime_running():
		_fallback_pending = false
		request_shader_fallback()
	autofocus.settle(_delta, Time.get_ticks_msec())
	_apply_stereo_focus()
	_maybe_focus()
	if subtitle_follow_view and view_camera and panel and geometry != Geometry.Geometry.FLAT:
		subtitle_follow.tick(panel.global_basis.inverse() * -view_camera.global_basis.z, _delta)
	server_playback.poll(self)
	if _sync_pending and PlatformMethods.supports(platform, "set_mpv_sync"):
		_sync_pending = not platform.set_mpv_sync(
			media.session_id, subtitle_delay_ms, audio_delay_ms
		)
	if (
		not _pending_external_uri.is_empty()
		and not _subtitle_loading
		and media.state in ["ready", "playing", "paused"]
	):
		if (
			PlatformMethods.supports(platform, "add_mpv_subtitle")
			and platform.add_mpv_subtitle(media.session_id, _pending_external_uri)
		):
			_subtitle_requested_uri = _pending_external_uri
			_subtitle_import_floor = int(
				media.playback.get("details", {}).get("subtitle_import_command", 0)
			)
			_pending_external_uri = ""
			_subtitle_loading = true
	if _audio_pending:
		_apply_audio_track(audio_track_id)
	elif (
		not _track_choices.has("audio")
		and prefer_clone_voice
		and not _clone_applied
		and clone_voice_track() > 0
	):
		_clone_applied = _apply_audio_track(clone_voice_track())
	if panel and geometry != Geometry.Geometry.FLAT:
		_center_on_view()
	if not _pending_revision.is_empty():
		_try_revision()
	_present_pending()
	_maybe_detect_stereo()
	_maybe_capture_thumbnail()
	_poll_subtitles()
	if layer_controller:
		layer_controller.tick(self)
	_sync_subtitle_surface()
	if _can_loop():
		seek_absolute(0)


func _exit_tree() -> void:
	if layer_controller:
		layer_controller.shutdown(self)
	_focus_probe.cancel()
	if _focus_thread:
		_focus_thread.wait_to_finish()
		_focus_thread = null
	if _focus_binding:
		_focus_binding.unbind()
	if not _focus_pin.is_empty() and platform:
		platform.release_mpv_pair_pin(int(_focus_pin.session_id), int(_focus_pin.slot_token))
		_focus_pin = {}
	if _stereo_thread:
		_stereo_thread.wait_to_finish()
		_stereo_thread = null
	if _stereo_capture_binding:
		_stereo_capture_binding.unbind()
	if not _stereo_pin.is_empty() and platform:
		platform.release_mpv_pair_pin(int(_stereo_pin.session_id), int(_stereo_pin.slot_token))
	close_video()
	if is_instance_valid(caption) and caption.get_parent() != self:
		caption.queue_free()


func waiting_for_first_frame() -> bool:
	return _waiting_first


func test_place_caption() -> void:
	_place_caption()


func test_set_waiting_for_frame(pending: bool) -> void:
	_waiting_first = pending


func test_step(delta: float) -> void:
	_process(delta)
