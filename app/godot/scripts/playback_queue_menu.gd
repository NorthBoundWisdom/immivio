extends RefCounted
const BASE := 20000
const ROWS := 3
var menu: Node3D
var offset := 0
var _scroll := 0.0
var actions := {}

func _init(owner: Node3D) -> void: menu = owner

func draw() -> void:
	var panel: MeshInstance3D = menu._quad(Vector2(1.12, 0.445), Vector3(0, 0.4975, 0.001), Color(menu.PANEL, 0.94), 10)
	menu.add_child(panel); menu._decorations.append(panel)
	var heading: Label3D = menu._label(menu.I18n.t("Queue"), Vector3(-0.49, 0.68, 0.004), 19)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	menu._glyph(menu.QUICK_CLOSE, "close", Vector2(0.49, 0.68), 0.06, true, menu.I18n.t("Close"))
	actions.clear()
	var entries: Array = menu._state.get("queue_items", [])
	offset = clampi(offset, 0, maxi(0, ((entries.size() - 1) / ROWS) * ROWS))
	var shuffle: Label3D = menu._label(menu.I18n.t("Shuffle"), Vector3(-0.49, 0.605, 0.004), 16)
	shuffle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	menu.choices.field(null, {"key": "queue_shuffle", "value": menu._state.get("queue_shuffle", false), "compact": true,
		"choices": [{"value": false, "label": "Off"}, {"value": true, "label": "On"}]}, Vector2(0.28, 0.605), 0.48, 0.055)
	for i in range(offset, mini(entries.size(), offset + ROWS)):
		var y := 0.53 - (i - offset) * 0.07
		button("queue_play_" + str(i), str(i + 1) + " · " + str(entries[i].title), Vector2(-0.18, y), Vector2(0.72, 0.06))
		if entries[i].uri == menu._state.get("source_uri", ""): menu._buttons.back().base_color = menu.SELECTED
		button("queue_up_" + str(i), "↑", Vector2(0.25, y), Vector2(0.07, 0.06), i > 0)
		button("queue_down_" + str(i), "↓", Vector2(0.34, y), Vector2(0.07, 0.06), i + 1 < entries.size())
		button("queue_remove_" + str(i), "×", Vector2(0.46, y), Vector2(0.08, 0.06))
	if entries.is_empty(): menu._label(menu.I18n.t("Queue is empty"), Vector3(0, 0.46, 0.004), 18)
	button("page_previous", "‹", Vector2(-0.49, 0.315), Vector2(0.07, 0.06), offset > 0)
	menu._label("%d / %d" % [offset / ROWS + 1, maxi(1, ceili(float(entries.size()) / ROWS))], Vector3(-0.38, 0.315, 0.004), 14)
	button("page_next", "›", Vector2(-0.27, 0.315), Vector2(0.07, 0.06), offset + ROWS < entries.size())
	button("queue_add", menu.I18n.t("Add videos"), Vector2(-0.03, 0.315), Vector2(0.30, 0.06))
	button("queue_clear", menu.I18n.t("Clear queue"), Vector2(0.38, 0.315), Vector2(0.30, 0.06), not entries.is_empty())
	menu.choices.finish()

func button(operation: String, title: String, centre: Vector2, size: Vector2, enabled: bool = true) -> void:
	var id := BASE + actions.size()
	actions[id] = operation
	menu._button(id, menu._fit_title(title, "", size.x - 0.04, 16), centre, size, enabled)
	(menu._buttons.back().node.get_child(0) as Label3D).font_size = 16

func action(target: int) -> bool:
	if not actions.has(target): return false
	var operation: String = actions[target]
	if operation == "page_previous": offset = maxi(0, offset - ROWS)
	elif operation == "page_next": offset += ROWS
	else: menu.action_requested.emit(operation)
	menu.refresh()
	return true

func stick_scroll(y: float, delta: float) -> void:
	if not is_finite(y) or absf(y) < .4: _scroll = 0; return
	_scroll -= y * delta * 7
	if absf(_scroll) >= 1:
		offset += int(_scroll) * ROWS; _scroll -= int(_scroll); menu.refresh()
