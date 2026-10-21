extends "res://scripts/systems/GameSystem.gd"
## Round 156 (Robert: testing kit for every character on the account). For TESTING, shared by all characters on this install
## (stored beside the saves in <save_base>_account.json, so it survives switching characters):
##   * the VAULT   -- one store for all characters; materials pouch overflow, the Home chest and the bench all use it. Dump
##                    straight into it from anywhere (the ' key, the Pack/pause menu), take from it from anywhere.
##   * crafting    -- whatever is in the vault AND the pack is usable at any bench; a portable table, forge and rune table
##                    for every craft (no "no bench" penalty anywhere).
##   * god mode    -- no damage, no death (so you can step away and your character stays safe).
## All of it can be switched off in the pause menu ("Test kit"). The god/table powers never apply in the online world.
## A one-off refund of 30 nanite shards (three orders lost to the pouch cap, round 155c) lands in the vault.

const OnlineGen := preload("res://scripts/world/OnlineGen.gd")

var vault := {}
var enabled := true
var god_on := true
var endless_on := true            # round 159: sit as long as you like -- no fatigue, no pursuit bank, no away cap
var locks_off := true             # round 159: every lock is open (gates, key stairs, paywall and Lite blocks, the seal)
var infinite_on := true          # round 158: unlimited materials and reagents for crafting and advancing
const STOCK := 99
const _FREE := ["material", "consumable"]
var refund_done := false
var _loaded := false
var _dirty := false
var _t := 0.0
var _stocked := false


func _path() -> String:
	return str(G.save_base) + "_account.json"


static func clean() -> bool:
	## CLEAN build: data/build_flavor.json {"clean": true} switches the whole test kit off for good (no god mode, vault, free tables, open locks)
	if not FileAccess.file_exists("res://data/build_flavor.json"):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/build_flavor.json"))
	return d is Dictionary and bool(d.get("clean", false))


func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if clean():
		enabled = false
		god_on = false
		infinite_on = false
		endless_on = false
		locks_off = false
		refund_done = true
		return
	var real := str(G.save_base) == "user://save" and not ("--script" in OS.get_cmdline_args() or DisplayServer.get_name() == "headless")      # (tools and tests: the kit is off unless a test turns it on)
	enabled = real
	god_on = real
	infinite_on = real
	endless_on = real
	locks_off = real
	if FileAccess.file_exists(_path()):
		var d = JSON.parse_string(FileAccess.get_file_as_string(_path()))
		if d is Dictionary:
			var v = d.get("vault", {})
			if v is Dictionary:
				for k in v:
					vault[str(k)] = int(v[k])
			enabled = bool(d.get("tester", real))
			god_on = bool(d.get("god", real))
			infinite_on = bool(d.get("infinite", real))
			endless_on = bool(d.get("endless", real))
			locks_off = bool(d.get("locks_off", real))
			refund_done = bool(d.get("refund_nanites", false))
	if not refund_done and enabled:
		refund_done = true
		vault["nanite_shard"] = int(vault.get("nanite_shard", 0)) + 30
		_dirty = true
		_flush()


func _flush() -> void:
	_dirty = false
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"vault": vault, "tester": enabled, "god": god_on, "infinite": infinite_on, "endless": endless_on, "locks_off": locks_off, "refund_nanites": refund_done}))


func touch() -> void:
	_dirty = true


func vault_on() -> bool:
	_ensure()
	return enabled


func vault_dict() -> Dictionary:
	_ensure()
	return vault


func active() -> bool:
	## the powers (god mode, portable tables) -- never in the online world
	_ensure()
	return enabled and not OnlineGen.is_online(str(G.current_level))


func god() -> bool:
	return active() and god_on


func endless() -> bool:
	return active() and endless_on


func unlocked() -> bool:
	return active() and locks_off


func floor_ids() -> Array:
	## every place worth a visit, in order: the village, the valley, floors 1..50 (whichever levels exist)
	var out := ["village"]
	if FileAccess.file_exists("res://levels/valley.json") or FileAccess.file_exists("res://data/valley.json"):
		out.append("valley")
	var n := 1
	while FileAccess.file_exists("res://levels/floor%d.json" % n):
		out.append("floor%d" % n)
		n += 1
	return out


func teleport(id: String, arrive: String = "") -> void:
	if not unlocked():
		G.message.emit(I18n.t("Teleport needs the test kit's open locks."))
		return
	G.message.emit(I18n.t("You step through to %s.") % id)
	var tag: String = arrive if arrive != "" else ("P" if id == "village" or id == "valley" else "<")
	G.go_to(id, tag)


func teleport_menu(hud, band: int = -1) -> void:
	var ids := floor_ids()
	var opts := []
	if band < 0:
		opts.append([I18n.t("The village"), func():
			hud.close_dialog()
			teleport("village")])
		if ids.has("valley"):
			opts.append([I18n.t("The valley"), func():
				hud.close_dialog()
				teleport("valley")])
		var floors := ids.filter(func(i): return str(i).begins_with("floor"))
		for b in range(0, floors.size(), 10):
			var lo := b
			var hi := mini(b + 10, floors.size())
			opts.append([I18n.t("Floors %d to %d") % [lo + 1, hi], func(): teleport_menu(hud, lo)])
		opts.append([I18n.t("Back"), func(): menu(hud)])
		hud.open_dialog(I18n.t("Teleport"), I18n.t("Where to? Locks are open while the test kit's switch is on. You are standing on floor: %s.") % str(G.current_level), opts)
		return
	var fl := ids.filter(func(i): return str(i).begins_with("floor"))
	for i in range(band, mini(band + 10, fl.size())):
		var fid: String = fl[i]
		opts.append([I18n.t("Floor %d") % (i + 1), func():
			teleport_pick(hud, fid, band, i + 1)])
	opts.append([I18n.t("Back"), func(): teleport_menu(hud)])
	hud.open_dialog(I18n.t("Teleport"), I18n.t("Pick a floor."), opts)


func teleport_pick(hud, fid: String, band: int, n: int) -> void:
	## round 168: arrive at the floor's start, or skip straight to its last room (the way down)
	var opts := []
	opts.append([I18n.t("The way down (last room)"), func():
		hud.close_dialog()
		teleport(fid, ">")])
	opts.append([I18n.t("The start of the floor"), func():
		hud.close_dialog()
		teleport(fid, "<")])
	opts.append([I18n.t("Back"), func(): teleport_menu(hud, band)])
	hud.open_dialog(I18n.t("Floor %d") % n, I18n.t("Where on this floor?"), opts)


func infinite() -> bool:
	return active() and infinite_on


func free_item(id: String) -> bool:
	## is this one of the things the kit never lets run out? (materials and consumables -- not gear, treasures or quest things)
	return infinite() and str(G.item_def(id).get("type", "")) in _FREE


func restock() -> void:
	for id in G.items:
		var sid := str(id)
		if str(G.items[id].get("type", "")) in _FREE and int(G.inventory.get(sid, 0)) < STOCK:
			G.inventory[sid] = STOCK
	G.stats_changed.emit()


func portable_bench() -> bool:
	return active()


func reset() -> void:
	_stocked = false


func load_state(_d: Dictionary) -> void:
	_stocked = false


func save_state() -> Dictionary:
	if _dirty:
		_flush()
	return {}


func tick(delta: float) -> void:
	_t += delta
	if god() and G.hp < G.max_hp():
		G.hp = G.max_hp()
		G.stats_changed.emit()
	if infinite() and not _stocked:
		_stocked = true
		restock()
	if _t >= 5.0:
		_t = 0.0
		if _dirty:
			_flush()


# ---- the vault ----------------------------------------------------------------------------------------------------

func dump() -> int:
	## every material in the pack goes into the vault, from anywhere
	_ensure()
	if not enabled:
		return -1
	var n: int = G.stash_all_materials()
	_dirty = true
	return n


func dump_text() -> String:
	var n := dump()
	if n < 0:
		return I18n.t("The test kit is off.")
	return I18n.t("%d materials went into the vault.") % n if n > 0 else I18n.t("You carry no materials to put in the vault.")


func pull_all() -> int:
	## the bench: everything the vault holds comes to hand (past the pouch cap, for the work)
	_ensure()
	if not enabled:
		return 0
	var moved := 0
	for id in vault.keys():
		var n: int = int(vault[id])
		if n > 0 and G.items.has(str(id)):
			G.inventory[str(id)] = G.count(str(id)) + n
			moved += n
			vault.erase(id)
	if moved > 0:
		_dirty = true
		G.stats_changed.emit()
	return moved


func pull_for(r: Dictionary) -> void:
	## short of something a recipe needs? take it from the vault
	_ensure()
	if not enabled or vault.is_empty():
		return
	for need in r.get("needs", {}):
		var id := str(need)
		var short: int = int(r["needs"][need]) - G.count(id)
		if short > 0 and int(vault.get(id, 0)) > 0:
			var take: int = mini(short, int(vault[id]))
			G.inventory[id] = G.count(id) + take
			vault[id] = int(vault[id]) - take
			if int(vault[id]) <= 0:
				vault.erase(id)
			_dirty = true


func total(id: String) -> int:
	_ensure()
	return int(vault.get(id, 0))


# ---- the menu -----------------------------------------------------------------------------------------------------

func menu(hud) -> void:
	_ensure()
	var lines := [
		I18n.t("Test kit (every character on this install): %s.") % (I18n.t("on") if enabled else I18n.t("off")),
		I18n.t("The vault holds your materials for all characters -- dump into it from anywhere (the ' key), craft from it and your pack at any bench."),
		I18n.t("God mode: %s. A portable table, forge and rune table: %s. (Neither works in the online world.)") % [I18n.t("on") if god_on else I18n.t("off"), I18n.t("on") if enabled else I18n.t("off")],
		""]
	var ids := vault.keys()
	ids.sort()
	if ids.is_empty():
		lines.append(I18n.t("The vault is empty."))
	else:
		var parts := []
		for id in ids:
			parts.append("%s x%d" % [G.item_name(str(id)), int(vault[id])])
		lines.append(I18n.t("In the vault: ") + ", ".join(parts))
	var opts := []
	opts.append([I18n.t("Dump all materials into the vault"), func():
		G.message.emit(dump_text())
		menu(hud)])
	for id in ids.slice(0, 12):
		opts.append([I18n.t("Take %s (%d)") % [G.item_name(str(id)), int(vault[id])], func():
			var n: int = G.take_from_stash(str(id))
			if n <= 0:
				G.message.emit(I18n.t("Your pouch has no room for more %s.") % G.item_name(str(id)))
			_dirty = true
			menu(hud)])
	opts.append([I18n.t("Test kit: %s (tap to switch)") % (I18n.t("on") if enabled else I18n.t("off")), func():
		enabled = not enabled
		_dirty = true
		_flush()
		menu(hud)])
	opts.append([I18n.t("Teleport to any floor"), func(): teleport_menu(hud)])
	opts.append([I18n.t("Endless meditation: %s (tap to switch)") % (I18n.t("on") if endless_on else I18n.t("off")), func():
		endless_on = not endless_on
		_dirty = true
		_flush()
		menu(hud)])
	opts.append([I18n.t("Every lock open: %s (tap to switch)") % (I18n.t("on") if locks_off else I18n.t("off")), func():
		locks_off = not locks_off
		_dirty = true
		_flush()
		menu(hud)])
	opts.append([I18n.t("Unlimited materials: %s (tap to switch)") % (I18n.t("on") if infinite_on else I18n.t("off")), func():
		infinite_on = not infinite_on
		_stocked = false
		_dirty = true
		_flush()
		menu(hud)])
	opts.append([I18n.t("God mode: %s (tap to switch)") % (I18n.t("on") if god_on else I18n.t("off")), func():
		god_on = not god_on
		_dirty = true
		_flush()
		menu(hud)])
	opts.append([I18n.t("Close"), hud.close_dialog])
	hud.open_dialog(I18n.t("Test kit"), "\n".join(lines), opts)
