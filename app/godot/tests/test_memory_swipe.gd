extends SceneTree
const Swipe := preload("res://scripts/memory_swipe.gd")
const Hand := preload("res://scripts/hand_pointer.gd")
const Main := preload("res://scripts/main.gd")
const HEAD := Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
const START := Vector3(0.18, 1.25, -0.5)
var checks := 0
var failures: Array[String] = []
var report := []


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func sample(point: Vector3) -> Dictionary:
	return {
		"source": "hand",
		"palm":
		{
			"tracked": true,
			"eligible": true,
			"position": point,
			"space": Transform3D.IDENTITY,
			"provider": "joints"
		}
	}


func run_path(
	g: RefCounted,
	travel: Vector3,
	seconds: float,
	fps: int,
	scale: float = 1.0,
	gap: bool = false,
	hand: String = "right_hand"
) -> Array:
	var actions := []
	var frames := maxi(2, roundi(seconds * fps))
	var head := HEAD
	head.origin *= scale
	g.update({hand: sample(START * scale)}, true, false, head, scale, 1.0 / fps)
	for frame in range(1, frames + 1):
		var inputs := {hand: sample((START + travel * frame / float(frames)) * scale)}
		if gap and frame == frames / 2:
			inputs = {}
		actions.append_array(g.update(inputs, true, false, head, scale, seconds / frames))
	return actions


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	call_deferred("_run")


func _run() -> void:
	for hand in ["left_hand", "right_hand"]:
		for fps in [24, 36, 72, 90]:
			for seconds in [0.16, 0.3, 0.5, 0.7]:
				for direction in [-1, 1]:
					var g := Swipe.new()
					var actions := run_path(
						g, Vector3(0.29 * direction, 0.045, -0.045), seconds, fps, 1, true, hand
					)
					check(
						actions.size() == 1,
						(
							"Physical wave fires once: %s / %d fps / %.2fs / %d"
							% [hand, fps, seconds, direction]
						)
					)
					report.append(
						{
							"hand": hand,
							"fps": fps,
							"duration_s": seconds,
							"direction": direction,
							"accepted": actions.size() == 1,
							"diagnostics": g.diagnostics.duplicate(true)
						}
					)
	for motion in [
		Vector3(0.08, 0, 0),
		Vector3(0.29, 0, 0),
		Vector3(0, 0.29, 0),
		Vector3(0, 0, 0.29),
		Vector3(0.19, 0.23, 0)
	]:
		var g := Swipe.new()
		check(
			run_path(g, motion, 2.0, 72).is_empty(),
			"Small motion, slow drift, vertical and depth motion do not shuffle"
		)
	for scale in [0.5, 2.0]:
		check(
			run_path(Swipe.new(), Vector3(-0.29, 0, 0), 0.4, 36, scale).size() == 1,
			"World scale keeps a physical displacement threshold"
		)
	var g := Swipe.new()
	run_path(g, Vector3(-0.29, 0, 0), 0.3, 36)
	var returns := []
	for frame in 12:
		returns.append_array(
			g.update(
				{"right_hand": sample(START - Vector3(0.29 * (1 - frame / 11.0), 0, 0))},
				true,
				false,
				HEAD,
				1,
				1.0 / 36
			)
		)
	check(returns.is_empty(), "The return stroke never swaps a second batch")
	for frame in 60:
		g.update({"right_hand": sample(START)}, true, false, HEAD, 1, 1.0 / 36)
	check(
		run_path(g, Vector3(0.29, 0, 0), 0.4, 36).size() == 1,
		"A quiet endpoint rearms without a prescribed finger pose"
	)
	for reason in ["pinch", "system", "menu", "body", "provider", "jump", "gap"]:
		g = Swipe.new()
		g.update({"right_hand": sample(START)}, true, false, HEAD, 1, 1.0 / 36)
		for frame in range(1, 5):
			g.update(
				{"right_hand": sample(START - Vector3(frame * 0.02, 0, 0))},
				true,
				false,
				HEAD,
				1,
				1.0 / 36
			)
		var input := sample(START - Vector3(0.13, 0, 0))
		var head := HEAD
		if reason == "pinch":
			input.palm.pinched = true
		if reason == "system":
			input.palm.blocked = true
		if reason == "body":
			head.origin.x += 0.10
		if reason == "provider":
			input.palm.provider = "meta_aim"
		if reason == "jump":
			input.palm.position.x -= 0.9
		if reason == "gap":
			input = {}
		var actions: Array = g.update(
			{"right_hand": input},
			reason != "menu",
			false,
			head,
			1,
			0.14 if reason == "gap" else 1.0 / 36
		)
		for frame in range(1, 4):
			actions.append_array(
				g.update(
					{"right_hand": sample(START - Vector3(0.13 + frame * 0.02, 0, 0))},
					true,
					false,
					HEAD,
					1,
					1.0 / 36
				)
			)
		check(actions.is_empty(), "Interrupted travel cannot finish an old gesture: " + reason)
	await production_sampling()
	var output := ProjectSettings.globalize_path(
		"res://../../build/output/photo-layouts/memory-wave-replay.json"
	)
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file:
		file.store_string(
			JSON.stringify({"cases": report, "checks": checks, "failures": failures}, "\t")
		)
		file = null
	for failure in failures:
		push_error(failure)
	print("Memory sweep: %d checks, %d failures" % [checks, failures.size()])
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)


func tracker(point: Vector3) -> XRHandTracker:
	var result := XRHandTracker.new()
	result.name = "/user/hand_tracker/right"
	result.has_tracking_data = true
	result.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
	result.set_hand_joint_flags(XRHandTracker.HAND_JOINT_PALM, Hand.POSITION_FLAGS)
	result.set_hand_joint_transform(
		XRHandTracker.HAND_JOINT_PALM, Transform3D(Basis.IDENTITY, point)
	)
	return result


func production_sampling() -> void:
	var optical := tracker(START)
	check(
		Hand.sweep_sample(optical, HEAD, Transform3D.IDENTITY, 1).get("eligible", false),
		"A tracked palm trajectory works without perfect finger-joint data"
	)
	var aim := XRControllerTracker.new()
	aim.name = "/user/fbhandaim/right"
	aim.set_input("index_pinch", true)
	check(
		Hand.sweep_sample(optical, HEAD, Transform3D.IDENTITY, 1, aim).pinched,
		"Official pinch blocks the displacement gesture"
	)
	aim.set_input("index_pinch", false)
	var head := XRPositionalTracker.new()
	head.name = "head"
	head.set_pose("default", HEAD, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	var app := Main.new()
	app.settings_path = "user://memory_sweep_%d.cfg" % Time.get_ticks_usec()
	root.add_child(app)
	app.set_process(false)
	app.input_visuals.free()
	app.input_visuals = null
	for item in [optical, aim, head]:
		XRServer.add_tracker(item)
	app.recent_menu.dismiss()
	app.photo_menu.dismiss()
	app.video_menu.dismiss()
	app.xr_camera.global_transform = HEAD
	app.photo_active = true
	app.player_menu = app.photo_menu
	app.photo.gallery.mode = 3
	app.photo.queue.assign(
		[
			{"uri": "file://memory-one.png", "title": "one"},
			{"uri": "file://memory-two.png", "title": "two"}
		]
	)
	app.photo.local_uri = "file://memory-one.png"
	app.photo.index = 0
	app._update_hand_input(1.0 / 36)
	for frame in range(1, 12):
		optical.set_hand_joint_transform(
			XRHandTracker.HAND_JOINT_PALM,
			Transform3D(Basis.IDENTITY, START - Vector3(frame * 0.025, 0, 0))
		)
		app._update_hand_input(1.0 / 36)
	check(
		app.photo.gallery._swap_phase == 1,
		"Production optical input samples palm displacement and triggers the swap even without an aim ray"
	)
	app.photo.gallery._swap_phase = 0
	app.memory_swipe.cancel()
	app.photo_menu.toggle()
	for frame in range(1, 12):
		optical.set_hand_joint_transform(
			XRHandTracker.HAND_JOINT_PALM,
			Transform3D(Basis.IDENTITY, START + Vector3(frame * 0.025, 0, 0))
		)
		app._update_hand_input(1.0 / 36)
	check(app.photo.gallery._swap_phase == 0, "Visible menus isolate memory swipes")
	app.photo_menu.dismiss()
	app.memory_swipe = Swipe.new()
	app.photo.gallery.mode = 2
	app._update_hand_input(1.0 / 36)
	for frame in range(1, 12):
		optical.set_hand_joint_transform(
			XRHandTracker.HAND_JOINT_PALM,
			Transform3D(Basis.IDENTITY, START - Vector3(frame * 0.025, 0, 0))
		)
		app._update_hand_input(1.0 / 36)
	check(
		app.photo.gallery._swap_phase == 1 and app.photo.gallery._batch_direction == 1,
		"Wall accepts the same lateral wave as next-group navigation"
	)
	for item in [optical, aim, head]:
		XRServer.remove_tracker(item)
	app.queue_free()
	await process_frame
