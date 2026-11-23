extends Node
## Round 192: picture size that follows the graphics card.
## Robert, 2026-11-08: "its very laggy keep trying to improve quickness and snappy response". His perf_probe.txt:
## 2560x1440, every part of the frame waiting on the GPU, and half resolution alone halved it. So with Picture size
## on "auto" (the default), the 3D is drawn at fewer pixels while the GPU can't keep up -- down to 60% -- and goes
## back up as soon as there is room; the menus and text stay sharp at full size. Upscaled with FSR where the renderer
## has it. Only the GPU's own time counts: a slow frame that is the CPU's fault is not helped by fewer pixels.

const MIN_SCALE := 0.6
const MAX_SCALE := 1.0
const WINDOW := 1.5            # seconds averaged per decision
const UP_AFTER := 6.0          # this long comfortably under budget before going back up

var scale := 1.0
var _acc := 0.0
var _n := 0
var _gpu := 0.0
var _calm := 0.0
var _rid: RID
var changes := 0               # how many times it moved (crumbs, the check)
var test_gpu_ms := -1.0        # tools: pretend the GPU took this long


func _ready() -> void:
	_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_rid, true)
	scale = clampf(float(get_viewport().scaling_3d_scale), MIN_SCALE, MAX_SCALE)


static func on() -> bool:
	return str(preload("res://scripts/core/Gfx.gd").settings.get("scale", "auto")) == "auto"


func budget_ms() -> float:
	var cap := int(Engine.max_fps)
	if cap <= 0:
		cap = int(clampf(DisplayServer.screen_get_refresh_rate(), 30.0, 144.0)) if DisplayServer.get_name() != "headless" else 60
	return 1000.0 / float(maxi(cap, 30))


func _process(delta: float) -> void:
	if not on():
		return
	var g := test_gpu_ms if test_gpu_ms >= 0.0 else RenderingServer.viewport_get_measured_render_time_gpu(_rid)
	if g <= 0.0:
		return
	_gpu += g
	_n += 1
	_acc += delta
	if _acc < WINDOW:
		return
	var avg := _gpu / float(_n)
	_acc = 0.0
	_gpu = 0.0
	_n = 0
	var b := budget_ms()
	if avg > b * 1.15 and scale > MIN_SCALE + 0.001:
		# the GPU can't keep up: fewer pixels, in a step big enough to matter (cost goes with the square)
		_resize(maxf(MIN_SCALE, scale - (0.15 if avg > b * 2.0 else 0.08)))
		_calm = 0.0
	elif avg < b * 0.6 and scale < MAX_SCALE - 0.001:
		_calm += WINDOW
		if _calm >= UP_AFTER:
			_resize(minf(MAX_SCALE, scale + 0.05))
			_calm = 0.0
	else:
		_calm = 0.0


func _resize(v: float) -> void:
	scale = snappedf(v, 0.01)
	var vp := get_viewport()
	vp.scaling_3d_scale = scale
	changes += 1
	var ml = get_node_or_null("/root/MemLog")
	if ml != null and ml.has_method("crumb"):
		ml.crumb("auto picture size: %d%%" % int(round(scale * 100.0)))
