extends SceneTree
const Main := preload("res://scripts/main.gd")
const Policy := preload("res://scripts/playback_preferences.gd")
const Focus := preload("res://scripts/stereo_focus.gd")
const Follow := preload("res://scripts/subtitle_follow.gd")
var failures: Array[String] = []


class SpeedHost:
	extends RefCounted
	var accepted := true

	func set_mpv_speed(_id: int, _speed: float) -> bool:
		return accepted

	func close_mpv_video(_id: int) -> void:
		pass


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _initialize() -> void:
	if preload("res://tests/support/test_result.gd").prepare(self):
		call_deferred("run")


func run() -> void:
	check(
		Policy.speed(NAN) == 1.0 and Policy.speed("2") == 1.0, "Corrupt speed uses a safe default"
	)
	check(
		Policy.seek_step(INF) == 10 and Policy.seek_step(10.5) == 10 and Policy.seek_step(30) == 30,
		"Seek steps validate finite whole values"
	)
	var path := "user://upstream_preferences.cfg"
	var main := Main.new()
	main.settings_path = path
	root.add_child(main)
	await process_frame
	main.test_setting_changed("seek_step", 30)
	main.test_setting_changed("subtitle_follow_view", true)
	main.test_setting_changed("subtitle_transparency", 35)
	var backend := SpeedHost.new()
	main.video.platform = backend
	main.video.media.begin(7)
	main.player_menu.adjustment_requested.emit("playback_speed", 1.75)
	check(main.video.playback_speed == 1.75, "Accepted speed uses the production UI route")
	backend.accepted = false
	main.player_menu.adjustment_requested.emit("playback_speed", 2.0)
	check(
		main.settings.get_value("playback", "speed") == 1.75,
		"A rejected native speed cannot overwrite the saved preference"
	)
	main.queue_free()
	await process_frame
	main = Main.new()
	main.settings_path = path
	root.add_child(main)
	await process_frame
	check(
		main.seek_step == 30 and main.video.playback_speed == 1.75,
		"Playback preferences survive restart"
	)
	check(
		main.video.subtitle_follow_view and main.video.subtitle_transparency == 35,
		"Subtitle preferences survive restart"
	)
	var viewport := main.get_viewport()
	main.display.preview = false
	var msaa := viewport.msaa_3d
	main.display.set_flat_surface_visible(true)
	main.display.set_flat_surface_visible(false)
	check(viewport.msaa_3d == msaa, "Device screen transitions never rebuild eye-buffer MSAA")
	var follow := Follow.new()
	follow.tick(Vector3.FORWARD, 0.016)
	follow.tick(Vector3(sin(0.05), 0, -cos(0.05)), 0.016)
	check(follow.centre.is_zero_approx(), "Small head motions leave subtitles stationary")
	follow.tick(Vector3.RIGHT, 0.016)
	check(follow.centre.x > 1, "Out-of-view captions return to the view")
	check(not Focus.measurable(Vector2(0, deg_to_rad(70)), 3, 180), "Polar measurements rejected")
	var focus := Focus.new()
	focus.observe({"valid": true, "degrees": 2.0}, 0.063, Vector2.ZERO, false, 0, 1000)
	focus.settle(0.1, 1000)
	check(
		focus.distance > 1.7 and focus.distance < 1.9,
		"Measured disparity produces finite stereo distance"
	)
	focus.settle(0.1, 4000)
	check(focus.distance == 0, "Expired depth evidence cannot keep driving focus")
	var black := Image.create(Focus.SIZE.x, Focus.SIZE.y, false, Image.FORMAT_RGB8)
	black.fill(Color.BLACK)
	check(not Focus.measure(black).valid, "Textureless patches never drive autofocus")
	var image := Image.create(Focus.SIZE.x, Focus.SIZE.y, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 74
	var texture: Array[float] = []
	for i in 96 * Focus.SIZE.y:
		texture.append(rng.randf())
	for y in Focus.SIZE.y:
		for x in 96:
			var a: float = texture[y * 96 + x]
			var b: float = texture[y * 96 + mini(x + 8, 95)]
			image.set_pixel(x, y, Color(a, a, a))
			image.set_pixel(x + 96, y, Color(b, b, b))
	var measured := Focus.measure(image)
	check(
		measured.valid and absf(measured.degrees - 8 * 29.0 / 96) < 0.01,
		"Independent synthetic stereo pair recovers disparity"
	)
	main.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("Upstream playback failures: ", failures)
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
