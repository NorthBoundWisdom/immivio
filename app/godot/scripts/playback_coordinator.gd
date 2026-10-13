extends RefCounted
## Owns playback/queue actions and source selection.

var _host_ref: WeakRef
const Log := preload("res://scripts/diagnostic_log.gd")
const Video := preload("res://scripts/mpv_video_display.gd")
const ThumbnailCache := preload("res://scripts/thumbnail_cache.gd")
const ImageInfo := preload("res://scripts/image_info.gd")
const I18n := preload("res://scripts/i18n.gd")

var _queue_add_mode := false
var _queue_end_key := ""

func _init(host: Node3D) -> void:
	_host_ref = weakref(host)

func _on_library_chosen(uri: String, title: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return
	var is_photo: bool = ImageInfo.is_image(uri, title) or host.recent_menu.is_image_uri(uri)
	if host._queue_add_mode:
		if not is_photo:
			var metadata: Dictionary = host.recent_menu.server_browser.selection.duplicate(true) if uri.begins_with("medialib://") else {}
			for item in host.recent_menu.video_queue():
				if item.uri == uri: metadata = item.get("metadata", {}); break
			host.playback_queue.custom = true
			host.playback_queue.append([{"uri": uri, "title": title, "metadata": metadata}])
			host._save_queue()
			host.recent_menu.status = "Added to playback queue"
			host.recent_menu.refresh()
		return
	var directory_context: Dictionary = host.recent_menu.photo_directory_context() if is_photo else {}
	host.recent_menu.dismiss()
	if host.player_menu: host.player_menu.dismiss()
	host._grab = {}
	host.stick_controls.suspend()
	if is_photo:
		host.video.close_video()
		host.photo_active = true
		host.player_menu = host.photo_menu
		host._photo_open_hide_controls = host.hand_pointers.values().any(func(pointer): return pointer.source == "hand")
		host.photo.open_image(uri, title, host.recent_menu.image_queue())
		host.photo.start_directory(directory_context)
		host._show_player_menu()
	else:
		host._photo_open_hide_controls = false
		host.photo.close_image()
		host.photo_active = false
		host.player_menu = host.video_menu
		host.playback_queue.anchor = uri
		if not host.playback_queue.custom: host.video_queue = host.recent_menu.video_queue()
		if host.playback_queue.find(uri).is_empty(): host.playback_queue.append([{"uri": uri, "title": title}])
		var metadata: Dictionary = host.recent_menu.server_browser.selection.duplicate(true) if uri.begins_with("medialib://") else {}
		if not uri.begins_with("medialib://"):
			for row in host.recent_menu.rows:
				if str(row.get("uri", "")) == uri: metadata = row.duplicate(true); break
		host.recent_menu.server_browser.selection = {}
		if metadata.get("uri", "") != uri: metadata = {}
		if not host.playback_queue.find(uri).is_empty(): host.playback_queue.find(uri).metadata = metadata.duplicate(true)
		if host.playback_queue.shuffle: host.playback_queue.configure("queue_shuffle", true, uri)
		host._save_queue()
		if host.video.open_library(uri, title, metadata): host._show_player_menu()

func _adjacent_video(direction: int) -> Dictionary:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return {}
	if host.photo_active or not host.video: return {}
	return host.playback_queue.adjacent(host.video.local_uri, direction)

func _navigate_video(direction: int) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return
	var item = host._adjacent_video(direction)
	if item.is_empty(): return
	host._grab = {}
	host.stick_controls.suspend()
	host._menu_touched_ms = Time.get_ticks_msec()
	host.video.open_library(str(item.uri), str(item.title), item.get("metadata", {}))
	if host.player_menu and host.player_menu.visible: host.player_menu.refresh()

func _queue_action(operation: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return
	host.playback_queue.anchor = host.video.local_uri
	if operation == "queue_add":
		host._queue_add_mode = true
		host.recent_menu.queue_add_mode = true
		host._show_recent_menu()
		return
	if operation == "queue_done":
		host._queue_add_mode = false; host.recent_menu.queue_add_mode = false
		host._show_player_menu()
		host.video_menu._adjustment = "queue"; host.video_menu.section = 1; host.video_menu.refresh()
		return
	if operation == "queue_add_list":
		host.playback_queue.custom = true; host.playback_queue.append(host.recent_menu.video_queue())
	elif operation == "queue_clear":
		host.playback_queue.clear(); host.playback_queue.custom = false
	else:
		var parts = operation.split("_")
		if parts.size() != 3 or not parts[2].is_valid_int(): return
		var index = int(parts[2])
		if index < 0 or index >= host.video_queue.size(): return
		if parts[1] != "play": host.playback_queue.custom = true
		match parts[1]:
			"play":
				var item = host.video_queue[index]
				if host.playback_queue.shuffle: host.playback_queue.configure("queue_shuffle", true, str(item.uri))
				host.photo.close_image(); host.photo_active = false; host.player_menu = host.video_menu
				host.video.requested_play = true
				host.video.open_library(str(item.uri), str(item.title), item.get("metadata", {}))
			"remove": host.playback_queue.remove(index)
			"up": host.playback_queue.move(index, -1)
			"down": host.playback_queue.move(index, 1)
	host._save_queue()
	if host.video_menu and host.video_menu.visible: host.video_menu.refresh()

func _save_queue() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return
	host.settings.set_value("playback", "queue", host.playback_queue.saved_entries())
	host.settings.set_value("playback", "custom_queue", host.playback_queue.custom)
	host.settings.save(host.settings_path)

func _advance_queue(session_id: int, uri: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return
	if host.photo_active or host.video.media.session_id != session_id or host.video.local_uri != uri or not host.video.completed_presentation(): return
	if host.video.loop_enabled or not host.playback_queue.autoplay: return
	var item = host.playback_queue.adjacent(uri, 1)
	if item.is_empty(): return
	# An automatic next entry starts at zero; manual navigation retains its resume policy.
	host.video.requested_play = true
	host.video.open_library(str(item.uri), str(item.title), item.get("metadata", {}), true)
	if host.player_menu and host.player_menu.visible: host.player_menu.refresh()

func _on_video_changed() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return
	if host.photo_active: return
	if host.video.media.state != "ended": host._queue_end_key = ""
	elif host.playback_queue.autoplay and not host.video.loop_enabled and host.video.completed_presentation():
		var key = "%s/%s/%s" % [host.video.media.session_id, host.video.local_uri, host.video.media.last_pair.get("source_epoch", 0)]
		if key != host._queue_end_key:
			host._queue_end_key = key
			host._advance_queue.call_deferred(host.video.media.session_id, host.video.local_uri)
	host._update_thumbnail_protection()
	host._update_background()
	host._update_status()
	if host.player_menu and host.player_menu.visible:
		host.player_menu.refresh_values()

func _on_video_thumbnail_ready(_uri: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return
	if host.recent_menu and host.recent_menu.visible: host.recent_menu.refresh()

func _update_thumbnail_protection() -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return
	if not host.video or host._thumbnail_history_sequence == host.video.recent_files.sequence: return
	host._thumbnail_history_sequence = host.video.recent_files.sequence
	ThumbnailCache.protect_keys(host.video.recent_files.list_recent().map(func(e): return str(e.uri)))

func _on_menu_action(operation: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return
	if operation.begins_with("queue_"):
		host._queue_action(operation); return
	if operation == "load_subtitle": host.video.pick_external_subtitle(); return
	if operation == "forget_subtitle": host.video.forget_external_subtitle(); return
	if host.photo_active:
		host._on_photo_action(operation)
		return
	if host.video and not host.video.mode_action_allowed(operation): return
	match operation:
		"open_file": host._show_recent_menu()
		"seek_mode":
			host._on_setting_changed("seek_mode", host.video.SeekPolicy.EXACT if host.video.seek_mode == host.video.SeekPolicy.SPEED else host.video.SeekPolicy.SPEED)
		"play": host.video.toggle_play()
		"alpha": host.video.set_alpha(not host.video.alpha_wanted())
		"depth":
			if host.video.set_depth(not host.video.depth_requested): host._remember_auto_depth(host.video.auto_depth)
		"depth_strength":
			host.video.cycle_depth_strength()
			host.settings.set_value("video", "depth_strength", host.video.depth_strength)
			host.settings.save(host.settings_path)
		"clone_voice":
			if host.video.toggle_clone_voice():
				host.settings.set_value("audio", "prefer_clone_voice", host.video.prefer_clone_voice)
				host.settings.save(host.settings_path)
		"previous_video": host._navigate_video(-1)
		"next_video": host._navigate_video(1)
		"loop": host.video.toggle_loop()
		"stop":
			host._grab.clear(); host._trigger_taps.clear(); host.stick_controls.suspend()
			host.video.close_video()
			host._show_recent_menu(true)
		"stereo": host.video.toggle_stereo()
		"eyes": host.video.toggle_eye_order()
		"projection": host.video.cycle_projection()
		"projection_0", "projection_1", "projection_2", "projection_3": host.video.set_projection(int(operation.right(1)))
		"stereo_2d":
			host._remember_auto_depth(false)
			host.video.set_depth(false) # plain 2D: also ends 2D -> 3D
			host.video.set_stereo_layout(0)
		"lock_mode":
			host.video.toggle_mode_lock()
		"stereo_sbs": host.video.set_stereo_layout(1)
		"stereo_tb": host.video.set_stereo_layout(2)
		"stereo_half_sbs": host.video.set_stereo_layout(3)
		"stereo_half_tb": host.video.set_stereo_layout(4)
		"fov_180", "fov_190", "fov_200", "fov_220": host.video.set_fisheye_fov(int(operation.right(3)))
		"recenter": host._recenter()
		"screen_curve":
			host.video.cycle_screen_curve()
			host._save_screen()
		"calibration": host.video.play_calibration_clip()
		"volume_down": host.video.change_volume(-10.0)
		"volume_up": host.video.change_volume(10.0)
		"mute": host.video.toggle_mute()
		"audio": host.video.cycle_audio_track()
		"capabilities": host.request_capabilities()

func _on_menu_seek(position_ms: int) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return
	if host.photo_active: return
	host.video.seek_absolute(position_ms)

func _on_player_setting(key: String, value: Variant) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return
	if key in ["queue_autoplay", "queue_repeat", "queue_shuffle"]:
		host.playback_queue.configure(key, bool(value), host.video.local_uri)
		host.settings.set_value("playback", key, bool(value)); host.settings.save(host.settings_path)
		return
	if host.photo_active: return
	match key:
		"seek_mode", "subtitle_distance", "subtitle_position", "subtitle_direction": host._on_setting_changed(key, value)
		"viewing_eye": host.video.set_viewing_eye(int(value))
		"subtitle_size", "subtitle_flat_position", "subtitle_palette": host._on_playback_adjustment(key, value); host._save_playback_adjustments()
		"loop": host.video.loop_enabled = bool(value); host.video.changed.emit()
		"show_fps": host._on_setting_changed(key, value)
		"screen_curve": host.video.set_screen_curve(float(value)); host._save_screen(); host.video.changed.emit()
		"audio_track":
			if host.video.select_audio_track(int(value)):
				host.settings.set_value("audio", "prefer_clone_voice", host.video.prefer_clone_voice)
				host.settings.save(host.settings_path)

func _on_bookmark_mode_requested(mode: String, scope: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return
	if host.photo_active or scope != host.video.bookmark_scope() or mode not in [host.video.SeekPolicy.GLOBAL, host.video.SeekPolicy.SPEED, host.video.SeekPolicy.EXACT]: return
	host._menu_touched_ms = Time.get_ticks_msec()
	host.video.bookmark_seek_mode = mode
	host.settings.set_value("video", "bookmark_seek_mode", mode)
	host.settings.save(host.settings_path)
	Log.record("setting_changed", {"key": "bookmark_seek_mode", "value": mode})

func _on_bookmark_request(operation: String, marker_id: String, scope: String) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return
	if host.photo_active: return
	host._menu_touched_ms = Time.get_ticks_msec()
	var message: String = host.video.bookmark_action(operation, marker_id, scope)
	if message == "Bookmark added":
		host.player_menu.bookmarks.notify(I18n.t(message) + " · " + host.player_menu._time(int(host.video.bookmark_last_added.position_ms)), str(host.video.bookmark_last_added.id))
	elif not message.is_empty(): host.player_menu.bookmarks.notify(I18n.t(message))
	else: host.player_menu.refresh_values()

func _on_menu_volume(volume: float, muted: bool) -> void:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return
	if host.photo_active: return
	host.video.set_audio_options(host.video.audio_track_id, host.video.audio_volume if muted else volume, muted)

func _audio_option_label(track: Dictionary) -> String:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return ""
	if track.get("external", false) and str(track.get("title", "")) == "Clone voice": return I18n.t("Dubbing")
	var title = str(track.get("title", "")).replace("\n", " ").replace("\r", " ").strip_edges()
	var language = str(track.get("language", "")).replace("_", "-").to_lower().split("-")[0]
	var names = {"en": "English", "eng": "English", "zh": "Chinese", "zho": "Chinese", "chi": "Chinese",
		"ja": "Japanese", "jpn": "Japanese", "fr": "French", "fra": "French", "fre": "French",
		"de": "German", "deu": "German", "ger": "German", "es": "Spanish", "spa": "Spanish",
		"ko": "Korean", "kor": "Korean", "ru": "Russian", "rus": "Russian"}
	var language_label = I18n.t(str(names.get(language, language))) if language not in ["", "und"] else ""
	if title.is_empty(): title = I18n.t("Track %d") % int(track.get("id", 0))
	return title + (" · " + language_label if not language_label.is_empty() else "")

func _audio_track_name(details: Dictionary) -> String:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return ""
	var current = str(details.get("audio_track_id", ""))
	for track in details.get("audio_tracks", []):
		if track is Dictionary and str(track.get("id", "")) == current:
			return host._audio_option_label(track)
	return current if not current.is_empty() else "Auto"

func _menu_error() -> String:
	var host := _host_ref.get_ref() as Node3D
	if not is_instance_valid(host): return ""
	var error: String = host.video.picker_error if not host.video.picker_error.is_empty() else host.video.media.error
	if error.is_empty():
		error = host.display.error_code
	match error:
		"PERMISSION_LOST", "LOCAL_DOCUMENT_PERMISSION_LOST": error = "File access lost. Select the video again (PERMISSION_LOST)."
		"MISSING", "LOCAL_DOCUMENT_MISSING": error = "Video no longer exists. Select another file (MISSING)."
		"TIMEOUT", "LOCAL_DOCUMENT_TIMEOUT": error = "File access timed out. Try opening again."
		"UNREADABLE": error = "Unable to read the video. Select another file."
	return I18n.t(error)
