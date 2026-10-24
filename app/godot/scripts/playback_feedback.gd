extends Node3D
## A small status plane during loading; no forced control-bar reopen for ordinary buffering.
const I18n := preload("res://scripts/i18n.gd")
const Menu := preload("res://scripts/ray_menu.gd")
var host: Node3D
var label: Label3D
var since := 0
var session := ""
var error_seen := ""
var message := ""


func _ready() -> void:
	label = Label3D.new()
	label.font = Menu.ui_font()
	label.font_size = 24
	label.pixel_size = 0.001
	label.outline_size = 8
	label.no_depth_test = true
	add_child(label)
	visible = false


func tick() -> void:
	if not is_instance_valid(host.video_menu):
		return
	var video: Node3D = host.video
	var key: String = str(video.media.session_id) + "/" + video.local_uri
	var details: Dictionary = video.media.playback.get("details", {})
	var stage := ""
	if host.photo_active:
		key = "photo/" + host.photo.local_uri
		if host.photo.loading:
			stage = "Loading image"
	elif video.media.accepts(video.media.session_id):
		if video._waiting_first or video.media.state in ["opening", "buffering"]:
			stage = str(video.media.playback.get("loading_stage", "Waiting for video"))
		elif str(details.get("paused_for_cache", "no")) == "yes":
			stage = "Buffering"
	if key != session:
		session = key
		since = 0
		error_seen = ""
	var failure: String = video.media.error if not host.photo_active else ""
	if not failure.is_empty() and error_seen != failure:
		error_seen = failure
		host._show_player_menu()
		host.video_menu._quick_open = "info"
		host.video_menu.refresh()
	if stage.is_empty():
		since = 0
		message = ""
		visible = false
		return
	if since == 0:
		since = Time.get_ticks_msec()
		var pose: Variant = host._view_pose(1.4, 0.30)
		global_transform = (
			pose if pose != null else Transform3D(Basis.IDENTITY, Vector3(0, 1.3, -1.4))
		)
	var previous := message
	var seconds := maxi(0, (Time.get_ticks_msec() - since) / 1000)
	message = I18n.t(stage) + " · %d s" % seconds
	var speed := (
		maxf(0, float(details.get("read_bytes_per_second", 0))) if not host.photo_active else 0.0
	)
	if speed > 0:
		message += (
			" · %.1f MB/s" % (speed / 1048576.0)
			if speed >= 1048576
			else " · %.0f KB/s" % (speed / 1024.0)
		)
	label.text = message
	if previous != message and host.player_menu.visible:
		host.player_menu.refresh_values()
	visible = not host.player_menu.visible and not host.recent_menu.visible
