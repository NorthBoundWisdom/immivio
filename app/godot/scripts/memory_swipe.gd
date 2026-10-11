extends RefCounted
## A lateral palm trajectory owns the gesture; no static finger pose is required.
const HANDS := ["right_hand", "left_hand"]
const TRAVEL := 0.18
const MIN_SPEED := 0.30
const MAX_SECONDS := 0.85
const GAP_SECONDS := 0.12
var states := {}
var diagnostics: Array[Dictionary] = []
var clock := 0.0
var cooldown_until := 0.0

func cancel() -> void:
	states.clear()

func _start(sample: Dictionary, head: Transform3D, scale: float) -> Dictionary:
	var forward := -head.basis.z; forward.y = 0; forward = forward.normalized()
	return {"anchor": sample.position, "last": sample.position, "basis": Basis(forward.cross(Vector3.UP), Vector3.UP, -forward),
		"head": head, "space": sample.get("space", Transform3D.IDENTITY), "provider": sample.get("provider", "joints"),
		"scale": scale, "age": 0.0, "gap": 0.0, "peak": 0.0, "moving": false, "locked": false,
		"stable": 0.0, "furthest": 0.0, "sign": 0.0}

func _reject(hand: String, reason: String, state: Dictionary) -> void:
	if state.moving:
		diagnostics.append({"hand": hand, "reason": reason, "travel_m": snappedf(state.furthest, 0.01),
			"duration_ms": roundi(state.age * 1000), "peak_mps": snappedf(state.peak, 0.01)})
	states.erase(hand)

func update(inputs: Dictionary, enabled: bool, busy: bool, head: Transform3D, scale: float, delta: float) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var dt := clampf(delta, 0.001, 0.15); clock += dt
	if not enabled or busy or not head.is_finite() or not is_finite(scale) or scale <= 0 \
		or Vector2(head.basis.z.x, head.basis.z.z).length_squared() < 0.001:
		for hand in states.keys():
			if not states[hand].locked: _reject(hand, "input_busy", states[hand])
		return actions
	for hand in HANDS:
		var sample: Dictionary = inputs.get(hand, {}).get("palm", {})
		var tracked: bool = inputs.get(hand, {}).get("source") == "hand" and sample.get("tracked", false) \
			and sample.get("position") is Vector3 and sample.position.is_finite()
		if not tracked:
			if states.has(hand):
				states[hand].gap += dt
				if states[hand].gap > GAP_SECONDS: _reject(hand, "tracking_gap", states[hand])
			continue
		if not sample.get("eligible", false) or sample.get("pinched", false) or sample.get("blocked", false):
			if states.has(hand): _reject(hand, "pose_or_region", states[hand])
			continue
		if not states.has(hand):
			states[hand] = _start(sample, head, scale); continue
		var state: Dictionary = states[hand]
		var elapsed: float = dt + state.gap; state.gap = 0.0
		var step: Vector3 = (sample.position - state.last) / scale
		var offset: Vector3 = state.basis.inverse() * (sample.position - state.anchor) / scale
		if sample.get("space", Transform3D.IDENTITY) != state.space or sample.get("provider", "joints") != state.provider \
			or not is_equal_approx(scale, state.scale) or delta > 0.15 or step.length() > 0.035 + 3.5 * elapsed:
			_reject(hand, "tracking_jump", state); states[hand] = _start(sample, head, scale); continue
		state.last = sample.position
		if state.locked:
			# The return stroke cannot trigger another batch. Rearm only after a quiet endpoint.
			state.stable = float(state.stable) + elapsed if step.length() / elapsed < 0.12 else 0.0
			if clock >= cooldown_until and state.stable >= 0.22: states[hand] = _start(sample, head, scale)
			continue
		if head.origin.distance_to(state.head.origin) / scale > 0.075 or head.basis.z.dot(state.head.basis.z) < cos(deg_to_rad(18.0)):
			_reject(hand, "head_motion", state); states[hand] = _start(sample, head, scale); continue
		if not state.moving:
			if absf(offset.x) < 0.025:
				if step.length() / elapsed < 0.12:
					state.stable += elapsed
					if state.stable > 0.12: states[hand] = _start(sample, head, scale)
				continue
			state.moving = true; state.sign = signf(offset.x); state.age = elapsed
		else: state.age += elapsed
		state.peak = maxf(state.peak, absf((state.basis.inverse() * step).x) / elapsed)
		state.furthest = maxf(state.furthest, absf(offset.x))
		if state.age > MAX_SECONDS or absf(offset.y) > 0.14 or absf(offset.z) > 0.18 \
			or absf(offset.x) + 0.045 < state.furthest or signf(offset.x) != state.sign:
			_reject(hand, "trajectory", state); states[hand] = _start(sample, head, scale); continue
		if clock < cooldown_until: continue
		if absf(offset.x) >= TRAVEL and absf(offset.x) > maxf(absf(offset.y), absf(offset.z)) * 1.6 \
			and absf(offset.x) / maxf(0.05, state.age) >= MIN_SPEED and state.peak >= 0.40:
			state.locked = true; state.stable = 0.0; cooldown_until = clock + 1.0
			diagnostics.append({"hand": hand, "reason": "accepted", "travel_m": snappedf(absf(offset.x), 0.01),
				"duration_ms": roundi(state.age * 1000), "peak_mps": snappedf(state.peak, 0.01)})
			actions.append({"hand": hand, "direction": 1 if offset.x < 0 else -1})
			for other in states: states[other].locked = true; states[other].stable = 0.0
			return actions
	return actions
