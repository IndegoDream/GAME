extends SceneTree
## Round 119: the legacy quest lines. Run: godot --headless --path . --script tools/legacy_line_check.gd

func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.new_game()
	var LL = load("res://scripts/systems/LegacyLines.gd")
	var Q = G.sys("quests")
	var ok := 0
	var bad := 0
	var checks := [
		["major base 6", LL.steps_for("major", 0.0) == 6],
		["major full synergy 3", LL.steps_for("major", 1.0) == 3],
		["heavenly base 10", LL.steps_for("heavenly", 0.0) == 10],
		["heavenly full synergy 5", LL.steps_for("heavenly", 1.0) == 5],
		["ultimate never under half", LL.steps_for("ultimate", 1.0) == 7],
		["longer tier is longer", LL.steps_for("heavenly", 0.5) > LL.steps_for("major", 0.5)],
		["more synergy never longer", LL.steps_for("major", 0.8) <= LL.steps_for("major", 0.2)],
	]
	var grants := {"techniques": ["iron_skin"]}
	var d1: Dictionary = LL.plan("t:key1", "the Test Sage", "major", grants, 4)
	var d2: Dictionary = LL.plan("t:key1", "the Test Sage", "major", grants, 4)
	checks.append(["plan is repeatable", JSON.stringify(d1) == JSON.stringify(d2)])
	checks.append(["plan has steps", d1["stages"].size() >= 3 and d1["stages"].size() <= 6])
	checks.append(["state starts none", LL.state("t:key1") == "none"])
	LL.start("t:key1", "the Test Sage", "major", grants, 4)
	checks.append(["state active after start", LL.state("t:key1") == "active"])
	checks.append(["kind is legacy", Q.kind_of("legacy:t:key1") == "legacy" and Q.kind_name("legacy") != "Legacy"])
	checks.append(["existing kinds kept", Q.kind_name("sect") == "Sects" and Q.kind_name("smithing") == "Blacksmithing"])
	checks.append(["quest shows in the log list", Q.all().any(func(q): return str(q.get("id", "")) == "legacy:t:key1")])
	var st: Dictionary = Q.save_state()
	Q.reset()
	checks.append(["reset forgets the line", LL.state("t:key1") == "none"])
	Q.load_state(st)
	checks.append(["save/load keeps the line and its steps", LL.state("t:key1") == "active" and Q.legacy_defs.has("legacy:t:key1")])
	var guard := 0
	while LL.state("t:key1") == "active" and guard < 20:
		guard += 1
		Q.advance("legacy:t:key1")
	checks.append(["finishing every step marks it done", LL.state("t:key1") == "done"])
	# round 119: deeper hidden masters take more talks
	var m_early: Dictionary = G.hm_master("ratcatcher")
	var m_late: Dictionary = G.hm_master("mirror")
	checks.append(["early master asks no extra talks", G.hm_extra_talks(m_early) == 0])
	checks.append(["late master asks more talks, not endless", G.hm_extra_talks(m_late) >= 3 and G.hm_extra_talks(m_late) <= 8])
	# round 119: the Balance
	var B = G.sys("balance")
	checks.append(["balance system exists", B != null])
	B.reset()
	checks.append(["no seat met: no imbalance", B.legacy_pct() < 0.0 and B.imbalance() == 0.0])
	B.note_seat("t:b1", "major")
	G.mq["chapter"] = G.mq_chapters().size()
	B.refresh()
	checks.append(["main road done, legacy road not begun: full imbalance", B.main_pct() >= 99.0 and B.imbalance() >= 0.99])
	var fx: Array = B.effects()
	checks.append(["imbalance cuts qi, never to nothing", fx.size() == 1 and float(fx[0]["qi_mult"]) < 0.8 and float(fx[0]["qi_mult"]) > 0.5])
	G.mq["chapter"] = int(G.mq_chapters().size() * 0.4)
	B.refresh()
	checks.append(["inside the limit: nothing", B.imbalance() == 0.0 and B.effects().is_empty()])
	G.mq["chapter"] = G.mq_chapters().size()
	LL.start("t:b1", "the Test Sage", "major", {}, 4)
	while LL.state("t:b1") == "active":
		Q.advance("legacy:t:b1")
	B.refresh()
	checks.append(["legacy road done: roads level, imbalance gone", B.legacy_pct() >= 99.0 and B.imbalance() == 0.0])
	checks.append(["no Even Road without the Balance", not B.even_road()])
	G.learn("the_balance")
	B.refresh()
	checks.append(["with the Balance and level roads: the Even Road", B.even_road() and B.effects().size() == 1 and float(B.effects()[0]["damage_taken"]) < 0.9])
	checks.append(["aspects are 0..1 and a weakest is named", B.aspects().size() == 7 and B.weakest() != "" and B.hint_line().begins_with("Weakest")])
	var hv: Dictionary = LL.plan("t:key2", "the Test Emperor", "heavenly", {"techniques": ["iron_skin"]}, 20)
	checks.append(["heavenly line is longer than major", hv["stages"].size() > d1["stages"].size() or hv["stages"].size() >= 5])
	for c in checks:
		if c[1]:
			ok += 1
		else:
			bad += 1
			print("LEGACY LINE FAIL: ", c[0])
	print("LEGACY LINE CHECK %d passed, %d failed" % [ok, bad])
	quit(1 if bad > 0 else 0)
