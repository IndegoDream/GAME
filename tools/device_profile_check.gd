extends SceneTree
# Device policy regression, independent of the host OS and isolated by the runner.
var failed := 0
var passed := 0

func _initialize() -> void:
	call_deferred("run")

func check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("  FAIL ", label)

func run() -> void:
	await process_frame
	var gfx = load("res://scripts/core/Gfx.gd")
	var fx = load("res://scripts/fx/FX.gd")
	gfx.load_settings()
	var saved: Dictionary = gfx.settings.duplicate(true)
	for bad in ["high", "ultra", "invalid"]:
		gfx.settings["preset"] = bad
		gfx.settings["preset_user"] = "yes"
		gfx.settings["custom"] = {"art": "realistic", "ssao": true, "msaa": 4, "shadow": 8192}
		gfx.settings["effects"] = "high"
		gfx.settings["fps"] = "120"
		gfx.enforce_device_limits(true)
		gfx._sync_static()
		check(bad + " becomes low", gfx.preset() == "low")
		check(bad + " discards expensive overrides", gfx.settings["custom"].is_empty())
		check(bad + " uses Kenney", gfx.Art.style == "kenney")
		check(bad + " caps frame rate", gfx.settings["fps"] == "60")
		check(bad + " effects low", gfx.effects_level() == "low" and not fx._rich())
		var pr: Dictionary = gfx.p()
		for feature in ["ssao", "ssil", "sdfgi", "vfog", "glow", "taa", "sky", "detail"]:
			check(bad + " disables " + feature, not pr[feature])
		check(bad + " mobile shadows and AA", pr["shadow"] == 2048 and pr["msaa"] == 0)
	gfx.settings["fps"] = "30"
	gfx.enforce_device_limits(true)
	check("battery cap preserved", gfx.settings["fps"] == "30")
	gfx.settings["preset"] = "high"
	gfx.enforce_device_limits(false)
	check("PC high retained", gfx.preset() == "high")
	var env := Environment.new()
	gfx.tune_env(env, "dungeon")
	check("PC high enables bloom", env.glow_enabled)
	gfx.settings["preset"] = "low"
	gfx.tune_env(env, "dungeon")
	check("downgrade disables bloom", not env.glow_enabled)
	check("downgrade disables GI/fog", not env.ssao_enabled and not env.ssil_enabled and not env.sdfgi_enabled and not env.volumetric_fog_enabled)
	check("downgrade restores filmic", env.tonemap_mode == Environment.TONE_MAPPER_FILMIC)
	gfx.settings["world"] = "auto"
	gfx.enforce_device_limits(true)
	check("phone auto has full world", not gfx.world_lite())
	var game = root.get_node("Game")
	check("phone auto valley available", not game.lite_blocked("valley"))
	check("phone auto frontier available", not game.lite_blocked("frontier:crash_site"))
	gfx.settings["world"] = "lite"
	check("explicit lite preference retained", gfx.world_lite())
	gfx.settings["preset"] = "high"
	for effect in ["low", "medium", "high"]:
		gfx.settings["effects"] = effect
		check(effect + " independent effects", gfx.effects_level() == effect)
		check(effect + " rich effects guard", fx._rich() == (effect == "high"))
	var cfg := ConfigFile.new()
	check("export config reads", cfg.load("res://export_presets.cfg") == OK)
	for index in [0, 2, 4]:
		var filter: String = cfg.get_value("preset.%d" % index, "exclude_filter", "")
		for folder in (["realistic", "polyhaven", "characters", "sky"] if index == 0 else ["realistic", "polyhaven", "sky"]):      # (Robert: the phone keeps its people and monsters)
			check("light package %d excludes %s" % [index, folder], filter.contains("assets/" + folder + "/*"))
	gfx.settings = saved
	gfx._sync_static()
	print("DEVICE PROFILE CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
