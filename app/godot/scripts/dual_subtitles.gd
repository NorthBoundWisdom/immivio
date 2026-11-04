extends RefCounted
## Two text channels share the existing playback clock, delay and caption renderer.
const State := preload("res://scripts/mpv_subtitle_state.gd")
const Methods := preload("res://scripts/platform_methods.gd")
var video: Node
var state := State.new()
var enabled := false


func _init(owner: Node) -> void:
	video = owner


func supported() -> bool:
	return Methods.supports(video.platform, "set_mpv_secondary_subtitle")


func primary_id() -> int:
	if video.subtitles.requested_track >= 0:
		return video.subtitles.requested_track
	return int(video.subtitles.cue.get("track_id", video.media.playback.get("details", {}).get("subtitle", {}).get("track_id", 0)))


func reset() -> void:
	enabled = false
	state.select(0)
	state.clear(true)


func select(id: int, remember: bool = true) -> bool:
	if id < 0 or not supported() or not video.media.accepts(video.media.session_id):
		return false
	if id > 0 and (id == primary_id() or not video.subtitle_tracks().any(func(track): return int(track.id) == id)):
		return false
	if not video.platform.set_mpv_secondary_subtitle(video.media.session_id, id):
		return false
	state.select(id)
	if id > 0:
		enabled = true
	if remember:
		video._remember_track("secondary_subtitle", id)
	video._subtitle_poll_ms = 0
	video.changed.emit()
	return true


func set_enabled(value: bool) -> bool:
	if not supported() or not video.media.accepts(video.media.session_id):
		return false
	if not value and not select(0):
		return false
	enabled = value
	state.clear()
	video.changed.emit()
	return true


func primary_changed() -> void:
	if primary_id() > 0 and primary_id() == state.requested_track:
		# Primary selection owns a collision. Keep both UI and saved secondary off.
		select(0)
	if primary_id() == 0:
		state.clear()


func observe(snapshot: Dictionary) -> void:
	if not enabled or int(snapshot.get("session_id", -1)) != video.media.session_id:
		state.clear()
		return
	var secondary: Variant = snapshot.get("secondary", {})
	if not secondary is Dictionary or secondary.is_empty():
		state.clear()
		return
	var cue: Dictionary = secondary.duplicate(true)
	for key in ["session_id", "source_epoch", "generation", "mpv_source_handle", "age_ms", "timeline_valid", "position_seconds"]:
		cue[key] = snapshot.get(key, -1)
	cue.required_command_id = snapshot.get("required_secondary_command_id", 0)
	state.observe(cue, video.media.session_id, video.media.last_pair)


func compose() -> String:
	if video.subtitles.requested_track == 0:
		return ""
	var primary: String = video.subtitles.text
	if not enabled or state.requested_track == primary_id() or state.text.is_empty():
		return primary
	return state.text if primary.is_empty() else primary + "\n" + state.text
