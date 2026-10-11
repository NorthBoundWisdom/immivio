extends Node3D
## UI-only native quad layer. The existing 3D controls retain input/state ownership.
## No video geometry enters this viewport; no CPU image readback is performed.
const UI_LAYER := 1 << 19
const CAPTURE_SIZE := Vector2i(3072, 2048)

var menus: Array = []
var head: Camera3D
var layer: OpenXRCompositionLayerQuad
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
	_session_state = session_state
	if not xr_enabled or OS.get_name() != "Android": return
	if RenderingServer.get_current_rendering_driver_name() not in ["opengl3", "opengl3_es"]: return
	if OpenXRAPIExtension.new().get_instance_proc_addr("xrCreateSwapchainAndroidSurfaceKHR") == 0: return
	_bridge = JavaClassWrapper.wrap("org.vrpassthroughplayer.plugin.XrUiSurfaceBridge")
	if _bridge == null: return
	_original_mask = head.cull_mask
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
	_configured = true
	process_priority = 50 # Update after menu layout, poses and pointer feedback.
	get_tree().node_added.connect(_node_added)
	get_tree().node_removed.connect(_node_removed)

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

func _process(_delta: float) -> void:
	if not _configured: return
	if not layer.is_natively_supported(): return
	if _session_state.is_valid() and _session_state.call() not in ["session_focussed", "session_visible"]:
		_bridge.setEnabled(false)
		if viewport: viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_set_native_ready(false)
		return
	if not viewport: _create_capture()
	var current_surface: Object = layer.get_android_surface()
	var generation: int = _bridge.contextGeneration()
	if current_surface != _surface or generation != _generation:
		_surface = current_surface; _generation = generation
		_texture_id = 0; _capture_frames = 0
		_bridge.attachSurface(_surface)
	_bridge_status = JSON.parse_string(_bridge.status())
	_set_native_ready(bool(_bridge_status.get("ready", false)) and _surface != null)
	if _surface != null and _capture_frames >= 2:
		if _texture_id == 0:
			_texture_id = RenderingServer.texture_get_native_handle(RenderingServer.viewport_get_texture(viewport.get_viewport_rid()))
		_bridge.submitTexture(_texture_id, CAPTURE_SIZE.x, CAPTURE_SIZE.y, _generation)
	var shown: Node3D
	for menu in menus:
		if is_instance_valid(menu) and menu.is_visible_in_tree():
			shown = menu; break
	if shown != active_menu:
		active_menu = shown; content_bounds = Rect2(); _bounds_due = 0
		_clear_frames = 2 if not shown else 0
	if not active_menu:
		# Keep the Android swapchain registered; stop GPU copies while hidden.
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _clear_frames > 0 else SubViewport.UPDATE_DISABLED
		_bridge.setEnabled(_clear_frames > 0)
		_clear_frames = maxi(0, _clear_frames - 1)
		layer.quad_size = Vector2.ONE * .001
		return
	if Time.get_ticks_msec() >= _bounds_due:
		_update_bounds()
		_bounds_due = Time.get_ticks_msec() + 100
	var centre := surface_rect.get_center()
	layer.global_transform = active_menu.global_transform * Transform3D(Basis.IDENTITY, Vector3(centre.x, centre.y, 0))
	camera.global_transform = layer.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, 1))
	camera.size = surface_rect.size.y
	layer.quad_size = surface_rect.size if native_supported else Vector2.ONE * .001
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_capture_frames += 1
	_bridge.setEnabled(true)
	layer.visible = true

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
	# Keep the physical pointing ray outside the quad visible in the scene too.
	node.layers = UI_LAYER | (int(_original_layers[id].layers) if not native_supported or node.get_meta("xr_ui_pointer", false) else 0)

func _tag_tree(node: Node) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D: _tag(child)
		_tag_tree(child)

func _visual_bounds(node: Node, inverse: Transform3D, result: Array) -> void:
	for child in node.get_children():
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

func _update_bounds() -> void:
	var result: Array = []
	_visual_bounds(active_menu, active_menu.global_transform.affine_inverse(), result)
	var bounds: Rect2 = result[0] if not result.is_empty() else Rect2(-.6, -.2, 1.2, .5)
	bounds = bounds.grow(.04)
	var low := (bounds.position * 10).floor() / 10
	var high := (bounds.end * 10).ceil() / 10
	bounds = Rect2(low, high - low)
	# Grow while a menu is open so hover/tooltips do not repeatedly shrink and
	# reallocate the XR swapchain. New menu openings start with fresh bounds.
	content_bounds = bounds if content_bounds.size == Vector2.ZERO else content_bounds.merge(bounds)
	# Fixed swapchain dimensions; only the physical quad/camera bounds change.
	var aspect := float(CAPTURE_SIZE.x) / CAPTURE_SIZE.y
	var height := maxf(content_bounds.size.y, content_bounds.size.x / aspect)
	var physical_size := Vector2(height * aspect, height)
	surface_rect = Rect2(content_bounds.get_center() - physical_size / 2, physical_size)

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

func map_ray(menu: Node3D, origin: Vector3, direction: Vector3) -> Dictionary:
	if not native_supported or menu != active_menu or not layer.visible: return {}
	return project_ray(layer.global_transform, layer.quad_size, origin, direction)

func snapshot() -> Dictionary:
	var font: Font = active_menu.ui_font() if is_instance_valid(active_menu) else null
	var session_ready: bool = not _session_state.is_valid() or _session_state.call() in ["session_focussed", "session_visible"]
	return {"native_supported": native_supported, "active": native_supported and session_ready and active_menu != null and layer != null and layer.visible,
		"session_ready": session_ready, "presentation": _bridge_status,
		"surface_available": _surface != null, "texture_id": _texture_id, "capture_frames": _capture_frames,
		"viewport_size": [viewport.size.x, viewport.size.y] if viewport else [],
		"main_msaa_3d": head.get_viewport().msaa_3d if is_instance_valid(head) else 0,
		"ui_only_cull_mask": camera.cull_mask if camera else 0,
		"ui_draw_calls": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME) if viewport else 0,
		"pixels_per_metre": CAPTURE_SIZE.x / surface_rect.size.x if surface_rect.size.x > 0 else 0,
		"font_msdf": bool(font.get("multichannel_signed_distance_field")) if font else false,
		"mode": "native_alpha_quad_overlay" if native_supported else "scene_fallback"}

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
	if is_instance_valid(layer):
		_bridge.setEnabled(false)
		_bridge.attachSurface(null)
		layer.queue_free()
