extends SceneTree
const Video := preload("res://scripts/mpv_video_display.gd")
const Memory := preload("res://scripts/file_mode_memory.gd")
const Menu := preload("res://scripts/player_menu.gd")
const Base := preload("res://tests/test_independent_playback.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	_run.call_deferred()

func _run() -> void:
	var video := Video.new()
	root.add_child(video)
	video.set_process(false)
	video.platform = Base.Host.new()
	video.mode_memory = Memory.new("user://below-memory")
	video.open_local("file:///below-a.mp4", "A")
	check(not video.subtitle_below_screen, "Unrecorded files default off")
	video.subtitle_flat_position = 0.73
	check(video.set_subtitle_below_screen(true), "Enable below-screen on flat video")
	video.caption.visible = true
	video.caption.text = "A long English primary caption with several words\n很短的中文"
	# Independently measure transformed glyph and screen corners, including a tilted
	# parent pose. Both mono and packed stereo share the flat screen envelope.
	var parent_poses := [Vector3(0.12, 0.1, -0.08), Vector3.ZERO,
		Vector3(deg_to_rad(-60.0), 0.1, -0.08), Vector3(deg_to_rad(60.0), 0.1, -0.08), Vector3(deg_to_rad(85.0), 0.1, -0.08)]
	for pose_index in parent_poses.size():
		var parent_angles: Vector3 = parent_poses[pose_index]
		# Preserve the original upright-mode matrix, then exercise real reclining
		# placement. Otherwise production deliberately removes the requested pitch.
		video.reclining_mode = pose_index > 0
		for scale_value in [0.05, 0.5, 1.0, 30.0]:
			for distance in [0.1, 2.0, 50.0]:
				for roll in [-90.0, -45.0, 0.0, 30.0, 90.0]:
					for stereo in [0, 1, 2]:
						video.geometry = 0
						video.stereo_sbs = stereo > 0
						video.top_bottom = stereo == 2
						video.set_screen_scale(scale_value)
						video.set_screen_distance(distance)
						video.set_flat_world_pose(Transform3D(Basis.from_euler(parent_angles), Vector3(0, 1.5, -distance)))
						video.set_screen_rotation(roll)
						for text_size in [0.5, 2.0]:
							video.subtitle_size = text_size
							video._place_caption()
							var pose := video.subtitle_transform()
							var to_plane := pose.affine_inverse()
							var lowest := INF
							for index in 4:
								lowest = minf(lowest, (to_plane * video.panel.global_transform * video.screen_corner(index)).y)
							var top := -INF
							var aabb := video.caption.get_aabb()
							for index in 8:
								top = maxf(top, (to_plane * video.caption.global_transform * aabb.get_endpoint(index)).y)
							var basis: Basis = pose.basis.inverse() * video.caption.global_basis
							var outline: float = video.caption.outline_size * video.caption.pixel_size * (absf(basis.x.y) + absf(basis.y.y))
							var context := str([rad_to_deg(parent_angles.x), scale_value, distance, roll, stereo, text_size])
							check(top + outline <= lowest - video.SUBTITLE_BELOW_GAP + 0.0001,
								"Caption below screen in pose plane: %s top=%.6f bottom=%.6f" % [context, top + outline, lowest])
							var depth := (to_plane * video.caption.global_position).z
							check(absf(depth - 0.01) <= 0.00001,
								"Caption stays on screen plane: %s normal_offset=%.6f expected=0.010000" % [context, depth])
							check(video.caption.vertical_alignment == VERTICAL_ALIGNMENT_TOP, "Below screen uses top alignment")
	check(is_equal_approx(video.subtitle_flat_position, 0.73), "Placement never changes saved slider value")
	video.set_subtitle_below_screen(false)
	video._place_caption()
	check(is_equal_approx(video.subtitle_flat_position, 0.73) and video.caption.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM, "Disabling restores original positioning")
	video.set_subtitle_below_screen(true)
	video.open_local("file:///below-b.mp4", "B")
	check(not video.subtitle_below_screen, "B never inherits A's preference")
	video.mode_memory = Memory.new("user://below-memory")
	video.mode_memory.load_saved()
	video.open_local("file:///below-a.mp4", "A")
	check(video.subtitle_below_screen, "A restores from the existing mode bank")
	video.mode_memory.relocate("file:///below-a.mp4", "file:///below-moved.mp4")
	check(video.mode_memory.lookup("file:///below-moved.mp4").subtitle_below_screen, "Rename/move retains layout")
	video.history_enabled = false
	video.open_local("file:///below-private.mp4", "Private")
	var sequence := video.mode_memory.sequence
	video.set_subtitle_below_screen(true)
	check(video.mode_memory.sequence == sequence and video.mode_memory.lookup(video.local_uri).is_empty(), "History-off writes no layout record")
	# An unrelated mode write must not smuggle a private layout preference into storage.
	video._remember_mode()
	check(not video.mode_memory.lookup(video.local_uri).has("subtitle_below_screen"), "Other mode writes cannot persist private below-screen selection")
	video.history_enabled = true
	video._remember_file = false
	sequence = video.mode_memory.sequence
	video.set_subtitle_below_screen(false)
	check(video.mode_memory.sequence == sequence, "Per-file memory disabled writes nothing")
	for geometry in [1, 2, 3]:
		video.geometry = geometry
		check(not video.set_subtitle_below_screen(true), "Non-flat toggle is ineffective")
		video.subtitle_below_screen = false
		video.caption.visible = true
		video._place_caption()
		var anchor: Variant = video.material.get_shader_parameter("subtitle_anchor_inverse")
		video.subtitle_below_screen = true
		video._place_caption()
		check(video.caption.layers == 0 and video.material.get_shader_parameter("subtitle_anchor_inverse") == anchor, "Immersive path unchanged by stored flat preference")
	var state := {"has_video": true, "source_uri": "file:///ui.mp4", "geometry": 0,
		"subtitle_flat_position": 73.0, "subtitle_below_screen": true}
	var menu := Menu.new()
	menu.state_provider = func(): return state
	root.add_child(menu)
	menu.toggle()
	menu._activate(110)
	check(not menu.choices.targets.values().any(func(item): return item.get("key", "") == "subtitle_flat_position"), "Below-screen disables slider capture")
	check(state.subtitle_flat_position == 73, "Disabled UI retains slider value")
	state.subtitle_below_screen = false
	menu.refresh()
	check(menu.choices.targets.values().any(func(item): return item.get("key", "") == "subtitle_flat_position"), "Slider re-enabled after turning layout off")
	for value in [33.3333333333333, 66.6666666666667, 50.0]:
		state.subtitle_below_screen = false
		state.subtitle_flat_position = value
		menu.refresh()
		var target := -1
		for id in menu.choices.sliders:
			if menu.choices.targets[id].get("key", "") == "subtitle_flat_position":
				target = id
		var active_text: String = menu.choices.sliders[target].label.text
		state.subtitle_below_screen = true
		menu.refresh()
		check(menu._buttons.any(func(button): return not button.enabled and (button.node.get_child(0) as Label3D).text == active_text),
			"Disabled percentage matches active slider: %.12f -> %s" % [value, active_text])
		check(state.subtitle_flat_position == value, "Formatting never rounds the saved slider value")

	state.geometry = 1
	menu.refresh()
	check(not menu.choices.targets.values().any(func(item): return item.get("key", "") == "subtitle_below_screen"), "Immersive UI disables the toggle")
	check(menu._subtitle_controls().back().field.hint == "Available for flat video only", "Immersive control explains its scope")
	menu.free()
	video.free()
	for failure in failures:
		push_error(failure)
	print("Below-screen checks=", checks, " failures=", failures.size())
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
