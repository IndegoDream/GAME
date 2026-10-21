extends "res://scripts/systems/GameSystem.gd"
## Three tiers of inheritance, laid out differently in every new game
## (round 51). Robert, 2026-10-04: "make sure major inheritance isn't
## something easy to find. I like the blacksmith in the beginning -- make it
## random though, to make replay interesting" ... "minor inheritances, major
## inheritances and heavenly inheritance, all providing unique benefits.
## It's possible to attain multiple throughout game play, and even when the
## main quest is done players are free to be a completionist within their
## own game."
##
##   MINOR     the craft masters at lost workshops (Vignette.gd). All five
##             are in every game; one waits on floor 1 or 2 -- which craft is
##             decided when the game begins -- and the rest on other upper
##             floors, also decided then.
##   MAJOR     the dead masters a floor's map names ("inheritances").
##             Always hidden: you see one only from a few steps away with
##             Spirit Sense, or by searching slowly right beside it. Each game
##             moves it to a far corner or a sealed chamber of its floor (or
##             leaves it where the floor's maker put it). About a third sleep
##             at first -- they wake when you're strong enough for them, or
##             once the road is walked -- and word comes up the stair.
##   HEAVENLY  a few per game, drawn from a larger pool, on random deep
##             floors. Core Formation to perceive one at all; Spirit Sense
##             from a few steps; and the master's echo tests you in a fight
##             before the legacy is yours. Each gives a heaven-grade art, a
##             treasure and a title nobody else in the world can have.
##
## The Road page keeps the count (and hints where to look), so a finished
## game can still be combed for every last one. data/legacies.json; Dev's
## words: brief heavenly_inheritances.

var data := {}
var seed_v := 0                 # this game's own layout
var crafts := {}                # floor id -> craft (minor masters)
var sealed := {}                # "floorN:I" -> true while that major sleeps
var heavens := {}               # floor id -> heavenly pool id
var claimed_heavens := []       # pool ids, in the order taken
var trials_passed := {}         # pool id -> true
var woke := []                  # majors that woke, for the Road page
var pin := {}                   # tools only (never saved): fixed layouts for tests
var _majors := []               # every major the level files name: {level, ch, cell, master, need}
var _wake_t := 0.0


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/legacies.json")
	var dr = G._load_json("res://data/drafts/heavenly_inheritances.json", {})
	if dr is Dictionary:
		for it in dr.get("items", []):
			if not (it is Dictionary) or str(it.get("text", "")).strip_edges() == "":
				continue
			for h in data.get("heavenly", {}).get("pool", []):
				if str(h.get("id", "")) == str(it.get("id", "")):
					h["text"] = str(it["text"]).strip_edges()
	_register()


func _register() -> void:
	## the heaven-grade arts and treasures join the game's own
	for h in data.get("heavenly", {}).get("pool", []):
		var t: Dictionary = h.get("technique", {})
		if not t.is_empty() and not G.technique_defs.has(str(t["id"])):
			G.technique_defs[str(t["id"])] = {"name": t.get("name", ""), "kind": "passive", "desc": t.get("desc", ""),
				"effect": (t.get("effect", {}) as Dictionary).duplicate(), "realm": 0, "source": "heavenly"}
		var it: Dictionary = h.get("item", {})
		if not it.is_empty() and not G.items.has(str(it["id"])):
			G.items[str(it["id"])] = {"name": it.get("name", ""), "type": "treasure", "value": int(it.get("value", 4000)),
				"effect": (it.get("effect", {}) as Dictionary).duplicate(), "desc": it.get("desc", ""), "heavenly": true}


func cfg(sec: String) -> Dictionary:
	return data.get(sec, {})


# ---- a new game: lay the world's legacies out ----------------------------------------------------

func reset() -> void:
	seed_v = randi() if not pin.has("seed") else int(pin["seed"])
	claimed_heavens = []
	trials_passed = {}
	woke = []
	_lay_out()


func _rng(salt: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d|%s" % [seed_v, salt])
	return r


func _lay_out() -> void:
	## decided once per game (and again, the same way, from the seed)
	crafts = {}
	sealed = {}
	heavens = {}
	var mn := cfg("minor")
	var list: Array = (mn.get("crafts", ["smithing", "alchemy", "medicine", "jewelcrafting", "herbalism"]) as Array).duplicate()
	var r := _rng("minor")
	_shuffle(list, r)
	if pin.has("first_craft") and list.has(str(pin["first_craft"])):
		list.erase(str(pin["first_craft"]))
		list.insert(0, str(pin["first_craft"]))
	var firsts: Array = mn.get("first_floors", [1, 2])
	var top := int(mn.get("upper_floors", 10))
	var first_floor := int(firsts[r.randi() % firsts.size()]) if firsts.size() > 0 else 1
	if pin.has("first_floor"):
		first_floor = int(pin["first_floor"])
	crafts["floor%d" % first_floor] = str(list[0])
	var floors := []
	for f in range(1, top + 1):
		if f != first_floor and _can_host(f):
			floors.append(f)
	_shuffle(floors, r)
	for i in range(1, list.size()):
		if i - 1 < floors.size():
			crafts["floor%d" % int(floors[i - 1])] = str(list[i])
	# the majors: which sleep at first
	var share := float(cfg("major").get("sealed_share", 0.35))
	var rm := _rng("major")
	for m in majors():
		if pin.get("all_majors", false):
			break
		if rm.randf() < share:
			sealed["%s:%s" % [m["level"], m["ch"]]] = true
	# the heavens: a few, from the pool, on random deep floors that exist
	var hv := cfg("heavenly")
	var pool: Array = (hv.get("pool", []) as Array).filter(func(x): return not bool(x.get("ultimate", false))).map(func(x): return str(x.get("id", "")))
	var rh := _rng("heavenly")
	_shuffle(pool, rh)
	var fr: Array = hv.get("floors", [8, 48])
	var deep := []
	for f in range(int(fr[0]), int(fr[1]) + 1):
		if FileAccess.file_exists("res://levels/floor%d.json" % f) or ResourceLoader.exists("res://levels/floor%d.json" % f):
			deep.append(f)
	_shuffle(deep, rh)
	var n := mini(int(hv.get("per_game", 3)), mini(pool.size(), deep.size()))
	for i in n:
		heavens["floor%d" % int(deep[i])] = str(pool[i])
	# round 119: the ultimate legacy (the Balance) is in every game, on its own band of floors
	for uh in hv.get("pool", []):
		if bool(uh.get("ultimate", false)):
			var uf: Array = uh.get("floors", fr)
			var cands := deep.filter(func(f): return int(f) >= int(uf[0]) and int(f) <= int(uf[1]) and not heavens.has("floor%d" % int(f)))
			if not cands.is_empty():
				heavens["floor%d" % int(cands[rh.randi() % cands.size()])] = str(uh.get("id", ""))


func _can_host(f: int) -> bool:
	## a dungeon floor that exists (not a cavern town: no lost workshops there)
	var p := "res://levels/floor%d.json" % f
	if not FileAccess.file_exists(p) and not ResourceLoader.exists(p):
		return false
	var d = G._load_json(p, {})
	return d is Dictionary and not (str(d.get("theme", "dungeon")) in ["settlement", "village"])


static func _shuffle(a: Array, r: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func save_state() -> Dictionary:
	return {"seed": seed_v, "crafts": crafts, "sealed": sealed, "heavens": heavens, "claimed_heavens": claimed_heavens,
		"trials_passed": trials_passed, "woke": woke}


func load_state(d: Dictionary) -> void:
	if not d.has("seed"):
		# a game from before round 51: lay its legacies out now, once
		seed_v = randi() if not pin.has("seed") else int(pin["seed"])
		claimed_heavens = []
		trials_passed = {}
		woke = []
		_lay_out()
		return
	seed_v = int(d.get("seed", 0))
	crafts = d.get("crafts", {}) if d.get("crafts", {}) is Dictionary else {}
	sealed = d.get("sealed", {}) if d.get("sealed", {}) is Dictionary else {}
	heavens = d.get("heavens", {}) if d.get("heavens", {}) is Dictionary else {}
	claimed_heavens = d.get("claimed_heavens", []) if d.get("claimed_heavens", []) is Array else []
	trials_passed = d.get("trials_passed", {}) if d.get("trials_passed", {}) is Dictionary else {}
	woke = d.get("woke", []) if d.get("woke", []) is Array else []


func effects() -> Array:
	return []                   # (the heaven-grade arts and treasures carry their own)


# ---- minor: the craft masters ---------------------------------------------------------------------

func craft_master_on(level_id: String) -> String:
	## the craft whose master waits on this floor this game ("" = none)
	if pin.get("crafts_by_look", false):
		return "*"
	return str(crafts.get(level_id, ""))


# ---- major: the dead masters ------------------------------------------------------------------------

func majors() -> Array:
	## every major any level file names (read once): {level, ch, cell, master, need}
	if not _majors.is_empty():
		return _majors
	for f in range(1, 201):
		var p := "res://levels/floor%d.json" % f
		if not FileAccess.file_exists(p) and not ResourceLoader.exists(p):
			if f > 60:
				break
			continue
		var d = G._load_json(p, {})
		if not (d is Dictionary):
			continue
		var inh = d.get("inheritances", {})
		if not (inh is Dictionary) or inh.is_empty():
			continue
		var rows: Array = d.get("map", [])
		for ch in inh:
			var cell := Vector2i(-1, -1)
			for y in rows.size():
				var x := str(rows[y]).find(str(ch))
				if x >= 0:
					cell = Vector2i(x, y)
					break
			var def: Dictionary = inh[ch]
			var need := int(def.get("needs_realm", -1))
			if need < 0:
				need = G.inheritance_default_realm(int(d.get("depth", f)))
			_majors.append({"level": "floor%d" % f, "ch": str(ch), "cell": cell, "master": str(def.get("master", I18n.t("a nameless master"))),
				"need": G.inheritance_need(need, def.get("grants", {})), "depth": int(d.get("depth", f))})
	return _majors


func major_present(level_id: String, ch: String) -> bool:
	return not sealed.has("%s:%s" % [level_id, ch])


func major_key(level_id: String, cell: Vector2i) -> String:
	return G.flag_key(level_id, cell, "inheritance")


func major_found(m: Dictionary) -> bool:
	return G.has_flag(major_key(str(m["level"]), m["cell"]))


func tick(delta: float) -> void:
	_wake_t -= delta
	if _wake_t > 0.0 or sealed.is_empty():
		return
	_wake_t = 5.0
	wake_check()


func wake_check() -> Array:
	## a sleeping master wakes when you're strong enough for it, or once the
	## road is walked -- and word comes up the stair
	var out := []
	var over := int(cfg("major").get("wake_realm_over_need", 1))
	for m in majors():
		var k := "%s:%s" % [m["level"], m["ch"]]
		if not sealed.has(k):
			continue
		if G.realm >= int(m["need"]) + over or G.finished():
			sealed.erase(k)
			woke.append(k)
			out.append(k)
			G.message.emit("Word comes up the stair: something old has stirred on floor %d -- a master's will, waking where no one has looked." % int(m["depth"]))
			G.log_event("legacy_woke", {"level": m["level"], "master": m["master"]})
	return out


func pick_spot(lvl, salt: String, designed: Vector2i) -> Vector2i:
	## where a hidden legacy sits this game: a sealed chamber, a dead end, a
	## far corner -- well away from the stairs. (Sometimes where the floor's
	## maker put it.)
	var r := _rng("%s|%s|spot" % [lvl.level_id, salt])
	var mj := cfg("major")
	if pin.get("designed_spots", false) and designed.x >= 0:
		return designed
	if designed.x >= 0 and r.randf() < float(mj.get("designed_spot_chance", 0.35)):
		return designed
	var starts := []
	for ch in ["<", "P", ">"]:
		for c in lvl.spawns.get(ch, []):
			starts.append(c)
	if starts.is_empty():
		return designed
	var open_only := _flood(lvl, starts, false)
	var with_secrets := _flood(lvl, starts, true)
	var far := int(mj.get("min_from_stairs", 12))
	var cands := []
	for c in with_secrets:
		var cell: Vector2i = c
		if lvl.char_at(cell) != "." or lvl.astar.is_point_solid(cell):
			continue
		var near := 9999
		for s in starts:
			near = mini(near, absi(s.x - cell.x) + absi(s.y - cell.y))
		if near < far:
			continue
		var walk := 0
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if lvl.is_walkable_char(lvl.char_at(cell + d)):
				walk += 1
		var score := float(with_secrets[cell])
		if not open_only.has(cell):
			score += 1000.0                 # behind a secret wall
		if walk <= 1:
			score += 200.0                  # a dead end
		elif walk == 2:
			score += 40.0
		cands.append([score + r.randf() * 30.0, cell])
	if cands.is_empty():
		return designed
	cands.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var top := maxi(4, int(cands.size() * 0.12))
	var first := r.randi() % mini(top, cands.size())
	# a solid legacy must never plug a one-wide corridor and cut the rest of the floor off from the stairs
	for k in range(mini(cands.size(), 60)):
		var pick: Vector2i = cands[(first + k) % cands.size()][1]
		if not _plugs(lvl, starts, pick, with_secrets.size()):
			return pick
	return designed


func _plugs(lvl, starts: Array, skip: Vector2i, total: int) -> bool:
	## true if blocking `skip` would leave some of the floor unreachable from the stairs
	var seen := {}
	var q := []
	for s in starts:
		if s != skip:
			seen[s] = true
			q.append(s)
	var i := 0
	while i < q.size():
		var c: Vector2i = q[i]
		i += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c + d
			if nb == skip or seen.has(nb):
				continue
			var ch: String = lvl.char_at(nb)
			if not (lvl.is_walkable_char(ch) or ch == "S"):
				continue
			seen[nb] = true
			q.append(nb)
	return seen.size() < total - 1


func _flood(lvl, starts: Array, through_secrets: bool) -> Dictionary:
	var dist := {}
	var q := []
	for s in starts:
		dist[s] = 0
		q.append(s)
	var i := 0
	while i < q.size():
		var c: Vector2i = q[i]
		i += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if dist.has(n):
				continue
			var ch: String = lvl.char_at(n)
			if not (lvl.is_walkable_char(ch) or (through_secrets and ch == "S")):
				continue
			dist[n] = int(dist[c]) + 1
			q.append(n)
	return dist


# ---- heavenly ----------------------------------------------------------------------------------------

func heavenly_on(level_id: String) -> Dictionary:
	var hid := str(heavens.get(level_id, ""))
	return heavenly(hid) if hid != "" else {}


func heavenly(hid: String) -> Dictionary:
	for h in cfg("heavenly").get("pool", []):
		if str(h.get("id", "")) == hid:
			return h
	return {}


func heavenly_def(h: Dictionary, depth: int) -> Dictionary:
	## the shape Inheritance.gd reads
	var need := maxi(int(cfg("heavenly").get("min_realm", 4)), G.inheritance_default_realm(depth) + 1)
	return {"master": h.get("master", ""), "text": h.get("text", ""), "hidden": true, "needs_realm": need, "tier": "heavenly", "heaven": h.get("id", ""),
		"grants": {"items": {str(h.get("item", {}).get("id", "")): 1}, "techniques": [str(h.get("technique", {}).get("id", ""))], "qi": int(cfg("heavenly").get("qi", 2500))}}


func heaven_key(hid: String) -> String:
	return "heaven:" + hid


func claim_heavenly(hid: String) -> void:
	var h := heavenly(hid)
	if h.is_empty() or claimed_heavens.has(hid):
		return
	claimed_heavens.append(hid)
	var t := str(h.get("title", ""))
	if t != "" and not G.titles.has(t):
		G.titles.append(t)
		G.message.emit("TITLE: %s." % t)
	G.log_event("heavenly_inheritance", {"id": hid, "master": h.get("master", "")})
	G.message.emit("HEAVENLY INHERITANCE: the legacy of %s is yours. Nobody else in the world will ever hold it." % str(h.get("master", "")))


# ---- the count (the Road page) -----------------------------------------------------------------------

func summary() -> Dictionary:
	var mj := majors()
	var found_m := 0
	var bands := {}
	for m in mj:
		if major_found(m):
			found_m += 1
		elif not sealed.has("%s:%s" % [m["level"], m["ch"]]):
			var b := int((int(m["depth"]) - 1) / 10)
			bands[b] = int(bands.get(b, 0)) + 1
	var minor_found := 0
	for lid in crafts:
		if G.has_tech(str(_craft_tech(str(crafts[lid])))):
			minor_found += 1
	var heav := []
	var bw := int(cfg("heavenly").get("band", 6))
	for lid in heavens:
		var d := int(str(lid).trim_prefix("floor"))
		var r := _rng("band|" + str(lid))
		var lo := maxi(1, d - r.randi_range(0, bw))
		heav.append({"id": heavens[lid], "claimed": claimed_heavens.has(str(heavens[lid])), "lo": lo, "hi": lo + bw})
	return {"minor": [minor_found, crafts.size()], "major": [found_m, mj.size()], "major_bands": bands, "sleeping": sealed.size(),
		"heavenly": heav}


func _craft_tech(craft: String) -> String:
	var L: Dictionary = G._load_json("res://data/vignettes.json", {}).get("legacies", {})
	return str(L.get(craft, {}).get("technique", ""))
