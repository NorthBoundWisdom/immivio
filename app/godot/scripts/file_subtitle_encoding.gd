extends RefCounted
## Policy adapted from Thru3D 9a6a905..da5f86c; persistence belongs to FileModeMemory.
const CHOICES := [
	"auto",
	"UTF-8",
	"UTF-16LE",
	"UTF-16BE",
	"windows-949",
	"GB18030",
	"Big5",
	"windows-31j",
	"windows-1252"
]


static func valid(values: Variant) -> bool:
	if not values is Dictionary or values.size() > 16:
		return false
	for key in values:
		if (
			not key is String
			or key.length() != 64
			or not key.is_valid_hex_number(false)
			or values[key] not in CHOICES
		):
			return false
	return true


static func row(tracks: Array, selected: int, values: Dictionary) -> Dictionary:
	for track in tracks:
		if int(track.get("id", 0)) != selected or not track.get("external", false):
			continue
		var key := str(track.get("encoding_key", ""))
		if key.length() != 64:
			return {}
		var choices: Array = []
		for encoding in CHOICES:
			choices.append(
				{
					"label": "Auto" if encoding == "auto" else encoding,
					"value": {"track_key": key, "encoding": encoding}
				}
			)
		return {
			"key": "subtitle_encoding",
			"value": {"track_key": key, "encoding": values.get(key, "auto")},
			"choices": choices,
			"dropdown": true
		}
	return {}
