extends Node3D

signal session_control_requested(operation: String)
signal placement_changed

const PAGE_SIZE := 7
const NONE := -1
const PREVIOUS := -2
const NEXT := -3
const CLOSE := -4
const MAX_RAY_METRES := 5.0
const FOLLOW := -1001
const TEMP_PASSTHROUGH := -1002
const CLOSE_MENU := -1003
const FOOTER_DIAMETER := 0.09
const FOOTER_HIT_SIZE := 0.105
const FOOTER_GAP := 0.025
const STATUS_WIDTH := 0.36
const CONTROL_HEIGHT := 0.065
const CONTROL_FONT_SIZE := 18
const CONTROL_ICON_SIZE := 0.032
var max_ray_metres := MAX_RAY_METRES
var xr_surface: Node
var curve_radius := 1.4
var allow_user_dismiss := true
const TOOLTIP_MAX_WIDTH := 0.64
const TOOLTIP_MARGIN := 0.12
var layout_revision := 0
const PointerRay := preload("res://scripts/pointer_ray.gd")
const SURFACE := preload("res://shaders/menu_surface.gdshader")
const Icons := preload("res://scripts/menu_icons.gd")
const I18n := preload("res://scripts/i18n.gd")
const DeviceStatus := preload("res://scripts/device_status.gd")
# Design tokens. Surfaces take the brand's deep navy; one aqua accent marks selection,
# focus and progress. Resting controls carry no outline: hover/selection draw the ring.
const PANEL := Color(0.043, 0.063, 0.106, 0.97)
const TILE := Color(0.098, 0.133, 0.196, 1.0)
const HOVER := Color(0.165, 0.216, 0.302, 1.0)
const SELECTED := Color(0.075, 0.235, 0.255, 1.0)
const SELECTED_HOVER := Color(0.102, 0.305, 0.325, 1.0)
const POPUP := Color(0.071, 0.098, 0.153, 1.0)
const DISABLED := Color(0.071, 0.094, 0.137, 1.0)
const OUTLINE := Color(1.0, 1.0, 1.0, 0.05)
const PANEL_EDGE := Color(1.0, 1.0, 1.0, 0.09)
const ACCENT := Color(0.49, 0.87, 0.80)
const ACCENT_HOVER := Color(0.68, 0.95, 0.89)
const ACCENT_DIM := Color(0.24, 0.42, 0.40)
const ON_ACCENT := Color(0.02, 0.09, 0.10)
const TEXT := Color(0.94, 0.96, 0.99)
const MUTED := Color(0.55, 0.62, 0.72)
const DIVIDER := Color(1.0, 1.0, 1.0, 0.07)
const TRACK := Color(1.0, 1.0, 1.0, 0.16)
const PANEL_RADIUS := 0.04
const CONTROL_RADIUS := 0.016
# File names and the menu are often Chinese/Japanese: fall back to the system CJK font.
static var FONT: Font = _make_font()
static var _font_language := I18n.language
static var _bold: Font
static var _bold_language := ""


## Headings, titles and the current navigation entry: the same face, emboldened. Embolden
## keeps glyph advances, so text fitted with ui_font() still fits.
static func ui_font_bold() -> Font:
	if _bold == null or _bold_language != I18n.language:
		_bold_language = I18n.language
		var variation := FontVariation.new()
		variation.base_font = ui_font()
		variation.variation_embolden = 0.55
		_bold = variation
	return _bold


static func _make_font() -> Font:
	var font := SystemFont.new()
	var names := ["Noto Sans CJK SC", "Noto Sans SC", "Microsoft YaHei", "PingFang SC"]
	if I18n.language == "zh_Hant":
		names = ["Noto Sans CJK TC", "Noto Sans TC", "Microsoft JhengHei", "PingFang TC"]
	elif I18n.language == "ja":
		names = ["Noto Sans CJK JP", "Noto Sans JP", "Yu Gothic", "Meiryo", "Hiragino Sans"]
	font.font_names = PackedStringArray(names + ["sans-serif"])
	# Complex CJK outlines in Android system fonts can self-intersect under MSDF
	# (visible missing strokes/triangles). Oversampled grayscale glyphs retain
	# their actual outlines and stay sharp in the fixed-resolution UI capture.
	font.multichannel_signed_distance_field = false
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.oversampling = 2.0
	font.generate_mipmaps = true
	var fallback := ThemeDB.fallback_font.duplicate() as Font
	if fallback is FontFile:
		fallback.multichannel_signed_distance_field = true
		fallback.msdf_size = 96
		fallback.msdf_pixel_range = 8
		fallback.generate_mipmaps = true
	font.fallbacks = [fallback]
	return font


static func ui_font() -> Font:
	if _font_language != I18n.language:
		_font_language = I18n.language
		FONT = _make_font()
	return FONT


var _buttons: Array[Dictionary] = []
var _labels: Array[Label3D] = []
var _hover: Dictionary = {}
var _pointers: Dictionary = {}
var _decorations: Array[Node3D] = []
var _backdrop: MeshInstance3D
## Hover names of icon-only buttons (target -> text), shown over the hovered button.
var _tips: Dictionary = {}
var _tooltip: MeshInstance3D
## Battery and clock pill under the panel; kept across redraws.
var device_status: Node3D
var session_controls_provider: Callable
var _footer_state := {}
var _footer_centre := Vector2.ZERO


func _ready() -> void:
	position = Vector3(0, -0.03, -1.55)
	_backdrop = _quad(Vector2(1.55, 1.08), Vector3.ZERO, PANEL, 10)
	add_child(_backdrop)
	visible = false


func toggle() -> void:
	if visible:
		dismiss()
	else:
		visible = true
		_reset_navigation()
		refresh()


func dismiss() -> void:
	visible = false
	_hover.clear()
	for pointer in _pointers.values():
		pointer.line.visible = false
		pointer.dot.visible = false


func capture_envelope() -> Rect2:
	return Rect2()


## Navigation changes need fresh pixels; value updates and scrolling share a page.
func presentation_page() -> Variant:
	return 0


func _reset_navigation() -> void:
	pass


func refresh() -> void:
	_draw()
	_update_highlights()


func _activate(_target: int) -> void:
	pass


func _draw() -> void:
	pass


# Origins/directions are in world space, including recenter/origin/menu transforms. Each button is
# tested on its own plane, so panels may be angled (the library's side column); the nearest wins.
# "point" is in this menu's space.
func ray_hit(origin: Vector3, direction: Vector3) -> Dictionary:
	if (
		not visible
		or not origin.is_finite()
		or not direction.is_finite()
		or direction.length_squared() < 0.000001
	):
		return {}
	var world_origin := origin
	var world_direction := direction
	var mapped := {}
	if (
		xr_surface
		and (xr_surface.native_supported or xr_surface.get("scene_curved") == true)
		and (
			xr_surface.active_menu == self
			or (xr_surface.has_method("captures_menu") and xr_surface.captures_menu(self))
		)
	):
		mapped = xr_surface.map_ray(self, origin, direction)
		if mapped.is_empty() or float(mapped.distance) > max_ray_metres:
			return {}
		origin = mapped.origin
		direction = mapped.direction
	var ray := direction.normalized()
	var best := {}
	for button in _buttons:
		if (
			(not button.enabled and not button.get("hover_disabled", false))
			or not button.node.is_visible_in_tree()
		):
			continue
		var inverse: Transform3D = button.node.global_transform.affine_inverse()
		var start: Vector3 = inverse * origin
		var delta: Vector3 = inverse.basis * ray
		# Only the front face accepts input; parallel, rear and behind-origin hits fail.
		if delta.z >= -0.00001 or start.z <= 0.0:
			continue
		var local := start + delta * (-start.z / delta.z)
		var half: Vector2 = button.rect.size * 0.5
		var radius := minf(0.012, minf(half.x, half.y))
		var corner := Vector2(absf(local.x), absf(local.y)) - (half - Vector2.ONE * radius)
		if corner.x > radius or corner.y > radius or corner.max(Vector2.ZERO).length() > radius:
			continue
		var world: Vector3 = button.node.global_transform * Vector3(local.x, local.y, 0)
		var distance := origin.distance_to(world)
		if distance > max_ray_metres or (not best.is_empty() and distance >= float(best.distance)):
			continue
		best = {
			"target": button.target,
			"point": to_local(world),
			"distance": distance,
			"enabled": button.enabled
		}
	if not best.is_empty() and mapped.is_empty():
		var panel_hit := ray_panel_hit(world_origin, world_direction)
		if not panel_hit.is_empty() and float(panel_hit.distance) < float(best.distance) - 0.00001:
			return {}
	if not best.is_empty() and not mapped.is_empty():
		best.point = to_local(mapped.get("canvas_point", mapped.point))
		best["world_point"] = mapped.point
		best.distance = mapped.distance
	return best


## Panel feedback is independent of button activation: gaps and hidden controls
## still stop the laser, without becoming clickable or highlighted targets.
func ray_panel_hit(origin: Vector3, direction: Vector3) -> Dictionary:
	if (
		not visible
		or not origin.is_finite()
		or not direction.is_finite()
		or direction.length_squared() < 0.000001
	):
		return {}
	if xr_surface and xr_surface.native_supported and xr_surface.has_method("map_panel_ray"):
		var feedback: Dictionary = xr_surface.map_panel_ray(self, origin, direction)
		if feedback.is_empty() or float(feedback.distance) > max_ray_metres:
			return {}
		return {
			"target": NONE,
			"point": to_local(feedback.get("canvas_point", feedback.point)),
			"world_point": feedback.point,
			"distance": feedback.distance,
			"enabled": false,
		}
	var mapped := {}
	if (
		xr_surface
		and (xr_surface.native_supported or xr_surface.get("scene_curved") == true)
		and (
			xr_surface.active_menu == self
			or (xr_surface.has_method("captures_menu") and xr_surface.captures_menu(self))
		)
	):
		mapped = xr_surface.map_ray(self, origin, direction)
		if mapped.is_empty() or float(mapped.distance) > max_ray_metres:
			return {}
		origin = mapped.origin
		direction = mapped.direction
	var best := {}
	for panel in _pointer_panels():
		var inverse := panel.global_transform.affine_inverse()
		var start := inverse * origin
		var delta := inverse.basis * direction.normalized()
		if delta.z >= -0.00001 or start.z <= 0.0:
			continue
		var local := start + delta * (-start.z / delta.z)
		var half: Vector2 = panel.mesh.size * 0.5
		var radius := minf(
			float(panel.material_override.get_shader_parameter("corner_radius")),
			minf(half.x, half.y)
		)
		var corner := Vector2(absf(local.x), absf(local.y)) - (half - Vector2.ONE * radius)
		if corner.x > radius or corner.y > radius or corner.max(Vector2.ZERO).length() > radius:
			continue
		var world: Vector3 = panel.global_transform * Vector3(local.x, local.y, 0)
		var distance := origin.distance_to(world)
		if distance > max_ray_metres or (not best.is_empty() and distance >= float(best.distance)):
			continue
		best = {"target": NONE, "point": to_local(world), "distance": distance, "enabled": false}
	if not best.is_empty() and not mapped.is_empty():
		best.point = to_local(mapped.get("canvas_point", mapped.point))
		best["world_point"] = mapped.point
		best.distance = mapped.distance
	return best


func _pointer_panels() -> Array[MeshInstance3D]:
	var candidates: Array[Node3D] = [_backdrop]
	candidates.append_array(_decorations)
	if is_instance_valid(device_status):
		candidates.append(device_status.pointer_surface())
	var panels: Array[MeshInstance3D] = []
	for panel in candidates:
		if (
			is_instance_valid(panel)
			and panel is MeshInstance3D
			and panel.is_visible_in_tree()
			and panel.get_meta("xr_ui_panel", false)
		):
			panels.append(panel)
	return panels


## Captures measure travel on the same flattened canvas used by ray_hit().
## Mixing physical cylinder rays with canvas points turns a stationary angled
## trigger hold into a drag, and moves sliders away from their pressed value.
func pointer_plane_point(origin: Vector3, direction: Vector3, plane_z: float) -> Variant:
	if not origin.is_finite() or not direction.is_finite() or direction.length_squared() < 0.000001:
		return null
	if (
		xr_surface
		and (xr_surface.native_supported or xr_surface.get("scene_curved") == true)
		and (
			xr_surface.active_menu == self
			or (xr_surface.has_method("captures_menu") and xr_surface.captures_menu(self))
		)
	):
		var mapped: Dictionary = xr_surface.map_ray(self, origin, direction)
		if mapped.is_empty() or float(mapped.distance) > max_ray_metres:
			return null
		origin = mapped.origin
		direction = mapped.direction
	var inverse := global_transform.affine_inverse()
	var start := inverse * origin
	var delta := inverse.basis * direction.normalized()
	if delta.z >= -0.00001 or start.z <= plane_z:
		return null
	return start + delta * ((plane_z - start.z) / delta.z)


func update_pointer(hand: String, origin: Vector3, direction: Vector3, tracked: bool) -> void:
	if not visible:
		return
	# A popup capture gates clicks for one or more frames. Its unchanged toolbar
	# should not lose hover in that interval. Keep updating the beam from the
	# current hand to the displayed panel instead of freezing its old endpoints.
	var retain_hover: bool = (
		tracked
		and origin.is_finite()
		and direction.is_finite()
		and direction.length_squared() > .000001
		and xr_surface
		and xr_surface.has_method("retains_toolbar")
		and xr_surface.retains_toolbar(self)
	)
	var hit := ray_hit(origin, direction) if tracked else {}
	if not retain_hover or not _hover.has(hand):
		_hover[hand] = int(hit.get("target", NONE))
	if tracked and hit.is_empty():
		hit = ray_panel_hit(origin, direction)
	if hit.is_empty():
		_hover[hand] = NONE
	var pointer := _pointer(hand)
	var valid := (
		tracked
		and origin.is_finite()
		and direction.is_finite()
		and direction.length_squared() > 0.000001
	)
	pointer.line.visible = valid
	pointer.dot.visible = not hit.is_empty()
	if valid:
		var endpoint: Vector3 = (
			hit.get("world_point", to_global(hit.point))
			if not hit.is_empty()
			else origin + direction.normalized() * max_ray_metres
		)
		PointerRay.draw(pointer.line, origin, to_global(to_local(endpoint) + Vector3(0, 0, 0.006)))
		var actionable: bool = (
			not hit.is_empty()
			and (
				(retain_hover and _hover.get(hand, NONE) != NONE)
				or (bool(hit.get("enabled", false)) and int(hit.get("target", NONE)) != NONE)
			)
		)
		pointer.line.material_override.set_shader_parameter(
			"ray_color",
			Color(
				pointer.color, PointerRay.HOVER_OPACITY if actionable else PointerRay.IDLE_OPACITY
			)
		)
		if not hit.is_empty():
			pointer.dot.position = hit.point + Vector3(0, 0, 0.008)
			pointer.dot.scale = Vector3.ONE * (1.25 if actionable else 1.0)
			pointer.dot.material_override.albedo_color = (
				pointer.color.lerp(Color.WHITE, 0.7) if actionable else pointer.color
			)
	_update_highlights()


func cancel_pointer(hand: String) -> void:
	update_pointer(hand, Vector3.ZERO, Vector3.ZERO, false)


func press_pointer(hand: String, origin: Vector3, direction: Vector3, tracked: bool) -> bool:
	# Recompute at trigger time. A stale hover or the other hand cannot click.
	update_pointer(hand, origin, direction, tracked)
	var hit := ray_hit(origin, direction) if tracked else {}
	if hit.is_empty():
		return false
	_activate_hit(hit)
	return true


func _activate_hit(hit: Dictionary) -> void:
	if not hit.get("enabled", true):
		return
	if _activate_footer(int(hit.target)):
		return
	_activate(int(hit.target))


func _activate_footer(target: int) -> bool:
	if target == CLOSE_MENU:
		if allow_user_dismiss:
			dismiss()
		return true
	if target not in [FOLLOW, TEMP_PASSTHROUGH]:
		return false
	var state := _session_controls()
	if target == FOLLOW:
		session_control_requested.emit("follow")
	elif state.get("passthrough_visible", false) and not state.get("alpha", false):
		session_control_requested.emit("temporary_passthrough")
	refresh_session_controls(true)
	return true


func _set_backdrop(size: Vector2, centre: Vector2 = Vector2.ZERO) -> void:
	_backdrop.mesh.size = size
	_backdrop.position = Vector3(centre.x, centre.y, 0)
	_backdrop.material_override.set_shader_parameter("surface_size", size)
	# All views, including modal/web/adjustment branches, get the same footer.
	_place_device_status(Vector2(centre.x, centre.y - size.y * 0.5 - 0.085))


func _clear_layout() -> void:
	layout_revision += 1
	if xr_surface:
		xr_surface.invalidate()
	for button in _buttons:
		button.node.free()
	_buttons.clear()
	for label in _labels:
		label.free()
	_labels.clear()
	for decoration in _decorations:
		decoration.free()
	_decorations.clear()
	_tips.clear()
	_footer_state.clear()
	if _tooltip:
		_tooltip.visible = false
	_hover.clear()
	for pointer in _pointers.values():
		pointer.dot.visible = false


func _button(
	target: int,
	text: String,
	centre: Vector2,
	size: Vector2,
	enabled: bool = true,
	icon: String = "",
	primary: bool = false,
	parent: Node3D = null
) -> void:
	var base := ACCENT if primary else TILE
	var foreground := ON_ACCENT if primary else TEXT
	var node := _quad(size, Vector3(centre.x, centre.y, 0.002), base, 11)
	if text.is_empty() and not icon.is_empty():
		# Icon-only actions read as capsules; text buttons keep the softer rectangle.
		node.material_override.set_shader_parameter("corner_radius", minf(size.x, size.y) * 0.5)
	node.visible = enabled
	(parent if parent else self).add_child(node)
	var label := _label(
		text,
		Vector3(0, -size.y * 0.26 if not icon.is_empty() else 0, 0.004),
		19 if not icon.is_empty() else 23,
		node
	)
	label.modulate = foreground if enabled else MUTED * Color(0.7, 0.7, 0.7)
	if primary:
		label.font = ui_font_bold()
	if not icon.is_empty():
		# Icon-only buttons centre a larger glyph; captioned buttons stack icon over text.
		var alone := text.is_empty()
		_icon(
			icon,
			Vector3(0, 0 if alone else size.y * 0.15, 0.004),
			minf(size.y * (0.55 if alone else 0.38), 0.05 if alone else 0.045),
			foreground if enabled else MUTED,
			node
		)
	_buttons.append(
		{
			"target": target,
			"rect": Rect2(centre - size / 2, size),
			"enabled": enabled,
			"node": node,
			"base_color": base,
			"foreground": foreground
		}
	)


## Standard settings action: one text line, optional inline icon, shared height.
## Media tiles, transport controls and slider hit areas retain their own layouts.
func _control_button(
	target: int,
	text: String,
	centre: Vector2,
	width: float,
	enabled: bool = true,
	icon: String = "",
	primary: bool = false,
	parent: Node3D = null
) -> void:
	var inset := 0.075 if not icon.is_empty() and not text.is_empty() else 0.04
	var caption := _fit_title(text, "", width - inset, CONTROL_FONT_SIZE)
	_button(target, caption, centre, Vector2(width, CONTROL_HEIGHT), enabled, "", primary, parent)
	var button: Dictionary = _buttons.back()
	var label: Label3D = button.node.get_child(0)
	label.font_size = CONTROL_FONT_SIZE
	if not icon.is_empty():
		if not text.is_empty():
			label.position.x = 0.02
		_icon(
			icon,
			Vector3(-width / 2 + 0.03 if not text.is_empty() else 0.0, 0, 0.004),
			CONTROL_ICON_SIZE,
			button.foreground if enabled else MUTED,
			button.node
		)
	if caption != text:
		_tips[target] = text


## Icon-only round button (play, floating actions); [tip] names it while a ray hovers it.
func _round(
	target: int,
	icon: String,
	centre: Vector2,
	diameter: float,
	enabled: bool = true,
	primary: bool = false,
	tip: String = ""
) -> void:
	_button(target, "", centre, Vector2.ONE * diameter, enabled, icon, primary)
	_buttons.back().node.material_override.set_shader_parameter("corner_radius", diameter * 0.5)
	if not tip.is_empty():
		_tips[target] = tip


## Icon over the panel without a tile of its own: only hover lights it up.
func _glyph(
	target: int, icon: String, centre: Vector2, size: float, enabled: bool = true, tip: String = ""
) -> void:
	_button(target, "", centre, Vector2.ONE * size, enabled, icon)
	var button: Dictionary = _buttons.back()
	button.base_color = Color(TILE, 0.0)
	button.node.material_override.set_shader_parameter("corner_radius", size * 0.5)
	if not tip.is_empty():
		_tips[target] = tip


## Puts the battery and clock pill centred at [centre], under the panel like SKYBOX.
func _place_device_status(centre: Vector2) -> void:
	if not device_status:
		device_status = DeviceStatus.new()
		device_status.minimum_width = STATUS_WIDTH
		add_child(device_status)
	var bottom: float = _backdrop.position.y - _backdrop.mesh.size.y * 0.5
	_footer_centre = Vector2(centre.x, minf(centre.y - 0.025, bottom - 0.085))
	refresh_session_controls(true)


func _session_controls() -> Dictionary:
	return session_controls_provider.call() if session_controls_provider.is_valid() else {}


func refresh_session_controls(force: bool = false) -> void:
	if not device_status:
		return
	var state := _session_controls()
	if not force and state == _footer_state:
		return
	_footer_state = state.duplicate()
	for index in range(_buttons.size() - 1, -1, -1):
		if _buttons[index].target in [CLOSE_MENU, FOLLOW, TEMP_PASSTHROUGH]:
			_buttons[index].node.free()
			_buttons.remove_at(index)
	var show_passthrough: bool = state.get("passthrough_visible", false)
	var count := 2 if show_passthrough else 1
	var span := count * FOOTER_DIAMETER + (count - 1) * FOOTER_GAP
	var width := span + FOOTER_GAP + STATUS_WIDTH
	var left := _footer_centre.x - width * 0.5
	device_status.position = Vector3(
		left + span + FOOTER_GAP + STATUS_WIDTH * 0.5, _footer_centre.y, 0.002
	)
	_footer_button(
		FOLLOW,
		"head_follow",
		Vector2(left + FOOTER_DIAMETER * 0.5, _footer_centre.y),
		state.get("follow", false),
		true,
		I18n.t("Disable follow" if state.get("follow", false) else "Enable follow")
	)
	if show_passthrough:
		var alpha: bool = state.get("alpha", false)
		_footer_button(
			TEMP_PASSTHROUGH,
			"passthrough",
			Vector2(left + span - FOOTER_DIAMETER * 0.5, _footer_centre.y),
			state.get("passthrough", false),
			not alpha,
			I18n.t(
				(
					"Cannot switch during person passthrough"
					if alpha
					else (
						"Disable temporary passthrough"
						if state.get("passthrough", false)
						else "Enable temporary passthrough"
					)
				)
			)
		)
	_update_highlights()


func _footer_button(
	target: int, icon: String, centre: Vector2, active: bool, enabled: bool, tip: String
) -> void:
	_round(target, icon, centre, FOOTER_DIAMETER, enabled, active, tip)
	var button: Dictionary = _buttons.back()
	button.rect = Rect2(centre - Vector2.ONE * FOOTER_HIT_SIZE * 0.5, Vector2.ONE * FOOTER_HIT_SIZE)
	button["hover_disabled"] = true
	button["tip_below"] = true
	if active:
		var marker := _quad(
			Vector2(0.014, 0.004),
			Vector3(0, -0.032, 0.005),
			button.foreground if enabled else MUTED,
			12
		)
		button.node.add_child(marker)


func _decoration(size: Vector2, centre: Vector2, color: Color) -> MeshInstance3D:
	var node := _quad(size, Vector3(centre.x, centre.y, 0.003), color, 12)
	add_child(node)
	_decorations.append(node)
	return node


func _icon(
	key: String, location: Vector3, size: float, color: Color, parent: Node = self
) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * size
	node.mesh = mesh
	node.position = location
	var material := _material(color, 12)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = Icons.texture(key)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	node.material_override = material
	parent.add_child(node)
	if parent == self:
		_decorations.append(node)
	return node


func _quad(size: Vector2, location: Vector3, color: Color, priority: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	if priority in [10, 30]:
		node.set_meta("xr_ui_panel", true)
	var mesh := QuadMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = location
	var surface := ShaderMaterial.new()
	surface.shader = SURFACE
	surface.render_priority = priority
	surface.set_shader_parameter("surface_color", color)
	surface.set_shader_parameter("surface_size", size)
	var panel := priority in [10, 30]
	# Panels get a hairline edge and a faint top light so they separate from bright
	# skyboxes and passthrough; controls only lift slightly towards their top.
	surface.set_shader_parameter(
		"border_width", 0.0016 if panel else (0.0012 if priority == 11 else 0.0)
	)
	surface.set_shader_parameter("border_color", PANEL_EDGE if panel else OUTLINE)
	surface.set_shader_parameter(
		"corner_radius", PANEL_RADIUS if priority == 10 else CONTROL_RADIUS
	)
	surface.set_shader_parameter("sheen", 0.025 if panel else (0.018 if priority == 11 else 0.0))
	surface.set_shader_parameter("rim_light", 0.06 if panel else 0.0)
	node.material_override = surface
	return node


func _material(color: Color, priority: int, overlay: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	# Keep icons/thumbnails in the ordered UI pass without writing depth over other UI.
	# Only the interaction ray/reticle bypass the depth of tracked input models.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.no_depth_test = overlay
	material.render_priority = priority
	return material


func _label(text: String, location: Vector3, size: int, parent: Node = self) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = ui_font()
	label.language = I18n.language
	label.font_size = size
	label.pixel_size = 0.0012
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	label.position = location
	label.no_depth_test = false
	label.render_priority = 12
	label.outline_size = 0
	parent.add_child(label)
	if parent == self:
		_labels.append(label)
	return label


func _pointer(hand: String) -> Dictionary:
	if _pointers.has(hand):
		return _pointers[hand]
	var color := Color(0.15, 0.9, 1.0) if hand == "left_hand" else Color(1.0, 0.65, 0.15)
	var line := PointerRay.create(Color(color, PointerRay.IDLE_OPACITY), 14)
	line.set_meta("xr_ui_pointer", true)
	line.set_meta("xr_ui_scene_ray", true)
	add_child(line)
	var dot := MeshInstance3D.new()
	dot.set_meta("xr_ui_pointer", true)
	var sphere := SphereMesh.new()
	sphere.radius = 0.009
	sphere.height = 0.018
	dot.mesh = sphere
	dot.material_override = _material(color, 15, true)
	add_child(dot)
	_pointers[hand] = {"line": line, "dot": dot, "color": color}
	return _pointers[hand]


func _update_highlights() -> void:
	for button in _buttons:
		button.node.visible = (
			button.get("layout_visible", true)
			and (
				button.enabled
				or button.get("keep_visible", false)
				or button.get("fixed_current", false)
			)
		)
		var hovered: bool = button.enabled and _hover.values().has(button.target)
		var color: Color = button.base_color
		if not button.enabled:
			color = (
				ACCENT_DIM
				if button.get("hover_disabled", false) and button.base_color == ACCENT
				else Color(DISABLED, button.base_color.a)
			)
		elif hovered:
			color = (
				ACCENT_HOVER
				if button.base_color == ACCENT
				else (SELECTED_HOVER if button.base_color == SELECTED else HOVER)
			)
		var outline: Color = (
			(ACCENT if button.base_color != ACCENT else ACCENT_HOVER)
			if hovered or button.get("open_choice", false) or button.base_color == SELECTED
			else OUTLINE
		)
		if button.node.material_override.get_shader_parameter("border_color") != outline:
			button.node.material_override.set_shader_parameter("border_color", outline)
		if button.node.material_override.get_shader_parameter("surface_color") != color:
			button.node.material_override.set_shader_parameter("surface_color", color)
	_update_tooltip()


func _update_tooltip() -> void:
	var shown := {}
	for button in _buttons:
		if (
			button.node.is_visible_in_tree()
			and (button.enabled or button.get("hover_disabled", false))
			and not str(_tips.get(button.target, "")).strip_edges().is_empty()
			and _hover.values().has(button.target)
		):
			shown = button
			break
	if shown.is_empty():
		if _tooltip:
			_tooltip.visible = false
		return
	if not _tooltip:
		_tooltip = _quad(Vector2(0.2, 0.05), Vector3.ZERO, Color(0.016, 0.027, 0.05, 0.94), 16)
		_tooltip.material_override.set_shader_parameter("border_width", 0.0012)
		_tooltip.material_override.set_shader_parameter("border_color", PANEL_EDGE)
		_tooltip.set_meta("xr_ui_transient_bounds", true)
		add_child(_tooltip)
		var text := _label("", Vector3(0, 0, 0.002), 17, _tooltip)
		text.render_priority = 17
	var label: Label3D = _tooltip.get_child(0)
	var text := str(_tips[shown.target]).strip_edges()
	var width := minf(
		TOOLTIP_MAX_WIDTH - 0.04,
		ui_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x * label.pixel_size
	)
	label.font = ui_font()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = maxf(width, 0.01) / label.pixel_size
	var measured := ui_font().get_multiline_string_size(
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		label.width,
		17,
		-1,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	)
	var size := Vector2(width + 0.04, maxf(0.046, measured.y * label.pixel_size + 0.02))
	_tooltip.mesh.size = size
	_tooltip.material_override.set_shader_parameter("surface_size", size)
	var rect: Rect2 = shown.rect
	var centre := to_local(shown.node.global_position)
	var at := Vector2(
		centre.x,
		(
			centre.y
			+ (
				(-1.0 if shown.get("tip_below", false) else 1.0)
				* (rect.size.y * 0.5 + size.y * 0.5 + 0.017)
			)
		)
	)
	var envelope := capture_envelope()
	if envelope.has_area():
		at.x = clampf(at.x, envelope.position.x + size.x * 0.5, envelope.end.x - size.x * 0.5)
		at.y = clampf(at.y, envelope.position.y + size.y * 0.5, envelope.end.y - size.y * 0.5)
	_tooltip.position = Vector3(at.x, at.y, 0.012)
	_tooltip.visible = true


## Reserve hover text before it becomes visible. Hover must not resize/recentre
## the capture or its cylinder, which can move the target out from under the ray.
func tooltip_envelope() -> Rect2:
	var reserved := capture_envelope()
	if reserved.has_area():
		# Reserve the same footer-tip margin for every page in the family.
		return reserved.grow_individual(0, TOOLTIP_MARGIN, 0, TOOLTIP_MARGIN)
	var bounds := Rect2()
	for button in _buttons:
		if not _tips.has(button.target):
			continue
		var rect: Rect2 = button.rect
		var y := rect.position.y - 0.04 if button.get("tip_below", false) else rect.end.y + 0.04
		var region := Rect2(
			Vector2(rect.get_center().x - TOOLTIP_MAX_WIDTH / 2, y - 0.023),
			Vector2(TOOLTIP_MAX_WIDTH, 0.046)
		)
		bounds = bounds.merge(region) if bounds.has_area() else region
	return bounds


func _fit_title(title: String, suffix: String, width: float = 1.32, font_size: int = 26) -> String:
	var fits := func(text: String) -> bool:
		return (
			ui_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.0012
			<= width
		)
	if title.is_empty() or fits.call(title + suffix):
		return title + suffix
	# Longest prefix that fits with the ellipsis, by bisection: every measure shapes the text.
	var low := 0
	var high := title.length() - 1
	while low < high:
		var middle := (low + high + 1) / 2
		if fits.call(title.left(middle) + "…" + suffix):
			low = middle
		else:
			high = middle - 1
	return title.left(low) + "…" + suffix


func text_snapshot() -> String:
	var lines := PackedStringArray()
	for label in _labels:
		lines.append(label.text)
	for button in _buttons:
		lines.append(button.node.get_child(0).text)
	return "\n".join(lines)


## Fingerprint of subclass-owned paint state, used without member-name reflection.
func paint_state_key() -> int:
	return 0


## Explicit deterministic action entry for host tests; runtime dispatch stays private.
func test_activate(target: int) -> void:
	_activate(target)


static func _freeze_snapshot(value: Variant) -> Variant:
	if value is Dictionary:
		for key in value:
			_freeze_snapshot(value[key])
		value.make_read_only()
	elif value is Array:
		for item in value:
			_freeze_snapshot(item)
		value.make_read_only()
	return value


static func _visual_snapshot(node: Node3D) -> Dictionary:
	if not is_instance_valid(node):
		return {}
	var ancestors: Array[int] = []
	var parent := node.get_parent()
	while parent:
		ancestors.append(parent.get_instance_id())
		parent = parent.get_parent()
	var children: Array[Dictionary] = []
	for child in node.get_children():
		if child is Node3D:
			children.append(_visual_snapshot(child))
	var result := {
		"instance_id": node.get_instance_id(),
		"kind": node.get_class(),
		"parent_id": node.get_parent().get_instance_id() if node.get_parent() else 0,
		"material_override": {"kind": ""},
		"position": node.position,
		"transform": node.transform,
		"scale": node.scale,
		"global_position": node.global_position if node.is_inside_tree() else node.position,
		"global_basis": node.global_basis if node.is_inside_tree() else node.basis,
		"global_transform": node.global_transform if node.is_inside_tree() else node.transform,
		"visible": node.visible,
		"visible_in_tree": node.is_visible_in_tree(),
		"ancestor_ids": ancestors,
		"children": children
	}
	if node is GeometryInstance3D:
		result["layers"] = node.layers
		var material: Material = node.material_override
		if material:
			var style := {"kind": material.get_class(), "render_priority": material.render_priority}
			if material is ShaderMaterial:
				style["surface_color"] = material.get_shader_parameter("surface_color")
				var texture: Variant = material.get_shader_parameter("surface_texture")
				style["surface_texture_id"] = (
					texture.get_instance_id() if texture is Texture2D else 0
				)
			elif material is StandardMaterial3D:
				style["albedo_color"] = material.albedo_color
				style["albedo_texture_id"] = (
					material.albedo_texture.get_instance_id() if material.albedo_texture else 0
				)
			result["material_override"] = style
	if node is MeshInstance3D and node.mesh:
		result["mesh"] = {
			"aabb": node.mesh.get_aabb(), "surface_count": node.mesh.get_surface_count()
		}
		if node.mesh is QuadMesh:
			result.mesh["size"] = node.mesh.size
	if node is Label3D:
		result["text"] = node.text
		result["font_size"] = node.font_size
		result["pixel_size"] = node.pixel_size
	return result


## Detached geometry/value records; never exposes the live rendering nodes.
func controls_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for button in _buttons:
		result.append(
			{
				"target": button.target,
				"rect": button.rect,
				"enabled": button.enabled,
				"base_color": button.base_color,
				"foreground": button.foreground,
				"node": _visual_snapshot(button.node)
			}
		)
	_freeze_snapshot(result)
	return result


func hover_snapshot() -> Dictionary:
	return _freeze_snapshot(_hover.duplicate(true))


func pointer_snapshot() -> Dictionary:
	var result := {}
	for hand in _pointers:
		var pointer: Dictionary = _pointers[hand]
		var material: ShaderMaterial = pointer.line.material_override
		var start: Variant = material.get_shader_parameter("ray_start")
		var end: Variant = material.get_shader_parameter("ray_end")
		var initialized: bool = start is Vector3 and end is Vector3
		if not start is Vector3:
			start = Vector3.ZERO
		if not end is Vector3:
			end = Vector3.ZERO
		var line := _visual_snapshot(pointer.line)
		var pose: Transform3D = line.global_transform
		result[hand] = {
			"dot": _visual_snapshot(pointer.dot),
			"line": line,
			"endpoints_initialized": initialized,
			"local_start": start,
			"local_end": end,
			"world_start": pose * start,
			"world_end": pose * end
		}
	return _freeze_snapshot(result)


func backdrop_snapshot() -> Dictionary:
	return _freeze_snapshot(_visual_snapshot(_backdrop))


func test_set_hover(hand: String, target: int) -> void:
	if hand.is_empty():
		_hover.clear()
	else:
		_hover[hand] = target


func test_set_pointer_visible(hand: String, visible: bool) -> void:
	if _pointers.has(hand):
		_pointers[hand].dot.visible = visible


func test_set_control_enabled(target: int, enabled: bool) -> void:
	for button in _buttons:
		if button.target == target:
			button.enabled = enabled


func test_duplicate_control(target: int) -> MeshInstance3D:
	for button in _buttons:
		if button.target == target:
			var copy := button.node.duplicate() as MeshInstance3D
			var nodes: Array = [copy]
			nodes.append_array(copy.find_children("*", "GeometryInstance3D", true, false))
			for node in nodes:
				if node.material_override:
					node.material_override = node.material_override.duplicate(true)
				if node is MeshInstance3D and node.mesh:
					node.mesh = node.mesh.duplicate(true)
			return copy
	return null


func test_set_control_transform(target: int, transform: Transform3D) -> void:
	for button in _buttons:
		if button.target == target:
			button.node.transform = transform


func test_set_control_visibility(target: int, keep_visible: bool, layout_visible: bool) -> void:
	for button in _buttons:
		if button.target == target:
			button["keep_visible"] = keep_visible
			button["layout_visible"] = layout_visible
