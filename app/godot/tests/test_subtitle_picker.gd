extends SceneTree
const Filter := preload("res://scripts/subtitle_picker_filter.gd")
class Platform extends RefCounted:
	func subtitle_candidates(_uri: String) -> int:
		return 42
func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	call_deferred("_run")
func _run() -> void:
	assert(Filter.default_query(" /movies/Film.MKV ") == "Film")
	assert(Filter.default_query("https://private/Film.mp4").is_empty())
	var menu := preload("res://scripts/library_menu.gd").new()
	root.add_child(menu)
	menu.platform = Platform.new()
	menu.visible = true
	menu.subtitle_picker.open("smb://account/share/Film.mkv", "Film.mkv", [], 7)
	var picker: RefCounted = menu.subtitle_picker
	assert(picker.query == "Film")
	assert(picker.receive(41, JSON.stringify({"source": "subtitle_candidates", "state": "ready", "entries": [{"title": "stale.srt"}]})))
	assert(picker.entries.is_empty())
	picker.receive(42, JSON.stringify({"source": "subtitle_candidates", "state": "ready", "entries": [{"title": "Film.en.srt", "subtitle_uri": "smb://account/share/Film.en.srt"}, {"title": "Other.srt", "subtitle_uri": "smb://account/share/Other.srt"}]}))
	assert(menu.rows.size() == 1)
	picker.action(picker.CLEAR)
	assert(menu.rows.size() == 2)
	var selected: Array = []
	menu.subtitle_chosen.connect(func(value): selected.append(value))
	menu.stick_scroll(1.0, 1.0)
	assert(selected.is_empty())
	picker.choose(menu.rows[1])
	assert(selected.size() == 1 and selected[0].session_id == 7)
	assert(not picker.active and not menu.visible)
	picker.receive(42, JSON.stringify({"source": "subtitle_candidates", "state": "ready", "entries": [{"title": "late.srt"}]}))
	assert(picker.entries.is_empty())
	menu.free()
	preload("res://tests/support/test_result.gd").finish(self, 0)
