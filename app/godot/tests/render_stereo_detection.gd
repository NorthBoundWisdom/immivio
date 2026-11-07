extends SceneTree
## Exercise the exact full-frame GPU sampling path used by automatic layout detection.
const Capture := preload("res://scripts/thumbnail_cache.gd")
const Detection := preload("res://scripts/stereo_detection.gd")
const Fixtures := preload("res://tests/test_stereo_detection.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _run() -> void:
	var owner := Node.new()
	root.add_child(owner)
	for stacked in [false, true]:
		var texture := ImageTexture.create_from_image(Fixtures.packed(stacked))
		var image: Image = await Capture.capture(
			owner,
			texture.get_rid(),
			false,
			false,
			Vector4(0, 0, 1, 1),
			Vector2.ONE,
			false,
			Vector2i(192, 108)
		)
		check(
			image.get_size() == Vector2i(192, 108),
			"GPU sampling remains bounded to the requested dimensions"
		)
		var result := Detection.classify(image)
		check(
			result.layout == ("tb" if stacked else "sbs"),
			"GPU capture keeps both eyes for content matching"
		)
		var one_eye: Image = await Capture.capture(
			owner,
			texture.get_rid(),
			false,
			true,
			Vector4(0, 0, 1, 1),
			Vector2.ONE,
			stacked,
			Vector2i(192, 108)
		)
		check(
			Detection.classify(one_eye).layout.is_empty(),
			"An already-split single eye is not mistaken for another packed pair"
		)
	var sample_dir := OS.get_environment("IMMIVIO_STEREO_SAMPLE_DIR")
	if not sample_dir.is_empty():
		for index in range(6, 9):
			var source := Image.load_from_file(sample_dir.path_join("key-%02d.png" % index))
			var texture := ImageTexture.create_from_image(source)
			var image: Image = await Capture.capture(
				owner,
				texture.get_rid(),
				false,
				false,
				Vector4(0, 0, 1, 1),
				Vector2.ONE,
				false,
				Vector2i(192, 108)
			)
			var result := Detection.classify(image)
			check(
				result.layout == "sbs",
				"Private representative frame %d remains SBS through the GPU path" % index
			)
			print("Private sample %d: %s" % [index, result])
	owner.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Stereo detection GPU: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
