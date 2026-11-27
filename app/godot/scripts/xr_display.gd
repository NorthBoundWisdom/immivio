class_name XrDisplay extends RefCounted

signal status_changed
signal presence_changed(present: bool)

var xr: XRInterface
var viewport: Viewport
var environment: Environment
var preview := true
var requested_passthrough := false
var applied_passthrough := false
var session_state := "uninitialized"
var error_code := ""
var render_scale := 1.0
var preferred_refresh_rate := 72.0
var match_video_rate := false
var applied_refresh_rate := 0.0
var msaa_3d := Viewport.MSAA_2X
var flat_msaa_3d := Viewport.MSAA_4X
var video_layer := false
var backdrop: MeshInstance3D
var backdrop_material: ShaderMaterial
var _backdrop_source: Material
var scenery: Sky
var scenery_rotation := Vector3.ZERO


func attach_video_backdrop(camera: Camera3D) -> void:
	backdrop = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 900
	sphere.height = 1800
	backdrop.mesh = sphere
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(backdrop)
	backdrop.visible = false


func set_video_layer(shown: bool) -> void:
	if shown == video_layer:
		return
	video_layer = shown
	if environment:
		_set_background(applied_passthrough)


func _sync_video_backdrop() -> void:
	if not backdrop:
		return
	backdrop.visible = video_layer and not applied_passthrough
	if not backdrop.visible:
		backdrop.material_override = null
		backdrop_material = null
		_backdrop_source = null
		return
	var source: Material = scenery.sky_material if scenery else null
	if source != _backdrop_source or backdrop_material == null:
		_backdrop_source = source
		backdrop_material = ShaderMaterial.new()
		if source is ShaderMaterial:
			var code: String = (
				source
				. shader
				. code
				. replace(
					"shader_type sky;",
					"shader_type spatial;\nrender_mode unshaded, cull_front, shadows_disabled, fog_disabled;\nuniform mat3 backdrop_orientation;\nvarying vec3 backdrop_direction;\nvoid vertex(){backdrop_direction=mat3(MODEL_MATRIX)*VERTEX;}"
				)
			)
			code = (
				code
				. replace("void sky()", "void fragment()")
				. replace("EYEDIR", "(backdrop_orientation * backdrop_direction)")
				. replace("COLOR =", "ALBEDO =")
			)
			var shader := Shader.new()
			shader.code = code
			backdrop_material.shader = shader
		else:
			backdrop_material.shader = preload("res://shaders/layer_backdrop.gdshader")
		backdrop.material_override = backdrop_material
	if source is ShaderMaterial:
		for uniform in source.shader.get_shader_uniform_list():
			backdrop_material.set_shader_parameter(
				uniform.name, source.get_shader_parameter(uniform.name)
			)
		backdrop_material.set_shader_parameter(
			"backdrop_orientation", Basis.from_euler(scenery_rotation).inverse()
		)
	else:
		backdrop_material.set_shader_parameter(
			"orientation", Basis.from_euler(scenery_rotation).inverse()
		)
		backdrop_material.set_shader_parameter(
			"has_panorama", source is PanoramaSkyMaterial and source.panorama != null
		)
		backdrop_material.set_shader_parameter(
			"panorama", source.panorama if source is PanoramaSkyMaterial else null
		)
		backdrop_material.set_shader_parameter(
			"energy_multiplier", source.energy_multiplier if source is PanoramaSkyMaterial else 1.0
		)


func set_scenery(value: Sky, yaw_degrees: float = 0.0, force: bool = true) -> void:
	# PanoramaSkyMaterial puts the texture seam along the viewer's default -Z axis.
	# Treat 0 degrees as the image centre facing forward; keep user rotation relative to it.
	var rotation := Vector3(0, deg_to_rad(yaw_degrees) + PI, 0)
	if not force and value == scenery and rotation == scenery_rotation:
		return
	scenery = value
	scenery_rotation = rotation
	if environment:
		_set_background(applied_passthrough)


func configure(
	target_viewport: Viewport,
	target_environment: Environment,
	interface: XRInterface,
	desktop_preview: bool
) -> bool:
	viewport = target_viewport
	environment = target_environment
	xr = interface
	preview = desktop_preview
	# Smooth geometry silhouettes in the eye buffers, including the video quad.
	# Source-video sharpening cannot antialias the mesh boundary.
	viewport.msaa_3d = msaa_3d
	_set_background(false)
	if preview:
		session_state = "desktop_preview"
		status_changed.emit()
		return true
	if xr != null and "render_target_size_multiplier" in xr:
		xr.render_target_size_multiplier = render_scale
	if xr == null or (not xr.is_initialized() and not xr.initialize()):
		error_code = "XR_INITIALIZATION_FAILED"
		session_state = "failed"
		DiagnosticLog.record("xr_initialization_failed")
		status_changed.emit()
		return false
	viewport.use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for event in [
		"session_begun",
		"session_focussed",
		"session_visible",
		"session_synchronized",
		"session_stopping",
		"session_loss_pending",
		"instance_exiting"
	]:
		if xr.has_signal(event):
			xr.connect(event, _on_session_event.bind(event))
	if xr.has_signal("user_presence_changed"):
		xr.connect("user_presence_changed", _on_presence_changed)
	session_state = "initialized"
	DiagnosticLog.record("xr_initialized", capabilities())
	status_changed.emit()
	return true


func supports_passthrough() -> bool:
	return (
		not preview
		and xr != null
		and xr.is_initialized()
		and XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in xr.get_supported_environment_blend_modes()
	)


func set_flat_surface_visible(flat_visible: bool) -> void:
	if not viewport or not preview:
		return
	var desired: int = flat_msaa_3d if flat_visible else msaa_3d
	if viewport.msaa_3d != desired:
		viewport.msaa_3d = desired


func set_passthrough(enabled: bool) -> bool:
	if enabled and not supports_passthrough():
		error_code = "XR_PASSTHROUGH_UNAVAILABLE"
		DiagnosticLog.record("display_mode_rejected", {"requested": enabled, "reason": error_code})
		status_changed.emit()
		return false
	requested_passthrough = enabled
	return _apply_requested_mode()


func _apply_requested_mode() -> bool:
	if xr != null and xr.is_initialized() and not preview:
		var mode := (
			XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
			if requested_passthrough
			else XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		)
		xr.environment_blend_mode = mode
		if xr.environment_blend_mode != mode:
			error_code = "XR_BLEND_MODE_REJECTED"
			DiagnosticLog.record(
				"display_mode_rejected", {"requested": requested_passthrough, "reason": error_code}
			)
			status_changed.emit()
			return false
	_set_background(requested_passthrough)
	applied_passthrough = requested_passthrough
	error_code = ""
	DiagnosticLog.record(
		"display_mode_applied", {"passthrough": applied_passthrough, "session": session_state}
	)
	status_changed.emit()
	return true


func _set_background(transparent: bool) -> void:
	viewport.transparent_bg = transparent or video_layer
	environment.sky = null if transparent or video_layer else scenery
	environment.sky_rotation = scenery_rotation
	# Meta reconstruction passthrough needs a transparent environment color too.
	# BG_CLEAR_COLOR inherits the project's opaque dark clear color.
	environment.background_mode = (
		Environment.BG_SKY
		if scenery and not transparent and not video_layer
		else Environment.BG_COLOR
	)
	environment.background_color = (
		Color(0, 0, 0, 0) if transparent or video_layer else Color(0.035, 0.045, 0.06, 1.0)
	)

	_sync_video_backdrop()


func _on_session_event(event: String) -> void:
	session_state = event
	DiagnosticLog.record(event, {"requested_passthrough": requested_passthrough})
	if event in ["session_begun", "session_focussed"]:
		# Reapply the user's mode after session resume; do not destroy the runtime.
		_apply_requested_mode()
		_apply_performance_levels()
		_apply_refresh_rate()
	status_changed.emit()


# High-resolution video sampling keeps the GPU busy continuously. Without a request
# the OpenXR runtime chooses lower CPU/GPU/memory levels for this app.
var performance_levels := "default"
var performance := preload("res://scripts/playback_performance.gd").new()
var policy_refresh_rate := 0.0


func update_playback_policy(
	visible: bool,
	playing: bool,
	layer: bool,
	expensive: bool,
	fps: float,
	low_end: bool,
	now_ms: int,
	menu_visible: bool = false
) -> void:
	var rate := preferred_refresh_rate
	if match_video_rate:
		var available := available_refresh_rates()
		var cap := (
			minf(preferred_refresh_rate, 90.0) if low_end or not layer else preferred_refresh_rate
		)
		rate = performance.video_rate(fps, available, cap) if playing else 0.0
		if rate <= 0:
			rate = closest_refresh_rate(available, minf(72.0, preferred_refresh_rate))
	# Composition still needs enough headroom to draw and copy the controls while video plays.
	var demand := (
		expensive or (visible and not layer) or (playing and (menu_visible or rate > 72.5))
	)
	var changes := performance.tick(demand, rate, now_ms)
	if changes.has("high"):
		_apply_performance_levels()
	if match_video_rate and changes.has("rate"):
		policy_refresh_rate = float(changes.rate)
		_apply_refresh_rate()


# Fixed foveated rendering for the eye buffers (0 off .. 3 high); the 8K video is sampled
# for every eye pixel at the display rate, so the periphery is a large bandwidth cost.
var foveation_level := 0


func set_foveation(level: int) -> void:
	foveation_level = clampi(level, 0, 3)
	_apply_foveation()


func _apply_foveation() -> void:
	if xr is OpenXRInterface and xr.is_initialized() and "foveation_level" in xr:
		xr.foveation_dynamic = false
		xr.foveation_level = foveation_level
		DiagnosticLog.record(
			"xr_foveation", {"level": foveation_level, "applied": xr.foveation_level}
		)


func _apply_performance_levels() -> void:
	if (
		preview
		or not (xr is OpenXRInterface)
		or not xr.is_initialized()
		or not xr.has_method("set_gpu_level")
	):
		performance_levels = "unsupported"
		return
	var level := (
		OpenXRInterface.PERF_SETTINGS_LEVEL_SUSTAINED_HIGH
		if performance.high
		else OpenXRInterface.PERF_SETTINGS_LEVEL_SUSTAINED_LOW
	)
	xr.set_cpu_level(level)
	xr.set_gpu_level(level)
	performance_levels = "sustained_high" if performance.high else "sustained_low"
	_apply_foveation()
	DiagnosticLog.record(
		"xr_performance_levels", {"cpu": performance_levels, "gpu": performance_levels}
	)


func _on_presence_changed(present: bool) -> void:
	DiagnosticLog.record("user_presence_changed", {"present": present})
	presence_changed.emit(present)


static func refresh_rates_from(target: Object) -> Array[float]:
	var result: Array[float] = []
	if target == null or not target.has_method("get_available_display_refresh_rates"):
		return result
	for item in target.get_available_display_refresh_rates():
		if (
			(item is int or item is float)
			and is_finite(float(item))
			and float(item) > 0.0
			and float(item) not in result
		):
			result.append(float(item))
	result.sort()
	return result


static func closest_refresh_rate(values: Array, preferred: float = 72.0) -> float:
	var chosen := 0.0
	var distance := INF
	for rate in values:
		var delta := absf(rate - preferred)
		if delta < distance or (is_equal_approx(delta, distance) and rate < chosen):
			chosen = rate
			distance = delta
	return chosen


func available_refresh_rates() -> Array[float]:
	var empty: Array[float] = []
	if xr != null and xr.is_initialized() and not preview:
		return refresh_rates_from(xr)
	return empty


func set_refresh_preference(value: float) -> bool:
	if not is_finite(value) or value not in available_refresh_rates():
		return false
	preferred_refresh_rate = value
	_reset_refresh_policy()
	return true


func set_refresh_matching(enabled: bool) -> void:
	match_video_rate = enabled
	_reset_refresh_policy()


func _reset_refresh_policy() -> void:
	policy_refresh_rate = 0.0
	performance.wanted_rate = -1.0
	performance.applied_rate = -1.0
	_apply_refresh_rate()


func _apply_refresh_to(target: Object) -> float:
	var selected := closest_refresh_rate(
		refresh_rates_from(target),
		policy_refresh_rate if policy_refresh_rate > 0 else preferred_refresh_rate
	)
	if selected > 0:
		target.set("display_refresh_rate", selected)
	return selected


func _apply_refresh_rate() -> void:
	if xr != null and xr.is_initialized() and not preview:
		applied_refresh_rate = _apply_refresh_to(xr)


func capabilities() -> Dictionary:
	var report := {
		"preview": preview,
		"session_state": session_state,
		"requested_passthrough": requested_passthrough,
		"applied_passthrough": applied_passthrough,
		"error_code": error_code,
		"initialized": xr != null and xr.is_initialized(),
		"supported_blend_modes": [],
		"passthrough_supported": supports_passthrough(),
		"viewport_use_xr": viewport != null and viewport.use_xr,
		"viewport_transparent_bg": viewport != null and viewport.transparent_bg,
		"performance_levels": performance_levels,
		"foveation_level": foveation_level,
		"render_scale": render_scale,
		"preferred_refresh_rate": preferred_refresh_rate,
		"match_video_rate": match_video_rate,
		"requested_refresh_rate": applied_refresh_rate,
		"viewport_msaa_3d": viewport.msaa_3d if viewport else Viewport.MSAA_DISABLED,
		# Vendors can shrink the actual render region without changing the allocated eye buffers.
		"meta_dynamic_resolution_enabled":
		bool(ProjectSettings.get_setting("xr/openxr/extensions/meta/dynamic_resolution", true)),
		"render_target_size_scope": "allocated_eye_buffer",
		"viewport_scaling_3d_scale": viewport.scaling_3d_scale if viewport else 1.0,
		"captured_ticks_usec": Time.get_ticks_usec(),
	}
	if xr != null and xr.is_initialized() and not preview:
		var target_size := xr.get_render_target_size()
		report["render_target_size"] = [int(target_size.x), int(target_size.y)]
		report["system_info"] = xr.get_system_info()
		report["view_count"] = xr.get_view_count()
		report["tracking_status"] = xr.get_tracking_status()
		report["tracking_status_enum_valid"] = int(report["tracking_status"]) in [0, 1, 2, 3, 4]
		# Godot 4.7.2's OpenXR tracking_state is not assigned in the upstream
		# implementation. Use the registered head pose to assess live tracking.
		var head := XRServer.get_tracker("head") as XRPositionalTracker
		report["head_tracker_registered"] = head != null
		if head != null:
			var head_pose := head.get_pose("default")
			if head_pose != null:
				report["head_has_tracking_data"] = head_pose.has_tracking_data
				report["head_tracking_confidence"] = head_pose.tracking_confidence
				report["head_position"] = [
					head_pose.transform.origin.x,
					head_pose.transform.origin.y,
					head_pose.transform.origin.z
				]
		report["actual_blend_mode"] = xr.environment_blend_mode
		report["eye_origins"] = []
		report["eye_quaternions"] = []
		for eye in range(xr.get_view_count()):
			var pose := xr.get_transform_for_view(eye, Transform3D.IDENTITY)
			var orientation := pose.basis.get_rotation_quaternion()
			report["eye_origins"].append([pose.origin.x, pose.origin.y, pose.origin.z])
			report["eye_quaternions"].append(
				[orientation.x, orientation.y, orientation.z, orientation.w]
			)
		report["supported_blend_modes"] = xr.get_supported_environment_blend_modes()
		if xr is OpenXRInterface:
			report["applied_render_scale"] = xr.render_target_size_multiplier
			report["applied_foveation_level"] = xr.foveation_level
			report["refresh_rates"] = xr.get_available_display_refresh_rates()
			report["refresh_rate"] = xr.display_refresh_rate
	if not preview and Engine.has_singleton("OpenXRFbPassthroughExtension"):
		var fb := Engine.get_singleton("OpenXRFbPassthroughExtension")
		report["fb_passthrough_supported"] = fb.is_passthrough_supported()
		report["fb_passthrough_started"] = fb.is_passthrough_started()
		report["color_passthrough_capability"] = fb.has_color_passthrough_capability()
	return report
