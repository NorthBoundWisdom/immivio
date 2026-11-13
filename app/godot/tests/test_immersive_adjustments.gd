extends SceneTree
const Main := preload("res://scripts/main.gd")
const Policy := preload("res://scripts/immersive_adjustments.gd")
const Video := preload("res://scripts/mpv_video_display.gd")


class TestInputSource:
	extends "res://scripts/input_source.gd"
	var active: Node3D

	func active_menu() -> Node3D:
		return active

	func input_focused() -> bool:
		return true

	func controller_allowed(_hand: String) -> bool:
		return true

	func ray(_hand: String) -> Variant:
		return [Vector3.ZERO, Vector3.FORWARD]


func _initialize() -> void:
	preload("res://tests/support/test_result.gd").prepare(self)
	call_deferred("_run")


func _run() -> void:
	var policy := Policy.new()
	assert(policy.poll("left_hand", Vector2.RIGHT, true).is_empty())
	policy.poll("left_hand", Vector2.ZERO, true)
	assert(policy.poll("left_hand", Vector2.RIGHT, true).key == "view_horizontal")
	assert(policy.poll("left_hand", Vector2.UP, true).is_empty())
	policy.suspend()
	assert(policy.poll("left_hand", Vector2.RIGHT, true).is_empty())
	var video := Video.new()
	root.add_child(video)
	video.platform = preload("res://tests/test_file_mode_memory.gd").Host.new()
	assert(video.open_local("file:///movie_180_LR.mp4", "movie_180_LR.mp4"))
	video.set_process(false)
	var host := Main.new()
	host.input_source = TestInputSource.new(host)
	host.video = video
	host.stick_controls = preload("res://scripts/player_stick_controls.gd").new()
	host.input_coordinator.immersive_grips = {"left_hand": true, "right_hand": true}
	host.input_coordinator._process_immersive(Vector2.ZERO, Vector2.ZERO, 0.1)
	assert(host.input_coordinator._process_immersive(Vector2.RIGHT, Vector2.ZERO, 0.1))
	assert(video.view_horizontal > 0 and video.view_vertical == 0)
	assert(video.panel.global_position.x > 0)
	var before := video.view_horizontal
	var menu := preload("res://scripts/library_menu.gd").new()
	root.add_child(menu)
	host.input_source.active = menu
	host.input_coordinator._process_immersive(Vector2.RIGHT, Vector2.ZERO, 0.1)
	assert(video.view_horizontal == before)
	host.input_source.active = null
	host.input_coordinator._process_immersive(Vector2.RIGHT, Vector2.ZERO, 0.1)
	assert(video.view_horizontal == before)
	host.input_coordinator._process_immersive(Vector2.ZERO, Vector2.ZERO, 0.1)
	for i in 120:
		host.input_coordinator._process_immersive(Vector2.ZERO, Vector2.RIGHT, 1.0 / 120.0)
	assert(is_equal_approx(video.stereo_horizontal, 2.0))
	video.commit_immersive_adjustments()
	var saved := video.mode_memory.lookup(video.local_uri)
	assert(is_equal_approx(saved.view_horizontal, before))
	assert(video.open_local("file:///movie_180_LR.mp4", "movie_180_LR.mp4"))
	assert(
		(
			is_equal_approx(video.view_horizontal, before)
			and is_equal_approx(video.stereo_horizontal, 2.0)
		)
	)
	assert(
		video.set_stereo_alignment("stereo_horizontal", 100.0) and video.stereo_horizontal == 10.0
	)
	video.geometry = 0
	video._apply_geometry()
	assert(video.stereo_horizontal == 5.0)
	assert(not video.set_immersive_adjustment("view_horizontal", 0.5))
	var guide := preload("res://scripts/picture_center_guide.gd").new()
	root.add_child(guide)
	var sample := {
		"identity": "movie",
		"hand": "left_hand",
		"held": true,
		"head": Transform3D.IDENTITY,
		"centre": Vector3(0, 0, -10)
	}
	guide.sync(sample, 0)
	guide.sync(sample, 200)
	assert(guide.joined)
	guide.release("left_hand", 201)
	sample.held = false
	guide.sync(sample, 300)
	assert(guide.visible and guide.opacity < 1.0)
	guide.sync(sample, 500)
	assert(not guide.visible)
	guide.free()
	menu.free()
	host.video = null
	host.free()
	video.free()
	preload("res://tests/support/test_result.gd").finish(self, 0)
