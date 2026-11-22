extends SceneTree
const Policy := preload("res://scripts/playback_performance.gd")
const Layout := preload("res://scripts/video_layer_layout.gd")
const Layers := preload("res://scripts/video_layers.gd")
const Media := preload("res://scripts/mpv_media_state.gd")
const FrameDiagnostics := preload("res://scripts/playback_frame_diagnostics.gd")
var failures: Array[String] = []


class Rates:
	extends "res://scripts/xr_display.gd"
	var selected := 0.0

	func available_refresh_rates() -> Array[float]:
		return [72.0, 90.0, 120.0]

	func _apply_refresh_rate() -> void:
		selected = policy_refresh_rate if policy_refresh_rate > 0 else preferred_refresh_rate


class SwitchHost:
	extends RefCounted
	var calls: Array = []

	func mpv_supported() -> bool:
		return true

	func open_mpv_video(
		uri: String, position: int, _stereo: bool, _hw: bool, _tb: bool, exact: bool
	) -> int:
		calls.append({"uri": uri, "position": position, "exact": exact})
		return calls.size() + 100

	func close_mpv_video(_id: int) -> void:
		pass

	func set_mpv_playing(_id: int, _playing: bool) -> void:
		pass

	func set_mpv_audio(_id: int, _track: int, _volume: float, _muted: bool) -> bool:
		return true


class SwitchLayers:
	extends RefCounted
	var running := true

	func session_running() -> bool:
		return running

	func direct_wanted(_video: Node3D, _uri: String) -> bool:
		return false

	func release(_video: Node3D) -> void:
		pass

	func shutdown(_video: Node3D) -> void:
		pass

	func tick(_video: Node3D) -> void:
		pass


class TestLayers:
	extends "res://scripts/video_layers.gd"
	var running := true

	func runtime_running() -> bool:
		return running


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


class Backend:
	extends RefCounted
	var draws := 0
	var destroys := 0
	var invalidations := 0
	var sent := PackedFloat32Array()

	func create_video_image(_w: int, _h: int) -> bool:
		return true

	func draw_video_image(_texture: int, _lens: bool, _v: PackedFloat32Array) -> bool:
		draws += 1
		return true

	func set_video_layers(_count: int, v: PackedFloat32Array) -> bool:
		sent = v.duplicate()
		return true

	func video_layer_address(index: int) -> int:
		return index + 1

	func destroy_video_image() -> void:
		destroys += 1

	func invalidate_video_layer() -> void:
		invalidations += 1


class Display:
	extends RefCounted
	var shown := false

	func set_video_layer(value: bool) -> void:
		shown = value


class Movie:
	extends Node3D
	var panel := MeshInstance3D.new()
	var material := ShaderMaterial.new()
	var color_grade := preload("res://scripts/color_grade.gd").new()
	var texture: ImageTexture
	var platform: Object
	var media := Media.new()
	var packed_file := false
	var packed_alpha := false
	var sharpness := 0.0
	var stereo_focus_mode := 0
	var stereo_horizontal := 0.0
	var stereo_vertical := 0.0
	var geometry := 0
	var fisheye_fov := 180
	var stereo_sbs := true
	var stereo_half := false
	var top_bottom := false
	var swap_eyes := false
	var viewing_eye := 0
	var screen_curve := 0.0
	var layer_shown := false
	var surface_requested := false
	var force_shader_output := false
	var output_width_choice := -1
	var hdr_to_sdr := false
	var requested_play := true
	var fallbacks := 0

	func _ready() -> void:
		panel.mesh = QuadMesh.new()
		material.shader = preload("res://shaders/video_opaque_pair.gdshader")
		panel.material_override = material
		add_child(panel)
		var image := Image.create(64, 32, false, Image.FORMAT_RGBA8)
		texture = ImageTexture.create_from_image(image)

	func borrowed_color() -> RID:
		return texture.get_rid()

	func auto_layout_pending() -> bool:
		return false

	func surface_context() -> Dictionary:
		return {"session_id": media.session_id, "source_epoch": 1}

	func request_shader_fallback() -> void:
		fallbacks += 1

	func composition_geometry() -> Dictionary:
		return {
			"pose": global_transform, "size": Vector2(2, 1), "radius": 0.0, "sphere_radius": 50.0
		}


func _initialize() -> void:
	if preload("res://tests/support/test_result.gd").prepare(self):
		call_deferred("run")


func run() -> void:
	var sampling := FrameDiagnostics.new()
	var dimensions := Vector2i(4096, 2048)
	var slow := {}
	for n in range(501):
		slow = sampling.tick(root, 90, "surface", dimensions, true, 1, n * 20_000)
	check(
		(
			slow.get("fps") == 50.0
			and slow.get("menu_visible") == true
			and not slow.has("render_gpu_ms")
		),
		"The first slow window reports route and menu context and arms detailed timing"
	)
	for n in range(501, 1001):
		slow = sampling.tick(root, 90, "surface", dimensions, true, 1, n * 20_000)
	check(slow.has("render_gpu_ms"), "The next slow window includes rendering timing")
	check(
		(
			sampling.tick(root, 90, "surface", dimensions, false, 1, 20_020_000).is_empty()
			and not sampling._measured.is_valid()
		),
		"Changing the visible menu starts a fresh window and disables detailed timing"
	)
	sampling.stop()
	var rates := Rates.new()
	rates.preferred_refresh_rate = 120
	rates.update_playback_policy(true, true, true, false, 24, false, 0)
	rates.update_playback_policy(true, true, true, false, 24, false, 1500)
	check(rates.selected == 72, "24 fps settles at 72 Hz")
	check(rates.set_refresh_preference(90), "Refresh cap can change during playback")
	rates.update_playback_policy(true, true, true, false, 24, false, 2000)
	rates.update_playback_policy(true, true, true, false, 24, false, 3500)
	check(rates.selected == 72, "An unchanged video rate reapplies after changing its cap")
	var overlay_rates := Rates.new()
	overlay_rates.update_playback_policy(true, true, true, false, 59.94, true, 0, true)
	overlay_rates.update_playback_policy(true, true, true, false, 59.94, true, 4000, true)
	check(
		overlay_rates.performance.high, "Playback controls keep performance high over Surface video"
	)
	overlay_rates.update_playback_policy(true, true, true, false, 59.94, true, 4100)
	overlay_rates.update_playback_policy(true, true, true, false, 59.94, true, 7100)
	check(not overlay_rates.performance.high, "Hidden controls let Surface playback settle to low")
	for row in [
		[24.0, 120, 72],
		[29.97, 120, 90],
		[59.94, 120, 120],
		[60.0, 90, 0],
		[30.0, 72, 0],
		[NAN, 120, 0]
	]:
		check(
			Policy.video_rate(row[0], [72.0, 90.0, 120.0], row[1]) == row[2],
			"Refresh matching honors fractional rates and cap"
		)
	var policy := Policy.new()
	check(policy.tick(true, 120, 0).high, "Raises apply immediately")
	check(not policy.tick(false, 72, 100).has("high"), "A brief seek does not drop clocks")
	check(not policy.tick(true, 120, 200).has("high"), "Seek recovery cancels the pending drop")
	policy.tick(false, 72, 300)
	check(
		not policy.tick(false, 72, 3299).has("high"), "Lower demand must persist for three seconds"
	)
	check(policy.tick(false, 72, 3300).high == false, "Sustained idle drops clocks")
	var small := Layout.picture_size(
		Vector2i(8192, 4096), 2, 220, true, false, Vector2i(8192, 8192)
	)
	check(
		small.x <= 8192 and small.y <= 8192 and small.x * small.y <= 35389440,
		"Wide fisheye memory remains bounded"
	)
	check(
		is_equal_approx(Layout.fisheye_span(220).x, TAU),
		"Wide lenses retain the pixels behind the poles"
	)
	var shape := {
		"pose": Transform3D.IDENTITY, "size": Vector2(2, 1), "radius": 0.0, "sphere_radius": 50.0
	}
	var values := Layout.layers(
		shape, Transform3D.IDENTITY, 0, 180, true, false, false, 0, Vector2i(4096, 2048), 1, 1
	)
	check(
		(
			values.size() == 56
			and values[1] == 1
			and values[29] == 2
			and values[9] == 0
			and values[37] == 2048
		),
		"Stereo uses complete left/right crops of a shared image"
	)
	values = Layout.layers(
		shape, Transform3D.IDENTITY, 0, 180, true, true, true, 1, Vector2i(2048, 4096), 1, 1
	)
	check(
		values.size() == 28 and values[1] == 0 and values[10] == 2048,
		"Logical single-eye and swap preserve top-bottom packing"
	)
	check(
		not Layout.surface_flip("PXR Runtime", false) and Layout.surface_flip("Meta", false),
		"Surface orientation follows the runtime"
	)
	var movie := Movie.new()
	root.add_child(movie)
	var backend := Backend.new()
	var display := Display.new()
	movie.platform = backend
	movie.media.begin(11)
	movie.media.state = "playing"
	movie.media.last_pair = {
		"width": 64, "height": 32, "frame_id": 1, "source_epoch": 1, "slot_token": 1
	}
	var layers := TestLayers.new()
	layers.configure(false, movie, display)
	layers.provider = Layers.Provider.new()
	layers.bound = true
	layers.picture_supported = true
	layers.surface_supported = true
	layers.capacity = 2
	layers.limit = Vector2i(4096, 4096)
	layers.types = {0: true, 1: true, 2: true}
	layers.tick(movie)
	check(
		movie.layer_shown and backend.draws == 1 and display.shown,
		"Compatible playback uses the compositor"
	)
	for i in 20:
		layers.tick(movie)
	check(backend.draws == 1, "XR refreshes do not redraw a retained video frame")
	movie.position.x = 0.3
	layers.tick(movie)
	check(backend.draws == 1, "Moving a screen updates its pose without copying pixels")
	movie.media.session_id = 12
	layers.tick(movie)
	check(backend.draws == 2, "A new session cannot reuse another movie's first frame")
	movie.color_grade.select("Warm")
	layers.tick(movie)
	check(
		(
			not movie.layer_shown
			and layers.provider.addresses.is_empty()
			and movie.panel.material_override == movie.material
		),
		"Incompatible grading returns to the original shader"
	)
	movie.color_grade.select("Original")
	check(
		layers.direct_wanted(movie, "file:///sample.mp4"),
		"Known compatible formats may use a decoder Surface"
	)
	movie.output_width_choice = 4096
	check(
		not layers.direct_wanted(movie, "file:///sample.mp4"),
		"An explicit resolution limit retains the processing path"
	)
	movie.output_width_choice = -1
	movie.surface_requested = true
	movie.hdr_to_sdr = true
	check(layers.direct_wanted(movie, "file:///sample.mp4"), "Open can probe color on Surface")
	movie.media.playback = {"details": {"color_transfer": "bt.1886"}}
	layers.tick(movie)
	check(
		movie.fallbacks == 0 and layers.route == "surface", "SDR keeps Surface with HDR to SDR on"
	)
	for detail in [{"color_transfer": "pq"}, {"color_transfer": "hlg"}, {"dolby_profile5": true}]:
		movie.media.playback = {"details": detail}
		for enabled in [true, false]:
			movie.hdr_to_sdr = enabled
			movie.fallbacks = 0
			layers.tick(movie)
			check(movie.fallbacks == 1, "HDR requires processed color with either switch state")
	movie.fallbacks = 0
	movie.media.playback = {}
	movie.geometry = 1
	movie.packed_alpha = true
	check(
		layers.direct_wanted(movie, "file:///sample.mp4"),
		"VR180 SBS can open on its Surface with Alpha pending"
	)
	layers.tick(movie)
	check(
		movie.fallbacks == 0 and layers.route == "surface" and movie.layer_shown,
		"Alpha pending in VR180 SBS keeps the existing decoder Surface"
	)
	movie.geometry = 2
	check(
		Layout.compatible(movie) == "packed alpha needs shader",
		"Full SBS fisheye still requires the packed alpha shader"
	)
	movie.packed_alpha = false
	movie.geometry = 0
	movie.sharpness = 0.2
	layers.tick(movie)
	check(movie.fallbacks == 1, "A Surface reopens safely when picture settings need processing")
	layers.release(movie)
	check(
		backend.destroys == 1 and layers.image_size == Vector2i.ZERO,
		"Closing releases the picture swapchain"
	)
	layers.bound = true
	movie.sharpness = 0.0
	movie.fallbacks = 0
	layers.tick(movie)
	check(movie.layer_shown and layers.route == "surface", "Surface is active before XR stops")
	layers.stopping()
	check(
		backend.invalidations == 0 and backend.destroys == 2,
		"XR pause frees pictures without abandoning the decoder Surface"
	)
	layers.tick(movie)
	check(movie.fallbacks == 0 and not movie.layer_shown, "STOPPING hides even before xrEndSession")
	layers.running = false
	layers.tick(movie)
	check(movie.fallbacks == 0, "An inactive runtime does not request Surface fallback")
	layers.running = true
	layers.session_begun()
	layers.tick(movie)
	check(movie.fallbacks == 0, "An unbound resume can retry binding without reopening video")
	layers.bound = true
	layers.tick(movie)
	check(movie.fallbacks == 0 and layers.route == "surface", "Rebinding restores the same Surface")
	layers.stopping()
	layers.stopping(true)
	check(backend.invalidations == 1, "Session loss abandons handles even after a pause")
	layers.running = false
	layers.tick(movie)
	check(movie.fallbacks == 0, "Session loss waits until the runtime can present again")
	layers.running = true
	layers.session_begun()
	layers.bound = true
	layers.capacity = 1
	layers.tick(movie)
	check(movie.fallbacks == 1, "Session loss with insufficient resumed capacity requests fallback")
	layers.shutdown(movie)
	movie.queue_free()

	var video := preload("res://scripts/mpv_video_display.gd").new(false)
	root.add_child(video)
	video.set_process(false)
	video.set_hdr_to_sdr(true)
	video.media.playback = {"details": {"color_transfer": "bt.1886"}}
	check(not video.hdr_to_sdr_active(), "SDR tone mapping does not request performance headroom")
	video.media.playback = {"details": {"color_transfer": "pq"}}
	check(video.hdr_to_sdr_active(), "HDR tone mapping requests performance headroom")
	video.set_hdr_to_sdr(false)
	check(not video.hdr_to_sdr_active(), "Disabling tone mapping clears its performance demand")
	var switch_host := SwitchHost.new()
	video.platform = switch_host
	var switch_layers := SwitchLayers.new()
	video.layer_controller = switch_layers
	video.requested_play = false
	check(
		video.open_local("https://example.invalid/a", "Friendly title", 0, false, "original.mp4"),
		"Open a source through the production API"
	)
	video.surface_requested = true
	video.stick_scrubbing = true
	switch_layers.running = false
	video.request_shader_fallback()
	check(not video.stick_scrub_available(), "A pending Surface fallback suspends stick scrubbing")
	switch_layers.running = true
	video.set_process(true)
	await process_frame
	await process_frame
	video.set_process(false)
	check(
		switch_host.calls.size() == 1 and video.stick_scrub_available(),
		"A stale fallback on resume leaves the current Surface session open"
	)
	video.stick_scrubbing = false
	video.set_alpha(true)
	video.subtitle_delay_ms = 450
	video.stereo_horizontal = 2.0
	video.viewing_eye = 1
	video.control.observe(12345, 20000)
	var layer_id: int = video.media.session_id
	var error := '{"code":"MPV_FRAME_PIPELINE_FAILED","message":"MPV playback: nothing to play"}'
	video._on_error(layer_id, error)
	video._on_error(layer_id, error)
	await process_frame
	check(
		(
			switch_host.calls.size() == 2
			and switch_host.calls.back().position == 12345
			and switch_host.calls.back().exact
		),
		"Repeated terminal Surface errors reopen once at the exact playback position"
	)
	video._on_error(layer_id, error)
	await process_frame
	check(switch_host.calls.size() == 2, "A retired Surface cannot reopen the shader session")
	check(
		(
			video.packed_alpha
			and video.packed_alpha_forced
			and video.layout_basename() == "original.mp4"
			and video.stereo_horizontal == 2.0
			and video.viewing_eye == 1
			and video.subtitle_delay_ms == 450
			and not video.requested_play
		),
		"Switching retains forced alpha, original identity, subtitle timing and pause intent"
	)
	video.force_shader_output = false
	video.request_shader_fallback()
	video.open_local("https://example.invalid/b", "Next movie", 0, false)
	video.request_shader_fallback()
	await process_frame
	check(
		switch_host.calls.size() == 4 and video.local_uri == "https://example.invalid/b",
		"An old deferred switch cannot reopen or interfere with a newer movie"
	)
	video.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Playback performance failures: ", failures)
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
