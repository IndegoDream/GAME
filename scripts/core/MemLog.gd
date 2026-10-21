extends Node
# Writes a small run log every 5 s; if the last run did not end cleanly, shows where/when/how much memory.
const PATH := "user://memlog.json"
var t0 := 0.0
var acc := 0.0
var safe_start := false          # round 169: the last run died in its first minute -> this one starts gently (no background model reading)
const CRUMBS := "user://crumbs.txt"


func crumb(msg: String) -> void:
	## one line, written and closed at once so a crash cannot take it (read it back with the game closed)
	var f := FileAccess.open(CRUMBS, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(CRUMBS, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%.2f %s" % [Time.get_ticks_msec() / 1000.0 - t0, msg])
	f.close()
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = true
	t0 = Time.get_ticks_msec() / 1000.0
	var prev = _read()
	if prev is Dictionary and not prev.get("clean", true) and float(prev.get("min", 0.0)) < 1.0:
		safe_start = true
	var cf := FileAccess.open(CRUMBS, FileAccess.WRITE)           # a fresh page for this run
	if cf != null:
		cf.store_line("run start; safe_start=%s; prev=%s" % [str(safe_start), JSON.stringify(prev)])
		cf.close()
	_write(false)
	if prev is Dictionary and not prev.get("clean", true) and float(prev.get("min", 0.0)) >= 0.5:
		call_deferred("_show_prev", prev)
func _read():
	if not FileAccess.file_exists(PATH): return null
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null: return null
	var d = JSON.parse_string(f.get_as_text())
	return d
func _write(clean: bool) -> void:
	var cs = get_tree().current_scene if is_inside_tree() else null
	var d := {
		"clean": clean,
		"min": snappedf((Time.get_ticks_msec() / 1000.0 - t0) / 60.0, 0.1),
		"static_mb": int(OS.get_static_memory_usage() / 1048576.0),
		"peak_mb": int(OS.get_static_memory_peak_usage() / 1048576.0),
		"tex_mb": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0),
		"vid_mb": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		"fps": int(Performance.get_monitor(Performance.TIME_FPS)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"scene": (cs.name if cs else "?"),
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(d))
func _process(dt: float) -> void:
	acc += dt
	if acc >= 5.0:
		acc = 0.0
		_write(false)
func _notification(what: int) -> void:
	if not is_inside_tree(): return
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_write(true)
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_write(true)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_write(false)
func _show_prev(p: Dictionary) -> void:
	var cl := CanvasLayer.new(); cl.layer = 128
	var l := Label.new()
	l.text = "Last run ended unexpectedly after %s min  |  mem %s MB (peak %s)  textures %s MB  video %s MB  fps %s  nodes %s  in %s" % [p.get("min"), p.get("static_mb"), p.get("peak_mb"), p.get("tex_mb"), p.get("vid_mb"), p.get("fps"), p.get("nodes"), p.get("scene")]
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(900, 0)
	l.position = Vector2(20, 20)
	cl.add_child(l); add_child(cl)
	get_tree().create_timer(25.0).timeout.connect(cl.queue_free)
