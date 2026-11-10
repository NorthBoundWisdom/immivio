extends SceneTree
const Menu := preload("res://scripts/library_menu.gd")
const Cache := preload("res://scripts/thumbnail_cache.gd")
var failures: Array[String] = []


class Host:
	extends RefCounted
	var requests: Array[String] = []
	var cancels := 0

	func media_local_thumbnail(uri: String) -> int:
		requests.append(uri)
		return 100 + requests.size()

	func media_local_thumbnail_cancel() -> void:
		cancels += 1


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)


func _initialize() -> void:
	if preload("res://tests/support/test_result.gd").prepare(self):
		_run.call_deferred()


func _run() -> void:
	Cache.clear()
	var image := Image.create(640, 180, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	image.fill_rect(Rect2i(320, 0, 320, 180), Color.BLUE)
	var mode := {"stereo": true, "top_bottom": false, "geometry": 0}
	var left := Cache.preview_frame(image, mode, Vector2(3840, 1080))
	check(
		left.get_pixel(100, 50).r > .9 and left.get_pixel(left.get_width() - 1, 50).b < .1,
		"SBS thumbnail contains one eye rather than a packed pair"
	)
	mode.swap = true
	check(
		Cache.preview_frame(image, mode, Vector2(3840, 1080)).get_pixel(100, 50).b > .9,
		"Reversed eye order selects the logical left eye"
	)
	var tall := Image.create(320, 360, false, Image.FORMAT_RGB8)
	tall.fill(Color.GREEN)
	tall.fill_rect(Rect2i(0, 180, 320, 180), Color.BLUE)
	check(
		(
			(
				Cache
				. preview_frame(
					tall, {"stereo": true, "top_bottom": true, "geometry": 0}, Vector2(1920, 2160)
				)
				. get_pixel(100, 50)
				. g
			)
			> .9
		),
		"Top-bottom thumbnail selects the top eye"
	)
	var panorama_source := Image.create(640, 320, false, Image.FORMAT_RGB8)
	panorama_source.fill(Color.BLUE)
	panorama_source.fill_rect(Rect2i(240, 115, 160, 90), Color.RED)
	var panorama := Cache.preview_frame(panorama_source, {"geometry": 3}, Vector2(4096, 2048))
	check(
		(
			panorama.get_size() == Cache.SIZE
			and panorama.get_pixel(10, 10).r > .9
			and panorama.get_pixel(310, 170).r > .9
		),
		"360 thumbnail uses the existing central panorama crop"
	)
	var half_source := Image.create(640, 360, false, Image.FORMAT_RGB8)
	half_source.fill(Color.BLUE)
	half_source.fill_rect(Rect2i(0, 0, 320, 360), Color.RED)
	half_source.fill_rect(Rect2i(0, 0, 320, 30), Color.GREEN)
	half_source.fill_rect(Rect2i(0, 330, 320, 30), Color.YELLOW)
	var half := Cache.fit(
		Cache.preview_frame(
			half_source, {"stereo": true, "stereo_half": true, "geometry": 0}, Vector2(1920, 1080)
		)
	)
	check(
		half.get_pixel(160, 2).g > .9 and half.get_pixel(160, 177).g > .9,
		"Half-SBS preview preserves the top and bottom instead of cropping the anamorphic eye"
	)
	var menu := Menu.new()
	root.add_child(menu)
	menu.set_process(false)
	var host := Host.new()
	menu.platform = host
	menu.visible = true
	menu.section = Menu.Section.LOCAL
	menu._local_stack = [{"id": "/Movies", "title": "Movies"}]
	menu._local_entries = [
		{
			"uri": "file:///Movies/demo_SBS.mp4",
			"title": "demo_SBS.mp4",
			"kind": "video",
			"id": "/Movies/demo_SBS.mp4"
		},
		{
			"uri": "file:///Movies/next.mp4",
			"title": "next.mp4",
			"kind": "video",
			"id": "/Movies/next.mp4"
		}
	]
	menu.refresh()
	menu.local_thumbnails.tick(menu)
	check(
		host.requests == ["file:///Movies/demo_SBS.mp4"],
		"Browsing requests an unplayed local video"
	)
	menu.local_thumbnails.tick(menu)
	check(host.requests.size() == 1, "Only one decode is outstanding")
	menu._sources._on_media_list(
		101,
		JSON.stringify(
			{
				"source": "local_thumbnail",
				"state": "ready",
				"uri": host.requests[0],
				"width": 3840,
				"height": 1080,
				"jpeg": Marshalls.raw_to_base64(image.save_jpg_to_buffer())
			}
		)
	)
	check(
		Cache.has(host.requests[0]) and menu._picture({"uri": host.requests[0]}) != null,
		"Native preview uses the shared library cache"
	)
	check(
		Cache.texture(host.requests[0]).get_image().get_pixel(150, 90).r > .8,
		"Native response is cropped before it is cached"
	)
	check(
		Cache.is_preview(host.requests[0]), "Browsing previews are marked for playback replacement"
	)
	var signature: String = menu.local_thumbnails.signature(menu.rows[0])
	check(
		Cache.preview_matches(host.requests[0], signature),
		"Preview fingerprint survives cache reloads"
	)
	check(
		not Cache.preview_matches(host.requests[0], signature + "changed"),
		"Replaced files invalidate preview fingerprints"
	)
	var video := preload("res://scripts/mpv_video_display.gd").new()
	video.platform = preload("res://tests/test_player_menu.gd").Host.new()
	root.add_child(video)
	video.open_local(host.requests[0], "demo_SBS.mp4")
	check(
		video._thumb_after_ms >= 0,
		"Opening a previewed video still schedules a displayed-frame capture"
	)
	video.queue_free()
	await process_frame
	Cache.store(host.requests[0], image)
	check(not Cache.is_preview(host.requests[0]), "A played frame replaces the preview marker")
	menu.local_thumbnails._next_request = 0
	menu.local_thumbnails.tick(menu)
	check(host.requests.size() == 2, "Visible items are decoded sequentially")
	menu.playback_browser = true
	menu.local_thumbnails.tick(menu)
	check(host.cancels == 1, "Playback browsing cancels the background decoder")
	menu._sources._on_media_list(
		102,
		JSON.stringify(
			{
				"source": "local_thumbnail",
				"state": "ready",
				"uri": host.requests[1],
				"width": 640,
				"height": 180,
				"jpeg": Marshalls.raw_to_base64(image.save_jpg_to_buffer())
			}
		)
	)
	check(not Cache.has(host.requests[1]), "A canceled late reply cannot repopulate the cache")
	menu.local_thumbnails.tick(menu)
	check(host.requests.size() == 2, "Playback does not request more thumbnails")
	menu.playback_browser = false
	menu.local_thumbnails._next_request = 0
	menu.local_thumbnails.tick(menu)
	menu._local_stack = [{"id": "/Other", "title": "Other"}]
	menu._sources._on_media_list(
		103,
		JSON.stringify(
			{
				"source": "local_thumbnail",
				"state": "ready",
				"uri": host.requests[1],
				"width": 640,
				"height": 180,
				"jpeg": Marshalls.raw_to_base64(image.save_jpg_to_buffer())
			}
		)
	)
	check(not Cache.has(host.requests[1]), "A reply from a previous directory is discarded")
	menu._local_stack = [{"id": "/Movies", "title": "Movies"}]
	menu.local_thumbnails.cancel(menu)
	menu.local_thumbnails._next_request = 0
	menu.local_thumbnails.tick(menu)
	menu.local_thumbnails.set_suspended(menu, true)
	menu.local_thumbnails.tick(menu)
	var request_count := host.requests.size()
	check(
		menu.local_thumbnails._pending.is_empty(),
		"Suspension releases a native-canceled request immediately"
	)
	menu.local_thumbnails.tick(menu)
	check(host.requests.size() == request_count, "Suspended library does not request previews")
	menu.local_thumbnails.set_suspended(menu, false)
	menu.local_thumbnails._next_request = 0
	menu.local_thumbnails.tick(menu)
	check(
		host.requests.size() == request_count + 1,
		"Return retries the canceled file without waiting for a timeout"
	)
	var pending_id: int = menu.local_thumbnails._pending.id
	menu.rows[1].size = 12345
	menu._sources._on_media_list(
		pending_id,
		JSON.stringify(
			{
				"source": "local_thumbnail",
				"state": "ready",
				"uri": host.requests[1],
				"width": 640,
				"height": 180,
				"jpeg": Marshalls.raw_to_base64(image.save_jpg_to_buffer())
			}
		)
	)
	check(not Cache.has(host.requests[1]), "A replaced file rejects its old in-flight preview")
	Cache.store("file:///evict.mp4", image, "preview")
	Cache.protect_keys([])
	Cache.prune(0)
	check(
		not Cache.has("file:///evict.mp4") and not Cache.is_preview("file:///evict.mp4"),
		"Cache eviction removes preview markers as well as images"
	)
	menu.queue_free()
	await process_frame
	Cache.clear()
	check(
		Cache.usage() == Vector2i.ZERO, "Clear cache removes previews without a second native cache"
	)
	print("Local thumbnail failures: %d" % failures.size())
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
