extends SceneTree

const Memory := preload("res://scripts/file_mode_memory.gd")
const Video := preload("res://scripts/mpv_video_display.gd")
var failures: Array[String] = []
var checks := 0
var test_path := ""


class Interrupted:
	extends "res://scripts/file_mode_memory.gd"

	func _commit(_staged: String, target: String) -> Error:
		# Model the real Windows rename gap: old target removed, replacement fails.
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)
		return ERR_CANT_CREATE


class Host:
	extends RefCounted
	var calls: Array = []
	var next_id := 7

	func mpv_supported() -> bool:
		return true

	func open_mpv_video(
		uri: String,
		start: int,
		stereo: bool,
		vulkan: bool,
		_top_bottom: bool = false,
		_exact: bool = false
	) -> int:
		calls.append([uri, start, stereo, vulkan])
		return next_id

	func set_mpv_playing(_id: int, _playing: bool) -> void:
		pass

	func close_mpv_video(_id: int) -> void:
		pass

	func revise_mpv_video(
		_id: int, _stereo: bool, _position: int, _top_bottom: bool = false, _exact: bool = false
	) -> int:
		return 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


func write(path: String, data: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(data)
	file.close()


func read_again() -> RefCounted:
	var fresh := Memory.new(test_path)
	fresh.load_saved()
	return fresh


func check_retired_mode_migration() -> void:
	var path := test_path.path_join("retired-field-migration")
	DirAccess.make_dir_recursive_absolute(path)
	var uri := "file:///migration/packed_LR_180_FISHEYE_F180_alpha.mp4"
	var clean := {
		"geometry": 2,
		"stereo_sbs": true,
		"swap_eyes": false,
		"subtitle_delay_ms": 250.0,
		"audio_delay_ms": -100.0,
		"view_zoom": .2
	}
	var legacy := clean.duplicate(true)
	legacy.merge(
		{
			"profile": "320x320",
			"alpha_requested": true,
			"depth_requested": true,
			"auto_depth": true,
			"depth_strength": 2.0
		}
	)
	var encoded := JSON.stringify(
		{"sequence": 1, "entries": {Memory.key_for(uri): {"mode": legacy, "updated": 1}}}
	)
	write(
		path.path_join("file_modes_0.json"),
		JSON.stringify(
			{
				"schema_version": 1,
				"sequence": 1,
				"payload_json": encoded,
				"payload_sha256": encoded.sha256_text()
			}
		)
	)
	var memory := Memory.new(path)
	memory.load_saved()
	check(
		memory.lookup(uri) == clean and memory.dirty,
		"V1 per-file migration removes only retired fields"
	)
	check(legacy.alpha_requested, "Per-file migration does not mutate the caller's old record")
	check(memory.save() and memory.sequence == 2, "Migrated per-file mode commits once")
	var first := FileAccess.get_file_as_string(path.path_join("file_modes_0.json"))
	var second := FileAccess.get_file_as_string(path.path_join("file_modes_1.json"))
	var reloaded := Memory.new(path)
	reloaded.load_saved()
	check(
		reloaded.lookup(uri) == clean and not reloaded.dirty and reloaded.sequence == 2,
		"Reloading a migrated mode is idempotent"
	)
	check(
		(
			reloaded.save()
			and first == FileAccess.get_file_as_string(path.path_join("file_modes_0.json"))
			and second == FileAccess.get_file_as_string(path.path_join("file_modes_1.json"))
		),
		"Repeated per-file migration produces no extra write"
	)
	check(
		reloaded.remember(uri, legacy) and not reloaded.dirty,
		"Legacy caller fields are never written back"
	)


func check_profile_migration() -> void:
	var expected := {
		"layout_auto": false,
		"geometry": 2,
		"stereo_sbs": true,
		"swap_eyes": true,
		"top_bottom": true,
		"stereo_half": true,
		"fisheye_fov": 200,
		"viewing_eye": 2,
		"stereo_horizontal": 1.25,
		"stereo_vertical": -0.5,
		"view_horizontal": 0.1,
		"view_vertical": -0.1,
		"view_zoom": 0.2,
		"subtitle_below_screen": true,
		"subtitle_delay_ms": 275,
		"audio_delay_ms": -150,
		"external_subtitle_uri": "content://captions/document/字幕.srt",
		"subtitle_encodings": {"file:///captions.srt".sha256_text(): "Big5"},
		"track_choices":
		{
			"audio": {"id": 2, "language": "ja", "codec": "aac"},
			"subtitle": {"id": 3, "language": "zh", "title": "中文字幕"},
			"secondary_subtitle": {"id": 4, "language": "en", "codec": "subrip"}
		}
	}
	# JSON numbers reload as floats, including nested track IDs. Compare stored values.
	var expected_stored: Dictionary = JSON.parse_string(JSON.stringify(expected))
	check(Memory.valid_mode(expected), "Current modes need no profile field")
	for version in [1, 2]:
		var path := test_path.path_join("profile-migration-v%d" % version)
		DirAccess.make_dir_recursive_absolute(path)
		var entries := {}
		var uris: Array[String] = []
		var profiles: Array = [null, "512x288", "retired-shape", null, {"obsolete": true}]
		for index in profiles.size():
			var uri := "file:///migration/v%d/movie-%d.mp4" % [version, index]
			uris.append(uri)
			var legacy := expected.duplicate(true)
			if index > 0:
				legacy["profile"] = profiles[index]
			entries[Memory.key_for(uri)] = {"mode": legacy, "updated": index + 3}
		var invalid := expected.duplicate(true)
		invalid.geometry = 9
		entries[Memory.key_for("file:///invalid.mp4")] = {"mode": invalid, "updated": 7}
		var encoded := JSON.stringify({"sequence": 7, "entries": entries})
		var original := JSON.stringify(
			{
				"schema_version": version,
				"sequence": 7,
				"payload_json": encoded,
				"payload_sha256": encoded.sha256_text()
			}
		)
		var bank0 := path.path_join("file_modes_0.json")
		var bank1 := path.path_join("file_modes_1.json")
		write(bank0, original)
		var memory := Memory.new(path)
		memory.load_saved()
		check(
			memory.entries.size() == uris.size() and memory.dirty and memory.sequence == 7,
			"V%d migration retains missing/retired profiles and rejects invalid geometry" % version
		)
		for uri in uris:
			check(
				JSON.parse_string(JSON.stringify(memory.lookup(uri))) == expected_stored,
				(
					"V%d migration preserves geometry, stereo, captions, tracks and timing: %s"
					% [version, uri]
				)
			)
		var interrupted := Interrupted.new(path)
		interrupted.load_saved()
		check(
			not interrupted.save() and interrupted.dirty and interrupted.sequence == 7,
			"Interrupted v%d migration remains retryable" % version
		)
		var retry := Memory.new(path)
		retry.load_saved()
		var saved_ok := retry.save()
		check(
			(
				JSON.parse_string(JSON.stringify(retry.lookup(uris[0]))) == expected_stored
				and saved_ok
				and retry.sequence == 8
			),
			"V%d migration retries from the intact legacy bank" % version
		)
		check(
			FileAccess.get_file_as_string(bank0) == original,
			"V%d migration preserves the previous checksummed generation" % version
		)
		if not saved_ok:
			continue
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(bank1))
		check(saved.schema_version == 3, "V%d migration writes schema 3" % version)
		var payload: Dictionary = JSON.parse_string(saved.payload_json)
		check(
			payload.entries.values().all(func(entry): return entry.mode == expected_stored),
			"V%d migration never writes a retired profile back" % version
		)
		var reloaded := Memory.new(path)
		reloaded.load_saved()
		var committed := FileAccess.get_file_as_string(bank1)
		check(
			(
				not reloaded.dirty
				and reloaded.sequence == 8
				and reloaded.save()
				and FileAccess.get_file_as_string(bank1) == committed
			),
			"V%d migration is idempotent after reload" % version
		)
		write(bank1, "{interrupted")
		var fallback := Memory.new(path)
		fallback.load_saved()
		check(
			(
				JSON.parse_string(JSON.stringify(fallback.lookup(uris[0]))) == expected_stored
				and fallback.sequence == 7
				and fallback.dirty
			),
			"Corrupt v3 bank falls back to v%d without losing preferences" % version
		)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	call_deferred("_run")


func _run() -> void:
	test_path = ProjectSettings.globalize_path(
		"res://../../build/tests/godot/mode-memory-host/" + str(Time.get_ticks_usec())
	)
	DirAccess.make_dir_recursive_absolute(test_path)
	check_retired_mode_migration()
	check_profile_migration()
	var uri := "content://local.documents/document/字幕%20VideoA"
	var mode := {"geometry": 1, "stereo_sbs": true, "swap_eyes": true}
	var memory := Memory.new(test_path)
	memory.load_saved()
	check(
		memory.sequence == 0 and memory.lookup(uri).is_empty(), "Missing preferences start safely"
	)
	check(
		Memory.key_for(uri) != Memory.key_for(uri.to_lower()),
		"Opaque content URI retains case-sensitive identity"
	)
	check(
		(
			Memory.key_for("http://127.0.0.1:4242/t/v.mp4").is_empty()
			and Memory.key_for("").is_empty()
			and Memory.key_for("ftp://x/v").is_empty()
			and Memory.key_for("cloud://retired-account/video.mp4").is_empty()
		),
		"Per-run loopback proxy and unknown schemes are not persisted"
	)
	check(
		(
			not Memory.key_for("smb://server-id/share/v.mp4").is_empty()
			and not Memory.key_for("http://192.168.1.5/1.mp4").is_empty()
		),
		"Stable SMB and DLNA library URIs keep per-file modes"
	)
	check(
		not Memory.key_for("smb://mount-id/中文%20VR.mp4").is_empty(),
		"SMB identity survives proxy URL changes"
	)
	check(
		not memory.remember(uri, {}) and not memory.remember("http://127.0.0.1:4242/t/v.mp4", mode),
		"Invalid modes/proxy source cannot enter memory"
	)
	for mutation in [{"geometry": 4}, {"geometry": 0.5}, {"geometry": NAN}, {"stereo_sbs": "true"}]:
		var invalid := mode.duplicate(true)
		invalid.merge(mutation, true)
		check(not memory.remember(uri, invalid), "Reject invalid saved mode " + str(mutation))
	check(memory.remember(uri, mode) and memory.save(), "Initial generation writes and commits")
	check(
		read_again().lookup(uri) == mode and read_again().sequence == 1,
		"Fresh object loads first committed mode"
	)
	var exposed: Dictionary = memory.lookup(uri)
	exposed.geometry = 0
	check(memory.lookup(uri) == mode, "Caller cannot mutate saved settings through lookup")
	check(
		memory.remember(uri, mode) and memory.save() and memory.sequence == 1,
		"Unchanged controls avoid unnecessary writes"
	)
	var newer := mode.duplicate(true)
	newer.geometry = 2
	check(
		memory.remember(uri, newer) and memory.save() and read_again().lookup(uri) == newer,
		"Second bank wins by validated sequence"
	)
	var bank0 := test_path.path_join("file_modes_0.json")
	var bank1 := test_path.path_join("file_modes_1.json")
	var intact := FileAccess.get_file_as_string(bank1)
	write(bank1, '{"interrupted":')
	check(
		read_again().lookup(uri) == mode,
		"Truncated newest generation falls back to previous valid bank"
	)
	write(bank1, intact)
	var envelope: Dictionary = JSON.parse_string(intact)
	envelope.sequence = 99
	write(bank1, JSON.stringify(envelope))
	check(read_again().lookup(uri) == mode, "Sequence tampering cannot promote an older payload")
	envelope = JSON.parse_string(intact)
	envelope.payload_json += " "
	write(bank1, JSON.stringify(envelope))
	check(read_again().lookup(uri) == mode, "Checksum rejects modified payload")
	envelope = JSON.parse_string(intact)
	envelope.schema_version = Memory.VERSION + 1
	write(bank1, JSON.stringify(envelope))
	check(read_again().lookup(uri) == mode, "Unknown schema does not reinterpret settings")
	var future := read_again()
	future.remember(uri, newer)
	var future_bytes := FileAccess.get_file_as_string(bank1)
	check(
		(
			future.read_only
			and not future.save()
			and FileAccess.get_file_as_string(bank1) == future_bytes
		),
		"A downgraded reader cannot overwrite newer configuration schema"
	)
	write(bank1, intact)
	var broken := Interrupted.new(test_path)
	broken.load_saved()
	broken.remember(uri, mode)
	check(
		not broken.save() and broken.dirty and broken.sequence == 2,
		"Failed commit retains pending choices and old in-memory generation"
	)
	check(
		not FileAccess.file_exists(bank0) and read_again().lookup(uri) == newer,
		"Real target-removal gap retains another valid generation"
	)
	check(
		FileAccess.file_exists(bank0 + ".tmp") and read_again().sequence == 2,
		"Uncommitted staging file is never loaded"
	)
	memory = read_again()
	check(
		memory.remember(uri, mode) and memory.save() and read_again().sequence == 3,
		"Successful retry commits after interrupted write"
	)
	var disk := FileAccess.get_file_as_string(bank0) + FileAccess.get_file_as_string(bank1)
	check(not disk.contains(uri), "Format memory stores a hash rather than document identifiers")
	for index in 129:
		memory.remember("file:///movie_%d.mp4" % index, mode)
		check(memory.save(), "Bounded map entry must save")
	check(
		(
			memory.entries.size() == 128
			and memory.lookup("file:///movie_0.mp4").is_empty()
			and not memory.lookup("file:///movie_128.mp4").is_empty()
		),
		"Oldest updated mode is evicted at the fixed limit"
	)
	check(read_again().entries.size() == 128, "Bounded map survives reload")
	# A real Video instance exercises restore before native open and live eye swap.
	var video := Video.new()
	root.add_child(video)
	video.set_process(false)
	video.mode_memory = Memory.new(test_path.path_join("integration"))
	video.mode_memory.remember(uri, newer)
	video.mode_memory.save()
	var host := Host.new()
	video.platform = host
	check(video.open_local(uri, "Selected video"), "Restored source opens")
	# Projection, stereo and eye order are restored; Alpha always starts off (player controls switch it on).
	check(
		(
			host.calls.back() == [uri, 0, true, true]
			and video.geometry == 2
			and video.swap_eyes
			and not video.alpha_wanted()
		),
		"Projection and eye order restore without a buffer-size argument"
	)
	check(
		not video.alpha_enabled and not video.panel.visible,
		"Remembered Alpha intent cannot expose passthrough before a complete pair"
	)
	video.test_set_waiting_for_frame(false)
	video.media.generation = 4
	check(
		(
			video.toggle_eye_order()
			and not video.swap_eyes
			and video.media.session_id == 7
			and video.media.generation == 4
		),
		"Eye order is a shader choice and preserves source/processing generation"
	)
	var loaded := Memory.new(test_path.path_join("integration"))
	loaded.load_saved()
	check(not loaded.lookup(uri).swap_eyes, "Manual eye order persists for the exact file")
	video.set_stereo_layout(4)
	loaded = Memory.new(test_path.path_join("integration"))
	loaded.load_saved()
	check(
		(
			loaded.lookup(uri).stereo_sbs
			and loaded.lookup(uri).top_bottom
			and loaded.lookup(uri).stereo_half
		),
		"Manual stereo layout still persists after inference retirement"
	)
	video.stereo_sbs = false
	check(not video.toggle_eye_order(), "Mono source has no L/R swap")
	video.geometry = 0
	check(
		(
			video.open_local(uri, "Calibration", 1234, false)
			and host.calls.back()[3]
			and video.geometry == 0
		),
		"Explicit diagnostic open bypasses per-file settings"
	)
	var before := video.mode_memory.sequence
	video.set_alpha(true)
	check(video.mode_memory.sequence == before, "Diagnostic controls do not rewrite user memory")
	video._remember_file = true
	video.geometry = 1
	video._reopen_after_context_loss(uri, "Recovered", 1234, true)
	check(
		video.geometry == 1 and video._remember_file and host.calls.back()[1] == 1234,
		"Context recovery retains unsaved live choices and memory eligibility"
	)
	host.next_id = -1
	video.open_local(uri, "Failed open")
	before = video.mode_memory.sequence
	video.set_alpha(false)
	check(
		video.mode_memory.sequence == before,
		"Rejected source cannot overwrite its remembered settings"
	)
	# A file without a remembered mode: explicit markers win, ambiguous 2:1 stays flat.
	host.next_id = 7
	check(
		(
			video.open_local("file:///v/show_RL_180.mp4", "show_RL_180.mp4")
			and host.calls.back()[2] == true
			and video.geometry == 1
			and video.swap_eyes
			and video._layout_pending == null
		),
		"Name markers reach native at open"
	)
	check(
		(
			video.open_local("file:///v/clip.mp4", "clip.mp4")
			and host.calls.back()[2] == false
			and video._layout_pending != null
		),
		"Unmarked name waits for the frame"
	)
	video.media.format = {
		"width": 8192, "height": 4096, "pixel_aspect": 1.0, "unapplied_rotation_degrees": 0
	}
	video._complete_layout()
	check(
		(
			video.geometry == 0
			and not video.stereo_sbs
			and video._pending_revision.is_empty()
			and video._layout_pending == null
		),
		"Unmarked 2:1 stays flat mono without restarting processing"
	)
	for lock in [
		{"geometry": 0, "layout": 0, "depth": false, "fisheye_fov": 180},
		{"geometry": 0, "layout": 0, "depth": true, "fisheye_fov": 180},
		{"geometry": 1, "layout": 1, "depth": false, "fisheye_fov": 180},
		{"geometry": 2, "layout": 4, "depth": false, "fisheye_fov": 200},
		{"geometry": 3, "layout": 2, "depth": false, "fisheye_fov": 180}
	]:
		video.load_mode_lock(lock)
		var expected: Dictionary = lock.duplicate()
		expected.depth = false
		check(
			(
				video.open_local(
					"file:///v/locked_%d.mp4" % lock.geometry, "locked_%d.mp4" % lock.geometry
				)
				and video.current_lock() == expected
				and video._layout_pending == null
			),
			"Unmarked source opens with locked mode %d" % lock.geometry
		)
		video.media.format = {"width": 8192, "height": 4096, "pixel_aspect": 1.0}
		video._complete_layout()
		check(
			(
				video.current_lock() == expected
				and video.mode_lock == expected
				and video._pending_revision.is_empty()
			),
			"First 2:1 frame preserves locked mode %d" % lock.geometry
		)
	video.load_mode_lock({})
	check(
		(
			video.open_local("file:///v/clip_alpha.mp4", "clip_alpha.mp4")
			and host.calls.back().size() == 4
			and not video.packed_file
		),
		"An old live-matting filename cannot request inference"
	)
	var packed_uri := "file:///v/clip_LR_180_FISHEYE_F180_alpha.mp4"
	check(
		(
			video.open_local(packed_uri, "clip_LR_180_FISHEYE_F180_alpha.mp4")
			and host.calls.back().size() == 4
			and video.packed_file
			and video.alpha_wanted()
			and video.geometry == 2
			and video.stereo_sbs
		),
		"Packed output shows its own mask with its packed alpha"
	)
	var opens := host.calls.size()
	check(
		video.set_alpha(false) and not video.alpha_wanted() and host.calls.size() == opens,
		"Alpha switch toggles the packed mask in place"
	)
	video.mode_memory.remember(packed_uri, {"geometry": 0, "stereo_sbs": false, "swap_eyes": false})
	check(
		(
			video.open_local(packed_uri, "clip_LR_180_FISHEYE_F180_alpha.mp4")
			and video.geometry == 0
			and not video.stereo_sbs
		),
		"The user's remembered mode wins over the name"
	)
	video.media.format = {"width": 8192, "height": 4096, "pixel_aspect": 1.0}
	video._complete_layout()
	check(
		video.geometry == 0 and not video.stereo_sbs and video._pending_revision.is_empty(),
		"First 2:1 frame preserves the per-file choice over explicit VR naming"
	)
	video.queue_free()
	await process_frame
	var half_uri := "file:///v/half.webm"
	var half_mode := mode.duplicate(true)
	half_mode.merge({"geometry": 2, "top_bottom": true, "stereo_half": true}, true)
	check(
		(
			memory.remember(half_uri, half_mode)
			and memory.save()
			and read_again().lookup(half_uri) == half_mode
		),
		"Half packing survives both checksummed banks"
	)
	var report := {
		"state": "passed" if failures.is_empty() else "failed",
		"checks": checks,
		"scope":
		"Actual host files and Godot player with mocked MPV; Android storage/power loss/URI permission not exercised",
		"failures": failures
	}
	write(test_path.path_join("verification.json"), JSON.stringify(report, "\t"))
	print("File mode memory host checks: %s (%d), evidence=%s" % [report.state, checks, test_path])
	for failure in failures:
		push_error(failure)
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
