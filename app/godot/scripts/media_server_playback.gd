extends RefCounted
## Adapted from Thru3D 0.16.5. Native binding validates provider and PlaybackInfo identity.
const Methods := preload("res://scripts/platform_methods.gd")
var uri := ""
var token := ""
var next_poll := 0
var privacy: Variant = null
var ended := false
var suppressed := false


func begin(value: String, allowed: bool = true) -> void:
	suppressed = not allowed
	uri = value if value.begins_with("medialib://") else ""
	token = str(Time.get_ticks_usec()) if not uri.is_empty() else ""
	next_poll = 0
	ended = false


func configure(platform: Object, enabled: bool) -> void:
	if not enabled:
		suppressed = true
	if Methods.supports(platform, "media_server_playback") and privacy != enabled:
		platform.media_server_playback(JSON.stringify({"action": "privacy", "enabled": enabled}))
		privacy = enabled


func poll(video: Node, force: bool = false) -> void:
	configure(video.platform, video.history_enabled)
	if (
		not video.history_enabled
		or suppressed
		or ended
		or token.is_empty()
		or video.local_uri != uri
		or not Methods.supports(video.platform, "media_server_playback")
	):
		return
	var now := Time.get_ticks_msec()
	if not force and now < next_poll:
		return
	next_poll = now + 250
	if (
		video._waiting_first
		or not video._pending_revision.is_empty()
		or video.control.pending
		or video.control.in_flight > 0
	):
		return
	var pair: Dictionary = video.media.last_pair
	if (
		not pair.get("source_pts_verified", false)
		or int(pair.get("session_id", 0)) != video.media.session_id
		or int(pair.get("generation", 0)) != video.media.generation
		or int(pair.get("pts_us", -1)) < 0
	):
		return
	if video.media.state not in ["playing", "paused", "buffering", "ready", "ended"]:
		return
	var details: Dictionary = video.media.playback.get("details", {})
	video.platform.media_server_playback(
		JSON.stringify(
			{
				"action": "state",
				"token": token,
				"uri": uri,
				"position_ms": int(pair.pts_us) / 1000,
				"paused": not video.requested_play or str(details.get("paused", "no")) == "yes",
				"can_seek": details.get("seekable", "no") == "yes"
			}
		)
	)
	if video.media.state == "ended" and not video.loop_enabled and video.completed_presentation():
		video.platform.media_server_playback(JSON.stringify({"action": "stop", "token": token}))
		ended = true


func finish(platform: Object) -> void:
	if not token.is_empty() and Methods.supports(platform, "media_server_playback"):
		platform.media_server_playback(JSON.stringify({"action": "stop", "token": token}))
	uri = ""
	token = ""
