extends SceneTree
## Real GPU rendering of synthetic UI only. No images or pixels are read/saved.
const Warmup := preload("res://scripts/ui_warmup.gd")

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var warmer := Warmup.new(); root.add_child(warmer)
	var started := Time.get_ticks_msec()
	while not warmer.complete and Time.get_ticks_msec() - started < 30000:
		await process_frame
	await process_frame
	var passed := warmer.complete and warmer.pages_rendered == Warmup.PAGES.size() and warmer.get_child_count() == 0
	var report := warmer.snapshot()
	report["state"] = "passed" if passed else "failed"
	report["elapsed_ms"] = Time.get_ticks_msec() - started
	print(JSON.stringify(report))
	warmer.queue_free()
	if not passed: push_error("UI prewarming did not finish/release its offscreen viewport")
	quit(0 if passed else 1)
