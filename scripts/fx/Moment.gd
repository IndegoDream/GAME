extends Node
## Moments: do something nobody built a menu for (Robert, 2026-10-02:
## "allow for character free text moments for out of the norm play but it
## needs reciprocating"). Press T anywhere, say what you try -- "I carve a
## whistle from the goblin's bone", "I sing for the fishermen", "I climb the
## stalactite to see what glitters" -- and the world answers.
##
## The box's own model judges it against who you are (skills, realm, what
## you carry) and where you are (the floor, who's near, what's around), and
## proposes what happens. Game.apply_moment() then decides how MUCH: every
## gain is capped by your depth, nothing comes free (a reward on anything
## less than a clean success costs something), and a failure always teaches.
## When the model is down, a plain reading of what you wrote stands in.
## One moment every Game.MOMENT_COOLDOWN seconds.

const LLM := preload("res://scripts/core/LLMCall.gd")

var npc_name := "The world"
var _llm: Node


func one_shot() -> bool:
	## (the HUD's chat panel takes one line from you, then this answers once)
	return true


func _ready() -> void:
	_llm = LLM.new()
	add_child(_llm)


# ---- what's around you ------------------------------------------------------------

func context() -> Dictionary:
	var ctx := {"place": str(Game.current_level), "town": false, "depth": Game.depth, "names": [], "foes": [], "things": [],
		"companion": str(Game.companion.get("name", ""))}
	var tree := get_tree() if is_inside_tree() else null
	var player = tree.get_first_node_in_group("player") if tree else null
	var lvl = player.get_parent().get_node_or_null("Level") if player and player.get_parent() else null
	if lvl:
		ctx["place"] = str(lvl.def.get("name", Game.current_level))
		ctx["town"] = lvl.is_town()
		ctx["theme"] = str(lvl.def.get("theme", ""))
	if player and tree:
		var p: Vector3 = player.global_position
		for e in tree.get_nodes_in_group("enemy"):
			if is_instance_valid(e) and e.global_position.distance_to(p) < 14.0 and ctx["foes"].size() < 5:
				ctx["foes"].append(str(e.stats.get("name", "something")))
		for n in tree.get_nodes_in_group("interactable"):
			if not is_instance_valid(n) or n.global_position.distance_to(p) > 10.0:
				continue
			if "npc_name" in n and str(n.npc_name) != "" and ctx["names"].size() < 5:
				ctx["names"].append(str(n.npc_name))
			elif "kind" in n and ctx["things"].size() < 5:
				ctx["things"].append({"herb": "a plant worth picking", "gem": "a glittering vein", "fish": "fishing water"}.get(str(n.kind), "an ore vein"))
	if ctx["companion"] != "" and not (ctx["companion"] in ctx["names"]):
		ctx["names"].append(ctx["companion"])
	return ctx


func _skills_line() -> String:
	var rows := []
	for sid in Game.skill_defs:
		var l := Game.skill_level(str(sid))
		if l > 0:
			rows.append([l, "%s %d" % [str(sid), l]])
	rows.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	var out := []
	for r in rows.slice(0, 8):
		out.append(str(r[1]))
	return ", ".join(out) if out.size() > 0 else "nothing much yet"


func _carry_line() -> String:
	var ids: Array = Game.inventory.keys()
	ids.sort_custom(func(a, b): return Game.count(a) > Game.count(b))
	var out := []
	for id in ids.slice(0, 12):
		out.append("%s x%d (%s)" % [str(id), Game.count(id), Game.item_name(id)])
	return ", ".join(out) if out.size() > 0 else "nothing"


func prompt(action: String, ctx: Dictionary) -> Array:
	var allowed: Array = Game.moment_items()
	var near := []
	for id in allowed:
		near.append("%s (%s)" % [id, Game.item_name(id)])
	var recent := []
	for m in Game.moments.slice(maxi(0, Game.moments.size() - 4)):
		if m is Dictionary:
			recent.append("%s -> %s" % [m.get("what", ""), m.get("outcome", "")])
	var sys := ("You are the game master of a cultivation world (qi, realms, sects) where tiny machines called nanites make cultivation work. " +
		"The player does something the game has no button for. Judge it like a fair tabletop GM: is it plausible for THIS character, here, now? " +
		"Skill and realm make success likelier; reckless or impossible things fail. The world must answer in kind -- a reward has a price unless " +
		"it was a clean success, and a failure still teaches something. Never grant gear or treasures. Keep numbers modest. " +
		"Reply ONLY with JSON: {\"outcome\": \"success\" | \"partial\" | \"fail\", \"narration\": \"two or three vivid sentences, second person\", " +
		"\"effects\": {\"gold\": int (negative = lost), \"hp\": int (negative = hurt), \"qi\": int, \"items\": {item_id: count}, " +
		"\"consume\": {item_id the player carries: count}, \"skill_xp\": {skill_id: amount 5-40}, \"bond\": {name of someone present: -5..5}, " +
		"\"affinity\": {element: -3..3}}, \"journal\": \"one short line for their journal, or empty\"}. Leave out effects that don't apply.")
	var user := ("WHERE: %s%s, floor depth %d. %s%s%s\n" % [ctx.get("place", ""), " (a town)" if ctx.get("town", false) else "", int(ctx.get("depth", 0)),
			("Nearby people: " + ", ".join(ctx["names"]) + ". ") if ctx.get("names", []).size() > 0 else "",
			("Monsters near: " + ", ".join(ctx["foes"]) + ". ") if ctx.get("foes", []).size() > 0 else "",
			("Also here: " + ", ".join(ctx["things"]) + ". ") if ctx.get("things", []).size() > 0 else ""] +
		"WHO: %s, %s background. HP %d/%d, %d gold. Weapon: %s. Skills: %s.\n" % [Game.cultivation_label(),
			str(Game.BACKGROUNDS.get(Game.background, {}).get("name", "unknown")), Game.hp, Game.max_hp(), Game.gold,
			Game.item_name(Game.weapon) if Game.weapon != "" else "bare hands", _skills_line()] +
		"CARRYING: %s.\n" % _carry_line() +
		"ITEMS THE WORLD MAY GIVE (use these ids only): %s.\n" % ", ".join(near.slice(0, 45)) +
		"SKILL IDS: %s.\n" % ", ".join(Game.skill_defs.keys()) +
		(("RECENTLY THEY: " + "; ".join(recent) + ".\n") if recent.size() > 0 else "") +
		"WHAT THEY DO: " + action)
	return [{"role": "system", "content": sys}, {"role": "user", "content": user}]


# ---- doing it ------------------------------------------------------------------------

func say(text: String, cb: Callable) -> void:
	## (the same shape as talking to someone, so the HUD's chat panel can
	## carry it) -- cb(what happened).
	text = text.strip_edges().left(300)
	if text == "":
		return
	var wait := Game.moment_wait()
	if wait > 0.0:
		cb.call("(Not yet. Give it %d more seconds -- the world is still settling from the last thing you did.)" % int(ceil(wait)))
		return
	var ctx := context()
	_llm.ask(prompt(text, ctx), func(d): cb.call(resolve(text, ctx, d, randf())), 360, 0.85)


func resolve(text: String, ctx: Dictionary, d, roll: float) -> String:
	var r: Dictionary = d if d is Dictionary and d.has("outcome") else fallback(text, ctx, roll)
	var res: Dictionary = Game.apply_moment(r, ctx.get("names", []), text)
	var narr := str(r.get("narration", "")).strip_edges()
	if narr == "":
		narr = "You try it. The world notices."
	var lines: Array = res.get("lines", [])
	return narr + ("\n\n[" + ", ".join(lines) + "]" if lines.size() > 0 else "")


# ---- when the model can't answer: a plain reading of what you wrote ---------------------

const READINGS := [
	{"id": "cook", "words": ["cook", "roast", "campfire", "broth", "stew", "meal", "eat"], "skill": "survival"},
	{"id": "forage", "words": ["forage", "search", "scavenge", "look for", "dig", "gather", "collect", "rummage", "pick"], "skill": "survival"},
	{"id": "train", "words": ["train", "practice", "practise", "spar", "drill", "kata", "exercise", "form"], "skill": "weapon"},
	{"id": "still", "words": ["meditate", "pray", "breathe", "cultivate", "contemplate", "reflect", "listen"], "skill": "survival"},
	{"id": "steal", "words": ["steal", "pickpocket", "swipe", "rob", "pilfer", "snatch"], "skill": "dagger"},
	{"id": "perform", "words": ["sing", "dance", "perform", "story", "juggle", "busk", "play music", "flute"], "skill": "survival"},
	{"id": "help", "words": ["help", "give", "gift", "share", "tend", "comfort", "bandage", "carry"], "skill": "medicine"},
	{"id": "talk", "words": ["bargain", "haggle", "persuade", "charm", "flirt", "bribe", "intimidate", "threaten", "boast"], "skill": "survival"},
	{"id": "tame", "words": ["tame", "befriend", "feed", "pet", "whistle", "call"], "skill": "hunting"},
	{"id": "make", "words": ["carve", "whittle", "repair", "sharpen", "mend", "craft", "build", "fashion"], "skill": "craft"},
	{"id": "dare", "words": ["climb", "jump", "leap", "swim", "sneak", "hide", "explore", "scout", "dive", "crawl"], "skill": "survival"},
]


func reading(text: String) -> Dictionary:
	var t := text.to_lower()
	for r in READINGS:
		for w in r["words"]:
			if t.contains(str(w)):
				return r
	return {"id": "other", "words": [], "skill": "survival"}


func _skill_for(r: Dictionary) -> String:
	var sk := str(r.get("skill", "survival"))
	if sk == "weapon":
		return Game.weapon_skill()
	if sk == "craft":
		var best := "smithing"
		var bx := -1.0
		for sid in Game.skill_defs:
			if str(Game.skill_defs[sid].get("kind", "")) == "crafting" and float(Game.skills.get(sid, 0.0)) > bx:
				bx = float(Game.skills.get(sid, 0.0))
				best = str(sid)
		return best
	return sk


func _pick_find(roll: float) -> String:
	var mats := Game.moment_items().filter(func(i): return str(Game.items[i].get("type", "")) == "material")
	if mats.is_empty():
		return "spirit_herb"
	mats.sort_custom(func(a, b): return int(Game.items[a].get("value", 0)) > int(Game.items[b].get("value", 0)))
	var top: Array = mats.slice(0, mini(8, mats.size()))
	return str(top[int(roll * 997.0) % top.size()])


func fallback(text: String, ctx: Dictionary, roll: float) -> Dictionary:
	var r := reading(text)
	var sk := _skill_for(r)
	var lvl := Game.skill_level(sk)
	var chance := clampf(0.4 + 0.035 * lvl, 0.15, 0.9)
	var outcome := "success" if roll < chance * 0.6 else ("partial" if roll < chance else "fail")
	var d := maxi(int(ctx.get("depth", Game.depth)), 1)
	var names: Array = ctx.get("names", [])
	var who := str(names[0]) if names.size() > 0 else ""
	var town := bool(ctx.get("town", false))
	var e := {"skill_xp": {sk: 10 + 3 * d}}
	var narr := ""
	match str(r["id"]):
		"cook":
			if Game.count("raw_meat") > 0:
				e["consume"] = {"raw_meat": 1}
				e["hp"] = int(Game.max_hp() * 0.2)
				narr = "You coax a small fire out of what's around and cook. It's not good, exactly, but it's hot and it stays down."
			else:
				e["hp"] = int(Game.max_hp() * 0.08)
				narr = "There's nothing much to cook, but you boil what you can find and it helps a little."
		"forage":
			e["items"] = {_pick_find(roll): 2 if outcome == "success" else 1}
			narr = "You go over the ground slowly, the way someone taught you once, and turn up something worth keeping."
		"train":
			e["skill_xp"] = {sk: 18 + 4 * d}
			e["hp"] = -int(Game.max_hp() * 0.06)
			narr = "You run the forms until your arms burn. It hurts. It's supposed to."
		"still":
			e["qi"] = int(Game.qi_to_next() * 0.06)
			narr = "You let the noise of the place fall away and breathe with it. The nanites hum a little brighter."
		"steal":
			if who != "" and town:
				e["gold"] = (5 + 3 * d) if outcome != "fail" else -(5 + 2 * d)
				e["bond"] = {who: -2 if outcome != "fail" else -5}
				narr = "Quick hands -- " + ("and nobody the wiser, almost." if outcome != "fail" else "but not quick enough. %s saw. You pay for it, one way or another." % who)
			else:
				e["gold"] = 3 + d
				narr = "There's nobody here to steal from but the dead. You take what they won't miss."
		"perform":
			if town:
				e["gold"] = 4 + 2 * d
				if who != "":
					e["bond"] = {who: 2}
				narr = "A few people stop to listen. A few coins land at your feet."
			else:
				e["qi"] = int(Game.qi_to_next() * 0.03)
				e["hp"] = -int(Game.max_hp() * 0.05)
				narr = "Your voice carries further down here than you meant it to. Something answers, far off -- you cut it short."
		"help":
			if who != "":
				e["bond"] = {who: 4}
				if Game.count("healing_salve") > 0:
					e["consume"] = {"healing_salve": 1}
				else:
					e["gold"] = -mini(5 + d, Game.gold)
				narr = "You help %s without being asked. It costs you something; it's remembered." % who
			else:
				narr = "There's no one here to help -- so you help the place: clear a fallen beam, mark a pit for whoever comes next."
		"talk":
			if who != "":
				e["bond"] = {who: 2 if outcome != "fail" else -3}
				e["gold"] = (3 + d) if outcome == "success" else 0
				narr = "You talk; %s listens, %s." % [who, "and something shifts in your favour" if outcome != "fail" else "and doesn't like what they hear"]
			else:
				narr = "You say it to the dark. The dark doesn't argue."
		"tame":
			if Game.count("raw_meat") > 0:
				e["consume"] = {"raw_meat": 1}
			narr = "You hold still and let it come to you. It takes the offering, and watches you after."
		"make":
			e["items"] = {"healing_salve": 1} if sk in ["medicine", "alchemy"] else {}
			narr = "You work at it with what's to hand. Not your best work -- but your hands learn from it."
		"dare":
			e["gold"] = 4 + 3 * d
			e["hp"] = -int(Game.max_hp() * 0.1)
			narr = "You go where the path doesn't. It's harder than it looked; there's a reason, and a little treasure, at the top."
		_:
			narr = "You try it. Nothing in the world is built for it -- but you're a little wiser for having tried."
	if outcome == "fail":
		narr += " It doesn't go the way you hoped."
	return {"outcome": outcome, "narration": narr, "effects": e, "journal": ""}
