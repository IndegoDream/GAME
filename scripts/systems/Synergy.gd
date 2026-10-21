extends "res://scripts/systems/GameSystem.gd"
## The swarm and qi, apart but bound (round 40). Robert, 2026-10-04: "have
## the swarm be separate but synergistic with qi ... the nanites using qi to
## function, the qi needing the nanites to increase recovery, focus,
## adaptability, connection. This was the original focus of the nanites, to
## help strengthen the connection; while it failed at that, its multitude of
## other functions help ease the way on the road to true enlightenment."
##
## SYNERGY LEVEL: the lower of your realm and your swarm tier -- both roads
## have to grow for it to grow -- plus half a level when they're in harmony.
## It raises four channels (data/synergy.json):
##   Recovery      faster qi while you sit, and health back every second
##   Focus         meridians open, nodes cleanse, research runs faster
##   Adaptability  every skill grows faster
##   Connection    insight comes easier; bonds (people, beasts) grow faster
##   Honing        (round 41: "designed to magnify focus and hone warriors as
##                 they grow together") harder blows, quicker hands, telling
##                 blows, and a wider moment to parry or slip a blow
## UPKEEP: designs and installs that run on qi draw from the qi you're
## gathering toward your next step, every minute. Run dry and they go quiet.

var data := {}
var starved := false
var drawn := 0.0              # qi drawn so far (shown on the page)
var _acc := 0.0


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/synergy.json")


func reset() -> void:
	starved = false
	drawn = 0.0


func save_state() -> Dictionary:
	return {"starved": starved, "drawn": drawn}


func load_state(d: Dictionary) -> void:
	starved = bool(d.get("starved", false))
	drawn = float(d.get("drawn", 0.0))


func level() -> float:
	var l := float(mini(G.realm, G.nanite_tier()))
	if G.harmony() == "harmony":
		l += float(data.get("harmony_bonus", 0.5))
	return l


func channel(ch: String) -> float:
	## the channel's bonus (0.1 = +10%)
	return level() * float(data.get("per_level", {}).get(ch, 0.0))


func effects() -> Array:
	var l := level()
	if l <= 0.0:
		return []
	return [{"meditate_mult": 1.0 + channel("recovery"), "regen": channel("recovery_regen"),
		"focus_mult": 1.0 + channel("focus"), "adapt_mult": 1.0 + channel("adaptability"),
		"insight_mult": 1.0 + channel("connection"), "bond_mult": 1.0 + channel("connection"),
		"damage_mult": 1.0 + channel("honing_damage"), "attack_speed": 1.0 + channel("honing_speed"),
		"crit_chance": channel("honing_crit"), "timing": channel("honing_timing")}]


func upkeep_per_minute() -> float:
	## qi a minute that the swarm's designs and installs draw
	var pts := 0.0
	var r = G.sys("research")
	if r:
		pts = float(r.upkeep_points())
	if pts <= 0.0:
		return 0.0
	return pts * float(data.get("upkeep_per_point", 0.00015)) * G.qi_to_next() * G.tech_effect("upkeep_mult", 1.0)


func tick(delta: float) -> void:
	_acc += delta
	if _acc < 1.0:
		return
	var secs := _acc
	_acc = 0.0
	var per_min := upkeep_per_minute()
	if per_min <= 0.0:
		if starved:
			starved = false
		return
	var need := per_min * secs / 60.0
	if G.qi >= need:
		G.qi -= need
		drawn += need
		if starved:
			starved = false
			G.message.emit("SWARM: there's qi again -- your designs wake.")
			G.stats_changed.emit()
	elif not starved:
		starved = true
		G.message.emit("SWARM: no qi left to run your designs -- they go quiet until you gather more (sit, or fight).")
		G.stats_changed.emit()


func rows() -> Array:
	## [name, bonus text, what it does] for the Mind page
	var C: Dictionary = data.get("channels", {})
	return [["Recovery", I18n.t("+%d%% qi while sitting, +%.2f health a second") % [int(round(channel("recovery") * 100)), channel("recovery_regen")], str(C.get("recovery", {}).get("desc", ""))],
		["Focus", "+%d%%" % int(round(channel("focus") * 100)), str(C.get("focus", {}).get("desc", ""))],
		["Adaptability", I18n.t("+%d%% skill growth") % int(round(channel("adaptability") * 100)), str(C.get("adaptability", {}).get("desc", ""))],
		["Connection", I18n.t("+%d%% insight and bonds") % int(round(channel("connection") * 100)), str(C.get("connection", {}).get("desc", ""))],
		["Honing", I18n.t("+%.1f%% damage, +%d%% strike speed, +%.1f%% telling blows, +%.2f s to parry and roll") % [channel("honing_damage") * 100, int(round(channel("honing_speed") * 100)),
			channel("honing_crit") * 100, channel("honing_timing")], str(C.get("honing", {}).get("desc", ""))]]
