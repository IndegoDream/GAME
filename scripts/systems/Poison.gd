extends "res://scripts/systems/GameSystem.gd"
## Round 138: poison. Robert, 2026-10-17: "Yes add that" (a poison you can use, a poison you can suffer).
##   COATINGS  venom_sac + a binder make a coating (items.json: coat). It gives your next N hits a poison that eats the foe a
##             little at a time; a numbing coating slows instead. Foes' poison is CAPPED per second (a fraction of the foe's
##             life), and masters shrug half of it off -- poison is a way to win a long fight, never a way to skip one.
##   VENOM     the venomous elites now poison you through here: it wears you down but never finishes you, caps at 12 seconds
##             of it, and does nothing while an antidote's ward holds.
##   ANTIDOTE  clears it and keeps you clean for four minutes. Also: resting at home clears it.
## data/poison.json. The coating's charges are saved; the poison in your veins is not (it's seconds long).

var data := {}
var coat_kind := ""
var coat_hits := 0
var p_left := 0.0           # seconds of poison still in you
var p_tick := 0
var _acc := 0.0


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/poison.json")
	G.buff_names["antidote_ward"] = "Antidote ward"


func reset() -> void:
	coat_kind = ""
	coat_hits = 0
	p_left = 0.0
	p_tick = 0
	_acc = 0.0


func save_state() -> Dictionary:
	return {"coat_kind": coat_kind, "coat_hits": coat_hits}


func load_state(d: Dictionary) -> void:
	reset()
	var k := str(d.get("coat_kind", ""))
	if data.get("coat", {}).has(k):
		coat_kind = k
		coat_hits = clampi(int(d.get("coat_hits", 0)), 0, 200)
		if coat_hits <= 0:
			coat_kind = ""


# ---- your weapon ------------------------------------------------------------------------------------------------------

func apply_coating(c: Dictionary, item_name: String) -> String:
	var k := str(c.get("kind", ""))
	if not data.get("coat", {}).has(k):
		return ""
	coat_kind = k
	coat_hits = clampi(int(c.get("hits", 20)), 1, 200)
	G.stats_changed.emit()
	return I18n.t("%s on your weapon: %d hits.") % [item_name, coat_hits]


func coat_text() -> String:
	if coat_hits <= 0:
		return ""
	return I18n.t("%s coating: %d hits left") % [str(data["coat"][coat_kind].get("name", coat_kind)), coat_hits]


func on_player_hit(foe, dmg: int) -> void:
	## called from every melee hit that lands
	if coat_hits <= 0 or foe == null or not is_instance_valid(foe):
		return
	var C: Dictionary = data["coat"].get(coat_kind, {})
	if C.is_empty():
		coat_hits = 0
		return
	coat_hits -= 1
	var boss: bool = bool(foe.stats.get("boss", false))
	if float(C.get("hit_share", 0.0)) > 0.0 and foe.has_method("poison"):
		foe.poison(maxi(1, int(round(float(dmg) * float(C["hit_share"])))), float(C.get("secs", 4.0)))
	if float(C.get("slow_secs", 0.0)) > 0.0 and foe.has_method("slow"):
		foe.slow(float(C["slow_secs"]) * (float(data.get("boss_slow_mult", 0.3)) if boss else 1.0))
	if coat_hits <= 0:
		coat_kind = ""
		G.message.emit("Your weapon's coating is spent.")
		G.stats_changed.emit()


func foe_cap_dps(foe) -> float:
	## the most poison may take from this foe each second
	var cap: Dictionary = data.get("foe_cap_per_sec", {})
	var share := float(cap.get("normal", 0.025))
	if bool(foe.stats.get("boss", false)):
		share = float(cap.get("boss", 0.006))
	elif bool(foe.get("elite")):
		share = float(cap.get("elite", 0.015))
	return maxf(1.0, float(foe.get("max_hp") if foe.get("max_hp") != null else foe.stats.get("hp", 10)) * share)


# ---- you ------------------------------------------------------------------------------------------------------------------

func warded() -> bool:
	return G.active_buffs().has(str(data.get("ward_buff", "antidote_ward")))


func afflict(tick: int, secs: float) -> bool:
	## true if it took hold
	if warded() or tick <= 0 or secs <= 0.0:
		return false
	var P: Dictionary = data.get("player", {})
	p_tick = maxi(p_tick if p_left > 0.0 else 0, tick)
	p_left = minf(p_left + secs, float(P.get("max_secs", 12.0)))
	G.stats_changed.emit()
	return true


func poisoned() -> bool:
	return p_left > 0.0


func antidote(strength: float) -> String:
	var was := poisoned()
	p_left = 0.0
	p_tick = 0
	_acc = 0.0
	G.add_buff(str(data.get("ward_buff", "antidote_ward")), {}, float(data.get("player", {}).get("antidote_ward_secs", 240.0)))
	G.stats_changed.emit()
	return I18n.t("The poison leaves you. You are clean of new ones for a while.") if was else I18n.t("You are clean of new poisons for a while.")


func tick(delta: float) -> void:
	if p_left <= 0.0:
		return
	p_left -= delta
	_acc += delta
	while _acc >= 1.0 and p_left > -1.0:
		_acc -= 1.0
		var cap := maxi(1, int(round(float(G.max_hp()) * float(data.get("player", {}).get("tick_cap_share", 0.04)))))
		var d := mini(mini(p_tick, cap), G.hp - 1)
		if d > 0:
			G.hurt(d)
			G.message.emit("-%d HP (poison)" % d)
	if p_left <= 0.0:
		p_left = 0.0
		p_tick = 0
		_acc = 0.0
		G.stats_changed.emit()


func on_event(kind: String, _d: Dictionary) -> void:
	if kind == "rest_home" and poisoned():
		p_left = 0.0
		p_tick = 0
