extends RefCounted
const I18n := preload("res://scripts/i18n.gd")
const SubtitleDepth := preload("res://scripts/subtitle_depth.gd")
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
	var heading: Label3D = menu._label(menu.I18n.t(title), Vector3(-0.49, top - 0.045, 0.004), 20)
	heading.font = menu.ui_font_bold()
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
			_slider("Distance", "screen_distance", Vector3(0.1, 50, 0.05), 2, " m", y - 0.09, 2)
			_slider("Size", "screen_scale", Vector3(5, 3000, 5), 100, "%", y - 0.18, 0)
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
							(
								-10.0
								if int(menu._state.get("geometry", 0)) != 0
								else -menu.StereoView.LIMIT
							),
							(
								10.0
								if int(menu._state.get("geometry", 0)) != 0
								else menu.StereoView.LIMIT
							),
							menu.StereoView.STEP
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
			func(key):
				return not is_equal_approx(
					float(values.get(key, menu.Grade.DEFAULTS[key])), menu.Grade.DEFAULTS[key]
				),
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


func draw_active() -> void:
	menu._reset_popup_fields()
	menu.bookmarks.draw_popup()
	if not menu._quick_open.is_empty():
		draw_quick()
	if menu._mode_open:
		draw_modes()
	if menu._subtitle_open:
		draw_subtitles()
	menu._bar_drawn = menu._bar_key()


## Compact controls share the normal setting/adjustment signals and persistence.
func draw_quick() -> void:
	if not menu._state.get("has_video", false) and menu._quick_open != "info":
		menu._quick_open = ""
		return
	if menu._quick_open == "queue":
		menu.queue_menu.draw()
	else:
		menu.playback_popups.draw(menu._quick_open)


func subtitle_tracks() -> Array:
	return menu._state.get("subtitle_options", [])


func subtitle_label(track: Dictionary) -> String:
	var title := str(track.get("title", "")).strip_edges()
	if title.is_empty():
		title = str(track.get("language", "")).strip_edges()
	if title.is_empty():
		title = I18n.t("Subtitles") + " %d" % int(track.id)
	var codec := str(track.get("codec", "")).to_upper().replace("SUBRIP", "SRT").replace(
		"WEBVTT", "VTT"
	)
	return menu._fit_title(
		title.replace("\n", " "),
		" · " + (I18n.t("Encoding invalid") if track.get("encoding_invalid", false) else codec),
		0.76,
		20
	)


func subtitle_controls() -> Array:
	var rows: Array = []
	var encoding: Dictionary = menu._state.get(
		"secondary_subtitle_encoding_row" if menu._subtitle_secondary else "subtitle_encoding_row",
		{}
	)
	if not encoding.is_empty():
		rows.append({"title": "Encoding (reopen video)", "field": encoding})
	if immersive_subtitles():
		rows.append(
			{
				"title": "Subtitle direction",
				"field": SubtitleDepth.direction_row(int(menu._state.get("subtitle_direction", 0)))
			}
		)
		rows.append(
			{
				"title":
				(
					"Horizontal position"
					if int(menu._state.get("subtitle_direction", 0)) == 1
					else "Subtitle position"
				),
				"field":
				SubtitleDepth.slider_row(
					"subtitle_position", float(menu._state.get("subtitle_position", 0.0))
				)
			}
		)
		rows.append(
			{
				"title": "Distance",
				"field":
				SubtitleDepth.slider_row(
					"subtitle_distance", float(menu._state.get("subtitle_distance", 5.0))
				)
			}
		)
	else:
		rows.append(
			{
				"title": "Vertical position",
				"field":
				{
					"key": "subtitle_flat_position",
					"enabled": not menu._state.get("subtitle_below_screen", false),
					"display_value":
					"%.0f%%" % float(menu._state.get("subtitle_flat_position", 0.0)),
					"value": menu._state.get("subtitle_flat_position", 0.0),
					"slider": true,
					"span": Vector3(0, 100, 1),
					"unit": "%",
					"reset_value": 0.0
				}
			}
		)
	rows.append(
		{
			"title": "Text size",
			"field":
			{
				"key": "subtitle_size",
				"value": menu._state.get("subtitle_size", 100.0),
				"slider": true,
				"span": Vector3(50, 200, 5),
				"unit": "%",
				"reset_value": 100.0
			}
		}
	)
	rows.append(
		{
			"title": "Text color",
			"field":
			preload("res://scripts/caption_palette.gd").choices(
				int(menu._state.get("subtitle_palette", 0))
			)
		}
	)
	rows.append(
		{
			"title": "Subtitles below screen",
			"field":
			{
				"key": "subtitle_below_screen",
				"value": menu._state.get("subtitle_below_screen", false),
				"enabled": menu._state.get("has_video", false) and not immersive_subtitles(),
				"hint": "Available for flat video only" if immersive_subtitles() else "",
				"choices": [{"value": false, "label": "Off"}, {"value": true, "label": "On"}]
			}
		}
	)
	return rows


func draw_subtitles() -> void:
	var tracks := subtitle_tracks()
	menu._subtitle_offset = clampi(
		menu._subtitle_offset, 0, maxi(0, tracks.size() - menu.SUBTITLE_ROWS)
	)
	var rows := subtitle_controls()
	var scrolling: bool = tracks.size() > menu.SUBTITLE_ROWS
	var height := (
		0.26
		+ (1 + mini(tracks.size(), menu.SUBTITLE_ROWS)) * 0.075
		+ rows.size() * 0.10
		+ 0.18
		+ (0.06 if scrolling else 0.0)
	)
	var top := 0.285 + height
	var panel: MeshInstance3D = menu._quad(
		Vector2(1.10, height), Vector3(0, 0.285 + height / 2, 0.001), Color(menu.PANEL, 0.96), 10
	)
	panel.material_override.set_shader_parameter("corner_radius", 0.025)
	menu.add_child(panel)
	menu._decorations.append(panel)
	var heading: Label3D = menu._label(I18n.t("Subtitles"), Vector3(-0.48, top - 0.05, 0.004), 20)
	heading.font = menu.ui_font_bold()
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var y := top - 0.125
	menu.choices.field(
		null,
		{
			"key": "dual_subtitles",
			"value": menu._state.get("dual_subtitles", false),
			"enabled": menu._state.get("dual_subtitles_available", false),
			"choices": [{"value": false, "label": "Off"}, {"value": true, "label": "On"}]
		},
		Vector2(0.14, y),
		0.64
	)
	var dual_title: Label3D = menu._label(I18n.t("Dual subtitles"), Vector3(-0.48, y, 0.004), 17)
	dual_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	y -= 0.09
	menu.choices.field(
		null,
		{
			"key": "subtitle_target",
			"value": menu._subtitle_secondary,
			"enabled": menu._state.get("dual_subtitles_available", false),
			"choices":
			[
				{"value": false, "label": "Primary subtitle"},
				{"value": true, "label": "Secondary subtitle"}
			]
		},
		Vector2(0, y),
		0.96
	)
	y -= 0.09
	subtitle_row(menu.SUBTITLE_ROW, 0, I18n.t("Off"), y)
	y -= 0.075
	for index in range(
		menu._subtitle_offset, mini(tracks.size(), menu._subtitle_offset + menu.SUBTITLE_ROWS)
	):
		var track: Dictionary = tracks[index]
		subtitle_row(menu.SUBTITLE_ROW + index + 1, int(track.id), subtitle_label(track), y)
		y -= 0.075
	if scrolling:
		menu._button(
			menu.SUBTITLE_UP,
			"↑",
			Vector2(-0.07, y + 0.015),
			Vector2(0.10, 0.05),
			menu._subtitle_offset > 0
		)
		menu._button(
			menu.SUBTITLE_DOWN,
			"↓",
			Vector2(0.07, y + 0.015),
			Vector2(0.10, 0.05),
			menu._subtitle_offset + menu.SUBTITLE_ROWS < tracks.size()
		)
		y -= 0.06
	y -= 0.01
	for row in rows:
		var title: Label3D = menu._label(I18n.t(row.title), Vector3(-0.48, y, 0.004), 17)
		if row.field.get("key", "") == "subtitle_below_screen" and immersive_subtitles():
			var unavailable: Label3D = menu._label(
				I18n.t("Available for flat video only"), Vector3(0.14, y - 0.032, 0.004), 12
			)
			unavailable.modulate = menu.MUTED
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		menu.choices.field(null, row.field, Vector2(0.14, y), 0.64, 0.075)
		y -= 0.10
	menu._button(
		menu.SUBTITLE_LOAD,
		I18n.t("Load subtitle file"),
		Vector2(-0.25, 0.365),
		Vector2(0.47, 0.065),
		not menu._state.get("subtitle_loading", false)
	)
	menu._button(
		menu.SYNC_SETTINGS, I18n.t("Synchronization"), Vector2(0.25, 0.365), Vector2(0.47, 0.065)
	)
	var hint: Label3D = menu._label(
		I18n.t("Matching subtitles load automatically; choose other files manually."),
		Vector3(0, 0.31, 0.004),
		13
	)
	hint.modulate = menu.MUTED
	var example: Label3D = menu._label(I18n.t("movie.mp4 → movie.srt"), Vector3(0, 0.28, 0.004), 12)
	example.modulate = menu.MUTED
	menu.choices.bounds = Vector2(0.285, top - 0.08)
	menu.choices.finish()


func immersive_subtitles() -> bool:
	return menu._state.get("has_video", false) and int(menu._state.get("geometry", 0)) != 0


func subtitle_row(target: int, id: int, text: String, y: float) -> void:
	menu._subtitle_ids[target] = id
	var enabled: bool = (
		not menu._subtitle_secondary
		or (
			menu._state.get("dual_subtitles", false)
			and (id == 0 or id != int(menu._state.get("primary_subtitle_id", 0)))
		)
	)
	menu._button(target, text, Vector2(0, y), Vector2(0.92, 0.065), enabled)
	var button: Dictionary = menu._buttons.back()
	var label: Label3D = button.node.get_child(0)
	label.font_size = 20
	label.position.x = -0.42
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if (
		id
		== int(
			menu._state.get(
				"secondary_subtitle_track" if menu._subtitle_secondary else "subtitle_track", 0
			)
		)
	):
		button.base_color = menu.SELECTED
		menu._icon("check", Vector3(0.414, 0, 0.004), 0.029, menu.ACCENT, button.node)


func supports_half_layouts() -> bool:
	return true


## Video mode: every projection and stereo layout at once, the current ones lit (no cycling).
## Pressing a lit tile again locks that projection and layout for unnamed new files (a lock on
## the corner of both); pressing a locked one again unlocks.
func draw_modes() -> void:
	menu._lit_modes = {}
	var half_choices := supports_half_layouts()
	var lock: Dictionary = menu._state.get("mode_lock", {})
	var locked := {}
	if not lock.is_empty():
		locked[menu.MODE_PROJECTION + int(lock.geometry)] = true
		locked[menu.MODE_STEREO + [0, 1, 4, 5, 6][int(lock.layout)]] = true
	var fisheye := int(menu._state.get("geometry", 0)) == 2
	# The lens row sits under the layouts: the panel rises to clear the floating round buttons.
	var top := 0.61 if fisheye else 0.47
	if half_choices:
		top = 0.465 if fisheye else 0.365
	# Fisheye adds a row of lens angles under the layouts.
	var height := (0.33 if fisheye else 0.24) if half_choices else (0.5 if fisheye else 0.36)
	var centre_y := (
		(0.44 if fisheye else 0.385) if half_choices else top - (0.07 if fisheye else 0.0)
	)
	if half_choices:
		height += .1
		centre_y += .05
		top += .1
	var panel: MeshInstance3D = menu._quad(
		Vector2(1.06, height), Vector3(0, centre_y, 0.001), Color(menu.PANEL, 0.94), 10
	)
	panel.material_override.set_shader_parameter("corner_radius", 0.04)
	menu.add_child(panel)
	menu._decorations.append(panel)
	var projection := int(menu._state.get("geometry", 0))
	var names := ["Flat", "180°", "Fisheye", "360°"]
	var icons := ["screen", "dome", "fisheye", "panorama"]
	var projection_order := [0, 1, 3, 2]
	for column in projection_order.size():
		var g: int = projection_order[column]
		mode_tile(
			menu.MODE_PROJECTION + g,
			I18n.t(names[g]),
			icons[g],
			Vector2(-0.3 + column * 0.2, top + 0.075),
			projection == g,
			true
		)
	var stereo: bool = menu._state.get("stereo", false)
	var tb: bool = stereo and menu._state.get("top_bottom", false)
	var half_layout: bool = stereo and menu._state.get("stereo_half", false)
	var layouts_y := top - (0.04 if half_choices else 0.09)
	mode_tile(menu.MODE_STEREO, "2D", "screen", Vector2(-0.4, layouts_y), not stereo, true)
	mode_tile(
		menu.MODE_STEREO + 1,
		I18n.t("3D SBS"),
		"stereo",
		Vector2(-0.2, layouts_y),
		stereo and not tb and not half_layout,
		true
	)
	mode_tile(
		menu.MODE_STEREO + 4,
		I18n.t("3D TB"),
		"stacked",
		Vector2(0.2 if half_choices else 0, layouts_y),
		tb and not half_layout,
		true
	)
	if half_choices:
		mode_tile(
			menu.MODE_STEREO + 5,
			I18n.t("Half SBS"),
			"stereo",
			Vector2(0, layouts_y),
			stereo and not tb and half_layout,
			true
		)
		mode_tile(
			menu.MODE_STEREO + 6,
			I18n.t("Half TB"),
			"stacked",
			Vector2(0.4, layouts_y),
			tb and half_layout,
			true
		)
	var controls_y := top - (0.15 if half_choices else 0.09)
	if not half_choices:
		mode_tile(
			menu.MODE_STEREO + 2,
			menu._caption("eyes"),
			"eyes",
			Vector2(0.4, controls_y),
			false,
			stereo
		)
	if fisheye:
		for i in menu.LENS_FOVS.size():
			menu._button(
				menu.MODE_LENS + i,
				"%d°" % menu.LENS_FOVS[i],
				Vector2(-0.3 + i * 0.2, layouts_y - 0.11 if half_choices else controls_y - 0.145),
				Vector2(0.18, 0.06 if half_choices else 0.08)
			)
			if int(menu._state.get("fisheye_fov", 180)) == menu.LENS_FOVS[i]:
				menu._buttons.back().base_color = menu.SELECTED
	if half_choices:
		menu._control_button(
			menu.MODE_STEREO + 7,
			I18n.t("Auto detect"),
			Vector2(0, controls_y - (.09 if fisheye else 0.0)),
			.96,
			true,
			"refresh"
		)
	for button in menu._buttons:
		if locked.has(button.target):
			var half: Vector2 = button.rect.size / 2
			menu._icon(
				"lock",
				Vector3(half.x - 0.022, half.y - 0.022, 0.005),
				0.026,
				menu.ACCENT,
				button.node
			)


func mode_tile(
	target: int, text: String, icon: String, centre: Vector2, current: bool, enabled: bool = true
) -> void:
	var height := (
		(0.08 if target in [menu.MODE_STEREO + 2, menu.MODE_STEREO + 3] else 0.1)
		if supports_half_layouts()
		else 0.13
	)
	menu._button(target, text, centre, Vector2(0.18, height), enabled, icon)
	if current:
		menu._buttons.back().base_color = menu.SELECTED
		if enabled:
			menu._lit_modes[target] = true
		else:
			menu._buttons.back()["fixed_current"] = true
			menu._buttons.back().node.get_child(0).modulate = menu._buttons.back().foreground
			menu._buttons.back().node.get_child(1).material_override.albedo_color = menu.ACCENT


func draw_adjustments() -> void:
	menu._quick_open = {"sync": "sync", "stereo_view": "ipd", "color_grade": "color"}.get(
		menu._adjustment, ""
	)
	menu._adjustment = ""
	menu.section = 0
	menu._draw_bar()
