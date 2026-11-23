extends "res://scripts/systems/GameSystem.gd"
## Round 188: the guild and its group chat. Robert, 2026-11-08: "We want the game to be fun and addicting. Have group
## chat guilds that can give some support but not push the balance, or be able to start our own sect and own guild."
## He chose: NPC guildmates now and real players in the same chat once online is live; gifts and fair trades, help
## requests, and guild tasks that pay in looks.
##
## JOIN one of three guilds (data/fellowship.json) or FOUND your own (a name, a tag, a motto, a colour; 500 gold).
## THE CHAT: guildmates talk -- each has a way of talking (veteran, cheerful, gruff, studious, joker, new, crafter) --
## greet you, react to what you do (a floor master down, a breakthrough, a death, a find), ask each other questions
## and answer them with real tips (Lore.tips(): true about where you are). You can talk back (Enter, or the Guild page);
## with the box's model on, a guildmate answers in their own voice. Online (Online.gd), the same chat carries real
## players in the same guild (server channel "guild").
## SUPPORT, never power:
##   gifts       now and then a guildmate sends a few of a material you have ALREADY found (a daily cap by realm)
##   trades      a swap at the shops' own prices (within 5%) -- your surplus for something you're short of
##   requests    ask for up to 10 of a material you've found; you pay what a shop would; it arrives in 8-20 min
##   tasks       four group goals a week (your deeds plus your guildmates'); renown buys titles, crests, emblems and
##               dressing for your sect hall -- looks only (effects() is always empty)

signal chat_added(line: Dictionary)

var data := {}
var g := {}                       # {} = in no guild; else {"kind": "npc"|"own", "id", "name", "tag", "motto", "color", "members", "level", "key"}
var chat: Array = []              # [{"id", "t", "ch": "guild"|"sect"|"sys", "who", "text", "kind", "offer"?}]
var next_id := 1
var renown := 0
var owned := {}                   # shop id -> true
var title := ""                   # a shop id (kind title) or ""
var crest := ""                   # a shop id (kind crest) or ""
var emblem := ""                  # a shop id (kind emblem) or ""
var requests: Array = []          # [{"id", "item", "n", "who", "due", "paid"}]
var trades: Array = []            # [{"id", "who", "give": [item, n], "get": [item, n], "until"}]  give = yours, get = theirs
var day := ""
var gift_value_today := 0
var week := ""
var tasks: Array = []             # [{"id", "text", "event", "goal", "have", "renown", "done"}]
var left_day := ""
var last_seen := 0.0
var unread := 0
var time_shift := 0.0             # (tests) move the clock
var rng := RandomNumberGenerator.new()
var _amb_t := 60.0
var _sim_t := 0.0
var _last_place := ""


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/fellowship.json")
	rng.randomize()


func reset() -> void:
	g = {}
	chat = []
	next_id = 1
	renown = 0
	owned = {}
	title = ""
	crest = ""
	emblem = ""
	requests = []
	trades = []
	day = ""
	gift_value_today = 0
	week = ""
	tasks = []
	left_day = ""
	last_seen = 0.0
	unread = 0
	_amb_t = 60.0


func save_state() -> Dictionary:
	return {"g": g, "chat": chat.slice(maxi(0, chat.size() - int(lim("chat_keep", 160)))), "next_id": next_id, "renown": renown, "owned": owned,
		"title": title, "crest": crest, "emblem": emblem, "requests": requests, "trades": trades, "day": day, "gift_value_today": gift_value_today,
		"week": week, "tasks": tasks, "left_day": left_day, "last_seen": now()}


func load_state(d: Dictionary) -> void:
	reset()
	g = d.get("g", {}) if d.get("g", {}) is Dictionary else {}
	chat = d.get("chat", []) if d.get("chat", []) is Array else []
	next_id = int(d.get("next_id", chat.size() + 1))
	renown = int(d.get("renown", 0))
	owned = d.get("owned", {}) if d.get("owned", {}) is Dictionary else {}
	title = str(d.get("title", ""))
	crest = str(d.get("crest", ""))
	emblem = str(d.get("emblem", ""))
	requests = d.get("requests", []) if d.get("requests", []) is Array else []
	trades = d.get("trades", []) if d.get("trades", []) is Array else []
	day = str(d.get("day", ""))
	gift_value_today = int(d.get("gift_value_today", 0))
	week = str(d.get("week", ""))
	tasks = d.get("tasks", []) if d.get("tasks", []) is Array else []
	left_day = str(d.get("left_day", ""))
	last_seen = float(d.get("last_seen", 0.0))
	for r in requests:                         # (a saved request whose item has gone from the game is dropped)
		if not G.items.has(str(r.get("item", ""))):
			requests.erase(r)


func now() -> float:
	return G._now() + time_shift


func lim(k: String, dflt = 0.0):
	return data.get("limits", {}).get(k, dflt)


func effects() -> Array:
	return []                                  # a guild never adds power (tools/fellowship_check.gd holds this)


# ---- the guild ---------------------------------------------------------------------------------------------------

func in_guild() -> bool:
	return not g.is_empty()


func guild_defs() -> Array:
	return data.get("guilds", [])


func guild_def(gid: String) -> Dictionary:
	for d in guild_defs():
		if str(d.get("id", "")) == gid:
			return d
	return {}


func _member(nm: String, persona: String, role: String) -> Dictionary:
	return {"name": nm, "persona": persona, "role": role, "realm": maxi(0, G.realm + rng.randi_range(-1, 1)), "online": false}


func join_check(gid: String) -> String:
	if in_guild():
		return I18n.t("You already belong to the %s. Leave it first.") % str(g.get("name", ""))
	if guild_def(gid).is_empty():
		return I18n.t("There's no such guild.")
	if left_day == G.today():
		return I18n.t("You left a guild today. Give it a day.")
	return ""


func join(gid: String) -> String:
	var why := join_check(gid)
	if why != "":
		return why
	var d := guild_def(gid)
	var ms := []
	for m in d.get("members", []):
		ms.append(_member(str(m[0]), str(m[1]), str(m[2])))
	g = {"kind": "npc", "id": gid, "name": str(d.get("name", gid)), "tag": str(d.get("tag", "")), "motto": str(d.get("motto", "")),
		"color": d.get("color", [1, 1, 1]), "members": ms, "level": 1, "key": "npc:" + gid, "since": G.today()}
	_new_week(true)
	sys_line(I18n.t("You join the %s.") % g["name"])
	_say_random("welcome_join")
	G.log_event("fellowship_join", {"guild": gid})
	_online_key()
	G.stats_changed.emit()
	return I18n.t("GUILD: you join the %s. Press Enter to talk in the guild chat.") % g["name"]


func found_check(nm: String, tag: String) -> String:
	if in_guild():
		return I18n.t("You already belong to the %s. Leave it first.") % str(g.get("name", ""))
	if nm.strip_edges().length() < 3 or nm.strip_edges().length() > 28:
		return I18n.t("A guild's name needs 3 to 28 letters.")
	var t := tag.strip_edges().to_upper()
	if t.length() < 2 or t.length() > 4 or not _alnum(t):
		return I18n.t("A tag is 2 to 4 letters or digits.")
	for d in guild_defs():
		if str(d.get("name", "")).to_lower() == nm.strip_edges().to_lower():
			return I18n.t("That name is taken.")
	if G.gold < int(lim("found_guild_gold", 500)):
		return I18n.t("Founding a guild costs %d gold (charter, seal, a hall to meet in).") % int(lim("found_guild_gold", 500))
	if left_day == G.today():
		return I18n.t("You left a guild today. Give it a day.")
	return ""


static func _alnum(s: String) -> bool:
	for c in s:
		if not ((c >= "A" and c <= "Z") or (c >= "0" and c <= "9")):
			return false
	return s.length() > 0


func found(nm: String, tag: String, motto: String = "", color_i: int = 0) -> String:
	var why := found_check(nm, tag)
	if why != "":
		return why
	G.remove_item("gold", int(lim("found_guild_gold", 500)))
	var cols: Array = data.get("sect", {}).get("colors", [[1, 0.8, 0.4]])
	var ms := []
	var used := {}
	var personas := ["vet", "cheer", "crafter", "joker", "scholar", "gruff"]
	for i in 3:
		var nm2 := _fresh_name(used)
		used[nm2] = true
		ms.append(_member(nm2, personas[i], "officer" if i == 0 else "member"))
	var code := "%04X" % (hash(nm + tag + str(now())) & 0xFFFF)
	g = {"kind": "own", "id": "own", "name": nm.strip_edges(), "tag": tag.strip_edges().to_upper(), "motto": motto.strip_edges().left(80),
		"color": cols[clampi(color_i, 0, cols.size() - 1)], "members": ms, "level": 1, "key": "own:%s:%s" % [tag.strip_edges().to_upper(), code],
		"since": G.today(), "founder": true}
	owned["title_founder"] = true
	_new_week(true)
	sys_line(I18n.t("You found the %s [%s].") % [g["name"], g["tag"]])
	add_line("guild", "", _fmt(_pick(data.get("lines", {}).get("found_guild", [""])), {"g": g["name"], "m": ms[0]["name"], "m2": ms[1]["name"], "m3": ms[2]["name"]}), "sys")
	G.log_event("fellowship_found", {"name": g["name"]})
	_online_key()
	G.stats_changed.emit()
	return I18n.t("GUILD: the %s is founded. Its join key is %s.") % [g["name"], g["key"]]


func leave() -> String:
	if not in_guild():
		return I18n.t("You belong to no guild.")
	var nm := str(g.get("name", ""))
	G.log_event("fellowship_leave", {"guild": str(g.get("id", ""))})
	g = {}
	tasks = []
	requests = []
	trades = []
	left_day = G.today()
	sys_line(I18n.t("You leave the %s.") % nm)
	_online_key()
	G.stats_changed.emit()
	return I18n.t("You leave the %s. Renown and looks stay yours.") % nm


func guild_level() -> int:
	var lv := 1
	var steps: Array = lim("guild_level_renown", [0, 150, 450])
	for i in steps.size():
		if renown >= int(steps[i]):
			lv = i + 1
	return lv


func member_cap() -> int:
	var caps: Array = lim("members_by_level", [6, 9, 12])
	return int(caps[clampi(guild_level() - 1, 0, caps.size() - 1)])


func recruits() -> Array:
	## your own guild: who answered the notice today (three a day; seeded by the day, so it doesn't reroll)
	if g.get("kind", "") != "own":
		return []
	var r := RandomNumberGenerator.new()
	r.seed = hash("recruits|" + G.today() + "|" + str(g.get("key", "")))
	var used := {}
	for m in g.get("members", []):
		used[str(m["name"])] = true
	var out := []
	var personas: Array = data.get("personas", ["cheer"])
	for i in 3:
		var nm := ""
		for k in 20:
			var c: String = data.get("names", ["Ash"])[r.randi() % data.get("names", ["Ash"]).size()]
			if not used.has(c):
				nm = c
				break
		if nm == "":
			continue
		used[nm] = true
		out.append({"name": nm, "persona": str(personas[r.randi() % personas.size()])})
	return out


func recruit(nm: String) -> String:
	if g.get("kind", "") != "own":
		return I18n.t("Only a guild you founded takes on recruits.")
	if (g.get("members", []) as Array).size() >= member_cap():
		return I18n.t("The guild hall is full (%d). More renown, a bigger hall.") % member_cap()
	for c in recruits():
		if str(c["name"]) == nm:
			(g["members"] as Array).append(_member(nm, str(c["persona"]), "member"))
			add_line("guild", "", _fmt(_pick(data.get("lines", {}).get("recruit", [""])), {"m": nm, "g": g["name"]}), "sys")
			G.stats_changed.emit()
			return I18n.t("%s joins the guild.") % nm
	return I18n.t("They've moved on.")


func dismiss(nm: String) -> String:
	if g.get("kind", "") != "own":
		return ""
	for m in g.get("members", []):
		if str(m["name"]) == nm:
			(g["members"] as Array).erase(m)
			sys_line(I18n.t("%s leaves the guild.") % nm)
			G.stats_changed.emit()
			return I18n.t("%s leaves the guild.") % nm
	return ""


func _fresh_name(used: Dictionary) -> String:
	var pool: Array = data.get("names", ["Ash"])
	for i in 40:
		var c := str(pool[rng.randi() % pool.size()])
		if not used.has(c):
			return c
	return "Guildmate %d" % rng.randi_range(2, 99)


# ---- the chat ----------------------------------------------------------------------------------------------------

func add_line(ch: String, who: String, text: String, kind: String = "line", extra: Dictionary = {}) -> Dictionary:
	if text.strip_edges() == "":
		return {}
	var line := {"id": next_id, "t": now(), "ch": ch, "who": who, "text": text, "kind": kind}
	line.merge(extra)
	next_id += 1
	chat.append(line)
	var keep := int(lim("chat_keep", 160))
	if chat.size() > keep + 40:
		chat = chat.slice(chat.size() - keep)
	if kind != "you":
		unread += 1
	chat_added.emit(line)
	return line


func sys_line(text: String) -> void:
	add_line("guild", "", text, "sys")


func lines(ch: String = "", n: int = 60) -> Array:
	var out := []
	for i in range(chat.size() - 1, -1, -1):
		var l: Dictionary = chat[i]
		if ch == "" or str(l.get("ch", "")) == ch or str(l.get("ch", "")) == "sys":
			out.push_front(l)
			if out.size() >= n:
				break
	return out


func _pick(arr) -> String:
	if not (arr is Array) or (arr as Array).is_empty():
		return ""
	return I18n.t(str(arr[rng.randi() % arr.size()]))


func _fmt(s: String, extra: Dictionary = {}) -> String:
	var d := {"p": me(), "g": str(g.get("name", "")), "realm": G.realm_name(), "place": _place_name(G.current_level),
		"foe": _some_foe(), "item": _some_item_name(), "tip": _tip()}
	d.merge(extra, true)
	return s.format(d)


func me() -> String:
	return G.char_name if str(G.char_name) != "" else I18n.t("friend")


func member_names(online_only: bool = false) -> Array:
	var out := []
	for m in g.get("members", []):
		if not online_only or bool(m.get("online", false)):
			out.append(str(m["name"]))
	return out


func _member_by(persona: String) -> Dictionary:
	var ms: Array = g.get("members", [])
	var pool := ms.filter(func(m): return str(m.get("persona", "")) == persona)
	if pool.is_empty():
		pool = ms
	return pool[rng.randi() % pool.size()] if pool.size() > 0 else {}


func _any_member(not_name: String = "") -> Dictionary:
	var ms: Array = (g.get("members", []) as Array).filter(func(m): return str(m["name"]) != not_name)
	return ms[rng.randi() % ms.size()] if ms.size() > 0 else {}


func _say_random(key: String, extra: Dictionary = {}) -> void:
	var m := _any_member()
	if m.is_empty():
		return
	add_line("guild", str(m["name"]), _fmt(_pick(data.get("lines", {}).get(key, [])), extra))


func _tip() -> String:
	## a true tip: about where you are now if the Lore system has one, else one of the loading screen's
	var LO = G.sys("lore")
	if LO != null and LO.has_method("tips"):
		var ts: Array = LO.tips()
		if ts.size() > 0:
			return str(ts[rng.randi() % mini(ts.size(), 3)].get("text", ""))
	var lt: Array = preload("res://scripts/ui/Loading.gd").TIPS
	var t := str(lt[rng.randi() % lt.size()])
	if "test kit" in t:
		t = str(lt[0])
	return I18n.t(t)


func _some_foe() -> String:
	var ks: Array = G.kills.keys() if G.kills is Dictionary else []
	if ks.is_empty():
		return I18n.t("goblin")
	var e: String = ks[rng.randi() % ks.size()]
	return I18n.t(str(G.enemies.get(e, {}).get("name", e.capitalize())))


func _some_item_name() -> String:
	var pool := allowed_items()
	if pool.is_empty():
		return G.item_name("spirit_herb")
	return G.item_name(str(pool[rng.randi() % pool.size()]))


func _place_name(lid: String) -> String:
	var lv = G.get_tree().get_first_node_in_group("level") if G.is_inside_tree() else null
	if lv != null and str(lv.level_id) == lid and lv.def.has("name"):
		return I18n.t(str(lv.def["name"]))
	if lid.begins_with("floor") and lid.substr(5).is_valid_int():
		return I18n.t("Floor %d") % int(lid.substr(5))
	return lid.replace("_", " ").replace(":", " ").capitalize()


func say(text: String) -> void:
	## you, in the guild chat
	var t := text.strip_edges().left(200)
	if t == "" or not in_guild():
		return
	add_line("guild", me(), t, "you")
	unread = 0
	if G.online != null and G.online.has_method("is_connected_ok") and G.online.is_connected_ok():
		G.online.send({"t": "chat", "ch": "guild", "text": t})
	_answer(t)


func _answer(t: String) -> void:
	var low := t.to_lower()
	var kind := "other"
	var words := {"hello": ["hi", "hello", "hey", "o/", "morning", "evening", "yo"], "thanks": ["thank", "thx", "ty"], "gg": ["gg"],
		"laugh": ["lol", "haha", "lmao", "rofl", ":d"], "bye": ["bye", "cya", "later", "gn", "good night"],
		"help": ["?", "how", "where", "what", "help", "tip", "why"]}
	for k in ["help", "thanks", "gg", "bye", "hello", "laugh"]:
		for w in words[k]:
			if (w.length() <= 2 and (low == w or low.begins_with(w + " ") or low.ends_with(" " + w) or (" " + w + " ") in low)) or (w.length() > 2 and w in low):
				kind = k
				break
		if kind != "other":
			break
	var who := _member_by("vet") if kind == "help" else _any_member()
	if who.is_empty():
		return
	if kind == "other" and (str(G.llm_url) != "" or G.llm_override.is_valid()):
		_voice_reply(who, t)                    # the box's model on: they answer in their own words
	else:
		_queue(str(who["name"]), _fmt(_pick(data.get("lines", {}).get("reply", {}).get(kind, []))), rng.randf_range(1.5, 4.0))
	if kind in ["hello", "gg", "laugh"] and (g.get("members", []) as Array).size() > 2 and rng.randf() < 0.6:
		var w2 := _any_member(str(who["name"]))
		_queue(str(w2["name"]), _fmt(_pick(data.get("lines", {}).get("reply", {}).get(kind, []))), rng.randf_range(3.0, 7.0))


var _voice: Node = null


func _voice_reply(who: Dictionary, text: String) -> void:
	if _voice == null:
		_voice = preload("res://scripts/core/Voice.gd").new()
		_voice.name = "GuildVoice"
		add_child(_voice)
	var nm := str(who["name"])
	_voice.npc_name = nm
	_voice.persona_text = I18n.t("%s, a %s member of the %s guild (motto: %s). You are chatting in the guild's group chat, so keep it short and casual, like a message.") % [
		nm, I18n.t(str(data.get("persona_names", {}).get(str(who.get("persona", "")), "friendly"))), str(g.get("name", "")), str(g.get("motto", ""))]
	_voice.situation = I18n.t("The person writing is your guildmate %s.") % me()
	_voice.say(text, func(reply: String):
		if in_guild() and reply.strip_edges() != "" and not reply.begins_with("("):
			add_line("guild", nm, reply.strip_edges().left(240))
		elif in_guild():
			add_line("guild", nm, _fmt(_pick(data.get("lines", {}).get("reply", {}).get("other", [])))))


var _queued: Array = []          # [[at_seconds, who, text]] -- replies arrive after a moment, like people typing


func _queue(who: String, text: String, delay: float) -> void:
	_queued.append([_clock + delay, who, text])


var _clock := 0.0


func online_line(from: String, text: String) -> void:
	## a real player in the same guild, through the server
	if not in_guild() or from == me():
		return
	add_line("guild", from, text, "online")


func online_key() -> String:
	return str(g.get("key", ""))


func _online_key() -> void:
	if G.online != null and G.online.has_method("is_connected_ok") and G.online.is_connected_ok():
		G.online.send({"t": "guild_key", "key": online_key()})


# ---- the day, the week, the clock --------------------------------------------------------------------------------

func _new_day() -> void:
	if day == G.today():
		return
	day = G.today()
	gift_value_today = 0


func week_key() -> String:
	var jd := int(now() / 86400.0)
	return "w%d" % int((jd + 3) / 7)          # weeks start on Monday (1970-01-01 was a Thursday)


func _new_week(force: bool = false) -> void:
	var wk := week_key()
	if not force and week == wk:
		return
	week = wk
	tasks = []
	var all: Array = data.get("tasks", [])
	if all.is_empty() or not in_guild():
		return
	var r := RandomNumberGenerator.new()
	r.seed = hash(wk + "|" + str(g.get("key", "")))
	var idx := range(all.size())
	for i in range(idx.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp = idx[i]
		idx[i] = idx[j]
		idx[j] = tmp
	var size_k := 0.7 + 0.15 * float((g.get("members", []) as Array).size()) / 6.0
	for i in mini(4, idx.size()):
		var t: Dictionary = all[idx[i]]
		var goal := maxi(1, int(round(float(t.get("goal", 10)) * size_k)))
		tasks.append({"id": str(t["id"]), "text": I18n.t(str(t["text"])) % goal, "event": str(t["event"]), "goal": goal, "have": 0.0,
			"renown": int(t.get("renown", 30)), "done": false})


func gift_cap() -> int:
	return int(lim("gift_value_day_base", 40)) + int(lim("gift_value_day_per_realm", 40)) * G.realm


func item_value_cap() -> int:
	return mini(int(lim("item_value_base", 30)) + int(lim("item_value_per_realm", 15)) * G.realm, int(lim("item_value_cap", 120)))


func allowed_items() -> Array:
	## what a guildmate may give, swap or fetch: a material you have FOUND before, worth no more than your realm's cap
	var out := []
	var cap := item_value_cap()
	for id in G.journal.get("items", {}):
		var d: Dictionary = G.items.get(str(id), {})
		if str(d.get("type", "")) == "material" and int(d.get("value", 0)) > 0 and int(d.get("value", 0)) <= cap and not d.has("heirloom") and not d.has("quest"):
			out.append(str(id))
	out.sort()
	return out


func tick(delta: float) -> void:
	_clock += delta
	for q in _queued.duplicate():
		if _clock >= float(q[0]):
			_queued.erase(q)
			if in_guild():
				add_line("guild", str(q[1]), str(q[2]))
	if not in_guild():
		return
	_sim_t -= delta
	if _sim_t <= 0.0:
		_sim_t = 5.0
		_new_day()
		_new_week()
		_deliver()
		_expire_trades()
		_members_work(5.0)
	_amb_t -= delta
	if _amb_t <= 0.0:
		var a: Array = lim("ambient_seconds", [70, 150])
		_amb_t = rng.randf_range(float(a[0]), float(a[1]))
		_ambient()


func _ambient() -> void:
	var r := rng.randf()
	if r < 0.12 and not maybe_gift().is_empty():
		return
	if r >= 0.12 and r < 0.2 and not offer_trade().is_empty():
		return
	if r >= 0.2 and r < 0.32:
		var nb := _member_by("newbie")
		var vet := _member_by("vet")
		if not nb.is_empty() and not vet.is_empty() and str(nb["name"]) != str(vet["name"]):
			add_line("guild", str(nb["name"]), _fmt(_pick(data.get("lines", {}).get("ambient", {}).get("newbie", []))))
			_queue(str(vet["name"]), _fmt(_pick(data.get("lines", {}).get("answer", [])), {"m": str(nb["name"])}), rng.randf_range(4.0, 9.0))
			return
	# (round 190: a gift or trade with nothing to give, or no newbie and veteran, falls through to plain talk --
	#  the guild never goes quiet for a whole stretch by chance)
	var m := _any_member()
	if m.is_empty():
		return
	var pool: Array = data.get("lines", {}).get("ambient", {}).get(str(m.get("persona", "cheer")), [])
	add_line("guild", str(m["name"]), _fmt(_pick(pool)))


func on_event(kind: String, d: Dictionary) -> void:
	if not in_guild():
		return
	for t in tasks:
		if not bool(t.get("done", false)) and str(t.get("event", "")) == kind:
			_task_add(t, 1.0)
	var key := ""
	var extra := {}
	match kind:
		"boss_kill":
			key = "boss_kill"
			extra["foe"] = I18n.t(str(G.enemies.get(str(d.get("type", d.get("boss", ""))), {}).get("name", I18n.t("floor master"))))
		"breakthrough":
			key = "breakthrough"
		"levelup":
			key = "levelup" if rng.randf() < 0.35 else ""
		"death":
			key = "death"
		"treasure", "rare_find":
			key = "treasure"
		"floor_cleared":
			key = "floor_cleared" if rng.randf() < 0.5 else ""
		"craft":
			if str(d.get("quality", "")) in ["fine", "superior", "masterwork"] and rng.randf() < 0.5:
				key = "craft_fine"
		"enter_level":
			var lid := str(d.get("level", d.get("id", G.current_level)))
			if lid != _last_place and int(G.journal.get("places", {}).get(lid, {}).get("visits", 2)) <= 1 and rng.randf() < 0.7:
				key = "enter_new"
				extra["place"] = _place_name(lid)
			_last_place = lid
	if key == "":
		return
	var m := _any_member()
	if m.is_empty():
		return
	_queue(str(m["name"]), _fmt(_pick(data.get("lines", {}).get("react", {}).get(key, [])), extra), rng.randf_range(2.0, 6.0))
	if key in ["boss_kill", "breakthrough"] and (g.get("members", []) as Array).size() > 2:
		var m2 := _any_member(str(m["name"]))
		_queue(str(m2["name"]), _fmt(_pick(data.get("lines", {}).get("reply", {}).get("gg", []))), rng.randf_range(6.0, 11.0))


func welcome_back() -> void:
	## once when a save is loaded in play: a greeting, and what came in while you were away
	if not in_guild():
		return
	_new_day()
	_new_week()
	_deliver()
	if now() - last_seen > 600.0:
		_say_random("greet")
	last_seen = now()


# ---- support: gifts, trades, requests ----------------------------------------------------------------------------

func maybe_gift() -> Dictionary:
	_new_day()
	var pool := allowed_items()
	if pool.is_empty():
		return {}
	var room := gift_cap() - gift_value_today
	var id: String = pool[rng.randi() % pool.size()]
	var v := maxi(1, int(G.items[id].get("value", 1)))
	var n := mini(rng.randi_range(2, 6), room / v)
	if n <= 0:
		return {}
	var m := _any_member()
	if m.is_empty():
		return {}
	gift_value_today += n * v
	G.add_item(id, n, false)
	add_line("guild", str(m["name"]), _fmt(_pick(data.get("lines", {}).get("gift", [])), {"m": str(m["name"]), "n": n, "item": G.item_name(id)}), "gift",
		{"item": id, "n": n})
	G.log_event("fellowship_gift", {"item": id, "n": n, "value": n * v})
	return {"item": id, "n": n, "value": n * v}


func offer_trade() -> Dictionary:
	## your surplus (20+) of one found material for theirs, at the shops' own prices
	if trades.size() >= 2:
		return {}
	var pool := allowed_items()
	var mine := pool.filter(func(i): return G.count(i) >= 20)
	var theirs := pool.filter(func(i): return G.count(i) < 10)
	if mine.is_empty() or theirs.is_empty():
		return {}
	var a: String = mine[rng.randi() % mine.size()]
	var b: String = theirs[rng.randi() % theirs.size()]
	if a == b:
		return {}
	var va := int(G.items[a].get("value", 1))
	var vb := int(G.items[b].get("value", 1))
	var best := []
	for nb in range(1, 11):                    # the fairest whole numbers: their n2 of b for your n1 of a
		var n1 := int(round(float(nb * vb) / float(va)))
		if n1 < 1 or n1 > mini(G.count(a), 30):
			continue
		var gap := absf(float(n1 * va - nb * vb)) / float(maxi(1, nb * vb))
		if best.is_empty() or gap < float(best[2]):
			best = [n1, nb, gap]
	if best.is_empty() or float(best[2]) > float(lim("trade_fair", 0.05)):
		return {}
	var m := _any_member()
	if m.is_empty():
		return {}
	var tr := {"id": next_id, "who": str(m["name"]), "give": [a, int(best[0])], "get": [b, int(best[1])], "until": now() + 1800.0}
	trades.append(tr)
	add_line("guild", str(m["name"]), _fmt(_pick(data.get("lines", {}).get("trade", [])), {"m": str(m["name"]), "n1": int(best[0]), "item1": G.item_name(a),
		"n2": int(best[1]), "item2": G.item_name(b)}), "trade", {"trade": tr["id"]})
	return tr


func trade_value_gap(tr: Dictionary) -> float:
	var give_v := float(G.items.get(str(tr["give"][0]), {}).get("value", 0)) * float(tr["give"][1])
	var get_v := float(G.items.get(str(tr["get"][0]), {}).get("value", 0)) * float(tr["get"][1])
	return absf(give_v - get_v) / maxf(1.0, get_v)


func accept_trade(tid: int) -> String:
	for tr in trades:
		if int(tr["id"]) == tid:
			trades.erase(tr)
			var a := str(tr["give"][0])
			var n1 := int(tr["give"][1])
			if G.count(a) < n1:
				return I18n.t("You don't have %d × %s any more.") % [n1, G.item_name(a)]
			G.remove_item(a, n1)
			G.add_item(str(tr["get"][0]), int(tr["get"][1]), false)
			sys_line(I18n.t("Traded %d × %s for %d × %s with %s.") % [n1, G.item_name(a), int(tr["get"][1]), G.item_name(str(tr["get"][0])), tr["who"]])
			G.log_event("fellowship_trade", {"give": tr["give"], "get": tr["get"]})
			return I18n.t("Done -- %d × %s for %d × %s.") % [n1, G.item_name(a), int(tr["get"][1]), G.item_name(str(tr["get"][0]))]
	return I18n.t("That offer is gone.")


func decline_trade(tid: int) -> void:
	for tr in trades:
		if int(tr["id"]) == tid:
			trades.erase(tr)
			_queue(str(tr["who"]), I18n.t("No worries."), 2.0)
			return


func _expire_trades() -> void:
	for tr in trades.duplicate():
		if float(tr.get("until", 0.0)) < now():
			trades.erase(tr)


func request_price(id: String, n: int) -> int:
	return int(ceil(float(G.items.get(id, {}).get("value", 0)) * float(n) * float(lim("request_price_mult", 2.0))))


func request_check(id: String, n: int) -> String:
	if not in_guild():
		return I18n.t("Join a guild first.")
	if not id in allowed_items():
		return I18n.t("Guildmates fetch only what you've found yourself, up to your realm's worth.")
	if n < 1 or n > int(lim("request_qty_max", 10)):
		return I18n.t("Ask for 1 to %d at a time.") % int(lim("request_qty_max", 10))
	if requests.size() >= int(lim("request_open_max", 3)):
		return I18n.t("Three asks are already out. Wait for one to come in.")
	if G.gold < request_price(id, n):
		return I18n.t("That costs %d gold -- what a shop would ask.") % request_price(id, n)
	return ""


func request(id: String, n: int) -> String:
	var why := request_check(id, n)
	if why != "":
		return why
	var price := request_price(id, n)
	G.remove_item("gold", price)
	var who := _member_by("crafter") if rng.randf() < 0.5 else _any_member()
	var mins: Array = lim("request_minutes", [8, 20])
	requests.append({"id": next_id, "item": id, "n": n, "who": str(who.get("name", "")), "due": now() + rng.randf_range(float(mins[0]), float(mins[1])) * 60.0, "paid": price})
	add_line("guild", str(who.get("name", "")), _fmt(_pick(data.get("lines", {}).get("request_taken", [])), {"m": str(who.get("name", "")), "n": n, "item": G.item_name(id)}))
	G.log_event("fellowship_request", {"item": id, "n": n, "paid": price})
	return I18n.t("Asked the guild for %d × %s (%d gold paid).") % [n, G.item_name(id), price]


func _deliver() -> void:
	for r in requests.duplicate():
		if float(r.get("due", 0.0)) <= now():
			requests.erase(r)
			G.add_item(str(r["item"]), int(r["n"]), false)
			add_line("guild", str(r["who"]), _fmt(_pick(data.get("lines", {}).get("request_done", [])), {"m": str(r["who"]), "n": int(r["n"]), "item": G.item_name(str(r["item"]))}), "gift")


# ---- tasks and renown --------------------------------------------------------------------------------------------

func _task_add(t: Dictionary, n: float) -> void:
	t["have"] = minf(float(t["goal"]), float(t.get("have", 0.0)) + n)
	if float(t["have"]) >= float(t["goal"]) and not bool(t.get("done", false)):
		t["done"] = true
		renown += int(t.get("renown", 30))
		add_line("guild", "", _fmt(_pick(data.get("lines", {}).get("task_done", [])), {"task": str(t["text"]), "n": int(t.get("renown", 30))}), "sys")
		G.log_event("fellowship_task", {"task": str(t["id"]), "renown": int(t.get("renown", 30))})


func _members_work(secs: float) -> void:
	## your guildmates do their part too: across a week of play they bring each task about halfway
	for t in tasks:
		if bool(t.get("done", false)):
			continue
		var per_sec := float(t["goal"]) * 0.5 / (6.0 * 3600.0) * float((g.get("members", []) as Array).size()) / 6.0
		_task_add(t, per_sec * secs)


func shop() -> Array:
	return data.get("shop", [])


func shop_item(sid: String) -> Dictionary:
	for s in shop():
		if str(s.get("id", "")) == sid:
			return s
	return {}


func can_have(s: Dictionary) -> bool:
	match str(s.get("needs", "")):
		"founded":
			return bool(owned.get("title_founder", false)) or str(g.get("kind", "")) == "own"
		"sect":
			return G.sys("own_sect") != null and G.sys("own_sect").founded()
	return true


func buy(sid: String) -> String:
	var s := shop_item(sid)
	if s.is_empty():
		return ""
	if owned.has(sid):
		return use(sid)
	if not can_have(s):
		return I18n.t("Not yet.")
	if renown < int(s.get("cost", 0)):
		return I18n.t("That takes %d renown (you have %d). Guild tasks earn it.") % [int(s.get("cost", 0)), renown]
	renown -= int(s.get("cost", 0))
	owned[sid] = true
	G.log_event("fellowship_buy", {"id": sid})
	use(sid)
	return I18n.t("Yours: %s.") % I18n.t(str(s.get("name", sid)))


func use(sid: String) -> String:
	var s := shop_item(sid)
	if s.is_empty() or not (owned.has(sid) or (int(s.get("cost", 0)) == 0 and can_have(s))):
		return ""
	owned[sid] = true
	match str(s.get("kind", "")):
		"title":
			title = "" if title == sid else sid
		"crest":
			crest = "" if crest == sid else sid
		"emblem":
			emblem = "" if emblem == sid else sid
	G.stats_changed.emit()
	return I18n.t(str(s.get("name", sid)))


func title_text() -> String:
	return I18n.t(str(shop_item(title).get("name", ""))) if title != "" else ""


func crest_color() -> Color:
	var c = shop_item(crest).get("color", g.get("color", [1, 0.85, 0.5]))
	return Color(float(c[0]), float(c[1]), float(c[2]))


func badge() -> String:
	## [TAG] with your emblem, for names in the chat
	if not in_guild():
		return ""
	var gl := str(shop_item(emblem).get("glyph", ""))
	return "%s[%s]" % [gl, str(g.get("tag", ""))]
