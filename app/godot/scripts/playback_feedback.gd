extends "res://scripts/ray_menu.gd"
## A small status plane during loading; no forced control-bar reopen for ordinary buffering.
var host: Node3D
var label: Label3D
var since := 0
var session := ""
var error_seen := ""
var message := ""


func _ready() -> void:
	# Share the menus' high-resolution capture, without drawing a menu or adding hit targets.
	curve_radius = 0.0
	label = Label3D.new()
	label.font = ui_font_bold()
	label.language = I18n.language
	label.font_size = 48
	label.pixel_size = 0.0007
	label.outline_size = 4
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	label.no_depth_test = true
	add_child(label)
	visible = false


func capture_envelope() -> Rect2:
	# Layout stays fixed as the elapsed time and transfer rate change.
	return Rect2(-0.55, -0.06, 1.1, 0.12)


func paint_state_key() -> int:
	return hash([message, label.language])


func snapshot() -> Dictionary:
	return {
		"message": message,
		"visible": visible,
		"native_overlay":
		(
			visible
			and is_instance_valid(xr_surface)
			and xr_surface.native_supported
			and xr_surface.is_layout_presented(self)
		)
	}


func tick() -> void:
	if not is_instance_valid(host.video_menu):
		return
	var video: Node3D = host.video
	var key: String = str(video.media.session_id) + "/" + video.local_uri
	var details: Dictionary = video.media.playback.get("details", {})
	var stage := ""
	if video.media.accepts(video.media.session_id):
		if (
			(video._waiting_first or video.media.state in ["opening", "buffering"])
			and not video.stick_scrubbing
		):
			stage = str(video.media.playback.get("loading_stage", "Waiting for video"))
		elif str(details.get("paused_for_cache", "no")) == "yes":
			stage = "Buffering"
	if key != session:
		session = key
		since = 0
		error_seen = ""
	var failure: String = video.media.error
	if not failure.is_empty() and error_seen != failure:
		error_seen = failure
		host.presentation_coordinator._show_player_menu()
		host.video_menu._quick_open = "info"
		host.video_menu.refresh()
	if stage.is_empty():
		since = 0
		message = ""
		visible = false
		return
	if since == 0:
		since = Time.get_ticks_msec()
		var pose: Variant = host.presentation_coordinator._view_pose(1.4, 0.30)
		global_transform = (
			pose if pose != null else Transform3D(Basis.IDENTITY, Vector3(0, 1.3, -1.4))
		)
	var previous := message
	var seconds := maxi(0, (Time.get_ticks_msec() - since) / 1000)
	message = I18n.t(stage) + " · %d s" % seconds
	var speed := maxf(0, float(details.get("read_bytes_per_second", 0)))
	if speed > 0:
		message += (
			" · %.1f MB/s" % (speed / 1048576.0)
			if speed >= 1048576
			else " · %.0f KB/s" % (speed / 1024.0)
		)
	if label.language != I18n.language:
		label.language = I18n.language
		label.font = ui_font_bold()
	label.text = message
	if previous != message and host.player_menu.visible:
		host.player_menu.refresh_values()
	visible = not host.player_menu.visible and not host.library_menu.visible
