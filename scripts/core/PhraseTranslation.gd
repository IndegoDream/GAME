class_name PhraseTranslation
extends Translation
## Round 141: the catalog lookup for one language. An exact English phrase comes back translated; text the game
## has joined together from known pieces ("<description>  (+5% strike speed)", "Alchemy 0/6") is translated piece by piece
## when most of its letters belong to known phrases -- otherwise it stays English, never half-and-half noise.

var _map: Dictionary = {}
var _first: Dictionary = {}     # first three letters -> phrases starting with them, longest first
var _cache: Dictionary = {}
var size := 0
var _tpl: Dictionary = {}       # first three letters of the fixed start -> [ [regex, key], ... ]  (keys with %d / %s / {x} in them)
var _tpl_any: Array = []        # templates that open with a placeholder
const COVER := 0.55
const TOKEN := "%[+\\-0-9.]*[sdf]|\\{[a-z0-9_]+\\}|%%"


func setup(d: Dictionary) -> void:
	_map = d
	size = d.size()
	var tmp := {}
	for k in d:
		var s := str(k)
		if s.length() < 4 or not _alpha(s.unicode_at(0)):
			continue
		var b := s.substr(0, 3)
		if not tmp.has(b):
			tmp[b] = []
		(tmp[b] as Array).append(s)
	for b in tmp:
		(tmp[b] as Array).sort_custom(func(x, y): return str(x).length() > str(y).length())
	_first = tmp
	_build_templates()


func _build_templates() -> void:
	## "Needs %d %s (you have %d)." becomes ^Needs (\d+) (.+?) \(you have (\d+)\)\.$ so text with the numbers and names already in it still finds its translation
	var tok := RegEx.new()
	tok.compile(TOKEN)
	_tpl.clear()
	_tpl_any.clear()
	for k in _map:
		var key := str(k)
		var ms := tok.search_all(key)
		if ms.is_empty():
			continue
		var fixed_letters := 0
		for ch in tok.sub(key, "", true):
			if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z"):
				fixed_letters += 1
		if fixed_letters < 6:
			continue
		var pat := "^"
		var pos := 0
		var n := 0
		for m in ms:
			pat += _esc(key.substr(pos, m.get_start() - pos))
			var t := m.get_string()
			if t == "%%":
				pat += "%"
			else:
				n += 1
				if t.ends_with("d"):
					pat += "([+\\-]?\\d+)"
				elif t.ends_with("f"):
					pat += "([+\\-]?\\d+(?:\\.\\d+)?)"
				else:
					pat += "(\\S+(?: \\S+){0,4}?)"
			pos = m.get_end()
		pat += _esc(key.substr(pos)) + "$"
		if n == 0:
			continue
		var rx := RegEx.new()
		if rx.compile(pat) != OK:
			continue
		var lead := key.substr(0, ms[0].get_start())
		var row := [rx, key, lead.length()]
		if lead.length() >= 3:
			var b := lead.substr(0, 3)
			if not _tpl.has(b):
				_tpl[b] = []
			(_tpl[b] as Array).append(row)
		else:
			_tpl_any.append(row)
	for b in _tpl:
		(_tpl[b] as Array).sort_custom(func(x, y): return int(x[2]) > int(y[2]))


static func _esc(t: String) -> String:
	var out := ""
	for i in t.length():
		var c := t[i]
		if c in "\\.^$*+?()[]{}|":
			out += "\\" + c
		else:
			out += c
	return out


static func _alpha(c: int) -> bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)


static func _alnum(c: int) -> bool:
	return _alpha(c) or (c >= 48 and c <= 57)


func _get_message(src_message: StringName, context: StringName) -> StringName:
	var s := str(src_message)
	if _map.has(s):
		return StringName(str(_map[s]))
	if context != &"" or s.length() < 4:
		return &""
	if _cache.has(s):
		return StringName(str(_cache[s]))
	var r := _template(s)
	if r == "":
		r = _phrases(s)
	if _cache.size() > 3000:
		_cache.clear()
	_cache[s] = r
	return StringName(r)


func _phrases(s: String) -> String:
	var n := s.length()
	var out := ""
	var i := 0
	var letters := 0
	var covered := 0
	while i < n:
		var ch := s.unicode_at(i)
		if _alpha(ch) and (i == 0 or not _alnum(s.unicode_at(i - 1))):
			var cands = _first.get(s.substr(i, 3), null)
			if cands != null:
				var hit := ""
				for cand in cands:
					var l: int = (cand as String).length()
					if i + l <= n and s.substr(i, l) == cand:
						var nx := s.unicode_at(i + l) if i + l < n else 32
						if _alnum(nx):
							continue
						if nx == 39 and i + l + 1 < n and _alpha(s.unicode_at(i + l + 1)):
							continue
						hit = cand
						break
				if hit != "":
					out += str(_map[hit])
					i += hit.length()
					for j in hit.length():
						if _alpha(hit.unicode_at(j)):
							covered += 1
							letters += 1
					continue
		if _alpha(ch):
			letters += 1
		out += s[i]
		i += 1
	if covered == 0 or float(covered) < COVER * float(letters):
		return ""
	return out


func _template(s: String) -> String:
	var rows: Array = []
	if s.length() >= 3 and _tpl.has(s.substr(0, 3)):
		rows = _tpl[s.substr(0, 3)]
	for row in rows:
		var r := _fit(s, row)
		if r != "":
			return r
	for row in _tpl_any:
		var r2 := _fit(s, row)
		if r2 != "":
			return r2
	return ""


func _fit(s: String, row: Array) -> String:
	var m: RegExMatch = (row[0] as RegEx).search(s)
	if m == null:
		return ""
	var tr_ := str(_map[row[1]])
	var tok := RegEx.new()
	tok.compile(TOKEN)
	var out := ""
	var pos := 0
	var gi := 1
	for t in tok.search_all(tr_):
		out += tr_.substr(pos, t.get_start() - pos)
		var g := t.get_string()
		if g == "%%":
			out += "%"
		else:
			var v := m.get_string(gi) if gi <= m.get_group_count() else ""
			gi += 1
			# a name or phrase that was filled in: give it its own translation when it has one
			if not (g.ends_with("d") or g.ends_with("f")) and _map.has(v):
				v = str(_map[v])
			out += v
		pos = t.get_end()
	out += tr_.substr(pos)
	return out
