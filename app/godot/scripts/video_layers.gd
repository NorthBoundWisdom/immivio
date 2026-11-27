extends RefCounted
## Video-only compositor provider, adapted from Thru3D 959abc2.
const Platform := preload("res://scripts/platform_methods.gd")
const Layout := preload("res://scripts/video_layer_layout.gd")
const Quality := preload("res://scripts/display_quality.gd")
const HOLE := preload("res://shaders/video_layer_hole.gdshader")


class Provider:
	extends OpenXRExtensionWrapper
	var addresses := PackedInt64Array()

	func _get_composition_layer_count() -> int:
		return addresses.size()

	func _get_composition_layer(index: int) -> int:
		return addresses[index] if index >= 0 and index < addresses.size() else 0

	func _get_composition_layer_order(_index: int) -> int:
		return -32


var api: OpenXRAPIExtension
var provider: Provider
var platform: Object
var origin: Node3D
var display: RefCounted
var bound := false
var surface_supported := false
var picture_supported := false
var image_layout := false
var surface_flip := true
var limit := Vector2i.ZERO
var capacity := 0
var types := {0: false, 1: false, 2: false}
var generation := 0
var session := 0
var space := 0
var hole := ShaderMaterial.new()
var image_size := Vector2i.ZERO
var copied_key: Array = []
var copied_frames := 0
var previous: PackedFloat32Array = PackedFloat32Array()
var route := "shader"
var reason := "runtime unavailable"
var failed_session := 0
var failed_since := -1
var allowed := true
var surface_allowed := true
var bypass_picture_copy := false
var force_picture := false
var _cadence_ms := -250
var _cadence_supported := false
var _cadence_active := false
var _session_stopped := false
var _surface_session_lost := false


func runtime_running() -> bool:
	return api != null and api.is_running()


func session_running() -> bool:
	return runtime_running() and not _session_stopped


func session_begun() -> void:
	_session_stopped = false


func _sync_cadence(active: bool) -> void:
	if not Platform.supports(platform, "set_video_vsync"):
		return
	if not active or not _cadence_supported or api == null:
		if _cadence_active:
			platform.set_video_vsync(0, 0, 0)
		_cadence_active = false
		return
	var now := Time.get_ticks_msec()
	if now - _cadence_ms < 250:
		return
	_cadence_ms = now
	var xr := XRServer.find_interface("OpenXR")
	var rate: float = xr.display_refresh_rate if xr and xr.is_initialized() else 0.0
	if rate <= 0:
		if _cadence_active:
			platform.set_video_vsync(0, 0, 0)
		_cadence_active = false
		return
	platform.set_video_vsync(api.get_predicted_display_time(), roundi(1e9 / rate), 16000000)
	_cadence_active = true


func configure(xr_enabled: bool, xr_origin: Node3D, target: RefCounted) -> void:
	origin = xr_origin
	display = target
	hole.shader = HOLE
	hole.render_priority = -20
	if not xr_enabled or OS.get_name() != "Android":
		return
	api = OpenXRAPIExtension.new()
	if api.is_running():
		api = null
		return
	provider = Provider.new()
	api.register_composition_layer_provider(provider)


func update_session(value: Object) -> void:
	platform = value
	if api == null or not Platform.supports(platform, "bind_video_layer"):
		return
	if not runtime_running():
		if bound:
			stopping()
		# A later running transition can also be observed without a signal.
		_session_stopped = false
		return
	if _session_stopped:
		return
	var current := api.get_session()
	var play_space := api.get_play_space()
	if current == session and play_space == space and bound:
		return
	if current != session:
		_surface_session_lost = _surface_session_lost or (session != 0 and current != 0)
		generation += 1
		copied_key.clear()
		failed_since = -1
		image_size = Vector2i.ZERO
	session = current
	space = play_space
	bound = platform.bind_video_layer(
		api.get_instance(), session, api.get_instance_proc_addr("xrGetInstanceProcAddr"), space
	)
	if not bound:
		return
	var limits := str(platform.video_layer_limits()).split(" ", false)
	if limits.size() < 5:
		bound = false
		return
	capacity = mini(2, maxi(0, int(limits[0]) - 4))
	for pair in [
		[0, OpenXRCompositionLayerQuad.new()],
		[1, OpenXRCompositionLayerCylinder.new()],
		[2, OpenXRCompositionLayerEquirect.new()]
	]:
		types[pair[0]] = pair[1].is_natively_supported()
		pair[1].free()
	limit = Vector2i(int(limits[1]), int(limits[2]))
	surface_supported = limits[3] == "1"
	picture_supported = limits[4] == "1"
	image_layout = (
		Engine.has_singleton("OpenXRFbCompositionLayerImageLayoutExtension")
		and Engine.get_singleton("OpenXRFbCompositionLayerImageLayoutExtension").is_enabled()
	)
	var xr := XRServer.find_interface("OpenXR")
	var info: Dictionary = xr.get_system_info() if xr else {}
	var runtime := str(info.get("XRRuntimeName", "")).to_lower()
	_cadence_supported = (
		not OS.has_feature("pico")
		and (runtime.begins_with("oculus") or runtime.begins_with("meta"))
	)
	surface_flip = Layout.surface_flip(
		str(info.get("XRRuntimeName", "")),
		OS.has_feature("pico"),
		str(info.get("OpenXRSystemName", ""))
	)
	# The Meta Surface convention needs image-layout support; never guess an unsupported flip.
	if surface_flip and not image_layout:
		surface_supported = false
	previous = PackedFloat32Array()


func stopping(session_lost: bool = false) -> void:
	_session_stopped = true
	_surface_session_lost = _surface_session_lost or session_lost
	if provider:
		provider.addresses = PackedInt64Array()
	# xrEndSession does not destroy its swapchains. Free the picture allocation, but
	# keep the decoder's Surface until acknowledged close or actual session loss.
	if bound:
		platform.set_video_layers(0, PackedFloat32Array())
		if Platform.supports(platform, "destroy_video_image"):
			platform.destroy_video_image()
	if session_lost and Platform.supports(platform, "invalidate_video_layer"):
		platform.invalidate_video_layer()
	previous = PackedFloat32Array()
	_cadence_ms = -250
	_sync_cadence(false)
	bound = false
	copied_key.clear()
	failed_since = -1
	image_size = Vector2i.ZERO


func direct_wanted(video: Node3D, uri: String) -> bool:
	if (
		not surface_allowed
		or not allowed
		or not bound
		or not surface_supported
		or capacity < (2 if video.stereo_sbs and video.viewing_eye == 0 else 1)
		or video.force_shader_output
	):
		return false
	var kind := (
		1 if video.geometry == 0 and video.screen_curve > 0 else 0 if video.geometry == 0 else 2
	)
	if not types.get(kind, false):
		return false
	if uri.begins_with("externalvideo://"):
		return false
	if video.geometry == 2 or not Layout.compatible(video).is_empty():
		return false
	# Keep image-based stereo analysis available for unmarked content.
	return (
		not video.auto_layout_pending() or video.Naming.has_layout_marker(video.layout_basename())
	)


func shutdown(video: Node3D) -> void:
	release(video)
	if provider:
		if api and api.is_running():
			# This controller belongs to the app's XR scene. Godot rejects unregister
			# while running; stop its interface before freeing the native provider.
			stopping(true)
			var xr := XRServer.find_interface("OpenXR")
			if xr:
				xr.uninitialize()
		if api:
			api.unregister_composition_layer_provider(provider)
		provider.free()
		provider = null
	api = null


func release(video: Node3D) -> void:
	hide(video)
	_surface_session_lost = false
	if bound and image_size != Vector2i.ZERO and Platform.supports(platform, "destroy_video_image"):
		platform.destroy_video_image()
	image_size = Vector2i.ZERO
	copied_key.clear()
	failed_since = -1


func hide(video: Node3D) -> void:
	if provider:
		provider.addresses = PackedInt64Array()
	if bound and previous.size() > 0:
		platform.set_video_layers(0, PackedFloat32Array())
	previous = PackedFloat32Array()
	if video.panel and video.panel.material_override == hole:
		video.panel.material_override = video.material
	video.layer_shown = false
	_sync_cadence(false)
	route = "shader"
	if display:
		display.set_video_layer(false)


func tick(video: Node3D) -> void:
	update_session(video.platform)
	if not session_running():
		hide(video)
		return
	var insufficient_capacity := (
		bound and capacity < (2 if video.stereo_sbs and video.viewing_eye == 0 else 1)
	)
	if (
		not allowed
		or not bound
		or insufficient_capacity
		or (video.surface_requested and _surface_session_lost)
	):
		hide(video)
		if (
			video.surface_requested
			and (not allowed or insufficient_capacity or _surface_session_lost)
		):
			video.request_shader_fallback()
		return
	if not video.panel.visible or not video.media.accepts(video.media.session_id):
		hide(video)
		return
	reason = Layout.compatible(video)
	var kind := (
		1 if video.geometry == 0 and video.screen_curve > 0 else 0 if video.geometry == 0 else 2
	)
	if not types.get(kind, false):
		reason = "projection unavailable"
	if video.surface_requested:
		if video.geometry == 2:
			reason = "fisheye needs frame remapping"
		if video.media.is_hdr():
			reason = "HDR needs processed color"
		var width_limit := Quality.output_width(video.output_width_choice, video.low_end_gpu)
		if reason.is_empty() and width_limit > 0 and int(video.media.format.width) > width_limit:
			reason = "output width limit needs scaling"
		if not reason.is_empty():
			hide(video)
			video.request_shader_fallback()
			return
		if video.surface_context().is_empty() and previous.is_empty():
			return
		route = "surface"
	else:
		if bypass_picture_copy and video.geometry != 2 and not force_picture:
			# The same RGBA frame can be sampled by the eye shaders. On this
			# GPU tier, avoid copying the full image into a second XR layer
			# while the UI compositor also has work to submit.
			reason = "picture copy bypassed while controls are visible"
			hide(video)
			return
		if (
			not reason.is_empty()
			or not picture_supported
			or failed_session == video.media.session_id
		):
			hide(video)
			return
		var pair: Dictionary = video.media.last_pair
		if pair.is_empty() or not video.borrowed_color().is_valid():
			hide(video)
			return
		var size := Vector2i(int(pair.width), int(pair.height))
		var lens: bool = video.geometry == 2
		var target := Layout.picture_size(
			size, video.geometry, video.fisheye_fov, video.stereo_sbs, video.top_bottom, limit
		)
		if target == Vector2i.ZERO:
			hide(video)
			return
		var uv: Array = pair.get("color_uv_scale", [1.0, 1.0])
		var context := [
			generation,
			video.media.session_id,
			pair.get("mpv_source_handle", 0),
			video.media.generation,
			pair.get("source_epoch", 0),
			size,
			target,
			video.geometry,
			video.fisheye_fov,
			video.stereo_half,
			video.stereo_sbs,
			video.top_bottom,
			uv
		]
		var key := [
			context,
			pair.get("slot_token", 0),
			pair.get("frame_id", 0),
			pair.get("frozen_frame_id", 0)
		]
		if key != copied_key:
			if image_size != target:
				if not platform.create_video_image(target.x, target.y):
					failed_session = video.media.session_id
					hide(video)
					return
				image_size = target
				copied_key.clear()
				previous = PackedFloat32Array()
			var span := Layout.fisheye_span(video.fisheye_fov)
			var parameters := PackedFloat32Array(
				[
					0 if not video.stereo_sbs else (2 if video.top_bottom else 1),
					1 if video.stereo_half else 0,
					video.fisheye_fov,
					span.x,
					span.y,
					size.x,
					size.y,
					uv[0],
					uv[1],
					0 if image_layout else 1
				]
			)
			var draw: int = platform.try_draw_video_image(
				RenderingServer.texture_get_native_handle(video.borrowed_color()), lens, parameters
			)
			if draw > 0:
				failed_since = -1
				copied_key = key
				copied_frames += 1
			else:
				var now := Time.get_ticks_msec()
				if failed_since < 0:
					failed_since = now
				if draw < 0 or now - failed_since > 2000:
					failed_session = video.media.session_id
					hide(video)
					return
				# A zero-timeout wait may miss one refresh. Keep submitting the last
				# released image only while its source and projection still match.
				if previous.is_empty() or copied_key.is_empty() or copied_key[0] != context:
					hide(video)
					return
		route = "fisheye" if lens else "picture"
	var geometry: Dictionary = video.composition_geometry()
	var values := Layout.layers(
		geometry,
		origin.global_transform,
		video.geometry,
		video.fisheye_fov,
		video.stereo_sbs,
		video.top_bottom,
		video.swap_eyes,
		video.viewing_eye,
		Vector2i(4096, 4096) if video.surface_requested else image_size,
		0 if video.surface_requested else 1,
		-1 if not image_layout else (1 if not video.surface_requested or surface_flip else 0)
	)
	if values.is_empty() or values.size() / 28 > capacity:
		hide(video)
		if video.surface_requested:
			video.request_shader_fallback()
		return
	if previous != values:
		if not platform.set_video_layers(values.size() / 28, values):
			hide(video)
			if video.surface_requested:
				video.request_shader_fallback()
			return
		var pointers := PackedInt64Array()
		for i in values.size() / 28:
			var address: int = platform.video_layer_address(i)
			if address <= 0:
				hide(video)
				if video.surface_requested:
					video.request_shader_fallback()
				return
			pointers.append(address)
		provider.addresses = pointers
		previous = values
	video.panel.material_override = hole
	video.layer_shown = true
	_sync_cadence(
		video.surface_requested and video.requested_play and video.media.state == "playing"
	)
	if display:
		display.set_video_layer(true)


func snapshot() -> Dictionary:
	return {
		"route": route,
		"reason": reason,
		"bound": bound,
		"copies": copied_frames,
		"image_size": image_size,
		"surface_supported": surface_supported,
		"capacity": capacity,
		"generation": generation
	}
