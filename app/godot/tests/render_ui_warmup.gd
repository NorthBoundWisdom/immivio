extends SceneTree
## Real GPU rendering of synthetic UI only. No images or pixels are read/saved.
const Warmup := preload("res://scripts/ui_warmup.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var menu := preload("res://scripts/player_menu.gd").new()
	root.add_child(menu)
	menu.set_process(false)
	var state := Warmup.STATE.duplicate(true)
	menu.state_provider = func(): return state
	var warmer := Warmup.new()
	warmer.playback_menu = menu
	root.add_child(warmer)
	var started := Time.get_ticks_msec()
	while not warmer.complete and Time.get_ticks_msec() - started < 30000:
		await process_frame
	await process_frame
	menu._activate(11)
	var first_settings := menu.settings_cache_hits == 1
	state["capabilities_available"] = true
	menu._activate(12)
	var first_info := menu.settings_cache_hits == 2
	var passed := (
		warmer.complete
		and warmer.pages_rendered == Warmup.PAGES.size()
		and warmer.library_pages_rendered == Warmup.LIBRARY_TABS.size()
		and warmer.get_child_count() == 0
		and first_settings
		and first_info
	)
	var report := warmer.snapshot()
	report["state"] = "passed" if passed else "failed"
	report["elapsed_ms"] = Time.get_ticks_msec() - started
	report["first_settings_uses_prepared_controls"] = first_settings
	report["first_info_uses_prepared_controls"] = first_info
	print(JSON.stringify(report))
	warmer.queue_free()
	menu.queue_free()
	if not passed:
		push_error("UI prewarming did not finish/release its offscreen viewport")
	quit(0 if passed else 1)
