extends SceneTree
## Recent tiles show how far a started video got, only when its length is known.
const Menu := preload("res://scripts/library_menu.gd")
var checks := 0
var failures: Array[String] = []


class Catalog:
	extends RefCounted

	func list_recent() -> Array[Dictionary]:
		return [
			{
				"uri": "file:///a.mp4",
				"title": "a.mp4",
				"position_ms": 600000,
				"duration_ms": 2400000
			},
			{"uri": "file:///b.mp4", "title": "b.mp4", "position_ms": 600000, "duration_ms": -1},
			{"uri": "file:///c.mp4", "title": "c.mp4", "position_ms": 0, "duration_ms": 2400000},
		]


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	call_deferred("_run")


func _progress_fill(menu: Node, target: int) -> Dictionary:
	for button in menu.controls_snapshot():
		if button.target != target:
			continue
		for child in button.node.children:
			if (
				child.kind == "MeshInstance3D"
				and child.material_override.kind == "ShaderMaterial"
				and child.material_override.render_priority == 14
				and child.material_override.surface_color == Menu.ACCENT
			):
				return child
	return {}


func _run() -> void:
	var menu := Menu.new()
	menu.catalog = Catalog.new()
	root.add_child(menu)
	menu.toggle()
	await process_frame
	check(menu.section == Menu.Section.RECENT and menu.rows.size() == 3, "Recent lists the catalog")
	check(is_equal_approx(float(menu.rows[0].get("progress", -1)), 0.25), "Known length: progress")
	check(not menu.rows[1].has("progress"), "Unknown length shows no progress")
	check(not menu.rows[2].has("progress"), "Unstarted video shows no progress")
	var fill := _progress_fill(menu, Menu.ROW_BASE)
	var track_width: float = Menu.TILE_SIZE.x - 0.02 - 0.03
	check(
		not fill.is_empty() and is_equal_approx(fill.mesh.size.x, track_width * 0.25),
		"Started tile draws a quarter-length accent bar"
	)
	check(_progress_fill(menu, Menu.ROW_BASE + 1).is_empty(), "Unknown length tile has no bar")
	menu.queue_free()
	await process_frame
	print("library progress checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures:
		push_error(failure)
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
