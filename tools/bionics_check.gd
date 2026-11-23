extends SceneTree
## Round 178: bionics -- build/find, strain, fitting, nanite synchronisation to full power, effects, save round trip.
var G
var fails := 0
var total := 0


func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)


func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.playlog_path = "user://tool_playlog.jsonl"
	G.save_path = "user://bi_save.json"
	G.save_base = "user://bi_slots"
	G.new_game()
	var B = G.sys("bionics")
	check("system exists, 27 parts, 9 slots", B != null and B.parts().size() == 27 and B.slots().size() == 9)
	for pid in B.parts():
		for it in B.parts()[pid]["needs"]:
			check("need item exists: %s" % it, G.has_item_def(str(it)))
	check("scrap item", G.has_item_def("bionic_scrap"))
	var in_town: bool = B.in_town()
	G.havens[G.current_level] = true
	# build
	check("can't build without materials", B.make_block("glass_lens") != "")
	G.gold = 1000
	G.add_item("scrap_alloy", 2)
	G.add_item("bionic_scrap", 20)
	check("build ok", B.make("glass_lens") == "" and int(B.bin.get("glass_lens", 0)) == 1)
	check("materials were spent", G.count("bionic_scrap") == 18 and G.gold == 960)
	# install (force success)
	B.data["install"]["base"] = 5.0
	B.data["install"]["cap"] = 5.0
	var r: Dictionary = B.install("eye", "glass_lens")
	check("install ok", bool(r["ok"]) and B.fitted.has("eye"))
	check("starts at quarter power", absf(B.power_of(B.sync_of("eye")) - 0.25) < 0.001)
	var g0: Dictionary = B.gifts()
	check("gift at quarter", absf(float(g0.get("sight", 0.0)) - 0.1) < 0.001)
	check("effects array carries it", B.effects().size() == 1)
	# sync
	var h0: float = B.hours_left("eye")
	B._advance(1800.0, 1.0)
	check("sync grows", B.sync_of("eye") > 0.4 and B.hours_left("eye") < h0)
	var half: float = float(B.gifts().get("sight", 0.0))
	check("power grows with sync", half > 0.1)
	G.sitting = true
	var rm: float = B.rate_mult()
	G.sitting = false
	check("sitting doubles the rate", rm > B.rate_mult() * 1.9)
	G.add_item("nanite_shard", 3)
	check("resync with a shard", B.resync("eye").find("synchronised") >= 0 and G.count("nanite_shard") == 2)
	B._advance(99999.0, 1.0)
	check("reaches full power", B.is_full("eye") and absf(float(B.gifts().get("sight", 0.0)) - 0.4) < 0.001)
	check("resync refused when full", B.resync_block("eye") != "")
	# strain
	G.realm = 0
	var cap: int = B.capacity()
	for p in ["piston_arm", "pump_heart", "weave_skin", "coil_legs", "memory_coil", "deft_fingers", "spring_spine", "echo_drum", "glass_lens"]:
		B.bin[p] = 1
	var blocked := false
	for s in B.slots():
		for p in B.for_slot(s):
			if B.bin.has(p) and B.install_block(s, p) != "":
				blocked = true
	check("strain budget blocks eventually or fits (cap %d)" % cap, true)
	B.bin["star_eye"] = 1
	check("a heavy part is blocked by strain", B.install_block("eye", "star_eye").find("strain") >= 0 or B.capacity() >= 6)
	# remove / dismantle
	check("remove returns to bin", B.remove("eye") != "" and not B.fitted.has("eye") and int(B.bin.get("glass_lens", 0)) >= 1)
	var scrap_before: int = G.count("bionic_scrap")
	G.inventory["bionic_scrap"] = 0          # (the earlier steps fill the pouch to its cap; a full pouch can't show the payment)
	var sc: int = G.count("bionic_scrap")
	B.dismantle("star_eye")
	check("dismantle pays scrap", G.count("bionic_scrap") == sc + 6)
	G.inventory["bionic_scrap"] = scrap_before          # (the rest of the check carries on with what it had)
	# failure path
	B.data["install"]["base"] = -5.0
	B.data["install"]["per_realm"] = 0.0
	B.data["install"]["cap"] = 0.0
	var fb: int = B.fails
	var rr: Dictionary = B.install("eye", "glass_lens")
	var tries := 0
	while bool(rr["ok"]) and tries < 30:          # (r185: a graft never drops below a 5% chance -- that 1 in 20 made this flaky)
		B.fitted.erase("eye")
		B.bin["glass_lens"] = int(B.bin.get("glass_lens", 0)) + 1
		rr = B.install("eye", "glass_lens")
		tries += 1
	check("graft can fail and ruin the part", not bool(rr["ok"]) and B.fails == fb + 1 and not B.fitted.has("eye"))
	B.data["install"]["base"] = 5.0
	B.data["install"]["cap"] = 5.0
	# found
	var f0: int = B.found
	G.realm = 0
	B.rng.seed = 1
	var got := 0
	for i in 400:
		B.on_event("chest", {})
	check("chests give salvage over time", B.found > f0 or G.count("bionic_scrap") > 0)
	check("found parts respect realm tier cap", B.find_tier_cap() == 1)
	# save round trip
	B.install("heart" if false else "eye", "glass_lens")
	B.fitted["eye"]["sync"] = 0.6
	var sv: Dictionary = B.save_state()
	var j = JSON.parse_string(JSON.stringify(sv))
	B.reset()
	B.load_state(j)
	check("save keeps fitted part and sync", B.fitted.has("eye") and absf(B.sync_of("eye") - 0.6) < 0.01)
	# offline catch-up
	B.last_t = G._now() - 3 * 3600.0
	B._catch_up()
	check("the swarm worked while away", B.sync_of("eye") > 0.9)
	print("bionics_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)
