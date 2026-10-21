extends RefCounted
## OwnFX (r121): the effects Dev's own studio made (assets/own/), used where the game had a gap.
## Robert, 2026-10-10: polish what we have first. The game already has hit sparks, flashes, damage numbers, a hurt
## vignette, torch flicker and elite auras, so this adds only what was missing:
##   OwnFX.dissolve(model)  a foe burns away from one side as it dies (the body still sinks after, as before)
##   OwnFX.sfx(name)        an optional second set of sound effects (Sound window: "Effects style")
## Both are off in the headless engine check and on "low" graphics, and each has a switch in the Sound window
## (own_fx: on/off, sfx_style: classic/own). Nothing in play depends on them.

const SHADER := "res://assets/own/shaders/own_dissolve.gdshader"
const SFX_DIR := "res://assets/own/sfx/"
const MAX_SURFACES := 40
## the game's sound names -> the studio's synthesized files (a name missing here keeps the game's own sound)
const SFX_MAP := {
	"hit_flesh": ["hit_flesh_a", "hit_flesh_b"],
	"hit_heavy": ["hit_metal"],
	"hit_metal": ["hit_metal"],
	"thud": ["death"],
	"swing": ["swing_a", "swing_b"],
	"hurt": ["hurt"],
	"door": ["door_open"],
	"chest": ["chest_open"],
	"coins": ["coin_pickup"],
	"pickup": ["coin_pickup"],
	"floor_clear": ["level_up"],
	"loot_epic": ["level_up"],
	"ui_click": ["ui_click"],
	"ui_select": ["ui_click"],
	"ui_ok": ["ui_click"],
	"crystal": ["qi_charge"],
	"parry": ["hit_metal"],
}
static var _shader: Shader
static var _own := {}


static func _setting(key: String, default: String) -> String:
	return str(preload("res://scripts/core/Gfx.gd").settings.get(key, default))


static func on(force: bool = false) -> bool:
	if force:
		return true
	if DisplayServer.get_name() == "headless":
		return false
	return _setting("own_fx", "on") != "off" and _setting("preset", "high") != "low"


static func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)


static func dissolve(model: Node, delay: float = 0.35, secs: float = 1.2, force: bool = false) -> bool:
	## burn the model away from one side; true when it started
	if model == null or not model.is_inside_tree() or not on(force):
		return false
	if _shader == null:
		_shader = load(SHADER) as Shader
	if _shader == null:
		return false
	var meshes := []
	_meshes(model, meshes)
	var mats := []
	for mi in meshes:
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			if mats.size() >= MAX_SURFACES:
				break
			var src: Material = m.get_active_material(i)
			var sm := ShaderMaterial.new()
			sm.shader = _shader
			var col := Color(0.55, 0.5, 0.45)
			if src is StandardMaterial3D:
				col = (src as StandardMaterial3D).albedo_color
				var tex := (src as StandardMaterial3D).albedo_texture
				if tex != null:
					sm.set_shader_parameter("albedo_tex", tex)
					sm.set_shader_parameter("use_tex", true)
			sm.set_shader_parameter("albedo", col)
			sm.set_shader_parameter("progress", 0.0)
			if m.material_override != null:
				m.material_override = sm          # (an override on the whole mesh hides per-surface ones)
				mats.append(sm)
				break
			m.set_surface_override_material(i, sm)
			mats.append(sm)
	if mats.is_empty():
		return false
	var tw := model.create_tween()
	tw.tween_interval(delay)
	tw.tween_method(func(v: float):
		for sm in mats:
			(sm as ShaderMaterial).set_shader_parameter("progress", v), 0.0, 1.0, secs)
	tw.tween_callback(func(): (model as Node3D).visible = false if model is Node3D else null)
	return true


static func sfx(name: String) -> AudioStream:
	## the studio's version of a game sound, or null (use the game's own)
	if _setting("sfx_style", "classic") != "own" or not SFX_MAP.has(name):
		return null
	var opts: Array = SFX_MAP[name]
	var f: String = opts[randi() % opts.size()]
	if not _own.has(f):
		var path := SFX_DIR + f + ".wav"
		_own[f] = load(path) if ResourceLoader.exists(path) else null
	return _own[f]
