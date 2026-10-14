extends SceneTree

const Catalog := preload("res://scripts/recent_files.gd")
const Scan := preload("res://scripts/recent_scan.gd")
const Main := preload("res://scripts/main.gd")
var failures: Array[String] = []
var checks := 0


class Host:
	extends RefCounted
	signal local_video_access(id: int, payload: String)
	var calls: Array[String] = []
	var cancelled: Array[int] = []
	var serial := 0
	var busy := false

	func request_local_video_access(uri: String) -> int:
		calls.append(uri)
		serial += 1
		return -1 if busy else serial

	func cancel_local_video_access(id: int) -> void:
		cancelled.append(id)

	func reply(id: int, uri: String, error: String = "", confirmed: bool = false) -> void:
		local_video_access.emit(
			id,
			JSON.stringify(
				{
					"uri": uri,
					"state": "readable" if error.is_empty() else "error",
					"error": error,
					"missing_confirmed": confirmed
				}
			)
		)


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)


func _initialize() -> void:
	if not preload("res://tests/support/test_result.gd").prepare(self):
		return
	call_deferred("_run")


func scanner(catalog: RefCounted, host: Object = null) -> Node:
	var scan := Scan.new()
	root.add_child(scan)
	scan.start(catalog, host)
	scan.set_process(false)
	return scan


func add(catalog: RefCounted, uri: String) -> void:
	catalog.opened(uri, "Synthetic media", true)
	catalog.save()


func _run() -> void:
	var folder := ProjectSettings.globalize_path(
		"res://../../build/output/recent-scan/" + str(Time.get_ticks_usec())
	)
	DirAccess.make_dir_recursive_absolute(folder)
	var existing := folder.path_join("测试 + video.mp4")
	var file := FileAccess.open(existing, FileAccess.WRITE)
	file.store_string("synthetic placeholder; never decoded")
	file.close()
	var live_uri := "file://" + existing.uri_encode().replace("%2F", "/")
	var missing_uri := "file://" + folder.path_join("removed.mp4")
	var catalog := Catalog.new(folder.path_join("history"))
	add(catalog, live_uri)
	add(catalog, missing_uri)
	add(catalog, "file://" + folder.path_join("unavailable/movie.mp4"))
	add(catalog, "file:///Volumes/Immivio-Synthetic-Unmounted/movie.mp4")
	add(catalog, "https://example.invalid/offline.mp4")
	add(catalog, "smb://offline/share/movie.mp4")
	add(catalog, "content://offline/document/unknown")
	var before: Dictionary = catalog.lookup(live_uri)
	var scan := scanner(catalog)
	for i in 8:
		scan._process(0.1)
	check(catalog.lookup(missing_uri).is_empty(), "Startup scan removes a deleted local file")
	check(
		catalog.lookup(live_uri) == before and FileAccess.file_exists(existing),
		"Existing Unicode/escaped path and resume metadata stay unchanged"
	)
	check(
		catalog.lookup("file://" + folder.path_join("unavailable/movie.mp4")).is_empty(),
		"Deleting a containing folder also prunes its missing children"
	)
	check(
		catalog.list_recent().size() == 5,
		"Unavailable volumes, network URLs and unsupported providers stay in history"
	)
	var reloaded := Catalog.new(catalog.directory)
	reloaded.load_saved()
	check(reloaded.lookup(missing_uri).is_empty(), "Removal persists across application restarts")
	scan.free()
	var local_host := Host.new()
	add(catalog, missing_uri)
	scan = scanner(catalog, local_host)
	scan._process(0.1)
	check(
		local_host.calls == [missing_uri],
		"Android checks one file at a time through asynchronous preflight"
	)
	local_host.reply(local_host.serial, missing_uri, "LOCAL_DOCUMENT_MISSING")
	check(
		catalog.lookup(missing_uri).is_empty(),
		"Android missing-file response is confirmed against the readable parent directory"
	)
	scan.free()
	for error in [
		"",
		"LOCAL_DOCUMENT_PERMISSION_LOST",
		"LOCAL_DOCUMENT_TIMEOUT",
		"LOCAL_DOCUMENT_UNREADABLE",
		"LOCAL_DOCUMENT_MISSING"
	]:
		var uri: String = "content://synthetic/document/" + error
		var history := Catalog.new(folder.path_join("provider" + str(checks)))
		add(history, uri)
		var host := Host.new()
		scan = scanner(history, host)
		scan._process(0.1)
		host.reply(host.serial, uri, error)
		check(
			not history.lookup(uri).is_empty(),
			"Unconfirmed provider response keeps history: " + error
		)
		scan.free()
	var uri := "content://synthetic/document/deleted"
	var host := Host.new()
	var history := Catalog.new(folder.path_join("confirmed"))
	add(history, uri)
	scan = scanner(history, host)
	scan._process(0.1)
	var id: int = host.serial
	host.reply(id - 1, uri, "LOCAL_DOCUMENT_MISSING", true)
	host.reply(id, uri + "wrong", "LOCAL_DOCUMENT_MISSING", true)
	host.local_video_access.emit(id, "invalid JSON")
	check(
		not history.lookup(uri).is_empty() and scan._request == id,
		"Stale, mismatched and malformed callbacks cannot delete records"
	)
	host.reply(id, uri, "LOCAL_DOCUMENT_MISSING", true)
	check(history.lookup(uri).is_empty(), "Confirmed missing document is removed")
	var provider_reload := Catalog.new(history.directory)
	provider_reload.load_saved()
	check(provider_reload.lookup(uri).is_empty(), "Confirmed document removal is persisted")
	scan.free()
	add(history, uri)
	scan = scanner(history, host)
	scan._process(0.1)
	add(history, uri)  # The user reopened it while its old startup check was pending.
	host.reply(host.serial, uri, "LOCAL_DOCUMENT_MISSING", true)
	check(
		not history.lookup(uri).is_empty(),
		"A newly reopened record survives an older missing response"
	)
	scan.free()
	scan = scanner(history, host)
	scan._process(0.1)
	id = host.serial
	scan._process(13.0)
	host.reply(id, uri, "LOCAL_DOCUMENT_MISSING", true)
	check(
		host.cancelled.has(id) and not history.lookup(uri).is_empty(),
		"Timeout cancels the check and ignores late completion"
	)
	scan.free()
	host.busy = true
	scan = scanner(history, host)
	for i in 5:
		scan._process(0.3)
	check(
		scan._pending.is_empty() and not history.lookup(uri).is_empty(),
		"Busy preflight retries are bounded without deleting history"
	)
	scan.free()
	host.busy = false
	scan = scanner(history, host)
	scan._process(0.1)
	id = host.serial
	scan.free()
	check(
		host.cancelled.has(id) and not host.local_video_access.has_connections(),
		"Shutdown cancels pending work and disconnects its listener"
	)
	# Exercise the actual application's startup wiring with an isolated catalog.
	var main := Main.new()
	main.settings_path = folder.path_join("settings.cfg")
	root.add_child(main)
	var startup: Node
	for child in main.get_children():
		if child.get_script() == Scan:
			startup = child
	check(
		startup != null and startup.catalog == main.video.recent_files,
		"Application startup scans the shared video/photo Recent catalog"
	)
	main.free()
	for failure in failures:
		printerr(failure)
	print(
		(
			"Recent startup scan checks: %s (%d)"
			% ["passed" if failures.is_empty() else "failed", checks]
		)
	)
	preload("res://tests/support/test_result.gd").finish(self, 0 if failures.is_empty() else 1)
