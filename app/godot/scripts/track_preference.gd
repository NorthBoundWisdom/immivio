extends RefCounted
## Persist intent, not MPV's automatically selected track. Metadata guards against
## a server reusing a numeric ID for a different language after a library refresh.
const FIELDS := ["language", "title", "codec"]


static func valid(value: Variant) -> bool:
	if not value is Dictionary or not value.has("id"):
		return false
	var id: Variant = value.id
	if (
		not (id is int or id is float)
		or not is_finite(float(id))
		or float(id) != floorf(float(id))
		or id < -1
		or id > 2147483647
	):
		return false
	for field in FIELDS:
		if value.has(field) and (not value[field] is String or value[field].length() > 256):
			return false
	return true


static func capture(id: int, tracks: Array) -> Dictionary:
	if id <= 0:
		return {"id": id} if id >= -1 else {}
	for track in tracks:
		if not track is Dictionary or int(track.get("id", 0)) != id:
			continue
		var result := {"id": id}
		for field in FIELDS:
			var text := str(track.get(field, "")).strip_edges().left(256)
			if not text.is_empty():
				result[field] = text
		return result
	return {}


static func resolve(preference: Dictionary, tracks: Array) -> Variant:
	if not valid(preference):
		return null
	if int(preference.id) <= 0:
		return int(preference.id)
	var candidates: Array[int] = []
	var described := FIELDS.any(func(field): return preference.has(field))
	for track in tracks:
		if not track is Dictionary or int(track.get("id", 0)) <= 0:
			continue
		if not FIELDS.all(
			func(field): return ( not preference.has(field) or str(track.get(field, "")).strip_edges().left(256) == preference[field] )
		):
			continue
		var id := int(track.id)
		if id == int(preference.id):
			return id
		if described:
			candidates.append(id)
	# Ambiguous or missing tracks must not silently select a different language.
	return candidates[0] if candidates.size() == 1 else null
