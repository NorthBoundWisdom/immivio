extends RefCounted
const Filter := preload("res://scripts/subtitle_picker_filter.gd")
const Methods := preload("res://scripts/platform_methods.gd")
const SYSTEM := 986100
const CLEAR := 986101
const ERASE := 986102
const KEYS := 986200
const LETTERS := "1234567890qwertyuiopasdfghjklzxcvbnm .-_"
var menu: Node3D
var active := false
var query := ""
var entries: Array = []
var request := 0
var source := ""
var session := 0
func _init(owner: Node3D) -> void:
	menu = owner
func open(uri: String, title: String, tracks: Array, session_id: int) -> void:
	active = true
	source = uri
	session = session_id
	query = Filter.default_query(title)
	entries = []
	request = 0
	menu.scroll = 0.0
	menu._drag.clear()
	menu.choices.reset()
	for track in tracks:
		if track.get("external", false):
			entries.append({"title": str(track.get("title", "")), "track_id": int(track.id)})
	if uri.begins_with("file://") or uri.begins_with("smb://"):
		if Methods.supports(menu.platform, "subtitle_candidates"):
			request = menu.platform.subtitle_candidates(uri)
	menu.refresh()
func close() -> void:
	active = false
	request = 0
	entries = []
func receive(id: int, raw: String) -> bool:
	var value: Variant = JSON.parse_string(raw)
	if not value is Dictionary or value.get("source") != "subtitle_candidates":
		return false
	if active and request > 0 and id == request:
		request = 0
		if value.get("state") == "ready":
			entries = value.get("entries", []).slice(0, 128)
		menu.refresh()
	return true
func rows() -> Array:
	return Filter.filter_rows(entries, query)
func choose(row: Dictionary) -> void:
	var selected := row.duplicate(true)
	selected.source_uri = source
	selected.session_id = session
	menu.dismiss()
	menu.subtitle_chosen.emit(selected)
func action(target: int) -> void:
	if target == menu.CLOSE or target == menu.PLAYER:
		menu.dismiss()
	elif target == SYSTEM:
		menu.dismiss()
		menu.subtitle_system_requested.emit()
	elif target == CLEAR:
		query = ""
	elif target == ERASE:
		query = query.left(maxi(0, query.length() - 1))
	elif target >= KEYS and target < KEYS + LETTERS.length():
		query = Filter.clean(query + LETTERS[target - KEYS])
	elif target >= menu.ROW_BASE and target < menu.ROW_BASE + 4:
		var index: int = menu._first_line() + target - menu.ROW_BASE
		if index < menu.rows.size():
			choose(menu.rows[index])
		return
	menu.scroll = 0.0
	menu.refresh()
func draw() -> void:
	menu._set_backdrop(Vector2(1.46, 1.2), Vector2(0.13, 0))
	menu._label(menu.I18n.t("Filter subtitles") + ": " + query.left(45), Vector3(0.13, 0.49, 0.004), 19)
	menu._button(CLEAR, menu.I18n.t("Clear"), Vector2(0.57, 0.4), Vector2(0.18, 0.07))
	menu._button(ERASE, "⌫", Vector2(0.77, 0.4), Vector2(0.12, 0.07))
	var first: int = menu._first_line()
	for i in range(first, mini(first + 4, menu.rows.size())):
		menu._button(menu.ROW_BASE + i - first, str(menu.rows[i].title).left(54), Vector2(0.13, menu.LIST_TOP - (i - first) * menu.ROW_PITCH), Vector2(1.25, 0.09))
	if menu.rows.is_empty():
		menu._label(menu.I18n.t("No matching files"), Vector3(0.13, 0.1, 0.004), 18)
	for i in LETTERS.length():
		menu._button(KEYS + i, LETTERS[i], Vector2(-0.45 + (i % 13) * 0.095, -0.19 - (i / 13) * 0.09), Vector2(0.085, 0.075))
	menu._button(SYSTEM, menu.I18n.t("System file picker"), Vector2(-0.1, -0.52), Vector2(0.8, 0.07))
	menu._button(menu.CLOSE, menu.I18n.t("Close"), Vector2(0.64, -0.52), Vector2(0.3, 0.07))
