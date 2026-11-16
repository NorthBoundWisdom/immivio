extends RefCounted
## Refresh matching and performance hysteresis have no device IO here.
const REFRESH_SETTLE_MS := 1500
const POWER_SETTLE_MS := 3000
var wanted_rate := -1.0
var rate_since := 0
var applied_rate := 0.0
var high := false
var low_since := -1


static func video_rate(fps: float, available: Array, cap: float) -> float:
	if not is_finite(fps) or fps < 10 or fps > 130:
		return 0.0
	var rates: Array = available.filter(
		func(r):
			return (
				(r is int or r is float)
				and is_finite(float(r))
				and float(r) >= 59.5
				and float(r) <= cap + 0.5
			)
	)
	rates.sort()
	for rate in rates:
		var repeats := roundf(float(rate) / fps)
		if repeats >= 1 and absf(float(rate) - repeats * fps) <= float(rate) * 0.005:
			return float(rate)
	return float(rates[-1]) if cap > 90.5 and not rates.is_empty() else 0.0


func tick(demand: bool, rate: float, now_ms: int) -> Dictionary:
	var changes := {}
	if demand:
		low_since = -1
		if not high:
			high = true
			changes["high"] = true
	elif high:
		if low_since < 0:
			low_since = now_ms
		elif now_ms - low_since >= POWER_SETTLE_MS:
			high = false
			low_since = -1
			changes["high"] = false
	if not is_equal_approx(rate, wanted_rate):
		wanted_rate = rate
		rate_since = now_ms
	elif now_ms - rate_since >= REFRESH_SETTLE_MS and not is_equal_approx(rate, applied_rate):
		applied_rate = rate
		changes["rate"] = rate
	return changes
