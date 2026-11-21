extends RefCounted
## Sample playback frame time in stable XR windows. Enable viewport timing only after a slow window.

const WINDOW_US := 10_000_000
const SLOW_FRACTION := 0.75

var _start_us := -1
var _last_us := -1
var _frames := 0
var _worst_us := 0
var _process_ms := 0.0
var _setup_ms := 0.0
var _render_cpu_ms := 0.0
var _render_gpu_ms := 0.0
var _measured := RID()
var _route := ""
var _output := Vector2i.ZERO
var _menu := false
var _refresh := 0.0
var _scope := 0


func stop() -> void:
	if _measured.is_valid():
		RenderingServer.viewport_set_measure_render_time(_measured, false)
		_measured = RID()
	_start_us = -1


func tick(
	viewport: Viewport,
	refresh: float,
	route: String,
	output: Vector2i,
	menu: bool,
	scope: int,
	now_us: int = Time.get_ticks_usec()
) -> Dictionary:
	var rid := viewport.get_viewport_rid()
	if (
		_start_us < 0
		or now_us - _last_us > 1_000_000
		or route != _route
		or output != _output
		or menu != _menu
		or not is_equal_approx(refresh, _refresh)
		or scope != _scope
	):
		stop()
		_route = route
		_output = output
		_menu = menu
		_refresh = refresh
		_scope = scope
		_begin(now_us)
		return {}
	_worst_us = maxi(_worst_us, now_us - _last_us)
	_last_us = now_us
	_frames += 1
	_process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_setup_ms += RenderingServer.get_frame_setup_time_cpu()
	if _measured.is_valid():
		_render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		_render_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var elapsed := now_us - _start_us
	if elapsed < WINDOW_US:
		return {}
	var fps := _frames * 1_000_000.0 / elapsed
	var result := {}
	if fps < refresh * SLOW_FRACTION:
		result = {
			"fps": snappedf(fps, 0.1),
			"refresh_hz": refresh,
			"mean_ms": snappedf(1000.0 / fps, 0.01),
			"worst_ms": _worst_us / 1000.0,
			"process_ms": snappedf(_process_ms / _frames, 0.01),
			"setup_ms": snappedf(_setup_ms / _frames, 0.01),
			"route": route,
			"output": [output.x, output.y],
			"menu_visible": menu
		}
		if _measured.is_valid():
			result["render_cpu_ms"] = snappedf(_render_cpu_ms / _frames, 0.01)
			result["render_gpu_ms"] = snappedf(_render_gpu_ms / _frames, 0.01)
		else:
			RenderingServer.viewport_set_measure_render_time(rid, true)
			_measured = rid
	elif _measured.is_valid():
		stop()
	_begin(now_us)
	return result


func _begin(now_us: int) -> void:
	_start_us = now_us
	_last_us = now_us
	_frames = 0
	_worst_us = 0
	_process_ms = 0.0
	_setup_ms = 0.0
	_render_cpu_ms = 0.0
	_render_gpu_ms = 0.0
