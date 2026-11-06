extends SceneTree


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	var failures: Array[String] = []
	var count := 0
	for name in DirAccess.get_files_at("res://tests"):
		if not name.begins_with("render_") or not name.ends_with(".gd"):
			continue
		count += 1
		var script: GDScript = load("res://tests/" + name)
		if script == null or script.reload() != OK or not script.can_instantiate():
			failures.append(name + ": cannot load or instantiate")
			continue
		var instance: Object = script.new()
		if instance == null:
			failures.append(name + ": instance is null")
		else:
			instance.free()
	for failure in failures:
		push_error(failure)
	print("Render script load checks: ", count, " failures: ", failures.size())
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
