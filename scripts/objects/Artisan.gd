extends RefCounted
## The makers of made-for-you pieces (Robert, 2026-10-02: "allow ai to
## tailor item to users game play or allow them to request up to 3 items
## the AI with randomly generated").
##
## Two ways to get one:
##   * a TAILORED piece, paid for with guild contribution (or Academy merit):
##     the maker reads how you actually play (Game.play_profile) and designs
##     for it -- your favourite weapon kind, your best craft, your element.
##   * a WISH at a settlement's smith (three per settlement, a gold fee):
##     you say what you want in your own words; the maker designs the
##     nearest honest thing, and chance decides how good a casting it is.
## The model only designs (name, look, kind, which gift); Game.finalize_design
## sets every number from your depth. When the model is down, design() here
## does it from tables -- a piece is always made.

const ELEMENT_WORDS := {
	"fire": ["Ember", "Cinder", "Furnace", "Red Sun"], "water": ["Tidewater", "Still-Pool", "Rain", "Deep Current"],
	"wood": ["Rootbound", "Greenheart", "Thornvine", "Old Oak"], "metal": ["Ironsong", "Bright Edge", "Silverthread", "Bell-Steel"],
	"earth": ["Stonebound", "Mountain", "Clay-Saint", "Bedrock"],
}
const NOUNS := {
	"sword": ["Sword", "Blade", "Jian"], "dagger": ["Fang", "Knife", "Needle"], "saber": ["Saber", "Dao", "Crescent"],
	"spear": ["Spear", "Lance", "Reed"], "axe": ["Axe", "Cleaver", "Woodsplitter"], "hammer": ["Maul", "Hammer", "Anvil-Fist"],
	"halberd": ["Glaive", "Halberd", "Guandao"], "staff": ["Staff", "Rod", "Pilgrim's Stave"], "fists": ["Wraps", "Knuckles", "Fist-Guards"],
	"bow": ["Bow", "Longbow", "Recurve"], "crossbow": ["Crossbow", "Repeater", "Arbalest"], "ki": ["Focus", "Qi Gauntlet", "Palm-Seal"],
	"armor": ["Coat", "Robe", "Scale", "Vest"], "ring": ["Ring", "Band", "Signet"], "amulet": ["Amulet", "Pendant", "Talisman"],
}
const ELEMENT_STEMS := {"fire": ["fire", "flam", "burn", "ember", "blaz", "scorch", "heat"], "water": ["water", "ice", "frost", "tide", "sea", "rain", "cold"],
	"wood": ["wood", "plant", "vine", "thorn", "leaf", "forest", "root"], "metal": ["metal", "steel", "iron", "silver", "bright"],
	"earth": ["earth", "stone", "rock", "mountain", "clay", "ground"]}
const WORDS_TYPE := {"ring": ["ring", "band", "signet"], "amulet": ["amulet", "pendant", "necklace", "talisman", "charm"],
	"armor": ["armor", "armour", "robe", "coat", "mail", "vest", "plate", "cloak", "shield"]}
const WORDS_EFFECT := {
	"damage_mult": ["hit hard", "damage", "strong", "power", "deadly", "sharp"], "attack_speed": ["fast", "quick", "swift", "speed"],
	"damage_taken": ["protect", "defen", "guard", "tough", "block"], "hp_mult": ["health", "life", "vital", "endur"],
	"qi_mult": ["qi", "cultivat", "spirit"], "meditate_mult": ["meditat", "calm", "focus"],
	"gather_chance": ["gather", "harvest", "forag", "mining", "herb"], "heal_on_kill": ["vampir", "drain", "heal", "lifesteal"],
	"sense_radius": ["sense", "see", "detect", "hidden", "find"],
}


static func effect_choices() -> Array:
	var out := []
	for k in Game.DESIGN_EFFECTS:
		if not str(k).begins_with("craft_"):
			out.append(str(k))
	for sid in Game.skill_defs:
		if str(Game.skill_defs[sid].get("kind", "")) == "crafting":
			out.append("craft_success_" + str(sid))
			out.append("craft_quality_" + str(sid))
	return out


static func _system(maker: String) -> String:
	return ("You are %s, a master artisan in a cultivation world (qi, realms, sects; tiny machines called nanites make cultivation work). " % maker +
		"You design ONE piece for the person in front of you. You choose only what it IS -- never numbers; the world decides how strong it is. " +
		"Reply ONLY with JSON: {\"name\": \"2-4 evocative words\", \"desc\": \"one or two sentences: how it looks, feels, what it's made from\", " +
		"\"type\": \"weapon\" | \"armor\" | \"ring\" | \"amulet\", \"kind\": one of %s (weapons only), " % str(Game.WEAPON_KINDS.keys()) +
		"\"effect\": one of %s, \"element\": one of %s, \"line\": \"what you say as you hand it over, in character\"}" % [str(effect_choices()), str(Game.ELEMENTS)])


static func tailor_prompt(maker: String, guild_name: String, p: Dictionary) -> Array:
	var user := ("The %s has commissioned a piece for one of its own, made for how they actually live. " % guild_name +
		"What you know of them: plays like a %s; favourite weapon kind %s (%s level %d); best craft %s; strongest element %s; " % [
			p.get("style", ""), p.get("favorite_weapon", ""), p.get("weapon_skill", ""), int(p.get("weapon_level", 0)),
			p.get("best_craft", "none"), p.get("element", "")] +
		"%d kills, %d things crafted; background: %s; deepest floor %d. " % [int(p.get("kills", 0)), int(p.get("crafted", 0)),
			str(Game.BACKGROUNDS.get(str(p.get("background", "")), {}).get("name", "unknown")), int(p.get("depth", 1))] +
		"A sensible choice would be a %s%s carrying %s -- but you are the artisan." % [p.get("suggest_type", "ring"),
			(" (" + str(p.get("suggest_kind", "")) + ")") if str(p.get("suggest_kind", "")) != "" else "", " or ".join(p.get("suggest_effects", []))])
	return [{"role": "system", "content": _system(maker)}, {"role": "user", "content": user}]


static func wish_prompt(maker: String, wish: String, p: Dictionary) -> Array:
	var user := ("They ask, in their own words: \"%s\"\n" % wish.left(300) +
		"Honour the wish as closely as the allowed types and gifts let you. If they ask for something no smith could make (a god-killing blade), " +
		"make the nearest honest thing and say so in your line. They fight best with: %s; their element: %s; deepest floor: %d." % [
			p.get("favorite_weapon", ""), p.get("element", ""), int(p.get("depth", 1))])
	return [{"role": "system", "content": _system(maker)}, {"role": "user", "content": user}]


static func _pick(arr: Array, roll: float) -> String:
	return str(arr[int(roll * 9973.0) % arr.size()])


static func design(p: Dictionary, wish: String, roll: float) -> Dictionary:
	## The tables' answer: what the profile (and the wish's words) point to.
	var t := str(p.get("suggest_type", "ring"))
	var kind := str(p.get("favorite_weapon", "sword"))
	var effs: Array = p.get("suggest_effects", ["hp_mult"])
	var eff := str(effs[0]) if effs.size() > 0 else "hp_mult"
	var el := str(p.get("element", "earth"))
	# whole words only, from their start ("balanced" is not a lance)
	var w := ""
	for ch in wish.to_lower():
		w += ch if (ch >= "a" and ch <= "z") else " "
	w = " " + w + " "
	if w.strip_edges() != "":
		var found_type := false
		for k in Game.WEAPON_KINDS:
			for word in [str(k), str(Game.WEAPON_KINDS[k]["name"]).to_lower()] + NOUNS.get(k, []).map(func(x): return str(x).to_lower()):
				if w.contains(" " + word):
					t = "weapon"
					kind = str(k)
					found_type = true
		if not found_type:
			for tt in WORDS_TYPE:
				for word in WORDS_TYPE[tt]:
					if w.contains(" " + str(word)):
						t = str(tt)
						found_type = true
		for e in ELEMENT_STEMS:
			for stem in ELEMENT_STEMS[e]:
				if w.contains(" " + str(stem)):
					el = str(e)
		for k in WORDS_EFFECT:
			for word in WORDS_EFFECT[k]:
				if w.contains(" " + str(word)):
					eff = str(k)
	if not Game.WEAPON_KINDS.has(kind):
		kind = "sword"
	var noun := _pick(NOUNS.get(kind if t == "weapon" else t, ["Ring"]), roll)
	var name := "%s %s" % [_pick(ELEMENT_WORDS.get(el, ["Plain"]), roll * 0.7 + 0.13), noun]
	var looks := {"fire": "warm to the touch, with a red sheen like coals", "water": "cool and smooth, faintly blue where the light catches it",
		"wood": "grained like old heartwood, with a green thread worked through it", "metal": "bright, ringing faintly when struck",
		"earth": "heavy and steady, the colour of river clay"}
	return {"name": name, "type": t, "kind": kind, "effect": eff, "element": el,
		"desc": "Made for you, %s." % looks.get(el, "plain and honest"),
		"line": "\"Here. It's yours -- it was always going to be yours.\""}
