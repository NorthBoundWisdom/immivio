extends RefCounted
const BASE := 20000
const ROWS := 4
var menu: Node3D
var offset := 0
var _scroll := 0.0
var actions := {}

func _init(owner: Node3D) -> void: menu = owner

func draw() -> void:
	menu._set_backdrop(Vector2(1.55, 1.08))
	menu._draw_settings_tabs(0.38)
	menu._place_device_status(Vector2(0, -0.585))
	actions.clear()
	var entries: Array = menu._state.get("queue_items", [])
	offset = clampi(offset, 0, maxi(0, ((entries.size() - 1) / ROWS) * ROWS))
	var keys := ["queue_autoplay", "queue_repeat", "queue_shuffle"]
	var names := ["Auto-play next", "Repeat queue", "Shuffle"]
	for i in keys.size():
		var y := 0.25 - i * 0.095
		var label: Label3D = menu._label(menu.I18n.t(names[i]), Vector3(-0.65, y, 0.004), 18)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		menu.choices.field(null, {"key": keys[i], "value": menu._state.get(keys[i], false),
			"choices": [{"value": false, "label": "Off"}, {"value": true, "label": "On"}]}, Vector2(0.33, y), 0.6, 0.065)
	for i in range(offset, mini(entries.size(), offset + ROWS)):
		var y := -0.065 - (i - offset) * 0.102
		button("queue_play_" + str(i), str(i + 1) + " · " + menu._fit_title(str(entries[i].title), "", 0.72, 18), Vector2(-0.18, y), Vector2(0.95, 0.085))
		if entries[i].uri == menu._state.get("source_uri", ""): menu._buttons.back().base_color = menu.SELECTED
		button("queue_up_" + str(i), "↑", Vector2(0.35, y), Vector2(0.08, 0.08), i > 0)
		button("queue_down_" + str(i), "↓", Vector2(0.45, y), Vector2(0.08, 0.08), i + 1 < entries.size())
		button("queue_remove_" + str(i), "×", Vector2(0.57, y), Vector2(0.10, 0.08))
	if entries.is_empty(): menu._label(menu.I18n.t("Queue is empty"), Vector3(0, -0.1, 0.004), 20)
	button("page_previous", "‹", Vector2(-0.60, -0.48), Vector2(0.09, 0.065), offset > 0)
	menu._label("%d / %d" % [offset / ROWS + 1, maxi(1, ceili(float(entries.size()) / ROWS))], Vector3(-0.40, -0.48, 0.004), 16)
	button("page_next", "›", Vector2(-0.24, -0.48), Vector2(0.07, 0.065), offset + ROWS < entries.size())
	button("queue_add", menu.I18n.t("Add videos"), Vector2(0.05, -0.48), Vector2(0.34, 0.065))
	button("queue_clear", menu.I18n.t("Clear queue"), Vector2(0.45, -0.48), Vector2(0.35, 0.065), not entries.is_empty())
	menu.choices.finish()

func button(operation: String, title: String, centre: Vector2, size: Vector2, enabled: bool = true) -> void:
	var id := BASE + actions.size()
	actions[id] = operation
	menu._button(id, title, centre, size, enabled)
	(menu._buttons.back().node.get_child(0) as Label3D).font_size = 17

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
