extends SceneTree
## GPU pixel oracle for the production thumbnail capture path; no media files.
const Thumbnails := preload("res://scripts/thumbnail_cache.gd")
var failures: Array[String] = []


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Thumbnail capture requires a GPU renderer; run without --headless")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	var frame := Image.create(640, 180, false, Image.FORMAT_RGBA8)
	frame.fill_rect(Rect2i(0, 0, 320, 90), Color.GREEN)
	frame.fill_rect(Rect2i(0, 90, 320, 90), Color.RED)
	frame.fill_rect(Rect2i(320, 0, 320, 180), Color.BLUE)
	var texture := ImageTexture.create_from_image(frame)
	var owner := Node.new()
	root.add_child(owner)
	var shot: Image = await Thumbnails.capture(
		owner, texture.get_rid(), false, true, Vector4(0, 0, 1, 1)
	)
	if shot == null or shot.get_size() != Thumbnails.SIZE:
		failures.append("Capture did not return the expected thumbnail dimensions")
	else:
		var top := shot.get_pixel(160, 30)
		var bottom := shot.get_pixel(160, 150)
		if top.g < .8 or top.r > .2 or top.b > .2:
			failures.append("Left-eye top row was flipped or sampled from the right eye")
		if bottom.r < .8 or bottom.g > .2 or bottom.b > .2:
			failures.append("Left-eye bottom row was flipped or sampled from the right eye")
	owner.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
