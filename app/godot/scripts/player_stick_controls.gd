extends RefCounted

const SEEK_HOLD_DELAY := 0.45
const SEEK_REPEAT_INTERVAL := 0.28

var left_latched := false
var right_latched := false
## The right stick is zooming an immersive view: it stays zoom until it returns to center.
var right_zooming := false
var seek_hand := ""
var _seek_direction := 0
var _held_seconds := 0.0
var _next_repeat := 0.0


## UI captures own the input until each stick returns to center.
func suspend() -> void:
	left_latched = true
	right_latched = true
	right_zooming = false
	cancel_seek_hold()


func cancel_seek_hold() -> void:
	seek_hand = ""


# One command per deflection; return to center before changing direction/action.
# With [zoom] (immersive views) the right stick's up/down zooms continuously.
func poll(
	left: Vector2,
	right: Vector2,
	zoom: bool = false,
	delta: float = 0.0,
	scrub: bool = false,
	seek_busy: bool = false
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if not seek_hand.is_empty():
		var stick := left if seek_hand == "left" else right
		if scrub and stick.x * _seek_direction > 0.6 and absf(stick.y) < 0.4:
			_held_seconds += clampf(delta, 0.0, 0.1)
			if _held_seconds >= _next_repeat and not seek_busy:
				_next_repeat = _held_seconds + SEEK_REPEAT_INTERVAL
				var steps := 6 if _held_seconds >= 4.0 else (3 if _held_seconds >= 2.0 else 1)
				actions.append({"operation": "seek_repeat", "direction": _seek_direction * steps})
			return actions
		suspend()
	for hand in ["left", "right"]:
		var stick: Vector2 = left if hand == "left" else right
		if not is_finite(stick.x) or not is_finite(stick.y):
			continue
		if stick.length() < 0.3:
			if hand == "left":
				left_latched = false
			else:
				right_latched = false
				right_zooming = false
			continue
		if (
			hand == "right"
			and zoom
			and (right_zooming or (not right_latched and absf(stick.y) >= absf(stick.x)))
		):
			right_zooming = true
			right_latched = true
			actions.append({"operation": "zoom", "amount": stick.y})
			continue
		var latched := left_latched if hand == "left" else right_latched
		if latched:
			continue
		# Cardinal pushes only: a diagonal does nothing (a stray diagonal once swapped the eyes).
		var action: Dictionary = {}
		if absf(stick.x) > 0.75 and absf(stick.y) < 0.3:
			var direction := 1 if stick.x > 0 else -1
			action = {"operation": "seek", "hand": hand, "direction": direction}
		if not action.is_empty():
			actions.append(action)
			if hand == "left":
				left_latched = true
			else:
				right_latched = true
			if scrub:
				seek_hand = hand
				_seek_direction = action.direction
				_held_seconds = 0.0
				_next_repeat = SEEK_HOLD_DELAY
				break
	return actions
