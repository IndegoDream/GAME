extends RefCounted
## Round 182: data mods. Robert, 2026-11-06 (earnings review): a mod scene keeps a game selling for years.
##
## A mod is a folder:   <mods>/<id>/mod.json   and   <mods>/<id>/data/<any data file>.json
##   mod.json  {"id": "more_herbs", "name": "More Herbs", "version": "1.0", "author": "...", "about": "..."}
##   <mods> is user://mods (on PC: %APPDATA%/Godot/app_userdata/<game>/mods), plus any Steam Workshop items once
##   the game has a Steam App ID (SteamLink.workshop_folders()).
## Each data file in a mod is laid OVER the game's file of the same name when the game reads it (Game._load_json):
##   - a dictionary merges key by key (deeper dictionaries merge too); a new key adds, a known key replaces
##   - null removes a key
##   - {"__append": [...]} adds to the end of a list (any other list replaces the game's list)
## Mods load in name order; a later mod wins a clash. A mod found is OFF until the player turns it on (Menu > Mods),
## and a change takes effect after a restart (the data is read once, at start).
## Never moddable (the files that decide money, accounts and the shared world): PROTECTED below. With any mod on,
## the online world (the Gate) stays shut and leaderboards don't take scores -- a modded game is a solo game.

const PROTECTED := ["store.json", "cloud.json", "online.json", "online_events.json", "build_info.json", "build_flavor.json",
	"build_flavor.CLEAN.json", "build_flavor.TESTKIT.json", "retail.json"]
const MAX_FILE_BYTES := 2097152

static var root := "user://mods"
static var _scanned := false
static var _found := []                    # [{id, name, version, author, about, dir, files: [names], problems: []}]
static var _enabled := {}                  # id -> true
static var _overlay := {}                  # data file name -> [Dictionary or Array, ...] in load order
static var extra_dirs := []                # (Workshop folders, or a tool's)


static func reset() -> void:
	_scanned = false
	_found = []
	_enabled = {}
	_overlay = {}


static func scan() -> void:
	if _scanned:
		return
	_scanned = true
	_found = []
	_overlay = {}
	_enabled = {}
	if FileAccess.file_exists(_enabled_path()):
		var e = JSON.parse_string(FileAccess.get_file_as_string(_enabled_path()))
		if e is Dictionary:
			for k in e:
				if bool(e[k]):
					_enabled[str(k)] = true
	var dirs := []
	if DirAccess.dir_exists_absolute(root):
		for d in DirAccess.get_directories_at(root):
			dirs.append(root + "/" + d)
	for d in extra_dirs:
		dirs.append(str(d))
	if root == "user://mods" and FileAccess.file_exists("user://mods_workshop.json"):
		var ws = JSON.parse_string(FileAccess.get_file_as_string("user://mods_workshop.json"))      # (SteamLink.note_workshop)
		if ws is Array:
			for d in ws:
				if DirAccess.dir_exists_absolute(str(d)):
					dirs.append(str(d))
	dirs.sort()
	var count := {}
	for dir in dirs:
		var m := _read_mod(dir)
		if m.is_empty():
			continue
		if str(m["id"]) != "":
			count[m["id"]] = int(count.get(m["id"], 0)) + 1
		_found.append(m)
	for m in _found:
		if str(m["id"]) != "" and int(count.get(m["id"], 0)) > 1:
			m["problems"].append("two mods use the id '%s' -- rename one" % m["id"])      # neither loads: which one was meant isn't ours to guess
	_found.sort_custom(func(a, b): return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	for m in _found:
		if m["id"] == "" or not _enabled.has(m["id"]) or not m["problems"].is_empty():
			continue
		for fn in m["files"]:
			var v = JSON.parse_string(FileAccess.get_file_as_string(m["dir"] + "/data/" + fn))
			if v is Dictionary or v is Array:
				if not _overlay.has(fn):
					_overlay[fn] = []
				_overlay[fn].append(v)


static func _read_mod(dir: String) -> Dictionary:
	if not FileAccess.file_exists(dir + "/mod.json"):
		return {}
	var j = JSON.parse_string(FileAccess.get_file_as_string(dir + "/mod.json"))
	var m := {"id": "", "name": dir.get_file(), "version": "", "author": "", "about": "", "dir": dir, "files": [], "problems": [], "skipped": []}
	if not (j is Dictionary):
		m["problems"].append("mod.json is not valid JSON")
		return m
	var id := str(j.get("id", ""))
	if not _good_id(id):
		m["problems"].append("its id must be 2-32 letters, digits or _ (lower case)")
	else:
		m["id"] = id
	m["name"] = str(j.get("name", id)).substr(0, 48)
	m["version"] = str(j.get("version", "")).substr(0, 16)
	m["author"] = str(j.get("author", "")).substr(0, 48)
	m["about"] = str(j.get("about", "")).substr(0, 400)
	if DirAccess.dir_exists_absolute(dir + "/data"):
		for fn in DirAccess.get_files_at(dir + "/data"):
			if not fn.ends_with(".json"):
				continue
			if fn in PROTECTED:
				m["skipped"].append(fn + " (never moddable)")
				continue
			if not FileAccess.file_exists("res://data/" + fn):
				m["skipped"].append(fn + " (the game has no such file)")
				continue
			var f := FileAccess.open(dir + "/data/" + fn, FileAccess.READ)
			if f == null or f.get_length() > MAX_FILE_BYTES:
				m["skipped"].append(fn + " (too big)")
				continue
			f.close()
			var v = JSON.parse_string(FileAccess.get_file_as_string(dir + "/data/" + fn))
			if not (v is Dictionary or v is Array):
				m["problems"].append(fn + " is not valid JSON")
				continue
			m["files"].append(fn)
	if m["files"].is_empty() and m["problems"].is_empty():
		m["problems"].append("it changes nothing (no data files)")
	return m


static func _good_id(id: String) -> bool:
	if id.length() < 2 or id.length() > 32:
		return false
	for ch in id:
		if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_"):
			return false
	return true


static func _enabled_path() -> String:
	return root + "/enabled.json"


# ---- what the game asks ----------------------------------------------------------------------------------------------

static func overlay(path: String, parsed):
	## Game._load_json: the game's data with the mods laid over it (unchanged with no mods on)
	if not path.begins_with("res://data/") or path.count("/") != 3:
		return parsed
	scan()
	var fn := path.get_file()
	if not _overlay.has(fn) or fn in PROTECTED:
		return parsed
	var out = parsed.duplicate(true) if (parsed is Dictionary or parsed is Array) else parsed
	for layer in _overlay[fn]:
		out = merge(out, layer)
	return out


static func merge(base, layer):
	if layer is Dictionary and layer.has("__append") and layer.size() == 1:
		var arr: Array = (base.duplicate(true) if base is Array else [])
		var add = layer["__append"]
		if add is Array:
			arr.append_array(add)
		return arr
	if base is Dictionary and layer is Dictionary:
		var out: Dictionary = base.duplicate(true)
		for k in layer:
			if layer[k] == null:
				out.erase(k)
			elif out.has(k):
				out[k] = merge(out[k], layer[k])
			else:
				out[k] = merge(null, layer[k]) if layer[k] is Dictionary else layer[k]
		return out
	if layer is Dictionary and layer.has("__append"):
		return merge(base, {"__append": layer["__append"]})
	return layer.duplicate(true) if (layer is Dictionary or layer is Array) else layer


static func active() -> bool:
	scan()
	for m in _found:
		if m["id"] != "" and _enabled.has(m["id"]) and m["problems"].is_empty() and not m["files"].is_empty():
			return true
	return false


static func active_ids() -> Array:
	scan()
	var out := []
	for m in _found:
		if m["id"] != "" and _enabled.has(m["id"]) and m["problems"].is_empty() and not m["files"].is_empty():
			out.append(m["id"])
	return out


static func found() -> Array:
	scan()
	return _found


static func is_on(id: String) -> bool:
	scan()
	return _enabled.has(id)


static func set_on(id: String, on: bool) -> void:
	## takes effect at the next start (what's loaded now stays as it is)
	scan()
	var e := _enabled.duplicate()
	if on:
		e[id] = true
	else:
		e.erase(id)
	DirAccess.make_dir_recursive_absolute(root)
	var f := FileAccess.open(_enabled_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(e))
		f.close()
	_enabled = e
	_restart_needed = true


static var _restart_needed := false


static func restart_needed() -> bool:
	return _restart_needed


static func folder_hint() -> String:
	return ProjectSettings.globalize_path(root)


# ---- the menu ------------------------------------------------------------------------------------------------------

static func menu(hud) -> void:
	scan()
	var lines := [I18n.t("Mods change the game's data: new items, foes, recipes, quests, numbers. A modded game is a solo game -- the online world and leaderboards stay shut while any mod is on."), ""]
	var opts := []
	if _found.is_empty():
		lines.append(I18n.t("No mods found. Put a mod's folder here:"))
		lines.append(folder_hint())
	for m in _found:
		var on: bool = str(m["id"]) != "" and _enabled.has(m["id"])
		var head: String = "%s %s%s" % [m["name"], m["version"], ("  by " + m["author"]) if m["author"] != "" else ""]
		lines.append(("[ON]  " if on else "[off]  ") + head)
		if m["about"] != "":
			lines.append("      " + m["about"])
		for p in m["problems"]:
			lines.append("      " + I18n.t("Can't load: ") + p)
		for s in m["skipped"]:
			lines.append("      " + I18n.t("Left out: ") + s)
		if m["id"] != "" and m["problems"].is_empty():
			var mid: String = m["id"]
			opts.append([(I18n.t("Turn off: ") if on else I18n.t("Turn on: ")) + str(m["name"]), func():
				set_on(mid, not on)
				menu(hud)])
	if _restart_needed:
		lines.append("")
		lines.append(I18n.t("Restart the game to apply the change."))
	opts.append(["Close", hud.close_dialog])
	hud.open_dialog(I18n.t("Mods"), "\n".join(lines), opts)
