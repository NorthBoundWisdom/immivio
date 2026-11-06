extends SceneTree
const Preferences := preload("res://scripts/player_settings_controller.gd")


func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	var host := Node3D.new()
	var fresh := Preferences.new(host)
	fresh.settings_path = "user://new-settings.cfg"
	fresh.load_preferences()
	assert(fresh.settings.get_value("controls", "pinch_hand", "right_hand") == "right_hand")
	assert(
		not FileAccess.file_exists(fresh.settings_path), "Fresh defaults need no migration write"
	)
	fresh.settings.set_value("library", "history", false)
	assert(fresh.settings.save(fresh.settings_path) == OK)
	var restarted := Preferences.new(host)
	restarted.settings_path = fresh.settings_path
	restarted.load_preferences()
	assert(
		restarted.settings.get_value("controls", "pinch_hand", "missing") == "right_hand",
		"A fresh install keeps Right after saving another setting and restarting"
	)
	assert(not restarted.settings.get_value("library", "history"))
	var old := ConfigFile.new()
	old.set_value("audio", "volume", 37.0)
	old.set_value("library", "history", false)
	assert(old.save("user://existing-settings.cfg") == OK)
	var existing := Preferences.new(host)
	existing.settings_path = "user://existing-settings.cfg"
	existing.load_preferences()
	assert(
		existing.settings.get_value("controls", "pinch_hand", "missing") == "both",
		"Existing settings without a pinch choice retain either-hand gestures"
	)
	assert(existing.settings.get_value("audio", "volume") == 37.0)
	assert(not existing.settings.get_value("library", "history"))
	var persisted := ConfigFile.new()
	assert(persisted.load(existing.settings_path) == OK)
	assert(persisted.get_value("controls", "pinch_hand") == "both")
	assert(
		not preload("res://scripts/player_settings_migration.gd").apply(persisted, true),
		"Repeated migration is idempotent"
	)
	persisted.set_value("controls", "pinch_hand", "left_hand")
	persisted.save(existing.settings_path)
	existing.load_preferences()
	assert(existing.settings.get_value("controls", "pinch_hand") == "left_hand")
	host.free()
	preload("res://tests/support/test_result.gd").finish(self, 0)
