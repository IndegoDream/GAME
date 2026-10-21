extends "res://scripts/systems/GameSystem.gd"
## Where your sitting goes (round 40). Robert: "choose a focus when you sit"
## -- and "allow for both: a research tree for splitting the mind or
## diverting the nanites' function on more than one thing at a time".
##
## FOCUS: Cultivate (qi in full, and your meridian focus point opens),
## Cleanse (a node of your meridians) or Research (a swarm design). Qi still
## comes while you cleanse or research -- 60% of it.
## SPLIT (Divided Mind research): two threads, then three -- shares you set.
## A split sitting does a little less of each (85%) until Quiet Mind.
## BACKGROUND (Swarm Parallelism): research and cleansing go on at a quarter
## (then half) pace while you're not sitting at all.

const WORK := ["cultivate", "cleanse", "research"]

var mode := "cultivate"
var split := {"cultivate": 1.0, "cleanse": 0.0, "research": 0.0}
var use_split := false


func reset() -> void:
	mode = "cultivate"
	split = {"cultivate": 1.0, "cleanse": 0.0, "research": 0.0}
	use_split = false
	clarity = 100.0
	mental_state = "focused"
	state_history.clear()


func save_state() -> Dictionary:
	return {
		"mode": mode,
		"split": split,
		"use_split": use_split,
		"clarity": clarity,
		"mental_state": mental_state,
		"state_history": state_history.duplicate()
	}


func load_state(d: Dictionary) -> void:
	mode = str(d.get("mode", "cultivate"))
	if not (mode in WORK):
		mode = "cultivate"
	var s = d.get("split", {})
	split = {"cultivate": 1.0, "cleanse": 0.0, "research": 0.0}
	if s is Dictionary:
		for k in WORK:
			split[k] = clampf(float(s.get(k, split[k])), 0.0, 1.0)
	use_split = bool(d.get("use_split", false))
	clarity = clampf(float(d.get("clarity", 100.0)), 0.0, 100.0)
	mental_state = str(d.get("mental_state", "focused"))
	state_history = []
	var h = d.get("state_history", [])
	if h is Array:
		state_history = h.duplicate()


func _res():
	return G.sys("research")


func threads() -> int:
	var r = _res()
	if r and r.unlocked("split3"):
		return 3
	if r and r.unlocked("split2"):
		return 2
	return 1


func set_mode(m: String) -> String:
	if not (m in WORK):
		return I18n.t("No such focus.")
	mode = m
	use_split = false
	G.stats_changed.emit()
	return I18n.t("Your focus when you sit: %s.") % label(m)


func set_share(k: String, v: float) -> String:
	if threads() < 2:
		return I18n.t("Your mind can't split yet (Divided Mind: Second Thread).")
	if not (k in WORK):
		return ""
	split[k] = clampf(v, 0.0, 1.0)
	use_split = true
	G.stats_changed.emit()
	return ""


func label(m: String) -> String:
	return {"cultivate": "Cultivate", "cleanse": "Cleanse", "research": "Research"}.get(m, m)


func shares() -> Dictionary:
	## what each second of sitting goes to (sums to 1)
	var out := {"cultivate": 0.0, "cleanse": 0.0, "research": 0.0}
	if not use_split or threads() < 2:
		out[mode] = 1.0
		return out
	# only as many threads as the mind can hold: the biggest shares win
	var ks := WORK.duplicate()
	ks.sort_custom(func(a, b): return float(split[a]) > float(split[b]))
	var tot := 0.0
	for i in mini(threads(), ks.size()):
		out[ks[i]] = float(split[ks[i]])
		tot += float(split[ks[i]])
	if tot <= 0.0:
		out = {"cultivate": 1.0, "cleanse": 0.0, "research": 0.0}
		return out
	for k in out:
		out[k] = float(out[k]) / tot
	return out


func split_efficiency(s: Dictionary) -> float:
	var used := 0
	for k in s:
		if float(s[k]) > 0.0:
			used += 1
	if used <= 1:
		return 1.0
	var r = _res()
	if r and r.unlocked("split_eff"):
		return 1.0
	return float(r.data.get("split_efficiency", 0.85)) if r else 0.85


func qi_factor(s: Dictionary) -> float:
	## qi still comes while the mind works on something else -- not as fast
	var r = _res()
	var q := float(r.data.get("split_qi", 0.6)) if r else 0.6
	return float(s.get("cultivate", 0.0)) + (1.0 - float(s.get("cultivate", 0.0))) * q


func bg_rate() -> float:
	var r = _res()
	if r == null:
		return 0.0
	var B: Dictionary = r.data.get("background", {})
	if r.unlocked("bg2"):
		return float(B.get("bg2", 0.5))
	if r.unlocked("bg1"):
		return float(B.get("bg1", 0.25))
	return 0.0


func summary() -> String:
	var s := shares()
	var parts := []
	for k in WORK:
		if float(s[k]) > 0.0:
			parts.append("%s %d%%" % [label(k), int(round(float(s[k]) * 100))])
	return "%s  (qi at %d%%)" % [", ".join(parts), int(round(qi_factor(s) * 100))]


var clarity: float = 100.0
var mental_state: String = "focused"
var state_history: Array = []

const STATES := ["tranquil", "focused", "agitated", "overwhelmed"]


func update_mental_state(delta_clarity: float, action_reason: String = "") -> void:
	clarity = clampf(clarity + delta_clarity, 0.0, 100.0)
	var prev_state = mental_state
	if clarity >= 80.0:
		mental_state = "tranquil"
	elif clarity >= 50.0:
		mental_state = "focused"
	elif clarity >= 25.0:
		mental_state = "agitated"
	else:
		mental_state = "overwhelmed"

	if action_reason != "" or prev_state != mental_state:
		state_history.append({
			"clarity": clarity,
			"state": mental_state,
			"reason": action_reason
		})
		if state_history.size() > 20:
			state_history.pop_front()
	G.stats_changed.emit()


func get_decision_modifier() -> float:
	match mental_state:
		"tranquil":
			return 1.15
		"focused":
			return 1.0
		"agitated":
			return 0.85
		"overwhelmed":
			return 0.7
	return 1.0
