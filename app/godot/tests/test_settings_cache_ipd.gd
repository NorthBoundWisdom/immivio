extends SceneTree
const Menu := preload("res://scripts/player_menu.gd")
const Warmup := preload("res://scripts/ui_warmup.gd")
const Main := preload("res://scripts/main.gd")
const Host := preload("res://tests/test_player_menu.gd").Host
const Memory := preload("res://scripts/file_mode_memory.gd")
var checks := 0
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var directory := ProjectSettings.globalize_path("res://../../build/output/settings-cache-ipd-test/%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var donor := Menu.new(); root.add_child(donor); donor.set_process(false); donor.visible = true
	var warmer := Warmup.new()
	for page in ["screen","playback","sync","queue","stereo","screen_immersive","bar"]: warmer.prepare(donor,page)
	var prepared_screen: Label3D = donor._settings_layouts.values().filter(func(entry):return entry.adjust_rows.has(450))[0].adjust_rows[450].label
	var state: Dictionary = Warmup.STATE.duplicate(true); state.source_uri = "file:///synthetic-test.mp4";state.screen_distance = 4.0
	var menu := Menu.new();root.add_child(menu);menu.set_process(false);menu.visible = true
	menu.state_provider = func():return state
	menu.adopt_prepared_layouts(donor)
	check(donor._settings_layouts.is_empty(),"Adoption transfers ownership without leaving dangling layouts")
	menu._activate(11)
	check(menu.settings_cache_hits==1 and menu._adjust_rows[450].label==prepared_screen,"First settings entry reuses the startup-prepared controls")
	check(menu._adjust_rows[450].label.text=="4.0 m" and not menu.choices.scope.contains("warmup://"),"Prepared controls refresh live values and interaction scope")
	var screen_label: Label3D = menu._adjust_rows[450].label
	menu._activate(menu.SYNC_SETTINGS)
	check(menu._adjustment=="sync" and menu.settings_cache_hits==2,"Synchronization tab is also prepared at startup")
	menu._activate(11)
	check(menu._adjust_rows[450].label==screen_label,"Repeated page switches retain node identity")
	state.screen_distance = 5.0; menu.refresh_values()
	check(menu._adjust_rows[450].label.text=="5.0 m","Cached slider tracks current values without a page rebuild")
	state.queue_items = []
	for index in 8: state.queue_items.append({"uri":"file:///synthetic-%d.mp4" % index,"title":"Synthetic %d" % index})
	menu._activate(menu.QUEUE_SETTINGS)
	var next: int = menu.queue_menu.actions.keys().filter(func(target):return menu.queue_menu.actions[target]=="page_next")[0]
	menu.queue_menu.action(next)
	check(menu.queue_menu.offset==4 and menu.queue_menu.actions.values().has("queue_play_4"),"Queue pagination advances with the correct actions")
	menu._activate(11);menu._activate(menu.QUEUE_SETTINGS)
	check(menu.queue_menu.offset==4 and menu.queue_menu.actions.values().has("queue_play_4"),"Cached queue restores the requested page and actions together")
	var previous: int = menu.queue_menu.actions.keys().filter(func(target):return menu.queue_menu.actions[target]=="page_previous")[0]
	menu.queue_menu.action(previous)
	check(menu.queue_menu.offset==0 and menu.queue_menu.actions.values().has("queue_play_0"),"Returning to cached queue page cannot revive another page's offset")
	menu._activate(menu.IPD_SETTINGS)
	check(menu._adjustment=="stereo_view" and menu._adjust_rows.has(menu.ALIGNMENT_HORIZONTAL),"Dedicated IPD tab exposes native-stereo horizontal compensation")
	check(menu._buttons.any(func(button):return button.target==menu.ALIGNMENT_RESET),"IPD corrections have a visible reset")
	state.stereo = false;menu.refresh_values()
	check(menu._adjustment=="stereo_view" and not menu._adjust_rows.has(menu.ALIGNMENT_HORIZONTAL),"Mono video shows an explanation instead of applying stereo offsets")
	state.stereo = true;state.geometry = 1;menu._activate(11)
	check(not menu._adjust_rows.has(450),"Immersive layout cannot reuse flat screen-distance controls")
	for index in 40:
		state.screen_curve = float(index)/100;menu.refresh()
	check(menu._settings_layouts.size()<=Menu.SETTINGS_CACHE_LIMIT,"Layout cache remains bounded across changed settings")
	menu.free(); donor.free(); warmer.free()
	var main := Main.new();main.settings_path = directory.path_join("settings.cfg")
	var settings := ConfigFile.new();settings.set_value("appearance","background","dark");settings.save(main.settings_path)
	root.add_child(main);main.set_process(false);main.report_timer.stop();main.menu_compositor.set_process(false);main.video.set_process(false);main.photo.set_process(false)
	var video: Node3D = main.video;var host := Host.new();video.platform = host;video.mode_memory = Memory.new(directory.path_join("modes"))
	video.recent_files = preload("res://scripts/recent_files.gd").new(directory.path_join("recent"))
	video.open_local("file:///synthetic180_SBS_180.mp4","synthetic180_SBS_180.mp4")
	video.stereo_sbs = true;video.geometry = 1;video.media.format = {"width":3840,"height":1920};video._apply_geometry()
	main._show_player_menu();main.player_menu._activate(main.player_menu.IPD_SETTINGS)
	var before := host.calls.size();var session: int = video.media.session_id
	main._on_playback_adjustment("stereo_horizontal",1.25);main._on_playback_adjustment("stereo_vertical",-.15)
	main._save_playback_adjustments()
	check(video.media.session_id==session and host.calls.size()==before,"IPD calibration never reopens decoder or inference")
	check(video.material.get_shader_parameter("stereo_offset").is_equal_approx(Vector2(.0125,-.0015)),"IPD controls reach the displayed per-eye coordinates")
	video.open_local("file:///other_SBS_180.mp4","other_SBS_180.mp4")
	check(video.stereo_horizontal==0 and video.stereo_vertical==0,"A different video never inherits another video's compensation")
	video.open_local("file:///synthetic180_SBS_180.mp4","synthetic180_SBS_180.mp4")
	check(is_equal_approx(video.stereo_horizontal,1.25) and is_equal_approx(video.stereo_vertical,-.15),"Reopening restores that video's IPD compensation")
	main._on_playback_adjustment("stereo_reset",true)
	check(video.stereo_horizontal==0 and video.stereo_vertical==0,"IPD reset restores neutral stereo")
	main.queue_free();await process_frame
	for failure in failures:push_error(failure)
	print("Settings cache and IPD: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
