extends RefCounted
const BASE := 20000
const ROWS := 4
var menu: Node3D
var offset := 0
var _scroll := 0.0
var actions := {}
var editing := false


func _init(owner: Node3D) -> void:
	menu = owner


## Playing is the default; ordering and removal stay behind Edit so rows read as a plain list.
func draw() -> void:
	var panel: MeshInstance3D = menu._quad(
		Vector2(1.12, 0.445), Vector3(0, 0.4975, 0.001), Color(menu.PANEL, 0.94), 10
	)
	menu.add_child(panel)
	menu._decorations.append(panel)
	actions.clear()
	var entries: Array = menu._state.get("queue_items", [])
	if entries.is_empty():
		editing = false
	offset = clampi(offset, 0, maxi(0, ((entries.size() - 1) / ROWS) * ROWS))
	var heading: Label3D = menu._label(
		menu.I18n.t("Queue") + ("  %d" % entries.size() if not entries.is_empty() else ""),
		Vector3(-0.49, 0.675, 0.004),
		20
	)
	heading.font = menu.ui_font_bold()
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var shuffle: bool = menu._state.get("queue_shuffle", false)
	var repeat: bool = menu._state.get("queue_loop", false)
	icon("toggle_shuffle", "shuffle", "Shuffle", 0.14, true, shuffle)
	icon("toggle_loop", "loop", "Repeat queue", 0.215, true, repeat)
	icon("queue_add", "plus", "Add videos", 0.325)
	icon(
		"toggle_edit",
		"check" if editing else "edit",
		"Done" if editing else "Edit",
		0.40,
		not entries.is_empty(),
		editing
	)
	menu._glyph(menu.QUICK_CLOSE, "close", Vector2(0.49, 0.675), 0.06, true, menu.I18n.t("Close"))
	var current: String = menu._state.get("queue_entry_uri", "")
	for i in range(offset, mini(entries.size(), offset + ROWS)):
		var y := 0.605 - (i - offset) * 0.07
		var width := 0.76 if editing else 1.0
		button(
			"queue_play_" + str(i),
			str(i + 1) + "   " + str(entries[i].title),
			Vector2(-0.50 + width / 2, y),
			Vector2(width, 0.06)
		)
		var row: Dictionary = menu._buttons.back()
		var label: Label3D = row.node.get_child(0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.position.x = -width / 2 + 0.025
		if entries[i].uri == current:
			row.base_color = menu.SELECTED
			row.node.material_override.set_shader_parameter("surface_color", menu.SELECTED)
			label.modulate = menu.ACCENT_HOVER
			label.font = menu.ui_font_bold()
		if editing:
			icon("queue_up_" + str(i), "arrow_up", "", 0.31, i > 0, false, y)
			icon("queue_down_" + str(i), "arrow_down", "", 0.38, i + 1 < entries.size(), false, y)
			icon("queue_remove_" + str(i), "close", "", 0.47, true, false, y)
	if entries.is_empty():
		menu._label(menu.I18n.t("Queue is empty"), Vector3(0, 0.50, 0.004), 18).modulate = (
			menu.MUTED
		)
	var pages := ceili(float(entries.size()) / ROWS)
	if pages > 1:
		icon("page_previous", "previous", "", -0.09, offset > 0, false, 0.315)
		menu._label("%d / %d" % [offset / ROWS + 1, pages], Vector3(0, 0.315, 0.004), 14)
		icon("page_next", "next", "", 0.09, offset + ROWS < entries.size(), false, 0.315)
	if editing:
		var id := BASE + actions.size()
		actions[id] = "queue_clear"
		menu._control_button(
			id, menu.I18n.t("Clear queue"), Vector2(0.37, 0.315), 0.26, true, "trash"
		)
	menu.choices.finish()


func icon(
	operation: String,
	glyph: String,
	tip: String,
	x: float,
	enabled: bool = true,
	active: bool = false,
	y: float = 0.675
) -> void:
	var id := BASE + actions.size()
	actions[id] = operation
	menu._button(id, "", Vector2(x, y), Vector2(0.06, 0.06), enabled, glyph, active)
	if not tip.is_empty():
		menu._tips[id] = menu.I18n.t(tip)


func button(operation: String, title: String, centre: Vector2, size: Vector2) -> void:
	var id := BASE + actions.size()
	actions[id] = operation
	menu._button(id, menu._fit_title(title, "", size.x - 0.06, 16), centre, size)
	(menu._buttons.back().node.get_child(0) as Label3D).font_size = 16


func action(target: int) -> bool:
	if not actions.has(target):
		return false
	var operation: String = actions[target]
	if operation == "page_previous":
		offset = maxi(0, offset - ROWS)
	elif operation == "page_next":
		offset += ROWS
	elif operation == "toggle_edit":
		editing = not editing
	elif operation == "toggle_shuffle" or operation == "toggle_loop":
		var key := "queue_shuffle" if operation == "toggle_shuffle" else "queue_loop"
		menu.setting_requested.emit(key, not bool(menu._state.get(key, false)))
	else:
		menu.action_requested.emit(operation)
	menu.refresh()
	return true


func stick_scroll(y: float, delta: float) -> void:
	if not is_finite(y) or absf(y) < .4:
		_scroll = 0
		return
	_scroll -= y * delta * 7
	if absf(_scroll) >= 1:
		offset += int(_scroll) * ROWS
		_scroll -= int(_scroll)
		menu.refresh()
