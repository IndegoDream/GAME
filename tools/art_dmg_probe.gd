extends SceneTree
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_path = "user://probe_save.json"; G.save_base = "user://probe_slots"; G.playlog_path = "user://probe_playlog.jsonl"
	load("res://Main.gd").force_veil = true
	var m = load("res://Main.tscn").instantiate(); root.add_child(m)
	for i in 6: await process_frame
	G.go_to("floor1", "<")
	for i in 30: await process_frame
	var p = m.player
	for aid in G.lattice_data().get("arts", {}).keys(): G.learn(str(aid), "probe")
	for pt in G.lattice_data().get("points", []): G.open_point(str(pt.get("id", "")))
	G.realm = G.REALMS.size() - 1
	for aid in G.arts.keys(): G.set_flag("ax:%s:sect" % aid, true)
	var targets := ["severing_finger", "collapsing_palm", "qi_burst", "rending_claw", "shatterpoint", "tidebreaker", "sect_iron_fist_clan_strike", "heron_lance", "leaf_sweep", "ironstorm_chain", "crimson_bloom", "quake_fist", "thunder_leap"]
	var es = root.get_tree().get_nodes_in_group("enemy")
	print("enemies ", es.size())
	for aid in targets:
		if not G.arts.has(aid): print("ART MISSING ", aid); continue
		var e = es[0]
		e.hp = 99999
		p.global_position = e.global_position + Vector3(0, 0, -1.3)
		p._model.rotation.y = 0.0
		p.velocity = Vector3.ZERO
		G.qi = G.qi_to_next() + 999.0; G.hp = G.max_hp()
		var msgs := []
		var cb = func(t): msgs.append(str(t))
		G.message.connect(cb)
		var r = p.cast_art(aid, Vector3(0, 0, 1))
		var trail := []
		for k in 12:
			for i in 8: await process_frame
			trail.append(99999 - e.hp)
		G.message.disconnect(cb)
		print("ART %s fam=%s cast=%s dmg_trail=%s msg=%s dist=%.1f" % [aid, G.art_family(aid), r, trail, " / ".join(msgs).left(60), p.global_position.distance_to(e.global_position)])
	quit()
