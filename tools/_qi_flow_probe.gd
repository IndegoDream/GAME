extends SceneTree
## Load a real save (a copy) and print every qi drain and gain, per minute.
##   godot --headless --path . --script res://tools/_qi_flow_probe.gd -- /abs/path/save.json
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_path = OS.get_cmdline_user_args()[0]
	G.save_base = "user://qi_probe_slots"
	print("loaded: ", G.load_game())
	var CN = G.sys("constructs")
	var SY = G.sys("synergy")
	print("realm ", G.realm, " sub ", G.sublevel, " qi ", G.qi, " to_next ", G.qi_to_next())
	print("mech_on ", CN.mech_on, " drain/min ", CN.mech_drain_per_min(), " frac ", CN.mech_drain_frac())
	print("synergy upkeep/min ", SY.upkeep_per_minute(), " points ", G.sys("research").upkeep_points())
	print("equipment ", G.equipment, " weapon ", G.weapon)
	var t0: float = G.qi
	# simulate 60 s standing still, not sitting
	for i in 60:
		G.sys("constructs").tick(1.0)
		G.sys("synergy").tick(1.0)
	print("60 s standing: qi change ", G.qi - t0)
	print("take everything off: ", G.unequip_all())
	var t1: float = G.qi
	for i in 60:
		G.sys("constructs").tick(1.0)
		G.sys("synergy").tick(1.0)
	print("after, 60 s standing: qi change ", G.qi - t1, "  frame on: ", CN.mech_on)
	quit()
