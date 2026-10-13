extends SceneTree
const Photo := preload("res://scripts/photo_display.gd")
const Memory := preload("res://scripts/file_mode_memory.gd")
const Thumbnails := preload("res://scripts/thumbnail_cache.gd")
var folder := "user://photo_preload_%d" % Time.get_ticks_usec()
var failures: Array[String] = []
var checks := 0

class Host extends RefCounted:
	var ready: Callable
	var folder := ""
	var next_id := 100
	var opens := 0
	var preloads := 0
	var held := {}
	var pending := {}
	var cancelled: Array[int] = []
	var activated: Array[int] = []
	func has_java_method(method: String) -> bool:
		return method in ["preload_photo", "activate_photo"]
	func make_file(uri: String) -> Dictionary:
		next_id += 1
		var path := folder.path_join("cache_%d.jpg" % next_id)
		DirAccess.copy_absolute(uri.trim_prefix("file://"), path)
		held[next_id] = path
		return {"id": next_id, "path": path}
	func open_photo(uri: String) -> int:
		opens += 1
		var file := make_file(uri)
		ready.call_deferred(file.id, JSON.stringify({"state":"ready", "path":file.path, "cache_bytes":4096}))
		return int(file.id)
	func preload_photo(uri: String) -> int:
		preloads += 1
		var file := make_file(uri)
		pending[file.id] = file.path
		return int(file.id)
	func complete() -> void:
		for id in pending.keys():
			ready.call_deferred(int(id), JSON.stringify({"state":"ready", "path":pending[id], "cache_bytes":4096}))
		pending.clear()
	func activate_photo(id: int) -> bool:
		if not held.has(id): return false
		activated.append(id)
		return true
	func release_photo(id: int) -> void:
		if held.has(id): DirAccess.remove_absolute(str(held[id])); held.erase(id)
	func cancel_photo(id: int) -> void: cancelled.append(id); release_photo(id)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void: call_deferred("_run")

func settle(photo: Node3D) -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while photo.loading and Time.get_ticks_msec() < deadline: await create_timer(.01).timeout
	check(not photo.loading, "Foreground settles")

func warm(photo: Node3D, host: RefCounted) -> void:
	photo.finish_transition()
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		host.complete()
		photo._pump_prefetch()
		if preloads_ready(photo,host): break
		await create_timer(.01).timeout
	check(preloads_ready(photo,host), "Adjacent preloads settle at the selected strength")

func preloads_ready(photo: Node3D, host: RefCounted) -> bool:
	for target in photo._neighbors(photo.index):
		if not photo._prefetched.has(target): return false
		var entry: Dictionary = photo._prefetched[target]
		if not entry.get("decoded", false): return false
		if photo.auto_depth:
			if not entry.has("depth_data"): return false
			if host.use_stereo and not is_equal_approx(float(entry.depth_data.get("strength", -1)), photo.depth_strength): return false
	return true

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var entries: Array[Dictionary] = []
	for i in 4:
		var image := Image.create(320,160,false,Image.FORMAT_RGB8)
		image.fill(Color(float(i)/4.0,.4,.6))
		var path := ProjectSettings.globalize_path(folder.path_join("photo_%d.jpg" % i))
		image.save_jpg(path)
		entries.append({"uri":"file://"+path, "title":"photo_%d.jpg" % i, "kind":"image"})
	var photo := Photo.new()
	photo.mode_memory = Memory.new(folder.path_join("modes")); photo.history_enabled = false
	root.add_child(photo)
	var host := Host.new(); host.folder = ProjectSettings.globalize_path(folder); host.ready = photo._on_ready
	photo.platform = host
	photo.open_image(entries[0].uri, entries[0].title, entries)
	await settle(photo); await warm(photo,host)
	check(host.opens == 1 and host.preloads == 2, "Initial display preloads next and wrapping previous through independent API")
	check(photo._prefetched.has(1) and photo._prefetched.has(3) and photo._prefetched.size() == 2, "Only two circular neighbours retained")
	check(Thumbnails.has(entries[1].uri) and Thumbnails.has(entries[3].uri), "Preloading persists thumbnails before neighbours are viewed")
	check(photo._prefetched[3].result.get("thumbnail_cached", false), "Cached decoded data remembers its persisted thumbnail")
	DirAccess.remove_absolute(Thumbnails.path_for(entries[3].uri))
	var first_request: int = photo._display_request
	var count: int = host.opens
	photo.navigate(-1)
	check(not photo.loading and photo.index == 3 and host.opens == count, "First-to-last uses decoded cache without foreground transfer")
	check(photo._transition_direction == -1, "Wrapping previous still enters from left")
	check(Thumbnails.has(entries[3].uri), "Cache hit restores a thumbnail removed by cache cleanup")
	await warm(photo,host)
	check(photo._prefetched.has(0) and int(photo._prefetched[0].id) == first_request, "Departing photo keeps its source and decoded data for return")
	photo.navigate(1)
	check(photo.index == 0 and not photo.loading and host.opens == count and photo._transition_direction == 1, "Last-to-first returns from cache with right entry")
	await warm(photo,host)
	photo.navigate(-1); photo.navigate(-1); photo.navigate(1)
	await settle(photo)
	check(photo.index == 3 and photo.pending_index == -1, "Rapid reversal back to displayed photo cancels stale request")
	host.complete(); await create_timer(.05).timeout
	check(photo.index == 3, "Late preload/foreground responses cannot overwrite chosen photo")
	await warm(photo,host)
	var invalid_id: int = photo._prefetched[2].id
	host.release_photo(invalid_id)
	count = host.opens
	photo.navigate(-1); await settle(photo)
	check(photo.index == 2 and host.opens == count + 1, "Missing cached source retries through normal foreground loading")
	await warm(photo,host)
	# A cancelled decoder owns its file until the worker returns.
	while photo._thread: await create_timer(.01).timeout
	photo.set_process(false)
	var neighbour: int = photo._neighbors(photo.index)[0]
	var id: int = photo._prefetched[neighbour].id
	var source_path: String = host.held[id]
	var entered := Semaphore.new(); var release := Semaphore.new()
	photo._decoding = {"id":id, "index":neighbour, "prefetch":true, "epoch":photo._cache_epoch}
	photo._thread = Thread.new()
	photo._thread.start(func(): entered.post(); release.wait(); return {"uncached":true})
	entered.wait()
	photo._drop_prefetch(neighbour)
	check(FileAccess.file_exists(source_path) and photo._deferred_release_ids.has(id), "Pruning does not unlink an active decoder source")
	release.post()
	while photo._thread.is_alive(): await create_timer(.01).timeout
	photo._process(0)
	check(not FileAccess.file_exists(source_path) and not photo._deferred_release_ids.has(id), "Worker completion releases the cancelled file lease")
	photo.set_process(true)
	photo.set_projection(3)
	photo._pump_prefetch()
	check(photo._prefetched.is_empty() and not photo.navigate(5), "Panorama keeps bounded navigation and has no background neighbour cache")
	photo.close_image()
	check(host.held.is_empty() and photo._prefetched.is_empty(), "Closing releases displayed and neighbouring sources")
	photo.open_image(entries[0].uri, entries[0].title)
	await settle(photo)
	count = host.preloads
	check(not photo.navigate(-1) and not photo.navigate(1) and not photo.snapshot().can_next, "Single-photo queue cannot navigate to itself")
	photo._pump_prefetch(); check(host.preloads == count, "Single photo starts no redundant preload")
	photo.open_image(entries[0].uri, entries[0].title, entries.slice(0,2))
	await settle(photo); await warm(photo,host)
	check(photo._prefetched.size() == 1, "Two-photo queue deduplicates previous/next to one preload")
	photo.navigate(-1)
	check(photo.index == 1 and photo._transition_direction == -1, "Two-photo reverse direction survives identical neighbour target")
	photo.queue_free(); await process_frame
	check(host.held.is_empty(), "Exiting releases all cache file ownership")
	# Large sources are retained as files; their tiny preview can still be cached.
	var large := Image.create(1,1,false,Image.FORMAT_RGB8).save_png_to_buffer()
	large[16]=0; large[17]=0; large[18]=32; large[19]=0
	large[20]=0; large[21]=0; large[22]=16; large[23]=0
	var large_path := ProjectSettings.globalize_path(folder.path_join("large-header.png"))
	FileAccess.open(large_path, FileAccess.WRITE).store_buffer(large)
	var bounded := Photo._decode({"prefetch":true, "info":{"path":large_path, "thumbnail_path":str(entries[0].uri).trim_prefix("file://"), "orientation":6}})
	check(bounded.get("uncached", false) and not bounded.has("image"), "8K predecode is skipped before allocating pixels above the cache budget")
	check(bounded.has("thumbnail") and bounded.thumbnail.get_height() > bounded.thumbnail.get_width(), "Large-file thumbnail remains available with EXIF orientation")
	for failure in failures: push_error(failure)
	print("Photo preload/cycle: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
