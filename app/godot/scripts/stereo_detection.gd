extends RefCounted
## Bounded, local image evidence for unmarked packed stereo. No projection or eye-order guess.
const SIZE := Vector2i(48, 32)
const MAX_SAMPLES := 5
var token := 0
var pending := false
var samples := 0
var captures := 0
var last_frame := -1
var due_ms := 0
var _vote := ""
var _count := 0


func begin(enabled: bool) -> void:
	token += 1
	pending = enabled
	samples = 0
	captures = 0
	last_frame = -1
	due_ms = 0
	_vote = ""
	_count = 0


func cancel() -> void:
	token += 1
	pending = false
	_vote = ""
	_count = 0


func wants(frame: int, allow_still: bool = false) -> bool:
	return (
		pending
		and samples < MAX_SAMPLES
		and captures < 12
		and (allow_still or frame != last_frame)
		and Time.get_ticks_msec() >= due_ms
	)


func started(frame: int) -> int:
	last_frame = frame
	captures += 1
	due_ms = Time.get_ticks_msec() + 350
	return token


func accept(request: int, result: Dictionary) -> String:
	if request != token or not pending:
		return ""
	if not bool(result.get("usable", false)):
		due_ms = Time.get_ticks_msec() + 1500
		pending = captures < 12
		return ""
	samples += 1
	var layout := str(result.get("layout", ""))
	if layout in ["sbs", "tb"]:
		_count = _count + 1 if layout == _vote else 1
		_vote = layout
		if _count >= 2:
			pending = false
			return layout
	else:
		_vote = ""
		_count = 0
	if samples >= MAX_SAMPLES:
		pending = false
	return ""


static func _features(image: Image, rect: Rect2i) -> PackedFloat32Array:
	var eye := image.get_region(rect)
	eye.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_BILINEAR)
	var luma := PackedFloat32Array()
	luma.resize(SIZE.x * SIZE.y)
	for y in SIZE.y:
		for x in SIZE.x:
			luma[y * SIZE.x + x] = eye.get_pixel(x, y).get_luminance()
	var details := PackedFloat32Array()
	details.resize(luma.size())
	for y in range(1, SIZE.y - 1):
		for x in range(1, SIZE.x - 1):
			var i := y * SIZE.x + x
			details[i] = (
				luma[i] - (luma[i - 1] + luma[i + 1] + luma[i - SIZE.x] + luma[i + SIZE.x]) * .25
			)
	return details


static func _tile(a: PackedFloat32Array, b: PackedFloat32Array, x: int, y: int) -> float:
	var best := -1.0
	for shift in range(-4, 5):
		var sa := 0.0
		var sb := 0.0
		var aa := 0.0
		var bb := 0.0
		var ab := 0.0
		for row in range(y, y + 10):
			for col in range(x, x + 10):
				var left := a[row * SIZE.x + col]
				var right := b[row * SIZE.x + col + shift]
				sa += left
				sb += right
				aa += left * left
				bb += right * right
				ab += left * right
		var va := aa - sa * sa / 100.0
		var vb := bb - sb * sb / 100.0
		# Smooth gradients, black bars and fades are not evidence of matching eye images.
		if minf(va, vb) < .002:
			continue
		best = maxf(best, (ab - sa * sb / 100.0) / sqrt(va * vb))
	return best


static func _score(image: Image, stacked: bool) -> Dictionary:
	var size := image.get_size()
	var half := Vector2i(size.x, size.y / 2) if stacked else Vector2i(size.x / 2, size.y)
	var a := _features(image, Rect2i(Vector2i.ZERO, half))
	var b := _features(image, Rect2i(Vector2i(0, half.y) if stacked else Vector2i(half.x, 0), half))
	var scores: Array[float] = []
	for y in [4, 17]:
		for x in [5, 18, 31]:
			var value := _tile(a, b, x, y)
			if value >= 0:
				scores.append(value)
	if scores.size() < 3:
		return {"score": 0.0, "textured": scores.size()}
	scores.sort()
	var top := scores.slice(scores.size() - 3)
	return {
		"score": (top[0] + top[1] + top[2]) / 3.0 if top[0] >= .65 else 0.0,
		"textured": scores.size()
	}


static func classify(image: Image) -> Dictionary:
	if not image or image.is_empty() or image.get_width() < 32 or image.get_height() < 32:
		return {}
	var side := _score(image, false)
	var stacked := _score(image, true)
	var sbs := float(side.score)
	var tb := float(stacked.score)
	var layout := ""
	if maxf(sbs, tb) >= .8 and absf(sbs - tb) >= .15:
		layout = "sbs" if sbs > tb else "tb"
	return {
		"layout": layout,
		"sbs": sbs,
		"tb": tb,
		"usable": maxi(int(side.textured), int(stacked.textured)) >= 3
	}
