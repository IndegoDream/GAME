class_name Icons
extends RefCounted
## Icons for every item, skill and technique (round 113). Pictures live in res://assets/icons/<kind>/<id>.png (96x96).
## Icons.item("iron_ore") -> Texture2D; an id with no picture gets the "?" plaque, never null. Cached after first load.
## Wire a UI row like:  icon_rect.texture = Icons.item(id)    (techniques: Icons.technique(id), skills: Icons.skill(id))

static var _cache: Dictionary = {}

static func item(id: String) -> Texture2D:
	return fetch("items", id)

static func skill(id: String) -> Texture2D:
	return fetch("skills", id)

static func technique(id: String) -> Texture2D:
	return fetch("techniques", id)

static func has_item(id: String) -> bool:
	return ResourceLoader.exists("res://assets/icons/items/%s.png" % id)

static func fetch(kind: String, id: String) -> Texture2D:
	var key := kind + "/" + id
	if _cache.has(key):
		return _cache[key]
	var p := "res://assets/icons/%s/%s.png" % [kind, id]
	if not ResourceLoader.exists(p):
		p = "res://assets/icons/items/_unknown.png"
	var t: Texture2D = null
	if ResourceLoader.exists(p):
		t = load(p) as Texture2D
	_cache[key] = t
	return t
