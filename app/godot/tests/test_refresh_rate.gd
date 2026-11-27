extends SceneTree
const Display := preload("res://scripts/xr_display.gd")


class Target:
	extends RefCounted
	var display_refresh_rate := 0.0
	var rates: Array = [120.0, 90.0, 72.0, NAN, -1.0, 72.0]

	func get_available_display_refresh_rates() -> Array:
		return rates


func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	var target := Target.new()
	var display := Display.new()
	assert(display._apply_refresh_to(target) == 72.0)
	assert(target.display_refresh_rate == 72.0)
	target.rates = [80.0, 64.0, 90.0]
	assert(display._apply_refresh_to(target) == 64.0)
	assert(target.display_refresh_rate == 64.0)
	target.rates = []
	assert(display._apply_refresh_to(target) == 0.0)
	assert(target.display_refresh_rate == 64.0)
	assert(not display.set_refresh_preference(999.0))
	var preview_rates: Variant = display.available_refresh_rates()
	assert(display.closest_refresh_rate(preview_rates) == 0.0)
	target.rates = [24.0]
	assert(display._apply_refresh_to(target) == 24.0)
	var settings := ConfigFile.new()
	settings.set_value("display", "refresh_rate", NAN)
	assert(preload("res://scripts/player_settings_migration.gd").apply(settings))
	assert(settings.get_value("display", "refresh_rate") == 72.0)
	assert(not preload("res://scripts/player_settings_migration.gd").apply(settings))
	settings.set_value("display", "refresh_rate", 24.0)
	assert(not preload("res://scripts/player_settings_migration.gd").apply(settings))
	var menu := preload("res://scripts/library_menu.gd").new()
	menu.section = menu.Section.SETTINGS
	menu.tab = menu.DISPLAY_TAB
	menu.settings_provider = func(): return {"refresh_rates": [72.0, 90.0], "refresh_rate": 72.0}
	menu.source_rows.rebuild()
	var row: Dictionary = menu.rows.filter(func(r): return r.get("key", "") == "refresh_rate")[0]
	assert(row.title == preload("res://scripts/i18n.gd").t("Fixed refresh rate"))
	assert(row.choices.size() == 2 and row.choices[1].value == 90.0)
	var overlay := preload("res://scripts/fps_overlay.gd").new()
	overlay.source = func(): return {"frames": 30, "active": true, "refresh_hz": 90.0}
	root.add_child(overlay)
	await create_timer(0.6).timeout
	assert("90 Hz" in overlay.text and " FPS" in overlay.text)
	overlay.source = func(): return {"active": false}
	await create_timer(0.6).timeout
	assert("Hz" not in overlay.text)
	overlay.free()
	menu.free()
	preload("res://tests/support/test_result.gd").finish(self, 0)
