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
const PixelProbe := preload("res://scripts/mpv_pixel_probe.gd")
const SubtitleState := preload("res://scripts/mpv_subtitle_state.gd")
const BitmapSubtitles := preload("res://scripts/bitmap_subtitles.gd")
var bitmap_subtitles := BitmapSubtitles.new()
const ModeMemory := preload("res://scripts/file_mode_memory.gd")
const StereoView := preload("res://scripts/stereo_view.gd")
var viewing_eye := 0 # 0 binocular; 1/2 duplicate the logical left/right view after eye swap.
var stereo_horizontal := 0.0
var stereo_vertical := 0.0
var _stereo_view_dirty := false
const RecentFiles := preload("res://scripts/recent_files.gd")
const BookmarkStore := preload("res://scripts/bookmark_store.gd")
var bookmark_store := BookmarkStore.new()
var _bookmark_metadata: Dictionary = {}
var _bookmark_media_id := ""
var _bookmark_scope_sequence := 0
var _bookmark_cache_revision := -1
var _bookmark_rows: Array = []
var bookmark_last_added: Dictionary = {}
const Naming := preload("res://scripts/media_naming.gd")
const AUTOMATIC_PROFILE := "320x320"
const PROFILES := ["320x320", "384x216", "512x288", "384x384", "512x512", "256x144", "256x256"]

var media := State.new()
var _spatial_video := false # Source type survives seek/effect session generations.
var control := PlaybackControl.new()
var platform: Object
var alpha_encoding := 1
var alpha_enabled := false
var alpha_requested := false
## Realtime 2D->3D: a depth model drives per-eye parallax on mono sources (never with Alpha or SBS).
var depth_requested := false
var auto_depth := false # Global user choice, independent of remembered per-file projection.
var depth_enabled := false
const DEPTH_STRENGTHS := [0.5, 1.0, 1.5, 2.0]
const DepthStrength := preload("res://scripts/depth_strength.gd")
## Eye-width fraction of the full parallax at strength 1 (PTMediaServer), and the near value kept on
## the screen plane (nearer content comes out of the screen).
const DEPTH_SHIFT := 0.035
const DEPTH_CONVERGENCE := 0.35
var _depth_view_sent := ""
var depth_strength := 1.0
## Pick the clone-voice track (an extra M4A beside the video) whenever a video has one.
var prefer_clone_voice := false
## The file is an alpha-packed fisheye output (its name says so): the mask is in the frame and
## the Alpha switch shows it instead of running RVM.
var packed_file := false
var packed_alpha := false
var reclining_mode := false
## What the file name left open; filled from the first frame's shape, then cleared.
var _layout_pending: Variant = null
var _layout_basename := ""
var _rvm_alpha := false # the bound pair carries an inferred Alpha
var _clone_applied := false
var loop_enabled := false
var requested_play := true
signal audio_preferences_changed(volume: float, muted: bool)
const TrackPreference := preload("res://scripts/track_preference.gd")
var _track_choices := {}
var _tracks_pending := {}
var audio_track_id := -1
var audio_volume := 100.0
var audio_muted := false
var subtitle_delay_ms := 0
var audio_delay_ms := 0
var external_subtitle_uri := ""
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
## Text subtitles: on the flat screen near its lower edge; in immersive modes floating at
## a video-local projection with stereo disparity controlled by [subtitle_distance].
var playback_speed := 1.0
var subtitle_size := 1.0:
	set(value): subtitle_size = clampf(value, 0.5, 2.0) if is_finite(value) else 1.0
var subtitle_flat_position := 0.0:
	set(value): subtitle_flat_position = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
var _subtitle_surface: MeshInstance3D
var _subtitle_material: ShaderMaterial
var caption: Label3D
const ColorGrade := preload("res://scripts/color_grade.gd")
var color_grade := ColorGrade.new()
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
const CAPTION_DROP := 0.244 # radians below the line of sight (14 degrees)
var _subtitle_poll_ms := 0
var _subtitle_received_ms := 0
var mode_memory := ModeMemory.new()
var _remember_file := false
var recent_files := RecentFiles.new()
## Settings: when off, nothing new is recorded and videos start from the beginning.
var history_enabled := true
var _history_started := false
var _file_permission_persisted := false
var _history_save_ms := 0
var _access_request := 0
var _access_pending: Dictionary = {}
var _audio_pending := false
var local_uri := ""
var display_name := ""
var picker_error := ""
var _picker_request := 0
var profile := AUTOMATIC_PROFILE # ROI default: one square input for full-eye and zoom windows
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
var _seek_trace: Array[Dictionary] = []
var _open_trace: Array[Dictionary] = []
var _debug_seek_delay_until_ms := 0
var _debug_request := 0
var _debug_commands: Array = []
var _debug_pairs: Array = []
var _debug_status: Dictionary = {}
var _debug_pixels: Dictionary = {}
var _debug_benchmark := false
var _debug_next_report_us := 0
var _pixel_request := 0
var _pixel_request_key := ""
var _pixel_busy := false

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
		if platform.has_signal("local_subtitle_selected"): platform.connect("local_subtitle_selected", _on_subtitle_selected)
		if platform.has_signal("mpv_subtitle_import"): platform.connect("mpv_subtitle_import", _on_subtitle_import)
		platform.connect("local_video_access", _on_local_access)
		platform.connect("mpv_pair_available", _on_pair)
		platform.connect("mpv_state", _on_state)
		platform.connect("mpv_error", _on_error)
		platform.connect("mpv_detach", _on_detach)
		platform.connect("mpv_released", _on_released)
		platform.connect("mpv_debug_command", _on_debug_command)
		platform.connect("mpv_pixel_mask", _on_pixel_mask)
		platform.connect("mpv_frozen_pair", _on_frozen_pair)
	_apply_geometry()

func ai_available() -> bool:
	return false

## First usable displayed source frame, for every stable library URI. No second video decoder.
var _thumb_after_ms := -1          # media position to try; -1: already cached/not wanted
var _thumb_tries := 0

static func _thumbnail_source(uri: String) -> bool:
	return not ModeMemory.key_for(uri).is_empty()

func _maybe_capture_thumbnail() -> void:
	if _debug_benchmark or _thumb_after_ms < 0 or _thumbnail_busy or _pixel_busy or _waiting_first or not _pending_revision.is_empty() \
		or media.state not in ["playing", "paused", "ended"] or not _binding.material or media.last_pair.is_empty():
		return
	if int(media.last_pair.get("pts_us", 0)) / 1000 < _thumb_after_ms:
		return
	var uri := local_uri
	var sequence := _thumbnail_sequence
	var pair := media.last_pair.duplicate(true)
	if not platform.pin_mpv_pair(int(pair.session_id), int(pair.slot_token)): return
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
	var eye := Vector2(float(pair.width) * (2.0 if false else 1.0) * (0.5 if stereo and not tb else 1.0), float(pair.height) * (0.5 if tb else 1.0))
	var scale: Array = pair.get("color_uv_scale", [1.0, 1.0])
	var image: Image = await Thumbnails.capture(self, binding.color_texture(), str(binding.ticket.get("color_target", "")) == "external",
		stereo, Thumbnails.crop_for(geometry, eye), Vector2(float(scale[0]), float(scale[1])), tb)
	binding.unbind()
	platform.release_mpv_pair_pin(int(pair.session_id), int(pair.slot_token))
	_thumbnail_busy = false
	if sequence != _thumbnail_sequence or uri != local_uri: return
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
	_thumbnail_result = {"state": "stored" if stored else "store_failed", "pts_us": int(pair.pts_us),
		"width": image.get_width(), "height": image.get_height(), "source_epoch": int(pair.source_epoch)}
	if stored: thumbnail_ready.emit(uri)
	_write_debug_report()

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
	if not result is Dictionary or _picker_request <= 0 or result.get("picker_request", -1) != _picker_request:
		return
	if result.get("state") == "selected":
		_picker_request = 0
		requested_play = true
		var uri := str(result.uri)
		if open_local(uri, str(result.get("display_name", "Local video")), _resume(uri), true, false, "", {"basename": result.get("display_name", "")}):
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
func open_library(uri: String, title: String, metadata: Dictionary = {}, from_start: bool = false) -> bool:
	var cover := str(metadata.get("cover", recent_files.lookup(uri).get("cover", "")))
	var opened := false
	if from_start:
		requested_play = true
		if uri.begins_with("content://") and not recent_files.lookup(uri).is_empty(): opened = open_recent(uri, true, metadata)
		else: opened = open_local(uri, title, 0, true, false, str(metadata.get("basename", "")), metadata)
	elif uri.begins_with("medialib://") and not metadata.is_empty():
		requested_play = true
		var start: int = int(metadata.get("start_ms", -1))
		opened = open_local(uri, title, _resume(uri) if start < 0 else start, true, false, str(metadata.get("basename", "")), metadata)
	elif not recent_files.lookup(uri).is_empty():
		opened = open_recent(uri, false, metadata)
	else:
		requested_play = true
		opened = open_local(uri, title, 0, true, false, "", metadata)
	if opened and RecentFiles.valid_cover(cover): _library_cover = cover
	return opened

func open_recent(uri: String, from_start: bool = false, metadata: Dictionary = {}) -> bool:
	var entry := recent_files.lookup(uri)
	if entry.is_empty() or not platform:
		return false
	if not uri.begins_with("content://"):
		requested_play = true
		return open_local(uri, str(entry.title), 0 if from_start else _resume(uri), true, false, "", metadata)
	cancel_pending_open()
	_access_pending = {"uri": uri, "title": str(entry.title), "start_ms": 0 if from_start else _resume(uri), "metadata": metadata.duplicate(true)}
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
		picker_error = str(result.get("error", "File unavailable; select it again"))
		changed.emit()
		return
	requested_play = true
	var metadata: Dictionary = pending.get("metadata", {}).duplicate(true)
	if not str(result.get("display_name", "")).is_empty(): metadata.basename = result.display_name
	if open_local(str(pending.uri), str(pending.title), int(pending.start_ms), true, false, "", metadata):
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

func open_local(uri: String, title: String, start_ms: int = 0, restore_mode: bool = true, alpha: bool = false, basename: String = "", metadata: Dictionary = {}) -> bool:
	_open_trace = [{"stage": "requested", "time_ms": Time.get_ticks_msec(), "start_ms": start_ms}]
	if not platform or not platform.mpv_supported():
		picker_error = "MPV playback backend unavailable"
		changed.emit()
		return false
	cancel_pending_open()
	close_video()
	# Alpha-packed and Alpha-wanted files say so in their names (PTMediaServer / DeoVR markers).
	_layout_basename = basename if not basename.is_empty() else (title if not title.is_empty() else uri.uri_decode().get_file())
	var stated := Naming.from_name(_layout_basename)
	if uri.begins_with("medialib://"): stated.erase("alpha")
	packed_file = bool(stated.get("packed", false))
	packed_alpha = packed_file
	_layout_pending = null
	var saved_sync := mode_memory.lookup(uri) if restore_mode else {}
	_track_choices = saved_sync.get("track_choices", {}).duplicate(true)
	_tracks_pending = _track_choices.duplicate(true)
	subtitle_delay_ms = int(saved_sync.get("subtitle_delay_ms", 0))
	audio_delay_ms = int(saved_sync.get("audio_delay_ms", 0))
	external_subtitle_uri = str(saved_sync.get("external_subtitle_uri", ""))
	_pending_external_uri = external_subtitle_uri
	if restore_mode:
		# Ignore legacy per-file model choices; everyday playback uses one tested ROI profile.
		profile = AUTOMATIC_PROFILE
		var saved := mode_memory.lookup(uri)
		if not saved.is_empty():
			# The user's own choice for this file wins over its name and shape.
			geometry = int(saved.geometry)
			stereo_sbs = bool(saved.stereo_sbs)
			top_bottom = stereo_sbs and bool(saved.get("top_bottom", false))
			stereo_half = stereo_sbs and bool(saved.get("stereo_half", false))
			fisheye_fov = int(saved.get("fisheye_fov", 180)) if int(saved.get("fisheye_fov", 180)) in FISHEYE_FOVS else 180
			swap_eyes = bool(saved.swap_eyes)
			viewing_eye = int(saved.get("viewing_eye", 0))
			stereo_horizontal = float(saved.get("stereo_horizontal", 0.0))
			stereo_vertical = float(saved.get("stereo_vertical", 0.0))
			depth_requested = bool(saved.get("depth_requested", false)) and not stereo_sbs
		elif not mode_lock.is_empty() and not stated.has("geometry") and not stated.has("stereo"):
			geometry = int(mode_lock.geometry)
			stereo_sbs = int(mode_lock.layout) != 0
			top_bottom = int(mode_lock.layout) in [2, 4]
			stereo_half = int(mode_lock.layout) in [3, 4]
			fisheye_fov = int(mode_lock.fisheye_fov)
			swap_eyes = false
			depth_requested = bool(mode_lock.depth) and not stereo_sbs
		else:
			depth_requested = false
			geometry = int(stated.get("geometry", Geometry.Geometry.FLAT))
			stereo_sbs = bool(stated.get("stereo", geometry in [Geometry.Geometry.HALF_EQUIRECT, Geometry.Geometry.FISHEYE]))
			top_bottom = stereo_sbs and bool(stated.get("top_bottom", false))
			stereo_half = stereo_sbs and bool(stated.get("stereo_half", false))
			fisheye_fov = int(stated.get("fisheye_fov", 180))
			swap_eyes = bool(stated.get("swap", false))
			if not stated.has("geometry") or not stated.has("stereo") or (geometry in [Geometry.Geometry.FLAT, Geometry.Geometry.FISHEYE] and not stated.has("stereo_half")):
				_layout_pending = stated
	# Videos start as normal playback unless the name asks for live Alpha.
	alpha_requested = ai_available() and (alpha or (restore_mode and bool(stated.get("alpha", false)) and not packed_file))
	_thumb_tries = 0
	_thumbnail_result = {}
	_thumb_after_ms = -1
	if not _debug_benchmark and _thumbnail_source(uri) and Thumbnails.texture(uri) == null:
		_thumb_after_ms = 0
	local_uri = uri
	display_name = title
	_bookmark_metadata = metadata.duplicate(true)
	if not basename.is_empty(): _bookmark_metadata.basename = basename
	if str(_bookmark_metadata.get("basename", "")).is_empty():
		if uri.begins_with("file://") or uri.begins_with("smb://") or uri.begins_with("cloud://"):
			_bookmark_metadata.basename = uri.uri_decode().get_file()
		elif uri.begins_with("content://"):
			_bookmark_metadata.basename = title
	if uri.begins_with("file://"):
		var source := FileAccess.open(uri.trim_prefix("file://").uri_decode(), FileAccess.READ)
		if source: _bookmark_metadata.size = source.get_length()
	_bookmark_resolve()
	depth_requested = ai_available() and auto_depth and geometry == Geometry.Geometry.FLAT and not stereo_sbs and not alpha_requested
	_last_seek_mode = SeekPolicy.normalize(seek_mode)
	var id: int = platform.open_mpv_video(uri, maxi(start_ms, 0), stereo_sbs, profile, alpha_requested, true, depth_requested,
		stereo_sbs and top_bottom, SeekPolicy.normalize(seek_mode) == SeekPolicy.EXACT)
	media.begin(id)
	playback_speed = 1.0
	screen_rotation = 0.0
	if PlatformMethods.supports(platform, "set_mpv_speed"): platform.set_mpv_speed(id, playback_speed)
	_open_trace.append({"stage": "dispatched", "time_ms": Time.get_ticks_msec(), "session_id": id})
	_remember_file = restore_mode and id > 0
	_history_started = false
	_file_permission_persisted = false
	audio_track_id = -1
	_clone_applied = false
	subtitles.select(0)
	subtitles.clear(true)
	bitmap_subtitles.clear(material)
	if _subtitle_surface: _subtitle_surface.visible = false
	reset_view() # every video starts straight ahead at its natural size
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
	_rvm_alpha = false
	depth_enabled = false
	panel.visible = false
	if caption:
		caption.visible = false

func close_video() -> void:
	if _subtitle_pick > 0 and PlatformMethods.supports(platform, "cancel_local_subtitle_pick"):
		platform.cancel_local_subtitle_pick(_subtitle_pick)
	_subtitle_pick = 0; _subtitle_pick_session = 0
	_pending_external_uri = ""; _subtitle_import_uri = ""; _subtitle_import_command = 0; _subtitle_loading = false
	_sync_pending = false
	commit_stereo_view()
	viewing_eye = 0
	stereo_horizontal = 0.0
	stereo_vertical = 0.0
	_apply_stereo_view()
	_spatial_video = false
	media.format.erase("spatial_video")
	_bookmark_scope_sequence += 1
	_bookmark_media_id = ""
	_bookmark_metadata.clear()
	_bookmark_rows.clear()
	_bookmark_cache_revision = -1
	_thumbnail_sequence += 1
	_library_cover = ""
	_record_history(true)
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
	_debug_seek_delay_until_ms = 0
	_waiting_first = false
	_audio_pending = false
	control.close()
	_remember_file = false
	_track_choices.clear(); _tracks_pending.clear()
	local_uri = ""
	display_name = ""
	alpha_requested = false
	depth_requested = false
	set_corner_hover(-1)
	subtitles.clear(true)
	bitmap_subtitles.clear(material)
	if _subtitle_surface: _subtitle_surface.visible = false
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
	if not history_enabled or not _remember_file or not media.accepts(media.session_id) or media.last_pair.is_empty() \
		or not preload("res://scripts/pair_texture_binding.gd").timing_valid(media.last_pair) or not panel.visible:
		return
	var pair: Dictionary = media.last_pair
	if int(pair.get("session_id", 0)) != media.session_id or int(pair.get("generation", 0)) != media.generation:
		return
	if not _history_started:
		if not recent_files.opened(local_uri, display_name, _file_permission_persisted):
			return
		_history_started = true
		recent_files.set_cover(local_uri, _library_cover)
		force = true
	var now := Time.get_ticks_msec()
	if not force and now < _history_save_ms:
		return
	var position_ms := clampi(int(float(pair.pts_us) / 1000.0), 0, 2147483647)
	recent_files.progress(local_uri, position_ms, control.duration_ms, media.state == "ended")
	_history_save_ms = now + 5000
	if not recent_files.save():
		Log.record("recent_file_save_failed", {"error": recent_files.last_error})

func _request_revision(position_ms: int = -1, mode: String = "") -> void:
	if not ai_available():
		alpha_requested = false
		depth_requested = false
	if not platform or not media.accepts(media.session_id):
		return
	_pending_revision = {"stereo": stereo_sbs, "alpha": alpha_requested, "profile": profile, "position_ms": position_ms,
		"depth": depth_requested and not alpha_requested and not stereo_sbs, "top_bottom": stereo_sbs and top_bottom,
		"seek_mode": SeekPolicy.normalize(seek_mode if mode.is_empty() else mode)}
	platform.set_mpv_playing(media.session_id, false)
	_waiting_first = true
	subtitles.clear()
	bitmap_subtitles.clear(material)
	if _subtitle_surface: _subtitle_surface.visible = false
	if caption:
		caption.visible = false
	if position_ms >= 0: _seek_event("requested")
	_try_revision()

func _start_seek_freeze() -> bool:
	# Capture exactly once before seek/flush; rapid requests share this frame.
	if _freeze_request == 0 and not _binding.ticket.is_empty() and not _is_frozen():
		var capable := Engine.has_singleton("QuestPlayer") or platform.has_method("freeze_mpv_pair")
		if capable:
			_freeze_sequence += 1
			_freeze_request = _freeze_sequence
			if not platform.freeze_mpv_pair(media.session_id, int(_binding.ticket.slot_token), _freeze_request):
				_abort_frozen_seek("Frame capture request rejected")
			return true
	return false

func _is_frozen() -> bool:
	return int(_binding.ticket.get("frozen_frame_id", 0)) > 0

func _seek_event(stage: String) -> void:
	_seek_trace.append({"stage": stage, "time_ms": Time.get_ticks_msec(), "visible": panel != null and panel.visible,
		"frozen": _is_frozen(), "capture_pending": _freeze_request > 0,
		"session_id": media.session_id, "target_ms": control.target_ms,
		"displayed_pts_us": int(_binding.ticket.get("pts_us", -1)),
		"freeze_copy_us": int(_binding.ticket.get("freeze_copy_us", 0))})
	if _seek_trace.size() > 64: _seek_trace.pop_front()
	_write_debug_report()

func _abort_frozen_seek(reason: String) -> void:
	_freeze_request = 0
	_pending_revision = {}
	_waiting_first = false
	control.reject()
	picker_error = reason
	platform.set_mpv_playing(media.session_id, requested_play)
	_seek_event("capture_failed")
	changed.emit()

func _on_frozen_pair(id: int, payload: String) -> void:
	var report: Variant = JSON.parse_string(payload)
	if not report is Dictionary: return
	var pair: Dictionary = report.get("pair", {})
	if id != media.session_id or int(report.get("request_id", 0)) != _freeze_request \
			or _pending_revision.is_empty() or int(_pending_revision.position_ms) < 0:
		if int(pair.get("frozen_frame_id", 0)) > 0:
			platform.release_mpv_frozen_frame(int(pair.frozen_frame_id))
		if int(report.get("request_id", 0)) == _freeze_request: _freeze_request = 0
		return
	if report.get("state") != "ready":
		_abort_frozen_seek(str(report.get("error", "Frame capture failed")))
		return
	# Preserve visibility, shader parameters and effect state during replacement.
	var previous := _binding.unbind()
	if not _binding.bind(material, pair):
		_binding.bind(material, previous)
		platform.release_mpv_frozen_frame(int(pair.frozen_frame_id))
		_abort_frozen_seek("Frozen video frame could not be bound")
		return
	platform.detach_mpv_pair(int(previous.session_id), int(previous.slot_token))
	_freeze_request = 0
	_seek_event("frozen")
	_try_revision()

func _try_revision() -> void:
	if _pending_revision.is_empty() or _freeze_request > 0 or _pixel_busy or _thumbnail_busy:
		return
	if int(_pending_revision.position_ms) >= 0 and _start_seek_freeze(): return
	if int(_pending_revision.position_ms) >= 0 and Time.get_ticks_msec() < _debug_seek_delay_until_ms:
		return
	var request := _pending_revision
	var id: int = platform.revise_mpv_video(media.session_id, request.stereo, request.alpha, request.profile, request.position_ms,
		request.depth, request.top_bottom, request.seek_mode == SeekPolicy.EXACT)
	if id <= 0:
		return
	if int(request.position_ms) < 0 or not _is_frozen(): _unbind()
	_pending_pair = {}
	_pending_revision = {}
	var held_format := media.format.duplicate()
	media.begin(id)
	if _is_frozen(): media.format = held_format
	_tracks_pending = _track_choices.duplicate(true)
	platform.set_mpv_playing(id, false)
	if int(request.position_ms) >= 0:
		_last_seek_mode = request.seek_mode
		control.take_pending()
		_debug_seek_delay_until_ms = 0
		_seek_event("seek_started")
	changed.emit()

## Alpha as the user sees it: live RVM, or the mask packed in this file.
func alpha_wanted() -> bool:
	return alpha_requested or (packed_file and packed_alpha)

## The URI/effect preferences survive close for history; they are not playback state.
func has_active_presentation() -> bool:
	if local_uri.is_empty() or not media.accepts(media.session_id): return false
	return media.state != "ended" or (loop_enabled and requested_play) \
		or _waiting_first or not _pending_revision.is_empty()

func set_alpha(enabled: bool) -> bool:
	# Precomputed alpha is media data; there is no live matting pipeline.
	if not packed_file: return false
	packed_alpha = enabled
	_apply_packed(); changed.emit()
	return true

## 2D->3D for mono sources; switching it on ends Alpha.
func set_depth(enabled: bool) -> bool:
	auto_depth = false; depth_requested = false; depth_enabled = false
	return not enabled

## The bridge renders the stereo pair: tell it the strength once per session and change.
func _send_depth_view() -> void:
	if not depth_enabled or media.session_id <= 0 or not platform:
		return
	# JNISingleton.has_method() cannot see Java plugin methods. Only inspect host test doubles.
	if not Engine.has_singleton("QuestPlayer") and not platform.has_method("set_mpv_depth_view"): return
	var strength := depth_strength if depth_requested else 0.0
	var key := "%d:%f" % [media.session_id, strength]
	if key != _depth_view_sent and platform.set_mpv_depth_view(media.session_id,
		DEPTH_SHIFT * strength, DEPTH_CONVERGENCE):
		_depth_view_sent = key

func depth_ready() -> bool:
	return depth_enabled and not media.last_pair.is_empty() and media.last_pair.get("depth_ran", false)

## Depth compiled for this device: 3D starts at once (otherwise frames show flat until it is).
func depth_model_ready() -> bool:
	return false

func cycle_depth_strength() -> void:
	pass

func set_depth_strength(value: float) -> bool:
	return false

## The extra track titled "Clone voice" (see SidecarAudio.kt); 0 when this video has none.
func clone_voice_track() -> int:
	for track in media.playback.get("details", {}).get("audio_tracks", []):
		if track is Dictionary and bool(track.get("external", false)) and str(track.get("title", "")) == "Clone voice":
			return int(track.get("id", 0))
	return 0

func clone_voice_active() -> bool:
	var clone := clone_voice_track()
	return clone > 0 and str(media.playback.get("details", {}).get("audio_track_id", "")) == str(clone)

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
	return alpha_enabled and not media.last_pair.is_empty() and media.last_pair.get("inference_ran", false)

func set_playback_speed(value: float) -> bool:
	if not is_finite(value) or value < 0.25 or value > 3.0 or not media.accepts(media.session_id): return false
	if not PlatformMethods.supports(platform, "set_mpv_speed") or not platform.set_mpv_speed(media.session_id, value): return false
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
		platform.set_mpv_playing(media.session_id, requested_play and not _waiting_first)
	changed.emit()

func set_sync_delay(key: String, value: float) -> bool:
	if key not in ["subtitle_delay_ms", "audio_delay_ms"] or not is_finite(value) or value < -10000 or value > 10000: return false
	var sub := roundi(value) if key == "subtitle_delay_ms" else subtitle_delay_ms
	var audio := roundi(value) if key == "audio_delay_ms" else audio_delay_ms
	if not PlatformMethods.supports(platform, "set_mpv_sync") or not media.accepts(media.session_id): return false
	if not platform.set_mpv_sync(media.session_id, sub, audio): return false
	subtitle_delay_ms = sub; audio_delay_ms = audio
	subtitles.clear(); bitmap_subtitles.clear(material)
	changed.emit()
	return true

func commit_sync() -> void:
	_remember_mode()

func pick_external_subtitle() -> void:
	if _subtitle_pick > 0 or _subtitle_loading or not media.accepts(media.session_id): return
	if not PlatformMethods.supports(platform, "pick_local_subtitle"):
		picker_error = "Subtitle picker unavailable"; changed.emit(); return
	_subtitle_pick_session = media.session_id
	_subtitle_pick = platform.pick_local_subtitle()

func _on_subtitle_selected(payload: String) -> void:
	var result: Variant = JSON.parse_string(payload)
	if not result is Dictionary or _subtitle_pick <= 0 or int(result.get("picker_request", 0)) != _subtitle_pick: return
	if _subtitle_pick_session != media.session_id:
		_subtitle_pick = 0; changed.emit(); return
	if result.get("state") in ["cancelled", "error"]:
		_subtitle_pick = 0
		if result.state == "error": picker_error = "Unable to read subtitle. Select it again."
	elif result.get("state") == "selected":
		_subtitle_pick = 0
		_pending_external_uri = str(result.get("uri", ""))
	changed.emit()

func _on_subtitle_import(id: int, payload: String) -> void:
	if id != media.session_id or not _subtitle_loading: return
	var result: Variant = JSON.parse_string(payload)
	if not result is Dictionary: return
	if result.get("state") == "queued":
		_subtitle_import_command = int(result.get("command", 0))
		_subtitle_import_uri = str(result.get("uri", ""))
		subtitles.select(-1)
	elif result.get("state") == "error":
		_subtitle_loading = false
		picker_error = "Unable to load subtitle. Choose an SRT, ASS, SSA or VTT file."
	changed.emit()

func forget_external_subtitle() -> void:
	if _subtitle_loading or _subtitle_pick > 0: return
	external_subtitle_uri = ""; _pending_external_uri = ""
	if picker_error.contains("subtitle"): picker_error = ""
	_remember_mode(); changed.emit()

func restore_audio_preferences(volume: Variant, muted: Variant) -> void:
	audio_volume = clampf(float(volume), 0.0, 100.0) if (volume is float or volume is int) and is_finite(float(volume)) else 100.0
	audio_muted = muted if muted is bool else false

func set_audio_options(track_id: int, volume: float, muted: bool) -> bool:
	if track_id < -1 or not is_finite(volume) or volume < 0.0 or volume > 100.0 or not platform or not media.accepts(media.session_id):
		return false
	if not platform.set_mpv_audio(media.session_id, track_id, volume, muted):
		return false
	var sound_changed := audio_volume != volume or audio_muted != muted
	audio_track_id = track_id
	audio_volume = volume
	audio_muted = muted
	_audio_pending = false
	if sound_changed: audio_preferences_changed.emit(volume, muted)
	changed.emit()
	return true

## An explicit menu choice wins over automatic dubbing, including before the first frame.
func select_audio_track(track_id: int) -> bool:
	if not set_audio_options(track_id, audio_volume, audio_muted): return false
	_remember_track("audio", track_id)
	_clone_applied = true
	prefer_clone_voice = clone_voice_track() > 0 and track_id == clone_voice_track()
	return true

## Raising the volume unmutes (a muted slider shows 0, so a silent step up would look ignored);
## lowering keeps mute.
func change_volume(delta: float) -> bool:
	return set_audio_options(audio_track_id, clampf(audio_volume + delta, 0.0, 100.0), audio_muted and delta <= 0.0)

func toggle_mute() -> bool:
	return set_audio_options(audio_track_id, audio_volume, not audio_muted)

func _remember_track(kind: String, id: int) -> void:
	var tracks: Array = subtitle_tracks() if kind == "subtitle" else media.playback.get("details", {}).get("audio_tracks", [])
	var choice := TrackPreference.capture(id, tracks)
	if choice.is_empty(): return
	_track_choices[kind] = choice
	if kind == "subtitle" and (_subtitle_loading or not _pending_external_uri.is_empty()):
		_tracks_pending[kind] = choice.duplicate(true)
	else:
		_tracks_pending.erase(kind)
	_remember_mode()

func _restore_track_choices() -> void:
	if not media.accepts(media.session_id): return
	var details: Dictionary = media.playback.get("details", {})
	for kind in _tracks_pending.keys():
		if kind == "subtitle" and (_subtitle_loading or not _pending_external_uri.is_empty()): continue
		if not details.has(kind + "_tracks"): continue
		var tracks: Array = subtitle_tracks() if kind == "subtitle" else details.audio_tracks
		var id: Variant = TrackPreference.resolve(_tracks_pending[kind], tracks)
		if id == null: continue
		var accepted := set_subtitle_track(int(id), false) if kind == "subtitle" else set_audio_options(int(id), audio_volume, audio_muted)
		if accepted:
			_tracks_pending.erase(kind)
			if kind == "audio": _clone_applied = true

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
	_bookmark_media_id = bookmark_store.resolve(local_uri, str(_bookmark_metadata.get("basename", "")), _bookmark_metadata.get("size", -1))
	_bookmark_cache_revision = -1

func bookmark_seekable() -> bool:
	var details: Dictionary = media.playback.get("details", {})
	return media.accepts(media.session_id) and control.duration_ms > 0 and details.get("seekable", "") == "yes" \
		and details.get("partially_seekable", "no") != "yes" and media.state not in ["failed", "closed"]

func bookmark_scope() -> String:
	return str(_bookmark_scope_sequence) + "|" + _bookmark_media_id

func bookmark_snapshot() -> Dictionary:
	if not bookmark_seekable() or _waiting_first or control.pending or control.in_flight > 0 \
		or not _pending_revision.is_empty() or _is_frozen() or not panel or not panel.visible: return {}
	var pair: Dictionary = _binding.ticket
	if not preload("res://scripts/pair_texture_binding.gd").timing_valid(pair) or int(pair.get("session_id", -1)) != media.session_id \
		or int(pair.get("generation", -1)) != media.generation or int(pair.get("pts_us", -1)) < 0: return {}
	var time := int(pair.pts_us) / 1000
	if time >= control.duration_ms: return {}
	return {"scope": bookmark_scope(), "position_ms": time}

func bookmarks_snapshot() -> Dictionary:
	if _bookmark_cache_revision != bookmark_store.revision:
		_bookmark_rows = bookmark_store.list_markers(_bookmark_media_id)
		_bookmark_cache_revision = bookmark_store.revision
	return {"bookmark_scope": bookmark_scope(), "bookmarks": _bookmark_rows,
		"bookmark_revision": bookmark_store.revision, "bookmark_undo": bookmark_store.can_undo(),
		"bookmark_ready": not bookmark_snapshot().is_empty(), "bookmark_seekable": bookmark_seekable(),
		"seek_mode": SeekPolicy.normalize(seek_mode), "bookmark_seek_mode": SeekPolicy.bookmark_override(bookmark_seek_mode),
		"bookmark_effective_seek_mode": SeekPolicy.effective(seek_mode, bookmark_seek_mode)}

func bookmark_action(operation: String, marker_id: String, scope: String) -> String:
	if scope != bookmark_scope(): return ""
	match operation:
		"add":
			var snapshot := bookmark_snapshot()
			if snapshot.is_empty(): return ""
			var item := bookmark_store.add(local_uri, str(_bookmark_metadata.get("basename", "")), _bookmark_metadata.get("size", -1), int(snapshot.position_ms))
			bookmark_last_added = item
			return "Bookmark added" if not item.is_empty() else bookmark_store.last_error
		"delete":
			return "Bookmark deleted" if bookmark_store.remove(_bookmark_media_id, marker_id) else "Bookmark save failed"
		"undo":
			return "Bookmark restored" if bookmark_store.restore() else "Bookmark save failed"
		"seek":
			if not bookmark_seekable(): return ""
			for marker in bookmark_store.list_markers(_bookmark_media_id):
				if marker.id == marker_id and int(marker.position_ms) < control.duration_ms:
					return "" if seek_absolute(int(marker.position_ms), SeekPolicy.effective(seek_mode, bookmark_seek_mode)) else "Bookmark jump failed"
	return ""

func set_subtitle_track(track_id: int, remember: bool = true) -> bool:
	if track_id < -1 or not platform or not media.accepts(media.session_id):
		return false
	if track_id > 0 and not subtitle_tracks().any(func(t): return int(t.id) == track_id):
		return false
	if not platform.set_mpv_subtitle(media.session_id, track_id):
		return false
	subtitles.select(track_id)
	if remember: _remember_track("subtitle", track_id)
	bitmap_subtitles.clear(material)
	if _subtitle_surface: _subtitle_surface.visible = false
	if caption:
		caption.visible = false
	if projected_subtitles:
		projected_subtitles.clear(material)
	changed.emit()
	return true

func subtitle_tracks() -> Array[Dictionary]:
	var tracks: Array[Dictionary] = []
	var details: Dictionary = media.playback.get("details", {})
	for track in details.get("subtitle_tracks", []):
		if track is Dictionary and int(track.get("id", 0)) > 0 and SubtitleState.supported_codec(str(track.get("codec", "")),
			geometry == Geometry.Geometry.FLAT, bool(details.get("pgs_supported", false))):
			tracks.append(track)
	return tracks

func cycle_subtitle_track(direction: int = 1) -> bool:
	var choices: Array[int] = [0]
	for track in subtitle_tracks():
		choices.append(int(track.id))
	if choices.size() == 1:
		return false
	return set_subtitle_track(choices[posmod(choices.find(subtitles.requested_track) + direction, choices.size())])

func _poll_subtitles() -> void:
	if not caption:
		return
	var ready := platform != null and media.accepts(media.session_id) and not media.last_pair.is_empty() \
		and not _waiting_first and _pending_revision.is_empty() and panel.visible
	if not ready:
		caption.visible = false
		projected_subtitles.clear(material)
		bitmap_subtitles.clear(material)
		if _subtitle_surface: _subtitle_surface.visible = false
		return
	var now := Time.get_ticks_msec()
	if now >= _subtitle_poll_ms:
		_subtitle_poll_ms = now + 50
		var payload: String = platform.get_mpv_subtitles(media.session_id, subtitles.sequence)
		var snapshot: Variant = JSON.parse_string(payload) if not payload.is_empty() else null
		if snapshot is Dictionary and subtitles.observe(snapshot, media.session_id, media.last_pair):
			_subtitle_received_ms = now
	if now - _subtitle_received_ms > 1000:
		subtitles.clear()
	if geometry == Geometry.Geometry.FLAT and not subtitles.bitmap.is_empty():
		var handle := int(subtitles.cue.get("mpv_source_handle", 0))
		var pixels := PackedByteArray()
		if bitmap_subtitles.needs_pixels(subtitles.bitmap, handle):
			pixels = platform.get_mpv_subtitle_bitmap(media.session_id, int(subtitles.bitmap.version))
		bitmap_subtitles.apply(material, subtitles.bitmap, handle, pixels)
	else:
		bitmap_subtitles.clear(material)
		if _subtitle_surface: _subtitle_surface.visible = false
	caption.text = subtitles.text
	caption.visible = not subtitles.text.is_empty()
	if caption.visible:
		_place_caption()
	else:
		projected_subtitles.clear(material)
	_sync_subtitle_surface()

func _place_caption() -> void:
	caption.modulate = CaptionPalette.INK[CaptionPalette.index(subtitle_palette)]
	caption.outline_modulate = CaptionPalette.outline(subtitle_palette)
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
		var text_height := minf(_flat.size.y - 2 * margin, caption.get_aabb().size.y)
		var y := lerpf(-_flat.size.y * 0.5 + margin, _flat.size.y * 0.5 - margin - maxf(0.064 * subtitle_size * screen_scale, text_height), subtitle_flat_position)
		var anchor := pose * Vector3(0, y, 0.01)
		caption.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		caption.layers = 1
		projected_subtitles.clear(material)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		caption.global_transform = Transform3D(pose.basis, anchor)
		return
	# Anchor in the video's coordinates, like burned-in captions. Head pose never changes it.
	# Direction/recenter/zoom move captions with the video; roll is excluded by the independent surface.
	var anchor_basis := SubtitleDepth.anchor(subtitle_position, subtitle_direction == 1)
	caption.layers = 0 # The live text patch is drawn only by the video's shader.
	projected_subtitles.update_patch(caption, material, anchor_basis, subtitle_distance, ProjectedSubtitles.runtime_ipd(), subtitle_direction == 1, subtitle_size)

func seek_relative(delta_ms: int) -> bool:
	if not platform or not media.accepts(media.session_id):
		return false
	control.seek_relative(delta_ms)
	_request_revision(control.target_ms)
	return true

## A decoded source type, retained until the file is closed.
func is_spatial_video() -> bool:
	return _spatial_video

func mode_action_allowed(operation: String) -> bool:
	if not is_spatial_video(): return true
	return operation not in ["stereo", "projection", "lock_mode", "depth", "depth_strength"] \
		and not operation.begins_with("stereo_") and not operation.begins_with("projection_") \
		and not operation.begins_with("fov_")

## The current projection and layout as a lock.
func current_lock() -> Dictionary:
	return {"geometry": geometry, "layout": stereo_layout(), "depth": depth_requested and not stereo_sbs, "fisheye_fov": fisheye_fov}

## Locks the current mode, or unlocks when it is the locked one.
func toggle_mode_lock() -> void:
	if is_spatial_video(): return
	var current := current_lock()
	mode_lock = {} if mode_lock == current else current
	mode_lock_changed.emit(mode_lock.duplicate())
	changed.emit()

## A stored lock, checked; anything malformed leaves the player unlocked.
func load_mode_lock(value: Variant) -> void:
	mode_lock = {}
	if not value is Dictionary:
		return
	var numbers := ["geometry", "layout", "fisheye_fov"].all(func(k): return value.get(k) is int or value.get(k) is float)
	if not numbers or not value.get("depth") is bool or int(value.geometry) not in [0, 1, 2, 3] 		or int(value.layout) not in [0, 1, 2, 3, 4] or int(value.fisheye_fov) not in FISHEYE_FOVS:
		return
	mode_lock = {"geometry": int(value.geometry), "layout": int(value.layout), "depth": false,
		"fisheye_fov": int(value.fisheye_fov)}

func toggle_loop() -> void:
	loop_enabled = not loop_enabled
	changed.emit()

## 2D -> side by side -> top-bottom -> 2D.
func toggle_stereo() -> void:
	set_stereo_layout(0 if stereo_sbs and top_bottom else (2 if stereo_sbs else 1))

## 0 mono, 1 full SBS, 2 full TB, 3 half SBS, 4 half TB.
func set_stereo_layout(layout: int) -> void:
	if is_spatial_video(): return
	if layout < 0 or layout > 4 or layout == stereo_layout():
		return
	_unlock_mode()
	_layout_pending = null # A manual choice before the first frame survives detection.
	var repack := (layout != 0) != stereo_sbs or (layout in [2, 4]) != top_bottom
	stereo_sbs = layout != 0
	top_bottom = layout in [2, 4]
	stereo_half = layout in [3, 4]
	var old_depth := depth_requested
	if stereo_sbs:
		depth_requested = false
	elif ai_available() and auto_depth and geometry == Geometry.Geometry.FLAT:
		depth_requested = true
		alpha_requested = false
	_remember_mode()
	if repack or old_depth != depth_requested: _request_revision()
	_apply_geometry()
	changed.emit()

func stereo_layout() -> int:
	return 0 if not stereo_sbs else ((4 if top_bottom else 3) if stereo_half else (2 if top_bottom else 1))

func set_fisheye_fov(value: int) -> void:
	if is_spatial_video(): return
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
	if is_spatial_video(): return
	if value < 0 or value > 3:
		return
	if value != geometry: _unlock_mode()
	geometry = value
	if _layout_pending is Dictionary: _layout_pending.geometry = value
	# Fisheye is a projection, independent of mono/SBS/TB. Preserve the chosen eye layout.
	var stereo := stereo_sbs if geometry == Geometry.Geometry.FISHEYE else geometry == Geometry.Geometry.HALF_EQUIRECT
	var revise := false
	if geometry != Geometry.Geometry.FLAT and stereo != stereo_sbs:
		stereo_sbs = stereo
		revise = true
	# 2D -> 3D applies to the flat screen, Alpha to VR180 and fisheye: stop effects when switching
	# to an unsupported projection, where their persistent bar buttons are disabled.
	if geometry != Geometry.Geometry.FLAT and depth_requested:
		depth_requested = false
		revise = true
	if not stereo and alpha_requested:
		alpha_requested = false
		revise = true
	if geometry == Geometry.Geometry.FLAT and not stereo_sbs and ai_available() and auto_depth and not depth_requested:
		depth_requested = true
		revise = true
	if revise:
		_request_revision()
	_apply_geometry()
	_remember_mode()
	changed.emit()

func toggle_eye_order() -> bool:
	if not stereo_sbs:
		return false
	swap_eyes = not swap_eyes
	_apply_geometry()
	_remember_mode()
	changed.emit()
	return true

func set_viewing_eye(value: int) -> bool:
	if not stereo_sbs or value not in [0, 1, 2]: return false
	viewing_eye = value
	_apply_stereo_view()
	_remember_mode()
	changed.emit()
	return true

func set_stereo_alignment(key: String, value: float) -> bool:
	if not stereo_sbs or viewing_eye != 0 or not is_finite(value): return false
	if key not in ["stereo_horizontal", "stereo_vertical"]: return false
	set(key, clampf(snappedf(value, StereoView.STEP), -StereoView.LIMIT, StereoView.LIMIT))
	_stereo_view_dirty = true
	_apply_stereo_view()
	return true

func reset_stereo_alignment() -> void:
	stereo_horizontal = 0.0
	stereo_vertical = 0.0
	_stereo_view_dirty = true
	_apply_stereo_view()
	commit_stereo_view()
	changed.emit()

func commit_stereo_view() -> void:
	if not _stereo_view_dirty: return
	_stereo_view_dirty = false
	_remember_mode()

func _apply_stereo_view() -> void:
	if not material: return
	# Native stereo only: mono and generated 2D->3D never inherit these corrections.
	material.set_shader_parameter("viewing_eye", viewing_eye if stereo_sbs else 0)
	material.set_shader_parameter("stereo_offset", Vector2(stereo_horizontal, stereo_vertical) * 0.01 if stereo_sbs else Vector2.ZERO)

## The file name left the projection or the layout open: the frame's shape decides (once).
func _complete_layout() -> void:
	if bool(media.format.get("spatial_video", false)): _spatial_video = true
	if is_spatial_video():
		_layout_pending = null
		var revise := not stereo_sbs or top_bottom or depth_requested
		geometry = Geometry.Geometry.FLAT
		stereo_sbs = true
		top_bottom = false
		stereo_half = false
		depth_requested = false
		if revise: _request_revision()
		_apply_geometry()
		return
	if _layout_pending == null:
		return
	var chosen := Naming.complete(_layout_pending, int(media.format.width), int(media.format.height), media.format, _layout_basename)
	_layout_pending = null
	swap_eyes = chosen.swap
	stereo_half = chosen.stereo_half
	var tb := bool(chosen.stereo) and bool(chosen.top_bottom)
	if int(chosen.geometry) != geometry or bool(chosen.stereo) != stereo_sbs or tb != top_bottom:
		geometry = int(chosen.geometry)
		var revise := bool(chosen.stereo) != stereo_sbs or tb != top_bottom
		stereo_sbs = chosen.stereo
		top_bottom = tb
		var wanted := ai_available() and auto_depth and geometry == Geometry.Geometry.FLAT and not stereo_sbs and not alpha_requested
		revise = revise or depth_requested != wanted
		depth_requested = wanted
		if revise: _request_revision()
	_apply_geometry()
	Log.record("auto_layout", {"geometry": geometry, "stereo_sbs": stereo_sbs, "swap_eyes": swap_eyes,
		"width": media.format.width, "height": media.format.height})

## Packed masks show only on the layout they were made for (fisheye side by side).
func _apply_packed() -> void:
	var shown := packed_file and packed_alpha and not media.last_pair.is_empty() 		and not top_bottom and not stereo_half and Geometry.legacy_compatible(media.format, stereo_sbs, geometry)
	material.set_shader_parameter("packed_alpha", shown)
	if shown:
		material.set_shader_parameter("packed_size", Vector2(Geometry.packed_dimensions(int(media.format.width), int(media.format.height))))
	alpha_enabled = _rvm_alpha or shown

func _remember_mode() -> void:
	if not _remember_file or not media.accepts(media.session_id):
		return
	var mode := {"geometry": geometry, "stereo_sbs": stereo_sbs, "swap_eyes": swap_eyes,
		"viewing_eye": viewing_eye, "stereo_horizontal": stereo_horizontal, "stereo_vertical": stereo_vertical,
		"alpha_requested": alpha_requested, "profile": profile, "depth_requested": depth_requested,
		"top_bottom": stereo_sbs and top_bottom, "stereo_half": stereo_sbs and stereo_half, "fisheye_fov": fisheye_fov,
		"subtitle_delay_ms": subtitle_delay_ms, "audio_delay_ms": audio_delay_ms, "external_subtitle_uri": external_subtitle_uri}
	if not _track_choices.is_empty(): mode["track_choices"] = _track_choices.duplicate(true)
	if mode_memory.remember(local_uri, mode) and not mode_memory.save():
		Log.record("file_mode_save_failed", {"error": mode_memory.last_error})

func _on_pair(id: int, payload: String) -> void:
	if id != media.session_id:
		return
	var pair: Variant = JSON.parse_string(payload)
	if pair is Dictionary:
		_pending_pair = pair

func _present_pending() -> void:
	if _pixel_busy or _thumbnail_busy or _pending_pair.is_empty() or not _pending_revision.is_empty():
		return
	var offered := _pending_pair
	_pending_pair = {}
	var claimed: Variant = JSON.parse_string(platform.claim_mpv_pair(media.session_id, int(offered.slot_token)))
	if not claimed is Dictionary:
		return
	_unbind()
	_binding.opaque = not packed_file and claimed.get("mask_kind") == "opaque"
	if not _binding.bind(material, claimed):
		platform.detach_mpv_pair(media.session_id, int(claimed.slot_token))
		picker_error = "Complete video frame could not be bound"
		changed.emit()
		return
	media.last_pair = claimed
	media.logical_session_id = int(claimed.logical_session_id)
	media.generation = int(claimed.generation)
	media.format_revision = int(claimed.format_revision)
	media.effect_revision = int(claimed.presentation_revision)
	media.frame_counter += 1
	var par := float(claimed.get("pixel_aspect", 1.0))
	_spatial_video = _spatial_video or bool(claimed.get("spatial_video", false))
	media.format = {"width": int(claimed.width), "height": int(claimed.height),
		"spatial_video": _spatial_video,
		"pixel_aspect": par if is_finite(par) and par > 0.0 and par <= 16.0 else 1.0,
		"stereo_mode": str(claimed.get("stereo_mode", "")), "unapplied_rotation_degrees": 0}
	_rvm_alpha = false
	depth_enabled = false
	_apply_packed()
	material.set_shader_parameter("alpha_enabled", _rvm_alpha)
	_send_depth_view()
	_apply_geometry()
	panel.visible = true
	if not platform.acknowledge_mpv_pair(media.session_id, int(claimed.slot_token)):
		_unbind()
		return
	if _waiting_first:
		if control.in_flight > 0: _seek_event("target_presented")
		_waiting_first = false
		var actual_position_ms := int(int(claimed.pts_us) / 1000)
		if control.in_flight > 0:
			control.first_frame(actual_position_ms)
		else:
			control.observe(actual_position_ms, control.duration_ms)
		platform.set_mpv_playing(media.session_id, requested_play)
	else:
		control.observe(int(int(claimed.pts_us) / 1000), control.duration_ms)
	if media.frame_counter == 1:
		_open_trace.append({"stage": "first_pair_bound", "time_ms": Time.get_ticks_msec(), "pts_us": int(claimed.pts_us)})
		_complete_layout()
		_remember_mode()
		Log.record("mpv_pair_bound", media.frame_identity())
	_record_history()
	if _debug_request > 0 and not _debug_benchmark and _debug_pairs.size() < 128:
		_debug_pairs.append(claimed.duplicate(true))
		_write_debug_report()
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
	if _subtitle_loading and _subtitle_import_command == 0 and int(details.get("subtitle_import_command", 0)) > _subtitle_import_floor:
		# A processing revision can supersede the queued callback while retaining the same MPV host.
		_subtitle_import_command = int(details.subtitle_import_command)
		_subtitle_import_uri = _subtitle_requested_uri
		subtitles.select(-1)
	if _subtitle_import_command > 0 and int(details.get("subtitle_import_command", 0)) >= _subtitle_import_command:
		if str(details.get("subtitle_import_error", "")).is_empty():
			external_subtitle_uri = _subtitle_import_uri
			_remember_mode(); picker_error = ""
		else:
			picker_error = "Unable to load subtitle. Choose an SRT, ASS, SSA or VTT file."
		_subtitle_import_command = 0; _subtitle_import_uri = ""; _subtitle_loading = false
	_restore_track_choices()
	var size := str(details.get("file_size", ""))
	if not BookmarkStore.integer(_bookmark_metadata.get("size", -1), 1, 9007199254740991) and size.is_valid_int() and BookmarkStore.integer(int(size), 1, 9007199254740991):
		# Native metadata fills gaps for recent/SAF opens, without hashing or reading the video.
		_bookmark_metadata.size = int(size)
		_bookmark_resolve()
	if details.has("position_seconds"):
		var position_ms := int(float(details.position_seconds) * 1000)
		# MPV's time-pos may still be the requested time after a paused keyframe
		# seek. Keep the timeline and relative shortcuts on the displayed frame.
		var pair: Dictionary = media.last_pair
		if pair.get("source_pts_verified", false) and int(pair.get("session_id", -1)) == media.session_id:
			position_ms = int(int(pair.pts_us) / 1000)
		control.observe(position_ms, int(float(details.get("duration_seconds", "-1")) * 1000))
		media.decoder = str(details.get("codec", "")) + " / " + str(details.get("hwdec_current", ""))
	media.state = str(report.get("state", "opening"))
	if media.state == "ended":
		_record_history(true)
	if _debug_request > 0:
		_debug_status = report.duplicate(true)
		_write_debug_report()
	changed.emit()

func _on_error(id: int, payload: String) -> void:
	if id != media.session_id:
		return
	_thumbnail_sequence += 1
	var report: Variant = JSON.parse_string(payload)
	media.error = str(report.get("code", "MPV playback failed")) if report is Dictionary else "MPV playback failed"
	media.state = "failed"
	_freeze_request = 0
	_pending_revision = {}
	_waiting_first = false
	control.reject()
	subtitles.clear()
	_recover = media.error == "MPV_GL_CONTEXT_RECREATED"
	_recover_ms = control.observed_position_ms
	_unbind()
	Log.record("mpv_error", {"session_id": id, "report": report})
	_write_debug_report()
	changed.emit()

func _on_detach(id: int, _payload: String) -> void:
	if int(_binding.ticket.get("session_id", 0)) == id and not _is_frozen():
		_unbind()

func _on_released(id: int, _payload: String) -> void:
	if id == media.session_id and _recover:
		_recover = false
		call_deferred("_reopen_after_context_loss", local_uri, display_name, _recover_ms, _remember_file)
	_write_debug_report()

func _reopen_after_context_loss(uri: String, title: String, position_ms: int, remember_file: bool) -> void:
	# Retain live user choices even if the last disk save failed.
	var persisted := _file_permission_persisted
	var eye := viewing_eye
	var alignment := Vector2(stereo_horizontal, stereo_vertical)
	if open_local(uri, title, position_ms, false, alpha_requested):
		_remember_file = remember_file
		_file_permission_persisted = persisted
		viewing_eye = eye
		stereo_horizontal = alignment.x
		stereo_vertical = alignment.y
		_apply_stereo_view()

func _on_debug_command(id: int, payload: String) -> void:
	var command: Variant = JSON.parse_string(payload)
	if command is Dictionary and command.get("operation", "") in ["open", "seek"] and command.get("seek_mode", "") in [SeekPolicy.SPEED, SeekPolicy.EXACT]:
		seek_mode = command.seek_mode
	if not command is Dictionary:
		return
	_debug_request = id
	if command.operation == "open":
		_debug_benchmark = bool(command.get("benchmark", false))
		loop_enabled = bool(command.get("loop", false)) # long thermal runs replay a short fixture
		_debug_next_report_us = 0
		if _debug_benchmark:
			geometry = int(command.get("projection", 0))
		_debug_commands = []
		_debug_pairs = []
		stereo_sbs = bool(command.get("stereo", true))
		profile = str(command.profile)
		alpha_requested = bool(command.enabled)
		depth_requested = bool(command.get("depth", false))
		auto_depth = depth_requested
		requested_play = true
		open_local(str(command.uri), str(command.title), maxi(int(command.position_ms), 0), false, alpha_requested)
	elif command.operation == "alpha":
		set_alpha(bool(command.enabled))
	elif command.operation == "depth":
		command["accepted"] = set_depth_strength(float(command.strength)) if command.has("strength") else set_depth(bool(command.enabled))
	elif command.operation == "audio":
		command["accepted"] = set_audio_options(int(command.track_id), audio_volume, audio_muted)
	elif command.operation == "subtitle":
		command["accepted"] = set_subtitle_track(int(command.track_id))
	elif command.operation == "playing":
		if requested_play != bool(command.enabled) or (bool(command.enabled) and media.state == "ended"):
			toggle_play()
	elif command.operation == "seek":
		_debug_seek_delay_until_ms = Time.get_ticks_msec() + clampi(int(command.get("hold_seek_ms", 0)), 0, 30000)
		seek_absolute(int(command.position_ms))
	elif command.operation == "hold_pixels":
		if _is_frozen() and not _pixel_busy:
			var held: Dictionary = _binding.ticket.duplicate(true)
			if false: held.stereo_sbs = false
			var pinned: bool = platform.retain_mpv_frozen_frame(int(held.frozen_frame_id))
			if not pinned: return
			_pixel_busy = true
			_debug_pixels = await PixelProbe.capture(self, held, id)
			_debug_pixels["request_key"] = str(command.request_key)
			platform.release_mpv_frozen_frame(int(held.frozen_frame_id))
			_pixel_busy = false
	elif command.operation == "observe":
		pass
	elif command.operation == "stereo":
		if stereo_sbs != bool(command.enabled):
			toggle_stereo()
	elif command.operation == "profile":
		profile = str(command.profile)
		_request_revision()
	elif command.operation == "close":
		close_video()
	elif command.operation == "pixels":
		_debug_pixels = {"state": "failed", "request_id": id, "request_key": str(command.request_key)}
		if not _pixel_busy and not requested_play and not _binding.ticket.is_empty() and _pending_revision.is_empty():
			_pixel_busy = true
			_pixel_request = id
			_pixel_request_key = str(command.request_key)
			if platform.request_mpv_pixel_mask(id, int(_binding.ticket.session_id), int(_binding.ticket.slot_token)):
				_debug_pixels["state"] = "waiting_mask"
			else:
				_pixel_busy = false
				_debug_pixels["error"] = "Native pinned mask request rejected"
		else:
			_debug_pixels["error"] = "Paused immutable binding required"
	command["request_id"] = id
	_debug_commands.append(command)
	if _debug_commands.size() > 32:
		_debug_commands.pop_front()
	# Commands need an immediate receipt even if benchmark telemetry was just written.
	# Closing stops periodic playback updates, so throttling here loses its final report.
	_debug_next_report_us = 0
	_write_debug_report()

func _on_pixel_mask(id: int, payload: String) -> void:
	if id != _pixel_request:
		return
	var mask: Variant = JSON.parse_string(payload)
	if not mask is Dictionary or mask.get("state") != "ready":
		_debug_pixels = {"state": "failed", "request_id": id, "error": "Native mask readback failed", "native": mask}
		_pixel_busy = false
		_write_debug_report()
		return
	var pair: Dictionary = mask.pair
	_debug_pixels = await PixelProbe.capture(self, pair, id)
	_debug_pixels["request_key"] = _pixel_request_key
	_debug_pixels["mask_reference"] = mask
	_debug_pixels["native_pin_released"] = platform.release_mpv_pixel_pin(int(pair.session_id), int(pair.slot_token))
	_pixel_busy = false
	_write_debug_report()

func _write_debug_report() -> void:
	if _debug_request <= 0 or not platform:
		return
	var now := Time.get_ticks_usec()
	if _debug_benchmark and now < _debug_next_report_us:
		return
	_debug_next_report_us = now + 250000
	var progress: Dictionary = {}
	var host := get_parent()
	if host and host.has_method("_menu_state"):
		var menu: Node3D = host.player_menu
		if menu and menu.visible and is_instance_valid(menu._thumb):
			progress = {"visible": true, "position_ms": int(menu._state.get("position_ms", -1)),
				"preview_ms": menu._seek_preview, "elapsed": menu._elapsed.text,
				"thumb_x": menu._thumb.position.x, "bar_width": menu.BAR_SEEK,
				"duration_ms": int(menu._state.get("duration_ms", -1))}
	var report := {"schema_version": 1, "request_id": _debug_request, "commands": _debug_commands,
		"picker_error": picker_error,
		"canvas_controls": host._canvas_controls_snapshot() if host and host.has_method("_canvas_controls_snapshot") else {},
		"seek_policy_ui": host.seek_policy_probe_result if host and host.get("seek_policy_probe_result") is Dictionary else {},
		"open_trace": _open_trace.duplicate(true),
		"media": media.snapshot(), "layout": layout_snapshot(), "pairs": _debug_pairs,
		"native_status": _debug_status, "engine_fps": Engine.get_frames_per_second(),
		"sample_monotonic_us": now, "engine_drawn_frames": Engine.get_frames_drawn(),
		"benchmark": _debug_benchmark,
		"pixel_probe": _debug_pixels,
		"seek_trace": _seek_trace,
		"player_menu_progress": progress,
		"thumbnail": {"available": Thumbnails.has(local_uri), "capture": _thumbnail_result, "busy": _thumbnail_busy},
		"diagnostic_2d": OS.get_cmdline_user_args().has("--mpv-diagnostic-2d"),
		"scope": "Production MPV/RVM/Godot ownership trace; independent pixel, audio and performance validation pending"}
	platform.save_mpv_player_report(_debug_request, JSON.stringify(report))

func _source_size() -> Vector2:
	return Vector2(float(media.format.width), float(media.format.height))

func _sync_subtitle_surface() -> void:
	if not _subtitle_surface or not material: return
	var separate := not is_zero_approx(screen_rotation)
	material.set_shader_parameter("separate_subtitles", separate)
	_subtitle_surface.visible = separate and panel.visible and (material.get_shader_parameter("subtitle_enabled") == true or material.get_shader_parameter("bitmap_subtitle_enabled") == true)
	if not _subtitle_surface.visible: return
	_subtitle_surface.mesh = panel.mesh
	_subtitle_surface.global_transform = subtitle_transform()
	for key in ["subtitle_texture", "subtitle_enabled", "subtitle_anchor_inverse", "subtitle_parallax", "subtitle_patch_half_extent", "bitmap_subtitle_texture", "bitmap_subtitle_enabled", "bitmap_subtitle_rect", "rotation_degrees"]:
		_subtitle_material.set_shader_parameter(key, material.get_shader_parameter(key))

func _pixel_aspect() -> float:
	return float(media.format.get("pixel_aspect", 1.0))

func _apply_flat_pose() -> void:
	# Reclining mode permits full placement tilt, including follow and recenter.
	if not reclining_mode:
		flat_pose = global_transform.affine_inverse() * upright_pose(global_transform * flat_pose)
	super._apply_flat_pose()
	if caption and caption.visible: _place_caption()
	_sync_subtitle_surface()

func _apply_geometry() -> void:
	super._apply_geometry()
	_apply_stereo_view()
	if geometry != Geometry.Geometry.FLAT:
		bitmap_subtitles.clear(material)
		if _subtitle_surface: _subtitle_surface.visible = false
		for track in media.playback.get("details", {}).get("subtitle_tracks", []):
			if track is Dictionary and int(track.get("id", 0)) == subtitles.requested_track and str(track.get("codec", "")) == "hdmv_pgs_subtitle":
				set_subtitle_track(0, false)
	_apply_packed()
	if caption and caption.visible: _place_caption()
	_sync_subtitle_surface()
	material.set_shader_parameter("stereo_sbs", stereo_sbs or false)
	material.set_shader_parameter("depth_enabled", depth_enabled and not false)
	material.set_shader_parameter("depth_shift", DEPTH_SHIFT * depth_strength if depth_requested else 0.0)

func layout_snapshot() -> Dictionary:
	var playback := control.snapshot()
	playback["seek_method"] = "mpv_absolute_" + ("exact" if _last_seek_mode == SeekPolicy.EXACT else "keyframes") + "_and_processing_generation"
	playback["seek_mode"] = SeekPolicy.normalize(seek_mode)
	playback["active_seek_mode"] = _last_seek_mode
	playback["bookmark_seek_mode"] = SeekPolicy.bookmark_override(bookmark_seek_mode)
	playback["source_frame_pts_verified"] = media.last_pair.get("source_pts_verified", false)
	return {"geometry": ["flat", "half_equirect_180", "fisheye_180", "equirect_360"][geometry], "stereo_sbs": stereo_sbs,
		"viewing_eye": viewing_eye, "stereo_horizontal": stereo_horizontal, "stereo_vertical": stereo_vertical,
		"opaque_rendering": material != null and material.shader == Binding.OPAQUE_SHADER,
		"top_bottom": stereo_sbs and top_bottom, "stereo_half": stereo_sbs and stereo_half, "fisheye_fov": fisheye_fov,
		"alpha_requested": alpha_requested, "alpha_enabled": alpha_enabled, "profile": profile,
		"depth_requested": depth_requested, "depth_enabled": depth_enabled, "depth_strength": depth_strength, "auto_depth": auto_depth,
		"screen_rotation": screen_rotation, "playback_speed": playback_speed,
		"alpha_ready": alpha_ready(), "backend": "Android_libmpv", "loop_enabled": loop_enabled,
		"playback_control": playback, "subtitles": {"requested_track": subtitles.requested_track,
			"cue": subtitles.cue, "text": subtitles.text,
			"bitmap_ready": geometry == Geometry.Geometry.FLAT and bitmap_subtitles.texture != null \
				and bool(material.get_shader_parameter("bitmap_subtitle_enabled")),
			"bitmap_texture_version": bitmap_subtitles.version,
			"bitmap_texture_size": [bitmap_subtitles.texture.get_width(), bitmap_subtitles.texture.get_height()] if bitmap_subtitles.texture else [],
			"render_layer": "flat_PGS_bitmap_overlay" if bitmap_subtitles.texture and geometry == Geometry.Geometry.FLAT \
				else ("independent_Label3D" if geometry == Geometry.Geometry.FLAT else "video_projection_overlay"),
			"size": subtitle_size, "flat_position": subtitle_flat_position, "rotation_independent": true,
			"distance_m": subtitle_distance, "position": subtitle_position, "direction": subtitle_direction,
			"runtime_ipd_m": ProjectedSubtitles.runtime_ipd(),
			"angular_parallax_rad": material.get_shader_parameter("subtitle_parallax"),
			"anchor_space": "screen" if geometry == Geometry.Geometry.FLAT else "video_local",
			"anchor_direction": _subtitle_anchor_direction(),
			"source_frame_sync_verified": false, "device_validation": "pending"},
		"frame_hold": {"visible": panel.visible, "frozen": _is_frozen(), "capture_pending": _freeze_request > 0,
			"frame_id": int(_binding.ticket.get("frame_id", -1)), "pts_us": int(_binding.ticket.get("pts_us", -1)),
			"frozen_frame_id": int(_binding.ticket.get("frozen_frame_id", 0)),
			"freeze_copy_us": int(_binding.ticket.get("freeze_copy_us", 0))}, "device_validation": "pending"}

func _subtitle_anchor_direction() -> Array:
	var anchor := SubtitleDepth.anchor(subtitle_position, subtitle_direction == 1) * Vector3.FORWARD
	return [anchor.x, anchor.y, anchor.z]

func completed_presentation() -> bool:
	if not requested_play or media.state != "ended" or _waiting_first or not _pending_revision.is_empty():
		return false
	var end: Dictionary = media.playback
	var final_pair: Dictionary = media.last_pair
	var target: Variant = end.get("eof_source_ticket")
	if not end.get("eof_source_resolved", false) or not end.get("eof_pair_post_draw", false) or not target is Dictionary or final_pair.is_empty():
		return false
	return int(end.get("eof_presented_slot", 0)) == int(final_pair.get("slot_token", -1)) \
		and int(target.source_epoch) == int(final_pair.get("source_epoch", -1)) \
		and int(target.frame_id) == int(final_pair.get("frame_id", -1)) \
		and int(target.pts_us) == int(final_pair.get("pts_us", -1)) \
		and final_pair.get("contract_version") == 2

func _can_loop() -> bool:
	return loop_enabled and completed_presentation()

func _process(_delta: float) -> void:
	if _sync_pending and PlatformMethods.supports(platform, "set_mpv_sync"):
		_sync_pending = not platform.set_mpv_sync(media.session_id, subtitle_delay_ms, audio_delay_ms)
	if not _pending_external_uri.is_empty() and not _subtitle_loading and media.state in ["ready", "playing", "paused"]:
		if PlatformMethods.supports(platform, "add_mpv_subtitle") and platform.add_mpv_subtitle(media.session_id, _pending_external_uri):
			_subtitle_requested_uri = _pending_external_uri
			_subtitle_import_floor = int(media.playback.get("details", {}).get("subtitle_import_command", 0))
			_pending_external_uri = ""; _subtitle_loading = true
	if _audio_pending:
		set_audio_options(audio_track_id, audio_volume, audio_muted)
	elif not _track_choices.has("audio") and prefer_clone_voice and not _clone_applied and clone_voice_track() > 0:
		_clone_applied = set_audio_options(clone_voice_track(), audio_volume, audio_muted)
	if panel and geometry != Geometry.Geometry.FLAT:
		_center_on_view()
	if not _pending_revision.is_empty():
		_try_revision()
	_present_pending()
	_maybe_capture_thumbnail()
	_poll_subtitles()
	if _can_loop():
		seek_absolute(0)

func _exit_tree() -> void:
	close_video()
	if is_instance_valid(caption) and caption.get_parent() != self:
		caption.queue_free()
