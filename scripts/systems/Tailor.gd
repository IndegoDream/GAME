extends "res://scripts/systems/GameSystem.gd"
## Round 177: the Tailor -- steer the bench by what you want.
## Robert, 2026-10-25: "allow for crafting to show likelihood of positive effects and negative effects, allow for user to pick for items
## benefit and then the user will have a list of choices to further tailor the choices to the users wishes."
## Pick an item and a goal; the Tailor ranks what you could work into it using the bench's own odds (Game.combine_preview), and shows for
## each the chance it works, the chance you lose the materials, the chance it backfires, a lucky find, and the good traits it brings.

var data := {}
var tries := 0


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/tailor.json")


func reset() -> void:
	tries = 0


func save_state() -> Dictionary:
	return {"tries": tries}


func load_state(d: Dictionary) -> void:
	reset()
	tries = int(d.get("tries", 0))


func goals() -> Dictionary:
	return data.get("goals", {})


func styles() -> Dictionary:
	return data.get("styles", {})


func bases() -> Array:
	## things you carry that the bench can work something into
	var out := []
	for id in G.inventory:
		if G.count(str(id)) <= 0 or not G.has_item_def(str(id)) or G.is_treasure(str(id)):
			continue
		if str(G.item_def(str(id)).get("type", "")) in ["currency", "formula", "treasure"]:
			continue
		if G._bench_kind(str(id), []) == "":
			continue
		out.append(str(id))
	out.sort_custom(func(a, b): return G.item_name(a) < G.item_name(b))
	return out


func _good_keys(goal: String) -> Array:
	return goals().get(goal, {}).get("keys", [])


func _benefit(pv: Dictionary, goal: String) -> Dictionary:
	## {points, names}: how much of what you asked for it brings (only what you can see: unknown things count for nothing)
	var keys := _good_keys(goal)
	var tr: Dictionary = G.craft_data().get("traits", {})
	var pts := 0.0
	var names := []
	var known: Dictionary = pv.get("traits", {})
	for t in known:
		var td: Dictionary = tr.get(str(t), {})
		if str(td.get("effect", "")) in keys:
			var w := float(data.get("volatile_half", 0.5)) if str(t) == "volatile" and not bool(pv.get("steady", false)) else 1.0
			pts += float(known[t]) * w
			names.append("%s %d" % [G.trait_name(str(t)), int(known[t])])
	for sy in G.craft_data().get("synergies", []):
		if str(sy["name"]) in pv.get("synergies", []):
			var n := 0
			for k in sy["effect"]:
				if str(k) in keys:
					n += 1
			if n > 0:
				pts += float(data.get("synergy_points", 3.0)) * float(n)
				names.append(str(sy["name"]))
	return {"points": pts, "names": names}


func _pool(base: String, goal: String) -> Array:
	var keys := _good_keys(goal)
	var tr: Dictionary = G.craft_data().get("traits", {})
	var cand := []
	for id in G.inventory:
		var sid := str(id)
		if G.count(sid) <= 0 or not G.has_item_def(sid) or G.is_treasure(sid):
			continue
		if str(G.item_def(sid).get("type", "")) in ["currency", "formula", "treasure", "weapon", "armor"] and G.gear_family(sid) != "":
			continue
		var rel := 0.0
		if G.knows_material(sid):
			var mt: Dictionary = G.material_traits(sid)
			for t in mt:
				if str(tr.get(str(t), {}).get("effect", "")) in keys:
					rel += float(mt[t])
		else:
			rel = 0.1                        # unknown: worth a gamble, ranked last
		cand.append([sid, rel])
	cand.sort_custom(func(a, b): return a[1] > b[1])
	var out := []
	for c in cand:
		if out.size() < int(data.get("pool", 10)):
			out.append(str(c[0]))
	return out


func _sets(pool: Array, maxn: int) -> Array:
	var out := []
	var n := pool.size()
	for i in n:
		out.append([pool[i]])
		if maxn >= 2:
			for j in range(i, n):
				out.append([pool[i], pool[j]])
				if maxn >= 3:
					for k in range(j, n):
						out.append([pool[i], pool[j], pool[k]])
	return out


func suggest(base: String, goal: String, style: String = "balanced", maxn: int = 3, avoid_volatile: bool = false, limit: int = 6) -> Array:
	var st: Dictionary = styles().get(style, styles()["balanced"])
	var rows := []
	for adds in _sets(_pool(base, goal), maxn):
		if adds.has(base) and G.count(base) < 1 + adds.count(base):
			continue
		if G.combine_check(base, adds) != "":
			continue
		var pv: Dictionary = G.combine_preview(base, adds)
		if not bool(pv["ok"]):
			continue
		if avoid_volatile and int(pv.get("volatile", 0)) > 0 and not bool(pv.get("steady", false)):
			continue
		var ben: Dictionary = _benefit(pv, goal)
		if float(ben["points"]) <= 0.0:
			continue
		var chance := float(pv["chance"])
		var backfire := 0.0
		if int(pv.get("volatile", 0)) >= 3 and not bool(pv.get("steady", false)):
			backfire = clampf(1.0 - chance - 0.3, 0.0, 1.0)
		var lose := 1.0 - chance
		var score := float(ben["points"]) * pow(chance, float(st["exp"])) - float(st["risk"]) * (lose + 2.0 * backfire) * 0.5
		rows.append({"adds": adds, "chance": chance, "luck": float(pv["luck"]), "lose": lose, "backfire": backfire, "benefit": float(ben["points"]),
			"good": ben["names"], "notes": pv.get("notes", []), "kind": str(pv["kind"]), "score": score, "steady": bool(pv.get("steady", false))})
	rows.sort_custom(func(a, b): return a["score"] > b["score"])
	var seen := {}
	var out := []
	for r in rows:
		var key := ",".join((r["adds"] as Array).map(func(x): return str(x)))
		if seen.has(key):
			continue
		seen[key] = true
		out.append(r)
		if out.size() >= limit:
			break
	return out


func adds_text(r: Dictionary) -> String:
	var counts := {}
	for a in r["adds"]:
		counts[str(a)] = int(counts.get(str(a), 0)) + 1
	var parts := []
	for k in counts:
		parts.append("%s%s" % [G.item_name(str(k)), (" x%d" % int(counts[k])) if int(counts[k]) > 1 else ""])
	return " + ".join(parts)


func odds_text(r: Dictionary) -> String:
	var t := I18n.t("Works %d%%  ·  fails %d%% (materials lost)") % [int(round(float(r["chance"]) * 100.0)), int(round(float(r["lose"]) * 100.0))]
	if float(r["backfire"]) > 0.0:
		t += I18n.t("  ·  backfires %d%%") % int(round(float(r["backfire"]) * 100.0))
	t += I18n.t("  ·  lucky find %d%%") % int(round(float(r["luck"]) * 100.0))
	return t


func good_text(r: Dictionary) -> String:
	return I18n.t("Brings: ") + (", ".join(r["good"]) if not (r["good"] as Array).is_empty() else I18n.t("nothing you asked for"))


func bad_text(r: Dictionary) -> String:
	var bits := []
	for n in r["notes"]:
		bits.append(str(n))
	if float(r["backfire"]) > 0.0:
		bits.append(I18n.t("can scorch or destroy the base"))
	return I18n.t("Watch for: ") + (", ".join(bits) if not bits.is_empty() else I18n.t("nothing special"))


func run(base: String, r: Dictionary) -> String:
	var res: Dictionary = G.combine_attempt(base, r["adds"])
	tries += 1
	G.stats_changed.emit()
	return str(res.get("text", ""))
