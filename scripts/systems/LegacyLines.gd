extends RefCounted
## Legacy quest lines (round 119). Robert, 2026-10-13: "Do not make it so easy
## to earn inheritances provide a quest line to fulfill to unlock. The better
## the inheritance the longer the quest line and depending on how much it
## synergizes shortens how much you have to do. The quest line can run
## parallel to the main quest."
##
## A major or heavenly inheritance only opens the master's task when you
## touch it. The task is a quest in the ordinary quest log (kind "legacy")
## built from steps the quest engine already knows (gather, kill_floor,
## skill, reach). The seat accepts you once the last step is done. How many
## steps: ceil(base * (1 - synergy_cut * synergy)), never under min_share of
## the base. synergy (0..1) is how many of the master's gift tags (offense,
## defense, qi, speed, craft, vitality, fortune) you already carry in
## the arts you know. Steps you already satisfy complete themselves.
## All numbers: data/legacy_quests.json.

static var _cfg := {}
static var skip := false        # tests of the older claim flow set this: every line counts as done


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var d = Game._load_json("res://data/legacy_quests.json", {})
		_cfg = d if d is Dictionary else {}
	return _cfg


static func needs_line(tier: String) -> bool:
	return tier == "major" or tier == "heavenly"


static func qid_of(key: String) -> String:
	return "legacy:" + key


static func state(key: String) -> String:
	if skip:
		return "done"
	var Q = Game.sys("quests")
	if Q == null:
		return "done"                      # no quest engine: never lock a player out
	var q := qid_of(key)
	if Q.done.has(q):
		return "done"
	if Q.active.has(q):
		return "active"
	return "none"


static func _tags_of_effect(e: Dictionary, into: Dictionary) -> void:
	var tm: Dictionary = cfg().get("effect_tags", {})
	for k in e:
		if tm.has(str(k)):
			into[str(tm[str(k)])] = true


static func master_tags(grants: Dictionary) -> Dictionary:
	var t := {}
	for tid in grants.get("techniques", []):
		var td: Dictionary = Game.technique_defs.get(str(tid), {})
		_tags_of_effect(td.get("effect", {}), t)
	for id in grants.get("items", {}):
		var it: Dictionary = Game.items.get(str(id), {})
		_tags_of_effect(it.get("effect", {}), t)
	return t


static func player_tags() -> Dictionary:
	var t := {}
	for tid in Game.techniques:
		var td: Dictionary = Game.technique_defs.get(str(tid), {})
		_tags_of_effect(td.get("effect", {}), t)
	return t


static func synergy(grants: Dictionary) -> float:
	var m := master_tags(grants)
	if m.is_empty():
		return 0.0
	var p := player_tags()
	var hit := 0
	for k in m:
		if p.has(k):
			hit += 1
	return float(hit) / float(m.size())


static func steps_for(tier: String, syn: float) -> int:
	var base := int(cfg().get("base_steps", {}).get(tier, 6))
	var cut := float(cfg().get("synergy_cut", 0.5))
	var floor_n := int(ceil(float(base) * float(cfg().get("min_share", 0.5))))
	return maxi(floor_n, int(ceil(float(base) * (1.0 - cut * clampf(syn, 0.0, 1.0)))))


static func _range(tier: String, key: String, r: RandomNumberGenerator) -> int:
	var a: Array = cfg().get(key, {}).get(tier, [3, 5])
	return r.randi_range(int(a[0]), int(a[1]))


static func _pick(words: Array, r: RandomNumberGenerator) -> String:
	return str(words[r.randi() % words.size()])


static func _gather_item(d: int, r: RandomNumberGenerator, used: Array) -> String:
	var pool: Array = []
	for b in cfg().get("gather_bands", []):
		if d >= int(b["floors"][0]) and d <= int(b["floors"][1]):
			pool = (b["items"] as Array).duplicate()
	if pool.is_empty():
		pool = ["iron_ore"]
	pool = pool.filter(func(i): return Game.items.has(str(i)) and not used.has(str(i)))
	if pool.is_empty():
		return "iron_ore"
	return str(pool[r.randi() % pool.size()])


static func plan(key: String, master: String, tier: String, grants: Dictionary, depth: int) -> Dictionary:
	## the quest definition for this seat, the same every time it is asked
	var d := clampi(depth, 1, 50)
	var syn := synergy(grants)
	var n := steps_for(tier, syn)
	var base := int(cfg().get("base_steps", {}).get(tier, 6))
	var r := RandomNumberGenerator.new()
	var Lg = Game.sys("legacies")
	r.seed = hash("%s|%d|line" % [key, int(Lg.seed_v) if Lg else 0])
	var W: Dictionary = cfg().get("words", {})
	var stages: Array = []
	var used_items: Array = []
	var used_skills: Array = []
	var did_reach := false
	var last := ""
	var kinds := ["gather", "kill", "gather", "kill", "skill", "reach"]
	for i in n:
		var k := ""
		var guard := 0
		while guard < 30:
			guard += 1
			k = str(kinds[r.randi() % kinds.size()])
			if k == last and guard < 20:
				continue
			if k == "reach" and (did_reach or i == 0):
				continue
			break
		last = k
		var st := {}
		match k:
			"gather":
				var it := _gather_item(d, r, used_items)
				used_items.append(it)
				var c := _range(tier, "gather_count", r)
				st = {"log": _pick(W.get("gather", ["Bring %d %s."]), r) % [c, Game.item_name(it)], "goal": {"gather": {"item": it, "count": c}}, "take": {it: c}}
			"kill":
				var f := clampi(d - r.randi_range(0, 2), 1, 50)
				var c2 := _range(tier, "kill", r)
				st = {"log": _pick(W.get("kill", ["Defeat %d foes on floor %d."]), r) % [c2, f], "goal": {"kill_floor": {"floor": f, "count": c2}}}
			"skill":
				var pool: Array = (cfg().get("skills", ["mining"]) as Array).filter(func(s): return not used_skills.has(str(s)))
				if pool.is_empty():
					pool = ["mining"]
				var sk := str(pool[r.randi() % pool.size()])
				used_skills.append(sk)
				var lv := int(cfg().get("skill_level", {}).get(tier, 2)) + int(d / 12)
				st = {"log": _pick(W.get("skill", ["Reach %s level %d."]), r) % [sk, lv], "goal": {"skill": {"id": sk, "level": lv}}}
			_:
				did_reach = true
				var to := clampi(d + int(cfg().get("reach_extra", {}).get(tier, 1)), 1, 50)
				st = {"log": _pick(W.get("reach", ["Walk down to floor %d."]), r) % to, "goal": {"reach": to}}
		stages.append(st)
	var nm := I18n.t("The Task of ") + master.trim_prefix("the ").capitalize()
	var rw := {"qi_kills": int(cfg().get("reward_qi_kills", {}).get(tier, 4))}
	return {"id": qid_of(key), "name": nm, "kind": "legacy", "giver": master, "pitch": "",
		"stages": stages, "unlock": {}, "synergy": syn, "base_steps": base,
		"endings": {"default": {"say": str(W.get("done", "The master's task is done.")), "reward": rw}}}


static func start(key: String, master: String, tier: String, grants: Dictionary, depth: int) -> void:
	var Q = Game.sys("quests")
	if Q == null or state(key) != "none":
		return
	var def := plan(key, master, tier, grants, depth)
	Q.legacy_defs[qid_of(key)] = def
	Q.accept(qid_of(key))
	Game.log_event("legacy_line_start", {"master": master, "steps": def["stages"].size()})
