extends "res://scripts/systems/GameSystem.gd"
## Round 145: the collection. Robert, 2026-10-18: "do them all" -- something for explorers and collectors. Nothing new to hunt for:
## it counts what the game already tracks (beasts and foes met, things found, treasures, recipes made, Wayfarers met, their stories, history
## fragments, hidden masters) as a completion percentage, and shows what is still unseen as silhouettes ("???" with a floor hint).
## Every 10% of the whole gives a little insight, once each. State: which tenths were paid.

var paid := {}              # "10", "20" ... -> true


func reset() -> void:
	paid = {}


func save_state() -> Dictionary:
	return {"paid": paid}


func load_state(d: Dictionary) -> void:
	reset()
	var p = d.get("paid", {})
	if p is Dictionary:
		for k in p:
			paid[str(k)] = true


func _foes() -> Array:
	var keys: Array = G.enemies.keys()
	keys.sort_custom(func(a, b):
		var fa := int(G.enemies[a].get("floor", 1))
		var fb := int(G.enemies[b].get("floor", 1))
		return fa < fb or (fa == fb and str(a) < str(b)))
	return keys


func _treasures() -> Array:
	var out := []
	for k in G.items:
		if G.is_treasure(str(k)):
			out.append(str(k))
	out.sort()
	return out


func _materials() -> Array:
	var out := []
	for k in G.items:
		if str(G.items[k].get("type", "")) == "material":
			out.append(str(k))
	out.sort()
	return out


func _wayfarers() -> Array:
	var M = G.sys("menagerie")
	var out := []
	if M != null:
		for w in M.data.get("wayfarers", []):
			out.append(str(w.get("name", "")))
	return out


func categories() -> Array:
	## [{"id","name","have","need","seen":[names], "hidden":[hints]}]
	var out := []
	# foes and beasts met
	var seen := []
	var hid := []
	for k in _foes():
		var e: Dictionary = G.enemies[k]
		if int(G.kills.get(str(k), 0)) > 0:
			seen.append(str(e.get("name", k)))
		else:
			hid.append(I18n.t("??? (floor %d)") % int(e.get("floor", 1)))
	out.append({"id": "foes", "name": I18n.t("Beasts and foes met"), "have": seen.size(), "need": seen.size() + hid.size(), "seen": seen, "hidden": hid})
	# materials found
	var ms := _materials()
	var mh := 0
	for m in ms:
		if G.journal.get("items", {}).has(str(m)):
			mh += 1
	out.append({"id": "materials", "name": I18n.t("Materials found"), "have": mh, "need": ms.size(), "seen": [], "hidden": []})
	# treasures
	var ts := _treasures()
	var th := []
	var tm := []
	for t in ts:
		if G.count(str(t)) > 0 or G.journal.get("items", {}).has(str(t)):
			th.append(G.item_name(str(t)))
		else:
			tm.append("???")
	out.append({"id": "treasures", "name": I18n.t("Treasures"), "have": th.size(), "need": ts.size(), "seen": th, "hidden": tm})
	# recipes made
	var cb = G.sys("craftbook")
	var made := 0
	if cb != null:
		made = cb.recipe_keys().size()
	var makes := {}
	for r in G.recipes:
		makes[str(r.get("makes", ""))] = true
	out.append({"id": "recipes", "name": I18n.t("Things you have made"), "have": mini(made, makes.size()), "need": makes.size(), "seen": [], "hidden": []})
	# wayfarers
	var M = G.sys("menagerie")
	var ws := _wayfarers()
	var wm := []
	var wh := []
	for n in ws:
		if M != null and (M.trust.has(n) or int(M.deep.get(n, 0)) > 0):
			wm.append(n)
		else:
			wh.append("???")
	out.append({"id": "wayfarers", "name": I18n.t("Wayfarers met"), "have": wm.size(), "need": ws.size(), "seen": wm, "hidden": wh})
	# their stories
	var WS = G.sys("stories")
	var ch := 0
	var chn := 0
	if WS != null:
		for n in ws:
			ch += WS.done_count(n)
			chn += WS.chapters(n).size()
	out.append({"id": "stories", "name": I18n.t("Wayfarer stories told"), "have": ch, "need": chn, "seen": [], "hidden": []})
	# history fragments
	var lo = G.sys("lore")
	if lo != null:
		out.append({"id": "history", "name": I18n.t("History fragments"), "have": lo.history_found.size(), "need": (lo.data.get("history", []) as Array).size(), "seen": [], "hidden": []})
	# hidden masters
	var hm_total := (G.hm_data().get("masters", []) as Array).size()
	var hm_found := 0
	for m in G.hm_data().get("masters", []):
		if G.hm.has(str(m.get("id", ""))):
			hm_found += 1
	out.append({"id": "masters", "name": I18n.t("Hidden masters found"), "have": hm_found, "need": hm_total, "seen": [], "hidden": []})
	return out


func overall() -> float:
	var cats := categories()
	var sum := 0.0
	var n := 0
	for c in cats:
		if int(c["need"]) > 0:
			sum += clampf(float(c["have"]) / float(c["need"]), 0.0, 1.0)
			n += 1
	return sum / float(maxi(n, 1))


func percent() -> int:
	return int(floor(overall() * 100.0))


func milestones_due() -> Array:
	var out := []
	var p := percent()
	for t in range(10, 101, 10):
		if p >= t and not paid.has(str(t)):
			out.append(t)
	return out


func claim() -> void:
	## pay each tenth reached, once (a little insight)
	for t in milestones_due():
		paid[str(t)] = true
		G.gain_insight(2.0, "the collection")
		G.message.emit(I18n.t("COLLECTION: %d%% of what the world holds is in your book. +2 insight.") % int(t))
		G.log_event("collection", {"percent": int(t)})
	if not milestones_due().is_empty():
		pass


func on_event(kind: String, _d: Dictionary) -> void:
	if kind in ["journal_item", "history_found", "hm_reveal", "hm_done", "wayfarer_story", "craft", "forge", "treasure"] or (kind == "kill" and int(G.kills.get(str(_d.get("type", "")), 0)) <= 1):
		claim()
