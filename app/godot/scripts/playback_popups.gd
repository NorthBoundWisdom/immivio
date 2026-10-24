extends RefCounted
## Small, mutually exclusive controls above the persistent playback timeline.
const GRADE_PREVIOUS := 218
const GRADE_NEXT := 219
const GRADE_PAGE_RESET := 220
const GRADE_PAGES := [
	["temperature", "tint", "exposure"],
	["contrast", "gamma", "saturation"],
	["red_gain", "green_gain", "blue_gain"],
	["red_gamma", "green_gamma", "blue_gamma"],
	["red_offset", "green_offset", "blue_offset"]
]
const GRADE_TITLES := ["Basic", "Basic", "RGB gain", "RGB gamma / offset", "RGB gamma / offset"]
var menu: Node3D


func _init(owner: Node3D) -> void:
	menu = owner


func _panel(title: String, height: float) -> float:
	var top := 0.285 + height
	var panel: MeshInstance3D = menu._quad(
		Vector2(1.12, height), Vector3(0, 0.285 + height / 2, 0.001), Color(menu.PANEL, 0.96), 10
	)
	menu.add_child(panel)
	menu._decorations.append(panel)
	var heading: Label3D = menu._label(menu.I18n.t(title), Vector3(-0.49, top - 0.045, 0.004), 19)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	menu._glyph(
		menu.QUICK_CLOSE, "close", Vector2(0.49, top - 0.045), 0.06, true, menu.I18n.t("Close")
	)
	menu.choices.bounds = Vector2(0.30, top - 0.09)
	return top - 0.13


func _row(title: String, field: Dictionary, y: float) -> void:
	var label: Label3D = menu._label(
		menu._fit_title(menu.I18n.t(title), "", 0.35, 16), Vector3(-0.49, y, 0.004), 16
	)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	menu.choices.field(null, field, Vector2(0.22, y), 0.64)


func _slider(
	title: String,
	key: String,
	span: Vector3,
	fallback: float,
	unit: String,
	y: float,
	precision: int = 1,
	signed: bool = false
) -> void:
	var field := {
		"key": key,
		"value": menu._state.get(key, fallback),
		"slider": true,
		"logarithmic": key in ["screen_distance", "screen_scale"],
		"span": span,
		"unit": unit,
		"precision": precision,
		"signed": signed
	}
	# Speed keeps its familiar, separate Restore 1× action.
	if key != "playback_speed":
		field["reset_value"] = fallback
	_row(title, field, y)


func _button(
	target: int, title: String, centre: Vector2, width: float, enabled: bool = true
) -> void:
	menu._control_button(target, menu.I18n.t(title), centre, width, enabled)


func draw(key: String) -> void:
	match key:
		"screen":
			var y := _panel("Screen layout", 0.82)
			var presets: Array = []
			for item in preload("res://scripts/screen_presets.gd").ITEMS:
				presets.append({"value": item.id, "label": item.title, "hint": item.detail})
			_row(
				"Screen preset",
				{
					"key": "screen_preset",
					"value": menu._state.get("screen_preset", ""),
					"choices": presets
				},
				y
			)
			_slider("Distance", "screen_distance", Vector3(1, 50, 0.05), 2, " m", y - 0.09, 2)
			_slider("Size", "screen_scale", Vector3(100, 3000, 5), 100, "%", y - 0.18, 0)
			_slider("Eye level", "screen_eye_level", Vector3(0, 1, 0.05), 0.5, "", y - 0.27, 2)
			_row(
				"Curvature",
				{
					"key": "screen_curve",
					"value": menu._state.get("screen_curve", 0),
					"choices":
					[
						{"value": 0.0, "label": "Off"},
						{"value": 0.35, "label": "Slight"},
						{"value": 0.7, "label": "Medium"},
						{"value": 1.0, "label": "Surround"}
					]
				},
				y - 0.36
			)
			_row(
				"Fix viewing defaults",
				{
					"key": "screen_fixed",
					"value": menu._state.get("screen_fixed", false),
					"choices": [{"value": false, "label": "Off"}, {"value": true, "label": "On"}]
				},
				y - 0.45
			)
			_button(221, "Save as default", Vector2(-0.26, 0.43), 0.48)
			_button(222, "Positioning grid", Vector2(0.26, 0.43), 0.48)
		"speed":
			var y := _panel("Playback speed", 0.33)
			_slider("Playback speed", "playback_speed", Vector3(0.25, 3, 0.05), 1, "×", y, 2)
			menu.choices.field(
				null,
				{
					"key": "playback_speed",
					"value": menu._state.get("playback_speed", 1.0),
					"compact": true,
					"choices":
					[
						{"value": 0.5, "label": "0.5×"},
						{"value": 1.0, "label": "1×"},
						{"value": 1.5, "label": "1.5×"},
						{"value": 2.0, "label": "2×"}
					]
				},
				Vector2(0, y - 0.08),
				1.0
			)
			_button(
				menu.SPEED_RESET,
				"Restore 1×",
				Vector2(0, 0.335),
				0.40,
				not is_equal_approx(float(menu._state.get("playback_speed", 1)), 1)
			)
		"sync":
			var y := _panel("Synchronization", 0.40)
			_slider(
				"Subtitle delay",
				"subtitle_delay_ms",
				Vector3(-10000, 10000, 50),
				0,
				" ms",
				y,
				0,
				true
			)
			_slider(
				"Audio delay",
				"audio_delay_ms",
				Vector3(-10000, 10000, 50),
				0,
				" ms",
				y - 0.085,
				0,
				true
			)
			menu._label(menu.I18n.t("Positive: later · Negative: earlier"), Vector3(0, y - 0.155, 0.004), 14).modulate = (
				menu.MUTED
			)
			_button(
				menu.SUBTITLE_LOAD,
				"Load subtitle file",
				Vector2(-0.26, 0.335),
				0.49,
				not menu._state.get("subtitle_loading", false)
			)
			_button(
				menu.SUBTITLE_FORGET,
				"Forget subtitle file",
				Vector2(0.26, 0.335),
				0.49,
				(
					menu._state.get("external_subtitle", false)
					and not menu._state.get("subtitle_loading", false)
				)
			)
		"ipd":
			var stereo: bool = menu._enabled("stereo_view")
			var y := _panel("IPD", 0.49 if stereo else 0.23)
			if stereo:
				var modes: Array = []
				for i in menu.StereoView.MODES.size():
					modes.append({"value": i, "label": menu.StereoView.MODES[i]})
				menu.choices.field(
					null,
					{
						"key": "viewing_eye",
						"value": menu._state.get("viewing_eye", 0),
						"choices": modes,
						"compact": true
					},
					Vector2(0, y),
					1.0
				)
				_button(
					menu.EYE_SWAP,
					menu.I18n.t("Swap eyes") + "  " + menu._caption("eyes"),
					Vector2(0, y - 0.08),
					0.60,
					menu._enabled("eyes")
				)
				if int(menu._state.get("viewing_eye", 0)) == 0:
					_slider(
						"IPD compensation",
						"stereo_horizontal",
						Vector3(
							-menu.StereoView.LIMIT, menu.StereoView.LIMIT, menu.StereoView.STEP
						),
						0,
						"%",
						y - 0.16,
						2,
						true
					)
					_slider(
						"Vertical alignment",
						"stereo_vertical",
						Vector3(
							-menu.StereoView.LIMIT, menu.StereoView.LIMIT, menu.StereoView.STEP
						),
						0,
						"%",
						y - 0.235,
						2,
						true
					)
					_button(menu.ALIGNMENT_RESET, "Reset alignment", Vector2(0, 0.335), 0.45)
				else:
					menu._label(menu.I18n.t("Same view in both eyes"), Vector3(0, y - 0.18, 0.004), 17).modulate = (
						menu.MUTED
					)
			else:
				menu._label(menu._fit_title(menu.I18n.t("Select a stereo video layout to adjust IPD."), "", 1.0, 16), Vector3(0, y, 0.004), 16).modulate = (
					menu.MUTED
				)
		"color":
			var y := _panel("Color grading", 0.57)
			var options: Array = []
			for name in menu.Grade.PRESETS:
				options.append({"value": name, "label": name})
			menu.choices.field(
				null,
				{
					"key": "grade_preset",
					"value": menu._state.get("color_grade", {}).get("preset", "Original"),
					"choices": options,
					"compact": true
				},
				Vector2(0, y),
				1.0
			)
			var page: int = clampi(menu._grade_page, 0, GRADE_PAGES.size() - 1)
			_button(GRADE_PREVIOUS, "‹", Vector2(-0.46, y - 0.08), 0.08, page > 0)
			menu._label(
				menu.I18n.t(GRADE_TITLES[page]) + " · %d / %d" % [page + 1, GRADE_PAGES.size()],
				Vector3(0, y - 0.08, 0.004),
				16
			)
			_button(GRADE_NEXT, "›", Vector2(0.46, y - 0.08), 0.08, page + 1 < GRADE_PAGES.size())
			var values: Dictionary = menu._state.get("grade_values", menu.Grade.DEFAULTS)
			for i in GRADE_PAGES[page].size():
				var field: String = GRADE_PAGES[page][i]
				_row(
					menu.Grade.NAMES[field],
					{
						"key": field,
						"value": values.get(field, menu.Grade.DEFAULTS[field]),
						"slider": true,
						"logarithmic": key in ["screen_distance", "screen_scale"],
						"span": menu.Grade.limits(field),
						"unit": " K" if field == "temperature" else "",
						"precision":
						(
							0
							if field in ["temperature", "tint"]
							else (3 if field.ends_with("offset") else 2)
						),
						"reset_value": menu.Grade.DEFAULTS[field]
					},
					y - 0.16 - i * 0.075
				)
			_button(
				GRADE_PAGE_RESET,
				"Reset page",
				Vector2(-0.26, 0.335),
				0.46,
				_grade_page_needs_reset()
			)
			_button(440, "Reset custom", Vector2(0.26, 0.335), 0.46)
		"info":
			var y := _panel("Info", 0.47)
			menu._info = menu._label(info_text(), Vector3(-0.49, y + 0.025, 0.004), 16)
			menu._info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			menu._info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			menu._info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			menu._info.width = 800
			_button(menu.BROWSE, "Library", Vector2(0, 0.40), 0.5)
			_button(
				menu.INFO_REFRESH,
				"Refresh device info",
				Vector2(0, 0.335),
				0.65,
				menu._enabled("capabilities")
			)
	menu.choices.finish()


func info_text() -> String:
	var lines := PackedStringArray()
	if not str(menu._state.get("error", "")).is_empty():
		lines.append(str(menu._state.error))
		var detail := str(menu._state.get("error_detail", ""))
		# Let Label3D wrap complete diagnostics rather than silently ellipsizing them.
		if not detail.is_empty():
			lines.append(detail)
		return "\n".join(lines)
	for line in menu._info_text().split("\n"):
		lines.append(menu._fit_title(line, "", 1.0, 16))
	return "\n".join(lines)


func refresh_values() -> void:
	var grades: Dictionary = menu._state.get("grade_values", menu.Grade.DEFAULTS)
	for target in menu.choices.sliders:
		if int(menu.choices.capture.get("target", -1)) == target:
			continue
		var key: String = menu.choices.targets[target].key
		if menu._state.has(key):
			menu.choices._refresh_slider(target, float(menu._state[key]))
		elif grades.has(key):
			menu.choices._refresh_slider(target, float(grades[key]))
	for button in menu._buttons:
		if button.target == GRADE_PAGE_RESET:
			button.enabled = _grade_page_needs_reset()
			button.node.visible = button.enabled
			button.node.get_child(0).modulate = button.foreground if button.enabled else menu.MUTED
		if button.target == menu.SPEED_RESET:
			button.enabled = not is_equal_approx(float(menu._state.get("playback_speed", 1)), 1)
			button.node.visible = button.enabled
			button.node.get_child(0).modulate = button.foreground if button.enabled else menu.MUTED


func _grade_page_needs_reset() -> bool:
	var page := clampi(menu._grade_page, 0, GRADE_PAGES.size() - 1)
	var values: Dictionary = menu._state.get("grade_values", menu.Grade.DEFAULTS)
	return (
		menu._state.get("has_video", false)
		and GRADE_PAGES[page].any(
			func(key): return not is_equal_approx( float(values.get(key, menu.Grade.DEFAULTS[key])), menu.Grade.DEFAULTS[key] )
		)
	)


func action(target: int) -> bool:
	var key: String = menu._quick_open
	var adjustment := ""
	var value: Variant = 0.0
	if key == "screen" and target in [221, 222]:
		adjustment = "screen_save_default" if target == 221 else "screen_grid"
		value = true
	elif key == "speed" and target == menu.SPEED_RESET:
		adjustment = "playback_speed"
		value = 1.0
	elif key == "sync" and target in [menu.SUBTITLE_DELAY_RESET, menu.AUDIO_DELAY_RESET]:
		adjustment = (
			"subtitle_delay_ms" if target == menu.SUBTITLE_DELAY_RESET else "audio_delay_ms"
		)
	elif key == "ipd" and target == menu.EYE_SWAP:
		menu.action_requested.emit("eyes")
	elif key == "ipd" and target == menu.ALIGNMENT_RESET:
		adjustment = "stereo_reset"
		value = true
	elif key == "color" and target in [GRADE_PREVIOUS, GRADE_NEXT]:
		menu._grade_page = clampi(
			menu._grade_page + (-1 if target == GRADE_PREVIOUS else 1), 0, GRADE_PAGES.size() - 1
		)
	elif key == "color" and target == 440:
		adjustment = "grade_reset"
		value = true
	elif key == "color" and target == GRADE_PAGE_RESET:
		if not _grade_page_needs_reset():
			return true
		adjustment = "grade_reset_fields"
		value = GRADE_PAGES[clampi(menu._grade_page, 0, GRADE_PAGES.size() - 1)].duplicate()
	elif key == "info" and target == menu.INFO_REFRESH:
		menu.action_requested.emit("capabilities")
	else:
		return false
	if not adjustment.is_empty():
		menu.adjustment_requested.emit(adjustment, value)
		menu.adjustment_committed.emit()
	menu.refresh()
	return true
