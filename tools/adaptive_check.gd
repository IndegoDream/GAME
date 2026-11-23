extends SceneTree
## Round 136: adaptive foes. Run: godot --headless --path . --script tools/adaptive_check.gd
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.new_game()
	var ch := []
	var n := 10
	# the expected cultivator for floor 10: base strength, no ramp
	G.realm = int(3 * n / 10)
	G.sublevel = ((3 * n) % 10) + 1
	var r0: float = G.adaptive_ramp(n)
	ch.append(["expected player: ramp ~0 (%.3f)" % r0, r0 < 0.02])
	# well under: never negative
	G.realm = 0
	G.sublevel = 1
	ch.append(["weak player: ramp 0", G.adaptive_ramp(n) == 0.0])
	# far ahead: capped at +25%
	G.realm = 9
	G.sublevel = 10
	var r1: float = G.adaptive_ramp(3)
	ch.append(["far ahead of floor 3: capped at max (%.3f)" % r1, absf(r1 - 0.25) < 0.0001])
	ch.append(["partly ahead of floor 10: between (%.3f)" % G.adaptive_ramp(n), G.adaptive_ramp(n) > 0.0 and G.adaptive_ramp(n) <= 0.25])
	# between: monotone
	var prev := -1.0
	var mono := true
	for rl in 12:
		G.realm = rl
		var v: float = G.adaptive_ramp(n)
		if v < prev - 0.00001:
			mono = false
		prev = v
	ch.append(["ramp never falls as you grow", mono])
	ch.append(["max hp/damage inputs positive", G.max_hp() > 0 and G.damage() > 0])
	G.realm = 9
	G.sublevel = 10
	ch.append(["floor 1 for a strong player is capped too", G.adaptive_ramp(1) <= 0.25 + 0.0001])
	ch.append(["depth 0 -> no ramp", G.adaptive_ramp(0) == 0.0])
	var fail := 0
	for c in ch:
		print("ADAPTIVE ", "ok  " if c[1] else "FAIL", c[0])
		if not c[1]:
			fail += 1
	print("ADAPTIVE CHECK ", ch.size() - fail, " passed, ", fail, " failed")
	quit(1 if fail > 0 else 0)
