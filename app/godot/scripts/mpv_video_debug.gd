extends Node
## Debug-only command dispatch, readback and telemetry; owned by the video scene.
const PixelProbe := preload("res://scripts/mpv_pixel_probe.gd")
const SeekPolicy := preload("res://scripts/seek_policy.gd")
const Geometry := preload("res://scripts/video_geometry.gd")
const Thumbnails := preload("res://scripts/thumbnail_cache.gd")
var _owner_ref: WeakRef
var seek_delay_until_ms := 0
var request := 0
var commands: Array = []
var pairs: Array = []
var status: Dictionary = {}
var pixels: Dictionary = {}
var benchmark := false
var next_report_us := 0
var pixel_request := 0
var pixel_request_key := ""
var pixel_busy := false
var seek_trace: Array[Dictionary] = []
var open_trace: Array[Dictionary] = []


func _init(video: Node3D) -> void:
	_owner_ref = weakref(video)


func connect_platform(platform: Object) -> void:
	platform.connect("mpv_debug_command", handle_command)
	platform.connect("mpv_pixel_mask", handle_pixel_mask)


func handle_command(id: int, payload: String) -> void:
	var video := _owner_ref.get_ref() as Node3D
	if not is_instance_valid(video):
		return
	var command: Variant = JSON.parse_string(payload)
	if (
		command is Dictionary
		and command.get("operation", "") in ["open", "seek"]
		and command.get("seek_mode", "") in [SeekPolicy.SPEED, SeekPolicy.EXACT]
	):
		video.seek_mode = command.seek_mode
	if not command is Dictionary:
		return
	request = id
	if command.operation == "open":
		benchmark = bool(command.get("benchmark", false))
		video.loop_enabled = bool(command.get("loop", false))  # long thermal runs replay a short fixture
		next_report_us = 0
		if benchmark:
			video.geometry = int(command.get("projection", 0))
		commands = []
		pairs = []
		video.stereo_sbs = bool(command.get("stereo", true))
		if bool(command.get("auto_stereo", false)):
			video.geometry = Geometry.Geometry.FLAT
			video.stereo_sbs = false
		video.requested_play = true
		video.open_local(
			str(command.uri), str(command.title), maxi(int(command.position_ms), 0), false
		)
		if bool(command.get("auto_stereo", false)):
			video.enable_auto_stereo()
	elif command.operation == "alpha":
		video.set_alpha(bool(command.enabled))
	elif command.operation == "audio":
		command["accepted"] = video._apply_audio_track(int(command.track_id))
	elif command.operation == "subtitle":
		command["accepted"] = video.set_subtitle_track(int(command.track_id))
	elif command.operation == "playing":
		if (
			video.requested_play != bool(command.enabled)
			or (bool(command.enabled) and video.media.state == "ended")
		):
			video.toggle_play()
	elif command.operation == "seek":
		seek_delay_until_ms = (
			Time.get_ticks_msec() + clampi(int(command.get("hold_seek_ms", 0)), 0, 30000)
		)
		video.seek_absolute(int(command.position_ms))
	elif command.operation == "hold_pixels":
		if video._is_frozen() and not pixel_busy:
			var held: Dictionary = video._binding.ticket.duplicate(true)
			if false:
				held.stereo_sbs = false
			var pinned: bool = video.platform.retain_mpv_frozen_frame(int(held.frozen_frame_id))
			if not pinned:
				return
			pixel_busy = true
			pixels = await PixelProbe.capture(video, held, id)
			pixels["request_key"] = str(command.request_key)
			video.platform.release_mpv_frozen_frame(int(held.frozen_frame_id))
			pixel_busy = false
	elif command.operation == "observe":
		pass
	elif command.operation == "stereo":
		if video.stereo_sbs != bool(command.enabled):
			video.toggle_stereo()
	elif command.operation == "close":
		video.close_video()
	elif command.operation == "pixels":
		pixels = {"state": "failed", "request_id": id, "request_key": str(command.request_key)}
		if (
			not pixel_busy
			and not video.requested_play
			and not video._binding.ticket.is_empty()
			and video._pending_revision.is_empty()
		):
			pixel_busy = true
			pixel_request = id
			pixel_request_key = str(command.request_key)
			if video.platform.request_mpv_pixel_mask(
				id, int(video._binding.ticket.session_id), int(video._binding.ticket.slot_token)
			):
				pixels["state"] = "waiting_mask"
			else:
				pixel_busy = false
				pixels["error"] = "Native pinned mask request rejected"
		else:
			pixels["error"] = "Paused immutable binding required"
	command["request_id"] = id
	commands.append(command)
	if commands.size() > 32:
		commands.pop_front()
	# Commands need an immediate receipt even if benchmark telemetry was just written.
	# Closing stops periodic playback updates, so throttling here loses its final report.
	next_report_us = 0
	write_report()


func handle_pixel_mask(id: int, payload: String) -> void:
	var video := _owner_ref.get_ref() as Node3D
	if not is_instance_valid(video):
		return
	if id != pixel_request:
		return
	var mask: Variant = JSON.parse_string(payload)
	if not mask is Dictionary or mask.get("state") != "ready":
		pixels = {
			"state": "failed",
			"request_id": id,
			"error": "Native mask readback failed",
			"native": mask
		}
		pixel_busy = false
		write_report()
		return
	var pair: Dictionary = mask.pair
	pixels = await PixelProbe.capture(video, pair, id)
	pixels["request_key"] = pixel_request_key
	pixels["mask_reference"] = mask
	pixels["native_pin_released"] = video.platform.release_mpv_pixel_pin(
		int(pair.session_id), int(pair.slot_token)
	)
	pixel_busy = false
	write_report()


func write_report() -> void:
	var video := _owner_ref.get_ref() as Node3D
	if not is_instance_valid(video):
		return
	if request <= 0 or not video.platform:
		return
	var now := Time.get_ticks_usec()
	if benchmark and now < next_report_us:
		return
	next_report_us = now + 250000
	var ui: Dictionary = (
		video.diagnostic_ui_provider.call() if video.diagnostic_ui_provider.is_valid() else {}
	)
	var report := {
		"schema_version": 1,
		"request_id": request,
		"commands": commands,
		"picker_error": video.picker_error,
		"loading_feedback": ui.get("loading_feedback", {}),
		"canvas_controls": ui.get("canvas_controls", {}),
		"selected_features_ui": ui.get("selected_features_ui", {}),
		"seek_policy_ui": ui.get("seek_policy_ui", {}),
		"open_trace": open_trace.duplicate(true),
		"media": video.media.snapshot(),
		"layout": video.layout_snapshot(),
		"pairs": pairs,
		"native_status": status,
		"engine_fps": Engine.get_frames_per_second(),
		"sample_monotonic_us": now,
		"engine_drawn_frames": Engine.get_frames_drawn(),
		"benchmark": benchmark,
		"pixel_probe": pixels,
		"seek_trace": seek_trace,
		"player_menu_progress": ui.get("player_menu_progress", {}),
		"thumbnail":
		{
			"available": Thumbnails.has(video.local_uri),
			"capture": video._thumbnail_result,
			"busy": video._thumbnail_busy
		},
		"diagnostic_2d": OS.get_cmdline_user_args().has("--mpv-diagnostic-2d"),
		"scope":
		"Production MPV/Godot ownership trace; independent pixel, audio and performance validation pending"
	}
	video.platform.save_mpv_player_report(request, JSON.stringify(report))


func record_seek(stage: String) -> void:
	var video := _owner_ref.get_ref() as Node3D
	if not is_instance_valid(video):
		return
	seek_trace.append(
		{
			"stage": stage,
			"time_ms": Time.get_ticks_msec(),
			"visible": video.panel != null and video.panel.visible,
			"frozen": video._is_frozen(),
			"capture_pending": video._freeze_request > 0,
			"session_id": video.media.session_id,
			"target_ms": video.control.target_ms,
			"displayed_pts_us": int(video._binding.ticket.get("pts_us", -1)),
			"freeze_copy_us": int(video._binding.ticket.get("freeze_copy_us", 0))
		}
	)
	if seek_trace.size() > 64:
		seek_trace.pop_front()
	write_report()


func open_requested(start_ms: int) -> void:
	open_trace = [{"stage": "requested", "time_ms": Time.get_ticks_msec(), "start_ms": start_ms}]


func open_dispatched(id: int) -> void:
	open_trace.append({"stage": "dispatched", "time_ms": Time.get_ticks_msec(), "session_id": id})


func first_pair_bound(pair: Dictionary) -> void:
	open_trace.append(
		{"stage": "first_pair_bound", "time_ms": Time.get_ticks_msec(), "pts_us": int(pair.pts_us)}
	)


func record_pair(pair: Dictionary) -> void:
	if request > 0 and not benchmark and pairs.size() < 128:
		pairs.append(pair.duplicate(true))
		write_report()


func record_state(report: Dictionary) -> void:
	if request > 0:
		status = report.duplicate(true)
		write_report()


func flush_report() -> void:
	next_report_us = 0
	write_report()
