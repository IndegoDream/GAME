extends "res://scripts/systems/GameSystem.gd"
## Round 146: aspecting the nanites. Robert, 2026-10-18: "allow for player to aspect their nanites to different elements for increased
## bonuses and secrets ... this can be part of meditation and active meditation which is a somewhat passive skill but it should be more of a
## buff that needs to be refreshed ... while moving is when aspecting is most likely to happen, sit meditation can also improve and refine".
##   ACTIVE MEDITATION ("flow"): press M while walking (or the flow key, "]"). You walk a little slower; every few seconds of walking you
##     draw a breath: the aspect's buff is topped up (lasts minutes, then fades -- refresh it) and your attunement to the chosen element grows.
##     Striking, being hit, or standing still for a while ends the flow. You can't flow in a fight for long -- that is the point.
##   SITTING: refines the chosen element (a slow +% to its strength). Sitting is for depth, walking is for growth.
##   SECRETS: at attunement 40 and 80 of each element, and when every thread passes 50, a small permanent gift.
## Starts at swarm tier 2 (Lattice). Offline game only. data/aspect.json.

var data := {}
var focus := "fire"
var att := {}               # element -> 0..100
var refine := {}            # element -> 0..100
var secrets := {}           # id -> true
var buff_left := 0.0        # seconds of the aspect buff left
var buff_el := ""           # the element the buff is for
var flowing := false
var _prog := 0.0            # seconds walked toward the next breath
var _idle := 0.0
var _fx_cache := {}
var _fx_key := ""


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/aspect.json")
	reset()


func reset() -> void:
	focus = "fire"
	att = {}
	refine = {}
	for e in G.ELEMENTS:
		att[e] = 0.0
		refine[e] = 0.0
	secrets = {}
	buff_left = 0.0
	buff_el = ""
	flowing = false
	_prog = 0.0
	_idle = 0.0
	_fx_key = ""


func save_state() -> Dictionary:
	return {"focus": focus, "att": att, "refine": refine, "secrets": secrets, "buff_left": buff_left, "buff_el": buff_el}


func load_state(d: Dictionary) -> void:
	reset()
	var f := str(d.get("focus", "fire"))
	focus = f if f in G.ELEMENTS else "fire"
	for k in ["att", "refine"]:
		var src = d.get(k, {})
		if src is Dictionary:
			for e in G.ELEMENTS:
				(att if k == "att" else refine)[e] = clampf(float(src.get(e, 0.0)), 0.0, 100.0)
	var sc = d.get("secrets", {})
	if sc is Dictionary:
		for k in sc:
			if not secret_def(str(k)).is_empty():
				secrets[str(k)] = true
	buff_left = maxf(0.0, float(d.get("buff_left", 0.0)))
	buff_el = str(d.get("buff_el", "")) if str(d.get("buff_el", "")) in G.ELEMENTS else ""
	if buff_el == "":
		buff_left = 0.0


func available() -> bool:
	return G.nanite_tier() >= int(data.get("min_tier", 2)) and not G.OnlineGen.is_online(str(G.current_level))


func aspect_def(el: String) -> Dictionary:
	return (data.get("aspects", {}) as Dictionary).get(el, {})


func secret_def(id: String) -> Dictionary:
	for s in data.get("secrets", []):
		if str(s.get("id", "")) == id:
			return s
	return {}


func set_focus(el: String) -> String:
	if not (el in G.ELEMENTS):
		return ""
	focus = el
	_fx_key = ""
	G.stats_changed.emit()
	return I18n.t("Your swarm turns toward %s.") % tr(str(aspect_def(el).get("name", el)))


func tier_factor() -> float:
	return clampf(float(data.get("tier_floor", 0.4)) + float(data.get("tier_step", 0.1)) * float(G.nanite_tier() - int(data.get("min_tier", 2))), 0.0, 1.0)


func strength(el: String) -> float:
	## 0..~1.5: attunement, deepened by sitting, held back by a young swarm
	return clampf(float(att.get(el, 0.0)) / 100.0, 0.0, 1.0) * (1.0 + float(refine.get(el, 0.0)) / 200.0) * tier_factor()


func buff_on() -> bool:
	return buff_left > 0.0 and buff_el != "" and available()


# ---- flow (active meditation) ---------------------------------------------------------------------------------------------------

func start_flow() -> String:
	if not available():
		return I18n.t("Your swarm is too young to take an aspect. (Nanite Lattice.)")
	if flowing:
		return ""
	flowing = true
	_prog = 0.0
	_idle = 0.0
	G.log_event("flow_start", {"element": focus})
	return I18n.t("You settle into the walk and draw on %s. Keep moving.") % tr(str(aspect_def(focus).get("name", focus)))


func stop_flow(why: String = "") -> void:
	if not flowing:
		return
	flowing = false
	_prog = 0.0
	if why != "":
		G.message.emit(why)


func flow_tick(delta: float, moving: bool) -> void:
	## once a frame from the Player while flowing
	if not flowing:
		return
	if not available():
		stop_flow()
		return
	if moving:
		_idle = 0.0
		_prog += delta
		if _prog >= float(data.get("breath_seconds", 5.0)):
			_prog = 0.0
			breath()
	else:
		_idle += delta
		if _idle >= float(data.get("idle_end", 8.0)):
			stop_flow(I18n.t("Your flow fades -- you stood still too long."))


func breath() -> void:
	var el := focus
	var gain := float(data.get("att_gain", 0.25)) * maxf(0.0, 1.0 - float(att[el]) / float(data.get("att_decay_at", 110.0)))
	att[el] = minf(100.0, float(att[el]) + gain)
	if buff_el != el:
		buff_left = 0.0
	buff_el = el
	buff_left = minf(float(data.get("buff_cap", 240.0)), buff_left + float(data.get("buff_per_breath", 45.0)))
	_fx_key = ""
	G.bump("flow_breaths")
	check_secrets()
	G.stats_changed.emit()


func sit_refine(secs: float) -> void:
	## sitting refines the chosen element
	if not available():
		return
	var cap := float(data.get("refine_cap", 100.0))
	refine[focus] = minf(cap, float(refine[focus]) + float(data.get("sit_refine_per_minute", 0.5)) * secs / 60.0 * (1.0 if float(att[focus]) > 0.0 else 0.0))
	_fx_key = ""


func meditate(secs: float, _shares: Dictionary, _aid: float) -> void:
	sit_refine(secs)


func tick(delta: float) -> void:
	if buff_left > 0.0:
		buff_left = maxf(0.0, buff_left - delta)
		if buff_left <= 0.0:
			_fx_key = ""
			if buff_el != "":
				G.message.emit(I18n.t("Your %s fades. Walk and draw breath (M) to bring it back.") % tr(str(aspect_def(buff_el).get("name", buff_el))))
	if flowing and G.sitting:
		stop_flow()


# ---- secrets -------------------------------------------------------------------------------------------------------------------

func check_secrets() -> void:
	for s in data.get("secrets", []):
		var id := str(s["id"])
		if secrets.has(id):
			continue
		var ok := false
		var el := str(s.get("element", ""))
		if el != "":
			ok = float(att[el]) >= float(s["att"])
		else:
			ok = G.ELEMENTS.all(func(e): return float(att[e]) >= float(s["att"]))
		if ok:
			secrets[id] = true
			_fx_key = ""
			G.message.emit(I18n.t("SECRET: %s -- %s") % [tr(str(s["name"])), tr(str(s["text"]))])
			G.log_event("aspect_secret", {"id": id})
			G.jingle("achievement")


func secret_rows() -> Array:
	var out := []
	for s in data.get("secrets", []):
		out.append({"id": str(s["id"]), "found": secrets.has(str(s["id"])), "name": str(s["name"]), "text": str(s["text"]), "element": str(s.get("element", "")), "att": int(s["att"])})
	return out


# ---- what it gives --------------------------------------------------------------------------------------------------------------

func _buff_fx() -> Dictionary:
	var out := {}
	var s := strength(buff_el)
	var fx: Dictionary = aspect_def(buff_el).get("fx", {})
	for k in fx:
		var v := float(fx[k])
		if k in G.ADDITIVE_KEYS:
			out[k] = v * s
		else:
			out[k] = 1.0 + v * s        # a multiplier key; a negative max (damage_taken) lowers it
	return out


func effects() -> Array:
	var out := []
	if not available():
		return out
	if buff_on():
		out.append(_buff_fx())
	var perm := {}
	for id in secrets:
		var fx: Dictionary = secret_def(str(id)).get("fx", {})
		for k in fx:
			if k in G.ADDITIVE_KEYS:
				perm[k] = float(perm.get(k, 0.0)) + float(fx[k])
			else:
				perm[k] = float(perm.get(k, 1.0)) * (1.0 + float(fx[k]))
	if not perm.is_empty():
		out.append(perm)
	return out
