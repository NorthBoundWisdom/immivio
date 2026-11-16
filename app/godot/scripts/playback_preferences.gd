extends RefCounted
## Shared validation for disk preferences and UI input.
const STEPS := [5, 10, 15, 20, 30, 60]


static func speed(value: Variant) -> float:
	return (
		clampf(float(value), 0.25, 3.0)
		if (value is float or value is int) and is_finite(float(value))
		else 1.0
	)


static func seek_step(value: Variant) -> int:
	return (
		int(value)
		if (
			(value is int or value is float)
			and is_finite(float(value))
			and float(value) == int(value)
			and int(value) in STEPS
		)
		else 10
	)


static func transparency(value: Variant) -> float:
	return (
		clampf(float(value), 0.0, 80.0)
		if (value is float or value is int) and is_finite(float(value))
		else 0.0
	)
