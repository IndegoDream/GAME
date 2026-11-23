extends RefCounted
## Graphics settings (Robert, 2026-10-02: "are we able to sharpen the
## graphics some" ... "as close to Morrowind or Skyrim in style").
##
## Four presets, picked in the pause menu and kept in user://settings.json
## (not in the save -- they belong to the machine, not the character):
##   low    -- the game as it was before this: Kenney models, no extras
##   medium -- anti-aliasing, sharp textures at an angle, photo-scanned
##             props (Art.gd), ambient occlusion, bloom on fire and crystal
##   high   -- + rough/AO detail on stone and earth, torch shadows near
##             you, volumetric fog underground, a real sky over Eliet
##   ultra  -- + global illumination (light bounces off walls), bigger
##             and softer shadows, temporal anti-aliasing
## Also here: window mode (fullscreen / windowed) and the camera
## (third person far, over the shoulder, first person -- C cycles).

const Art := preload("res://scripts/core/Art.gd")
const Look := preload("res://scripts/world/Look.gd")
const PATH := "user://settings.json"
const PRESET_ORDER := ["low", "medium", "high", "ultra"]
const PRESETS := {
	"low":    {"art": "kenney", "detail": false, "msaa": 0, "fxaa": false, "taa": false, "aniso": 1, "ssao": false, "ssil": false,
		"glow": false, "vfog": false, "sdfgi": false, "sky": false, "shadow": 2048, "pshadow": 2048, "soft": 1, "torch_shadow": 0.0, "grade": false},
	"medium": {"art": "realistic", "detail": false, "msaa": 2, "fxaa": false, "taa": false, "aniso": 3, "ssao": true, "ssil": false,
		"glow": true, "vfog": false, "sdfgi": false, "sky": false, "shadow": 2048, "pshadow": 2048, "soft": 2, "torch_shadow": 0.0, "grade": true},
	"high":   {"art": "realistic", "detail": true, "msaa": 4, "fxaa": false, "taa": false, "aniso": 4, "ssao": true, "ssil": true,
		"glow": true, "vfog": true, "sdfgi": false, "sky": true, "shadow": 4096, "pshadow": 4096, "soft": 3, "torch_shadow": 13.0, "grade": true},
	"ultra":  {"art": "realistic", "detail": true, "msaa": 4, "fxaa": false, "taa": true, "aniso": 4, "ssao": true, "ssil": true,
		"glow": true, "vfog": true, "sdfgi": true, "sky": true, "shadow": 8192, "pshadow": 8192, "soft": 4, "torch_shadow": 20.0, "grade": true},
}
const LABEL := {"low": "Low (the original look)", "medium": "Medium", "high": "High", "ultra": "Ultra"}
const CAMERAS := ["far", "shoulder", "first"]
const CAMERA_LABEL := {"far": "third person", "shoulder": "over the shoulder", "first": "first person"}
const SKY_DAY := "res://assets/sky/kloofendal_28d_misty.hdr"
const SKY_EVENING := "res://assets/sky/evening_meadow.hdr"

static var settings := {"preset": "high", "window": "fullscreen", "camera": "far", "zoom_far": "9.0", "zoom_sh": "3.0", "zoom_fov": "75.0", "touch": "auto", "vr": "off", "steam": "off", "music": 6, "sfx": 8, "fog": "on", "ambience": 7, "music_often": "sometimes", "fight_music": "on", "music_style": "subtle", "music_v": "1", "amb_style": "new", "world_sounds": "on", "room_echo": "on", "greetings": "on", "store_test": "off", "preset_user": "no", "custom": {}, "effects": "high", "scale": "auto", "fps": "auto", "world": "auto", "cloud_when": "saves", "a_text": "1.0", "a_cb": "off", "a_toggle": "off", "a_caps": "off", "a_motion": "full", "a_hand": "right", "a_big": "off", "art_pack": "new", "gpu_ai": "free", "res_v": "1"}


static func step_volume(which: String, tree: SceneTree) -> int:
	## round 31: music / sounds, 0-10, round the dial
	load_settings()
	var v := (int(settings.get(which, 6)) + 2) % 12
	settings[which] = v
	save_settings()
	var g = tree.root.get_node_or_null("Game")
	if g and g.audio:
		g.audio.apply_volumes()
		if which == "sfx":
			g.audio.play("ui_ok", 0.8)
	return v
# round 59: sound -- how often music plays, fights' drums, the old loops
const MUSIC_OFTEN := ["often", "sometimes", "rarely"]
const MUSIC_OFTEN_LABEL := {"often": "often", "sometimes": "now and then", "rarely": "rarely"}


static func next_sound_option(which: String, tree: SceneTree) -> String:
	load_settings()
	var opts: Array = {"music_often": MUSIC_OFTEN, "fight_music": ["on", "off"], "gpu_ai": ["free", "leave"], "music_style": ["subtle", "new", "original", "classic"], "amb_style": ["new", "classic"], "sfx_style": ["classic", "own"]}.get(which, ["on", "off"])
	var i := opts.find(str(settings.get(which, opts[0])))
	settings[which] = opts[(i + 1) % opts.size()]
	save_settings()
	var g = tree.root.get_node_or_null("Game") if tree else null
	if g and g.audio and which == "music_style":
		g.audio.restart_music()
	if g and g.audio and which == "amb_style" and g.audio.has_method("set_ambience"):
		var cur: String = g.audio.ambience
		g.audio.ambience = ""
		g.audio.set_ambience(cur)                 # the new bed straight away
	return str(settings[which])


const TOUCH_MODES := ["auto", "on", "off"]
const TOUCH_LABEL := {"auto": "when there's a touch screen", "on": "on", "off": "off"}


static func lite_art() -> bool:
	## the phone export leaves out the photo-scanned art (export feature tag "lite_art"): the light look is the only look there
	return OS.has_feature("lite_art")


static func small_device() -> bool:
	## Browsers also use the lightweight package and Compatibility renderer.
	return OS.has_feature("web") or OS.has_feature("mobile") or OS.has_feature("android")


static func enforce_device_limits(lightweight: bool) -> void:
	# Never trust restored PC settings or custom overrides on a phone.
	if lightweight:
		settings["preset"] = "low"
		settings["custom"] = {}
		settings["effects"] = "low"
		if str(settings.get("fps", "auto")) not in ["30", "60"]:
			settings["fps"] = "60"


static func effects_level() -> String:
	load_settings()
	if small_device() or preset() == "low":
		return "low"
	return str(settings.get("effects", "high"))


static func next_effects() -> String:
	load_settings()
	var levels := ["low", "medium", "high"]
	settings["effects"] = levels[(levels.find(str(settings.get("effects", "high"))) + 1) % levels.size()]
	save_settings()
	return effects_level()


static var _loaded := false

const WORLD_MODES := ["auto", "lite", "full"]
const WORLD_LABEL := {"auto": "Full world on every device", "lite": "Lite (the village and the dungeon)", "full": "Full (the valley, towers and the tech frontier too)"}


const CLOUD_WHEN := ["saves", "floor", "manual"]
const CLOUD_WHEN_LABEL := {"saves": "a little after every save", "floor": "at the start of each dungeon floor (and back in the village)", "manual": "only when I press Sync now"}


static func next_cloud_when() -> String:
	var i := CLOUD_WHEN.find(str(settings.get("cloud_when", "saves")))
	settings["cloud_when"] = CLOUD_WHEN[(i + 1) % CLOUD_WHEN.size()]
	save_settings()
	return str(settings["cloud_when"])


static func world_lite() -> bool:
	# Reduced content is opt-in, never a consequence of phone graphics.
	return str(settings.get("world", "auto")) == "lite"


## 2026-11-06 (Robert: "Yes, CC0 only" -- swap in free art, keep the old look as the backup):
## "new" = the CC0 art packs (built houses, photo skies, land grounds, props, animals);
## "previous" = exactly the look before them. Low graphics and phones keep the original either way.
const ART_PACKS := ["new", "previous"]
const ART_PACK_LABEL := {"new": "new art packs", "previous": "the previous look"}


static func art_pack() -> String:
	load_settings()
	var v := str(settings.get("art_pack", "new"))
	return v if v in ART_PACKS else "new"


static func next_art_pack(tree: SceneTree = null) -> String:
	load_settings()
	settings["art_pack"] = ART_PACKS[(ART_PACKS.find(art_pack()) + 1) % ART_PACKS.size()]
	save_settings()
	return str(settings["art_pack"])


static func next_world(tree: SceneTree = null) -> String:
	var i := WORLD_MODES.find(str(settings.get("world", "auto")))
	settings["world"] = WORLD_MODES[(i + 1) % WORLD_MODES.size()]
	save_settings()
	return str(settings["world"])


static func load_settings() -> Dictionary:
	if _loaded:
		enforce_device_limits(small_device())
		return settings
	_loaded = true
	if small_device():
		settings["preset"] = "low"
		settings["window"] = "windowed"
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			for k in settings:
				if d.has(k):
					if k == "custom":
						settings[k] = d[k] if d[k] is Dictionary else {}
					else:
						settings[k] = int(d[k]) if k in ["music", "sfx", "ambience"] else str(d[k])
	if str(settings.get("res_v", "1")) != "2":
		# round 192 (Robert: "very laggy ... quickness and snappy response"): 100% was the old default, not a choice --
		# everyone on it moves to auto picture size once; any other size someone picked stays
		if str(settings.get("scale", "1.0")) == "1.0":
			settings["scale"] = "auto"
		settings["res_v"] = "2"
	if str(settings.get("music_v", "1")) != "2":
		# round 183c (Robert: "make the music more refined and subtle"): everyone moves to the refined pieces once;
		# the fuller ones stay in Sound > Music style
		settings["music_style"] = "subtle"
		settings["music_v"] = "2"
	if not PRESETS.has(settings["preset"]):
		settings["preset"] = "high"
	if not (settings["camera"] in CAMERAS):
		settings["camera"] = "far"
	if not (settings["cloud_when"] in CLOUD_WHEN):
		settings["cloud_when"] = "saves"
	if not (settings["world"] in WORLD_MODES):
		settings["world"] = "auto"
	if not (settings["touch"] in TOUCH_MODES):
		settings["touch"] = "auto"
	if not (str(settings.get("vr", "off")) in ["off", "on"]):
		settings["vr"] = "off"
	if str(settings.get("effects", "high")) not in ["low", "medium", "high"]:
		settings["effects"] = "high"
	enforce_device_limits(small_device())
	_sync_static()
	return settings


static func save_settings() -> void:
	enforce_device_limits(small_device())
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings, "  "))


static func p() -> Dictionary:
	## the preset, with whatever the player fine-tuned laid over it (round 123)
	if lite_art():
		return PRESETS["low"]
	var base: Dictionary = PRESETS[str(load_settings()["preset"])]
	var c = settings.get("custom", {})
	if not (c is Dictionary) or c.is_empty():
		return base
	var out: Dictionary = base.duplicate()
	for k in c:
		if out.has(k) and typeof(c[k]) == typeof(out[k]):
			out[k] = c[k]
		elif out.has(k) and typeof(out[k]) == TYPE_INT and typeof(c[k]) == TYPE_FLOAT:
			out[k] = int(c[k])           # (JSON turns every number into a float)
		elif out.has(k) and typeof(out[k]) == TYPE_FLOAT and typeof(c[k]) == TYPE_INT:
			out[k] = float(c[k])
	return out


static func preset() -> String:
	if lite_art():
		return "low"
	return str(load_settings()["preset"])


static func _sync_static() -> void:
	var pr: Dictionary = p()
	Art.style = str(pr["art"])
	Art.full_detail = preset() == "ultra"           # round 186: the full photo scans only on Ultra
	Look.detail = bool(pr["detail"])
	Look.natural = str(pr["art"]) == "realistic"


static func set_preset(name: String, tree: SceneTree) -> void:
	if not PRESETS.has(name):
		return
	load_settings()
	settings["preset"] = name
	settings["custom"] = {}                 # picking a preset starts from its own settings again
	settings["preset_user"] = "yes"
	_sync_static()
	save_settings()
	apply(tree)


static func next_preset(tree: SceneTree) -> String:
	var i := PRESET_ORDER.find(preset())
	var n: String = PRESET_ORDER[(i + 1) % PRESET_ORDER.size()]
	set_preset(n, tree)
	return preset()


# ---- round 123: fine-tune -- each effect on its own, over the chosen preset ------------------
## [key, label, [values], how to say a value]. Taps step through the values.
const TUNE := [
	["art", "Models and textures", ["kenney", "realistic"], {"kenney": "simple (light)", "realistic": "detailed"}],
	["msaa", "Edge smoothing", [0, 2, 4], {0: "off", 2: "2x", 4: "4x"}],
	["aniso", "Texture sharpness at an angle", [1, 3, 4], {1: "off", 3: "medium", 4: "full"}],
	["shadow", "Sun shadow detail", [1024, 2048, 4096, 8192], {1024: "very low", 2048: "low", 4096: "high", 8192: "ultra"}],
	["pshadow", "Light shadow detail", [1024, 2048, 4096, 8192], {1024: "very low", 2048: "low", 4096: "high", 8192: "ultra"}],
	["soft", "Shadow softness", [1, 2, 3, 4], {1: "hard", 2: "soft", 3: "softer", 4: "softest"}],
	["torch_shadow", "Torch shadows near you", [0.0, 13.0, 20.0], {0.0: "off", 13.0: "near", 20.0: "far"}],
	["ssao", "Corner shading", [false, true], {false: "off", true: "on"}],
	["ssil", "Light bounce on nearby walls", [false, true], {false: "off", true: "on"}],
	["glow", "Glow on fire and crystal", [false, true], {false: "off", true: "on"}],
	["vfog", "Fog you can see light in", [false, true], {false: "off", true: "on"}],
	["sdfgi", "Full light bounce (heavy)", [false, true], {false: "off", true: "on"}],
	["sky", "Photographed sky", [false, true], {false: "off", true: "on"}],
	["detail", "Rough stone and earth detail", [false, true], {false: "off", true: "on"}],
	["grade", "Colour grade", [false, true], {false: "off", true: "on"}],
	["taa", "Temporal smoothing", [false, true], {false: "off", true: "on"}],
]
const SCALES := ["0.5", "0.67", "0.75", "0.85", "1.0", "auto"]          # round 192: auto follows the GPU (AutoRes.gd)
const FPS_CAPS := ["auto", "30", "60", "120"]


static func tune_text(row: Array) -> String:
	var v = p()[row[0]]
	var say: Dictionary = row[3]
	return "%s: %s%s" % [row[1], str(say.get(v, v)), "  *" if (settings.get("custom", {}) as Dictionary).has(row[0]) else ""]


static func tune_step(key: String, tree: SceneTree) -> void:
	for row in TUNE:
		if row[0] != key:
			continue
		var vals: Array = row[2]
		var i := vals.find(p()[key])
		var nv = vals[(i + 1) % vals.size()]
		load_settings()
		var c: Dictionary = settings.get("custom", {})
		if nv == PRESETS[str(settings["preset"])][key]:
			c.erase(key)                  # back to the preset's own value
		else:
			c[key] = nv
		settings["custom"] = c
		settings["preset_user"] = "yes"
		_sync_static()
		save_settings()
		apply(tree)
		return


static func tune_reset(tree: SceneTree) -> void:
	load_settings()
	settings["custom"] = {}
	settings["scale"] = "auto"
	settings["fps"] = "auto"
	_sync_static()
	save_settings()
	apply(tree)


static func next_scale(tree: SceneTree) -> String:
	load_settings()
	var i := SCALES.find(str(settings.get("scale", "auto")))
	settings["scale"] = SCALES[(i + 1) % SCALES.size()]
	settings["preset_user"] = "yes"
	save_settings()
	apply(tree)
	return str(settings["scale"])


static func next_fps(tree: SceneTree) -> String:
	load_settings()
	var caps: Array = ["30", "60"] if small_device() else FPS_CAPS
	var i := caps.find(str(settings.get("fps", "auto")))
	settings["fps"] = caps[(i + 1) % caps.size()]
	save_settings()
	apply(tree)
	return str(settings["fps"])


static func set_window(mode: String, tree: SceneTree) -> void:
	load_settings()
	settings["window"] = mode
	save_settings()
	apply(tree)


static func next_touch(tree: SceneTree) -> String:
	load_settings()
	var i := TOUCH_MODES.find(str(settings["touch"]))
	settings["touch"] = TOUCH_MODES[(i + 1) % TOUCH_MODES.size()]
	save_settings()
	preload("res://scripts/ui/TouchUI.gd").sync(tree)
	return str(settings["touch"])


static func next_fog(tree: SceneTree) -> String:
	## round 35: fog of war on or off (it takes effect on the next floor you enter)
	load_settings()
	settings["fog"] = "off" if str(settings.get("fog", "on")) == "on" else "on"
	save_settings()
	if settings["fog"] == "off":
		for f in tree.get_nodes_in_group("fog_of_war"):
			f.queue_free()
		for n in tree.get_nodes_in_group("enemy") + tree.get_nodes_in_group("interactable"):
			if n.has_meta("fog_hidden"):
				n.remove_meta("fog_hidden")
				n.visible = true
	return str(settings["fog"])


static func next_steam(tree: SceneTree) -> String:
	## round 30: Steam for testing on this PC (a Steam export has it on anyway)
	load_settings()
	settings["steam"] = "off" if str(settings.get("steam", "off")) == "on" else "on"
	save_settings()
	var g = tree.root.get_node_or_null("Game")
	if g and g.steam:
		if settings["steam"] == "on":
			g.steam.start()
		else:
			g.steam.stop()
	return str(settings["steam"])


static func next_camera() -> String:
	load_settings()
	var i := CAMERAS.find(str(settings["camera"]))
	settings["camera"] = CAMERAS[(i + 1) % CAMERAS.size()]
	save_settings()
	return str(settings["camera"])


static func apply(tree: SceneTree) -> void:
	## The renderer side: anti-aliasing, texture filtering, shadows, window.
	var pr := p()
	var vp := tree.root
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][[0, 2, 4, 8].find(int(pr["msaa"]))]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if bool(pr["fxaa"]) else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = bool(pr["taa"])
	if "anisotropic_filtering_level" in vp:
		vp.anisotropic_filtering_level = int(pr["aniso"])
	var sc_s := str(settings.get("scale", "auto"))
	if "scaling_3d_scale" in vp:
		if sc_s == "auto":
			# round 192: AutoRes.gd moves it as the GPU allows; start from where it was (or full size)
			var ar = tree.root.find_child("AutoRes", true, false)
			vp.scaling_3d_scale = float(ar.scale) if ar != null else 1.0
		else:
			vp.scaling_3d_scale = clampf(float(sc_s), 0.4, 1.0)          # render resolution (round 123): a phone can draw fewer pixels and still look sharp UI-wise
		if "scaling_3d_mode" in vp:
			var fwd := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus")) == "forward_plus" and DisplayServer.get_name() != "headless"
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if fwd and vp.scaling_3d_scale < 0.999 or (fwd and sc_s == "auto") else Viewport.SCALING_3D_MODE_BILINEAR
	Engine.max_fps = 0 if str(settings.get("fps", "auto")) == "auto" else int(str(settings.get("fps", "0")))
	vp.positional_shadow_atlas_size = int(pr["pshadow"])
	RenderingServer.directional_shadow_atlas_set_size(int(pr["shadow"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(pr["soft"]))
	RenderingServer.positional_soft_shadow_filter_set_quality(int(pr["soft"]))
	if DisplayServer.get_name() != "headless" and not (OS.has_feature("web") and str(settings["window"]) != "fullscreen"):
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if str(settings["window"]) == "fullscreen" else DisplayServer.WINDOW_MODE_MAXIMIZED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
	fit_small_window(tree)
	var lvl = tree.root.find_child("Level", true, false)
	if lvl and "_env" in lvl and lvl._env:
		tune_env(lvl._env, str(lvl.theme) if "theme" in lvl else "dungeon")


static func fit_small_window(tree: SceneTree) -> void:
	## round 174: the menus are laid out for about 1067 x 640. A smaller window (a PC window dragged small,
	## a small screen) scales the whole interface down so every menu still shows; a big one is left alone.
	## (A touch device already scales in TouchUI.fit_screen.)
	if DisplayServer.get_name() == "headless":
		return
	var w := tree.root
	if not w.has_meta("fit_small_hooked"):
		w.set_meta("fit_small_hooked", true)
		w.size_changed.connect(func(): fit_small_window(tree))
	if preload("res://scripts/ui/TouchUI.gd").wanted():
		return
	var ws := DisplayServer.window_get_size()
	var small: bool = ws.x < 1100 or ws.y < 740      # 2026-10-31: was 1100 x 640 -- a normal window with a title bar fell just under the menus' height
	var want_mode := Window.CONTENT_SCALE_MODE_CANVAS_ITEMS if small else Window.CONTENT_SCALE_MODE_DISABLED
	w.content_scale_size = Vector2i(1067, 640)
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if w.content_scale_mode != want_mode:
		w.content_scale_mode = want_mode
		w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		w.content_scale_size = Vector2i(1067, 640)


static func tune_env(env: Environment, theme: String) -> void:
	## The scene side: occlusion, bloom, fog you can see light in, bounce
	## light, and a colour grade that leans toward the cool, earthy look of
	## the old Elder Scrolls games. Low leaves the environment as built.
	var pr := p()
	var LK: Dictionary = preload("res://scripts/fx/FX.gd").feel("look")      # round 52: more contrast (data/feel.json)
	env.ssao_enabled = bool(pr["ssao"])
	env.ssao_radius = 1.6
	env.ssao_intensity = float(LK.get("ssao_intensity", 1.8))
	env.ssil_enabled = bool(pr["ssil"])
	env.glow_enabled = bool(pr["glow"])
	if env.glow_enabled:
		env.glow_intensity = float(LK.get("glow", 0.7))
		env.glow_bloom = float(LK.get("bloom", 0.08))
		env.glow_hdr_threshold = 1.1
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	var underground := theme != "village"
	env.volumetric_fog_enabled = bool(pr["vfog"]) and underground
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = 0.009
		env.volumetric_fog_albedo = Color(0.85, 0.85, 0.9)
		env.volumetric_fog_emission = Color(0, 0, 0)
		env.volumetric_fog_anisotropy = 0.4
		env.volumetric_fog_length = 48.0
	env.sdfgi_enabled = bool(pr["sdfgi"])
	if env.sdfgi_enabled:
		env.sdfgi_use_occlusion = true
		env.sdfgi_energy = 0.9
	env.adjustment_enabled = bool(pr["grade"])
	if env.adjustment_enabled:
		env.adjustment_contrast = float(LK.get("contrast", 1.07))
		env.adjustment_saturation = float(LK.get("saturation_under", 0.9)) if underground else float(LK.get("saturation_sky", 0.95))
		env.adjustment_brightness = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX if bool(pr["grade"]) else Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0


static func day_sky(dl: float) -> Sky:
	## A real (photographed) misty sky over Eliet by day, at High and up.
	## null when it isn't wanted or isn't there -- the drawn sky stays.
	var path := SKY_DAY if dl >= 0.7 else SKY_EVENING      # (a low gold sun: the evening sky)
	if not bool(p()["sky"]) or dl < 0.35 or not ResourceLoader.exists(path):
		return null
	var tex = load(path)
	if tex == null:
		return null
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = tex
	mat.energy_multiplier = 0.45 + 0.75 * dl
	var sky := Sky.new()
	sky.sky_material = mat
	return sky


static func torch_shadow_radius() -> float:
	return float(p()["torch_shadow"])
