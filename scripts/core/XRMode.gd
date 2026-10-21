extends RefCounted
## VR on/off (round 135). Off by default: nothing here runs, and no VR runtime is ever started, unless the player turns VR on
## (pause menu > VR) AND an OpenXR headset is there. The flat game never changes.

const MODES := ["off", "on"]
const LABEL := {"off": "off", "on": "on (needs a headset)"}


static func mode() -> String:
	var m := str(preload("res://scripts/core/Gfx.gd").settings.get("vr", "off"))
	return m if MODES.has(m) else "off"


static func interface() -> XRInterface:
	return XRServer.find_interface("OpenXR")


static func available() -> bool:
	return interface() != null


static func launched_vr() -> bool:
	## PlayVR.bat starts the game with --vr (or Godot's own --xr-mode on): no menu needed, so a headset on your face can just go
	var a := OS.get_cmdline_args()
	if a.has("--vr"):
		return true
	var i := a.find("--xr-mode")
	return i >= 0 and i + 1 < a.size() and str(a[i + 1]) == "on"


static func wanted() -> bool:
	return (mode() == "on" or launched_vr()) and available()


static func start(player) -> Node:
	## turn the headset on and put the rig on the player. Returns the rig, or null (no headset / runtime refused).
	var xi := interface()
	if xi == null:
		return null
	if not xi.is_initialized() and not xi.initialize():
		push_warning("VR: the OpenXR runtime would not start (is the headset on and SteamVR/Oculus running?)")
		return null
	var vp: Viewport = player.get_viewport()
	vp.use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)      # the headset sets the pace
	Engine.max_fps = 0
	var rig = preload("res://scripts/actors/XRRig.gd").new()
	rig.name = "XRRig"
	player.add_child(rig)
	rig.setup(player)
	rig.head.cull_mask = rig.head.cull_mask & ~(1 << 19)       # your own body would fill the headset: leave it out (the layer Player hides in first person)
	if player.camera != null:
		player.camera.current = false
	return rig


static func next_mode(_tree: SceneTree) -> String:
	var G = preload("res://scripts/core/Gfx.gd")
	G.load_settings()
	var i := MODES.find(mode())
	G.settings["vr"] = MODES[(i + 1) % MODES.size()]
	G.save_settings()
	return str(G.settings["vr"])
