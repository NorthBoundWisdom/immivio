extends RefCounted
## One palette for flat, curved and vertical text; bitmap captions retain source colors.
const NAMES := ["White text", "Yellow text", "Cyan text", "Green text", "Dark text"]
const INK := [Color.WHITE, Color("ffe080"), Color("8feaff"), Color("aff0a0"), Color("161a20")]


static func index(value: Variant) -> int:
	if not (value is int or value is float) or not is_finite(float(value)):
		return 0
	return (
		int(value)
		if float(value) == floorf(float(value)) and int(value) >= 0 and int(value) < NAMES.size()
		else 0
	)


static func outline(value: int) -> Color:
	return Color.WHITE if index(value) == 4 else Color.BLACK


static func choices(value: int) -> Dictionary:
	var options := []
	for i in NAMES.size():
		options.append({"value": i, "label": NAMES[i]})
	return {"key": "subtitle_palette", "value": index(value), "choices": options}
