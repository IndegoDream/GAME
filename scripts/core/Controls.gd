extends RefCounted
## round 158 (Robert: "allow users to manage their own button configuration"): every keyboard action can be moved to
## another key. Choices live in user://controls.json (all characters on this install), over the defaults Game._setup_input
## registers. Mouse buttons and pads keep their own settings; only keys are rebound here.

const PATH := "user://controls.json"

# [action, label, group] -- what the screen lists, in this order
const ROWS := [
	["move_forward", "Move forward", "Move"], ["move_back", "Move back", "Move"], ["move_left", "Move left", "Move"], ["move_right", "Move right", "Move"],
	["jump", "Jump", "Move"], ["sprint", "Sprint", "Move"], ["dodge", "Dodge", "Move"], ["wind_step", "Step art (wind step)", "Move"],
	["attack", "Attack", "Fight"], ["guard", "Guard", "Fight"], ["lock_on", "Lock on", "Fight"], ["qi_burst", "Strike art", "Fight"], ["art_cycle", "Swap strike art", "Fight"],
	["quick1", "Quick key 1", "Quick arts"], ["quick2", "Quick key 2", "Quick arts"], ["quick3", "Quick key 3", "Quick arts"], ["quick4", "Quick key 4", "Quick arts"],
	["support_art", "Support art", "Quick arts"], ["support2_art", "Second support art", "Quick arts"], ["path_art", "Path art", "Quick arts"], ["flying_sword", "Flying sword", "Quick arts"],
	["use_salve", "Use salve", "Items"], ["use_pill", "Use qi pill", "Items"], ["use_gourd", "Use gourd", "Items"], ["talisman", "Burn talisman", "Items"], ["vault_dump", "Dump into vault", "Items"],
	["interact", "Interact / talk", "World"], ["meditate", "Meditate", "World"], ["flow", "Flow (active meditation)", "World"], ["mech", "Mech", "World"], ["camera_view", "Camera view", "World"],
	["menu", "Menu", "Menus"], ["inventory", "Bag", "Menus"], ["map", "Map", "Menus"], ["journal", "Journal", "Menus"], ["lattice", "Meridians", "Menus"], ["character", "Character", "Menus"], ["pause", "Pause", "Menus"], ["photo", "Photo mode", "Menus"],
]

static var defaults := {}        # action -> [keycode]: what the game ships with (snapshotted before any choice is applied)
static var chosen := {}          # action -> [keycode]: the player's own


static func _keys_of(action: String) -> Array:
	var out := []
	if InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				out.append(int((ev as InputEventKey).physical_keycode))
	return out


static func init() -> void:
	## call once, after the defaults are registered
	if defaults.is_empty():                  # (only the first time: later calls would snapshot the player's own keys as defaults)
		for r in ROWS:
			defaults[str(r[0])] = _keys_of(str(r[0]))
	else:
		for a in defaults:
			_apply(str(a), defaults[a])
	chosen = {}
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			for k in d:
				if defaults.has(str(k)) and d[k] is Array:
					chosen[str(k)] = (d[k] as Array).map(func(v): return int(v))
	for a in chosen:
		_apply(str(a), chosen[a])


static func _apply(action: String, codes: Array) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	for c in codes:
		var ev := InputEventKey.new()
		ev.physical_keycode = int(c)
		InputMap.action_add_event(action, ev)


static func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(chosen))


static func keys(action: String) -> Array:
	return chosen[action] if chosen.has(action) else defaults.get(action, [])


static func key_text(action: String) -> String:
	var ks := keys(action)
	if ks.is_empty():
		return I18n.t("(none)")
	return " / ".join(ks.map(func(k): return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(k)) if DisplayServer.get_name() != "headless" else OS.get_keycode_string(k)))


static func owner_of(code: int, except_action: String = "") -> String:
	## which action already uses this key ("" if none)
	for r in ROWS:
		var a := str(r[0])
		if a != except_action and int(code) in keys(a):
			return a
	return ""


static func label_of(action: String) -> String:
	for r in ROWS:
		if str(r[0]) == action:
			return I18n.t(str(r[1]))
	return action


static func bind(action: String, code: int) -> String:
	## give `action` this key (replacing its old keys). A key another action held is taken from it, and that is said aloud.
	if not defaults.has(action):
		return ""
	var note := ""
	var other := owner_of(code, action)
	if other != "":
		var rest: Array = (keys(other) as Array).filter(func(k): return int(k) != code)
		chosen[other] = rest
		_apply(other, rest)
		note = I18n.t(" (%s lost that key)") % label_of(other)
	chosen[action] = [code]
	_apply(action, [code])
	save()
	return I18n.t("%s is now on %s.") % [label_of(action), OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code)) if DisplayServer.get_name() != "headless" else str(code)] + note


static func reset_one(action: String) -> void:
	chosen.erase(action)
	_apply(action, defaults.get(action, []))
	save()


static func reset_all() -> void:
	for a in defaults:
		_apply(str(a), defaults[a])
	chosen = {}
	save()


static func is_default(action: String) -> bool:
	return not chosen.has(action)
