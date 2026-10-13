extends Node3D
## UI-only native quad/cylinder layers with a curved scene fallback. The existing 3D controls retain input/state ownership.
## No video geometry enters this viewport; no CPU image readback is performed.
const UI_LAYER := 1 << 19
const CAPTURE_SIZE := Vector2i(3072, 2048)

## Metadata follows the GPU copy acknowledgement, never a newly requested layout.
class PresentationQueue extends RefCounted:
	var serial := 0
	var committed := -1
	var pending := {}
	func stage(metadata: Dictionary) -> int:
		serial += 1
		pending[serial] = metadata.duplicate()
		while pending.size() > 4: pending.erase(pending.keys()[0])
		return serial
	func take(acknowledged: int) -> Dictionary:
		if acknowledged <= committed or not pending.has(acknowledged): return {}
		var result: Dictionary = pending[acknowledged]
		committed = acknowledged
		for key in pending.keys():
			if int(key) <= acknowledged: pending.erase(key)
		return result
	func reset() -> void:
		pending.clear(); committed = serial

var warmup: Node
var presentations := PresentationQueue.new()
var presented := {}
var _rect_changes := 0
var _last_frame_us := 0
var _frame_gap_max_us := 0
var menus: Array = []
var head: Camera3D
var layer: OpenXRCompositionLayerQuad
var cylinder_layer: OpenXRCompositionLayerCylinder
var scene_curved := false
var curved_mesh: MeshInstance3D
var _mesh_key := Vector3.ZERO
const MediaSurface := preload("res://scripts/media_surface.gd")
var viewport: SubViewport
var _bridge: Object
var _surface: Object
var _texture_id := 0
var _generation := -1
var _capture_frames := 0
var _bridge_status := {}
var camera: Camera3D
var active_menu: Node3D
var native_supported := false
var content_bounds := Rect2()
var surface_rect := Rect2()
var _original_mask := 0
var _original_layers := {}
var _bounds_due := 0
var _configured := false
var _clear_frames := 0
var _session_state := Callable()
func configure(values: Array, view_camera: Camera3D, xr_enabled: bool, session_state: Callable = Callable()) -> void:
	menus = values; head = view_camera
	_original_mask = head.cull_mask
	_configured = true
	process_priority = 50
	get_tree().node_added.connect(_node_added)
	get_tree().node_removed.connect(_node_removed)
	warmup = preload("res://scripts/ui_warmup.gd").new()
	for menu in menus:
		if menu.has_method("adopt_prepared_layouts"): warmup.playback_menu = menu; break
	add_child(warmup)
	_session_state = session_state
	if not xr_enabled or OS.get_name() != "Android": return
	if RenderingServer.get_current_rendering_driver_name() not in ["opengl3", "opengl3_es"]: return
	if OpenXRAPIExtension.new().get_instance_proc_addr("xrCreateSwapchainAndroidSurfaceKHR") == 0: return
	_bridge = JavaClassWrapper.wrap("org.vrpassthroughplayer.plugin.XrUiSurfaceBridge")
	if _bridge == null: return
	layer = OpenXRCompositionLayerQuad.new()
	layer.visible = true
	layer.quad_size = Vector2.ONE * .001
	layer.android_surface_size = CAPTURE_SIZE
	layer.use_android_surface = true
	layer.alpha_blend = true
	layer.sort_order = 5
	# Android Surface orientation differs by runtime. Match GodotVR's official
	# Android Surface sample: GLES on Oculus needs this extra runtime correction.
	var runtime: String = XRServer.find_interface("OpenXR").get_system_info().get("XRRuntimeName", "")
	if runtime.begins_with("Oculus"):
		layer.set("XR_FB_composition_layer_image_layout/vertical_flip", true)
	# Parenting directly to the XR origin also avoids a Godot composition-node
	# transform notification before get_global_transform() is available.
	head.get_parent().add_child(layer)
	cylinder_layer = OpenXRCompositionLayerCylinder.new()
	cylinder_layer.use_android_surface = true
	cylinder_layer.android_surface_size = CAPTURE_SIZE
	cylinder_layer.alpha_blend = true
	cylinder_layer.sort_order = 5
	cylinder_layer.central_angle = .001
	cylinder_layer.aspect_ratio = 1.5
	if runtime.begins_with("Oculus"):
		cylinder_layer.set("XR_FB_composition_layer_image_layout/vertical_flip", true)
	head.get_parent().add_child(cylinder_layer)

func _create_capture() -> void:
	viewport = SubViewport.new()
	viewport.size = CAPTURE_SIZE
	viewport.transparent_bg = true
	viewport.world_3d = get_world_3d()
	# MSDF glyphs and analytic UI edges supply coverage at native UI resolution.
	# Keep the ordinary capture single-sampled for its GPU framebuffer copy.
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = .01; camera.far = 3.0
	camera.cull_mask = UI_LAYER
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color(0, 0, 0, 0)
	viewport.add_child(camera)
	camera.current = true
	head.cull_mask = _original_mask & ~UI_LAYER
	for menu in menus:
		menu.xr_surface = self
		_tag_tree(menu)

func _display_layer() -> OpenXRCompositionLayer:
	return cylinder_layer if active_menu and active_menu.curve_radius > 0.0 else layer

func _hide_layers() -> void:
	if layer: layer.quad_size = Vector2.ONE * .001
	if cylinder_layer: cylinder_layer.central_angle = .001
	if curved_mesh: curved_mesh.visible = false

func _set_scene_curved(value: bool) -> void:
	if scene_curved == value: return
	scene_curved = value
	for item in _original_layers.values():
		var node: Object = item.node.get_ref()
		if is_instance_valid(node): _tag(node)

func _process(_delta: float) -> void:
	if not _configured: return
	if _session_state.is_valid() and OS.get_name() == "Android" and _session_state.call() not in ["session_focussed", "session_visible"]:
		if _bridge: _bridge.setEnabled(false)
		if viewport: viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		presentations.reset(); presented.clear(); _last_frame_us = 0
		_hide_layers(); _set_native_ready(false); _set_scene_curved(false)
		return
	var shown: Node3D
	for menu in menus:
		if is_instance_valid(menu) and menu.is_visible_in_tree():
			shown = menu; break
	if shown != active_menu:
		active_menu = shown; content_bounds = Rect2(); _bounds_due = 0
		_clear_frames = 2 if not shown else 0
		_set_scene_curved(false)
	var target := _display_layer()
	var use_native := target != null and target.is_natively_supported() and _bridge != null
	var use_scene: bool = active_menu != null and active_menu.curve_radius > 0.0 and not use_native
	if not viewport and (use_native or use_scene): _create_capture()
	if not viewport: return
	var now := Time.get_ticks_usec()
	if _last_frame_us > 0: _frame_gap_max_us = maxi(_frame_gap_max_us, now - _last_frame_us)
	_last_frame_us = now
	if use_native:
		var current_surface: Object = target.get_android_surface()
		var generation: int = _bridge.contextGeneration()
		if current_surface != _surface or generation != _generation:
			_surface = current_surface; _generation = generation
			_texture_id = 0; _capture_frames = 0
			presentations.reset(); presented.clear()
			_bridge.attachSurface(_surface)
		_bridge_status = JSON.parse_string(_bridge.status())
		var acknowledged := presentations.take(int(_bridge_status.get("presented_serial", -1)))
		if not acknowledged.is_empty(): presented = acknowledged
		_set_native_ready(bool(_bridge_status.get("ready", false)) and not presented.is_empty() and _surface != null)
	else:
		if _bridge: _bridge.setEnabled(false)
		_set_native_ready(false)
	_set_scene_curved(use_scene)
	if use_native and active_menu:
		if active_menu.curve_radius > 0.0: layer.quad_size = Vector2.ONE * .001
		else: cylinder_layer.central_angle = .001
		if curved_mesh: curved_mesh.visible = false
	else: _hide_layers()
	if not active_menu or not (use_native or use_scene):
		_hide_layers()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if use_native and _clear_frames > 0 else SubViewport.UPDATE_DISABLED
		if use_native:
			_bridge.setEnabled(_clear_frames > 0)
			if _clear_frames > 0: _submit_capture({"visible": false})
		_clear_frames = maxi(0, _clear_frames - 1)
		return
	if Time.get_ticks_msec() >= _bounds_due:
		_update_bounds()
		_bounds_due = Time.get_ticks_msec() + 100
	var capture := capture_pose(active_menu)
	var centre := surface_rect.get_center()
	camera.global_transform = capture * Transform3D(Basis.IDENTITY, Vector3(centre.x, centre.y, 1))
	camera.size = surface_rect.size.y
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if use_scene:
		_apply_curved_mesh(capture, surface_rect, active_menu.curve_radius)
	else:
		_apply_presented_layer()
		_bridge.setEnabled(true)
		_submit_capture({"visible": true, "menu_id": active_menu.get_instance_id(),
			"layout_revision": active_menu.layout_revision, "pose": capture, "rect": surface_rect,
			"curve_radius": active_menu.curve_radius})

func _apply_curved_mesh(pose: Transform3D, rect: Rect2, radius: float) -> void:
	if not curved_mesh:
		curved_mesh = MeshInstance3D.new()
		add_child(curved_mesh)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_texture = viewport.get_texture()
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		curved_mesh.material_override = material
	var key := Vector3(rect.size.x, rect.size.y, radius)
	if key != _mesh_key:
		_mesh_key = key
		curved_mesh.mesh = MediaSurface._cylinder(rect.size, radius, 64)
	curved_mesh.global_transform = pose * Transform3D(Basis.IDENTITY, Vector3(rect.get_center().x, rect.get_center().y, 0))
	curved_mesh.visible = true

func _submit_capture(metadata: Dictionary) -> void:
	_capture_frames += 1
	if _surface == null or _capture_frames < 2: return
	if _texture_id == 0:
		_texture_id = RenderingServer.texture_get_native_handle(RenderingServer.viewport_get_texture(viewport.get_viewport_rid()))
	if _texture_id <= 0: return
	var serial := presentations.stage(metadata)
	_bridge.submitTexture(_texture_id, CAPTURE_SIZE.x, CAPTURE_SIZE.y, _generation, serial)

static func presented_pose(metadata: Dictionary, menu: Node3D) -> Transform3D:
	return capture_pose(menu) if metadata.layout_revision == menu.layout_revision else metadata.pose

func _apply_presented_layer() -> void:
	if not native_supported or not presented.get("visible", false) or presented.get("menu_id") != active_menu.get_instance_id():
		_hide_layers()
		return
	# Rigid head/canvas motion is safe with the same layout. A page transition
	# retains its old pose as well as its old projection until the new image arrives.
	var pose := presented_pose(presented, active_menu)
	var rect: Rect2 = presented.rect
	var radius: float = presented.get("curve_radius", 0.0)
	if radius > 0.0:
		cylinder_layer.global_transform = pose * Transform3D(Basis.IDENTITY, Vector3(rect.get_center().x, rect.get_center().y, radius))
		cylinder_layer.radius = radius
		cylinder_layer.central_angle = rect.size.x / radius
		cylinder_layer.aspect_ratio = rect.size.x / rect.size.y
	else:
		layer.global_transform = pose * Transform3D(Basis.IDENTITY, Vector3(rect.get_center().x, rect.get_center().y, 0))
		layer.quad_size = rect.size

## Recenter signals can arrive during XR processing, after the scene callback.
## Move the existing image's layer immediately so it cannot render at the old
## coordinates for one frame before the next compositor _process call.
func refresh_placement() -> void:
	if not is_instance_valid(active_menu): return
	if native_supported:
		_apply_presented_layer()
	elif scene_curved:
		_apply_curved_mesh(capture_pose(active_menu), surface_rect, active_menu.curve_radius)

func _set_native_ready(value: bool) -> void:
	if native_supported == value: return
	native_supported = value
	for item in _original_layers.values():
		var node: Object = item.node.get_ref()
		if is_instance_valid(node): _tag(node)

func invalidate() -> void:
	_bounds_due = 0

func _belongs_to_menu(node: Node) -> bool:
	var parent := node.get_parent()
	while parent:
		if parent in menus: return true
		parent = parent.get_parent()
	return false

func _node_added(node: Node) -> void:
	if viewport and node is GeometryInstance3D and _belongs_to_menu(node):
		_tag(node)
		invalidate()

func _node_removed(node: Node) -> void:
	var id := node.get_instance_id()
	if _original_layers.has(id):
		if is_instance_valid(node): node.layers = _original_layers[id].layers
		_original_layers.erase(id)

func _tag(node: GeometryInstance3D) -> void:
	var id := node.get_instance_id()
	if not _original_layers.has(id):
		_original_layers[id] = {"node": weakref(node), "layers": node.layers}
	# A 3D ray flattened by the orthographic camera becomes a projection stripe.
	# Only its reticle belongs in the UI texture; keep the ray in the main scene.
	if node.get_meta("xr_ui_scene_ray", false):
		node.layers = int(_original_layers[id].layers) & ~UI_LAYER
		return
	node.layers = UI_LAYER | (int(_original_layers[id].layers) if not (native_supported or scene_curved) or (node.get_meta("xr_ui_pointer", false) and not (active_menu and active_menu.curve_radius > 0.0)) else 0)

func _tag_tree(node: Node) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D: _tag(child)
		_tag_tree(child)

func _visual_bounds(node: Node, inverse: Transform3D, result: Array) -> void:
	for child in node.get_children():
		if child.get_meta("xr_ui_transient_bounds", false): continue
		if child is Node3D and not child.is_visible_in_tree(): continue
		if child is GeometryInstance3D and not child.get_meta("xr_ui_pointer", false):
			var box: AABB = child.get_aabb()
			var transform: Transform3D = inverse * child.global_transform
			for corner in 8:
				var p := transform * box.get_endpoint(corner)
				var point := Vector2(p.x, p.y)
				if result.is_empty(): result.append(Rect2(point, Vector2.ZERO))
				else: result[0] = result[0].expand(point)
		_visual_bounds(child, inverse, result)

## Capture scaled UI geometry in metres with an unscaled camera/native quad.
static func capture_pose(menu: Node3D) -> Transform3D:
	return menu.global_transform.orthonormalized()

func _update_bounds() -> void:
	var result: Array = []
	_visual_bounds(active_menu, capture_pose(active_menu).affine_inverse(), result)
	var bounds: Rect2 = result[0] if not result.is_empty() else Rect2(-.6, -.2, 1.2, .5)
	var envelope: Rect2 = active_menu.capture_envelope()
	var tooltip_bounds: Rect2 = active_menu.tooltip_envelope()
	if tooltip_bounds.has_area(): envelope = envelope.merge(tooltip_bounds) if envelope.has_area() else tooltip_bounds
	if envelope.has_area():
		var local_to_capture := capture_pose(active_menu).affine_inverse() * active_menu.global_transform
		for corner in [envelope.position, Vector2(envelope.end.x, envelope.position.y), envelope.end, Vector2(envelope.position.x, envelope.end.y)]:
			var point: Vector3 = local_to_capture * Vector3(corner.x, corner.y, 0)
			bounds = bounds.expand(Vector2(point.x, point.y))
	bounds = bounds.grow(.04)
	var low := ((bounds.position + Vector2.ONE * .00001) * 50).floor() / 50
	var high := ((bounds.end - Vector2.ONE * .00001) * 50).ceil() / 50
	bounds = Rect2(low, high - low)
	# Grow while a menu is open so hover/tooltips do not repeatedly shrink and
	# reallocate the XR swapchain. New menu openings start with fresh bounds.
	content_bounds = bounds if content_bounds.size == Vector2.ZERO else content_bounds.merge(bounds)
	# Fixed swapchain dimensions; only the physical quad/camera bounds change.
	var aspect := float(CAPTURE_SIZE.x) / CAPTURE_SIZE.y
	var height := maxf(content_bounds.size.y, content_bounds.size.x / aspect)
	var physical_size := Vector2(height * aspect, height)
	var next_rect := Rect2(content_bounds.get_center() - physical_size / 2, physical_size)
	if next_rect != surface_rect: _rect_changes += 1
	surface_rect = next_rect

## Map a physical ray through the flat compositor surface into the orthographic
## camera used for existing controls, including angled library side columns.
static func project_ray(pose: Transform3D, size: Vector2, origin: Vector3, direction: Vector3) -> Dictionary:
	if direction.length_squared() < .000001: return {}
	var inverse := pose.affine_inverse()
	var from := inverse * origin
	var delta := inverse.basis * direction.normalized()
	if from.z <= 0 or delta.z >= -.00001: return {}
	var point := from + delta * (-from.z / delta.z)
	if absf(point.x) > size.x / 2 or absf(point.y) > size.y / 2: return {}
	return {"origin": pose * Vector3(point.x, point.y, 1), "direction": -pose.basis.z.normalized(),
		"point": pose * Vector3(point.x, point.y, 0), "distance": origin.distance_to(pose * Vector3(point.x, point.y, 0))}

func is_layout_presented(menu: Node3D) -> bool:
	return (scene_curved and menu == active_menu) or (native_supported and menu == active_menu and presented.get("menu_id") == menu.get_instance_id() and presented.get("layout_revision") == menu.layout_revision)

func native_placement_available() -> bool:
	# Placement policy follows capability, not the first image's acknowledgement.
	# Otherwise the first menu jumps from scene clearance to overlay distance.
	return _configured and layer != null and layer.is_natively_supported() and str(_bridge_status.get("error", "")).is_empty()

func reset_metrics() -> void:
	_frame_gap_max_us = 0; _rect_changes = 0; _last_frame_us = 0

## A cylindrical canvas uses arc length for x, preserving texture/control alignment.
static func project_curved_ray(pose: Transform3D, rect: Rect2, radius: float, origin: Vector3, direction: Vector3) -> Dictionary:
	if not origin.is_finite() or not direction.is_finite() or direction.length_squared() < .000001 or radius <= 0.0: return {}
	var inverse := pose.affine_inverse()
	var centre := rect.get_center()
	var start := inverse * origin - Vector3(centre.x, centre.y, radius)
	var delta := inverse.basis * direction.normalized()
	var a := delta.x * delta.x + delta.z * delta.z
	if a < .000001: return {}
	var b := 2.0 * (start.x * delta.x + start.z * delta.z)
	var c := start.x * start.x + start.z * start.z - radius * radius
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0: return {}
	for distance in [(-b - sqrt(discriminant)) / (2.0 * a), (-b + sqrt(discriminant)) / (2.0 * a)]:
		if distance <= 0.0: continue
		var hit: Vector3 = start + delta * distance
		# The interior face is interactive; reject rays arriving from outside.
		if Vector2(hit.x, hit.z).dot(Vector2(delta.x, delta.z)) <= 0.0: continue
		var x := atan2(hit.x, -hit.z) * radius
		if absf(x) > rect.size.x / 2 or absf(hit.y) > rect.size.y / 2: continue
		var canvas := Vector3(centre.x + x, centre.y + hit.y, 0)
		var world := pose * (hit + Vector3(centre.x, centre.y, radius))
		return {"origin": pose * (canvas + Vector3.BACK), "direction": -pose.basis.z.normalized(),
			"canvas_point": pose * canvas, "point": world, "distance": origin.distance_to(world)}
	return {}

func map_ray(menu: Node3D, origin: Vector3, direction: Vector3) -> Dictionary:
	if menu != active_menu: return {}
	if scene_curved:
		return project_curved_ray(capture_pose(menu), surface_rect, menu.curve_radius, origin, direction)
	if not native_supported or not is_layout_presented(menu): return {}
	if menu.curve_radius > 0.0:
		return project_curved_ray(presented_pose(presented, menu), presented.rect, presented.curve_radius, origin, direction)
	return project_ray(layer.global_transform, layer.quad_size, origin, direction)

func snapshot() -> Dictionary:
	var projected_rays := 0
	for item in _original_layers.values():
		var node: Object = item.node.get_ref()
		if is_instance_valid(node) and node.get_meta("xr_ui_scene_ray", false) and node.layers & UI_LAYER != 0: projected_rays += 1
	var font: Font = active_menu.ui_font() if is_instance_valid(active_menu) else null
	var session_ready: bool = OS.get_name() != "Android" or not _session_state.is_valid() or _session_state.call() in ["session_focussed", "session_visible"]
	return {"native_supported": native_supported, "active": (native_supported or scene_curved) and session_ready and active_menu != null,
		"session_ready": session_ready, "presentation": _bridge_status, "projected_ray_count": projected_rays,
		"warmup": warmup.snapshot() if is_instance_valid(warmup) else {},
		"capture_serial": presentations.serial, "presented_serial": presentations.committed,
		"capture_rect": [surface_rect.position.x, surface_rect.position.y, surface_rect.size.x, surface_rect.size.y],
		"rect_changes": _rect_changes, "ui_frame_gap_max_us": _frame_gap_max_us,
		"layout_revision": active_menu.layout_revision if active_menu else -1,
		"presented_layout_revision": presented.get("layout_revision", -1),
		"surface_available": _surface != null, "texture_id": _texture_id, "capture_frames": _capture_frames,
		"viewport_size": [viewport.size.x, viewport.size.y] if viewport else [],
		"main_msaa_3d": head.get_viewport().msaa_3d if is_instance_valid(head) else 0,
		"ui_only_cull_mask": camera.cull_mask if camera else 0,
		"ui_draw_calls": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME) if viewport else 0,
		"quad_scale": [layer.global_basis.x.length(), layer.global_basis.y.length()] if layer else [],
		"pixels_per_metre": CAPTURE_SIZE.x / surface_rect.size.x if surface_rect.size.x > 0 else 0,
		"font_msdf": bool(font.get("multichannel_signed_distance_field")) if font else false,
		"curve_radius": active_menu.curve_radius if active_menu else 0.0,
		"mode": ("native_alpha_cylinder_overlay" if active_menu and active_menu.curve_radius > 0.0 else "native_alpha_quad_overlay") if native_supported else ("scene_curved" if scene_curved else "scene_fallback")}

func _exit_tree() -> void:
	if not _configured: return
	if get_tree().node_added.is_connected(_node_added): get_tree().node_added.disconnect(_node_added)
	if get_tree().node_removed.is_connected(_node_removed): get_tree().node_removed.disconnect(_node_removed)
	for item in _original_layers.values():
		var node: Object = item.node.get_ref()
		if is_instance_valid(node): node.layers = item.layers
	for menu in menus:
		if is_instance_valid(menu): menu.xr_surface = null
	if is_instance_valid(head): head.cull_mask = _original_mask
	if is_instance_valid(cylinder_layer): cylinder_layer.queue_free()
	if is_instance_valid(layer):
		_bridge.setEnabled(false)
		_bridge.attachSurface(null)
		layer.queue_free()
