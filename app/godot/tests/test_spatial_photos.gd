extends SceneTree
const Photo := preload("res://scripts/photo_display.gd")
const Info := preload("res://scripts/image_info.gd")
const Memory := preload("res://scripts/file_mode_memory.gd")
var failures: Array[String] = []
var checks := 0
var folder := "user://spatial_photos_%d" % Time.get_ticks_usec()


class Host:
	extends RefCounted
	var ready: Callable
	var payload := {}
	var requests := 0
	var depth_calls := 0

	func open_photo(_uri: String) -> int:
		requests += 1
		ready.call_deferred(requests, JSON.stringify(payload))
		return requests

	func cancel_photo(_id: int) -> void:
		pass

	func release_photo(_id: int) -> void:
		pass

	func prepare_photo_depth(_id: int) -> bool:
		depth_calls += 1
		return false


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func settle(photo: Node3D) -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while photo.loading and Time.get_ticks_msec() < deadline:
		await create_timer(.01).timeout
	check(
		not photo.loading and photo.error.is_empty(),
		"Native pair completes without waiting for a depth model"
	)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var pair := Image.create(80, 32, false, Image.FORMAT_RGBA8)
	pair.fill(Color.RED)
	pair.fill_rect(Rect2i(40, 0, 40, 32), Color.GREEN)
	var path := ProjectSettings.globalize_path(folder.path_join("native.rgba"))
	FileAccess.open(path, FileAccess.WRITE).store_buffer(pair.get_data())
	var thumb := Image.create(40, 32, false, Image.FORMAT_RGB8)
	thumb.fill(Color.RED)
	var thumbnail := ProjectSettings.globalize_path(folder.path_join("thumbnail.jpg"))
	thumb.save_jpg(thumbnail)
	var info := {
		"state": "ready",
		"path": path,
		"raw_rgba": true,
		"decoded_width": 80,
		"decoded_height": 32,
		"width": 4032,
		"height": 1512,
		"orientation": 1,
		"native_stereo": true,
		"spatial_disparity": .02,
		"thumbnail_path": thumbnail
	}
	var decoded: Dictionary = Photo._decode({"info": info})
	check(
		(
			decoded.has("image")
			and decoded.image.get_pixel(10, 16).r > .9
			and decoded.image.get_pixel(70, 16).g > .9
		),
		"Raw pair preserves separate left and right colours"
	)
	check(
		decoded.thumbnail.get_width() == 40 and decoded.thumbnail.get_height() == 32,
		"Spatial library thumbnail uses one eye without copying the packed pair"
	)
	var invalid := info.duplicate()
	invalid.decoded_width = 81
	check(
		Photo._decode({"info": invalid}).has("error"),
		"Wrong raw length cannot be accepted as an image"
	)
	invalid.decoded_width = 9000
	check(
		Photo._decode({"info": invalid}).get("error") == "Image too large",
		"Raw allocation remains bounded before file IO"
	)
	for name in ["https://host/native.HEIC?token=1", "file://camera.heif"]:
		check(Info.is_image(name), "HEIC/HEIF enters the image queue: " + name)
	check(
		not Info.is_image("https://host/movie.mp4?cover=photo.heic"),
		"HEIC query text cannot turn a video into an image"
	)
	var photo := Photo.new()
	photo.auto_depth = true
	photo.history_enabled = false
	photo.mode_memory = Memory.new(folder.path_join("modes"))
	root.add_child(photo)
	var host := Host.new()
	host.ready = photo._on_ready
	host.payload = info
	photo.platform = host
	photo.load_mode_lock({"geometry": 3, "layout": 2, "depth": false, "fisheye_fov": 180})
	photo.open_image("file://camera.HEIC", "camera_360_TB.HEIC")
	await settle(photo)
	check(
		photo.geometry == 0 and photo.stereo_sbs and not photo.top_bottom,
		"Explicit native pairing wins over filename hints and a global projection lock"
	)
	check(
		not photo.depth_enabled and host.depth_calls == 0 and photo.auto_depth,
		"Native stereo skips inference while preserving the user's automatic 3D choice for other photos"
	)
	check(
		(
			photo.snapshot().native_stereo
			and not photo.snapshot().depth_available
			and not photo.set_depth(true)
		),
		"Native photo cannot accidentally be sent through 2D-to-3D again"
	)
	check(
		is_equal_approx(photo._flat.size.x / photo._flat.size.y, 1.25),
		"Display size uses one eye's aspect ratio"
	)
	check(
		(
			photo.material.get_shader_parameter("native_stereo")
			and is_equal_approx(photo.material.get_shader_parameter("spatial_disparity"), .02)
		),
		"Native disparity reaches the photo material"
	)
	check(
		photo.toggle_eye_order() and photo.material.get_shader_parameter("swap_eyes"),
		"Existing eye swap works for native stereo"
	)
	photo.close_image()
	photo.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Spatial photos: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
