extends Node
## Game -- the one place the player's progress lives (autoloaded as "Game").
##
## Cultivation (5 realms x 10 sub-levels, the nanites are how it works),
## gold, inventory, equipped gear, quests, which level you're on, and
## saving. Every other script reads and changes progress through here,
## never by keeping its own copy -- so a save always has everything.
##
## Content (items, enemies, recipes, quests, levels) is DATA, in
## res://data/*.json and res://levels/*.json. See DEV_GUIDE.md.

signal stats_changed
signal message(text: String)
signal language_changed                       # round 140: the menus redraw in the new language
signal level_change_requested(level_id: String, spawn_tag: String)
signal familiar_changed
signal companion_changed
signal unlock_wanted(level_id: String, arrive_at: String)   # round 58: the way below the free floors (HUD opens the unlock window)

const CELL := 2.0                  # one map character = 2 x 2 metres
const ScavengeGen := preload("res://scripts/world/ScavengeGen.gd")
const Arena := preload("res://scripts/world/Arena.gd")
const Design := preload("res://scripts/systems/Design.gd")
const AcademyLib := preload("res://scripts/world/Academy.gd")
const ValleyGen := preload("res://scripts/world/Valley.gd")
const FrontierGen := preload("res://scripts/world/Frontier.gd")          # round 123: the tech frontier
const Gfx := preload("res://scripts/core/Gfx.gd")
const CloudSaveScript := preload("res://scripts/core/CloudSave.gd")
const Hook := preload("res://scripts/systems/Hook.gd")          # round 126: chains, luck, the daily pull
const Comfort := preload("res://scripts/systems/Comfort.gd")      # round 127: convenience and style, never power
const OnlineGen := preload("res://scripts/world/OnlineGen.gd")          # round 125: the Gate (shared world)
const OnlineScript := preload("res://scripts/net/Online.gd")
var online = null                       # round 125: the online client (a node), made in _ready
var online_from := "village"            # where the Gate was entered from (a save made inside the Gate is written as this place)
var cloudsave = null                    # round 124: the cloud save client (a node), made in _ready
const TowerGen := preload("res://scripts/world/TowerGen.gd")
const TOURNEY_COOLDOWN := 1200.0    # real seconds before a settlement holds its next tournament for you
const KNOWLEDGE_RETRY := 300.0
var save_path := "user://save.json"   # tools/ point this elsewhere so tests never touch your real save
const AFK_QI_PER_HOUR := 15.0      # nanites refine qi while you're away (at least this; see AWAY_QI_FRAC)
const AFK_SHRINE_MULT := 2.0       # ...twice as fast if you left meditating (was 3x: meditation is slow without aids, 2026-10-02)
const SUBLEVELS := 10
const POUCH_CAP := 20             # of each material, until you own a storage ring

const REALMS := [
	{"name": "Body Tempering", "nanite": "Nanite Seeding"},
	{"name": "Qi Condensation", "nanite": "Nanite Bloom"},
	{"name": "Foundation Establishment", "nanite": "Nanite Lattice"},
	{"name": "Core Formation", "nanite": "Nanite Core"},
	{"name": "Nascent Soul", "nanite": "Nanite Ascendance"},
	{"name": "Soul Transformation", "nanite": "Nanite Transcendence"},
	{"name": "Void Refinement", "nanite": "Nanite Void"},
	{"name": "Body Integration", "nanite": "Nanite Union"},
	{"name": "Mahayana", "nanite": "Nanite Sea"},
	{"name": "Tribulation Transcendence", "nanite": "Nanite Storm"},
	{"name": "Immortal Ascension", "nanite": "Nanite Heaven"},
]
## "always have a way forward": past the last named realm the road goes on --
## Immortal Realm I, II, III... (realm_info)
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

# ---- progress (everything below is saved) ----
var realm := 0            # index into REALMS
var sublevel := 1         # 1..10
var qi := 0.0
var hp := 100
var gold := 20
var inventory := {}       # item_id -> count
var weapon := ""          # item_id or ""
## Round 27: everything you wear sits in `equipment` (slot -> item id; the
## slots are data/gear.json's). armor / ring / amulet are the old names for
## three of those slots and still read and write them.
var equipment := {}
var armor: String:
	get:
		return str(equipment.get("chest", ""))
	set(v):
		if v == "":
			equipment.erase("chest")
		else:
			equipment["chest"] = v
var ring: String:
	get:
		return str(equipment.get("ring_l1", ""))
	set(v):
		if v == "":
			equipment.erase("ring_l1")
		else:
			equipment["ring_l1"] = v
var amulet: String:
	get:
		return str(equipment.get("necklace", ""))
	set(v):
		if v == "":
			equipment.erase("necklace")
		else:
			equipment["necklace"] = v
var quests := {}          # quest_id -> "active" | "done"
var kills := {}           # enemy_type -> count
var flags := {}           # world state: opened chests, found secrets, gathered nodes
var current_level := "village"
var spawn_tag := "P"
var meditating := false
var playtime := 0.0
var techniques := {}      # technique_id -> true, once learned
var counters := {}        # discovery counters: "talk:Little Rin", "shrine_seconds", "coins"...
var lore_read := {}       # lore stones already read (key -> true)
var skills := {}          # skill_id -> xp  (mining, herbalism, smithing, alchemy...)
var journal := {"items": {}, "places": {}}   # what you've found, where, and what it's for
var affinity := {"wood": 0.0, "fire": 0.0, "earth": 0.0, "metal": 0.0, "water": 0.0}
var guilds := {}          # guild_id -> {"rep": float, "contract": {...}}
var familiar := {}        # {"species", "name", "bond"} -- an animal that chose you
var bonds := {}           # npc name -> {"warmth", "talks", "memories": [...]}
var companion := {}        # who travels with you: {"name", "persona", "tint", "home", "partner"}
var companion2 := {}       # round 39: the second of a party of two (same shape)
var contracts := []        # round 39: every contract beast ({"species","name","bond","tier","out","lead"}); `familiar` is the lead
var partner := ""          # the one who said yes to more than company
var depth := 0               # the floor you're on (Level.build sets it): what drops, drops for this depth
var arena := {}            # the fight in progress (Arena.gd), or the last result to report
var academy := {"trials": {}, "enrolled": false, "rank": 0, "merit": 0.0}
var rivals := {}           # rival name -> {"met", "beat", "lost"}: you beat them / they beat you
var titles := []           # what tournaments and the Academy have named you
var last_haven := "village"   # the last town you reached: where you wake if you fall
var havens := {}              # level id -> name, every town you've reached
var background := ""          # who you were before the road (BACKGROUNDS); "" = not chosen yet
var focus := {}               # skill id -> {"v", "t"}: how deep in one craft you are right now
var custom_items := {}        # item id -> def: pieces made for you (tailored, wished for) -- saved with you
var wishes := {}              # settlement level id -> wishes used there (WISHES_PER_SETTLEMENT)
var moments := []             # the last few things you did that weren't in any menu (the world remembers)
var _legacy_save := false     # a save from before backgrounds: asked once, nothing taken away
# People you can talk to freely speak through the box's own local model.
var llm_url := "http://127.0.0.1:11434/api/chat"
var llm_model := "qwen2.5:latest"
var llm_override := Callable()   # tools/tests answer instead of the model
const BOND_STAGES := [[0, "a stranger"], [15, "an acquaintance"], [35, "a friend"], [60, "a close friend"], [85, "devoted to you"]]
const COMPANION_WARMTH := 60.0     # a close friend may come along, if they choose
const PARTNER_WARMTH := 85.0       # someone devoted may choose more than company
const ASK_AGAIN_SECONDS := 300.0   # a "not now" is not a "never" -- ask again later
## Walking the road together with a partner: steadier, and you cultivate
## better side by side.
const PARTNER_EFFECT := {"damage_taken": 0.95, "meditate_mult": 1.2, "qi_mult": 1.05}

# ---- content, loaded from res://data ----
var items := {}
var enemies := {}
var recipes := []
var quest_defs := {}
var technique_defs := {}
var skill_defs := {}
var guild_defs := {}
const RIVAL_REP_MULT := 0.5        # belong to rivals and each trusts you half as much

# ---- growth: skills, crafting quality, the five elements ----
const ELEMENTS := ["wood", "fire", "earth", "metal", "water"]
# the generating cycle (each feeds the next) and the overcoming cycle (each
# beats one) -- the old five-phase theory cultivators actually use. Two
# strong elements that feed each other SYNERGIZE; two that fight CLASH.
const GENERATES := {"wood": "fire", "fire": "earth", "earth": "metal", "metal": "water", "water": "wood"}
const OVERCOMES := {"water": "fire", "fire": "metal", "metal": "wood", "wood": "earth", "earth": "water"}
const AFFINITY_ACTIVE := 25.0      # an element this strong is part of who you are
const CLASH_GAP := 15.0            # ...and one this close to its rival fights it
const QUALITY := [
	{"id": "crude", "name": "Crude", "mult": 0.8},
	{"id": "", "name": "", "mult": 1.0},
	{"id": "fine", "name": "Fine", "mult": 1.15},
	{"id": "superior", "name": "Superior", "mult": 1.35},
	{"id": "masterwork", "name": "Masterwork", "mult": 1.6},
]
const INTENTS := {
	"careful": {"name": "Carefully", "success": 0.15, "quality": -1, "desc": "safer, but it won't be better than Fine"},
	"balanced": {"name": "Steadily", "success": 0.0, "quality": 0, "desc": "your honest best"},
	"bold": {"name": "Boldly", "success": -0.2, "quality": 1, "desc": "riskier -- the only way to a Masterwork"},
}
## Weapon kinds (Robert, 2026-10-02: "make sure weapons are being dropped and
## found as well as able to be made"). A kind decides how a weapon plays --
## an item can still set its own "speed" / "reach" / "effect".
const WEAPON_KINDS := {
	"sword": {"name": "Sword", "speed": 1.0, "reach": 0.0, "note": "balanced"},
	"dagger": {"name": "Dagger", "speed": 1.4, "reach": -0.4, "note": "fast, short"},
	"saber": {"name": "Saber", "speed": 1.15, "reach": 0.1, "note": "quick cuts"},
	"spear": {"name": "Spear", "speed": 0.9, "reach": 1.1, "note": "long reach"},
	"axe": {"name": "Axe", "speed": 0.8, "reach": 0.2, "note": "heavy blows"},
	"hammer": {"name": "Hammer", "speed": 0.7, "reach": 0.1, "note": "slow, crushing"},
	"halberd": {"name": "Halberd", "speed": 0.78, "reach": 1.3, "note": "slow, long, brutal"},
	"staff": {"name": "Staff", "speed": 1.0, "reach": 0.7, "note": "qi flows through it"},
	"fists": {"name": "Fist Wraps", "speed": 1.6, "reach": -0.6, "note": "a flurry"},
	# round 119 (Robert: "long range weapons ... ki and energy and bow and crossbow, maybe not in the first few floors"):
	# these shoot -- click for a quick shot, hold to draw a harder one (data/combat.json "ranged")
	"bow": {"name": "Bow", "speed": 1.0, "reach": -0.6, "ranged": true, "note": "loose from afar; hold to draw"},
	"crossbow": {"name": "Crossbow", "speed": 0.7, "reach": -0.6, "ranged": true, "note": "slow, hard bolts that pierce"},
	"ki": {"name": "Qi Focus", "speed": 1.1, "reach": -0.6, "ranged": true, "note": "hurl your own qi; it needs a breath between bursts"},
}
## the first floor a distance weapon can turn up (drops go by an item's "tier"; made-for-you gear by depth)
const RANGED_MIN_TIER := 5
## Found gear isn't always good gear: what a drop turns out to be.
const DROP_QUALITY_WEIGHTS := [22.0, 46.0, 20.0, 9.0, 3.0]
const BODY_DROP_SHARE := 0.45     # round 27: of gear drops, how many are the rest of the body (and jewellery)
const GEAR_CHANCE := 0.03          # an ordinary monster, now and then
const BRUTE_GEAR_CHANCE := 0.07    # a big one (hp well above its floor's)
const SKILL_TITLES := [[0, "Novice"], [5, "Apprentice"], [10, "Journeyman"], [20, "Expert"], [35, "Master"], [50, "Grandmaster"]]

## Who you were before the road (Robert, 2026-10-02: "No one is proficient
## with anything from the start except one skill plus hand to hand combat
## and survival"). Everyone starts an Apprentice (level 5) at Unarmed and
## Survival, and at the ONE skill their background gave them; everything
## else -- every other craft, every weapon -- starts at nothing and grows
## with use. An untrained hand with a sword hits like a novice (see
## proficiency_mult).
const START_XP := 250.0            # level 5, Apprentice
const BACKGROUNDS := {
	"smith": {"name": "Forge-hand", "group": "craft", "skill": "smithing", "items": {"iron_ore": 4},
		"desc": "You pumped the bellows in a village forge until you could read heat by colour."},
	"alchemist": {"name": "Furnace-tender", "group": "craft", "skill": "alchemy", "items": {"qi_pill": 1, "spirit_herb": 2},
		"desc": "You kept an alchemist's fires and learned which smoke means ruin."},
	"physician": {"name": "Physician's Apprentice", "group": "craft", "skill": "medicine", "items": {"healing_salve": 3},
		"desc": "You held the bowl, then the needle, then the patient's trust."},
	"jeweler": {"name": "Jeweler's Apprentice", "group": "craft", "skill": "jewelcrafting", "items": {"rough_jade": 2},
		"desc": "You polished other people's stones until you could see what was inside them."},
	"miner": {"name": "Mine-runner", "group": "gather", "skill": "mining", "items": {"iron_ore": 2, "gold": 15},
		"desc": "You grew up underground, carrying ore and listening to the rock."},
	"herbalist": {"name": "Herb-picker", "group": "gather", "skill": "herbalism", "items": {"healing_salve": 1, "spirit_herb": 3},
		"desc": "You know a plant by its leaf, its smell and what it drinks."},
	"fisher": {"name": "Fisher", "group": "gather", "skill": "fishing", "items": {"carp_oil_salve": 1},
		"desc": "Patience, mostly. You've waited out worse than a dungeon."},
	"hunter": {"name": "Hunter", "group": "gather", "skill": "hunting", "items": {"raw_meat": 3, "hunting_knife": 1},
		"desc": "Tracking, waiting, and a clean kill. You hunted the hills above Eliet."},
	"swordsman": {"name": "Sword-school Dropout", "group": "weapon", "skill": "sword", "items": {"iron_sword": 1},
		"desc": "Three years at a sword school before the money ran out. Your stance is still good."},
	"spearman": {"name": "Militia Spear", "group": "weapon", "skill": "spear", "items": {"practice_spear": 1},
		"desc": "You stood a wall with the village militia. Distance is the whole art."},
	"cutpurse": {"name": "Street Knife", "group": "weapon", "skill": "dagger", "items": {"hunting_knife": 1, "gold": 10},
		"desc": "Quick hands, quicker feet. Nobody asks where you learned it."},
	"woodcutter": {"name": "Woodcutter", "group": "weapon", "skill": "axe", "items": {"woodcutters_axe": 1},
		"desc": "Ten thousand logs split. A goblin is not so different."},
	"wanderer": {"name": "Temple Wanderer", "group": "weapon", "skill": "staff", "items": {"quarterstaff": 1, "qi_pill": 1},
		"desc": "A monk's staff, a monk's patience, and no temple left to go back to."},
}
const WEAPON_SKILL := {"sword": "sword", "dagger": "dagger", "saber": "saber", "spear": "spear", "axe": "axe",
	"hammer": "hammer", "halberd": "halberd", "staff": "staff", "fists": "unarmed",
	"bow": "bow", "crossbow": "crossbow", "ki": "ki"}
## Focus: staying with one craft is rewarded (Robert: "more focus in a task
## could be more rewarding"). Every use of a skill deepens its focus; time
## away lets it fade (half-life FOCUS_HALF_LIFE seconds of play).
const FOCUS_HALF_LIFE := 600.0
const FOCUS_CAP := 30.0
const FOCUS_STEP_XP := 0.025       # +2.5% skill growth per point of focus, up to +50% at 20
## Free-text moments (HUD "T"): one try every MOMENT_COOLDOWN real seconds.
const MOMENT_COOLDOWN := 180.0
const WISHES_PER_SETTLEMENT := 3
## How a weapon kind's damage compares (the same factors the floor forge uses).
const KIND_DAMAGE := {"sword": 1.0, "dagger": 0.7, "fists": 0.6, "saber": 0.9, "spear": 0.95, "axe": 1.3, "hammer": 1.45, "halberd": 1.25, "staff": 0.85, "bow": 0.85, "crossbow": 1.15, "ki": 0.8}
## What a made-for-you ring/amulet/armor/weapon may carry, and how strong it
## can be at a depth: [base, per floor, cap]; multiplicative keys are 1 + x.
const DESIGN_EFFECTS := {
	"hp_mult": [0.03, 0.003, 0.14], "damage_mult": [0.03, 0.003, 0.14], "qi_mult": [0.03, 0.003, 0.14],
	"damage_taken": [0.03, 0.002, 0.10], "attack_speed": [0.03, 0.002, 0.10], "meditate_mult": [0.08, 0.008, 0.35],
	"gather_chance": [0.06, 0.008, 0.3], "heal_on_kill": [2.0, 0.5, 15.0], "sense_radius": [2.0, 0.2, 8.0],
	"craft_success": [0.04, 0.003, 0.12], "craft_quality": [0.03, 0.002, 0.09],
}

var playlog_path := "user://playlog.jsonl"   # tools/ point this elsewhere
const PLAYLOG_MAX_BYTES := 2000000
var _level_entered_at := 0.0

var _autosave_timer := 0.0


func _ready() -> void:
	migrate_user_dir()                      # round 56: saves from when the game was "Dungeon Crawl Eliet"
	items = _load_json("res://data/items.json", {})
	enemies = _load_json("res://data/enemies.json", {})
	recipes = _load_json("res://data/recipes.json", [])
	quest_defs = _load_json("res://data/quests.json", {})
	technique_defs = _load_json("res://data/techniques.json", {})
	skill_defs = _load_json("res://data/skills.json", {})
	guild_defs = _load_json("res://data/guilds.json", {})
	_merge_lattice_defs()
	_merge_valley_arts()
	_merge_round27_items()
	_merge_runes()                          # round 38: rune craft and talismans
	_init_systems()                         # round 40: the modular systems (scripts/systems/)
	hm_data()                               # round 34: the hidden masters' own techniques
	_setup_input()
	_round30_ready()
	if OS.has_feature("android"):
		llm_url = ""                        # round 56: the Google Play build stands alone -- no box to ask
		if OS.has_feature("beta"):             # the phone test build: offer updates from the box when it is reachable
			var bu = load("res://scripts/core/BetaUpdate.gd")
			if bu:
				var bn = bu.new()
				bn.name = "BetaUpdate"
				add_child.call_deferred(bn)
	cloudsave = CloudSaveScript.new()                # round 124: cloud saves -- idle until set up and signed in
	cloudsave.name = "CloudSave"
	cloudsave.bind(self)
	add_child.call_deferred(cloudsave)
	online = OnlineScript.new()                       # round 125: Elite Online -- idle until you step through the Gate
	online.name = "Online"
	add_child.call_deferred(online)
	if not FileAccess.file_exists("user://ai_on.txt"):
		llm_url = ""                        # round 119: no AI model asked by default -- it shared the player's own graphics card and made play laggy; the game answers from its own words. Make a file named ai_on.txt in the game's user folder to turn it on.
	if OS.has_feature("web"):
		# in a browser (the phone version, round 29) 127.0.0.1 is the phone:
		# ask the box's model through the server the page came from
		# (Godot Studio passes it on to Ollama: godot_web.llm_chat)
		var origin = JavaScriptBridge.eval("window.location.origin", true)
		if origin is String and str(origin).begins_with("http"):
			llm_url = str(origin) + "/api/llm_chat"


func _exit_tree() -> void:
	TranslationServer.clear()          # round 141: the phrase catalogs hold compiled patterns; let go of them before the engine shuts down


func _process(delta: float) -> void:
	if _hitstop_until > 0 and Time.get_ticks_msec() >= _hitstop_until:
		_hitstop_until = 0
		Engine.time_scale = 1.0                # round 37: a hit-stop always ends, whatever happened meanwhile
	playtime += delta
	if downtime_live:
		_downtime_tick(delta)
	if not contracts.is_empty():
		_rest_tick(delta)                       # round 39: resting beasts grow too
	_systems_tick(delta)                        # round 40
	_autosave_timer += delta
	if _autosave_timer > 60.0:
		_autosave_timer = 0.0
		save_game()


# ======================================================================
# cultivation
# ======================================================================

func step_index() -> int:
	## 0 for Body Tempering 1, 49 for Nascent Soul 10.
	return realm * SUBLEVELS + (sublevel - 1)


func realm_info(i: int) -> Dictionary:
	if i < REALMS.size():
		return REALMS[maxi(i, 0)]
	var n := i - REALMS.size()
	var tag: String = str(ROMAN[n]) if n < ROMAN.size() else str(n + 1)
	return {"name": I18n.t("Immortal Realm ") + tag, "nanite": I18n.t("Nanite Infinity ") + tag}


func qi_to_next() -> float:
	## x1.16 a step (2026-10-02; was x1.28, which put Core Formation tens of
	## thousands of qi a step away -- out of reach of floor 9's inheritance,
	## and endless floors need a curve the monsters can keep pace with).
	var need := 40.0 * pow(1.16, step_index())
	if sublevel == SUBLEVELS:
		need *= 2.0           # crossing into a new realm is a breakthrough
	return round(need)


func realm_name() -> String:
	return str(realm_info(realm)["name"])


func cultivation_label() -> String:
	return "%s %d/%d" % [realm_name(), sublevel, SUBLEVELS]


func nanite_label() -> String:
	## the swarm has its own road now (round 21): its tier, not your realm
	return tier_name()


func add_qi(amount: float, source: String = "") -> void:
	if amount <= 0:
		return
	amount *= tech_effect("qi_mult", 1.0) * growth_mult()
	qi += amount
	if source != "":
		message.emit("+%d qi (%s)" % [int(amount), source])
	while qi >= qi_to_next():
		if sublevel == SUBLEVELS:
			# round 25: the realm crossing waits for comprehension and the
			# tribulation -- the sea of qi stays full until then
			qi = qi_to_next()
			if not has_flag("threshold:%d" % realm):
				set_flag("threshold:%d" % realm)
				var miss := breakthrough_missing()
				message.emit(I18n.t("THE SEA IS FULL: %s.") % (I18n.t("you're ready -- sit (M) and face your tribulation") if miss.is_empty() else I18n.t("to break through you still need ") + ", ".join(miss)))
			stats_changed.emit()
			return
		qi -= qi_to_next()
		var snap0 := stat_snapshot()
		sublevel += 1
		level_up_note(snap0, "step")                 # round 36: the level-up window
		message.emit(I18n.t("Cultivation rises: %s") % cultivation_label())
		jingle("levelup")
		log_event("levelup", {"label": cultivation_label()})
		hp = max_hp()        # a level-up refills you
	stats_changed.emit()


func max_hp() -> int:
	var bonus := worn_hp()
	return int(round((100 + step_index() * 14 + realm * 40 + bonus) * tech_effect("hp_mult", 1.0) * Hook.power("hp")))


func damage() -> int:
	return weapon_damage(weapon)


func weapon_damage(id: String) -> int:
	## What a strike deals with this weapon in hand ("" = bare hands): your
	## cultivation plus the weapon, times how well you know its kind.
	var bonus := 0
	if id != "" and has_item_def(id):
		bonus = int(item_def(id).get("damage", 0))
	return maxi(1, int(round((9 + step_index() * 2 + realm * 6 + bonus) * tech_effect("damage_mult", 1.0) * proficiency_mult(id) * Hook.power("dmg"))))


# ---- weapon proficiency: every kind is its own skill -------------------------

func weapon_skill(id: String = "") -> String:
	## The skill a weapon trains ("" = bare hands -> Unarmed).
	var w := id if id != "" else weapon
	if w == "" or not has_item_def(w):
		return "unarmed"
	return str(WEAPON_SKILL.get(str(item_def(w).get("kind", "sword")), "sword"))


func proficiency_mult(id: String = "") -> float:
	## x0.65 untrained, x1.0 at Apprentice (5), then +2% a level -- it never
	## stops growing, it just slows.
	var lvl := skill_level(weapon_skill(id))
	if lvl < 5:
		return 0.65 + 0.07 * lvl
	return 1.0 + 0.02 * (lvl - 5)


func proficiency_speed(id: String = "") -> float:
	## An untrained swing is a slow swing: x0.85 at 0, x1.0 at 5, up to x1.15.
	var lvl := skill_level(weapon_skill(id))
	if lvl < 5:
		return 0.85 + 0.03 * lvl
	return minf(1.0 + 0.01 * (lvl - 5), 1.15)


func proficiency_text(id: String = "") -> String:
	var sk := weapon_skill(id)
	var lvl := skill_level(sk)
	var t := "%s %d (%s)" % [skill_name(sk), lvl, skill_title(sk)]
	if lvl < 5:
		t += I18n.t(" -- untrained: %d%% damage") % int(round(proficiency_mult(id) * 100))
	return t


func train_weapon(hits: int, kill_hp: int = 0) -> void:
	## Every landed blow teaches the hand holding it; a kill teaches more.
	if hits <= 0 and kill_hp <= 0:
		return
	var sk := weapon_skill()
	var xp := float(hits) * (2.0 + 0.25 * float(depth))
	if kill_hp > 0:
		xp += 4.0 + float(kill_hp) / 25.0
	add_skill_xp(sk, xp, "fighting")


# ---- survival: everyone has some; the deep rewards more -------------------------

func survival_trap_mult() -> float:
	## Traps bite less once you know their tells: -2.5% a level, at most -60%.
	return maxf(0.4, 1.0 - 0.025 * skill_level("survival"))


func survival_heal_mult() -> float:
	## Field-dressing: every salve and broth goes 2% further a level.
	return 1.0 + 0.02 * skill_level("survival")


func survival_regen() -> float:
	## HP a second that your wounds close on their own between fights.
	return float(max_hp()) * 0.0008 * skill_level("survival")


# ======================================================================
# health
# ======================================================================

func hurt(amount: int) -> void:
	if sys("tester") != null and sys("tester").god():
		return                      # round 156: test kit -- god mode
	amount = int(round(amount * tech_effect("damage_taken", 1.0) * ward_factor()))
	hp = max(hp - amount, 0)
	last_hurt_at = Time.get_unix_time_from_system()
	trial_note_hurt(amount)
	stats_changed.emit()


func heal(amount: int) -> void:
	hp = min(hp + amount, max_hp())
	stats_changed.emit()


func player_died(cause: String = "", where: Vector2i = Vector2i.ZERO) -> void:
	if sys("tester") != null and sys("tester").god():
		hp = max_hp()                # round 156: test kit -- god mode, nothing ends you
		stats_changed.emit()
		return
	if str(current_level).begins_with("tribulation:"):
		tribulation_lost()         # a setback, not a death: no gold, no haven walk
		return
	if Arena.is_arena(current_level):
		arena_lost(cause)      # carried out of the ring -- no gold lost
		return
	log_event("death", {"cause": cause, "cell": [where.x, where.y]})
	jingle("death")
	add_skill_xp("survival", 10.0 + float(depth), "a hard lesson")
	var lost := 0 if tech_effect("keep_gold", 0.0) > 0.0 else int(gold * 0.1)
	gold -= lost
	hp = max_hp()
	meditating = false
	if lost > 0:
		message.emit(I18n.t("You fall... and wake in %s. (-%d gold)") % [haven_name(), lost])
	else:
		message.emit("You fall... and wake in %s. Your gold is safe inside the ring." % haven_name())
	if last_haven == "" or (last_haven != "village" and not FileAccess.file_exists("res://levels/%s.json" % last_haven)):
		last_haven = "village"      # that town's gone (renamed / removed): home
	if store and store.level_locked(last_haven):
		last_haven = free_haven()   # (round 58: a refunded full game -- wake in the deepest free town)
	if ads:
		ads.last_fall_gold = lost   # (round 58: on the free tier, a gift can give it back)
	go_to(last_haven, "P")


func haven_name() -> String:
	return I18n.t("the village") if last_haven == "village" or last_haven == "" else str(havens.get(last_haven, last_haven))


func enter_haven(level_id: String, display_name: String) -> void:
	## Reaching a town makes it home: fall below and you wake here.
	var first := not havens.has(level_id)
	havens[level_id] = display_name
	if last_haven != level_id:
		last_haven = level_id
		if level_id != "village":
			message.emit("HAVEN: %s. If you fall in the deep, you'll wake here now." % display_name)
	if first and level_id != "village":
		note_place(I18n.t("Reached ") + display_name)
		log_event("haven", {"id": level_id})


# ======================================================================
# inventory, gear, crafting
# ======================================================================

func item_name(id: String) -> String:
	return str(item_def(id).get("name", id))


func base_id(id: String) -> String:
	return id.get_slice("@", 0)


func has_item_def(id: String) -> bool:
	return items.has(base_id(id))


func item_def(id: String) -> Dictionary:
	## "iron_sword@fine" is a Fine Iron Sword: the base item, its numbers
	## scaled by quality, its name prefixed. Plain ids come back as-is.
	var b := base_id(id)
	if not items.has(b):
		return {}
	if b == id:
		return items[b]
	var qi_ := quality_index(id)
	var q: Dictionary = QUALITY[qi_]
	var d: Dictionary = items[b].duplicate(true)
	for k in ["damage", "hp", "heal", "qi"]:
		if d.has(k):
			d[k] = int(round(float(d[k]) * float(q["mult"])))
	d["name"] = ("%s %s" % [q["name"], d.get("name", b)]).strip_edges()
	d["value"] = int(round(float(d.get("value", 1)) * float(q["mult"]) * float(q["mult"])))
	d["quality"] = q["id"]
	return d


func quality_index(id: String) -> int:
	var tag := id.get_slice("@", 1) if id.contains("@") else ""
	for i in QUALITY.size():
		if QUALITY[i]["id"] == tag:
			return i
	return 1


func count(id: String) -> int:
	return int(inventory.get(id, 0))


func add_item(id: String, n: int = 1, announce: bool = true) -> void:
	if n <= 0:
		return
	if id == "gold":
		gold += n
	else:
		var def: Dictionary = item_def(id)
		if def.get("type") == "treasure":
			if count(id) > 0:
				return            # one of a kind
			inventory[id] = 1
			note_item(id)
			message.emit(I18n.t("TREASURE: %s -- %s") % [item_name(id), def.get("desc", "")])
			log_event("treasure", {"id": id})
			if def.has("sips"):
				counters["gourd_sips"] = float(def["sips"])
			stats_changed.emit()
			return
		if def.get("type") == "formula":
			learn_formula(str(def.get("formula", "")), "bought")
			stats_changed.emit()
			return
		if def.get("type") == "material" and count(id) + n > pouch_cap():
			var room := maxi(pouch_cap() - count(id), 0)
			var extra := n - room
			if (has_home() or (sys("tester") != null and sys("tester").vault_on())) and extra > 0:
				# nothing earned is lost: what the pouch can't hold goes to the chest at home
				var st0: Dictionary = stash_ref()
				st0[id] = int(st0.get(id, 0)) + extra
				home["stash"] = st0
				message.emit(I18n.t("Your pouch is full of %s (%d) -- %d went to your chest at home.") % [item_name(id), pouch_cap(), extra])
			else:
				message.emit(I18n.t("Your pouch is full of %s (%d) -- the rest is left behind. A storage ring would hold more.") % [item_name(id), pouch_cap()])
			log_event("pouch_full", {"id": id})
			n = room
			if n <= 0:
				stats_changed.emit()
				return
		inventory[id] = count(id) + n
		note_item(id)
		if loot_source != "" and sys("craftbook") != null:
			sys("craftbook").note_drop(loot_source, id)
		# better gear equips itself -- one less menu to dig through
		if def.get("type") == "weapon" and _gear_value(id, "damage") > _gear_value(weapon, "damage"):
			weapon = id
			message.emit("Equipped %s." % item_name(id))
		elif def.get("type") == "weapon" and int(def.get("damage", 0)) > int(item_def(weapon).get("damage", 0)) and skill_level(weapon_skill(id)) < 5:
			message.emit(I18n.t("The %s is better steel than you can use yet -- %s. (Equip it from the inventory to start learning.)") % [item_name(id), proficiency_text(id)])
		else:
			_auto_wear(id)
	if announce:
		message.emit("+%d %s" % [n, item_name(id)])
	stats_changed.emit()


func remove_item(id: String, n: int = 1) -> bool:
	if n < 0:
		return false                      # (round 57: taking a negative number would GIVE things)
	if id == "gold":
		if gold < n:
			return false
		gold -= n
	else:
		if count(id) < n:
			return false
		if sys("tester") != null and sys("tester").free_item(id):
			stats_changed.emit()
			return true                   # round 158: the test kit's unlimited materials are never used up
		inventory[id] = count(id) - n
		if inventory[id] <= 0:
			inventory.erase(id)
			inscriptions.erase(id)         # round 38: the runes went with it
		_fix_equipment(id)
	stats_changed.emit()
	return true


func _gear_value(id: String, key: String) -> int:
	if key == "damage" and (id == "" or not has_item_def(id)):
		return int(round(float(weapon_damage("")) * proficiency_speed("")))    # bare hands
	if id == "" or not has_item_def(id):
		return 0
	if key == "damage":
		# a fast dagger and a slow hammer compare by what they deal over time --
		# in YOUR hands (a sword you've never trained with can lose to your fists)
		return int(round(float(weapon_damage(id)) * weapon_speed(id) * proficiency_speed(id)))
	return int(item_def(id).get(key, 0))


func use_item(id: String) -> bool:
	if count(id) <= 0:
		message.emit("You have no %s." % item_name(id))
		return false
	var def: Dictionary = item_def(id)
	if def.get("type") != "consumable":
		return false
	remove_item(id, 1)
	log_event("use_item", {"id": id})                      # round 121: the Mender's deeds
	if def.has("heal"):
		var amt := int(round(float(def["heal"]) * survival_heal_mult()))
		heal(amt)
		message.emit("%s: +%d HP" % [item_name(id), amt])
		add_skill_xp("survival", 1.5, "dressing a wound")
		glimpse("salve")                                    # round 122: Mending Breath grows from tending wounds
	if def.has("qi"):
		add_qi(float(def["qi"]), item_name(id))
	if def.has("heal") and not injury.is_empty():
		mend_injuries(20.0)            # a salve eases an injured meridian too
	if def.get("aid", null) is Dictionary:
		light_incense(float(def["aid"].get("mult", 1.5)), float(def["aid"].get("seconds", 600.0)))
	for e in def.get("attune", {}):
		attune(str(e), float(def["attune"][e]))
	if def.has("blood"):
		blood_essence(str(def["blood"]))       # a drop of old blood (round 30)
	if def.has("cleanse") and sys("cleansing"):
		message.emit(sys("cleansing").use_pill(float(def["cleanse"])))      # round 40
	if def.get("coat", null) is Dictionary and sys("poison") != null:                   # round 138: a weapon coating
		var ct: String = sys("poison").apply_coating(def["coat"], item_name(id))
		if ct != "":
			message.emit(ct)
	if def.has("antidote") and sys("poison") != null:
		message.emit(sys("poison").antidote(float(def["antidote"])))
	if def.get("buff", null) is Dictionary:
		# round 34: a whetstone, incense, a salve -- it lasts a while
		var b: Dictionary = def["buff"]
		var secs := float(b.get("seconds", 600))
		if bool(def.get("meal", false)) and sys("cooking") != null:
			secs *= sys("cooking").stretch()            # round 164: a practised cook's meals last longer
		add_buff(base_id(id), b.get("effect", {}), secs)
		message.emit(I18n.t("%s: %s for %s.") % [item_name(id), str(def.get("desc", "")).get_slice(":", 1).strip_edges() if str(def.get("desc", "")).contains(":") else I18n.t("its effect"), _dur(secs)])
	return true


func use_best(base: String) -> bool:
	## Key 1 / key 2: drink the best-quality one you carry.
	var best := ""
	var best_q := -1
	for id in inventory:
		if base_id(id) == base and count(id) > 0 and quality_index(id) > best_q:
			best = id
			best_q = quality_index(id)
	if best == "":
		message.emit("You have no %s." % item_name(base))
		return false
	return use_item(best)


func can_craft(recipe: Dictionary) -> bool:
	if sys("tester") != null:
		sys("tester").pull_for(recipe)      # round 156: the vault feeds the table
	if not skill_known(str(recipe.get("skill", "smithing"))):
		return false                      # round 38: a craft you haven't been taught
	if gold < int(recipe.get("gold", 0)):
		return false
	for need in recipe.get("needs", {}):
		if count(need) < int(recipe["needs"][need]):
			return false
	return true


func craft(recipe: Dictionary, intent: String = "balanced") -> bool:
	return bool(craft_attempt(recipe, intent).get("ok", false))


func craft_chance(recipe: Dictionary, intent: String = "balanced") -> float:
	## The odds you see before you commit: your skill against the work,
	## how you approach it, and what your affinities and techniques add.
	var lvl := skill_level(str(recipe.get("skill", "smithing")))
	var diff := int(recipe.get("difficulty", 0))
	var c := 0.7 + (lvl - diff) * 0.07 + float(INTENTS.get(intent, INTENTS["balanced"])["success"])
	c += tech_effect("craft_success", 0.0) + tech_effect("craft_success_" + str(recipe.get("skill", "")), 0.0)
	c += 0.06 * focus_bonus(str(recipe.get("skill", "smithing")))     # in the flow: steadier hands
	return clampf(c, 0.05, 0.97)


func craft_attempt(recipe: Dictionary, intent: String = "balanced", roll: float = -1.0, qroll: float = -1.0, design: Dictionary = {}) -> Dictionary:
	## {ok, success, item, quality, chance, lost, text}. ok=false means you
	## couldn't even try (missing materials). A failed craft is a real
	## result: some materials are lost, some skill is learned.
	if not can_craft(recipe):
		return {"ok": false, "text": "You're missing something for that."}
	var sk := str(recipe.get("skill", "smithing"))
	if not Design.has_section(sk):
		design = {}
	if not Design.is_plain(design):
		var dwhy := Design.check(sk, design, skill_level(sk))
		if dwhy != "":
			return {"ok": false, "text": dwhy}
	var diff := int(recipe.get("difficulty", 0))
	var chance := craft_chance(recipe, intent)
	var pl := craft_play_apply(roll, qroll)                # round 141c: the mini-game's result, if one was played
	var r := float(pl["roll"]) if float(pl["roll"]) >= 0.0 else randf()
	gold -= int(recipe.get("gold", 0))
	var xp := (10.0 + diff * 4.0) * float(pl["xp"])
	if r >= chance:
		var lost := []
		for need in recipe.get("needs", {}):
			var n := int(ceil(int(recipe["needs"][need]) / 2.0))
			remove_item(need, n)
			lost.append("%d %s" % [n, item_name(need)])
		add_skill_xp(sk, xp * 0.4, "a failed attempt")
		log_event("craft", {"makes": recipe["makes"], "success": false, "intent": intent, "chance": snappedf(chance, 0.01)})
		sfx("thud", 0.7)                                # round 146: a failed piece sounds like one
		var t := "It goes wrong -- %s lost. You learned something from it, though." % ", ".join(lost)
		message.emit(t)
		stats_changed.emit()
		return {"ok": true, "success": false, "chance": chance, "lost": lost, "text": t}
	for need in recipe.get("needs", {}):
		remove_item(need, int(recipe["needs"][need]))
	if int(recipe.get("needs", {}).get("nanite_shard", 0)) > 0:
		integrate(_ng("craft_per_shard", 10.0) * int(recipe["needs"]["nanite_shard"]), "nanite work")    # working nanites grows the swarm
	var q := craft_quality(recipe, intent, float(pl["qroll"]))
	var made := str(recipe["makes"]) + ("" if QUALITY[q]["id"] == "" else "@" + str(QUALITY[q]["id"]))
	if not Design.is_plain(design):
		Design.take(sk, design)
		var dd: Dictionary = Design.apply(sk, item_def(made), design)
		var doses := 1 + maxi(int(dd.get("design_dose", 0)), 0)
		dd.erase("design_dose")
		var did := _register_custom("c27_", dd)
		add_item(did, doses, false)
		made = did
		for dk in design:
			if str(design[dk]) in ["spirit", "ember", "moon"]:
				add_skill_xp("herbalism", 6.0, "a tincture")
				guild_event("craft:herbalism")
	else:
		add_item(made, 1)
	add_skill_xp(sk, xp * (1.0 + 0.25 * max(q - 1, 0)), "crafting")
	add_qi(3.0 * (1 + int(recipe.get("gold", 0)) / 10), "crafting insight")
	note_use(str(recipe["makes"]), recipe)
	craftbook_note("recipe", made, recipe.get("needs", {}), sk, {"makes": str(recipe["makes"]), "design": design if not Design.is_plain(design) else {}, "q": q, "gold": int(recipe.get("gold", 0))})
	counters["crafted:" + str(recipe["makes"])] = float(counters.get("crafted:" + str(recipe["makes"]), 0.0)) + 1.0
	counters["made:" + made] = float(counters.get("made:" + made, 0.0)) + 1.0     # (the Academy's Trial of Craft)
	guild_event("craft:" + sk)
	counters["crafted_skill:" + sk] = float(counters.get("crafted_skill:" + sk, 0.0)) + 1.0     # round 34: a master's test counts these
	if q >= 2:
		guild_event("craft_fine")
	if q >= 4:
		counters["masterworks"] = float(counters.get("masterworks", 0.0)) + 1.0
	log_event("craft", {"makes": made, "success": true, "intent": intent, "quality": QUALITY[q]["id"], "chance": snappedf(chance, 0.01)})
	if q >= 4:                                          # round 146: a masterwork rings; a good piece clinks; the rest stamps
		jingle("achievement")
	else:
		sfx("hit_metal" if q >= 2 else "stamp", 0.7)
	return {"ok": true, "success": true, "item": made, "quality": q, "chance": chance,
		"text": "You made %s." % item_name(made)}


func craft_play_apply(roll: float, qroll: float) -> Dictionary:
	## what a mini-game just played is worth (scripts/systems/CraftPlay.gd): a shift on the random rolls, never on a fixed one
	var out := {"roll": roll, "qroll": qroll, "xp": 1.0}
	var cp = sys("craftplay")
	if cp == null:
		return out
	var s: float = cp.take()
	if s < 0.0 or roll >= 0.0:
		return out
	var b: Dictionary = cp.bonus(s)
	out["roll"] = clampf(randf() - float(b["chance"]), 0.0, 1.0)
	if qroll < 0.0:
		out["qroll"] = clampf(randf() - float(b["quality"]), 0.0, 1.0)
	out["xp"] = float(b["xp"])
	return out


func craft_quality(recipe: Dictionary, intent: String, qroll: float = -1.0) -> int:
	var lvl := skill_level(str(recipe.get("skill", "smithing")))
	var edge := (lvl - int(recipe.get("difficulty", 0))) * 0.05
	edge += float(INTENTS.get(intent, INTENTS["balanced"])["quality"]) * 0.15
	edge += tech_effect("craft_quality", 0.0) + tech_effect("craft_quality_" + str(recipe.get("skill", "")), 0.0)
	edge += 0.1 * focus_bonus(str(recipe.get("skill", "smithing")))    # ...and finer work
	var r := randf() if qroll < 0.0 else qroll
	var q := 1
	if intent == "bold" and r < clampf(0.02 + edge * 0.3, 0.0, 0.25):
		q = 4
	elif r < clampf(0.08 + edge * 0.6, 0.0, 0.45):
		q = 3
	elif r < clampf(0.25 + edge, 0.0, 0.75):
		q = 2
	elif r > clampf(0.85 + edge, 0.5, 1.0):
		q = 0
	if intent == "careful":
		q = clampi(q, 1, 2)
	return q


func recipe_text(recipe: Dictionary) -> String:
	var parts := []
	for need in recipe.get("needs", {}):
		parts.append("%d %s (%d)" % [int(recipe["needs"][need]), item_name(need), count(need)])
	if int(recipe.get("gold", 0)) > 0:
		parts.append(I18n.t("%d gold") % int(recipe["gold"]))
	return ", ".join(parts)


var loot_source := ""        # round 137: the foe whose loot is being rolled (the bestiary learns what it drops)


func clear_loot_source() -> void:
	loot_source = ""


func craftbook_note(kind: String, item: String, inputs: Dictionary, skill: String, meta: Dictionary = {}) -> void:
	var cb = sys("craftbook")
	if cb != null:
		cb.note_made(kind, item, inputs, skill, meta)


func roll_loot(loot: Dictionary) -> void:
	## loot: {"item_id": [min, max], ...} -- the shape enemies and chests use.
	## "random_gear" / "random_weapon" / "random_armor": that many pieces
	## of gear for this depth, each with a quality roll.
	for id in loot:
		var r = loot[id]
		var n := 0
		if r is Array and r.size() >= 2:
			n = randi_range(int(r[0]), int(r[1]))
		else:
			n = int(r)
		if str(id).begins_with("random_"):
			var kinds: Array = {"random_gear": ["weapon", "armor"], "random_weapon": ["weapon"], "random_armor": ["armor"]}.get(str(id), ["weapon", "armor"])
			for i in n:
				drop_gear(depth, 1, kinds)
			continue
		var lm = tech_effect_dict("loot_mult").get(id, 1.0)
		if lm != 1.0 and n > 0:
			n = int(ceil(n * float(lm)))
		if n > 0:
			add_item(id, n)


func gear_pool(d: int, kinds: Array = ["weapon", "armor"]) -> Array:
	## Gear that can turn up at this depth ("drop": true, "tier" within one
	## floor of it); nearest shallower tier when nothing is that close.
	var near := []
	var best_tier := -1
	for id in items:
		var it: Dictionary = items[id]
		if not bool(it.get("drop", false)) or not (str(it.get("type", "")) in kinds):
			continue
		var t := int(it.get("tier", 0))
		if absi(t - d) <= 1:
			near.append(id)
		elif t < d and t > best_tier:
			best_tier = t
	if near.is_empty() and best_tier >= 0:
		for id in items:
			var it: Dictionary = items[id]
			if bool(it.get("drop", false)) and str(it.get("type", "")) in kinds and int(it.get("tier", 0)) == best_tier:
				near.append(id)
	near.sort()
	return near


func roll_quality(boost: int = 0, roll: float = -1.0) -> int:
	## 0 crude .. 4 masterwork; boost shifts the odds up (a boss, a prize).
	var w: Array = DROP_QUALITY_WEIGHTS.duplicate()
	for b in boost:
		w = [w[0] * 0.4, w[1] * 0.7, w[2] * 1.4, w[3] * 1.8, w[4] * 2.2]
	var total := 0.0
	for x in w:
		total += float(x)
	var r := (randf() if roll < 0.0 else roll) * total
	for i in w.size():
		r -= float(w[i])
		if r <= 0.0:
			return i
	return w.size() - 1


func with_quality(id: String, qi_: int) -> String:
	var tag := str(QUALITY[clampi(qi_, 0, QUALITY.size() - 1)]["id"])
	return id if tag == "" else "%s@%s" % [id, tag]


func drop_gear(d: int, boost: int = 0, kinds: Array = ["weapon", "armor"], pick: float = -1.0) -> String:
	boost += Hook.pity_boost()                       # round 126: the luck meter tilts the odds
	if pick < 0.0 and "armor" in kinds and randf() < BODY_DROP_SHARE:
		var bp := drop_body_piece(d, boost)          # round 27: the rest of the body
		if bp != "":
			return bp
	var pool := gear_pool(d, kinds)
	if pool.is_empty():
		return ""
	var id := with_quality(str(pool[int((randf() if pick < 0.0 else pick) * pool.size()) % pool.size()]), roll_quality(boost))
	message.emit(I18n.t("FOUND: %s!%s") % [item_name(id), Hook.compare(id)])
	log_event("gear_drop", {"id": id, "depth": d})
	add_item(id, 1)
	reveal_loot(id)
	return id


func weapon_kind(id: String = "") -> Dictionary:
	var w := id if id != "" else weapon
	if w == "" or not has_item_def(w):
		return WEAPON_KINDS["fists"].merged({"name": "Bare Hands", "speed": 1.0, "reach": 0.0}, true)
	return WEAPON_KINDS.get(str(item_def(w).get("kind", "sword")), WEAPON_KINDS["sword"])


func draft_texts(brief: String) -> Dictionary:
	## round 59: Dev's words from the writing room (data/drafts/<brief>.json,
	## {"items": [{"id", "text"}]}) as id -> text; {} until there are any
	var d = _load_json("res://data/drafts/%s.json" % brief, {})
	var out := {}
	if d is Dictionary:
		for it in d.get("items", []):
			if it is Dictionary and str(it.get("id", "")) != "" and str(it.get("text", "")).strip_edges() != "":
				out[str(it["id"])] = str(it["text"]).strip_edges()
	return out


func kill_qi_at(depth_: int) -> float:
	## round 61: one ordinary kill's qi on that floor (what rewards count in)
	var tot := 0.0
	var n := 0
	for eid in enemies:
		var st: Dictionary = enemies[eid]
		if int(st.get("floor", -1)) == maxi(depth_, 1) and not bool(st.get("passive", false)) and not bool(st.get("boss", false)):
			tot += float(st.get("qi", 0))
			n += 1
	return (tot / n if n > 0 else 10.0 * pow(1.4, maxi(depth_, 1))) * KILL_QI_MULT


signal loot_reveal(id: String, quality: int)       # round 61: a Superior or Masterwork find -- a beam, a sound
var drop_pos := Vector3.INF                         # where the last foe fell (the beam rises there)


func reveal_loot(id: String) -> void:
	var tag := id.get_slice("@", 1) if id.contains("@") else ""
	var q := -1
	for i in QUALITY.size():
		if str(QUALITY[i]["id"]) == tag and tag != "":
			q = i
	Hook.found(q)
	if q >= 3:
		sfx("loot_epic" if q >= 4 else "loot_rare", 0.9)
		log_event("rare_find", {"id": id, "quality": q})
		loot_reveal.emit(id, q)


func weapon_trait(id: String = "") -> Dictionary:
	## round 60: how this kind of weapon fights (data/combat.json "weapon_traits")
	var t = combat_data().get("weapon_traits", {}).get(weapon_skill(id), {})
	return t if t is Dictionary else {}


func weapon_is_ranged(id: String = "") -> bool:
	## round 119: a bow, a crossbow, a qi focus -- it shoots instead of swinging
	var w := id if id != "" else weapon
	if w == "" or not has_item_def(w):
		return false
	return bool(weapon_kind(w).get("ranged", false))


func ranged_data(id: String = "") -> Dictionary:
	## data/combat.json "ranged": how this kind of weapon shoots
	var r = combat_data().get("ranged", {}).get(weapon_skill(id), {})
	return r if r is Dictionary else {}


func weapon_speed(id: String = "") -> float:
	var w := id if id != "" else weapon
	if w == "" or not has_item_def(w):
		return 1.0
	return float(item_def(w).get("speed", weapon_kind(w).get("speed", 1.0)))


func weapon_reach(id: String = "") -> float:
	var w := id if id != "" else weapon
	if w == "" or not has_item_def(w):
		return 0.0
	return float(item_def(w).get("reach", weapon_kind(w).get("reach", 0.0)))


func attack_speed() -> float:
	return maxf(tech_effect("attack_speed", 1.0) * weapon_speed() * proficiency_speed(), 0.35)      # r151: never so slow a swing hangs


func is_treasure(id: String) -> bool:
	return str(items.get(id, {}).get("type", "")) == "treasure"


func has_treasure(id: String) -> bool:
	return is_treasure(id) and count(id) > 0


func pouch_cap() -> int:
	## 20 of each material -- until a storage ring makes it 99.
	var cap := POUCH_CAP
	for id in inventory:
		if is_treasure(id):
			cap = maxi(cap, int(items[id].get("effect", {}).get("pouch_cap", 0)))
	return cap


func gourd_sips() -> int:
	return int(counters.get("gourd_sips", 0.0))


func drink_gourd() -> bool:
	if not has_treasure("spirit_gourd"):
		return false
	if gourd_sips() <= 0:
		message.emit("The gourd is empty. Sit at a shrine and it fills again.")
		return false
	counters["gourd_sips"] = float(gourd_sips() - 1)
	var amt := int(round(max_hp() * float(items["spirit_gourd"].get("heal_frac", 0.4))))
	heal(amt)
	message.emit(I18n.t("Spirit Gourd: +%d HP (%d sips left)") % [amt, gourd_sips()])
	log_event("gourd", {"left": gourd_sips()})
	return true


func refill_gourd() -> void:
	if has_treasure("spirit_gourd"):
		var full := int(items["spirit_gourd"].get("sips", 3))
		if gourd_sips() < full:
			counters["gourd_sips"] = float(full)
			message.emit("The Spirit Gourd fills at the shrine (%d sips)." % full)
			stats_changed.emit()


func claim_inheritance(key: String, master: String, grants: Dictionary) -> void:
	## A dead master's legacy: items, techniques, qi -- once, ever.
	set_flag(key)
	counters["legacies"] = float(counters.get("legacies", 0.0)) + 1.0
	log_event("inheritance", {"master": master})
	message.emit("INHERITANCE: you receive the legacy of %s." % master)
	for id in grants.get("items", {}):
		add_item(str(id), int(grants["items"][id]))
	for tid in grants.get("techniques", []):
		learn(str(tid), "inheritance:" + master)
	if grants.has("qi"):
		add_qi(float(grants["qi"]), master + "'s legacy")
	var bl := blood_inheritance(key, grants)     # round 30: some legacies carry the master's blood
	if bl != "":
		message.emit(I18n.t("In the legacy, a trace of %s's blood: %s.") % [master, blood_line(bl).get("name", bl)])
	stats_changed.emit()


func can_sense_hidden() -> bool:
	return has_tech("spirit_sense")


# ======================================================================
# kills and quests
# ======================================================================

func record_kill(enemy_type: String) -> void:
	Hook.on_kill(enemy_type)
	kills[enemy_type] = int(kills.get(enemy_type, 0)) + 1
	log_event("kill", {"type": enemy_type})
	if enemy_type == "heart_demon":
		tribulation_won.call_deferred()
	if not bool(enemies.get(enemy_type, {}).get("passive", false)):
		sect_contrib(1.0, "kill")
	guild_event("kill")
	if bool(enemies.get(enemy_type, {}).get("boss", false)):
		guild_event("boss")
		story_boss_killed(depth)                   # round 32
		counters["boss_floor:%d" % depth] = 1.0    # round 34: the main quest counts masters by floor
	check_unlocks()
	for qid in quests:
		if quests[qid] != "active":
			continue
		var goal: Dictionary = quest_defs.get(qid, {}).get("goal", {})
		if goal.get("kill", "") == enemy_type:
			message.emit("Quest goal met: %s -- return to Elder Mo." % quest_defs[qid]["name"])
	stats_changed.emit()


func quest_ready(qid: String) -> bool:
	var goal: Dictionary = quest_defs.get(qid, {}).get("goal", {})
	if goal.has("kill"):
		return int(kills.get(goal["kill"], 0)) >= int(goal.get("count", 1))
	if goal.has("have"):
		return count(goal["have"]) >= int(goal.get("count", 1))
	return false


func quest_available(qid: String) -> bool:
	if quests.has(qid):
		return false
	var req: String = quest_defs.get(qid, {}).get("requires", "")
	return req == "" or quests.get(req, "") == "done"


func turn_in(qid: String) -> void:
	var q: Dictionary = quest_defs[qid]
	var goal: Dictionary = q.get("goal", {})
	if goal.get("take", false) and goal.has("have"):
		remove_item(goal["have"], int(goal.get("count", 1)))
	quests[qid] = "done"
	log_event("quest_done", {"quest": qid})
	var rw: Dictionary = q.get("reward", {})
	if rw.has("gold"):
		add_item("gold", int(rw["gold"]))
	for id in rw.get("items", {}):
		add_item(id, int(rw["items"][id]))
	if rw.has("qi"):
		add_qi(float(rw["qi"]), I18n.t("quest: ") + str(q["name"]))
	message.emit("Quest complete: %s" % q["name"])


# ======================================================================
# world state flags (chests opened, secrets found, nodes gathered)
# ======================================================================

func flag_key(level_id: String, cell: Vector2i, what: String) -> String:
	return "%s:%d,%d:%s" % [level_id, cell.x, cell.y, what]


func has_flag(key: String) -> bool:
	return flags.has(key)


func set_flag(key: String, value = true) -> void:
	flags[key] = value


func gathered_recently(key: String, regrow_seconds: float) -> bool:
	if not flags.has(key):
		return false
	return Time.get_unix_time_from_system() - float(flags[key]) < regrow_seconds


# ======================================================================
# levels
# ======================================================================

func load_level_def(level_id: String) -> Dictionary:
	if OnlineGen.is_online(level_id):
		return OnlineGen.make_def(level_id, float(online.inst.get("radius", 24.0)) if online != null else 24.0)
	if Arena.is_arena(level_id):
		for eid in arena.get("defs", {}):
			enemies[eid] = arena["defs"][eid]       # rivals live in the arena, not in data/
		return Arena.generate(level_id, arena)
	if ScavengeGen.is_scavenge(level_id):
		var sp := ScavengeGen.parse(level_id)
		if sp.is_empty():
			return {}
		var from_def := load_level_def(str(sp["from"]))
		var depth := int(from_def.get("depth", 1))
		var pool := []
		var beasts := []
		for e in enemies:
			if bool(enemies[e].get("passive", false)):
				if int(enemies[e].get("floor", 99)) <= depth:
					beasts.append(e)
			elif int(enemies[e].get("floor", -1)) == depth and not bool(enemies[e].get("boss", false)):
				pool.append(e)
		return ScavengeGen.generate(level_id, depth, pool, beasts)
	if level_id.begins_with("tribulation:"):
		return tribulation_def(level_id)
	if TrialGen.is_trial(level_id):
		return trial_level_def(level_id)          # round 30: the daily trial
	if level_id == "valley":
		return ValleyGen.make_def(valley_data(), enemies)          # round 24: drawn from data/valley.json
	if FrontierGen.is_frontier(level_id):
		return FrontierGen.make_def(level_id, enemies)          # round 123: the Fallen Beacon, the Ring, the Moon ...
	if TowerGen.is_tower(level_id):
		var tp := TowerGen.parse(level_id)
		var td := tower_def(str(tp.get("id", "")))
		return TowerGen.generate(level_id, td, str(int(td.get("slot", 0)) + 1))
	var path := "res://levels/%s.json" % level_id
	var d = _load_json(path, null)
	if d == null or not (d is Dictionary):
		push_error(I18n.t("Level '%s' could not be loaded from %s") % [level_id, path])
		return {}
	return d


func lite_blocked(level_id: String) -> bool:
	if tester_unlocked():
		return false
	## round 124: in the Lite world only the village and the dungeon are there. The valley, the towers and the tech frontier are Full-world places.
	if not Gfx.world_lite():
		return false
	return level_id == "valley" or TowerGen.is_tower(level_id) or FrontierGen.is_frontier(level_id)


func online_blocked() -> String:
	## round 125: "" if this copy may use the Gate, else why not (data/online.json: require_full_game)
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/online.json")) if FileAccess.file_exists("res://data/online.json") else {}
	if d is Dictionary and bool(d.get("require_full_game", false)) and store != null and not store.full_game():
		return I18n.t("The Gate is a place of the full game. (Menu -> Unlock the full game.)")
	return ""


func lite_message() -> String:
	return I18n.t("That road is only in the Full world. (Pause menu -> Graphics fine-tune -> World: Full. Your character and save are the same either way.)")


func go_to(level_id: String, arrive_at: String) -> void:
	if lite_blocked(level_id):
		message.emit(lite_message())
		return
	var stop: String = store.travel_check(level_id) if store else ""
	if stop != "" and tester_unlocked() and not load_level_def(level_id).is_empty():
		stop = ""                       # round 159: the test kit opens every road
	if stop != "":
		# round 58: a word first (the free tier's ads, once), the full game
		# (model "locked"), or an expansion that isn't yours -- the HUD's window
		if stop == "locked":
			message.emit("Below floor %d is the full game." % store.free_depth())
		log_event("paywall", {"to": level_id, "why": stop})
		unlock_wanted.emit(level_id, arrive_at)
		return
	log_event("leave_level", {"to": level_id, "seconds": int(playtime - _level_entered_at)})
	if OnlineGen.is_online(level_id):
		if not OnlineGen.is_online(current_level):
			online_from = current_level
	elif OnlineGen.is_online(current_level) and online != null:
		online.close()                                  # round 125: out of the Gate, the connection is closed
	current_level = level_id
	spawn_tag = arrive_at
	meditating = false
	save_game()
	if cloudsave != null and cloudsave.is_inside_tree():
		cloudsave.on_travel(level_id)               # round 125: "at the start of each floor" uploads go here
	level_change_requested.emit.call_deferred(level_id, arrive_at)


# ======================================================================
# save / load (+ AFK cultivation)
# ======================================================================

# ---- round 51: three games, each its own character ----------------------------------------------
# Robert, 2026-10-04: "allow the user to have up to 3 games going that save to
# their own unique character." Slot n saves to <save_base>_slot<n>.json; the
# last one played opens next time. A save from before slots becomes slot 1
# (the old file is kept beside it). Erasing a slot keeps the file too, renamed.

var SLOTS: int:
	get:
		return 5 if (store != null and store.comfort()) else 3       # round 127: the full game's comfort
var slot := 1
var save_base := "user://save"          # tools/ point this elsewhere


func slot_path(n: int) -> String:
	return "%s_slot%d.json" % [save_base, clampi(n, 1, SLOTS)]


func _slots_meta_path() -> String:
	return save_base + "_slots.json"


func cloud_file() -> String:
	## Steam Cloud: slot 1 keeps the old file name (so an old cloud save is slot 1)
	return "eliet_save.json" if slot == 1 else "eliet_save_slot%d.json" % slot


func use_slot(n: int) -> void:
	slot = clampi(n, 1, SLOTS)
	save_path = slot_path(slot)
	var f := FileAccess.open(_slots_meta_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"last": slot}))


func last_slot() -> int:
	var d = _load_json(_slots_meta_path(), {}) if FileAccess.file_exists(_slots_meta_path()) else {}
	return clampi(int(d.get("last", 1)) if d is Dictionary else 1, 1, SLOTS)


# ---- round 56: the game's new name -------------------------------------------------------
# Godot keeps saves in a folder named after the game (config/name). The game
# was "Dungeon Crawl Eliet" until round 56 and is "Dungeon Crawl Elite" now:
# the first run under the new name copies the old folder's files across (it
# never overwrites anything, and the old folder stays exactly as it was).

const OLD_GAME_NAMES := ["Dungeon Crawl Eliet"]
const MOVED_MARK := "moved_from_old_name.txt"


func migrate_user_dir(here: String = "", parent: String = "") -> int:
	if OS.has_feature("web") and here == "":
		return 0                            # (a browser's save store doesn't go by the name)
	if here == "":
		here = OS.get_user_data_dir()
	if parent == "":
		parent = here.get_base_dir()
	if here == "" or FileAccess.file_exists(here.path_join(MOVED_MARK)):
		return 0
	var n := 0
	for old in OLD_GAME_NAMES:
		var src: String = parent.path_join(str(old))
		if src == here or not DirAccess.dir_exists_absolute(src):
			continue
		n += _copy_tree(src, here)
	if n > 0:
		var f := FileAccess.open(here.path_join(MOVED_MARK), FileAccess.WRITE)
		if f:
			f.store_string(I18n.t("Copied %d file(s) from the game's old save folder on %s.\n") % [n, Time.get_datetime_string_from_system()])
			f.close()
	return n


func _copy_tree(src: String, dst: String) -> int:
	DirAccess.make_dir_recursive_absolute(dst)
	var d := DirAccess.open(src)
	if d == null:
		return 0
	var n := 0
	for f in d.get_files():
		var to := dst.path_join(f)
		if not FileAccess.file_exists(to) and d.copy(src.path_join(f), to) == OK:
			n += 1
	for sub in d.get_directories():
		n += _copy_tree(src.path_join(sub), dst.path_join(sub))
	return n


func llm_offline() -> bool:
	## no model to ask (the Google Play build): free talk isn't offered
	return llm_url == "" and not llm_override.is_valid()


func migrate_to_slots(old_path: String = "user://save.json") -> bool:
	## a save from before slots becomes slot 1 (the old file stays as it was)
	if not FileAccess.file_exists(old_path):
		return false
	for n in range(1, SLOTS + 1):
		if FileAccess.file_exists(slot_path(n)):
			return false
	var text := FileAccess.get_file_as_string(old_path)
	if text.strip_edges() == "":
		return false
	var f := FileAccess.open(slot_path(1), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	use_slot(1)
	return true


func slot_info(n: int) -> Dictionary:
	## what the title shows for a slot: who, how far, where, how long
	var p := slot_path(n)
	var d = _read_save(p)
	if steam:
		# round 57: a slot that lives only in Steam Cloud (a new PC) isn't empty
		var cf := "eliet_save.json" if n == 1 else "eliet_save_slot%d.json" % n
		var cloud = steam.cloud_get(cf)
		if cloud is Dictionary and float(cloud.get("saved_at", 0.0)) > (float(d.get("saved_at", 0.0)) if d is Dictionary else -1.0):
			d = cloud
	if d == null:
		return {"slot": n, "exists": false}
	if not (d is Dictionary) or d.is_empty() or str(d.get("background", "")) == "":
		return {"slot": n, "exists": false}         # (nobody made yet)
	var r := int(d.get("realm", 0))
	var nm := str(d.get("char_name", ""))
	return {"slot": n, "exists": true, "name": nm if nm != "" else "(unnamed)", "background": str(d.get("background", "")),
		"label": "%s %d/%d" % [realm_name_of(r), int(d.get("sublevel", 1)), SUBLEVELS], "realm": r,
		"place": str(d.get("current_level", "village")), "playtime": float(d.get("playtime", 0.0)), "saved_at": float(d.get("saved_at", 0.0)),
		"finished": (d.get("flags", {}) as Dictionary).has("story:finished") if d.get("flags", {}) is Dictionary else false}


func erase_slot(n: int) -> bool:
	## the slot is free again -- the file is kept, renamed, in case you want it back
	var p := slot_path(n)
	if not FileAccess.file_exists(p):
		return false
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	var to := "%s.erased-%s.json" % [p.trim_suffix(".json"), stamp]
	if FileAccess.file_exists(p + ".bak"):
		# (round 57: its backup goes with it -- or an erased slot would come back from the .bak)
		DirAccess.rename_absolute(ProjectSettings.globalize_path(p + ".bak"), ProjectSettings.globalize_path("%s.erased-%s.bak.json" % [p.trim_suffix(".json"), stamp]))
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(to)) == OK


func switch_slot(n: int, fresh: bool) -> void:
	## put this game away and pick up (or start) the one in slot n
	if FileAccess.file_exists(save_path) or background != "":
		save_game()
	use_slot(n)
	new_game()
	if not fresh:
		load_game()
	go_to(current_level, spawn_tag if spawn_tag != "" else "P")


const SAVE_VERSION := 1       # bump when the save layout changes; add a step to _migrate_save
var loaded_save_version := 0


func _migrate_save(d: Dictionary) -> Dictionary:
	var v := int(d.get("save_version", 0))
	loaded_save_version = v
	# v0 -> v1: no layout change (the version marker is new). Future steps go here, one per version.
	d["save_version"] = SAVE_VERSION
	return d


func save_game() -> void:
	var data := {
		"save_version": SAVE_VERSION,
		"realm": realm, "sublevel": sublevel, "qi": qi, "hp": hp, "gold": gold,
		"inventory": inventory, "weapon": weapon, "armor": armor, "ring": ring, "amulet": amulet,
		"equipment": equipment, "formulas_known": formulas_known, "nano_nodes": nano_nodes, "mat_known": mat_known,
		"quests": quests, "kills": kills, "flags": flags,
		"current_level": online_from if OnlineGen.is_online(current_level) else current_level, "spawn_tag": "P" if OnlineGen.is_online(current_level) else spawn_tag,
		"meditating": meditating, "playtime": playtime,
		"techniques": techniques, "counters": counters, "lore_read": lore_read,
		"skills": skills, "journal": journal, "affinity": affinity, "guilds": guilds, "familiar": familiar, "bonds": bonds,
		"last_haven": last_haven, "havens": havens,
		"companion": companion, "partner": partner,
		"arena": arena, "academy": academy, "rivals": rivals, "titles": titles,
		"background": background, "focus": focus, "custom_items": custom_items, "wishes": wishes, "moments": moments,
		"away_task": away_task, "expedition": expedition, "home": home, "bounties": bounties, "achievements": achievements,
		"lattice": lattice, "lattice_progress": lattice_progress, "lattice_focus": lattice_focus, "arts": arts,
		"injury": injury, "art_slots": art_slots, "quick_slots": quick_slots, "glimpses": glimpses, "bridges": bridges, "aid_buff": aid_buff, "post_log": post_log,
		"integration": integration, "augments": augments, "discoveries": discoveries,
		"sect": sect, "towers": towers, "insight": insight, "dao_heart": dao_heart,
		"saved_at": Time.get_unix_time_from_system(),
	}
	data.merge(r30_save())
	var text := JSON.stringify(data, "  ")
	var wrote := _write_safely(save_path, text)
	if wrote and steam:
		steam.cloud_put(text, cloud_file())          # Steam Cloud, when the game runs under Steam (each slot its own file)
	if wrote and cloudsave != null and cloudsave.is_inside_tree():
		cloudsave.mark_dirty(slot)                   # round 124: the cloud copy follows a little later


# ---- round 57: a save can't be lost to a crash halfway through writing it ------------------
# The new save is written to "<slot>.tmp" and checked; the last good save
# becomes "<slot>.bak"; then the new one takes its place. If a slot's file
# won't read, load_game tries the .bak -- and a file that won't read is never
# written over: it's kept aside as "<slot>.broken-<time>.json".

func _write_safely(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if JSON.parse_string(FileAccess.get_file_as_string(tmp)) == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return false                      # (the disk didn't keep what we wrote: leave the old save alone)
	var g_path := ProjectSettings.globalize_path(path)
	var g_bak := ProjectSettings.globalize_path(path + ".bak")
	if FileAccess.file_exists(path):
		if JSON.parse_string(FileAccess.get_file_as_string(path)) != null:
			if FileAccess.file_exists(path + ".bak"):
				DirAccess.remove_absolute(g_bak)
			DirAccess.rename_absolute(g_path, g_bak)          # the last good save, one step back
		else:
			_keep_broken(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(g_path)
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), g_path) == OK


func _keep_broken(path: String) -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path("%s.broken-%s.json" % [path.trim_suffix(".json"), stamp]))


func _read_save(path: String):
	## the slot's save -- or, if it won't read, its last good backup
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			return d
		push_warning("The save %s won't read -- trying its backup." % path)
	if FileAccess.file_exists(path + ".bak"):
		var b = JSON.parse_string(FileAccess.get_file_as_string(path + ".bak"))
		if b is Dictionary:
			if FileAccess.file_exists(path):
				_keep_broken(path)
			message.emit.call_deferred("Your last save didn't finish writing -- the one before it has been restored.")
			return b
	return null


func load_game() -> bool:
	var d = _read_save(save_path)
	if steam:
		# Steam Cloud: if another machine saved more recently, play from that
		var cloud = steam.cloud_get(cloud_file())
		if cloud is Dictionary and float(cloud.get("saved_at", 0.0)) > (float(d.get("saved_at", 0.0)) if d is Dictionary else -1.0):
			d = cloud
	if d == null:
		return false
	if not (d is Dictionary):
		return false
	d = _migrate_save(d)
	realm = clampi(int(d.get("realm", 0)), 0, 999)
	sublevel = clampi(int(d.get("sublevel", 1)), 1, SUBLEVELS)
	qi = float(d.get("qi", 0.0))
	gold = int(d.get("gold", 0))
	inventory = d.get("inventory", {})
	for k in inventory.keys():
		inventory[k] = int(inventory[k])
		if str(k).begins_with("key_floor"):
			register_key(str(k), I18n.t("Floor ") + str(k).trim_prefix("key_floor"))      # (round 32: a floor's key, carried between sessions)
	weapon = str(d.get("weapon", ""))
	equipment = {}
	armor = str(d.get("armor", ""))
	ring = str(d.get("ring", ""))
	amulet = str(d.get("amulet", ""))
	if d.get("equipment", null) is Dictionary:
		for sl in d["equipment"]:
			equipment[str(sl)] = str(d["equipment"][sl])
	for pair in [["formulas_known", "formulas_known"], ["nano_nodes", "nano_nodes"], ["mat_known", "mat_known"]]:
		var v0 = d.get(pair[0], {})
		set(pair[1], v0 if v0 is Dictionary else {})
	quests = d.get("quests", {})
	kills = d.get("kills", {})
	flags = d.get("flags", {})
	current_level = str(d.get("current_level", "village"))
	spawn_tag = str(d.get("spawn_tag", "P"))
	playtime = float(d.get("playtime", 0.0))
	techniques = d.get("techniques", {})
	counters = d.get("counters", {})
	lore_read = d.get("lore_read", {})
	skills = d.get("skills", {})
	guilds = d.get("guilds", {})
	familiar = d.get("familiar", {})
	bonds = d.get("bonds", {})
	last_haven = str(d.get("last_haven", "village"))
	havens = d.get("havens", {})
	companion = d.get("companion", {})
	partner = str(d.get("partner", ""))
	arena = d.get("arena", {})
	academy = d.get("academy", {"trials": {}, "enrolled": false, "rank": 0, "merit": 0.0})
	rivals = d.get("rivals", {})
	titles = d.get("titles", [])
	_forget_custom_items()
	var ci = d.get("custom_items", {})
	if ci is Dictionary:
		for cid in ci:
			if ci[cid] is Dictionary:
				custom_items[str(cid)] = ci[cid]
				items[str(cid)] = ci[cid]          # made for you: as real as anything in data/
	wishes = d.get("wishes", {}) if d.get("wishes", {}) is Dictionary else {}
	focus = d.get("focus", {}) if d.get("focus", {}) is Dictionary else {}
	moments = d.get("moments", []) if d.get("moments", []) is Array else []
	background = str(d.get("background", ""))
	for pair in [["away_task", "away_task"], ["expedition", "expedition"], ["home", "home"], ["bounties", "bounties"], ["achievements", "achievements"]]:
		var v = d.get(pair[0], {})
		set(pair[1], v if v is Dictionary else {})
	away_report = []
	lattice = d.get("lattice", {}) if d.get("lattice", {}) is Dictionary else {}
	lattice_progress = d.get("lattice_progress", {}) if d.get("lattice_progress", {}) is Dictionary else {}
	lattice_focus = str(d.get("lattice_focus", ""))
	arts = d.get("arts", {}) if d.get("arts", {}) is Dictionary else {}
	for pair in [["injury", "injury"], ["art_slots", "art_slots"], ["glimpses", "glimpses"], ["bridges", "bridges"], ["aid_buff", "aid_buff"], ["post_log", "post_log"]]:
		var v2 = d.get(pair[0], {})
		set(pair[1], v2 if v2 is Dictionary else {})
	var qs = d.get("quick_slots", [])
	quick_slots = ["", "", "", ""]
	if qs is Array:
		for qi in range(mini((qs as Array).size(), 4)):
			quick_slots[qi] = str(qs[qi])                  # round 158: the quick-art deck comes back with you
	heat = 0.0
	integration = float(d.get("integration", 0.0))
	for pair in [["augments", "augments"], ["discoveries", "discoveries"]]:
		var v3 = d.get(pair[0], {})
		set(pair[1], v3 if v3 is Dictionary else {})
	if not d.has("integration"):
		_grandfather_swarm()
	for pair in [["sect", "sect"], ["towers", "towers"]]:
		var v4 = d.get(pair[0], {})
		set(pair[1], v4 if v4 is Dictionary else {})
	dao_heart = float(d.get("dao_heart", 0.0))
	tribulation = {}
	r30_load(d)
	if d.has("insight"):
		insight = float(d["insight"])
	else:
		_grandfather_insight()
	if str(current_level).begins_with("tribulation:"):
		current_level = last_haven if level_exists(last_haven) else "village"     # (a tribulation isn't a place to wake up in -- the last town is)
		spawn_tag = "P"
	if store and store.level_locked(str(current_level)):
		# round 58: saved below the free floors, and the full game isn't here (a refund,
		# or a save carried over from another device): wake in the deepest free town
		current_level = free_haven()
		spawn_tag = "P"
		if store.level_locked(last_haven):
			last_haven = current_level
		_after_load_note = I18n.t("You wake in %s: below floor %d is the full game (Menu -> Unlock the full game, or Restore purchases).") % [str(havens.get(current_level, I18n.t("the village"))) if current_level != "village" else I18n.t("the village"), store.free_depth()]
	if lite_blocked(str(current_level)):
		# round 124: saved in the valley (or a tower, or the frontier) and this device plays the Lite world: wake in the village
		current_level = "village"
		spawn_tag = "P"
		_after_load_note = "You wake in the village: this device plays the Lite world (the village and the dungeon). Pause menu -> Graphics fine-tune -> World: Full brings the rest back."
	if lite_blocked(str(last_haven)):
		last_haven = "village"
	if Arena.is_arena(str(current_level)):
		# round 57: saved mid-fight in the arena -- the bout's off; back where you came from
		var back := str(arena.get("return_to", ""))
		current_level = back if back != "" and level_exists(back) else (last_haven if level_exists(last_haven) else "village")
		spawn_tag = "P"
		arena = {}
	if not d.has("lattice"):
		_grandfather_arts()
	if companion.has("name"):
		flags["travelled:" + str(companion["name"])] = true
	if companion2.has("name"):
		flags["travelled:" + str(companion2["name"])] = true
	_legacy_save = not d.has("background")
	journal = d.get("journal", {"items": {}, "places": {}})
	for k in ["items", "places"]:
		if not journal.has(k):
			journal[k] = {}
	var aff = d.get("affinity", {})
	for e in ELEMENTS:
		affinity[e] = float(aff.get(e, 0.0)) if aff is Dictionary else 0.0
	if _legacy_save:
		_grandfather_skills()
	hp = clampi(int(d.get("hp", max_hp())), 1, max_hp())
	if not ScavengeGen.is_scavenge(current_level) and not ResourceLoader.exists("res://levels/%s.json" % current_level) and not FileAccess.file_exists("res://levels/%s.json" % current_level):
		current_level = "village"
		spawn_tag = "P"
	# Away: the nanites keep refining, and whatever you set yourself to do
	# got done (resolve_away); the bench and any expedition caught up too.
	# round 63: not a lump any more -- the hours are worked through in order
	# (systems/Pursuit.gd), within the pursuit bank, by the high-water clock
	var away := Time.get_unix_time_from_system() - float(d.get("saved_at", Time.get_unix_time_from_system()))
	var hours: float = clampf(away / 3600.0, 0.0, away_cap_hours())
	var PU = sys("pursuit")
	if PU:
		away_report = PU.offline(float(d.get("saved_at", 0.0)), bool(d.get("meditating", false)))
	else:
		away_report = resolve_away(hours, bool(d.get("meditating", false)))
	away_report.append_array(check_expedition())
	var bench := process_queue()
	if bench.size() > 0:
		away_report.append_array(bench.slice(maxi(0, bench.size() - 6)))
	if hours >= 1.0 or Time.get_date_dict_from_unix_time(int(d.get("saved_at", 0))).get("day", -1) != Time.get_date_dict_from_system().get("day", -2):
		away_report.append_array(welcome_lines())     # round 30: today's trial, your streak, the week
	if away_report.size() > 0:
		message.emit.call_deferred("While you were away (%.1fh): see what happened." % hours)
	meditating = false
	stats_changed.emit()
	# round 57: what the away time gave is written down now -- quitting the game
	# by force within a minute can't hand it out twice
	save_game()
	return true


func new_game() -> void:
	sitting = false                   # (round 57: nothing of the last character's moment carries over)
	sit_aid = 1.0
	at_bench = ""
	_marrow_acc = 0.0
	_rest_t = 0.0
	realm = 0
	sublevel = 1
	qi = 0.0
	gold = 20
	inventory = {"healing_salve": 2}
	weapon = ""
	equipment = {}
	formulas_known = {}
	nano_nodes = {}
	mat_known = {}
	quests = {}
	kills = {}
	flags = {}
	current_level = "village"
	spawn_tag = "P"
	playtime = 0.0
	techniques = {}
	counters = {}
	lore_read = {}
	skills = {}
	guilds = {}
	familiar = {}
	contracts = []
	companion2 = {}
	taming_perks = []
	mq = {}
	buffs = {}
	hm = {}
	fog_seen = {}
	attrs = {}
	char_name = ""
	look = {}
	born = {}
	fog_frac = {}
	inscriptions = {}
	talisman_ready = ""
	_systems_reset()
	bonds = {}
	last_haven = "village"
	havens = {}
	companion = {}
	partner = ""
	arena = {}
	academy = {"trials": {}, "enrolled": false, "rank": 0, "merit": 0.0}
	rivals = {}
	titles = []
	journal = {"items": {}, "places": {}}
	background = ""
	focus = {}
	_forget_custom_items()
	wishes = {}
	moments = []
	lattice = {}
	lattice_progress = {}
	lattice_focus = ""
	arts = {}
	heat = 0.0
	injury = {}
	art_slots = {}
	quick_slots = ["", "", "", ""]
	glimpses = {}
	bridges = {}
	aid_buff = {}
	post_log = {}
	integration = 0.0
	augments = {}
	discoveries = {}
	sect = {}
	towers = {}
	insight = 0.0
	dao_heart = 0.0
	tribulation = {}
	_edge_secs = 0.0
	_parry_times = []
	away_task = {}
	away_report = []
	expedition = {}
	home = {}
	bounties = {}
	achievements = {}
	_legacy_save = false
	trials = {}
	marks = 0
	coll_claimed = {}
	world_events = {}
	ascension = {}
	blood_new_game(randi())
	for e in ELEMENTS:
		affinity[e] = 0.0
	# everyone who lives long enough to leave home can throw a punch and
	# find water -- the one thing you're GOOD at comes from your background
	skills = {"unarmed": START_XP, "survival": START_XP}
	hp = max_hp()
	stats_changed.emit()


func _forget_custom_items() -> void:
	for cid in custom_items:
		items.erase(cid)
	custom_items = {}


func needs_background() -> bool:
	return background == ""


func choose_background(bid: String) -> bool:
	## Pick who you were. On a new game it gives the one skill and the
	## starting kit; on an older save it only ever ADDS (nothing you've
	## learned is taken away).
	if not BACKGROUNDS.has(bid) or background != "":
		return false
	var b: Dictionary = BACKGROUNDS[bid]
	background = bid
	for sk in [str(b["skill"]), "unarmed", "survival"]:
		skills[sk] = maxf(float(skills.get(sk, 0.0)), START_XP)
	for id in b.get("items", {}):
		add_item(str(id), int(b["items"][id]), false)
	var w := ""
	for id in b.get("items", {}):
		if str(item_def(str(id)).get("type", "")) == "weapon":
			w = str(id)
	if w != "" and count(w) > 0:
		weapon = w               # you know this one: it's in your hand
	note_place(I18n.t("Before the road: ") + str(b["name"]))
	log_event("background", {"id": bid})
	message.emit(I18n.t("You were a %s. %s") % [b["name"], b["desc"]])
	hp = max_hp()
	stats_changed.emit()
	save_game()
	return true


func _grandfather_skills() -> void:
	## A save from before weapons were skills: your hands remember what
	## they've been doing. Unarmed and Survival to Apprentice, and the kind
	## you've been fighting with, by how much you've fought.
	var total := 0
	for k in kills:
		total += int(kills[k])
	for sk in ["unarmed", "survival"]:
		skills[sk] = maxf(float(skills.get(sk, 0.0)), START_XP)
	if weapon != "":
		var ws := weapon_skill(weapon)
		skills[ws] = maxf(float(skills.get(ws, 0.0)), clampf(total * 4.0, START_XP, 4000.0))


# ======================================================================
# techniques (hidden skills you discover) and discovery counters
# ======================================================================

func has_tech(tid: String) -> bool:
	return techniques.has(tid)


func _effects() -> Array:
	## Every passive effect the player has: learned techniques AND owned
	## treasures (a jade pendant works the same way a technique does).
	var out := []
	for tid in techniques:
		out.append(technique_defs.get(tid, {}).get("effect", {}))
	for id in inventory:
		if is_treasure(id):
			out.append(items[id].get("effect", {}))
	out.append(affinity_effect())
	out.append(lattice_effect())
	for k in active_buffs():                          # round 34: crafted buffs
		out.append(buffs[k].get("effect", {}))
	out.append(nanite_effect())
	out.append(sect_effect())
	out.append(dao_heart_effect())
	if partner != "":
		out.append(PARTNER_EFFECT)
	for bst in beasts_out():                    # round 39: every contract beast you've called (the lead in full)
		var fe: Dictionary = enemies.get(str(bst.get("species", "")), {}).get("familiar", {}).get("effect", {})
		var grow := (1.0 + float(bst.get("bond", 0.0)) / 100.0) * familiar_effect_mult(bst) * (1.0 if is_same(bst, familiar) else float(party_data().get("beasts", {}).get("second_share", 0.6)))     # round 32: a grown familiar gives more
		var scaled := {}
		for k in fe:
			if k in ["gather_chance", "sense_radius", "gather_bonus", "heal_on_kill"] or str(k).begins_with("craft_"):
				scaled[k] = float(fe[k]) * grow
			else:
				scaled[k] = 1.0 + (float(fe[k]) - 1.0) * grow
		out.append(scaled)
	out.append_array(gear_effects())        # round 27: every worn piece
	out.append_array(rune_effects())        # round 38: what's carved into it
	for sysn in systems.values():           # round 40: synergy, cleansing, research and whatever comes next
		out.append_array(sysn.effects())
	out.append(blood_effect())              # round 30: your blood
	out.append(zone_effect())               # the day's trial, a floor's event
	out.append(ascension_effect())
	out.append(attribute_effect())          # round 36: what you've earned and spent
	out.append(title_effect())              # round 36: every title carries a small gift
	for gid in guilds:
		var ranks: Array = guild_defs.get(gid, {}).get("ranks", [])
		for i in range(mini(guild_rank(gid) + 1, ranks.size())):
			out.append(ranks[i].get("effect", {}))
	return out


func tech_effect(key: String, default_value: float) -> float:
	## Multiplies together every learned technique's (and owned treasure's)
	## value for `key` (damage_taken 0.85 x ...), or adds for additive keys.
	var additive := key in ADDITIVE_KEYS or key.begins_with("craft_")
	var v := 0.0 if additive else default_value
	var found := false
	for e in _effects():
		if e.has(key) and not (e[key] is Dictionary):
			found = true
			if additive:
				v += float(e[key])
			else:
				v *= float(e[key])
	if additive and not found:
		return default_value
	return v


func _paths_fx() -> Dictionary:
	## round 121: what the walked paths give right now (for the character sheet's breakdown)
	var ps = sys("paths")
	if ps == null:
		return {}
	var a: Array = ps.effects()
	return a[0] if a.size() > 0 else {}


func tech_effect_dict(key: String) -> Dictionary:
	var out := {}
	for e in _effects():
		if e.get(key) is Dictionary:
			for k in e[key]:
				out[k] = float(out.get(k, 1.0)) * float(e[key][k])
	return out


func learn(tid: String, source: String = "") -> bool:
	if techniques.has(tid) or not technique_defs.has(tid):
		return false
	techniques[tid] = true
	var t: Dictionary = technique_defs[tid]
	var how := ""
	if t.get("kind") == "active":
		how = " (press %s)" % t.get("key", "?")
	message.emit(I18n.t("TECHNIQUE LEARNED: %s%s -- %s") % [t.get("name", tid), how, t.get("desc", "")])
	log_event("technique", {"id": tid, "source": source})
	if lattice_data().get("arts", {}).has(tid):
		# an active art: it lives in the lattice -- start learning it, and if
		# its route isn't open, point you at the first sealed point
		if not arts.has(tid):
			arts[tid] = {"m": 0.0, "u": 0.0}
			if lattice_data()["arts"][tid].has("sect"):
				arts[tid]["b"] = str(art_def(tid).get("branches", [""])[0])      # a sect art carries its element from the start
		for pid in art_route(tid):
			if not lattice.has(str(pid)):
				if lattice_focus == "" or can_focus(lattice_focus) != "":
					lattice_focus = str(pid)
				message.emit(I18n.t("MERIDIAN: %s runs through your %s point, still sealed -- meditate with it as your focus (K).") % [t.get("name", tid), lattice_point(str(pid)).get("name", pid)])
				break
	add_qi(25.0, "insight")
	stats_changed.emit()
	return true


func bump(counter: String, by: float = 1.0) -> void:
	counters[counter] = float(counters.get(counter, 0.0)) + by
	check_unlocks()


func check_unlocks() -> void:
	## Techniques that come from DOING things rather than reading them.
	for tid in technique_defs:
		if techniques.has(tid):
			continue
		var u: Dictionary = technique_defs[tid].get("unlock", {})
		if u.has("kills"):
			var ok := true
			for et in u["kills"]:
				if int(kills.get(et, 0)) < int(u["kills"][et]):
					ok = false
			if ok:
				learn(tid, "kills")
		if u.has("shrine_seconds") and float(counters.get("shrine_seconds", 0.0)) >= float(u["shrine_seconds"]):
			learn(tid, "shrine")
		if u.has("talk"):
			for who in u["talk"]:
				if float(counters.get("talk:" + who, 0.0)) >= float(u["talk"][who]):
					learn(tid, "talk")
		if u.has("skill"):
			var ok_s := true
			for sk in u["skill"]:
				if skill_level(str(sk)) < int(u["skill"][sk]):
					ok_s = false
			if ok_s:
				learn(tid, "mastery")


# ======================================================================
# the play log -- what actually happens when the game is played, so Dev
# can learn what works (where people die, what goes unfound, how long
# each floor takes) and what needs rebuilding. Local file only.
# ======================================================================

func _starter_gift() -> void:
	## round 152: nobody should meet the first goblin empty-handed. Elder Mo presses an old blade on you, once.
	if weapon != "" or has_flag("fs:gift"):
		return
	var pu = sys("pull")
	var wid: String = str(pu.cfg.get("starter_weapon", "iron_sword")) if pu != null else "iron_sword"
	if not items.has(wid):
		return
	set_flag("fs:gift")
	add_item(wid, 1, false)
	equip(wid)
	message.emit(I18n.t("Elder Mo presses an old blade into your hand: \"It has done more good than harm. Go on.\" (%s, equipped)") % item_name(wid))
	jingle("discovery")


func log_event(kind: String, data: Dictionary = {}) -> void:
	weekly_note(kind)
	if kind == "talk" and str(data.get("role", "")) == "elder":
		set_flag("fs:talk")
		_starter_gift()
	elif kind == "point_open":
		set_flag("fs:meditate")                      # round 30: the week's sect trials count what you do
	elif (kind == "craft" or kind == "forge") and bool(data.get("success", false)):
		set_flag("fs:craft")                         # round 142b: a first craft (pace: crafter)
	elif kind == "waystone":
		set_flag("fs:waystone")                      # round 142b: a first waystone (pace: wanderer)
	elif kind == "lesson":
		set_flag("fs:lesson")                        # round 142b: a first lesson (pace: scholar)
	var row := {"t": Time.get_unix_time_from_system(), "play": int(playtime),
		"level": current_level, "kind": kind,
		"cult": step_index(), "hp": hp, "gold": gold}
	row.merge(data)
	_insight_from_event(kind, data)
	for sy in systems.values():                      # round 44: systems hear what you do (standing, a camp's hunt)
		sy.on_event(kind, data)
	if kind != "chapter_done":
		mq_auto()                                    # round 34: a chapter nobody reports completes itself
	if FileAccess.file_exists(playlog_path):
		var f0 := FileAccess.open(playlog_path, FileAccess.READ)
		if f0 and f0.get_length() > PLAYLOG_MAX_BYTES:
			f0.close()
			DirAccess.rename_absolute(ProjectSettings.globalize_path(playlog_path),
				ProjectSettings.globalize_path(playlog_path + ".old"))
	var f := FileAccess.open(playlog_path, FileAccess.READ_WRITE if FileAccess.file_exists(playlog_path) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(JSON.stringify(row))


func mark_level_entered(level_id: String, info: Dictionary) -> void:
	_level_entered_at = playtime
	if OnlineGen.is_online(level_id):
		return                                          # (the Gate is not a place in the solo journal)
	Hook.daily_login.call_deferred()                    # round 126: the day's streak and challenges
	if level_id == "village":
		Comfort.on_village.call_deferred()              # round 127: the full game's auto-stash
	Hook.welcome_back.call_deferred()
	Hook.season_notice.call_deferred()
	Hook.watch_power.call_deferred()
	var pl: Dictionary = journal["places"].get(level_id, {"visits": 0, "first": int(playtime), "notes": []})
	pl["visits"] = int(pl.get("visits", 0)) + 1
	pl["counts"] = info
	journal["places"][level_id] = pl
	if int(pl["visits"]) == 1 and not Arena.is_arena(level_id) and not ScavengeGen.is_scavenge(level_id) and not level_id.begins_with("tribulation:"):
		gain_insight(2.0, "new ground")         # a first visit to a place: insight
	if int(pl["visits"]) == 1 and int(info.get("enemies", 0)) > 0 and not Arena.is_arena(level_id):
		add_skill_xp("survival", 8.0 + 2.0 * float(depth), "new ground")     # the deep teaches by being new
	var d := {"id": level_id}
	d.merge(info)
	log_event("enter_level", d)
	if level_id.begins_with("floor") and depth > int(counters.get("blood_floor", 0.0)):
		counters["blood_floor"] = float(depth)
		blood_floor_reached(depth)                 # round 30: deep enough, the blood wakes
	if level_id.begins_with("floor"):
		story_check("floor_reached", depth)         # round 32: the story follows you down
	if steam:
		steam.presence()
		steam.stat("deepest_floor", reach_depth())


# ======================================================================
# helpers
# ======================================================================

func _load_json(path: String, fallback):
	if not FileAccess.file_exists(path):
		return fallback
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("Could not parse JSON in %s" % path)
		return fallback
	return parsed


func _setup_input() -> void:
	## Controls are registered here, in code, so they're easy to read and
	## change: WASD move, mouse look, left click / J attack, E interact,
	## Shift sprint, Space jump, M meditate, I inventory, 1 salve, 2 qi pill.
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"attack": [KEY_J], "interact": [KEY_E], "sprint": [KEY_SHIFT],
		"jump": [KEY_SPACE], "meditate": [KEY_M], "inventory": [KEY_I], "menu": [KEY_TAB],         # round 39: Tab is the whole menu
		"use_salve": [KEY_1], "use_pill": [KEY_2], "pause": [KEY_ESCAPE],
		"wind_step": [KEY_V], "qi_burst": [KEY_F],
		"flying_sword": [KEY_G], "use_gourd": [KEY_3], "journal": [KEY_N],
		"cam_left": [KEY_Q, KEY_COMMA], "cam_right": [KEY_PERIOD], "vault_dump": [KEY_APOSTROPHE], "moment": [KEY_T], "help": [KEY_H], "camera_view": [KEY_C], "lattice": [KEY_K],
		"guard": [KEY_B], "art_cycle": [KEY_X],
		"dodge": [KEY_CTRL, KEY_ALT], "lock_on": [KEY_Z],          # round 32
		"character": [KEY_P],                                      # round 36: the character sheet
		"talisman": [KEY_4], "talisman_cycle": [KEY_5],           # round 38: burn a talisman / switch
		"party": [KEY_O], "bonds": [KEY_U], "road": [KEY_L],     # round 39: the menu's sections
		"swarm": [KEY_Y],                                          # round 40: the swarm's research
		"path_art": [KEY_6], "path_cycle": [KEY_7],
		"support_art": [KEY_8], "support2_art": [KEY_9], "support_cycle": [KEY_0], "support2_cycle": [KEY_MINUS],      # round 122: support arts                      # round 121: the path's art / which path's art is readied
		"flow": [KEY_BRACKETRIGHT, KEY_QUOTELEFT], "mech": [KEY_BACKSLASH],                                # round 146: active meditation (or M while walking)
		"map": [KEY_F2],                                           # round 75: the map (every letter was taken)
		"photo": [KEY_F9],                                         # round 165: photo mode
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", mb)
	# round 158: R is the first of four quick-art keys (R, F3, F4, F5) -- any art you know, assigned in the Arts menu
	for qi in range(4):
		var qa := "quick%d" % (qi + 1)
		if not InputMap.has_action(qa):
			InputMap.add_action(qa)
		var qe := InputEventKey.new()
		qe.physical_keycode = [KEY_R, KEY_F3, KEY_F4, KEY_F5][qi]
		InputMap.action_add_event(qa, qe)
	var mwheel := InputEventMouseButton.new()
	mwheel.button_index = MOUSE_BUTTON_MIDDLE                # r150: the flow is one click of the wheel
	InputMap.action_add_event("flow", mwheel)
	var mr := InputEventMouseButton.new()
	mr.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("guard", mr)
	var mm := InputEventMouseButton.new()
	mm.button_index = MOUSE_BUTTON_MIDDLE
	InputMap.action_add_event("lock_on", mm)
	_setup_pad()
	preload("res://scripts/core/Controls.gd").init()          # round 158: the keys the player has moved


func _setup_pad() -> void:
	## A game pad (round 29: for the phone, a TV, or streaming the game to a
	## phone): left stick walks (click it to run), right stick looks (click
	## it: camera), A jump, X attack, B step (V), Y use (E), LB guard (tap:
	## parry), RB qi art (F), RT attack, LT flying sword, d-pad up salve /
	## right pill / down meditate / left switch art, Back the bag, Start the menu.
	for a in ["look_left", "look_right", "look_up", "look_down"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.15)
	var axes := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0],
		"look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0],
		"look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0],
		"attack": [JOY_AXIS_TRIGGER_RIGHT, 1.0], "dodge": [JOY_AXIS_TRIGGER_LEFT, 1.0]}
	for action in axes:
		var m := InputEventJoypadMotion.new()
		m.axis = axes[action][0]
		m.axis_value = float(axes[action][1])
		InputMap.action_add_event(action, m)
	for action in ["move_left", "move_right", "move_forward", "move_back"]:
		InputMap.action_set_deadzone(action, 0.2)
	var buttons := {"jump": JOY_BUTTON_A, "attack": JOY_BUTTON_X, "wind_step": JOY_BUTTON_B, "interact": JOY_BUTTON_Y,
		"guard": JOY_BUTTON_LEFT_SHOULDER, "qi_burst": JOY_BUTTON_RIGHT_SHOULDER, "sprint": JOY_BUTTON_LEFT_STICK,
		"lock_on": JOY_BUTTON_RIGHT_STICK, "pause": JOY_BUTTON_START,         # (Back: the bag on release, or the quick layer -- see _input)
		"use_salve": JOY_BUTTON_DPAD_UP, "use_pill": JOY_BUTTON_DPAD_RIGHT, "meditate": JOY_BUTTON_DPAD_DOWN,
		"art_cycle": JOY_BUTTON_DPAD_LEFT}
	for action in buttons:
		var b := InputEventJoypadButton.new()
		b.button_index = buttons[action]
		InputMap.action_add_event(action, b)


# ---- round 166: the pad's quick layer -----------------------------------------------------------------------
# Hold Back and the face buttons become the four quick arts (A B X Y = 1 2 3 4); let go of Back with nothing pressed and it is the bag, as before.
const PAD_FACE := {JOY_BUTTON_A: ["jump", "quick1"], JOY_BUTTON_B: ["wind_step", "quick2"], JOY_BUTTON_X: ["attack", "quick3"], JOY_BUTTON_Y: ["interact", "quick4"]}
var pad_layer := false
var _pad_used := false


func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton):
		return
	var jb := event as InputEventJoypadButton
	if jb.button_index == JOY_BUTTON_BACK:
		if jb.pressed and not pad_layer:
			_pad_swap(true)
		elif not jb.pressed and pad_layer:
			_pad_swap(false)
			if not _pad_used:
				_pad_tap("inventory")
	elif pad_layer and jb.pressed and PAD_FACE.has(jb.button_index):
		_pad_used = true


func _pad_swap(on: bool) -> void:
	pad_layer = on
	if on:
		_pad_used = false
	for bi in PAD_FACE:
		var from_a: String = PAD_FACE[bi][0 if on else 1]
		var to_a: String = PAD_FACE[bi][1 if on else 0]
		for ev in InputMap.action_get_events(from_a):
			if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == bi:
				InputMap.action_erase_event(from_a, ev)
		var nb := InputEventJoypadButton.new()
		nb.button_index = bi
		InputMap.action_add_event(to_a, nb)
	if not on:
		for q in ["quick1", "quick2", "quick3", "quick4"]:
			Input.action_release(q)
		for a in ["jump", "wind_step", "attack", "interact"]:
			Input.action_release(a)


func _pad_tap(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event.call_deferred(up)


# ======================================================================
# skills -- every one keeps growing (there is always a way forward)
# ======================================================================

func skill_level(sid: String) -> int:
	return int(floor(sqrt(float(skills.get(sid, 0.0)) / 10.0)))


func skill_title(sid: String) -> String:
	var lvl := skill_level(sid)
	var t := "Novice"
	for row in SKILL_TITLES:
		if lvl >= int(row[0]):
			t = str(row[1])
	return t


func skill_name(sid: String) -> String:
	return str(skill_defs.get(sid, {}).get("name", sid.capitalize()))


func add_skill_xp(sid: String, amount: float, source: String = "") -> void:
	if amount <= 0.0:
		return
	amount *= focus_mult(sid) * growth_mult() * tech_effect("adapt_mult", 1.0)     # round 40: Adaptability
	_deepen_focus(sid)
	var before := skill_level(sid)
	skills[sid] = float(skills.get(sid, 0.0)) + amount
	var after := skill_level(sid)
	# doing a craft is also tuning yourself to its elements
	for e in skill_defs.get(sid, {}).get("elements", {}):
		attune(str(e), amount * 0.04 * float(skill_defs[sid]["elements"][e]))
	if after > before:
		message.emit(I18n.t("SKILL: %s rises to %d (%s)") % [skill_name(sid), after, skill_title(sid)])
		log_event("skill_up", {"skill": sid, "level": after, "source": source})
	check_unlocks()
	stats_changed.emit()


func focus_value(sid: String) -> float:
	var f: Dictionary = focus.get(sid, {})
	if f.is_empty():
		return 0.0
	var age := maxf(0.0, playtime - float(f.get("t", playtime)))
	return float(f.get("v", 0.0)) * pow(0.5, age / FOCUS_HALF_LIFE)


func focus_bonus(sid: String) -> float:
	## 0..1: how far into the flow of this one craft you are.
	return clampf(focus_value(sid) / 20.0, 0.0, 1.0)


func focus_mult(sid: String) -> float:
	return 1.0 + FOCUS_STEP_XP * minf(focus_value(sid), 20.0)


func _deepen_focus(sid: String) -> void:
	var before := focus_value(sid)
	var after := minf(before + 1.0, FOCUS_CAP)
	focus[sid] = {"v": after, "t": playtime}
	for mark in [10.0, 20.0]:
		if before < mark and after >= mark:
			message.emit(I18n.t("FOCUS: %s -- %s (+%d%% skill growth%s)") % [skill_name(sid),
				"you're in the flow" if mark < 20.0 else "complete absorption", int(round((focus_mult(sid) - 1.0) * 100)),
				", finer work" if str(skill_defs.get(sid, {}).get("kind", "")) in ["crafting", "gathering"] else ""])
			log_event("focus", {"skill": sid, "level": int(mark)})


func top_focus() -> Array:
	## [skill id, value] of whatever you're most absorbed in right now.
	var best := ""
	var bv := 0.0
	for sid in focus:
		var v := focus_value(str(sid))
		if v > bv:
			bv = v
			best = str(sid)
	return [best, bv]


# ======================================================================
# the five elements -- pros, cons, synergy and clash
# ======================================================================

func attune(element: String, amount: float) -> void:
	if not affinity.has(element) or amount == 0.0:
		return
	var a: float = affinity[element]
	# the stronger it already is, the slower it grows; it never quite caps
	var gain := amount * (1.0 - a / 120.0) if amount > 0.0 else amount
	var before_active := a >= AFFINITY_ACTIVE
	affinity[element] = clampf(a + gain, 0.0, 100.0)
	if not before_active and affinity[element] >= AFFINITY_ACTIVE:
		message.emit("AFFINITY: %s settles into your foundation." % element.capitalize())
		log_event("affinity", {"element": element})
		for s_ in affinity_status()["synergies"] + affinity_status()["clashes"]:
			message.emit(s_)


const HARMONY_HP := 0.03           # per tempered clash: the foundation
const HARMONY_QI := 1.04           # per tempered clash: the core
const HARMONY_BOND := 1.15         # per tempered clash: the gifts of the elements around it


func all_aspects_alive() -> bool:
	## every element alive in you (so every generating bond holds): a clash is no longer a war, it tempers
	for e in ELEMENTS:
		if affinity[e] < AFFINITY_ACTIVE:
			return false
	return true


func _clash_pairs() -> Array:
	var out := []
	for e in ELEMENTS:
		var o: String = OVERCOMES[e]
		if affinity[e] >= AFFINITY_ACTIVE and affinity[o] >= AFFINITY_ACTIVE \
				and absf(affinity[e] - affinity[o]) < CLASH_GAP:
			out.append([e, o])
	return out


func affinity_status() -> Dictionary:
	var syn := []
	var cla := []
	if all_aspects_alive():
		for pr in _clash_pairs():
			syn.append(I18n.t("Tempered: %s and %s clash, and every bond around them grows stronger.") % [str(pr[0]).capitalize(), str(pr[1]).capitalize()])
	for e in ELEMENTS:
		var g: String = GENERATES[e]
		if affinity[e] >= AFFINITY_ACTIVE and affinity[g] >= AFFINITY_ACTIVE:
			syn.append(I18n.t("Synergy: %s feeds %s.") % [e.capitalize(), g.capitalize()])
		var o: String = OVERCOMES[e]
		if not all_aspects_alive() and affinity[e] >= AFFINITY_ACTIVE and affinity[o] >= AFFINITY_ACTIVE \
				and absf(affinity[e] - affinity[o]) < CLASH_GAP:
			cla.append(I18n.t("Clash: %s and %s war in your meridians.") % [e.capitalize(), o.capitalize()])
	return {"synergies": syn, "clashes": cla}


func affinity_effect() -> Dictionary:
	## What your elements do for you -- and to you. Each element has a
	## gift; a generating pair amplifies the second one's gift; an
	## overcoming pair held at nearly equal strength costs qi and halves
	## the weaker one's gift. Doing it all is possible, but not free.
	var f := {}
	var gift := {}
	for e in ELEMENTS:
		gift[e] = float(affinity[e]) / 100.0
	for e in ELEMENTS:
		var g: String = GENERATES[e]
		if affinity[e] >= AFFINITY_ACTIVE and affinity[g] >= AFFINITY_ACTIVE:
			gift[g] *= 1.4
	var qi_pen := 1.0
	var tempered := 0
	var all_alive := all_aspects_alive()
	for e in ELEMENTS:
		var o: String = OVERCOMES[e]
		if affinity[e] >= AFFINITY_ACTIVE and affinity[o] >= AFFINITY_ACTIVE \
				and absf(affinity[e] - affinity[o]) < CLASH_GAP:
			if all_alive:
				# synergy in every aspect: the clash forces strength into the bonds around it
				tempered += 1
				for nb in [GENERATES[e], GENERATES[o]]:
					gift[nb] *= HARMONY_BOND
				for nb2 in ELEMENTS:
					if GENERATES[nb2] == e or GENERATES[nb2] == o:
						gift[nb2] *= HARMONY_BOND
			else:
				qi_pen *= 0.88
				gift[o] *= 0.5
	f["damage_mult"] = 1.0 + gift["fire"] * 0.25          # fire: the strike
	f["hp_mult"] = 1.0 + gift["earth"] * 0.2               # earth: the body
	f["meditate_mult"] = 1.0 + gift["water"] * 0.4         # water: the flow
	f["gather_chance"] = gift["wood"] * 0.5                # wood: growth
	f["craft_success"] = gift["metal"] * 0.15              # metal: precision
	f["craft_quality"] = gift["metal"] * 0.1
	f["qi_mult"] = qi_pen * pow(HARMONY_QI, tempered)
	if tempered > 0:
		f["hp_mult"] = float(f["hp_mult"]) + HARMONY_HP * tempered     # the foundation
	return f


# ======================================================================
# the journal -- what you've found, where, and what it's for
# ======================================================================

func note_item(id: String) -> void:
	var b := base_id(id)
	var e: Dictionary = journal["items"].get(b, {})
	if e.is_empty():
		e = {"first": current_level, "where": [], "uses": []}
		log_event("journal_item", {"id": b})
	if not (current_level in e["where"]):
		e["where"].append(current_level)
	journal["items"][b] = e


func note_use(made: String, recipe: Dictionary) -> void:
	for need in recipe.get("needs", {}):
		var e: Dictionary = journal["items"].get(need, {"first": current_level, "where": [], "uses": []})
		if not (made in e["uses"]):
			e["uses"].append(made)
		journal["items"][need] = e


func note_place(text: String) -> void:
	if OnlineGen.is_online(current_level):
		return
	var pl: Dictionary = journal["places"].get(current_level, {"visits": 0, "notes": []})
	if not pl.has("notes"):
		pl["notes"] = []
	if not (text in pl["notes"]):
		pl["notes"].append(text)
	journal["places"][current_level] = pl


func item_desc(id: String) -> String:
	## A description that grows with you: the base line, then whatever
	## your skills let you see in it, then what you know it's used for.
	var d := item_def(id)
	var out := str(d.get("desc", ""))
	if str(d.get("type", "")) == "weapon":
		var k := weapon_kind(id)
		out += I18n.t(" [%s: %d damage, %s%s]") % [k.get("name", I18n.t("Weapon")), int(d.get("damage", 0)), k.get("note", ""),
			(", speed x%.2f" % weapon_speed(id)) if absf(weapon_speed(id) - 1.0) > 0.01 else ""]
		var wt := weapon_trait(id)
		if wt.has("name"):
			out += " %s: %s." % [str(wt["name"]), str(wt.get("desc", ""))]
	for row in items.get(base_id(id), {}).get("lore", []):
		if skill_level(str(row.get("skill", ""))) >= int(row.get("level", 0)):
			out += " " + str(row.get("text", ""))
	if inscription_text(id) != "":
		out += " " + inscription_text(id) + "."          # round 38
	var known: Array = journal["items"].get(base_id(id), {}).get("uses", [])
	var uses := []
	for r in recipes:
		if r.get("needs", {}).has(base_id(id)):
			var mk := str(r["makes"])
			if mk in known or skill_level(str(r.get("skill", ""))) >= 3:
				uses.append(item_name(mk))
	if uses.size() > 0:
		out += I18n.t(" Used for: %s.") % ", ".join(uses)
	return out


# ======================================================================
# guilds -- join any, all, or none; rivals cost you
# ======================================================================

func in_guild(gid: String) -> bool:
	return guilds.has(gid)


func guild_name(gid: String) -> String:
	return str(guild_defs.get(gid, {}).get("name", gid.capitalize()))


func join_guild(gid: String) -> String:
	if not guild_defs.has(gid):
		return ""
	if in_guild(gid):
		return I18n.t("You're already one of the %s.") % guild_name(gid)
	guilds[gid] = {"rep": 0.0, "contract": {}}
	var t := "You join the %s." % guild_name(gid)
	var owed := float(flags.get("story:rep_owed:" + gid, 0.0))     # round 32: standing the story earned you before you joined
	if owed > 0.0:
		flags.erase("story:rep_owed:" + gid)
		add_guild_rep(gid, owed)
		t += I18n.t(" They knew your name already (+%d standing).") % int(owed)
	var rival := str(guild_defs[gid].get("rival", ""))
	if rival != "" and in_guild(rival):
		t += I18n.t(" The %s won't like it: while you belong to both, each trusts you half as much.") % guild_name(rival)
	message.emit(I18n.t("GUILD: ") + t)
	log_event("guild_join", {"guild": gid})
	stats_changed.emit()
	return t


func leave_guild(gid: String) -> void:
	if guilds.erase(gid):
		message.emit("GUILD: You leave the %s. Your standing there is gone." % guild_name(gid))
		log_event("guild_leave", {"guild": gid})
		stats_changed.emit()


func guild_rank(gid: String) -> int:
	if not in_guild(gid):
		return -1
	if gid == "academy":
		return int(academy.get("rank", 0))     # Academy ranks are won in rank trials, not just earned
	var rep := float(guilds[gid].get("rep", 0.0))
	var best := 0
	var ranks: Array = guild_defs.get(gid, {}).get("ranks", [])
	for i in ranks.size():
		if rep >= float(ranks[i].get("rep", 0)):
			best = i
	return best


func guild_rank_name(gid: String) -> String:
	var ranks: Array = guild_defs.get(gid, {}).get("ranks", [])
	var r := guild_rank(gid)
	return str(ranks[r].get("name", "")) if r >= 0 and r < ranks.size() else ""


func _rival_penalty(gid: String) -> float:
	var rival := str(guild_defs.get(gid, {}).get("rival", ""))
	return RIVAL_REP_MULT if rival != "" and in_guild(rival) else 1.0


func add_guild_rep(gid: String, amount: float) -> void:
	if not in_guild(gid) or amount <= 0.0:
		return
	var before := guild_rank(gid)
	guilds[gid]["rep"] = float(guilds[gid].get("rep", 0.0)) + amount * _rival_penalty(gid)
	if gid == "academy":
		academy["merit"] = float(academy.get("merit", 0.0)) + amount      # the sect's contribution
	else:
		guilds[gid]["contrib"] = float(guilds[gid].get("contrib", 0.0)) + amount * _rival_penalty(gid)
	var after := guild_rank(gid)
	if after > before:
		var rk: Dictionary = guild_defs[gid]["ranks"][after]
		message.emit(I18n.t("GUILD: You are now a %s of the %s%s.") % [rk.get("name", ""), guild_name(gid),
			(" -- " + str(rk["perk"])) if rk.has("perk") else ""])
		log_event("guild_rank", {"guild": gid, "rank": rk.get("name", "")})
	stats_changed.emit()


func guild_event(source: String, amount: float = 1.0) -> void:
	## Something happened (a kill, a gathered herb, a crafted salve); every
	## guild you belong to that values it raises your standing.
	if source == "gather":
		counters["gathered"] = float(counters.get("gathered", 0.0)) + amount
	elif source == "boss":
		counters["bosses"] = float(counters.get("bosses", 0.0)) + 1.0
	for gid in guilds.keys():
		var per := float(guild_defs.get(gid, {}).get("rep_from", {}).get(source, 0.0))
		if per > 0.0:
			add_guild_rep(gid, per * amount)


func contract_offer(gid: String) -> Dictionary:
	## The next contract this guild has for you. All done? They come round
	## again -- there is always work.
	var cs: Array = guild_defs.get(gid, {}).get("contracts", [])
	if cs.is_empty():
		return {}
	for c in cs:
		if float(counters.get("contract_done:" + str(c["id"]), 0.0)) < 1.0:
			return c
	var total := 0
	for c in cs:
		total += int(counters.get("contract_done:" + str(c["id"]), 0.0))
	return cs[total % cs.size()]


func take_contract(gid: String, c: Dictionary) -> void:
	if not in_guild(gid):
		return
	var g: Dictionary = c.get("goal", {})
	guilds[gid]["contract"] = {"id": c["id"],
		"kills0": int(kills.get(str(g.get("kill", "")), 0)),
		"craft0": int(counters.get("crafted:" + str(g.get("craft", "")), 0.0))}
	message.emit(I18n.t("Contract taken: ") + str(c.get("desc", "")))
	log_event("contract_take", {"guild": gid, "id": c["id"]})


func _contract_def(gid: String) -> Dictionary:
	var cur: Dictionary = guilds.get(gid, {}).get("contract", {})
	for c in guild_defs.get(gid, {}).get("contracts", []):
		if c["id"] == cur.get("id", ""):
			return c
	return {}


func contract_progress(gid: String) -> Array:
	## [done, needed] for the active contract ([0, 0] when there is none).
	var c := _contract_def(gid)
	if c.is_empty():
		return [0, 0]
	var cur: Dictionary = guilds[gid]["contract"]
	var g: Dictionary = c.get("goal", {})
	var need := int(g.get("count", 1))
	if g.has("kill"):
		return [mini(int(kills.get(str(g["kill"]), 0)) - int(cur.get("kills0", 0)), need), need]
	if g.has("craft"):
		return [mini(int(counters.get("crafted:" + str(g["craft"]), 0.0)) - int(cur.get("craft0", 0)), need), need]
	if g.has("have"):
		return [mini(count(str(g["have"])), need), need]
	return [0, need]


func contract_ready(gid: String) -> bool:
	var p := contract_progress(gid)
	return int(p[1]) > 0 and int(p[0]) >= int(p[1])


func turn_in_contract(gid: String) -> bool:
	if not contract_ready(gid):
		return false
	var c := _contract_def(gid)
	var g: Dictionary = c.get("goal", {})
	if g.has("have") and bool(g.get("take", false)):
		remove_item(str(g["have"]), int(g.get("count", 1)))
	var rw: Dictionary = c.get("reward", {})
	var repeat := float(counters.get("contract_done:" + str(c["id"]), 0.0)) >= 1.0
	counters["contract_done:" + str(c["id"])] = float(counters.get("contract_done:" + str(c["id"]), 0.0)) + 1.0
	guilds[gid]["contract"] = {}
	if rw.has("gold"):
		add_item("gold", int(rw["gold"]))
	add_guild_rep(gid, float(rw.get("rep", 0)) * (0.6 if repeat else 1.0))
	message.emit("Contract complete for the %s." % guild_name(gid))
	log_event("contract_done", {"guild": gid, "id": c["id"]})
	return true


func jewel_effect(id: String) -> Dictionary:
	## A ring's or amulet's effect, scaled by its quality: a Fine jade ring
	## gives a little more than a plain one, a Crude one a little less.
	var base: Dictionary = items.get(base_id(id), {}).get("effect", {})
	var m: float = float(QUALITY[quality_index(id)]["mult"])
	var out := {}
	for k in base:
		var v = base[k]
		if v is Dictionary:
			out[k] = v
		elif k in ADDITIVE_KEYS or str(k).begins_with("craft_"):
			out[k] = float(v) * m
		else:
			out[k] = 1.0 + (float(v) - 1.0) * m
	return out


func equip(id: String, slot: String = "") -> String:
	## round 27: put it on -- in `slot`, or the first free slot of its kind
	## (else the first of its kind). Returns what happened.
	return wear(id, slot)


# ======================================================================
# familiars -- an animal that chose you, and grows with you
# ======================================================================

func bond_familiar(species: String) -> void:
	## round 39: every beast that chooses you is a CONTRACT. The first walks
	## at your heel; the rest wait in your spirit space until you call them.
	var fd: Dictionary = enemies.get(species, {}).get("familiar", {})
	var nb := {"species": species, "name": str(fd.get("name", species.capitalize())), "bond": 0.0, "tier": 0, "out": false}
	var taken := contracts.map(func(c): return str(c.get("name", "")))
	var base_name := str(nb["name"])
	var k := 2
	while str(nb["name"]) in taken:
		nb["name"] = "%s %s" % [base_name, ["", "", "II", "III", "IV", "V", "VI", "VII", "VIII"][mini(k, 8)]]
		k += 1
	contracts.append(nb)
	if familiar.is_empty():
		nb["out"] = true
		nb["lead"] = true
		familiar = nb
		message.emit(I18n.t("FAMILIAR: The %s follows you now. You call it %s.") % [str(enemies.get(species, {}).get("name", species)).to_lower(), familiar["name"]])
	else:
		message.emit(I18n.t("CONTRACT: The %s binds itself to you -- %s waits in your spirit space (call it from the menu, Party).") % [str(enemies.get(species, {}).get("name", species)).to_lower(), nb["name"]])
	log_event("familiar", {"species": species})
	note_place(I18n.t("Befriended ") + str(nb["name"]))
	familiar_changed.emit()
	stats_changed.emit()


func grow_bond(amount: float, beast: Dictionary = {}) -> void:
	var f := _bst(beast)
	if f.is_empty():
		return
	var before := int(float(f.get("bond", 0.0)) / 25.0)
	var stage0 := familiar_stage(beast)
	if has_perk("wild_call"):
		amount *= 1.5
	if amount > 0.0:
		amount *= tech_effect("bond_mult", 1.0)      # round 40: Connection
	f["bond"] = minf(float(f.get("bond", 0.0)) + amount, 200.0)
	if int(float(f["bond"]) / 25.0) > before and amount >= 0.5:
		message.emit(I18n.t("FAMILIAR: %s trusts you more. (bond %d)") % [f["name"], int(f["bond"])])
	familiar_stage_check(stage0, beast)                 # round 32: it grows


# ======================================================================
# bonds -- people who come to know you, through what you say to them
# ======================================================================

func bond(name: String) -> Dictionary:
	if not bonds.has(name):
		bonds[name] = {"warmth": 0.0, "talks": 0, "memories": []}
	return bonds[name]


func bond_stage(name: String) -> String:
	var w := float(bond(name).get("warmth", 0.0))
	var t := "a stranger"
	for row in BOND_STAGES:
		if w >= float(row[0]):
			t = str(row[1])
	return t


func adjust_bond(name: String, delta: float, memory: String = "") -> void:
	## Warmth moves with what you say and do -- by chance as much as by
	## design; a stage crossed is a moment worth noting.
	var b := bond(name)
	b["talks"] = int(b.get("talks", 0)) + 1
	if memory.strip_edges() != "":
		var mem: Array = b.get("memories", [])
		mem.append(memory.strip_edges().left(140))
		b["memories"] = mem.slice(maxi(0, mem.size() - 8))
	warm_bond(name, delta)


func warm_bond(name: String, delta: float) -> void:
	## Warmth without words: time on the road together, a fight shared.
	var b := bond(name)
	var before := bond_stage(name)
	if delta > 0.0:
		delta *= tech_effect("bond_mult", 1.0)       # round 40: Connection
	b["warmth"] = clampf(float(b.get("warmth", 0.0)) + delta, -50.0, 100.0)
	var after := bond_stage(name)
	if after != before and float(b["warmth"]) > 0.0:
		message.emit(I18n.t("BOND: %s now counts you as %s.") % [name, after.trim_prefix("a ").trim_prefix("an ")] if not after.begins_with("devoted") else I18n.t("BOND: %s is devoted to you.") % name)
		log_event("bond", {"npc": name, "stage": after})
		note_place("%s: %s" % [name, after])
	stats_changed.emit()


# ======================================================================
# companions -- someone who chooses to walk with you (Companion.gd)
# ======================================================================

func can_ask_companion(name: String) -> bool:
	return float(bond(name).get("warmth", 0.0)) >= COMPANION_WARMTH and in_party(name) < 0


func asked_recently(name: String, what: String) -> bool:
	return gathered_recently("ask:%s:%s" % [what, name], ASK_AGAIN_SECONDS)


func companion_chance(name: String) -> float:
	## Warmth tilts it; chance decides it.
	var w := float(bond(name).get("warmth", 0.0))
	return clampf(0.3 + (w - COMPANION_WARMTH) / 50.0, 0.3, 0.95)


func ask_companion(name: String, persona_text: String, home: String, tint: Color, roll: float) -> String:
	## "yes", "no" (not now -- ask again later), "later" (asked too recently),
	## "not_close" (they don't know you well enough yet).
	if not can_ask_companion(name):
		return "not_close"
	if asked_recently(name, "travel"):
		return "later"
	if roll >= companion_chance(name):
		set_flag("ask:travel:" + name, Time.get_unix_time_from_system())
		log_event("companion_declined", {"npc": name})
		return "no"
	return seat_companion(name, persona_text, home, tint)


func seat_companion(name: String, persona_text: String, home: String, tint: Color) -> String:
	## they say yes: seat them (also how a wayfarer is taken on -- scripts/systems/Menagerie.gd)
	var into := party_free_slot()
	if into < 0:
		into = 1 if party_size() >= 2 else 0       # a full party: the newest takes the second place
		part_with_companion(into)
	var nc := {"name": name, "persona": persona_text, "home": home,
		"tint": [tint.r, tint.g, tint.b], "partner": partner == name}
	if into == 1:
		companion2 = nc
	else:
		companion = nc
	var bd := bond(name)                       # round 39: remembered, so you can call them again (the roster)
	bd["persona"] = persona_text
	bd["home"] = home
	bd["tint"] = [tint.r, tint.g, tint.b]
	warm_bond(name, 2.0)
	set_flag("travelled:" + name)
	message.emit("COMPANION: %s comes with you." % name)
	log_event("companion", {"npc": name})
	note_place("%s began travelling with you" % name)
	companion_changed.emit()
	save_game()
	return "yes"


func part_with_companion(slot: int = 0) -> void:
	var cc := cslot(slot)
	if cc.is_empty():
		return
	var name := str(cc.get("name", ""))
	if cc.has("search"):
		message.emit(I18n.t("%s is out searching -- wait until they are back.") % name)
		return
	var home := str(cc.get("home", "village"))
	message.emit(I18n.t("%s heads back to %s. You'll find them there.") % [name, I18n.t("the village") if home == "village" else str(havens.get(home, home))])
	log_event("companion_parted", {"npc": name})
	if slot == 1:
		companion2 = {}
	else:
		companion = companion2              # the second steps up to your shoulder
		companion2 = {}
	companion_changed.emit()


func can_ask_partner(name: String) -> bool:
	return partner == "" and in_party(name) >= 0 and float(bond(name).get("warmth", 0.0)) >= PARTNER_WARMTH


func ask_partner(name: String, roll: float) -> bool:
	if not can_ask_partner(name) or asked_recently(name, "partner"):
		return false
	var w := float(bond(name).get("warmth", 0.0))
	if roll >= clampf(0.45 + (w - PARTNER_WARMTH) / 30.0, 0.45, 0.95):
		set_flag("ask:partner:" + name, Time.get_unix_time_from_system())
		log_event("partner_declined", {"npc": name})
		return false
	partner = name
	cslot(in_party(name))["partner"] = true
	warm_bond(name, 5.0)
	message.emit("PARTNER: %s walks the road of cultivation with you now." % name)
	log_event("partner", {"npc": name})
	note_place("%s became your partner" % name)
	companion_changed.emit()
	stats_changed.emit()
	save_game()
	return true


func brute_hp_line(d: int) -> int:
	## Above this many hit points a monster counts as one of its floor's big
	## ones (better odds of carrying gear): twice the floor's weakest.
	var lo := 0
	for e in enemies:
		var st: Dictionary = enemies[e]
		if int(st.get("floor", -1)) == d and not bool(st.get("passive", false)) and not bool(st.get("boss", false)):
			lo = int(st.get("hp", 0)) if lo == 0 else mini(lo, int(st.get("hp", 0)))
	return lo * 2 if lo > 0 else 999999


# ======================================================================
# the arena: the Academy's trials and the settlements' tournaments
# ======================================================================

func floor_foes(d: int, brutes: bool = false) -> Array:
	## The ordinary monsters of the nearest floor at or above depth d.
	var best := -1
	for e in enemies:
		var st: Dictionary = enemies[e]
		var f := int(st.get("floor", -1))
		if f >= 1 and f <= d and not bool(st.get("passive", false)) and not bool(st.get("boss", false)) and f > best:
			best = f
	var out := []
	for e in enemies:
		var st: Dictionary = enemies[e]
		if int(st.get("floor", -1)) == best and not bool(st.get("passive", false)) and not bool(st.get("boss", false)):
			out.append(e)
	out.sort_custom(func(a, b): return int(enemies[a].get("hp", 0)) < int(enemies[b].get("hp", 0)))
	return out


func _start_arena(state: Dictionary) -> void:
	arena = state
	arena["stage"] = 0
	arena["return_to"] = current_level
	log_event("arena_start", {"event": state.get("event", ""), "host": state.get("host", "")})
	hp = max_hp()
	go_to(Arena.make_id(str(state["host"]), str(state["event"]), 0), "P")


func arena_active() -> bool:
	return not arena.is_empty() and not arena.has("result")


func start_exam_strength(host: String, host_depth: int) -> void:
	var f := floor_foes(maxi(host_depth - 2, 1))
	var a: String = f[0] if f.size() > 0 else "goblin"
	var b: String = f[f.size() - 1] if f.size() > 0 else "goblin_brute"
	_start_arena({"event": "exam", "host": host, "depth": host_depth, "title": "The Academy's Trial of Strength",
		"round_names": ["First Wave", "Second Wave", "Last Wave"],
		"rounds": [[{"id": a, "count": 2}], [{"id": a, "count": 2}, {"id": b, "count": 1}], [{"id": a, "count": 2}, {"id": b, "count": 2}]]})


func academy_rank_def(r: int) -> Dictionary:
	var ranks: Array = guild_defs.get("academy", {}).get("ranks", [])
	return ranks[r] if r >= 0 and r < ranks.size() else {}


func can_rank_trial() -> String:
	## "" when the next rank trial is open to you, else why not.
	if not bool(academy.get("enrolled", false)):
		return I18n.t("You are not a disciple of the Academy.")
	var nxt := academy_rank_def(int(academy.get("rank", 0)) + 1)
	if nxt.is_empty():
		return I18n.t("There is no rank above yours. The Academy has nothing left to test you on.")
	if float(guilds.get("academy", {}).get("rep", 0.0)) < float(nxt.get("rep", 0)):
		return I18n.t("Your standing (%d) is short of what a %s needs (%d).") % [int(guilds.get("academy", {}).get("rep", 0.0)), nxt.get("name", ""), int(nxt.get("rep", 0))]
	if realm < int(nxt.get("realm", 0)):
		return I18n.t("A %s must have reached %s.") % [nxt.get("name", ""), realm_info(int(nxt.get("realm", 0)))["name"]]
	return ""


func start_rank_trial(host: String) -> void:
	var r := int(academy.get("rank", 0)) + 1
	var nxt := academy_rank_def(r)
	var tier := int(nxt.get("trial_tier", 4 * r + 2))
	var f := floor_foes(tier)
	var a: String = f[0] if f.size() > 0 else "goblin"
	var b: String = f[f.size() - 1] if f.size() > 0 else "goblin_brute"
	_start_arena({"event": "rank", "host": host, "depth": tier, "title": "Rank Trial: %s" % nxt.get("name", ""),
		"round_names": ["First Bout", "Second Bout", "Final Bout"],
		"rounds": [[{"id": a, "count": 2}], [{"id": a, "count": 1}, {"id": b, "count": 1}], [{"id": b, "count": 2}, {"id": a, "count": 1}]]})


func tourney_cooldown(host: String) -> float:
	## seconds until this settlement's next tournament will have you (0 = now)
	var key := "tourney:" + host
	if not flags.has(key):
		return 0.0
	return maxf(0.0, TOURNEY_COOLDOWN - (Time.get_unix_time_from_system() - float(flags[key])))


func start_tournament(host: String, host_name: String, tier: int, roll: float = -1.0) -> bool:
	if tourney_cooldown(host) > 0.0:
		return false
	var fee := 10 * tier
	if gold < fee:
		return false
	gold -= fee
	var pool := Arena.RIVALS.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_unix_time_from_system()) if roll < 0.0 else int(roll * 100000.0)
	# the final is against whoever you've crossed most -- rivals come back
	pool.sort_custom(func(a, b): return int(rivals.get(a["name"], {}).get("met", 0)) > int(rivals.get(b["name"], {}).get("met", 0)))
	var finalist: Dictionary = pool[0] if int(rivals.get(pool[0]["name"], {}).get("met", 0)) > 0 else pool[rng.randi_range(0, pool.size() - 1)]
	pool.erase(finalist)
	var picks := []
	for i in 2:
		picks.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	picks.append(finalist)
	var defs := {}
	var rounds := []
	var names := []
	for r in picks:
		var eid := "rival_" + str(r["name"]).to_lower().replace(" ", "_")
		defs[eid] = Arena.rival_def(r, tier, int(rivals.get(r["name"], {}).get("met", 0)))
		rounds.append([{"id": eid, "count": 1}])
		names.append(r["name"])
	_start_arena({"event": "tour", "host": host, "host_name": host_name, "depth": tier, "tier": tier,
		"title": "The %s Tournament" % host_name, "round_names": ["Quarterfinal", "Semifinal", "Final"],
		"rounds": rounds, "defs": defs, "opponents": names})
	message.emit("TOURNAMENT: %s, %s, and in the final, %s." % names)
	return true


func _rival_meet(name: String, you_won: bool) -> void:
	var r: Dictionary = rivals.get(name, {"met": 0, "beat": 0, "lost": 0})
	r["met"] = int(r.get("met", 0)) + 1
	if you_won:
		r["beat"] = int(r.get("beat", 0)) + 1
	else:
		r["lost"] = int(r.get("lost", 0)) + 1
	rivals[name] = r


func _rival_line(name: String, key: String) -> String:
	for r in Arena.RIVALS:
		if r["name"] == name:
			return str(r.get(key, ""))
	return ""


func arena_round_foe() -> String:
	if str(arena.get("event", "")) != "tour":
		return ""
	var ops: Array = arena.get("opponents", [])
	var st := int(arena.get("stage", 0))
	return str(ops[st]) if st < ops.size() else ""


func arena_cleared() -> void:
	## Everything in the ring is down.
	if not arena_active():
		return
	var foe := arena_round_foe()
	if foe != "":
		_rival_meet(foe, true)
		message.emit("%s: %s" % [foe, _rival_line(foe, "win")])
	arena["stage"] = int(arena.get("stage", 0)) + 1
	hp = max_hp()
	if str(arena.get("event", "")) == "gauntlet":
		Hook.gauntlet_wave_cleared()
	if int(arena["stage"]) < arena.get("rounds", []).size():
		if str(arena.get("event", "")) == "gauntlet":
			Hook.gauntlet_between()                  # a boon first; it calls arena_next()
			return
		arena_next()
	else:
		_arena_finished(true)


func arena_next() -> void:
	var nm: Array = arena.get("round_names", [])
	message.emit("ARENA: Round won. Next: %s." % (nm[arena["stage"]] if int(arena["stage"]) < nm.size() else "the next round"))
	go_to(Arena.make_id(str(arena["host"]), str(arena["event"]), int(arena["stage"])), "P")


func arena_lost(cause: String = "") -> void:
	if arena.is_empty():
		return
	if Hook.gauntlet_revive():
		return
	var foe := arena_round_foe()
	if foe != "":
		_rival_meet(foe, false)
		message.emit("%s: %s" % [foe, _rival_line(foe, "lose")])
	hp = max_hp()
	meditating = false
	log_event("arena_lost", {"event": arena.get("event", ""), "stage": arena.get("stage", 0), "cause": cause})
	_arena_finished(false)


func _arena_finished(won: bool) -> void:
	var ev := str(arena.get("event", ""))
	var host := str(arena.get("host", "village"))
	var tier := int(arena.get("tier", arena.get("depth", 1)))
	var text := ""
	match ev:
		"exam":
			if won:
				academy["trials"]["strength"] = true
				text = I18n.t("The examiner nods once. \"Strength: passed.\"")
			else:
				text = I18n.t("You wake on a bench outside the ring. The examiner says you may try again whenever you are ready.")
		"rank":
			if won:
				academy["rank"] = int(academy.get("rank", 0)) + 1
				var rk := academy_rank_def(int(academy["rank"]))
				text = I18n.t("You are now a %s of the Lotus Ascent Academy%s.") % [rk.get("name", ""), (" -- " + str(rk["perk"])) if rk.has("perk") else ""]
				note_place("Became a %s of the Academy" % rk.get("name", ""))
				log_event("academy_rank", {"rank": rk.get("name", "")})
			else:
				text = I18n.t("The proctors carry you out. The trial will wait for you.")
		"gauntlet":
			text = Hook.gauntlet_end(won)
		"tour":
			flags["tourney:" + host] = Time.get_unix_time_from_system()
			if won:
				var prize := 40 * tier
				gold += prize
				var title := "Champion of %s" % arena.get("host_name", host)
				if not (title in titles):
					titles.append(title)
				counters["tourney_wins"] = float(counters.get("tourney_wins", 0.0)) + 1.0
				add_guild_rep("academy", 60.0)
				drop_gear(tier + 1, 3)
				text = I18n.t("The crowd roars your name. %d gold, a prize from the champions' rack, and a title: %s.") % [prize, title]
				note_place(title)
			else:
				text = I18n.t("Knocked out of the %s. The crowd moves on; you won't forget who beat you.") % arena.get("title", "tournament")
	arena = {"result": ev, "won": won, "text": text, "host": host}
	message.emit(I18n.t("ARENA: ") + text)
	log_event("arena_done", {"event": ev, "won": won})
	go_to(host, "P")


# ---- the Academy's other two entrance trials -----------------------------

func exam_knowledge_seed() -> int:
	return int(counters.get("exam_knowledge_tries", 0.0)) * 7919 + 17


func knowledge_retry_wait() -> float:
	if not flags.has("exam:knowledge:fail"):
		return 0.0
	return maxf(0.0, KNOWLEDGE_RETRY - (Time.get_unix_time_from_system() - float(flags["exam:knowledge:fail"])))


func exam_knowledge_done(score: int) -> bool:
	counters["exam_knowledge_tries"] = float(counters.get("exam_knowledge_tries", 0.0)) + 1.0
	if score >= AcademyLib.PASS_MARK:
		academy["trials"]["knowledge"] = true
		return true
	flags["exam:knowledge:fail"] = Time.get_unix_time_from_system()
	return false


func craft_trial_candidates() -> Array:
	## Things you made yourself, Fine or better, that you still have.
	var out := []
	for id in inventory:
		if count(id) > 0 and quality_index(id) >= 2 and float(counters.get("made:" + str(id), 0.0)) > 0.0:
			out.append(id)
	out.sort()
	return out


func exam_present_craft(id: String) -> bool:
	if not (id in craft_trial_candidates()):
		return false
	remove_item(id, 1)
	academy["trials"]["craft"] = true
	return true


func exam_complete() -> bool:
	var t: Dictionary = academy.get("trials", {})
	return bool(t.get("strength", false)) and bool(t.get("knowledge", false)) and bool(t.get("craft", false))


func enroll() -> bool:
	if bool(academy.get("enrolled", false)) or not exam_complete():
		return false
	academy["enrolled"] = true
	academy["rank"] = 0
	guilds["academy"] = {"rep": 0.0, "contract": {}}
	add_item("lotus_disciple_robe", 1)
	add_guild_rep("academy", 40.0)
	titles.append(I18n.t("Outer Disciple of the Lotus Ascent Academy"))
	message.emit("ACADEMY: You are an Outer Disciple of the Lotus Ascent Academy.")
	note_place("Entered the Lotus Ascent Academy")
	log_event("academy_enrolled", {})
	stats_changed.emit()
	return true


func library_list() -> Array:
	## [{tech, rank, merit}] the Academy library offers (Academy rank-gated)
	return guild_defs.get("academy", {}).get("library", [])


func library_learn(tid: String) -> String:
	for row in library_list():
		if str(row.get("tech", "")) != tid:
			continue
		if has_tech(tid):
			return I18n.t("You already know it.")
		if int(academy.get("rank", -1)) < int(row.get("rank", 0)) or not bool(academy.get("enrolled", false)):
			return I18n.t("That scroll is kept for a %s.") % academy_rank_def(int(row.get("rank", 0))).get("name", I18n.t("higher rank"))
		if float(academy.get("merit", 0.0)) < float(row.get("merit", 0)):
			return I18n.t("You need %d merit; you have %d.") % [int(row.get("merit", 0)), int(academy.get("merit", 0.0))]
		academy["merit"] = float(academy.get("merit", 0.0)) - float(row.get("merit", 0))
		learn(tid, "the Academy library")
		return ""
	return I18n.t("The library has no such scroll.")


# ======================================================================
# contribution: what guilds and the sect let you SPEND (Robert, 2026-10-02:
# "use sect and guild contribution points for special items"). Standing
# (rep) is what you are to them and never goes down; contribution is
# earned alongside it and spent on their special stock, on donations
# taken in, and on a piece made just for you.
# ======================================================================

func contribution(gid: String) -> float:
	if gid == "academy":
		return float(academy.get("merit", 0.0))
	return float(guilds.get(gid, {}).get("contrib", 0.0))


func contribution_name(gid: String) -> String:
	return "merit" if gid == "academy" else "contribution"


func spend_contribution(gid: String, amount: float) -> bool:
	if not in_guild(gid) or contribution(gid) < amount:
		return false
	if gid == "academy":
		academy["merit"] = float(academy.get("merit", 0.0)) - amount
	else:
		guilds[gid]["contrib"] = float(guilds[gid].get("contrib", 0.0)) - amount
	stats_changed.emit()
	return true


func guild_specials(gid: String) -> Array:
	return guild_defs.get(gid, {}).get("specials", [])


func special_block(gid: String, row: Dictionary) -> String:
	## "" when you may have it now, else why not.
	var id := str(row.get("item", ""))
	if not in_guild(gid):
		return I18n.t("Members only.")
	if not bool(row.get("repeat", false)) and count(id) > 0:
		return I18n.t("You already have one.")
	var rk := int(row.get("rank", 0))
	if guild_rank(gid) < rk:
		var ranks: Array = guild_defs.get(gid, {}).get("ranks", [])
		return I18n.t("Kept for a %s.") % (str(ranks[rk].get("name", I18n.t("higher rank"))) if rk < ranks.size() else I18n.t("higher rank"))
	if contribution(gid) < float(row.get("cost", 0)):
		return I18n.t("Needs %d %s (you have %d).") % [int(row.get("cost", 0)), contribution_name(gid), int(contribution(gid))]
	return ""


func buy_special(gid: String, id: String) -> String:
	for row in guild_specials(gid):
		if str(row.get("item", "")) != id:
			continue
		var why := special_block(gid, row)
		if why != "":
			return why
		spend_contribution(gid, float(row.get("cost", 0)))
		add_item(id, 1)
		log_event("special_bought", {"guild": gid, "id": id})
		note_place(I18n.t("The %s gave you their %s") % [guild_name(gid), item_name(id)])
		return ""
	return I18n.t("They have no such thing.")


func donation_value(gid: String) -> int:
	## Materials the guild will take, and what they're worth to it.
	if gid == "academy" or not in_guild(gid):
		return 0
	var v := 0
	for id in inventory:
		if str(items.get(id, {}).get("type", "")) == "material":
			v += int(items[id].get("value", 0)) * count(id)
	return int(v / 6.0)


func donate_materials(gid: String) -> int:
	var v := donation_value(gid)
	if v <= 0:
		return 0
	for id in inventory.keys():
		if str(items.get(id, {}).get("type", "")) == "material":
			remove_item(id, count(id))
	add_guild_rep(gid, float(v))
	log_event("donation", {"guild": gid, "value": v})
	return v


# ======================================================================
# made for you: a tailored piece (paid in contribution) and wishes at a
# settlement's smith (Robert: "allow ai to tailor item to users game play
# or allow them to request up to 3 items the AI with randomly generated").
# The AI only ever chooses WHAT it is -- its kind, name, look, and which
# gift it carries. How strong it is comes from here, from the depth you've
# reached, the same lines the floor forge's own gear follows.
# ======================================================================

func reach_depth() -> int:
	var d := maxi(depth, 1)
	for pid in journal.get("places", {}):
		var s := str(pid)
		if s.begins_with("floor") and s.substr(5).is_valid_int():
			d = maxi(d, int(s.substr(5)))
	return d


func design_effect(key: String, d: int, roll: float = 1.0) -> Dictionary:
	## {key: value} for a made piece's gift at depth d (roll 0..1 = how good
	## a casting it was). "craft_success_<skill>" / "craft_quality_<skill>" ok.
	var base := key
	for pre in ["craft_success", "craft_quality"]:
		if key.begins_with(pre):
			base = pre
	if not DESIGN_EFFECTS.has(base):
		return {}
	var row: Array = DESIGN_EFFECTS[base]
	var v := minf(float(row[0]) + float(row[1]) * float(d), float(row[2])) * (0.6 + 0.4 * clampf(roll, 0.0, 1.0))
	match base:
		"hp_mult", "damage_mult", "qi_mult", "attack_speed", "meditate_mult":
			return {key: snappedf(1.0 + v, 0.001)}
		"damage_taken":
			return {key: snappedf(1.0 - v, 0.001)}
		"heal_on_kill":
			return {key: float(int(round(v)))}
	return {key: snappedf(v, 0.001)}


func _favorite_kind() -> String:
	var best := "fists"
	var bx := -1.0
	for kind in WEAPON_SKILL:
		var x := float(skills.get(WEAPON_SKILL[kind], 0.0))
		if x > bx:
			bx = x
			best = str(kind)
	return best


func play_profile() -> Dictionary:
	## How you actually play -- what a tailor reads before cutting cloth.
	var total_kills := 0
	for k in kills:
		total_kills += int(kills[k])
	var crafted := 0.0
	for c in counters:
		if str(c).begins_with("crafted:"):
			crafted += float(counters[c])
	var gath := 0.0
	var craft_best := ""
	var cb := -1.0
	for sid in skill_defs:
		var kind := str(skill_defs[sid].get("kind", ""))
		var x := float(skills.get(sid, 0.0))
		if kind == "gathering":
			gath += x
		if kind == "crafting" and x > cb:
			cb = x
			craft_best = str(sid)
	var elem := "earth"
	var ev := -1.0
	for e in ELEMENTS:
		if float(affinity[e]) > ev:
			ev = float(affinity[e])
			elem = e
	var med := float(counters.get("shrine_seconds", 0.0))
	var scores := {"fighter": total_kills * 10.0, "crafter": crafted * 40.0, "gatherer": gath * 0.6, "cultivator": med * 0.3}
	var style := "fighter"
	var sv := -1.0
	for k in scores:
		if float(scores[k]) > sv:
			sv = float(scores[k])
			style = str(k)
	var fav := _favorite_kind()
	var plans: Dictionary = {
		"fighter": {"type": "weapon", "kind": fav, "effects": ["damage_mult", "attack_speed", "heal_on_kill"]},
		"crafter": {"type": "ring", "kind": "", "effects": ["craft_quality_" + craft_best, "craft_success_" + craft_best]},
		"gatherer": {"type": "amulet", "kind": "", "effects": ["gather_chance", "sense_radius"]},
		"cultivator": {"type": "amulet", "kind": "", "effects": ["qi_mult", "meditate_mult"]},
	}
	var plan: Dictionary = plans[style]
	return {"style": style, "kills": total_kills, "crafted": int(crafted), "favorite_weapon": fav,
		"best_craft": craft_best, "element": elem, "background": background, "depth": reach_depth(),
		"suggest_type": plan["type"], "suggest_kind": plan["kind"], "suggest_effects": plan["effects"],
		"weapon_skill": skill_name(WEAPON_SKILL[fav]), "weapon_level": skill_level(WEAPON_SKILL[fav])}


func finalize_design(design: Dictionary, d: int, roll: float, source: String) -> Dictionary:
	## Bound whatever the AI (or the fallback) proposed into a real item def.
	d = maxi(d, 1)
	var t := str(design.get("type", "ring")).to_lower()
	if not (t in ["weapon", "armor", "ring", "amulet"]):
		t = "ring"
	var name := str(design.get("name", "")).replace("\"", "").replace("\n", " ").strip_edges().left(40)
	if name.length() < 3:
		name = "Nameless " + {"weapon": I18n.t("Blade"), "armor": I18n.t("Coat"), "ring": I18n.t("Ring"), "amulet": I18n.t("Amulet")}[t]
	var desc := str(design.get("desc", "")).replace("\n", " ").strip_edges().left(220)
	var ekey := str(design.get("effect", "")).strip_edges()
	if design_effect(ekey, d).is_empty():
		ekey = {"weapon": "damage_mult", "armor": "damage_taken", "ring": "hp_mult", "amulet": "qi_mult"}[t]
	if ekey.begins_with("craft_success_") or ekey.begins_with("craft_quality_"):
		# "craft_quality_smithing": the skill must be a real craft
		var sk := ekey.trim_prefix("craft_success_").trim_prefix("craft_quality_")
		if str(skill_defs.get(sk, {}).get("kind", "")) != "crafting":
			ekey = "craft_quality" if ekey.begins_with("craft_quality") else "craft_success"
	var r := clampf(roll, 0.0, 1.0)
	var def := {"name": name, "type": t, "custom": true, "made": source, "tier": d}
	var eff := design_effect(ekey, d, r)
	var lines := []
	match t:
		"weapon":
			var kind := str(design.get("kind", _favorite_kind())).to_lower()
			if not WEAPON_KINDS.has(kind):
				kind = _favorite_kind()
			if bool(WEAPON_KINDS[kind].get("ranged", false)) and d < RANGED_MIN_TIER:
				kind = "sword"                      # round 119: no distance weapons in the first few floors
			def["kind"] = kind
			def["damage"] = int(round(5.8 * d * float(KIND_DAMAGE.get(kind, 1.0)) * (0.92 + 0.16 * r)))
			def["value"] = 90 * d
			lines.append(I18n.t("+%d damage (%s)") % [int(def["damage"]), str(WEAPON_KINDS[kind]["name"])])
			eff = design_effect(ekey, int(ceil(d / 2.0)), r)       # a weapon's gift is a lesser one
		"armor":
			def["hp"] = int(round(36.0 * d * (0.92 + 0.16 * r)))
			def["value"] = 90 * d
			lines.append(I18n.t("+%d max HP") % int(def["hp"]))
			eff = design_effect(ekey, int(ceil(d / 2.0)), r)
		_:
			def["value"] = 60 * d
	def["effect"] = eff
	lines.append(effect_text(eff))
	var el := str(design.get("element", "")).to_lower()
	if el in ELEMENTS:
		def["element"] = el
	def["desc"] = ((desc + " ") if desc != "" else "") + "(" + "; ".join(lines) + ")"
	return def


func effect_text(eff: Dictionary) -> String:
	var parts := []
	for k in eff:
		if eff[k] is Dictionary:
			continue
		var v := float(eff[k])
		var ks := str(k)
		if ks.begins_with("craft_") and ks.length() > 13 and (ks.begins_with("craft_success_") or ks.begins_with("craft_quality_")):
			parts.append("+%d%% %s %s" % [int(round(v * 100)), I18n.t("success at") if ks.begins_with("craft_success") else I18n.t("finer work in"),
				skill_name(ks.trim_prefix("craft_success_").trim_prefix("craft_quality_"))])
			continue
		match ks:
			"damage_taken":
				parts.append(I18n.t("-%d%% damage taken") % int(round((1.0 - v) * 100)))
			"hp_mult", "damage_mult", "qi_mult", "attack_speed", "meditate_mult":
				parts.append("+%d%% %s" % [int(round((v - 1.0) * 100)), {"hp_mult": I18n.t("max HP"), "damage_mult": "damage", "qi_mult": "qi",
					"attack_speed": "strike speed", "meditate_mult": "meditation"}[ks]])
			"gather_chance":
				parts.append(I18n.t("+%d%% gathering") % int(round(v * 100)))
			"heal_on_kill":
				parts.append(I18n.t("+%d HP per kill") % int(v))
			"sense_radius":
				parts.append(I18n.t("+%dm spirit sense") % int(round(v)))
			"ward":
				parts.append(I18n.t("+%.1f ward") % v)
			"regen":
				parts.append(I18n.t("+%.2f health a second") % v)
			"craft_success", "craft_quality":
				parts.append("+%d%% %s" % [int(round(v * 100)), I18n.t("craft success") if ks == "craft_success" else "finer work"])
			"crit_chance":
				parts.append(I18n.t("+%d%% chance of a telling blow") % int(round(v * 100)))
			"dodge_chance":
				parts.append(I18n.t("+%d%% chance to slip a blow") % int(round(v * 100)))
			"burn_on_hit":
				parts.append(I18n.t("your blows burn (%d)") % int(v))
			"loot_luck":
				parts.append(I18n.t("+%d%% chance of a second share of loot") % int(round(v * 100)))
			"rebirth":
				parts.append(I18n.t("once a day, rise from a killing blow"))
			"low_hp_fury":
				parts.append(I18n.t("+%d%% damage when badly hurt") % int(round(v * 100)))
			"swarm_mult", "move_mult":
				parts.append("%+d%% %s" % [int(round((v - 1.0) * 100)), I18n.t("swarm growth") if ks == "swarm_mult" else "speed"])
			"focus_mult", "adapt_mult", "insight_mult", "bond_mult", "research_speed", "cleanse_speed":
				parts.append("%+d%% %s" % [int(round((v - 1.0) * 100)), {"focus_mult": I18n.t("focus (meridians, cleansing, research)"), "adapt_mult": I18n.t("skill growth"),
					"insight_mult": "insight", "bond_mult": "bonds", "research_speed": "research speed", "cleanse_speed": "cleansing speed"}[ks]])
			"upkeep_mult":
				parts.append(I18n.t("-%d%% qi upkeep") % int(round((1.0 - v) * 100)))
			"timing":
				parts.append(I18n.t("+%.2f s to parry and roll") % v)
			"sight":
				parts.append(I18n.t("+%d sight") % int(round(v)))
			"gather_bonus":
				parts.append(I18n.t("+%d to every gathering") % int(round(v)))
			_:
				parts.append("%s %s" % [ks, str(v)])
	return ", ".join(parts) if parts.size() > 0 else I18n.t("no gifts")


func register_custom_item(def: Dictionary) -> String:
	var n := int(counters.get("custom_seq", 0.0)) + 1
	counters["custom_seq"] = float(n)
	var id := "custom_%d" % n
	while items.has(id):
		n += 1
		id = "custom_%d" % n
		counters["custom_seq"] = float(n)
	custom_items[id] = def
	items[id] = def
	return id


func grant_custom_item(def: Dictionary, quality: int, how: String) -> String:
	var id := register_custom_item(def)
	var full := with_quality(id, quality)
	add_item(full, 1, false)
	message.emit(I18n.t("MADE FOR YOU: %s -- %s") % [item_name(full), str(def.get("desc", ""))])
	log_event("custom_item", {"id": full, "how": how, "type": def.get("type", "")})
	note_place("%s: %s" % [how, item_name(full)])
	save_game()
	return full


func tailor_cost(gid: String) -> int:
	return int(guild_defs.get(gid, {}).get("tailor_cost", 0))


func tailor_block(gid: String) -> String:
	if not in_guild(gid):
		return I18n.t("Members only.")
	var c := tailor_cost(gid)
	if c <= 0:
		return I18n.t("They don't do that here.")
	if guild_rank(gid) < int(guild_defs.get(gid, {}).get("tailor_rank", 1)):
		return I18n.t("They only make pieces for members of some standing.")
	if contribution(gid) < float(c):
		return I18n.t("Needs %d %s (you have %d).") % [c, contribution_name(gid), int(contribution(gid))]
	return ""


func wishes_left(settlement: String) -> int:
	return maxi(0, WISHES_PER_SETTLEMENT - int(wishes.get(settlement, 0)))


func wish_fee() -> int:
	return 20 + 15 * reach_depth()


func use_wish(settlement: String) -> bool:
	if wishes_left(settlement) <= 0 or gold < wish_fee():
		return false
	gold -= wish_fee()
	wishes[settlement] = int(wishes.get(settlement, 0)) + 1
	stats_changed.emit()
	return true


# ======================================================================
# moments: anything you can describe (HUD "T", scripts/Moment.gd). The
# model judges it; THIS decides how much the world can give or take, by
# how deep you are -- and the world always answers, with a cost when it
# gives and a lesson when it takes (Robert: "it needs reciprocating").
# ======================================================================

func moment_wait() -> float:
	if not flags.has("moment:last"):
		return 0.0
	return maxf(0.0, MOMENT_COOLDOWN - (Time.get_unix_time_from_system() - float(flags["moment:last"])))


func moment_items() -> Array:
	## What the world may hand you in a moment at this depth (no gear, no
	## treasures, nothing made for someone).
	var d := maxi(depth, 1)
	var out := []
	for id in items:
		var it: Dictionary = items[id]
		var t := str(it.get("type", ""))
		if not (t in ["material", "consumable"]) or bool(it.get("special", false)) or bool(it.get("custom", false)):
			continue
		if int(it.get("value", 0)) <= 12 + 5 * d:
			out.append(str(id))
	out.sort()
	return out


func _moment_gain_caps() -> Dictionary:
	var d := maxi(depth, 1)
	return {"gold": 10 + 8 * d, "gold_loss": maxi(5, int(gold * 0.3)), "hp": int(max_hp() * 0.3), "hp_loss": int(max_hp() * 0.35),
		"qi": qi_to_next() * 0.12, "xp": 30.0 + 5.0 * d, "bond": 6.0, "aff": 3.0}


func apply_moment(r: Dictionary, names: Array, action: String) -> Dictionary:
	## r: {"outcome": "success"|"partial"|"fail", "narration", "effects": {...},
	## "journal"}. Returns {"lines": [what changed], "outcome"}.
	flags["moment:last"] = Time.get_unix_time_from_system()
	var cap := _moment_gain_caps()
	var e: Dictionary = r.get("effects", {}) if r.get("effects", {}) is Dictionary else {}
	var outcome := str(r.get("outcome", "partial")).to_lower()
	if not (outcome in ["success", "partial", "fail"]):
		outcome = "partial"
	var gain_mult: float = {"success": 1.0, "partial": 0.5, "fail": 0.0}[outcome]
	# the same trick twice in a row wears thin
	var key := _moment_key(action)
	var repeats := 0
	for m in moments:
		if m is Dictionary and str(m.get("key", "")) == key and key != "":
			repeats += 1
	if repeats >= 2:
		gain_mult *= 0.5
	var lines := []
	var gained := false
	var cost := false
	# gold
	var g := int(_num(e.get("gold", 0)))
	if g > 0:
		g = int(mini(g, int(cap["gold"])) * gain_mult)
		if g > 0:
			add_item("gold", g, false)
			lines.append(I18n.t("+%d gold") % g)
			gained = true
	elif g < 0:
		g = mini(-g, mini(int(cap["gold_loss"]), gold))
		if g > 0:
			gold -= g
			lines.append(I18n.t("-%d gold") % g)
			cost = true
	# health
	var h := int(_num(e.get("hp", 0)))
	if h > 0:
		h = int(mini(h, int(cap["hp"])) * gain_mult)
		if h > 0 and hp < max_hp():
			heal(h)
			lines.append("+%d HP" % h)
			gained = true
	elif h < 0:
		h = mini(-h, int(cap["hp_loss"]))
		h = mini(h, hp - 1)            # a moment never kills you outright
		if h > 0:
			hp -= h
			lines.append("-%d HP" % h)
			cost = true
	# qi
	var q := _num(e.get("qi", 0))
	if q > 0.0:
		q = minf(q, float(cap["qi"])) * gain_mult
		if q >= 1.0:
			add_qi(q)
			lines.append("+%d qi" % int(q))
			gained = true
	# what you give up (only what you actually carry)
	var used: Dictionary = e.get("consume", {}) if e.get("consume", {}) is Dictionary else {}
	var n_used := 0
	for id in used:
		if n_used >= 3:
			break
		var n := mini(clampi(int(_num(used[id])), 0, 3), count(str(id)))
		if n > 0 and not is_treasure(str(id)) and not is_equipped(str(id)):
			remove_item(str(id), n)
			lines.append("-%d %s" % [n, item_name(str(id))])
			cost = true
			n_used += 1
	# what you find
	var allowed := moment_items()
	var got: Dictionary = e.get("items", {}) if e.get("items", {}) is Dictionary else {}
	var kinds := 0
	for id in got:
		if kinds >= 3 or gain_mult <= 0.0:
			break
		if not (str(id) in allowed):
			continue
		var n2 := int(round(clampi(int(_num(got[id])), 0, 3) * maxf(gain_mult, 0.5)))
		if n2 > 0:
			add_item(str(id), n2, false)
			lines.append("+%d %s" % [n2, item_name(str(id))])
			gained = true
			kinds += 1
	# what you learn -- even (especially) from failing
	var xp: Dictionary = e.get("skill_xp", {}) if e.get("skill_xp", {}) is Dictionary else {}
	var learned := 0
	for sid in xp:
		if learned >= 2 or not skill_defs.has(str(sid)):
			continue
		var amt := clampf(_num(xp[sid]), 0.0, float(cap["xp"]))
		if outcome == "fail":
			amt = maxf(amt * 0.6, 5.0)
		if amt >= 1.0:
			add_skill_xp(str(sid), amt, "a moment")
			lines.append("+%d %s xp" % [int(amt), skill_name(str(sid))])
			learned += 1
	# who saw it (and remembers)
	var bd: Dictionary = e.get("bond", {}) if e.get("bond", {}) is Dictionary else {}
	for who in bd:
		if str(who) in names:
			var dv := clampf(_num(bd[who]), -float(cap["bond"]), float(cap["bond"]))
			if dv != 0.0:
				adjust_bond(str(who), dv, "You " + action.left(100))
				lines.append("%s %s" % [str(who), I18n.t("warms to you") if dv > 0.0 else "cools toward you"])
	var af: Dictionary = e.get("affinity", {}) if e.get("affinity", {}) is Dictionary else {}
	for el in af:
		if str(el) in ELEMENTS:
			var av := clampf(_num(af[el]), -float(cap["aff"]), float(cap["aff"]))
			if av != 0.0:
				attune(str(el), av)
				lines.append("%s %s" % [str(el).capitalize(), "stirs" if av > 0.0 else "ebbs"])
	# reciprocity: nothing comes free, nothing is for nothing
	if outcome != "success" and gained and not cost:
		var toll := maxi(1, int(max_hp() * 0.05))
		toll = mini(toll, hp - 1)
		if toll > 0:
			hp -= toll
			lines.append(I18n.t("-%d HP (it took something out of you)") % toll)
			cost = true
	if outcome == "fail" and not cost:
		var toll2 := mini(maxi(1, int(max_hp() * 0.08)), hp - 1)
		if toll2 > 0:
			hp -= toll2
			lines.append("-%d HP" % toll2)
	if learned == 0:
		var lesson := 5.0 + 2.0 * float(maxi(depth, 0))
		add_skill_xp("survival", lesson, "a moment")
		lines.append(I18n.t("+%d Survival xp") % int(lesson))
	var jt := str(r.get("journal", "")).strip_edges().left(140)
	if jt != "":
		note_place(jt)
	moments.append({"key": key, "what": action.left(120), "outcome": outcome, "t": int(playtime), "level": current_level})
	moments = moments.slice(maxi(0, moments.size() - 12))
	log_event("moment", {"outcome": outcome, "key": key})
	stats_changed.emit()
	return {"lines": lines, "outcome": outcome}


func _moment_key(action: String) -> String:
	## The gist of an action (its first two real words) -- to notice repeats.
	var words := []
	for w in action.to_lower().replace(",", " ").replace(".", " ").split(" ", false):
		var s := str(w)
		if s.length() > 3 and not (s in ["the", "with", "that", "this", "into", "from", "some", "them", "they", "their", "then", "there", "try", "tries", "trying"]):
			words.append(s)
		if words.size() >= 2:
			break
	return " ".join(words)


func _num(v) -> float:
	## A number from whatever the model wrote (5, 5.0, "5", "+5"); 0 if not one.
	if v is int or v is float:
		return float(v)
	if v is String:
		var t: String = v.strip_edges().trim_prefix("+")
		if t.is_valid_float():
			return t.to_float()
	return 0.0


# ---- looks -----------------------------------------------------------------------

const HEAD_SCALE := 0.72   # Robert, 2026-10-02: the human model's head was "obnoxiously large"


func shrink_head(model: Node, s: float = HEAD_SCALE) -> void:
	## Scales the "head" bone of a Kenney character (it pivots at the neck,
	## so the head stays on the shoulders). No animation tracks the head's
	## scale, so set once it holds through every animation.
	if model == null:
		return
	var sk: Skeleton3D = model if model is Skeleton3D else null
	if sk == null:
		for n in model.find_children("*", "Skeleton3D", true, false):
			sk = n
			break
	if sk == null:
		return
	var i := sk.find_bone("head")
	if i >= 0:
		sk.set_bone_pose_scale(i, Vector3.ONE * s)


# ---- the hour (town life): the village keeps your own clock -------------------------

var hour_override := -1.0    # tools/tests: pretend it's this hour (0-24)
var life_in_tests := false    # tools/tests: let villagers wander on the headless engine too


func hour() -> float:
	if hour_override >= 0.0:
		return fmod(hour_override, 24.0)
	var t := Time.get_datetime_dict_from_system()
	return float(t.get("hour", 12)) + float(t.get("minute", 0)) / 60.0


func daylight() -> float:
	## 0 at night, 1 in full day; dawn 5-7, dusk 18-21.
	var h := hour()
	if h < 5.0 or h >= 21.0:
		return 0.0
	if h < 7.0:
		return (h - 5.0) / 2.0
	if h < 18.0:
		return 1.0
	return 1.0 - (h - 18.0) / 3.0


# ======================================================================
# downtime (Robert, 2026-10-02: "focus on afk and downtime portions of the
# game, that way the user always feels like they are accomplishing
# something"). Five things keep moving when you're not fighting:
#   * what you do while you're away (away_task: meditate, train a skill,
#     gather, or work through a crafting queue) -- reported when you're back
#   * expeditions: your companion or familiar off on their own for a few
#     hours, home with materials, coin and a story
#   * your home in Eliet: a garden that grows in real time, a workbench that
#     works through a queue, a stash, a bed that leaves you well rested
#   * daily bounties (new every day, finished the moment you do them)
#   * achievements: long goals, each one a little permanent boost
# ======================================================================

const AWAY_CAP_HOURS := 12.0


func away_cap_hours() -> float:
	return 14.0 * 24.0 if tester_endless() else AWAY_CAP_HOURS


func tester_endless() -> bool:
	var t = sys("tester")
	return t != null and t.endless()


func tester_unlocked() -> bool:
	## the test kit's open locks (never in the online world)
	var t = sys("tester")
	return t != null and t.unlocked()

const AWAY_QI_FRAC := 0.04          # of a level, an hour, just for being a cultivator
const ACHIEVEMENT_BONUS := 0.005     # +0.5% qi and skill growth for each achievement
const GROW_HOURS := 2.0
const PLOT_UPGRADES := [[3, 0], [6, 250], [9, 900]]
const QUEUE_SECONDS := 600.0
const RESTED_SECONDS := 1800.0
const RESTED_MULT := 1.1
const PLANTABLE := ["spirit_herb", "ember_root", "iron_thistle", "moonpetal", "verdant_heart", "glowcap_spore"]
const ANECDOTES := [
	"{who} found a camp someone had left in a hurry, and ate their dinner for them.",
	"{who} got lost for an hour, then found the way by following a draught of warm air.",
	"{who} hid from something big. They won't say what. They're fine.",
	"{who} met a hermit who asked after you by name. Odd.",
	"{who} fought three of them at once, and only lost a sleeve.",
	"{who} found an old shrine and left a coin for you as well.",
	"{who} sat a long time by an underground river, and came back calmer than they left.",
	"{who} is very pleased with themselves and will tell you about it at length.",
]

var away_task := {}            # {"kind": "meditate"|"train"|"gather"|"craft", "skill", "recipe", "count"}
var away_report := []          # what happened last time you were away (shown when you're back)
var expedition := {}           # who's out exploring: {"who", "kind", "floor", "place", "depth", "start", "end"}
var home := {}                 # {"plots", "garden": [...], "stash": {}, "queue": {}, "rested_until", "have": true}
var bounties := {}             # {"day", "list": [...], "streak", "last_day"}
var achievements := {}         # id -> unix time it was earned
var achievement_defs := []
var _downtime_t := 0.0
var downtime_live := true       # tools/playtest: off, so bounties and achievements don't fire mid-test


func _now() -> float:
	return Time.get_unix_time_from_system()


func _downtime_tick(delta: float) -> void:
	_downtime_t += delta
	if _downtime_t < 2.0:
		return
	_downtime_t = 0.0
	check_expedition()
	process_queue()
	check_bounties()
	check_achievements()
	check_collections()


# ---- what you do while you're away ---------------------------------------------------

func away_task_text(t: Dictionary = {}) -> String:
	var a: Dictionary = t if not t.is_empty() else away_task
	match str(a.get("kind", "")):
		"meditate":
			return I18n.t("meditate (twice the qi)")
		"train":
			return I18n.t("train %s") % skill_name(str(a.get("skill", "")))
		"gather":
			return I18n.t("go out %s") % {"mining": "mining", "herbalism": I18n.t("picking herbs"), "fishing": "fishing", "hunting": "hunting"}.get(str(a.get("skill", "")), "gathering")
		"craft":
			return I18n.t("work through %d %s at the bench") % [int(a.get("count", 0)), item_name(str(a.get("recipe", "")))]
	return I18n.t("rest (your nanites still refine a little qi)")


func set_away_task(t: Dictionary) -> String:
	away_task = t.duplicate(true)
	save_game()
	return I18n.t("While you're away, you'll %s.") % away_task_text()


func _recipe_for(makes: String) -> Dictionary:
	for r in recipes:
		if str(r.get("makes", "")) == makes:
			return r
	return {}


func craftable_now() -> Array:
	## recipes you have everything for right now (for the away queue)
	var out := []
	for r in recipes:
		if can_craft(r):
			out.append(r)
	return out


func _gather_haul(sk: String, n: int, d: int, rng: RandomNumberGenerator) -> Dictionary:
	var got := {}
	for i in n:
		var id := ""
		match sk:
			"mining":
				var r := rng.randf()
				id = "rough_jade" if r < 0.08 else ("gold_nugget" if r < 0.16 else ("silver_ore" if d >= 4 and r < 0.5 else "iron_ore"))
			"herbalism":
				var pool := ["spirit_herb", "spirit_herb"]
				if d >= 2:
					pool += ["ember_root", "iron_thistle"]
				if d >= 3:
					pool.append("moonpetal")
				id = str(pool[rng.randi() % pool.size()])
			"fishing":
				id = "glowfin_eel" if d >= 3 and rng.randf() < 0.3 else "cave_carp"
			_:
				id = "beast_hide" if rng.randf() < 0.4 else "raw_meat"
		if has_item_def(id):
			got[id] = int(got.get(id, 0)) + 1
	return got


func resolve_away(hours: float, was_meditating: bool, rng_seed: int = -1) -> Array:
	## Everything that happened while you were gone, applied, as lines to read.
	var lines := []
	hours = clampf(hours, 0.0, away_cap_hours())
	if hours < 0.05:
		return lines
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_now()) if rng_seed < 0 else rng_seed
	var kind := str(away_task.get("kind", ""))
	if was_meditating and kind == "":
		kind = "meditate"
	var d := reach_depth()
	var qi_mult := AFK_SHRINE_MULT if kind == "meditate" else 1.0
	var q := hours * maxf(AFK_QI_PER_HOUR, qi_to_next() * AWAY_QI_FRAC) * qi_mult
	lines.append(I18n.t("Away %.1f hours (up to %d count).") % [hours, int(away_cap_hours())])
	var step0 := step_index()
	add_qi(q)
	lines.append(I18n.t("Your nanites refined %d qi%s.") % [int(q), I18n.t(" -- you sat in meditation the whole time") if kind == "meditate" else ""])
	if step_index() > step0:
		lines.append(I18n.t("You rose to %s.") % cultivation_label())
	var unsettled := 0.0
	for aid in arts:
		unsettled += float(arts[aid].get("u", 0.0))
	if unsettled > 0.0:
		settle_all(1.0)
		lines.append(I18n.t("Your practice settled while you rested."))
	match kind:
		"train":
			var sk := str(away_task.get("skill", "unarmed"))
			var lv0 := skill_level(sk)
			var xp := hours * (10.0 * (lv0 + 1) + 15.0)
			add_skill_xp(sk, xp, "training while away")
			lines.append(I18n.t("You trained %s: +%d xp%s.") % [skill_name(sk), int(xp),
				(" -- now level %d" % skill_level(sk)) if skill_level(sk) > lv0 else ""])
		"gather":
			var sk2 := str(away_task.get("skill", "herbalism"))
			var n := int(hours * (2.0 + skill_level(sk2) / 3.0))
			var haul := _gather_haul(sk2, n, d, rng)
			var parts := []
			for id in haul:
				add_item(str(id), int(haul[id]), false)
				parts.append("%d %s" % [int(haul[id]), item_name(str(id))])
			add_skill_xp(sk2, hours * 12.0, "gathering while away")
			lines.append(I18n.t("You went out %s and brought back %s.") % [away_task_text().trim_prefix(I18n.t("go out ")), ", ".join(parts) if parts.size() > 0 else "very little"])
		"craft":
			var r := _recipe_for(str(away_task.get("recipe", "")))
			var want := int(away_task.get("count", 0))
			if r.is_empty() or want <= 0:
				lines.append(I18n.t("You meant to craft, but never settled on what."))
			else:
				var per_hour := 2.0 + skill_level(str(r.get("skill", "smithing"))) / 5.0
				var tries := mini(want, int(hours * per_hour))
				var made := 0
				var failed := 0
				for i in tries:
					_pull_for(r)
					if not can_craft(r):
						break
					var res := craft_attempt(r, "balanced", rng.randf(), rng.randf())
					if bool(res.get("success", false)):
						made += 1
					else:
						failed += 1
				away_task["count"] = want - made - failed
				lines.append(I18n.t("At the bench: %d %s made, %d spoiled%s.") % [made, item_name(str(r["makes"])), failed,
					"" if made + failed >= want else " (you ran out of time or materials)"])
				if int(away_task["count"]) <= 0:
					away_task = {}
	lines.append_array(home_away_lines(hours))          # round 32: a compound looks after yours
	return lines


# ---- expeditions --------------------------------------------------------------------

func expedition_floors() -> Array:
	## Dungeon floors you've been to, deepest first (up to three): somewhere
	## someone could go without you.
	var out := []
	for pid in journal.get("places", {}):
		var s := str(pid)
		if s.begins_with("floor") and s.substr(5).is_valid_int():
			var def := load_level_def(s)
			if str(def.get("theme", "dungeon")) == "dungeon":
				out.append(s)
	out.sort_custom(func(a, b): return int(a.substr(5)) > int(b.substr(5)))
	return out.slice(0, 3)


func can_send(kind: String) -> String:
	## "" when you can, else why not.
	if not expedition.is_empty():
		return I18n.t("%s is already out on an expedition.") % str(expedition.get("who", I18n.t("Someone")))
	if kind == "companion" and companion.is_empty():
		return I18n.t("Nobody is travelling with you.")
	if kind == "companion" and companion.has("search"):
		return I18n.t("%s is out searching.") % str(companion.get("name", ""))
	if kind == "familiar" and familiar.is_empty():
		return I18n.t("You have no familiar.")
	if expedition_floors().is_empty():
		return I18n.t("There's nowhere you know well enough to send them yet.")
	return ""


func start_expedition(kind: String, floor_id: String, hours: float) -> bool:
	if can_send(kind) != "":
		return false
	var who := str(companion.get("name", "")) if kind == "companion" else str(familiar.get("name", ""))
	var def := load_level_def(floor_id)
	expedition = {"who": who, "kind": kind, "floor": floor_id, "place": str(def.get("name", floor_id)),
		"depth": int(def.get("depth", 1)), "start": _now(), "end": _now() + hours * 3600.0, "hours": hours}
	if kind == "companion":
		companion["away"] = true
		companion_changed.emit()
	else:
		familiar["away"] = true
		familiar_changed.emit()
	message.emit(I18n.t("EXPEDITION: %s sets off for %s. Back in %s.") % [who, expedition["place"], _dur(hours * 3600.0)])
	log_event("expedition_start", {"who": who, "floor": floor_id, "hours": hours})
	save_game()
	return true


func expedition_left() -> float:
	return maxf(0.0, float(expedition.get("end", 0.0)) - _now()) if not expedition.is_empty() else 0.0


func _dur(s: float) -> String:
	var m := int(ceil(s / 60.0))
	return "%dh %02dm" % [m / 60, m % 60] if m >= 60 else "%dm" % m


func check_expedition(force_roll: float = -1.0) -> Array:
	## Home yet? Then they bring back what they found.
	if expedition.is_empty() or expedition_left() > 0.0:
		return []
	var e := expedition
	expedition = {}
	var hours := float(e.get("hours", 1.0))
	var d := maxi(int(e.get("depth", 1)), 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(e.get("start", 0)) if force_roll < 0.0 else int(force_roll * 100000)
	var lines := []
	var gold_n := int(hours * (4 + 3 * d))
	add_item("gold", gold_n, false)
	var finds := {}
	var pool := []
	for eid in enemies:
		var st: Dictionary = enemies[eid]
		if int(st.get("floor", -1)) == d and not bool(st.get("boss", false)) and not bool(st.get("passive", false)):
			pool.append(st.get("loot", {}))
	for i in int(hours * 2.0):
		if pool.is_empty():
			break
		var loot: Dictionary = pool[rng.randi() % pool.size()]
		for id in loot:
			if str(id) == "gold" or str(id).begins_with("random_"):
				continue
			var r = loot[id]
			var n := rng.randi_range(int(r[0]), int(r[1])) if r is Array and r.size() >= 2 else int(r)
			if n > 0:
				finds[str(id)] = int(finds.get(str(id), 0)) + n
	var parts := ["%d gold" % gold_n]
	for id in finds:
		add_item(str(id), int(finds[id]), false)
		parts.append("%d %s" % [int(finds[id]), item_name(str(id))])
	if rng.randf() < 0.08 * hours:
		var g := drop_gear(d, 0)
		if g != "":
			parts.append(item_name(g))
	var who := str(e.get("who", "They"))
	if str(e.get("kind", "")) == "companion":
		companion.erase("away")
		warm_bond(who, 1.5 * hours)
		companion_changed.emit()
	else:
		familiar.erase("away")
		grow_bond(2.0 * hours)
		familiar_changed.emit()
	counters["expeditions"] = float(counters.get("expeditions", 0.0)) + 1.0
	var story := str(ANECDOTES[rng.randi() % ANECDOTES.size()]).replace("{who}", who)
	lines.append(I18n.t("%s is back from %s with %s.") % [who, str(e.get("place", I18n.t("the deep"))), ", ".join(parts)])
	lines.append(story)
	message.emit(I18n.t("EXPEDITION: ") + lines[0])
	note_place(I18n.t("%s's expedition to %s") % [who, str(e.get("place", ""))])
	log_event("expedition_done", {"who": who, "hours": hours})
	save_game()
	return lines


# ---- home: garden, workbench, stash, bed ---------------------------------------------

func has_home() -> bool:
	return bool(home.get("have", false))


func take_home() -> void:
	## Elder Mo's spare plot: yours from the first time you look at it.
	if has_home():
		return
	home = {"have": true, "plots": 3, "garden": [{}, {}, {}], "stash": {}, "queue": {}, "rested_until": 0.0, "stage": 0}
	note_place("A home in Eliet: a garden, a bench, a bed")
	log_event("home", {})


func plot_count() -> int:
	return int(home.get("plots", 3))


func plot_upgrade_cost() -> int:
	for row in PLOT_UPGRADES:
		if int(row[0]) > plot_count():
			return int(row[1])
	return 0


func upgrade_plots() -> bool:
	var c := plot_upgrade_cost()
	if c <= 0 or gold < c:
		return false
	gold -= c
	var n := plot_count()
	for row in PLOT_UPGRADES:
		if int(row[0]) > n:
			n = int(row[0])
			break
	home["plots"] = n
	var g: Array = home.get("garden", [])
	while g.size() < n:
		g.append({})
	home["garden"] = g
	stats_changed.emit()
	return true


func plantable() -> Array:
	var out := []
	for id in PLANTABLE:
		if count(id) > 0:
			out.append(id)
	return out


func grow_seconds() -> float:
	return GROW_HOURS * 3600.0 * maxf(0.5, 1.0 - 0.03 * skill_level("herbalism"))


func plant(i: int, seed_id: String) -> bool:
	var g: Array = home.get("garden", [])
	if i < 0 or i >= g.size() or not (g[i] as Dictionary).is_empty() or count(seed_id) <= 0 or not (seed_id in PLANTABLE):
		return false
	remove_item(seed_id, 1)
	g[i] = {"seed": seed_id, "planted": _now(), "ready": _now() + grow_seconds()}
	home["garden"] = g
	add_skill_xp("herbalism", 3.0, "planting")
	return true


func plot_ready(i: int) -> bool:
	var g: Array = home.get("garden", [])
	return i >= 0 and i < g.size() and not (g[i] as Dictionary).is_empty() and _now() >= float(g[i].get("ready", 0.0))


func ready_plots() -> int:
	var n := 0
	for i in home.get("garden", []).size():
		if plot_ready(i):
			n += 1
	return n


func harvest(i: int, roll: float = -1.0) -> String:
	if not plot_ready(i):
		return ""
	var g: Array = home["garden"]
	var sid := str(g[i].get("seed", "spirit_herb"))
	g[i] = {}
	var lvl := skill_level("herbalism")
	var n := 3 + lvl / 3 + (1 if (randf() if roll < 0.0 else roll) < 0.5 else 0)
	add_item(sid, n, false)
	var t := "%d %s" % [n, item_name(sid)]
	var idx := PLANTABLE.find(sid)
	if (randf() if roll < 0.0 else roll) < 0.15 and idx >= 0 and idx + 1 < PLANTABLE.size() and has_item_def(str(PLANTABLE[idx + 1])):
		add_item(str(PLANTABLE[idx + 1]), 1, false)
		t += I18n.t(", and a %s that seeded itself") % item_name(str(PLANTABLE[idx + 1]))
	add_skill_xp("herbalism", 15.0 + 2.0 * lvl, "your garden")
	counters["harvests"] = float(counters.get("harvests", 0.0)) + 1.0
	log_event("harvest", {"seed": sid, "n": n})
	return t


func stash_ref() -> Dictionary:
	## the chest's contents: the account-wide vault when the test kit is on, else this character's home chest
	var t = sys("tester")
	if t != null and t.vault_on():
		return t.vault_dict()
	return home.get("stash", {})


func stash_all_materials() -> int:
	var st: Dictionary = stash_ref()
	var moved := 0
	for id in inventory.keys():
		if str(items.get(id, {}).get("type", "")) == "material":
			var n := count(id)
			st[id] = int(st.get(id, 0)) + n
			remove_item(id, n)
			moved += n
	home["stash"] = st
	return moved


func take_from_stash(id: String) -> int:
	var st: Dictionary = stash_ref()
	var n := int(st.get(id, 0))
	if n <= 0:
		return 0
	var room := n
	if str(items.get(id, {}).get("type", "")) == "material":
		room = mini(n, maxi(0, pouch_cap() - count(id)))
	if room <= 0:
		return 0
	add_item(id, room, false)
	st[id] = n - room
	if int(st[id]) <= 0:
		st.erase(id)
	home["stash"] = st
	return room


func queue_craft(makes: String, n: int) -> String:
	## The bench works through it on its own, one piece every few minutes,
	## whether you're in the deep or away from the game.
	var r := _recipe_for(makes)
	if r.is_empty() or n <= 0:
		return I18n.t("Nothing to queue.")
	var q: Dictionary = home.get("queue", {})
	if int(q.get("left", 0)) > 0:
		return I18n.t("The bench is busy with %d %s.") % [int(q["left"]), item_name(str(q.get("recipe", "")))]
	n = mini(n, bench_can_make(r))
	if n <= 0:
		return I18n.t("You don't have the materials for %s, in your pouch or your stash.") % item_name(makes)
	home["queue"] = {"recipe": makes, "left": n, "next": _now() + queue_period(r)}
	return I18n.t("The bench will make %d %s, one every %s.") % [n, item_name(makes), _dur(queue_period(r))]


func bench_can_make(r: Dictionary) -> int:
	## How many of this the bench could make from your pouch AND your stash.
	if r.is_empty() or not skill_known(str(r.get("skill", "smithing"))):
		return 0
	var st: Dictionary = stash_ref()
	var n := 9999
	var g := int(r.get("gold", 0))
	if g > 0:
		n = gold / g
	for need in r.get("needs", {}):
		var per := maxi(1, int(r["needs"][need]))
		n = mini(n, (count(str(need)) + int(st.get(need, 0))) / per)
	return maxi(n, 0) if n < 9999 else 0


func _pull_for(r: Dictionary) -> void:
	## Short of something the bench needs? It's taken from the stash first.
	var st: Dictionary = stash_ref()
	if st.is_empty():
		return
	for need in r.get("needs", {}):
		var id := str(need)
		var short := int(r["needs"][need]) - count(id)
		if short > 0 and int(st.get(id, 0)) > 0:
			var take := mini(short, int(st[id]))
			inventory[id] = count(id) + take
			st[id] = int(st[id]) - take
			if int(st[id]) <= 0:
				st.erase(id)
	home["stash"] = st


func queue_period(r: Dictionary) -> float:
	return QUEUE_SECONDS * maxf(0.4, 1.0 - 0.03 * skill_level(str(r.get("skill", "smithing"))))


func process_queue() -> Array:
	var q: Dictionary = home.get("queue", {})
	if int(q.get("left", 0)) <= 0:
		return []
	var r := _recipe_for(str(q.get("recipe", "")))
	var out := []
	var guard := 0
	while int(q.get("left", 0)) > 0 and _now() >= float(q.get("next", 0.0)) and guard < 200:
		guard += 1
		_pull_for(r)
		if r.is_empty() or not can_craft(r):
			out.append(I18n.t("The bench stopped: no more materials for %s.") % item_name(str(q.get("recipe", ""))))
			q["left"] = 0
			break
		var res := craft_attempt(r, "balanced")
		q["left"] = int(q["left"]) - 1
		q["next"] = float(q["next"]) + queue_period(r)
		out.append(I18n.t("The bench: %s") % str(res.get("text", "")))
	home["queue"] = q if int(q.get("left", 0)) > 0 else {}
	if out.size() > 0:
		message.emit(str(out[out.size() - 1]))
		stats_changed.emit()
	return out


func stop_queue() -> void:
	home["queue"] = {}


func rest_at_home() -> void:
	hp = max_hp()
	settle_all(SLEEP_SETTLE_BONUS)       # a night in your own bed: all your practice settles, and a little more
	injury = {}                           # ...and injured meridians mend
	heat = 0.0
	home["rested_until"] = _now() + RESTED_SECONDS * home_rested_mult()      # (round 32: a cottage rests you longer)
	counters["slept_home"] = float(counters.get("slept_home", 0.0)) + 1.0
	companion_revive()                                                        # round 32: they sleep it off too
	message.emit("WELL RESTED: +10% qi and skill growth for half an hour.")
	log_event("rest_home", {})
	stats_changed.emit()


func rested() -> bool:
	return float(home.get("rested_until", 0.0)) > _now()


func growth_mult() -> float:
	## Everything that makes you learn faster: being well rested, and every
	## achievement you've earned.
	return (RESTED_MULT if rested() else 1.0) * (1.0 + ACHIEVEMENT_BONUS * achievements.size()) * balance_mult()


# ---- daily bounties ------------------------------------------------------------------

func today() -> String:
	var t := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(t["year"]), int(t["month"]), int(t["day"])]


func _total_kills() -> int:
	var n := 0
	for k in kills:
		n += int(kills[k])
	return n


func _total_crafted() -> int:
	var n := 0
	for c in counters:
		if str(c).begins_with("crafted:"):
			n += int(counters[c])
	return n


func bounties_today() -> Array:
	if str(bounties.get("day", "")) != today():
		_new_bounties()
	return bounties.get("list", [])


func _new_bounties() -> void:
	var d := reach_depth()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(today())
	var foes := []
	for eid in enemies:
		var st: Dictionary = enemies[eid]
		var f := int(st.get("floor", -1))
		if f >= maxi(1, d - 2) and f <= d and not bool(st.get("boss", false)) and not bool(st.get("passive", false)):
			foes.append(str(eid))
	foes.sort()
	var list := []
	if foes.size() > 0:
		var foe: String = foes[rng.randi() % foes.size()]
		list.append({"kind": "kill", "what": foe, "need": 6 + d / 2, "base": int(kills.get(foe, 0)),
			"text": I18n.t("Defeat %d %s") % [6 + d / 2, str(enemies[foe].get("name", foe))]})
	list.append({"kind": "gather", "need": 8 + d / 2, "base": int(counters.get("gathered", 0.0)), "text": I18n.t("Gather %d times") % (8 + d / 2)})
	list.append({"kind": "craft", "need": 3, "base": _total_crafted(), "text": I18n.t("Make 3 things")})
	for b in list:
		b["done"] = false
		b["reward_gold"] = 25 + 15 * d
	bounties["day"] = today()
	bounties["list"] = list


func bounty_progress(b: Dictionary) -> int:
	var now := 0
	match str(b.get("kind", "")):
		"kill":
			now = int(kills.get(str(b.get("what", "")), 0))
		"gather":
			now = int(counters.get("gathered", 0.0))
		"craft":
			now = _total_crafted()
	return clampi(now - int(b.get("base", 0)), 0, int(b.get("need", 1)))


func check_bounties() -> Array:
	var done := []
	for b in bounties_today():
		if bool(b.get("done", false)) or bounty_progress(b) < int(b.get("need", 1)):
			continue
		b["done"] = true
		var g := int(b.get("reward_gold", 30))
		add_item("gold", g, false)
		add_qi(qi_to_next() * 0.08)
		var gl := guilds.keys()
		gl.sort()
		for gid in gl:
			if gid != "academy":
				add_guild_rep(str(gid), 15.0)
				break
		counters["bounties"] = float(counters.get("bounties", 0.0)) + 1.0
		if str(bounties.get("last_day", "")) != today():
			var yesterday := Time.get_date_string_from_unix_time(int(_now()) - 86400 + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
			bounties["streak"] = int(bounties.get("streak", 0)) + 1 if str(bounties.get("last_day", "")) == yesterday else 1
			bounties["last_day"] = today()
		message.emit(I18n.t("BOUNTY DONE: %s -- %d gold, some qi%s.") % [str(b.get("text", "")), g, (I18n.t(" (day %d in a row)") % int(bounties["streak"])) if int(bounties.get("streak", 0)) > 1 else ""])
		log_event("bounty", {"kind": b.get("kind", "")})
		done.append(b)
	return done


# ---- achievements --------------------------------------------------------------------

func achievement_value(stat: String) -> float:
	match stat:
		"kills":
			return float(_total_kills())
		"bosses":
			return counters.get("bosses", 0.0)
		"depth":
			return float(reach_depth())
		"realm":
			return float(realm)
		"best_skill":
			var b := 0
			for sid in skills:
				b = maxi(b, skill_level(str(sid)))
			return float(b)
		"skills_at_5":
			var n := 0
			for sid in skills:
				if skill_level(str(sid)) >= 5:
					n += 1
			return float(n)
		"crafted":
			return float(_total_crafted())
		"items_known":
			return float(journal.get("items", {}).size())
		"techniques":
			return float(techniques.size())
		"close_friends":
			var c := 0
			for nm in bonds:
				if float(bonds[nm].get("warmth", 0.0)) >= COMPANION_WARMTH:
					c += 1
			return float(c)
		"academy":
			return 1.0 if bool(academy.get("enrolled", false)) else 0.0
		"bounty_streak":
			return float(bounties.get("streak", 0))
		"moments":
			return float(moments.size())
		"vignettes", "companions":
			var pre := "vignette:" if stat == "vignettes" else "travelled:"
			var k := 0
			for f in flags:
				if str(f).begins_with(pre):
					k += 1
			return float(k)
	return float(counters.get(stat, 0.0))


func check_achievements() -> Array:
	if achievement_defs.is_empty():
		var d = _load_json("res://data/achievements.json", {})
		achievement_defs = d.get("list", []) if d is Dictionary else []
	var earned := []
	for a in achievement_defs:
		var id := str(a.get("id", ""))
		if id == "" or achievements.has(id):
			continue
		if achievement_value(str(a.get("stat", ""))) >= float(a.get("need", 1)):
			achievements[id] = _now()
			earned.append(a)
			message.emit(I18n.t("ACHIEVEMENT: %s -- %s (+%.1f%% to all growth)") % [a.get("name", id), a.get("desc", ""), ACHIEVEMENT_BONUS * 100.0])
			jingle("achievement")
			log_event("achievement", {"id": id})
			if steam:
				steam.achieve(id.to_upper())     # the same achievement on Steam (round 30)
	if earned.size() > 0:
		stats_changed.emit()
	return earned


func next_achievements(n: int = 3) -> Array:
	## the closest ones you haven't got: [name, desc, have, need]
	if achievement_defs.is_empty():
		check_achievements()
	var rows := []
	for a in achievement_defs:
		if achievements.has(str(a.get("id", ""))):
			continue
		var have := achievement_value(str(a.get("stat", "")))
		var need := float(a.get("need", 1))
		rows.append([str(a.get("name", "")), str(a.get("desc", "")), have, need, have / maxf(need, 1.0)])
	rows.sort_custom(func(x, y): return float(x[4]) > float(y[4]))
	return rows.slice(0, n)


# ---- what to do next (always on screen) ------------------------------------------------

const PACE_ORDER := {
	"fighter": ["fs:weapon", "fs:path", "fs:floor", "fs:kill", "fs:talk", "fs:bag", "fs:meditate", "fs:journal"],
	"crafter": ["fs:talk", "fs:bag", "fs:craft", "fs:weapon", "fs:floor", "fs:kill", "fs:path", "fs:meditate", "fs:journal"],
	"wanderer": ["fs:talk", "fs:weapon", "fs:floor", "fs:waystone", "fs:kill", "fs:path", "fs:meditate", "fs:bag", "fs:journal"],
	"scholar": ["fs:talk", "fs:bag", "fs:lesson", "fs:meditate", "fs:journal", "fs:path", "fs:weapon", "fs:floor", "fs:kill"],
}
const PACE_STEP_TEXT := {
	"fs:craft": "Make something at a bench: ask Smith Hale or Apothecary Lin what you can craft (menu > Craft)",
	"fs:waystone": "Find a waystone and wake it -- waystones are how you travel",
	"fs:lesson": "Learn from a teacher: ask a master about their art (E)",
}


func pace() -> String:
	## round 142b: what you said you wanted from your first days ("" for an older save or if you skipped it)
	for p in ["fighter", "crafter", "wanderer", "scholar"]:
		if has_flag("pace:" + p):
			return p
	return ""


func first_steps() -> Array:
	## round 31: the first hour, one thing at a time (gone once they're done)
	if playtime > 5400.0 or has_flag("fs:done"):
		return []
	var steps := [
		["fs:talk", "Walk to the fountain and talk to Elder Mo (E)"],
		["fs:bag", "Open your bag (I)"],
		["fs:weapon", "Get a weapon: Smith Hale sells one, or take a goblin's"],
		["fs:floor", "Take the stairs down into the Goblin Warrens"],
		["fs:kill", "Win a fight: strike a goblin (J, or ATK on a phone)"],
		["fs:path", "Choose a Path (menu > Path) -- who you are in a fight"],
		["fs:journal", "Read your journal (N) -- goals, skills, your blood"],
		["fs:meditate", "Sit and meditate (M) at the shrine to gather qi"],
	]
	if weapon != "":
		set_flag("fs:weapon")
	if reach_depth() >= 1 and journal.get("places", {}).has("floor1"):
		set_flag("fs:floor")
	if has_flag("op:blood"):
		set_flag("fs:kill")                              # round 121: first blood
	var pths = sys("paths")
	if pths != null and pths.primary != "":
		set_flag("fs:path")                              # round 121: a road chosen
	var text := {}
	for st in steps:
		text[str(st[0])] = str(st[1])
	var order: Array = PACE_ORDER.get(pace(), [])          # round 142b: the same steps, in the order your pace suggests
	if order.is_empty():
		for st in steps:
			order.append(str(st[0]))
	var out := []
	for fid in order:
		if not has_flag(str(fid)):
			var where_txt := ""
			var pu2 = sys("pull")
			if pu2 != null and current_level == "village":
				where_txt = pu2.where("elder" if str(fid) == "fs:talk" else ("shrine" if str(fid) == "fs:meditate" else ""))      # round 152: which way
			out.append(I18n.t("First steps: ") + I18n.t(str(text.get(fid, PACE_STEP_TEXT.get(fid, "")))) + where_txt)
			break
	if out.is_empty():
		set_flag("fs:done")
	return out


func almost() -> String:
	## round 61: the next thing you're nearly at -- the pull of "just a bit more"
	var need := qi_to_next()
	if need > 0.0 and qi / need >= 0.85 and qi < need:
		return I18n.t("Almost: your next step (%d%%)") % int(qi / need * 100.0)
	var Q = sys("quests")
	if Q and Q.tracked != "" and Q.active.has(Q.tracked):
		var pt: String = Q.progress_text(Q.tracked)
		var m := RegEx.create_from_string("\\((\\d+)/(\\d+)\\)").search(pt)
		if m and int(m.get_string(2)) - int(m.get_string(1)) == 1:
			return I18n.t("Almost: one more for %s") % str(Q.qdef(Q.tracked).get("name", I18n.t("your quest")))
	for sid in skills:
		var lvl := skill_level(sid)
		var lo := 10.0 * lvl * lvl
		var hi := 10.0 * (lvl + 1) * (lvl + 1)
		var f := (float(skills[sid]) - lo) / maxf(hi - lo, 1.0)
		if lvl >= 1 and f >= 0.9:
			return I18n.t("Almost: %s %d (%d%%)") % [skill_name(sid), lvl + 1, int(f * 100.0)]
	var FR = sys("floorrun")
	if FR and not FR.run.is_empty() and str(FR.run.get("level", "")) == current_level and not bool(FR.run.get("cleared", false)):
		var ct := int(FR.run.get("chests_total", 0))
		if ct > 1 and ct - int(FR.run.get("chests", 0)) == 1:
			return I18n.t("Almost: one chest left on this floor")
		var ex := float(fog_frac.get(current_level, 0.0))
		if ex >= 0.85 and ex < 0.97:
			return I18n.t("Almost: this floor walked end to end (%d%%)") % int(ex * 100.0)
	return ""


func next_goals() -> Array:
	## Up to two short lines: what's waiting for you, and what's next.
	var out := []
	if has_flag("fs:done") and mq_line() != "":
		out.append(mq_line())                        # round 34: the road down, always first
	if sys("quests") and str(sys("quests").tracked_line()) != "":
		out.append(sys("quests").tracked_line())     # round 52: the side quest you're following
	if has_home() and ready_plots() > 0:
		out.append(I18n.t("Your garden is ready (%d)") % ready_plots())
	out.append_array(first_steps())
	if not expedition.is_empty():
		out.append(I18n.t("%s returns in %s") % [expedition.get("who", ""), _dur(expedition_left())])
	var q: Dictionary = home.get("queue", {})
	if int(q.get("left", 0)) > 0:
		out.append(I18n.t("Bench: %d %s to go") % [int(q["left"]), item_name(str(q.get("recipe", "")))])
	if at_threshold() and out.size() < 2:
		var miss := breakthrough_missing()
		out.append(I18n.t("Breakthrough: sit (M) and face your heart demon") if miss.is_empty() else I18n.t("Breakthrough needs ") + miss[0])
	if out.size() < 2 and has_flag("fs:floor"):
		# the Meridian Lattice: the point you're opening, or a nudge to pick one
		# (round 62: not in the first minutes -- one thing at a time)
		if lattice_focus != "" and not lattice.has(lattice_focus):
			out.append(I18n.t("Open %s (%d%%)") % [lattice_point(lattice_focus).get("name", lattice_focus), int(point_fraction(lattice_focus) * 100)])
		elif next_point("strike") != "" or next_point("guard") != "" or next_point("step") != "":
			out.append(I18n.t("Choose a point to open (K)"))
	if out.size() < 2:
		var dl: String = Hook.next_line()
		if dl != "":
			out.append(dl)
	if out.size() < 2:
		var best = null
		var bp := -1.0
		for b in bounties_today():
			if bool(b.get("done", false)):
				continue
			var p := float(bounty_progress(b)) / maxf(float(b.get("need", 1)), 1.0)
			if p > bp:
				bp = p
				best = b
		if best != null:
			out.append(I18n.t("Bounty: %s (%d/%d)") % [best["text"], bounty_progress(best), int(best["need"])])
	if out.size() < 2 and not trial_done_today() and reach_depth() >= 2:
		out.append(I18n.t("Today's trial is posted (Trial Board)"))
	if out.size() < 2:
		var cn := collection_nudge()
		if cn != "":
			out.append(cn)
	if out.size() < 2:
		if realm >= 1 and not bool(academy.get("enrolled", false)):
			var t: Dictionary = academy.get("trials", {})
			out.append(I18n.t("Academy exam: %d/3 trials") % [int(bool(t.get("strength", false))) + int(bool(t.get("knowledge", false))) + int(bool(t.get("craft", false)))])
		else:
			out.append(I18n.t("Next: reach Floor %d") % (reach_depth() + 1))
	return out.slice(0, 2)


# ======================================================================
# the Meridian Lattice and the ki arts (Robert, 2026-10-02: "the characters
# can develop everything over time with practice and meditation and through
# use ... maybe have them found in a skill tree" -- "actual fighting can
# increase ki with every kill but meditation should not be quick without
# aids or special skills"). The design: Claude Docs, "Cultivation x
# Nanites: the design".
#   * the skill tree IS your body: 36 acupoints, 6 rings (one per realm), 3
#     meridians (strike / guard / step). You open a point by meditating with
#     it as your focus; using an art also tugs at the next sealed point on
#     its meridian. Every open point is a small permanent bonus and grows
#     its element's affinity.
#   * an active art (Qi Burst, Wind Step ...) runs along a route of points:
#     it works once they're open. Using it earns PRACTICE, which stays
#     unsettled until you meditate or sleep -- then it becomes mastery.
#     Practiced -> Fluent -> Mastered -> Transcendent: more power, less cooldown.
#   * meditation is slow on its own; aids (a shrine, the Lotus Seat,
#     meditation techniques) multiply it. Kills are the main road to qi.
# ======================================================================

const MEDITATE_BASE_QI := 0.25          # a second, sitting anywhere, no aids
const SITTING_FATIGUE_SECONDS := 300.0  # after this long in one sitting, qi flows at half
const SHRINE_AID := 2.0
const KILL_QI_MULT := 1.5
const ART_STAGES := [["Practiced", 0.0], ["Fluent", 150.0], ["Mastered", 600.0], ["Transcendent", 2000.0]]
const ART_POWER := [0.85, 1.0, 1.12, 1.3]
const ART_COOLDOWN := [1.0, 1.0, 0.8, 0.7]
const SETTLE_PER_SECOND := 1.0          # practice settled per second of meditation (x aids)
const SLEEP_SETTLE_BONUS := 1.1
const TUG_SECONDS := 3.0                 # each real use of an art pushes its meridian's next point this far

var lattice := {}                # point id -> true (open)
var lattice_progress := {}       # point id -> seconds of meditation put into it
var lattice_focus := ""          # the point you're opening
var arts := {}                   # art id -> {"m": settled mastery, "u": unsettled practice}
var lattice_def := {}


func lattice_data() -> Dictionary:
	if lattice_def.is_empty():
		lattice_def = _load_json("res://data/lattice.json", {"points": [], "open_seconds": [150], "arts": {}})
	return lattice_def


func lattice_point(pid: String) -> Dictionary:
	for p in lattice_data().get("points", []):
		if str(p.get("id", "")) == pid:
			return p
	return {}


func point_ring_open(ring: int) -> bool:
	## ring 1 is open from the start; ring n waits for realm n-1
	return realm >= ring - 1


func point_cost(pid: String) -> float:
	var secs: Array = lattice_data().get("open_seconds", [150])
	var r := int(lattice_point(pid).get("ring", 1))
	return float(secs[clampi(r - 1, 0, secs.size() - 1)])


func can_focus(pid: String) -> String:
	## "" when this point can be your focus, else why not
	var p := lattice_point(pid)
	if p.is_empty():
		return I18n.t("There's no such point.")
	if lattice.has(pid):
		return I18n.t("%s is already open.") % p["name"]
	if not point_ring_open(int(p["ring"])):
		return I18n.t("%s lies in the %s ring -- sealed until %s.") % [p["name"], _ordinal(int(p["ring"])), REALMS[clampi(int(p["ring"]) - 1, 0, REALMS.size() - 1)]["name"]]
	return ""


func _ordinal(n: int) -> String:
	return ["first", "second", "third", "fourth", "fifth", "sixth"][clampi(n - 1, 0, 5)]


func set_focus(pid: String) -> String:
	var why := can_focus(pid)
	if why != "":
		return why
	lattice_focus = pid
	var p := lattice_point(pid)
	return I18n.t("Your focus: %s (%s), %d%% open. Meditate to open it.") % [p["name"], p["meaning"], int(point_fraction(pid) * 100)]


func point_fraction(pid: String) -> float:
	if lattice.has(pid):
		return 1.0
	return clampf(float(lattice_progress.get(pid, 0.0)) / maxf(point_cost(pid), 1.0), 0.0, 1.0)


func _push_point(pid: String, secs: float) -> bool:
	## true when this push opened it
	if pid == "" or lattice.has(pid) or can_focus(pid) != "":
		return false
	lattice_progress[pid] = float(lattice_progress.get(pid, 0.0)) + secs
	if float(lattice_progress[pid]) >= point_cost(pid):
		open_point(pid)
		return true
	return false


func open_point(pid: String) -> void:
	var p := lattice_point(pid)
	if p.is_empty() or lattice.has(pid):
		return
	lattice[pid] = true
	lattice_progress.erase(pid)
	if bridges.has(pid):
		bridges.erase(pid)
		add_item("nanite_bridge", 1, false)
		message.emit("The nanite bridge across %s comes free -- the point holds on its own now." % p["name"])
	if lattice_focus == pid:
		lattice_focus = next_point(str(p["meridian"]))
	var el := str(p.get("element", ""))
	if affinity.has(el):
		affinity[el] = float(affinity[el]) + 5.0
	counters["points_open"] = float(lattice.size())
	message.emit(I18n.t("MERIDIAN: %s opens -- %s. (%s %s)") % [p["name"], p["meaning"], el, _point_bonus_text(str(p["meridian"]), int(p["ring"]))])
	log_event("point_open", {"id": pid, "ring": p["ring"]})
	stats_changed.emit()


func _point_bonus_text(mer: String, ring: int) -> String:
	var b: Dictionary = lattice_data().get("bonus", {}).get(mer, {})
	for k in b:
		var v: float = float(b[k][1] if ring >= 6 else b[k][0])
		var pct := int(round(absf(v - 1.0) * 100))
		match str(k):
			"damage_mult":
				return I18n.t("+%d%% strike damage") % pct
			"damage_taken":
				return I18n.t("-%d%% damage taken") % pct
			"move_mult":
				return I18n.t("+%d%% speed") % pct
	return ""


func next_point(mer: String) -> String:
	## the next sealed point on this meridian you could open now ("" = none)
	for p in lattice_data().get("points", []):
		if str(p["meridian"]) == mer and not lattice.has(str(p["id"])) and point_ring_open(int(p["ring"])):
			return str(p["id"])
	return ""


func lattice_effect() -> Dictionary:
	var out := {}
	var bonus: Dictionary = lattice_data().get("bonus", {})
	for pid in lattice:
		var p := lattice_point(str(pid))
		if p.is_empty() or injury.has(str(p["meridian"])):
			continue
		var b: Dictionary = bonus.get(str(p["meridian"]), {})
		for k in b:
			var v: float = float(b[k][1] if int(p["ring"]) >= 6 else b[k][0])
			out[k] = float(out.get(k, 1.0)) * v
	return out


func ring_complete(ring: int) -> bool:
	for p in lattice_data().get("points", []):
		if int(p["ring"]) == ring and not lattice.has(str(p["id"])):
			return false
	return true


# ---- meditation ----------------------------------------------------------------

func meditation_aid(at_shrine: bool) -> float:
	## every aid multiplies: a shrine, the Lotus Seat (a shrine wherever you
	## sit), meditation techniques
	var m := tech_effect("meditate_mult", 1.0)
	if at_shrine:
		m *= SHRINE_AID
	if float(aid_buff.get("seconds", 0.0)) > 0.0:
		m *= float(aid_buff.get("mult", 1.0))
	m *= sit_aid
	# aids stack with diminishing returns past 3x: a pile of them is good, not absurd
	if m > AID_SOFT_CAP:
		m = AID_SOFT_CAP * sqrt(m / AID_SOFT_CAP)
	return m


func meditate_tick(secs: float, at_shrine: bool, sat_for: float) -> void:
	## one beat of sitting: qi (slow without aids, half after a long sitting),
	## practice settling into mastery, and your focus point opening
	var aid := meditation_aid(at_shrine)
	var fatigue := (0.75 if discoveries.has("still_mind") else 0.5) if sat_for > SITTING_FATIGUE_SECONDS and not tester_endless() else 1.0
	var moon := 1.3 if discoveries.has("moonwater_breath") and near_water and (hour() >= 20.0 or hour() < 5.0) else 1.0
	# round 40: where the sitting goes (the Mind page) -- qi still comes while you cleanse or research, slower
	var mind = sys("mind")
	var shares: Dictionary = mind.shares() if mind else {"cultivate": 1.0}
	add_qi(MEDITATE_BASE_QI * aid * fatigue * moon * secs * (mind.qi_factor(shares) if mind else 1.0))
	for sysn in systems.values():
		sysn.meditate(secs, shares, aid)
	if at_shrine and blood_awake() and blood_dominant() != "":
		add_purity(blood_dominant(), float(blood_data().get("gain", {}).get("shrine_hour", 0.6)) * secs / 3600.0, "")
	settle_practice(SETTLE_PER_SECOND * aid * secs)
	if lattice_focus != "" and float(shares.get("cultivate", 0.0)) > 0.0:
		var furnace := 3.0 if discoveries.has("furnace_sitting") and running_hot() else 1.0
		_push_point(lattice_focus, aid * secs * swarm_open_mult() * furnace * tech_effect("focus_mult", 1.0) * float(shares.get("cultivate", 0.0)))
	if float(aid_buff.get("seconds", 0.0)) > 0.0:
		aid_buff["seconds"] = float(aid_buff["seconds"]) - secs
		if float(aid_buff["seconds"]) <= 0.0:
			aid_buff = {}
			message.emit("The incense burns out.")


# ---- the arts ------------------------------------------------------------------

func art_route(aid: String) -> Array:
	return lattice_data().get("arts", {}).get(aid, {}).get("route", [])


func art_family(aid: String) -> String:
	return str(lattice_data().get("arts", {}).get(aid, {}).get("family", ""))


func art_blocked(aid: String) -> String:
	## "" when the art's route is open, else which point is sealed
	var ax = sys("arts")
	if ax != null:
		var gate: String = ax.gate(aid)           # round 122: a sect's or a road's art asks for more than an open route
		if gate != "":
			return gate
		if ax.nano_carries(aid):                  # ...and the new arts run on nanites alone, if ki has not opened the way
			return ""
	for pid in art_route(aid):
		if not lattice.has(str(pid)) and not bridges.has(str(pid)):
			var p := lattice_point(str(pid))
			return I18n.t("%s needs your %s point open (%s). Press K and make it your focus, then meditate.") % [
				str(technique_defs.get(aid, {}).get("name", aid)), p.get("name", pid), p.get("meaning", "")]
	return ""


func art_stage(aid: String) -> int:
	var m := float(arts.get(aid, {}).get("m", 0.0))
	var s := 0
	for i in ART_STAGES.size():
		if m >= float(ART_STAGES[i][1]):
			s = i
	return s


func art_stage_name(aid: String) -> String:
	return str(ART_STAGES[art_stage(aid)][0])


func _aff(aid: String, k: String) -> float:
	## round 122: what your road adds to this art's family
	var ax = sys("arts")
	return float(ax.affinity(art_family(aid)).get(k, 1.0)) if ax != null else 1.0


func _res_power(aid: String) -> float:
	## round 122: ki and nanites together run an art stronger
	var ax = sys("arts")
	return float(ax.resonance(aid).get("power", 1.0)) if ax != null else 1.0


func art_power(aid: String) -> float:
	var base := float(ART_POWER[art_stage(aid)]) if techniques.has(aid) else 1.0
	base *= _aff(aid, "power")
	if art_family(aid) == "guard":
		base *= _res_power(aid)            # (a guard is never "fired", so its resonance is felt here)
	return base


func art_cooldown_mult(aid: String) -> float:
	return float(ART_COOLDOWN[art_stage(aid)]) * _aff(aid, "cd")


func art_next_need(aid: String) -> float:
	var s := art_stage(aid)
	return float(ART_STAGES[s + 1][1]) if s + 1 < ART_STAGES.size() else -1.0


func practice(aid: String, landed: bool, gain_override: float = -1.0) -> void:
	## A real use of an art: practice (three times as much when it lands --
	## a hit, a blow dodged), held unsettled until you rest; and a tug at
	## the next sealed point on its meridian.
	if not techniques.has(aid):
		return
	var a: Dictionary = arts.get(aid, {"m": 0.0, "u": 0.0})
	var gain := 3.0 if landed else 1.0
	if gain_override >= 0.0:
		gain = gain_override
	var nxt := art_next_need(aid)
	var cap := maxf(40.0, (nxt - float(a["m"])) * 2.0) if nxt > 0.0 else 200.0
	a["u"] = minf(float(a["u"]) + gain, cap)
	arts[aid] = a
	var fam := art_family(aid)
	if fam != "":
		_push_point(next_point(fam), TUG_SECONDS * (2.0 if augment_on("meridian_lance") else 1.0))


func settle_practice(amount: float) -> void:
	## rest turns practice into mastery (meditation a little at a time)
	for aid in arts.keys():
		var a: Dictionary = arts[aid]
		var u := float(a.get("u", 0.0))
		if u <= 0.0:
			continue
		var s0 := art_stage(aid)
		var take := minf(u, amount)
		a["u"] = u - take
		a["m"] = float(a.get("m", 0.0)) + take
		arts[aid] = a
		if art_stage(aid) > s0:
			message.emit(I18n.t("MASTERY: your %s settles -- %s.") % [technique_defs.get(aid, {}).get("name", aid), art_stage_name(aid)])
			log_event("art_stage", {"art": aid, "stage": art_stage_name(aid)})
			if art_stage(aid) == 1 and can_branch(aid) == "":
				message.emit("Your %s is Fluent: it can take an element now (K)." % technique_defs.get(aid, {}).get("name", aid))
			check_glimpses()
			stats_changed.emit()


func settle_all(bonus: float = 1.0) -> void:
	## a night's sleep (or time away): everything unsettled settles
	for aid in arts.keys():
		var a: Dictionary = arts[aid]
		var u := float(a.get("u", 0.0))
		if u > 0.0:
			var s0 := art_stage(aid)
			a["m"] = float(a.get("m", 0.0)) + u * bonus
			a["u"] = 0.0
			arts[aid] = a
			if art_stage(aid) > s0:
				message.emit(I18n.t("MASTERY: your %s settles -- %s.") % [technique_defs.get(aid, {}).get("name", aid), art_stage_name(aid)])
	check_glimpses()


func _grandfather_arts() -> void:
	## Saves from before the lattice: arts you already had keep working --
	## their route points open, and you're Fluent in them.
	for aid in lattice_data().get("arts", {}):
		if techniques.has(aid):
			for pid in art_route(str(aid)):
				lattice[str(pid)] = true
			if not arts.has(aid):
				arts[aid] = {"m": float(ART_STAGES[1][1]), "u": 0.0}


# ======================================================================
# Round 20 -- nanite heat, the guard, glimpsed arts, branches, bridges,
# meditation aids, the training post. (Robert, 2026-10-02: "pick the best
# combination of options that will make this game great, playable and not
# too easy or too hard.")
#
#   HEAT: every art pushes your nanites hotter (data/lattice.json "heat").
#     Above 70% you RUN HOT: arts hit 15% harder. Past the cap: BACKLASH --
#     10% of your life, and that art's meridian is INJURED for 90 s (its
#     arts cost double heat, its point bonuses go quiet; meditating mends it
#     four times faster, a night in your own bed mends it at once). Heat
#     vents by itself -- fast out of a fight, faster sitting, and a perfect
#     parry vents a chunk. Water and earth affinity run cool, fire hot.
#     The cap grows with every complete ring of the lattice.
#   GUARD (hold right mouse / B): frontal blows let through half. Tap it
#     just as a blow lands -- the PARRY window -- and the blow is gone, the
#     attacker staggers, and heat vents. Blocking heats you a little; so a
#     turtle cooks, and a parrier stays cool.
#   GLIMPSES: new arts aren't bought. Each is GLIMPSED by doing the thing
#     it grows from (kills with your qi, steps through blows, parries...),
#     and most also need the art before it grown Fluent: a tree you climb by
#     playing. Progress shows on K.
#   BRANCHES: at Fluent, an art can take one of two elements (K) -- burn,
#     slow, mend, cut, stagger... chosen once.
#   NANITE BRIDGES: a great foe's first fall leaves one. Wired across a
#     sealed point (K), an art's route runs before the point opens -- at
#     1.5x heat. Limit: one, plus one per complete ring.
#   AIDS: meditation multipliers stack with diminishing returns past 3x
#     (so a pile of aids is good, not absurd); Calming Incense gives ten
#     minutes of 1.5x sitting.
#   TRAINING POST (home): drilling an art at it is real practice, 30
#     minutes a day -- a steady way forward that never replaces a fight.
# ======================================================================

const AID_SOFT_CAP := 3.0
const POST_DAILY_SECONDS := 1800.0
const ART_SOURCES := ["qi burst", "severing finger", "collapsing palm", "returning tide", "burning"]

var heat := 0.0
var injury := {}                 # meridian family -> seconds until it mends
var quick_slots: Array = ["", "", "", ""]   # round 158: the quick-art deck (R, F3, F4, F5): any known art, any family


func quick_art(i: int) -> String:
	## the art on quick key i (0-3). An empty first key falls back to the wired strike, so R always does something.
	var a := str(quick_slots[i]) if i >= 0 and i < quick_slots.size() else ""
	if a != "" and techniques.has(a) and art_family(a) != "guard":
		return a
	# out of the box every quick key already does something: R the strike, F3 the step, F4 the support, F5 the second support
	var fb: String = ["strike", "step", "support", "support2"][clampi(i, 0, 3)]
	var f: String = slot_art(fb)
	if f != "" and f in quick_slots:
		return ""                      # (it already has a key of its own)
	return f


func set_quick(i: int, aid: String) -> String:
	if i < 0 or i > 3:
		return ""
	if aid != "" and (not techniques.has(aid) or art_family(aid) == "guard" or art_family(aid) == ""):
		return I18n.t("That art can't be put on a quick key.")
	while quick_slots.size() < 4:
		quick_slots.append("")
	for j in range(4):
		if aid != "" and str(quick_slots[j]) == aid:
			quick_slots[j] = ""            # one art, one key
	quick_slots[i] = aid
	stats_changed.emit()
	if aid == "":
		return I18n.t("Quick key %d is empty.") % (i + 1)
	return I18n.t("%s is on quick key %d.") % [technique_defs.get(aid, {}).get("name", aid), i + 1]


func quick_key_label(i: int) -> String:
	## the key as the player has it set (Controls.gd), so the HUD and menus never name a key that has moved
	var C = preload("res://scripts/core/Controls.gd")
	var ks: Array = C.keys("quick%d" % (clampi(i, 0, 3) + 1))
	if ks.is_empty():
		return "Q%d" % (clampi(i, 0, 3) + 1)
	return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(int(ks[0]))) if DisplayServer.get_name() != "headless" else ["R", "F3", "F4", "F5"][clampi(i, 0, 3)]


var art_slots := {}              # family -> the art wired to its key (F strike / V step / guard)
var glimpses := {}               # art id -> how much of it you've glimpsed
var bridges := {}                # point id -> true (a nanite bridge across a sealed point)
var aid_buff := {}               # {"mult", "seconds"} -- incense burning
var post_log := {}               # {"day", "used"} -- the training post's daily drill


func _merge_lattice_defs() -> void:
	## The arts, aids and recipes this round adds live in data/lattice.json
	## (Claude's file) -- items/techniques/recipes are the forge's, written
	## on the box. Merged in only where the forge has nothing by that id.
	var L := lattice_data()
	for aid in L.get("arts", {}):
		var d = L["arts"][aid].get("def", null)
		if d is Dictionary and not technique_defs.has(aid):
			technique_defs[aid] = d
	for id in L.get("items", {}):
		if not items.has(id):
			items[id] = L["items"][id]
	for r in L.get("recipes", []):
		var have := false
		for q in recipes:
			if q is Dictionary and str(q.get("makes", "")) == str(r.get("makes", "")):
				have = true
		if not have:
			recipes.append(r)


func art_def(aid: String) -> Dictionary:
	return lattice_data().get("arts", {}).get(aid, {})


# ---- heat --------------------------------------------------------------------------

func heat_cfg(k: String, d: float = 0.0) -> float:
	return float(lattice_data().get("heat", {}).get(k, d))


func heat_cap() -> float:
	var n := 0
	for r in range(1, 7):
		if ring_complete(r):
			n += 1
	var c := heat_cfg("cap", 100.0) + heat_cfg("cap_per_ring", 15.0) * n + swarm_heat_cap()
	if harmony() == "qi_ahead":
		c *= float(nanite_data().get("harmony", {}).get("qi_cap", 0.85))
	return c


func heat_frac() -> float:
	return clampf(heat / maxf(heat_cap(), 1.0), 0.0, 1.5)


func running_hot() -> bool:
	return heat_frac() >= (0.6 if augment_on("kinetic_capacitor") else heat_cfg("hot_frac", 0.7))


func hot_power() -> float:
	return heat_cfg("hot_power", 1.15) + (0.05 if augment_on("kinetic_capacitor") else 0.0)


func _route_bridged(aid: String) -> bool:
	var ax = sys("arts")
	if ax != null and ax.nano_carries(aid):
		return true                              # round 122: nanites carrying a sealed route run it hot, like a bridge
	for pid in art_route(aid):
		if bridges.has(str(pid)) and not lattice.has(str(pid)):
			return true
	return false


func art_heat(aid: String) -> float:
	## what one use of this art adds to your heat
	var h := float(art_def(aid).get("heat", 0.0))
	h *= 1.0 - 0.25 * float(affinity.get("water", 0.0)) / 100.0 - 0.15 * float(affinity.get("earth", 0.0)) / 100.0 \
		+ 0.10 * float(affinity.get("fire", 0.0)) / 100.0
	if _route_bridged(aid):
		h *= 1.5
	if injury.has(art_family(aid)):
		h *= 2.0
	if harmony() == "swarm_ahead":
		h *= float(nanite_data().get("harmony", {}).get("swarm_heat", 1.2))
	var b := art_branch(aid)
	if b == "water":
		h *= 0.8 if art_family(aid) == "strike" else 0.6
	h *= _aff(aid, "heat")
	var ax = sys("arts")
	if ax != null and h > 0.0:
		h *= float(ax.resonance(aid).get("heat", 1.0))       # round 122: both roads together run cooler
	return maxf(h, 0.0)


func art_fire(aid: String) -> float:
	## Using an art: its heat goes on, and back comes its power -- with the
	## running-hot bonus if you were already hot, or a BACKLASH if this one
	## pushed you past the cap.
	var hot := running_hot()
	var h := art_heat(aid)
	heat += h
	# the swarm grows by being run: double when hot, triple on the edge (once you've found Edge Running)
	var g := h * _ng("heat", 0.25) * (_ng("hot_mult", 2.0) if hot else 1.0)
	if discoveries.has("edge_running") and heat_frac() >= 0.85:
		g *= 3.0
	integrate(g, "heat")
	if heat > heat_cap():
		_backlash(aid)
		return art_power(aid) * (_res_power(aid) if art_family(aid) != "guard" else 1.0)
	return art_power(aid) * (_res_power(aid) if art_family(aid) != "guard" else 1.0) * (hot_power() if hot else 1.0)


func _backlash(aid: String) -> void:
	var fam := art_family(aid)
	heat = heat_cap() * heat_cfg("backlash_reset", 0.6)
	var dmg := mini(int(round(max_hp() * heat_cfg("backlash_hp", 0.1))), maxi(hp - 1, 0))
	hp = max(hp - dmg, 1)
	if fam != "":
		injury[fam] = heat_cfg("injury_seconds", 90.0)
	bump("backlashes")
	integrate(_ng("backlash", 15.0), "backlash")     # the swarm learns from an overrun
	message.emit(I18n.t("BACKLASH: your nanites overrun your %s meridian (-%d HP). It's injured -- its arts run twice as hot until it mends. Sit to mend it faster.") % [fam, dmg])
	log_event("backlash", {"art": aid})
	stats_changed.emit()


func heat_tick(delta: float, calm: bool, guarding: bool, sitting: bool) -> void:
	## Heat vents on its own; injured meridians mend.
	var v := heat_cfg("vent_calm", 8.0) if calm else heat_cfg("vent_fight", 2.5)
	if sitting:
		v = heat_cfg("vent_meditate", 20.0)
		if discoveries.has("furnace_sitting") and running_hot():
			v = 2.0          # Furnace Sitting: hold the heat, and the point opens three times as fast
	if guarding:
		v += heat_cfg("vent_guard", 4.0)
	v *= 1.0 + 0.5 * float(affinity.get("water", 0.0)) / 100.0
	v *= swarm_vent_mult()
	var h0 := heat
	heat = maxf(heat - v * delta, 0.0)
	var vented := h0 - heat
	if vented > 0.0:
		if sitting and augment_on("qi_transducer"):
			add_qi(vented * 0.2)
		if not calm and not sitting and augment_on("marrow_forge"):
			_marrow_acc += vented
			while _marrow_acc >= 10.0:
				_marrow_acc -= 10.0
				heal(maxi(1, int(round(max_hp() * 0.01))))
	for fam in injury.keys():
		injury[fam] = float(injury[fam]) - delta * (4.0 if sitting else 1.0)
		if float(injury[fam]) <= 0.0:
			injury.erase(fam)
			message.emit("Your %s meridian has mended." % fam)
			stats_changed.emit()


func mend_injuries(secs: float) -> void:
	## medicine (a salve) and sleep
	for fam in injury.keys():
		injury[fam] = float(injury[fam]) - secs
		if float(injury[fam]) <= 0.0:
			injury.erase(fam)


# ---- the guard -----------------------------------------------------------------

func guard_cfg(k: String, d: float) -> float:
	return float(lattice_data().get("guard", {}).get(k, d))


func guard_art() -> String:
	var g := slot_art("guard")
	return g if g != "" and art_blocked(g) == "" else ""


func guard_take(front: bool = true) -> float:
	## the share of a blow that gets through your guard
	var t := guard_cfg("take", 0.5)
	var g := guard_art()
	if g != "":
		var gt := art_param(g, "guard_take", t)
		t = 1.0 - (1.0 - gt) * art_power(g)
		if art_branch(g) == "earth":
			t -= 0.1
	if augment_on("dermal_plating"):
		t -= 0.05
	t = clampf(t, 0.05, 1.0)
	if not front:
		t = lerpf(t, 1.0, 0.5)
	return t


func parry_window() -> float:
	var w := guard_cfg("parry_window", 0.2)
	var g := guard_art()
	if g != "":
		w += art_param(g, "parry_bonus", 0.0) * art_power(g)
	if augment_on("reflex_mesh"):
		w += 0.06
	w += minf(tech_effect("timing", 0.0), 0.15)          # round 41: Honing (the swarm and qi, grown together)
	return w


func block(amount: int, front: bool) -> Dictionary:
	## A blow on your guard: {"take": what gets through, "reflect": what
	## goes back}. Heats you a little; practises your guard art.
	var take := int(round(amount * guard_take(front)))
	var g := guard_art()
	var bh := heat_cfg("block_heat", 4.0)
	if g != "":
		bh *= art_param(g, "block_heat_mult", 1.0)
	if augment_on("dermal_plating"):
		bh *= 0.5
	heat += bh
	integrate(_ng("block", 1.0), "block")
	var out := {"take": take, "reflect": 0, "burn": 0}
	if g != "":
		practice(g, true)
		if art_param(g, "thorns", 0.0) > 0.0:               # round 122: Thorn Bark
			out["reflect"] = int(round(amount * art_param(g, "thorns", 0.0) * art_power(g)))
		if art_param(g, "ward_burn", 0.0) > 0.0:            # Ember Ward
			out["burn"] = int(round(amount * art_param(g, "ward_burn", 0.0)))
		if art_param(g, "block_heal", 0.0) > 0.0:           # Steady Breath
			heal(maxi(1, int(round(max_hp() * art_param(g, "block_heal", 0.0)))))
		match art_branch(g):
			"wood":
				heal(maxi(1, int(round(max_hp() * 0.02))))
			"metal":
				out["reflect"] = maxi(int(out["reflect"]), int(round(amount * 0.25)))
	glimpse("block")
	bump("blocks")
	return out


func parry(amount: int) -> Dictionary:
	## A perfect parry: nothing gets through, the attacker staggers, heat
	## vents. {"reflect": dmg back, "burn": burn on them, "stagger": secs}
	var g := guard_art()
	var vent := heat_cfg("parry_vent", 25.0)
	var out := {"reflect": 0, "burn": 0, "stagger": guard_cfg("stagger", 1.2)}
	if g != "":
		vent = maxf(vent, art_param(g, "parry_vent", vent))
		if art_param(g, "reflect_mult", 0.0) > 0.0:
			out["reflect"] = int(round(amount * art_param(g, "reflect_mult", 0.0) * art_power(g)))
		match art_branch(g):
			"water":
				vent += 20.0
			"fire":
				out["burn"] = int(round(amount * 0.5))
		if art_param(g, "parry_burn", 0.0) > 0.0:           # round 122: Ember Ward
			out["burn"] = maxi(int(out["burn"]), int(round(amount * art_param(g, "parry_burn", 0.0))))
		if art_param(g, "parry_charge", 0.0) > 0.0:         # Counter Current: the parry charges your next blow
			out["charge"] = art_param(g, "parry_charge", 0.0)
			out["charge_secs"] = art_param(g, "parry_charge_secs", 3.0)
		practice(g, true)
	heat = maxf(heat - vent, 0.0)
	integrate(_ng("parry", 3.0), "parry")
	on_parry_rhythm(Time.get_ticks_msec() / 1000.0)
	glimpse("parry")
	bump("parries")
	log_event("parry", {})
	return out


# ---- which art is on which key ----------------------------------------------------

func slot_of(aid: String) -> String:
	## round 122: which wired slot an art lives in (support arts depend on the support mode)
	var ax = sys("arts")
	return ax.slot_of(aid) if ax != null else art_family(aid)


func known_arts(fam: String) -> Array:
	## (fam is a SLOT: strike, step, guard, support, support2)
	var out := []
	for aid in lattice_data().get("arts", {}):
		if techniques.has(aid) and slot_of(str(aid)) == fam:
			out.append(str(aid))
	return out


func slot_art(fam: String) -> String:
	var s := str(art_slots.get(fam, ""))
	if s != "" and techniques.has(s) and slot_of(s) == fam:
		return s
	var k := known_arts(fam)
	return k[0] if k.size() > 0 else ""


func wire(aid: String) -> String:
	if not techniques.has(aid) or art_family(aid) == "":
		return I18n.t("You don't know that art.")
	art_slots[slot_of(aid)] = aid
	stats_changed.emit()
	var ax = sys("arts")
	var key: String = ax.slot_key(slot_of(aid)) if ax != null else "?"
	return I18n.t("%s is wired to %s.") % [technique_defs.get(aid, {}).get("name", aid), I18n.t("your guard") if key == "guard" else key]


func cycle_slot(fam: String) -> String:
	var k := known_arts(fam)
	if k.size() < 2:
		return I18n.t("You know only one %s art.") % fam if k.size() == 1 else I18n.t("You know no %s arts yet.") % fam
	var i := k.find(slot_art(fam))
	return wire(k[(i + 1) % k.size()])


# ---- branches ------------------------------------------------------------------

func art_branch(aid: String) -> String:
	return str(arts.get(aid, {}).get("b", ""))


func branch_options(aid: String) -> Array:
	return art_def(aid).get("branches", [])


func branch_text(aid: String, el: String) -> String:
	return str(lattice_data().get("branches", {}).get(art_family(aid), {}).get(el, ""))


func can_branch(aid: String) -> String:
	if not arts.has(aid):
		return I18n.t("You don't know that art.")
	if art_branch(aid) != "":
		return I18n.t("It has already taken its element.")
	if art_stage(aid) < 1:
		return I18n.t("An art takes an element when it's Fluent.")
	return ""


func choose_branch(aid: String, el: String) -> String:
	var why := can_branch(aid)
	if why != "":
		return why
	if not el in branch_options(aid):
		return I18n.t("That element doesn't fit this art.")
	var a: Dictionary = arts[aid]
	a["b"] = el
	arts[aid] = a
	affinity[el] = minf(float(affinity.get(el, 0.0)) + 3.0, 100.0)
	log_event("art_branch", {"art": aid, "element": el})
	stats_changed.emit()
	return I18n.t("BRANCH: your %s takes %s -- %s") % [technique_defs.get(aid, {}).get("name", aid), el, branch_text(aid, el)]


func branch_damage_mult(aid: String) -> float:
	return 1.2 if art_branch(aid) == "metal" and art_family(aid) == "strike" else 1.0


func branch_on_hit(aid: String, enemy, dmg: int, nth: int) -> void:
	## a strike art's element, on whatever it hit (nth: 0 for the first foe)
	if enemy == null or not is_instance_valid(enemy):
		return
	match art_branch(aid):
		"fire":
			if enemy.has_method("burn"):
				enemy.burn(int(round(dmg * 0.35)), 3.0)
		"water":
			if enemy.has_method("slow"):
				enemy.slow(3.0)
		"earth":
			if enemy.has_method("stagger"):
				enemy.stagger(0.8)
		"wood":
			if nth < 3:
				heal(maxi(1, int(round(max_hp() * 0.03))))


# ---- glimpses: how new arts are found ----------------------------------------------

func art_requires_met(aid: String) -> bool:
	var r: Dictionary = art_def(aid).get("requires", {})
	if r.is_empty():
		return true
	var ra := str(r.get("art", ""))
	return techniques.has(ra) and art_stage(ra) >= int(r.get("stage", 0))


func art_requires_text(aid: String) -> String:
	var r: Dictionary = art_def(aid).get("requires", {})
	if r.is_empty():
		return ""
	var ra := str(r.get("art", ""))
	return "%s %s" % [technique_defs.get(ra, {}).get("name", ra), str(ART_STAGES[clampi(int(r.get("stage", 0)), 0, 3)][0])]


func glimpse(event: String, n: float = 1.0) -> void:
	for aid in lattice_data().get("arts", {}):
		var g: Dictionary = art_def(str(aid)).get("glimpse", {})
		if str(g.get("from", "")) != event or techniques.has(aid):
			continue
		var before := float(glimpses.get(aid, 0.0))
		var need := float(g.get("need", 1))
		glimpses[aid] = minf(before + n, need)
		if before < 1.0 and float(glimpses[aid]) >= 1.0 and need > 1.0:
			message.emit(I18n.t("GLIMPSE: %s (%s, %d/%d%s)") % [g.get("text", ""), technique_defs.get(aid, {}).get("name", aid),
				int(glimpses[aid]), int(need), (I18n.t(" -- and it needs your ") + art_requires_text(str(aid))) if not art_requires_met(str(aid)) else ""])
	check_glimpses()


func glimpse_art(aid: String, n: float) -> void:
	## a glimpse of one particular art (an echo stone, a trial, a lesson)
	var g: Dictionary = art_def(aid).get("glimpse", {})
	if aid == "" or g.is_empty() or techniques.has(aid):
		return
	var need := float(g.get("need", 1))
	glimpses[aid] = minf(float(glimpses.get(aid, 0.0)) + n, need)
	message.emit(I18n.t("GLIMPSE: %s (%d/%d%s)") % [technique_defs.get(aid, {}).get("name", aid), int(glimpses[aid]), int(need),
		(I18n.t(" -- it needs your ") + art_requires_text(aid)) if not art_requires_met(aid) else ""])
	check_glimpses()


func check_glimpses() -> void:
	## any art fully glimpsed whose root art has grown enough is learned
	for aid in lattice_data().get("arts", {}):
		if techniques.has(aid) or not technique_defs.has(aid):
			continue
		var g: Dictionary = art_def(str(aid)).get("glimpse", {})
		if g.is_empty() or float(glimpses.get(aid, 0.0)) < float(g.get("need", 1)) or not art_requires_met(str(aid)):
			continue
		message.emit("GLIMPSE: %s" % g.get("text", ""))
		learn(str(aid), "glimpse")
		glimpses.erase(aid)


func glimpse_rows() -> Array:
	## for K: [name, have, need, needs-text] of every art still to find
	var out := []
	for aid in lattice_data().get("arts", {}):
		var g: Dictionary = art_def(str(aid)).get("glimpse", {})
		if g.is_empty() or techniques.has(aid):
			continue
		out.append([str(technique_defs.get(aid, {}).get("name", aid)), int(glimpses.get(aid, 0.0)), int(g.get("need", 1)),
			"" if art_requires_met(str(aid)) else art_requires_text(str(aid)), str(technique_defs.get(aid, {}).get("hint", ""))])
	return out


func is_art_source(src: String) -> bool:
	if src in ART_SOURCES:
		return true
	var ax = sys("arts")
	return ax != null and ax.is_source(src)


func boss_fell(first: bool) -> void:
	glimpse("boss")
	if first:
		add_item("nanite_bridge", 1, false)
		message.emit("NANITE BRIDGE: it leaves a sliver of living lattice. Wire it across a sealed point (K) to run an art early -- hot.")


# ---- nanite bridges ------------------------------------------------------------

func bridge_limit() -> int:
	var n := 1
	for r in range(1, 7):
		if ring_complete(r):
			n += 1
	return n


func can_bridge(pid: String) -> String:
	var p := lattice_point(pid)
	if p.is_empty():
		return I18n.t("There's no such point.")
	if lattice.has(pid):
		return I18n.t("%s is already open.") % p["name"]
	if bridges.has(pid):
		return I18n.t("%s already has a bridge.") % p["name"]
	if int(p["ring"]) > realm + 2:
		return I18n.t("%s is too deep to bridge yet.") % p["name"]
	if count("nanite_bridge") <= 0:
		return I18n.t("You have no nanite bridge. Great foes carry them.")
	if bridges.size() >= bridge_limit():
		return I18n.t("Your lattice can hold %d bridge%s. (Each complete ring holds one more.)") % [bridge_limit(), "" if bridge_limit() == 1 else "s"]
	return ""


func set_bridge(pid: String) -> String:
	var why := can_bridge(pid)
	if why != "":
		return why
	remove_item("nanite_bridge", 1)
	bridges[pid] = true
	log_event("bridge", {"id": pid})
	stats_changed.emit()
	return I18n.t("BRIDGE: living metal knits across %s. Arts through it run at half again the heat until it opens.") % lattice_point(pid).get("name", pid)


func pull_bridge(pid: String) -> String:
	if not bridges.has(pid):
		return I18n.t("There's no bridge there.")
	bridges.erase(pid)
	add_item("nanite_bridge", 1, false)
	stats_changed.emit()
	return I18n.t("You draw the bridge back out of %s.") % lattice_point(pid).get("name", pid)


# ---- aids and the training post ------------------------------------------------

func light_incense(mult: float, secs: float) -> void:
	aid_buff = {"mult": mult, "seconds": secs}
	message.emit(I18n.t("The incense smoulders. For %d minutes of sitting, qi and practice come %d%% faster.") % [int(secs / 60.0), int(round((mult - 1.0) * 100))])


func post_budget() -> float:
	if str(post_log.get("day", "")) != today():
		post_log = {"day": today(), "used": 0.0}
	return maxf(POST_DAILY_SECONDS - float(post_log.get("used", 0.0)), 0.0)


func post_drill(aid: String) -> bool:
	## An art used at the training post: real practice (between a miss and
	## a hit), while today's half hour lasts.
	if not arts.has(aid) or post_budget() <= 0.0:
		return false
	var cost := maxf(float(technique_defs.get(aid, {}).get("cooldown", 2.0)), 2.0)
	post_log["used"] = float(post_log.get("used", 0.0)) + cost
	practice(aid, false, 2.0)
	if post_budget() <= 0.0:
		message.emit("The post has taught you all it can today. Fights teach more; it'll be here tomorrow.")
	return true


# ======================================================================
# Round 21 -- the nanite swarm: its own road, beside cultivation.
# Robert, 2026-10-02: "make sure that the nanite and the cultivation are
# both separate and synergistic -- they can support each other ... they
# should rise separately through their own unique uses", and
# "experimentation for growth, or finding secrets ... a faster or more
# diverse path".
#
#   CULTIVATION (qi -> realms; the lattice; arts' mastery) rises by
#     sitting and by killing -- as before.
#   THE SWARM (integration -> nanite tiers, data/nanites.json) rises only
#     by USE: heat you run through it (double when hot), blows it hardens
#     against, parries, overruns survived, nanite shards absorbed, nanite
#     work at the bench, and experiments. Never by sitting.
#   Each feeds the other: every open lattice point is a channel the swarm
#     grows along (+1.5% integration each); every swarm tier pries the
#     meridians (+4% point opening), cools you (+12 heat cap, +8% vent) and
#     knits you (+1.5% life). Within a tier of each other they're in
#     HARMONY: +10% qi and +10% integration. Three apart, they STRAIN:
#     a swarm far ahead runs arts 20% hotter; qi far ahead caps your heat
#     at 85%. So both roads matter, and neither is a chore.
#   AUGMENTS: the swarm's own upgrades -- discovered by EXPERIMENTING at
#     your workbench (a shard and a reagent; the swarm tells you when
#     you're close), installed in slots that come with tiers.
#   DISCOVERIES: six hidden ways of doing things (Furnace Sitting,
#     Moonwater Breath, Edge Running...), found by trying them -- each a
#     faster or different road once found. Townsfolk know rumours.
# ======================================================================

var integration := 0.0           # the swarm's growth (its own road)
var near_water := false          # set by the Player (Moonwater Breath)
var sit_aid := 1.0               # round 23: a quiet alcove (Wonder.gd hermitage) deepens the sitting
var augments := {}               # augment id -> "known" | "on"
var discoveries := {}            # discovery id -> true
var _edge_secs := 0.0            # seconds held above 85% heat in a fight (Edge Running)
var _parry_times := []           # recent parries (Perfect Rhythm)
var _marrow_acc := 0.0
var nanite_def := {}


func nanite_data() -> Dictionary:
	if nanite_def.is_empty():
		nanite_def = _load_json("res://data/nanites.json", {"tiers": [{"name": "Nanite Seeding", "need": 0}], "gain": {}, "augments": {}, "discoveries": {}})
	return nanite_def


func _ng(k: String, d: float = 0.0) -> float:
	return float(nanite_data().get("gain", {}).get(k, d))


func nanite_tier() -> int:
	var t := 0
	var tiers: Array = nanite_data().get("tiers", [])
	for i in tiers.size():
		if integration >= float(tiers[i].get("need", 0)):
			t = i
	return t


func tier_name(t: int = -1) -> String:
	var tiers: Array = nanite_data().get("tiers", [])
	if t < 0:
		t = nanite_tier()
	return str(tiers[clampi(t, 0, tiers.size() - 1)].get("name", "Nanite Seeding")) if tiers.size() > 0 else "Nanite Seeding"


func integration_next() -> float:
	## the integration the next tier needs (-1 at the top)
	var tiers: Array = nanite_data().get("tiers", [])
	var t := nanite_tier()
	return float(tiers[t + 1].get("need", 0)) if t + 1 < tiers.size() else -1.0


func harmony() -> String:
	## "harmony" | "swarm_ahead" | "qi_ahead" | "" -- how the two roads sit together
	var h: Dictionary = nanite_data().get("harmony", {})
	var d := nanite_tier() - realm
	if absi(d) <= int(h.get("band", 1)):
		return "harmony" if nanite_tier() >= 1 and realm >= 1 else ""    # both roads have to have begun
	if d >= int(h.get("strain", 3)):
		return "swarm_ahead"
	if -d >= int(h.get("strain", 3)):
		return "qi_ahead"
	return ""


func harmony_text() -> String:
	match harmony():
		"harmony":
			return I18n.t("in harmony: +10% qi, +10% swarm growth")
		"swarm_ahead":
			return I18n.t("the swarm outruns your qi: arts run 20% hotter")
		"qi_ahead":
			return I18n.t("your qi outgrows the swarm: heat capped at 85%")
	if nanite_tier() < 1 or realm < 1:
		return I18n.t("both roads just begun -- grow each, and they'll fall into harmony")
	return I18n.t("a little out of step")


func integration_mult() -> float:
	var m := 1.0 + _ng("per_point", 0.015) * lattice.size()
	if harmony() == "harmony":
		m *= float(nanite_data().get("harmony", {}).get("mult", 1.1))
	return m * growth_mult() * tech_effect("swarm_mult", 1.0)


func integrate(amount: float, why: String = "") -> void:
	## the swarm grows (never from sitting -- only from use)
	if amount <= 0.0:
		return
	var t0 := nanite_tier()
	integration += amount * integration_mult()
	var t1 := nanite_tier()
	if t1 > t0:
		var pt: Dictionary = nanite_data().get("per_tier", {})
		message.emit(I18n.t("SWARM: your nanites reach %s -- heat cap +%d, they vent faster, they pry your meridians open faster.%s") % [
			tier_name(t1), int(pt.get("heat_cap", 12)), " A new augment slot." if augment_slots() > _slots_at(t0) else ""])
		log_event("nanite_tier", {"tier": tier_name(t1), "why": why})
		hp = mini(hp, max_hp())
		stats_changed.emit()


func _slots_at(t: int) -> int:
	var n := 0
	for row in nanite_data().get("slots", []):
		if t >= int(row[0]):
			n = int(row[1])
	return n


func augment_slots() -> int:
	return _slots_at(nanite_tier())


func nanite_effect() -> Dictionary:
	## what the swarm gives the body (into _effects)
	var out := {}
	var pt: Dictionary = nanite_data().get("per_tier", {})
	var t := nanite_tier()
	if t > 0:
		out["hp_mult"] = 1.0 + float(pt.get("hp_mult", 0.015)) * t
		out["damage_mult"] = 1.0 + float(pt.get("damage_mult", 0.0)) * t       # round 36: the swarm in the arm, too
		out["regen"] = float(pt.get("regen", 0.0)) * t
	if harmony() == "harmony":
		out["qi_mult"] = float(nanite_data().get("harmony", {}).get("mult", 1.1))
	return out


func swarm_open_mult() -> float:
	return 1.0 + float(nanite_data().get("per_tier", {}).get("open_speed", 0.04)) * nanite_tier()


func swarm_vent_mult() -> float:
	var m := 1.0 + float(nanite_data().get("per_tier", {}).get("vent", 0.08)) * nanite_tier()
	if augment_on("coolant_weave"):
		m *= 1.3
	return m


func swarm_heat_cap() -> float:
	return float(nanite_data().get("per_tier", {}).get("heat_cap", 12)) * nanite_tier()


# ---- augments ---------------------------------------------------------------------

func augment_def(id: String) -> Dictionary:
	return nanite_data().get("augments", {}).get(id, {})


func augment_on(id: String) -> bool:
	return str(augments.get(id, "")) == "on"


func augments_on() -> int:
	var n := 0
	for id in augments:
		if str(augments[id]) == "on":
			n += 1
	return n


func set_augment(id: String, on: bool) -> String:
	if not augments.has(id):
		return I18n.t("You haven't found that augment.")
	if on:
		if augment_on(id):
			return I18n.t("It's already running.")
		if augments_on() >= augment_slots():
			return I18n.t("Your swarm can run %d augment%s at %s. (More come with its tiers.)") % [augment_slots(), "" if augment_slots() == 1 else "s", tier_name()] if augment_slots() > 0 else I18n.t("Your swarm is too young to hold an augment -- it needs to reach %s.") % tier_name(1)
		augments[id] = "on"
	else:
		augments[id] = "known"
	stats_changed.emit()
	return "%s %s." % [augment_def(id).get("name", id), I18n.t("comes alive in your swarm") if on else "goes quiet"]


func experiment(reagent: String) -> String:
	## At the workbench: a nanite shard and something else, and see what the
	## swarm makes of it. The right reagent teaches it an augment; a near
	## miss (the same element) says so; anything else is still a little
	## growth.
	if count("nanite_shard") <= 0:
		return I18n.t("You need a nanite shard to experiment with.")
	if reagent == "nanite_shard" or count(reagent) <= 0:
		return I18n.t("You need some of that to try.")
	remove_item("nanite_shard", 1)
	remove_item(reagent, 1)
	bump("experiments")
	integrate(_ng("experiment", 10.0), "experiment")
	var tried: Dictionary = flags.get("experiments_tried", {}) if flags.get("experiments_tried", {}) is Dictionary else {}
	tried[reagent] = true
	flags["experiments_tried"] = tried
	for id in nanite_data().get("augments", {}):
		if str(augment_def(str(id)).get("reagent", "")) == reagent:
			if augments.has(id):
				return I18n.t("The swarm remembers this one -- it already makes %s from it. (+a little growth)") % augment_def(str(id)).get("name", id)
			augments[id] = "known"
			log_event("augment_found", {"id": id, "reagent": reagent})
			stats_changed.emit()
			return I18n.t("EXPERIMENT: the swarm takes the %s and builds something new -- %s. %s Install it from K.") % [item_name(reagent), augment_def(str(id)).get("name", id), augment_def(str(id)).get("desc", "")]
	var el := str(items.get(reagent, {}).get("element", ""))
	for id in nanite_data().get("augments", {}):
		if augments.has(id):
			continue
		var rel := str(items.get(str(augment_def(str(id)).get("reagent", "")), {}).get("element", ""))
		if rel != "" and rel == el:
			return I18n.t("The swarm stirs at the %s in it -- something %s is close, but this isn't it. (+a little growth)") % [el, el]
	return I18n.t("The swarm eats the %s and learns a little. Nothing new. (+a little growth)") % item_name(reagent)


func experiment_reagents() -> Array:
	## materials you could try (everything but the shard itself)
	var out := []
	for id in inventory:
		if str(items.get(base_id(str(id)), {}).get("type", "")) == "material" and str(id) != "nanite_shard" and count(str(id)) > 0:
			out.append(str(id))
	out.sort()
	return out


func absorb(id: String, sitting: bool = false) -> String:
	## nanite material taken into the swarm
	var per := float(nanite_data().get("gain", {}).get("absorb", {}).get(id, 0.0))
	if per <= 0.0:
		return I18n.t("The swarm can't take that in.")
	if count(id) <= 0:
		return I18n.t("You have none.")
	remove_item(id, 1)
	var g := per
	if sitting:
		discover("shard_communion")      # tried it while sitting: that's how it's found
		g *= 2.0
	integrate(g, "absorb")
	bump("absorbed")
	return I18n.t("The %s dissolves into you; the swarm hums. (%s, %d / %d)") % [item_name(id), tier_name(), int(integration), int(integration_next())]


# ---- discoveries ---------------------------------------------------------------

func discover(id: String) -> bool:
	## true the first time
	if discoveries.has(id) or not nanite_data().get("discoveries", {}).has(id):
		return false
	discoveries[id] = true
	var d: Dictionary = nanite_data()["discoveries"][id]
	message.emit(I18n.t("DISCOVERY: %s -- %s") % [d.get("name", id), d.get("desc", "")])
	log_event("discovery", {"id": id})
	bump("discoveries")
	stats_changed.emit()
	return true


func nanite_tick(delta: float, in_fight: bool, sitting: bool, near_water: bool, sat_for: float) -> void:
	## once a frame from the Player: the discoveries that are about how you
	## do things, and the augments that work over time
	if in_fight and heat_frac() >= 0.85 and not sitting:
		_edge_secs += delta
		if _edge_secs >= 15.0:
			discover("edge_running")
	if sitting:
		if running_hot():
			discover("furnace_sitting")
		if near_water and (hour() >= 20.0 or hour() < 5.0):
			discover("moonwater_breath")
		if sat_for >= 600.0:
			discover("still_mind")


func on_parry_rhythm(now: float) -> void:
	_parry_times.append(now)
	while _parry_times.size() > 0 and now - float(_parry_times[0]) > 6.0:
		_parry_times.pop_front()
	if _parry_times.size() >= 3:
		var first := discover("perfect_rhythm")
		if discoveries.has("perfect_rhythm"):
			heat = 0.0
			integrate(20.0, "rhythm")
			if not first:
				message.emit("PERFECT RHYTHM -- your heat falls silent.")
		_parry_times.clear()


func discovery_rows() -> Array:
	## for the journal: [name, desc-or-"?", found]
	var out := []
	for id in nanite_data().get("discoveries", {}):
		var d: Dictionary = nanite_data()["discoveries"][id]
		out.append([str(d.get("name", id)) if discoveries.has(id) else "???", str(d.get("desc", "")) if discoveries.has(id) else "", discoveries.has(id)])
	return out


func rumour(rng_seed: int = -1) -> String:
	## something a townsperson might say about a discovery you haven't made
	var left := []
	for id in nanite_data().get("discoveries", {}):
		if not discoveries.has(id):
			left.append(str(nanite_data()["discoveries"][id].get("rumour", "")))
	for id in nanite_data().get("augments", {}):
		if not augments.has(id):
			left.append(str(augment_def(str(id)).get("hint", "")))
	# round 26: and what Eliet says about the valley (Dev's rumours)
	for r in valley_data().get("rumours", []):
		for line in r.get("lines", []):
			left.append(str(line))
	if left.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	return str(left[rng.randi() % left.size()])


func _grandfather_swarm() -> void:
	## a save from before the swarm had its own road: it grew with your
	## realm then, so it starts at the tier your realm had named
	var tiers: Array = nanite_data().get("tiers", [])
	integration = float(tiers[clampi(realm, 0, tiers.size() - 1)].get("need", 0)) if tiers.size() > 0 else 0.0


# ======================================================================
# Round 22 -- training you find by asking, and trade without the fuss.
# Robert, 2026-10-02: "smooth out the chat and trade screens; include
# training if it's available in chat, or make it discoverable through
# asking." Every townsperson can teach ONE thing (data/training.json,
# picked by their role and name). Ask them about training/lessons in
# chat and they tell you what and for how much; from then on it's a
# button in their menu too. Once a person, once a day.
# ======================================================================

var training_def := {}


func training_data() -> Dictionary:
	if training_def.is_empty():
		training_def = _load_json("res://data/training.json", {"words": [], "lessons": {}, "by_role": {}, "price": {}})
	return training_def


func asks_about_training(text: String) -> bool:
	var t := " " + text.to_lower() + " "
	for w in training_data().get("words", []):
		if t.contains(str(w)):
			return true
	return false


func lesson_for(npc_name: String, role: String) -> String:
	## the one thing this person teaches ("" for none)
	var opts: Array = training_data().get("by_role", {}).get(role, training_data().get("by_role", {}).get("villager", []))
	if opts.is_empty():
		return ""
	return str(opts[absi(hash(npc_name)) % opts.size()])


func lesson_price(npc_name: String) -> int:
	var p: Dictionary = training_data().get("price", {})
	var g := float(p.get("base", 15)) + float(p.get("per_realm", 20)) * realm
	if float(bond(npc_name).get("warmth", 0.0)) >= 25.0:
		g *= float(p.get("friend_mult", 0.75))
	return int(round(g))


func knows_lesson(npc_name: String) -> bool:
	return has_flag("lesson_known:" + npc_name)


func learn_of_lesson(npc_name: String) -> void:
	if not knows_lesson(npc_name):
		set_flag("lesson_known:" + npc_name)
		log_event("lesson_found", {"npc": npc_name})


func lesson_pitch(npc_name: String, role: String) -> String:
	## what they'd say they can teach (fed to their voice, and shown)
	var l: Dictionary = training_data().get("lessons", {}).get(lesson_for(npc_name, role), {})
	if l.is_empty():
		return ""
	return I18n.t("%s can teach you %s -- %s. (%d gold, once a day.)") % [npc_name, l.get("pitch", l.get("name", "")), l.get("desc", ""), lesson_price(npc_name)]


func lesson_wait(npc_name: String) -> bool:
	return str(flags.get("lesson_day:" + npc_name, "")) == today()


func take_lesson(npc_name: String, role: String) -> String:
	var kind := lesson_for(npc_name, role)
	var l: Dictionary = training_data().get("lessons", {}).get(kind, {})
	if l.is_empty():
		return I18n.t("%s has nothing to teach you.") % npc_name
	if lesson_wait(npc_name):
		return I18n.t("\"That's enough for today. Let it settle. Come back tomorrow.\"")
	var price := lesson_price(npc_name)
	if gold < price:
		return I18n.t("\"%d gold. Lessons aren't free -- I have to eat too.\"") % price
	gold -= price
	flags["lesson_day:" + npc_name] = today()
	learn_of_lesson(npc_name)
	var out := ""
	match kind:
		"strike_drill", "step_drill", "guard_drill":
			var fam := kind.trim_suffix("_drill")
			var a := slot_art(fam)
			if a != "":
				practice(a, false, 12.0)
				out = "You drill your %s until your arms ache (+12 practice -- it settles when you rest)." % technique_defs.get(a, {}).get("name", a)
			# a glimpse of what comes next in that family
			var g_aid := ""
			for aid in lattice_data().get("arts", {}):
				if art_family(str(aid)) == fam and not techniques.has(aid) and not art_def(str(aid)).get("glimpse", {}).is_empty():
					g_aid = str(aid)
					break
			if g_aid != "":
				var need := float(art_def(g_aid)["glimpse"].get("need", 1))
				glimpses[g_aid] = minf(float(glimpses.get(g_aid, 0.0)) + maxf(2.0, need * 0.2), need)
				out += (" " if out != "" else "") + I18n.t("And you watch how they do it -- a glimpse of %s (%d/%d).") % [technique_defs.get(g_aid, {}).get("name", g_aid), int(glimpses[g_aid]), int(need)]
				check_glimpses()
			if out == "":
				out = "You drill until your arms ache, though you know nothing yet to drill."
		"breath":
			light_incense(1.4, 900.0)
			if lattice_focus != "":
				_push_point(lattice_focus, 60.0)
			out = "You sit together and breathe. Your focus point loosens, and your next quarter hour on the mat will run deeper."
		"weapon":
			add_skill_xp(weapon_skill(), 40.0 + 10.0 * depth, "a lesson")
			out = "An hour of correction: your grip, your feet, your wrist. Your %s comes easier." % skill_name(weapon_skill())
		"swarm":
			integrate(30.0, "lesson")
			var r := rumour(hash(npc_name + today()))
			out = I18n.t("They show you how the old machines like to be handled. Your swarm hums.") + ((I18n.t(" And they let something slip: \"%s\"") % r) if r != "" else "")
	warm_bond(npc_name, 2.0)
	bump("lessons")
	log_event("lesson", {"npc": npc_name, "kind": kind})
	stats_changed.emit()
	return out


# ---- trade ---------------------------------------------------------------------

func sell_price(id: String) -> int:
	## what a trader gives you for one (0 = they won't take it)
	var d := item_def(id)
	if d.is_empty() or is_treasure(id):
		return 0
	var val: int = int(d.get("value", 0))
	var cheapest_shop: int = int(round(round(round(val * 2.0) * 0.85) * 0.85 * 0.8))
	var max_sell: int = maxi(0, cheapest_shop - 1)
	match str(d.get("type", "")):
		"material":
			return mini(val, max_sell)
		"weapon", "armor", "ring", "amulet", "consumable", "cowl", "choker", "necklace", "cape", "pauldrons", "robe", \
		"underarmour", "vambraces", "bracelet", "gloves", "gauntlets", "pants", "greaves", "boots", "toering":
			if count(id) <= equipped_count(id):
				return 0           # not what you're wearing
			return mini(mini(maxi(1, val / 2), made_sell_cap(id)), max_sell)
		"crystal":
			return mini(val, max_sell)     # round 43: a condensed legacy sells at its worth
	return 0


# ---- round 57: no buy-make-sell money loop -------------------------------------------------

var _make_cost := {}            # base id -> the least its materials could cost (raw value), or -1 if it isn't made
var _recipes_for := {}
var _econ := {}


func economy_data() -> Dictionary:
	if _econ.is_empty():
		_econ = _load_json("res://data/economy.json", {"cheapest_buy_factor": 1.156, "made_sell_cap": 0.9})
	return _econ


func make_cost(id: String) -> float:
	## the least one of these could cost to make from BOUGHT materials (a
	## recipe, the forge from a stock material, a jewel from a metal and a gem):
	## materials at the cheapest any shop could ever sell them, plus the fees
	## and fuel; -1 if nothing makes it
	var b := base_id(id)
	if _make_cost.has(b):
		return float(_make_cost[b])
	if _recipes_for.is_empty():
		for r in recipes:
			var mk := str(r.get("makes", ""))
			if not _recipes_for.has(mk):
				_recipes_for[mk] = []
			_recipes_for[mk].append(r)
	var f := float(economy_data().get("cheapest_buy_factor", 1.156))
	var best := -1.0
	for r in _recipes_for.get(b, []):
		var m := 0.0
		var needs: Dictionary = r.get("needs", {})
		for k in needs:
			m += float(items.get(base_id(str(k)), {}).get("value", 0)) * float(needs[k])
		var c := (float(r.get("gold", 0)) + m * f) / maxf(1.0, float(r.get("count", 1)))
		if best < 0.0 or c < best:
			best = c
	var d: Dictionary = items.get(b, {})
	var fams: Dictionary = gear_data().get("families", {})
	var fam := str(d.get("type", ""))
	var mat := str(d.get("stock", d.get("metal", "")))
	if mat != "" and items.has(mat):
		var need := float(fams.get(fam, fams.get("armor", {}) if fam == "armor" else {}).get("needs", 1))
		var m2 := need * float(items[mat].get("value", 0))
		if str(d.get("gem", "")) != "" and items.has(str(d["gem"])):
			m2 += float(items[str(d["gem"])].get("value", 0))
		var c2 := m2 * f + 3.0 * float(d.get("tier", 1))
		if best < 0.0 or c2 < best:
			best = c2
	_make_cost[b] = best
	return best


func made_sell_cap(id: String) -> int:
	## what a trader will pay at most for a made thing: never more than the
	## cheapest its materials could be bought for (no buy-make-sell loop)
	var c := make_cost(id)
	if c < 0.0:
		return 1 << 30
	return maxi(1, int(floor(c * float(economy_data().get("made_sell_cap", 0.9)))))


func sellables() -> Array:
	var out := []
	for id in inventory:
		if count(str(id)) > 0 and sell_price(str(id)) > 0:
			out.append(str(id))
	out.sort_custom(func(a, b): return item_name(a) < item_name(b))
	return out


func sell(id: String, n: int) -> int:
	## returns the gold paid
	n = mini(n, count(id))
	if sys("tester") != null and sys("tester").free_item(id):
		return 0                          # (conjured stock isn't for sale)
	var p := sell_price(id)
	if n <= 0 or p <= 0:
		return 0
	remove_item(id, n)
	gold += p * n
	log_event("sell", {"id": id, "n": n})
	stats_changed.emit()
	return p * n


# ======================================================================
# Round 24 -- the valley: sects and towers.
# Robert, 2026-10-02: "towers to climb and sects outside of the dungeon --
# the dungeon is the primary way to progress but not the only way";
# "do both, start with the valley sects and towers".
#
# data/valley.json (built by tools/integrate_drafts.py from Dev's drafts)
# holds the sects Dev wrote -- creed, nanite way, entry trial, elder,
# rival, three arts -- and three towers of nine trial floors.
#   SECTS: pass a sect's entry trial at its seat in the valley and you're
#     an Outer Disciple. Contribution (kills anywhere, tower floors,
#     materials of the sect's element) raises you through four ranks, and
#     each of the first three teaches one of the sect's own arts -- real
#     ki arts in the lattice, built on the engine's art templates (picked
#     from Dev's own description of the art), carrying the sect's element
#     from the start. One sect at a time; leaving keeps what you learned.
#     A member sits in the sect hall at 2.5x.
#   TOWERS: nine floors each -- combat, puzzle (wake the five element
#     pillars in the order of creation or of overcoming), endurance, insight
#     -- with a guardian at the top. Each tower opens at a realm (0 / 2 / 4)
#     and pays per floor (gold, qi, swarm, contribution); the summit names
#     you, gives a nanite bridge and the swarm a great deal.
# ======================================================================

const ART_TEMPLATES := {
	"qi_burst": {"family": "strike", "heat": 28.0, "cooldown": 7.0, "key": "F", "params": {"burst_radius": 4.5, "burst_mult": 1.9},
		"how": "a ring of force around you"},
	"severing_finger": {"family": "strike", "heat": 22.0, "cooldown": 3.5, "key": "F", "params": {"finger_range": 13.0, "finger_mult": 2.1},
		"how": "one foe, at range"},
	"collapsing_palm": {"family": "strike", "heat": 36.0, "cooldown": 9.0, "key": "F", "params": {"palm_range": 5.0, "palm_mult": 2.9},
		"how": "a heavy cone ahead that staggers"},
	"wind_step": {"family": "step", "heat": 16.0, "cooldown": 2.5, "key": "V", "params": {"dash": 7.0}, "how": "a dash through blows"},
	"hollow_step": {"family": "step", "heat": 20.0, "cooldown": 5.0, "key": "V", "params": {"hollow_range": 9.0, "ambush_mult": 1.5},
		"how": "appear behind a foe; the next strike lands harder"},
	"cloud_ladder": {"family": "step", "heat": 14.0, "cooldown": 3.0, "key": "V", "params": {"ladder_lift": 1.6}, "how": "a leap off the air itself"},
	"iron_shell": {"family": "guard", "heat": 0.0, "cooldown": 0.0, "key": "Right mouse", "params": {"guard_take": 0.32, "block_heat_mult": 0.6},
		"how": "a guard that lets little through"},
	"returning_tide": {"family": "guard", "heat": 0.0, "cooldown": 0.0, "key": "Right mouse",
		"params": {"parry_bonus": 0.08, "reflect_mult": 1.3, "parry_vent": 35.0}, "how": "a parry that sends the blow back"},
}
const TOWER_FLOOR_RANGE := {1: [1, 3], 2: [6, 9], 3: [12, 17]}
const TOWER_DEPTH := {1: 3, 2: 8, 3: 15}
const SECT_HALL_AID := 2.5
const SECT_GUEST_AID := 1.25

var sect := {}                   # {"id", "rank", "contrib"} -- the sect you belong to
var towers := {}                 # tower id -> highest floor cleared
var valley_def := {}


func valley_data() -> Dictionary:
	if valley_def.is_empty():
		valley_def = _load_json("res://data/valley.json", {"sects": [], "towers": [], "ranks": []})
	return valley_def


func sect_def(id: String) -> Dictionary:
	for s in valley_data().get("sects", []):
		if str(s.get("id", "")) == id:
			return s
	return {}


func tower_def(id: String) -> Dictionary:
	for t in valley_data().get("towers", []):
		if str(t.get("id", "")) == id:
			return t
	return {}


func art_template(aid: String) -> String:
	return str(art_def(aid).get("template", aid))


func art_param(aid: String, key: String, default_value: float) -> float:
	## an art's own numbers: a templated art's "params", else its effect
	var d: Dictionary = technique_defs.get(aid, {})
	if d.get("params", {}) is Dictionary and d.get("params", {}).has(key):
		return float(d["params"][key])
	if d.get("effect", {}) is Dictionary and d.get("effect", {}).has(key):
		return float(d["effect"][key])
	return default_value


func _merge_valley_arts() -> void:
	## every sect's three arts become real arts in the lattice
	var L := lattice_data()
	var arts_l: Dictionary = L.get("arts", {})
	for s in valley_data().get("sects", []):
		var el := str(s.get("element", "earth"))
		for a in s.get("arts", []):
			var aid := str(a.get("id", ""))
			var tm: Dictionary = ART_TEMPLATES.get(str(a.get("template", "")), {})
			if aid == "" or tm.is_empty():
				continue
			var fam := str(tm["family"])
			arts_l[aid] = {"family": fam, "route": _sect_route(fam, int(a.get("rank", 1)), el), "heat": tm["heat"], "branches": [el],
				"template": str(a["template"]), "sect": str(s["id"])}
			technique_defs[aid] = {"name": str(a.get("name", aid)), "kind": "active", "key": tm["key"], "cooldown": tm["cooldown"], "realm": 0,
				"desc": I18n.t("%s (%s art: %s; %s from the start.)") % [str(a.get("what", "")).strip_edges(), str(s.get("name", "")), tm["how"], el],
				"params": tm["params"].duplicate(), "effect": {},
				"hint": I18n.t("Taught by the %s to its %s.") % [s.get("name", ""), sect_rank_name(int(a.get("rank", 1)) - 1)]}
	L["arts"] = arts_l


func _sect_route(fam: String, rank: int, el: String) -> Array:
	## two first-ring points; deeper ranks run deeper, along the sect's element where it can
	var by_ring := {}
	for p in lattice_data().get("points", []):
		if str(p["meridian"]) == fam:
			if not by_ring.has(int(p["ring"])):
				by_ring[int(p["ring"])] = []
			by_ring[int(p["ring"])].append(p)
	var out := []
	for p in by_ring.get(1, []):
		out.append(str(p["id"]))
	for ring in range(2, rank + 1):
		var pick = null
		for p in by_ring.get(ring, []):
			if str(p.get("element", "")) == el:
				pick = p
		if pick == null and by_ring.get(ring, []).size() > 0:
			pick = by_ring[ring][0]
		if pick != null:
			out.append(str(pick["id"]))
	return out


# ---- sects -------------------------------------------------------------------------

func sect_ranks() -> Array:
	var r: Array = valley_data().get("ranks", [])
	return r if r.size() > 0 else [["Outer Disciple", 0, 0], ["Inner Disciple", 100, 1], ["Core Disciple", 300, 2], ["Elder's Disciple", 800, 3]]


func sect_rank_name(r: int = -1) -> String:
	if r < 0:
		r = int(sect.get("rank", 0))
	var rows := sect_ranks()
	return str(rows[clampi(r, 0, rows.size() - 1)][0])


func in_sect(id: String = "") -> bool:
	return not sect.is_empty() and (id == "" or str(sect.get("id", "")) == id)


func sect_join_check(id: String) -> String:
	if sect_def(id).is_empty():
		return I18n.t("There's no such sect.")
	if in_sect(id):
		return I18n.t("You already belong to the %s.") % sect_def(id).get("name", id)
	if in_sect():
		return I18n.t("You belong to the %s. A sect takes all of you -- leave it first.") % sect_def(str(sect["id"])).get("name", "")
	if str(flags.get("sect_left_day", "")) == today():
		return I18n.t("\"You left a sect this very day. Come back when you've decided who you are.\"")
	return ""


func join_sect(id: String) -> String:
	var why := sect_join_check(id)
	if why != "":
		return why
	var s := sect_def(id)
	sect = {"id": id, "rank": 0, "contrib": 0.0}
	_teach_sect_rank(0)
	story_owed_on_join()                         # round 32
	log_event("sect_join", {"sect": id})
	bump("sects_joined")
	stats_changed.emit()
	return I18n.t("SECT: you are an %s of the %s.") % [sect_rank_name(0), s.get("name", id)]


func _teach_sect_rank(r: int) -> void:
	for a in sect_def(str(sect.get("id", ""))).get("arts", []):
		if int(a.get("rank", 1)) == r + 1 and not techniques.has(str(a["id"])):
			learn(str(a["id"]), "sect")


func sect_contrib(n: float, why: String = "") -> void:
	if sect.is_empty() or n <= 0.0:
		return
	sect["contrib"] = float(sect.get("contrib", 0.0)) + n
	var rows := sect_ranks()
	while int(sect["rank"]) + 1 < rows.size():
		var nxt: Array = rows[int(sect["rank"]) + 1]
		if float(sect["contrib"]) < float(nxt[1]):
			break
		if realm < int(nxt[2]):
			if not has_flag("sect_wait:%s:%d" % [sect["id"], int(sect["rank"]) + 1]):
				set_flag("sect_wait:%s:%d" % [sect["id"], int(sect["rank"]) + 1])
				message.emit(I18n.t("SECT: you've given enough to be %s -- the elders want your cultivation to reach %s first.") % [nxt[0], realm_info(int(nxt[2]))["name"]])
			break
		sect["rank"] = int(sect["rank"]) + 1
		_teach_sect_rank(int(sect["rank"]))
		message.emit(I18n.t("SECT: the %s raise you to %s.") % [sect_def(str(sect["id"])).get("name", ""), sect_rank_name()])
		log_event("sect_rank", {"sect": sect["id"], "rank": sect_rank_name()})
		if int(sect["rank"]) == rows.size() - 1:
			var el := str(sect_def(str(sect["id"])).get("element", ""))
			if affinity.has(el):
				affinity[el] = minf(float(affinity[el]) + 10.0, 100.0)
		stats_changed.emit()


func sect_next_text() -> String:
	if sect.is_empty():
		return ""
	var rows := sect_ranks()
	var r := int(sect.get("rank", 0))
	if r + 1 >= rows.size():
		return I18n.t("You stand as high in the sect as a disciple can.")
	var nxt: Array = rows[r + 1]
	return I18n.t("Next: %s at %d contribution%s (you have %d).") % [nxt[0], int(nxt[1]),
		(", and %s" % realm_info(int(nxt[2]))["name"]) if int(nxt[2]) > 0 else "", int(sect.get("contrib", 0.0))]


func leave_sect() -> String:
	if sect.is_empty():
		return I18n.t("You belong to no sect.")
	var nm := str(sect_def(str(sect["id"])).get("name", ""))
	log_event("sect_leave", {"sect": sect["id"]})
	sect = {}
	flags["sect_left_day"] = today()
	stats_changed.emit()
	return I18n.t("You leave the %s. What they taught you stays with you.") % nm


func sect_donate() -> String:
	## materials of the sect's element, for contribution (a fifth of their worth)
	if sect.is_empty():
		return I18n.t("You belong to no sect.")
	var el := str(sect_def(str(sect["id"])).get("element", ""))
	var worth := 0
	for id in inventory.keys():
		var d: Dictionary = items.get(base_id(str(id)), {})
		if str(d.get("type", "")) == "material" and str(d.get("element", "")) == el:
			worth += int(d.get("value", 0)) * count(str(id))
			remove_item(str(id), count(str(id)))
	if worth <= 0:
		return I18n.t("You carry nothing of %s for the sect's stores.") % el
	sect_contrib(worth / 5.0, "donation")
	log_event("sect_donate", {"worth": worth})
	return I18n.t("The stores take it gratefully. (+%d contribution)") % int(worth / 5.0)


func sect_effect() -> Dictionary:
	if not sect.is_empty() and int(sect.get("rank", 0)) >= sect_ranks().size() - 1:
		return {"meditate_mult": 1.15}
	return {}


# ---- towers ----------------------------------------------------------------------

func level_exists(level_id: String) -> bool:
	## a file in levels/, or one of the places drawn when entered
	if level_id == "valley" or level_id.begins_with("tribulation:") or FrontierGen.exists(level_id) or OnlineGen.is_online(level_id):
		return true
	if TowerGen.is_tower(level_id):
		return not tower_def(str(TowerGen.parse(level_id).get("id", ""))).is_empty()
	return ScavengeGen.is_scavenge(level_id) or FileAccess.file_exists("res://levels/%s.json" % level_id)


func tower_cleared(tid: String) -> int:
	return int(towers.get(tid, 0))


func tower_locked(tid: String) -> String:
	var t := tower_def(tid)
	if t.is_empty():
		return I18n.t("That tower isn't there.")
	if realm < int(t.get("realm", 0)):
		return I18n.t("The door of %s doesn't move for you. (It opens to %s.)") % [t.get("name", tid), realm_info(int(t.get("realm", 0)))["name"]]
	return ""


func tower_enemy_pool(tier: int) -> Array:
	var rg: Array = TOWER_FLOOR_RANGE.get(tier, [1, 3])
	var out := []
	for id in enemies:
		var e: Dictionary = enemies[id]
		var f := int(e.get("floor", -1))
		if f >= int(rg[0]) and f <= int(rg[1]) and not bool(e.get("boss", false)) and not bool(e.get("passive", false)):
			out.append(str(id))
	out.sort()
	return out


func tower_guardian(tier: int) -> String:
	var rg: Array = TOWER_FLOOR_RANGE.get(tier, [1, 3])
	var best := ""
	var best_f := -1
	for id in enemies:
		var e: Dictionary = enemies[id]
		var f := int(e.get("floor", -1))
		if bool(e.get("boss", false)) and f >= int(rg[0]) and f <= int(rg[1]) and f > best_f:
			best_f = f
			best = str(id)
	return best


func clear_tower_floor(tid: String, n: int) -> String:
	var t := tower_def(tid)
	var tier := int(t.get("tier", 1))
	var first := n > tower_cleared(tid)
	if not first:
		add_item("gold", 5 * tier * n, false)
		return I18n.t("The floor remembers you. (+%d gold)") % (5 * tier * n)
	towers[tid] = n
	add_item("gold", 20 * tier * n, false)
	add_qi(12.0 * tier * n, "the tower")
	integrate(6.0 * tier + 2.0 * n, "tower")
	sect_contrib(10.0, "tower")
	bump("tower_floors")
	log_event("tower_floor", {"tower": tid, "floor": n})
	var out := I18n.t("FLOOR CLEARED: %s, floor %d. (+%d gold)") % [t.get("name", tid), n, 20 * tier * n]
	if n >= 9:
		var title := "Summit of %s" % t.get("name", tid)
		if not (title in titles):
			titles.append(title)
		add_item("nanite_bridge", 1, false)
		integrate(100.0 * tier, "summit")
		bump("tower_summits")
		log_event("tower_summit", {"tower": tid})
		out = I18n.t("SUMMIT: %s -- %s You are named %s. (A nanite bridge; your swarm surges.)") % [t.get("name", tid), t.get("summit", ""), title]
	message.emit(out)
	stats_changed.emit()
	return out


# ======================================================================
# Round 25 -- the breakthrough you earn twice: comprehension and the heart
# demon. (Robert, 2026-10-02: "do both"; the design doc's round 3.)
#
# The ten steps inside a realm still fill with qi. Crossing INTO the next
# realm takes three things:
#   1. a full sea of qi (step 10, topped up -- qi stops there and waits),
#   2. COMPREHENSION: enough insight (10 for Qi Condensation, then 25, 50,
#      90, 150...) -- insight comes from doing new things: a first visit to
#      a place, a lore stone read, an art grown Fluent/Mastered/Transcendent,
#      a lesson, a discovery, a tower floor, a sect rank, a riddle solved --
#      AND every point of your current ring of the lattice open,
#   3. the TRIBULATION: sit (M) and your nanites resist being rewritten --
#      the resistance takes your shape, a HEART DEMON with your strength
#      and the art family you lean on most. Win and you cross, with a Dao
#      Heart bonus (more if you win on your first try). Lose and it costs an
#      injured meridian and an hour -- never your progress.
# ======================================================================

const INSIGHT_NEED := [10, 25, 50, 90, 150, 220, 300, 400, 520, 660]
const INSIGHT_FOR := {"lore_read": 1.0, "lesson": 1.0, "discovery": 3.0, "tower_floor": 1.0, "tower_summit": 5.0, "sect_rank": 3.0,
	"sect_join": 2.0, "riddle_solved": 2.0, "inheritance": 3.0, "augment_found": 2.0, "glimpse_learned": 2.0,
	"landmark_seen": 2.0, "landmark_secret": 2.0, "codex_read": 1.0, "nano_node": 2.0, "elite_kill": 1.0, "duel_won": 2.0}
const TRIBULATION_RETRY_SECONDS := 3600.0

var insight := 0.0
var dao_heart := 0.0               # % to qi, damage and life
var tribulation := {}              # {"from_level", "from_tag", "target", "tries"} while one is under way


func insight_need(r: int = -1) -> int:
	if r < 0:
		r = realm
	if r < INSIGHT_NEED.size():
		return int(INSIGHT_NEED[r])
	return int(INSIGHT_NEED[-1]) + 150 * (r - INSIGHT_NEED.size() + 1)


func gain_insight(n: float, why: String = "") -> void:
	if n <= 0.0:
		return
	n *= tech_effect("insight_mult", 1.0)          # round 40: Connection
	var before := insight
	insight += n
	if before < insight_need() and insight >= insight_need():
		message.emit("COMPREHENSION: you understand enough to break through to %s -- once the sea of qi is full and your ring is open." % realm_info(realm + 1)["name"])
	stats_changed.emit()


func _insight_from_event(kind: String, data: Dictionary) -> void:
	## (log_event calls this: insight follows what you DO for the first time)
	if INSIGHT_FOR.has(kind):
		# round 57: things you can do again and again (elites come back with the
		# floor) only teach so much in a day -- comprehension is for new things
		var caps: Dictionary = economy_data().get("insight_daily_caps", {})
		if caps.has(kind):
			var ck := "insight_day:" + kind
			var rec = flags.get(ck, {})
			if not (rec is Dictionary) or str(rec.get("day", "")) != today():
				rec = {"day": today(), "n": 0.0}
			if float(rec["n"]) >= float(caps[kind]):
				return
			rec["n"] = float(rec["n"]) + float(INSIGHT_FOR[kind])
			flags[ck] = rec
		gain_insight(float(INSIGHT_FOR[kind]), kind)
	elif kind == "art_stage":
		gain_insight({"Fluent": 3.0, "Mastered": 5.0, "Transcendent": 8.0}.get(str(data.get("stage", "")), 0.0), "art")
	elif kind == "technique" and str(data.get("source", "")) == "glimpse":
		gain_insight(2.0, "glimpse")


func at_threshold() -> bool:
	return sublevel == SUBLEVELS and qi >= qi_to_next() - 0.001


func breakthrough_missing() -> Array:
	## what still stands between you and the next realm ([] = ready)
	var out := []
	if not at_threshold():
		out.append(I18n.t("a full sea of qi (%s, %d%%)") % [cultivation_label(), int(100.0 * qi / maxf(qi_to_next(), 1.0))])
	if insight < insight_need():
		out.append(I18n.t("insight %d / %d") % [int(insight), insight_need()])
	var ring := realm + 1
	if ring <= 6 and not ring_complete(ring):
		var open_n := 0
		for p in lattice_data().get("points", []):
			if int(p["ring"]) == ring and lattice.has(str(p["id"])):
				open_n += 1
		out.append(I18n.t("the %s ring open (%d / 6)") % [_ordinal(ring), open_n])
	var wait := float(flags.get("tribulation_wait", 0.0)) - Time.get_unix_time_from_system()
	if wait > 0.0:
		out.append(I18n.t("an hour's rest after the last tribulation (%d min)") % int(ceil(wait / 60.0)))
	return out


func breakthrough_ready() -> bool:
	return breakthrough_missing().is_empty()


func favored_family() -> String:
	## the art family you lean on most (the heart demon leans on it too)
	var best := "strike"
	var bm := -1.0
	for fam in ["strike", "step", "guard"]:
		var m := 0.0
		for aid in arts:
			if art_family(str(aid)) == fam:
				m += float(arts[aid].get("m", 0.0)) + float(arts[aid].get("u", 0.0))
		if m > bm:
			bm = m
			best = fam
	return best


func heart_demon_def() -> Dictionary:
	## your own shape: as hard to wear down as you hit, hitting as you'd hurt
	var mh := max_hp()
	var dmg := damage()
	return {"name": "Your Heart Demon", "model": "human", "tint": [0.2, 0.12, 0.28], "scale": 1.0, "boss": true,
		"hp": int(maxf(dmg * (16.0 + 2.0 * realm), mh * 1.2)), "damage": int(maxf(mh * 0.065, 4.0)),
		"speed": 4.2, "cooldown": 1.3, "range": 1.9, "aggro": 30.0, "qi": 0, "loot": {}, "kind": "sword",
		"favored": favored_family(), "realm": realm}


func tribulation_def(level_id: String) -> Dictionary:
	enemies["heart_demon"] = heart_demon_def()
	var R := 8
	var size := R * 2 + 5
	var c := Vector2i(size / 2, size / 2)
	var rows := []
	for y in size:
		var row := ""
		for x in size:
			var d := Vector2(x - c.x, y - c.y).length()
			row += "." if d <= R + 0.3 else " "
		rows.append(row)
	var put := func(q: Vector2i, ch: String) -> void:
		var row: String = rows[q.y]
		rows[q.y] = row.substr(0, q.x) + ch + row.substr(q.x + 1)
	for i in 6:
		var a := TAU * i / 6.0
		put.call(c + Vector2i(int(round(cos(a) * (R - 1))), int(round(sin(a) * (R - 1)))), "L")
	put.call(Vector2i(c.x, c.y - 4), "D")
	put.call(Vector2i(c.x, c.y + 5), "P")
	return {"id": level_id, "name": "The Tribulation -- %s" % realm_info(realm + 1)["name"], "theme": "dungeon", "look": "mirror",
		"depth": maxi(depth, 1), "no_expand": true, "map": rows, "enemies": {"D": "heart_demon"}, "exits": {}, "tribulation": true}


func begin_tribulation() -> String:
	var miss := breakthrough_missing()
	if not miss.is_empty():
		return I18n.t("Not yet -- you still need %s.") % ", ".join(miss)
	tribulation = {"from_level": current_level, "from_tag": spawn_tag if spawn_tag != "" else "P", "target": realm + 1,
		"tries": int(counters.get("tribulations_tried:%d" % (realm + 1), 0.0))}
	bump("tribulations_tried:%d" % (realm + 1))
	log_event("tribulation_start", {"target": realm + 1})
	message.emit("TRIBULATION: the world folds away. Something stands up out of you.")
	go_to("tribulation:%d" % (realm + 1), "P")
	return ""


func tribulation_won() -> void:
	if tribulation.is_empty():
		return
	var first := int(tribulation.get("tries", 0)) == 0
	qi = 0.0
	var snap0 := stat_snapshot()
	realm += 1
	sublevel = 1
	hp = max_hp()
	level_up_note(snap0, "realm")                    # round 36
	jingle("trial")                                  # round 146: a breakthrough has its own fanfare
	slow_mo(0.25, 0.45)
	dao_heart += 2.0 if first else 1.0
	if not ("Heart Unshaken" in titles):
		titles.append(I18n.t("Heart Unshaken"))
	message.emit(I18n.t("BREAKTHROUGH -- you enter %s! Your heart demon was you, and you were stronger. (Dao Heart +%d%%%s)") % [
		realm_name(), 2 if first else 1, ", first try" if first else ""])
	log_event("breakthrough", {"realm": realm_name(), "tribulation": true, "first_try": first})
	if blood_awake() and blood_dominant() != "":
		add_purity(blood_dominant(), float(blood_data().get("gain", {}).get("breakthrough", 2.0)), "breakthrough")
	if steam:
		steam.stat("realm", realm)
	var back_l := str(tribulation.get("from_level", "village"))
	var back_t := str(tribulation.get("from_tag", "P"))
	tribulation = {}
	stats_changed.emit()
	go_to(back_l, back_t)


func tribulation_lost() -> void:
	var fams := ["strike", "guard", "step"]
	var fam: String = fams[randi() % fams.size()]
	injury[fam] = 300.0
	flags["tribulation_wait"] = Time.get_unix_time_from_system() + TRIBULATION_RETRY_SECONDS
	hp = max_hp()
	meditating = false
	message.emit("The heart demon throws you out of yourself. Your %s meridian is torn; your qi is still there. Rest an hour, and face it again." % fam)
	log_event("tribulation_lost", {"target": int(tribulation.get("target", realm + 1))})
	var back_l := str(tribulation.get("from_level", "village"))
	var back_t := str(tribulation.get("from_tag", "P"))
	tribulation = {}
	stats_changed.emit()
	go_to(back_l, back_t)


func dao_heart_effect() -> Dictionary:
	if dao_heart <= 0.0:
		return {}
	var m := 1.0 + dao_heart / 100.0
	return {"qi_mult": m, "damage_mult": m, "hp_mult": m}


func _grandfather_insight() -> void:
	## a save from before comprehension: what you've already done counts
	var places := 0
	for pid in journal.get("places", {}):
		places += 1
	var stages := 0.0
	for aid in arts:
		stages += {0: 0.0, 1: 3.0, 2: 8.0, 3: 16.0}.get(art_stage(str(aid)), 0.0)
	insight = 2.0 * places + float(lore_read.size()) + stages + 3.0 * discoveries.size() + float(tower_cleared_total())
	# ...and anyone already deep in a realm isn't stopped at a door they couldn't have known about
	insight = maxf(insight, float(insight_need(maxi(realm - 1, 0))))


func tower_cleared_total() -> int:
	var n := 0
	for t in towers:
		n += int(towers[t])
	return n



# ======================================================================
# Round 26 -- Dev's landmarks, codex and rumours in the valley.
# Landmarks: Landmark.gd (placed by Valley.gd). Rumours: Game.rumour.
# The nanite codex: a cultivator's notebook about the nanites, one entry
# per realm-band (Dev's words); an entry opens to you when your
# cultivation reaches its realm, and reading it (the journal) is insight.
# ======================================================================

const CODEX_REALM := {"body tempering": 0, "qi condensation": 1, "foundation establishment": 2, "core formation": 3,
	"nascent soul": 4, "soul transformation": 5}


func codex_entries() -> Array:
	## [{name, realm, text, open, new}] in realm order
	var out := []
	for e in valley_data().get("codex", []):
		var r := int(CODEX_REALM.get(str(e.get("realm", "")).to_lower(), 0))
		out.append({"name": str(e.get("name", "")), "realm": r, "text": str(e.get("text", "")), "open": r <= realm,
			"new": r <= realm and not has_flag("codex:" + str(e.get("name", "")))})
	out.sort_custom(func(a, b): return int(a["realm"]) < int(b["realm"]))
	return out


func read_codex() -> int:
	## the journal shows the codex: every newly opened entry is read now (+1 insight each)
	var n := 0
	for e in codex_entries():
		if bool(e["new"]):
			set_flag("codex:" + str(e["name"]))
			log_event("codex_read", {"name": e["name"]})
			n += 1
	return n


# ======================================================================
# Round 27 -- the whole body's gear, materials that mean something, the
# bench where anything meets anything, and the nanotech tree.
# Robert, 2026-10-03: "an actual inventory with an equipment dummy ... 4
# rings per hand, one bracelet on each wrist, one choker, one necklace, 2
# toe rings, boots, greaves, pauldrons, gloves, vambraces, gauntlets, chest,
# pants, under-armour gear, robes that can be on the outside of armour, cape
# and cowl. These items can be nano tech or crafted or both. Create a
# nanotech crafting tree, allow for all items to be combined in some way,
# allow recipes to be bought or created through trial and error. Allow for
# items, reagents, ores, gems and plants to have different attributes that
# can be combined with other materials to create synergistic effects or
# improve the odds of success, failure and unexpected benefits."
#
#   GEAR (data/gear.json): 27 slots. Armour pieces give health and WARD
#     (blows lose ward/(ward+200) of themselves) and weigh something: over
#     what you can carry (more with every realm) you move and swing slower.
#     Jewellery carries gifts from its gem; many pieces of jewellery stack
#     with diminishing returns. The catalogue (g_<stock>_<family>,
#     j_<metal>_<gem>_<family>) is generated here from the stocks.
#   MATERIALS (data/crafting.json): every material has an element and
#     traits (hard, supple, vital, keen, conductive, resonant, warding,
#     volatile, binding, nano, seeking, living). Traits become effects on
#     what they're worked into; pairs of traits make SYNERGIES; binding
#     steadies a mix, volatility risks it; elements that feed each other
#     help, elements that fight hurt -- and surprise more often.
#   THE BENCH: anything with anything (Game.combine_attempt): gear + materials
#     = an infused piece; materials + materials = an alloy (or, if it's a
#     known FORMULA, its product); a consumable + materials = a stronger
#     one; two pieces of a kind = one (Singularity Forge). Formulas are
#     bought as scrolls (smiths, merchants, alchemists) or found by trying
#     the right things together.
#   FORGING: make any piece from a stock material (Game.forge_piece).
#   THE NANOFORGE (data/nanotech.json): nodes unlocked with nanite shards at
#     your swarm's tier; they open nano classes (nanoweave, lattice,
#     swarm-shell), circuit jewellery, hybrids, self-repair... Two are
#     secrets, found by experimenting.
# ======================================================================

const ADDITIVE_KEYS := ["sight", "gather_bonus", "heal_on_kill", "dash", "sense_radius", "burst_radius", "keep_gold", "gather_chance", "ward", "regen",
	"crit_chance", "dodge_chance", "burn_on_hit", "loot_luck", "rebirth", "low_hp_fury",        # (the last six: round 30, bloodlines)
	"timing"]                                                                                   # round 41: seconds added to the parry window and a roll's slip
const WEAR_TYPES := ["armor", "cowl", "cape", "pauldrons", "robe", "underarmour", "vambraces", "gloves", "gauntlets", "pants", "greaves", "boots"]
const JEWEL_TYPES := ["ring", "toering", "bracelet", "choker", "necklace", "amulet"]
const KIND_WEIGHT := {"dagger": 0.8, "sword": 2.0, "saber": 1.8, "spear": 3.0, "axe": 3.2, "hammer": 4.5, "halberd": 4.2, "staff": 1.8, "fists": 0.0, "bow": 1.2, "crossbow": 3.2, "ki": 0.0}

var formulas_known := {}      # formula id -> how ("bought", "found", "taught")
var nano_nodes := {}          # nanotech node id -> true
var mat_known := {}           # material id -> true: you've learned what it is
func road_bench() -> bool:
	## round 148: a folding table in your pack counts as a bench wherever you are
	var w = sys("workshop")
	return w != null and w.road_table()


func field_forge() -> bool:
	var w = sys("workshop")
	return w != null and w.field_forge()


func rune_table_anywhere() -> bool:
	var w = sys("workshop")
	return w != null and w.rune_table()


var world_frozen := false     # round 157: the menu holds the world still (set by Main); the player does not move or fall meanwhile
var at_bench := ""            # "" | "home" | "forge" | "workshop": where you're working (set by the UI)
var gear_def := {}
var craft_def := {}
var nanotech_def := {}


func gear_data() -> Dictionary:
	if gear_def.is_empty():
		gear_def = _load_json("res://data/gear.json", {"slots": [], "families": {}, "classes": {}, "stocks": {}, "jewel_metals": {}, "jewel_gems": []})
	return gear_def


func craft_data() -> Dictionary:
	if craft_def.is_empty():
		craft_def = _load_json("res://data/crafting.json", {"traits": {}, "synergies": [], "materials": {}, "products": {}, "formulas": [], "odds": {}})
	return craft_def


func nanotech_data() -> Dictionary:
	if nanotech_def.is_empty():
		nanotech_def = _load_json("res://data/nanotech.json", {"nodes": []})
	return nanotech_def


# ---- the catalogue ---------------------------------------------------------------

func _merge_round27_items() -> void:
	var cd := craft_data()
	for pid in cd.get("products", {}):
		var pr: Dictionary = cd["products"][pid]
		if not items.has(pid):
			items[pid] = {"name": pr.get("name", pid), "type": "material", "value": int(pr.get("value", 20)), "desc": pr.get("desc", ""), "product": true}
	for f in cd.get("formulas", []):
		if int(f.get("price", 0)) > 0:
			var mk := str(f.get("makes", ""))
			items["scroll_" + str(f["id"])] = {"name": I18n.t("Formula: %s") % items.get(mk, {}).get("name", mk), "type": "formula",
				"formula": str(f["id"]), "value": int(int(f["price"]) / 2), "desc": "A worked recipe, written down. %s" % f.get("hint", "")}
	var gd := gear_data()
	for stock in gd.get("stocks", {}):
		for fam in gd.get("families", {}):
			var fd: Dictionary = gd["families"][fam]
			if str(fd.get("kind", "")) != "wear":
				continue
			if not (str(gd["stocks"][stock].get("class", "")) in fd.get("classes", [])):
				continue
			var gid := gear_id(stock, fam)
			if not items.has(gid):
				items[gid] = piece_def(stock, fam)
	for metal in ["iron_ore", "silver_ore", "gold_nugget"]:
		for gem in gd.get("jewel_gems", []):
			for fam in ["ring", "toering", "bracelet", "choker", "necklace"]:
				var jid := "j_%s_%s_%s" % [metal, gem, fam]
				if not items.has(jid):
					items[jid] = jewel_def(metal, gem, fam)


func gear_id(stock: String, fam: String) -> String:
	return "g_%s_%s" % [stock, "chest" if fam == "armor" else fam]


func stock_info(id: String) -> Dictionary:
	## what a material is as something to make gear from: {name, class, tier,
	## color} -- a stock from gear.json, or an alloy of one (a tier better)
	var b := base_id(id)
	var st: Dictionary = gear_data().get("stocks", {}).get(b, {})
	if not st.is_empty():
		return st
	var d: Dictionary = items.get(b, {})
	if d.has("stock_of"):
		var under: Dictionary = gear_data().get("stocks", {}).get(str(d["stock_of"]), {})
		if not under.is_empty():
			var o := under.duplicate(true)
			o["tier"] = int(under.get("tier", 1)) + 1
			o["name"] = str(d.get("short", d.get("name", b)))
			return o
	return {}


func jewel_metal(id: String) -> Dictionary:
	var b := base_id(id)
	var jm: Dictionary = gear_data().get("jewel_metals", {}).get(b, {})
	if not jm.is_empty():
		return jm
	var d: Dictionary = items.get(b, {})
	if d.has("stock_of"):
		var under: Dictionary = gear_data().get("jewel_metals", {}).get(str(d["stock_of"]), {})
		if not under.is_empty():
			var o := under.duplicate(true)
			o["potency"] = float(under.get("potency", 1.0)) + 0.2
			o["name"] = str(d.get("short", d.get("name", b)))
			return o
	return {}


func piece_def(stock: String, fam: String, extra_traits: Dictionary = {}) -> Dictionary:
	var gd := gear_data()
	var st := stock_info(stock)
	var fd: Dictionary = gd["families"][fam]
	var cl: Dictionary = gd.get("classes", {}).get(str(st.get("class", "metal")), {})
	var t := int(st.get("tier", 1))
	var hp_ := int(round(36.0 * t * float(fd.get("share", 0.1)) * float(cl.get("hp", 1.0))))
	var ward_ := snappedf(float(fd.get("ward", 1.0)) * float(cl.get("ward", 1.0)) * (2.0 + t * 0.6), 0.1)
	var w := snappedf(float(fd.get("weight", 1.0)) * float(cl.get("weight", 1.0)), 0.1)
	# the material's own nature, lightly: its strongest trait
	var tr := material_traits(stock).duplicate()
	for k in extra_traits:
		tr[k] = int(tr.get(k, 0)) + int(extra_traits[k])
	var gift := traits_to_effect(_top_traits(tr, 1), 0.5 + 0.05 * t)
	gift.erase("craft_success")
	var name_ := "%s %s" % [st.get("name", stock), fd.get("name", fam)]
	return {"name": name_, "type": fam, "hp": hp_, "ward": ward_, "weight": w, "tier": t, "drop": not items.get(base_id(stock), {}).has("stock_of") and not str(cl.get("make", "")) == "nano",
		"value": int(6 + hp_ * 0.8 + ward_ * 5.0), "make": str(cl.get("make", "crafted")), "class": str(st.get("class", "metal")), "stock": base_id(stock),
		"color": st.get("color", [0.5, 0.5, 0.5]), "look": str(cl.get("look", "metal")), "effect": gift,
		"desc": I18n.t("%s, of %s. +%d health, %.1f ward, %.1f weight.") % [fd.get("name", fam), str(st.get("name", stock)).to_lower(), hp_, ward_, w]}


func jewel_def(metal: String, gem: String, fam: String) -> Dictionary:
	var gd := gear_data()
	var jm := jewel_metal(metal)
	var fd: Dictionary = gd["families"][fam]
	var power := float(fd.get("power", 1.0)) * float(jm.get("potency", 1.0))
	var eff := {}
	if gem != "":
		eff = traits_to_effect(_top_traits(material_traits(gem), 2), material_potency(gem) * power * 0.55)
	var mt := traits_to_effect(_top_traits(material_traits(metal), 1), power * 0.35)
	eff = merge_effects(eff, mt)
	var nm := "%s %s" % [jm.get("name", metal), fd.get("name", fam)]
	if gem != "":
		nm += I18n.t(" set with %s") % str(items.get(base_id(gem), {}).get("name", gem)).to_lower()
	var v := int(20 + 40 * power + float(items.get(base_id(gem), {}).get("value", 0)) * 1.5)
	return {"name": nm, "type": fam, "value": v, "weight": float(fd.get("weight", 0.05)), "effect": eff, "drop": true,
		"tier": int(round(power * 4)), "make": "nano" if bool(jm.get("nano", false)) else "crafted", "class": "jewel", "metal": base_id(metal), "gem": base_id(gem),
		"color": jm.get("color", [0.8, 0.8, 0.8]), "gem_color": _element_color(material_element(gem)) if gem != "" else [0.9, 0.9, 0.9],
		"desc": "%s. %s" % [nm, effect_text(eff)]}


func _element_color(el: String) -> Array:
	return {"wood": [0.3, 0.8, 0.4], "fire": [0.95, 0.3, 0.2], "earth": [0.85, 0.65, 0.3], "metal": [0.85, 0.88, 0.95], "water": [0.3, 0.55, 0.95]}.get(el, [0.8, 0.8, 0.8])


# ---- slots and wearing --------------------------------------------------------------

func gear_slots() -> Array:
	return gear_data().get("slots", [])


func slot_family(slot: String) -> String:
	for s in gear_slots():
		if str(s[0]) == slot:
			return str(s[2])
	return ""


func slot_name(slot: String) -> String:
	for s in gear_slots():
		if str(s[0]) == slot:
			return str(s[1])
	return slot


func gear_family(id: String) -> String:
	## what kind of slot this goes in ("" = not something you wear)
	if id == "" or not has_item_def(id):
		return ""
	var t := str(item_def(id).get("type", ""))
	if t == "amulet":
		return "necklace"
	if t == "weapon" or t in WEAR_TYPES or t in JEWEL_TYPES:
		return t
	return ""


func is_jewel(id: String) -> bool:
	return gear_family(id) in JEWEL_TYPES


func slots_for(fam: String) -> Array:
	var out := []
	for s in gear_slots():
		if str(s[2]) == fam:
			out.append(str(s[0]))
	return out


func worn(slot: String) -> String:
	if slot == "weapon":
		return weapon
	return str(equipment.get(slot, ""))


func equipped_count(id: String) -> int:
	if id == "":
		return 0
	var n := 1 if weapon == id else 0
	for sl in equipment:
		if str(equipment[sl]) == id:
			n += 1
	return n


func is_equipped(id: String) -> bool:
	return equipped_count(id) > 0


func wear(id: String, slot: String = "") -> String:
	var fam := gear_family(id)
	if fam == "":
		return I18n.t("You can't wear that.")
	if count(id) <= 0:
		return I18n.t("You don't have it.")
	var choices := slots_for(fam)
	if slot != "" and not (slot in choices):
		return I18n.t("That doesn't go there.")
	if slot == "":
		for c in choices:
			if worn(c) == "":
				slot = c
				break
		if slot == "":
			slot = choices[0] if choices.size() > 0 else ""
	if slot == "":
		return I18n.t("There's nowhere to wear it.")
	if worn(slot) == id:
		return I18n.t("You're already wearing it there.")
	if equipped_count(id) - (1 if worn(slot) == id else 0) >= count(id):
		return I18n.t("You only have %d, and %s already worn.") % [count(id), "it's" if count(id) == 1 else "they're all"]
	if slot == "weapon":
		weapon = id
	else:
		equipment[slot] = id
	log_event("equip", {"id": id, "slot": slot})
	stats_changed.emit()
	return I18n.t("You put on the %s (%s).") % [item_name(id), slot_name(slot).to_lower()]


func unequip(slot: String) -> String:
	var id := worn(slot)
	if id == "":
		return ""
	if slot == "weapon":
		weapon = ""
	else:
		equipment.erase(slot)
	stats_changed.emit()
	return I18n.t("You take off the %s.") % item_name(id)


func _fix_equipment(id: String) -> void:
	## gone from the pack, gone from your body
	while equipped_count(id) > count(id):
		if weapon == id:
			weapon = ""
			continue
		for sl in equipment.keys():
			if str(equipment[sl]) == id:
				equipment.erase(sl)
				break


func _piece_score(id: String) -> float:
	if id == "" or not has_item_def(id):
		return 0.0
	var d := item_def(id)
	return float(d.get("hp", 0)) + 6.0 * piece_ward(id)


func _auto_wear(id: String) -> void:
	## found something to wear: an empty slot takes it, and a clearly better
	## piece replaces what's there (one less menu to dig through)
	var fam := gear_family(id)
	if fam == "" or fam == "weapon":
		return
	var choices := slots_for(fam)
	for c in choices:
		if worn(c) == "":
			wear(id, c)
			message.emit("You put on the %s." % item_name(id))
			return
	if fam in WEAR_TYPES and choices.size() > 0 and _piece_score(id) > _piece_score(worn(choices[0])) * 1.1 + 1.0:
		wear(id, choices[0])
		message.emit("Equipped %s." % item_name(id))


# ---- what it all adds up to -------------------------------------------------------

func piece_ward(id: String) -> float:
	if id == "" or not has_item_def(id):
		return 0.0
	var d := item_def(id)
	if d.has("ward"):
		var m := 1.0
		if base_id(id) != id:
			m = float(QUALITY[quality_index(id)]["mult"])
		return float(d["ward"]) * m
	if str(d.get("type", "")) == "armor":
		return float(d.get("hp", 0)) / 12.0        # the older armour: ward from its weight of plate
	return 0.0


func piece_weight(id: String) -> float:
	if id == "" or not has_item_def(id):
		return 0.0
	var d := item_def(id)
	if d.has("weight"):
		return float(d["weight"])
	match str(d.get("type", "")):
		"weapon":
			return float(KIND_WEIGHT.get(str(d.get("kind", "sword")), 2.0))
		"armor":
			var light := false
			for w in ["robe", "vest", "weave", "silk", "wrap", "vestment", "leathers", "coat"]:
				if str(d.get("name", "")).to_lower().contains(w):
					light = true
			return (3.0 + float(d.get("hp", 0)) / 80.0) * (0.5 if light else 1.0)
	return 0.1


func worn_ids() -> Array:
	var out := []
	for s in gear_slots():
		var id := worn(str(s[0]))
		if id != "" and count(id) > 0:
			out.append(id)
	return out


func worn_hp() -> int:
	var t := 0
	for sl in equipment:
		var id := str(equipment[sl])
		if id != "" and has_item_def(id) and gear_family(id) in WEAR_TYPES:
			t += int(item_def(id).get("hp", 0))
	return t


func total_ward() -> float:
	var w := 0.0
	for sl in equipment:
		var id := str(equipment[sl])
		if id != "" and gear_family(id) in WEAR_TYPES:
			w += piece_ward(id)
	return w + tech_effect("ward", 0.0)


func ward_factor() -> float:
	var w := maxf(total_ward(), 0.0)
	var k := float(gear_data().get("ward_k", 200.0))
	return k / (k + w)


func total_weight() -> float:
	var t := 0.0
	for id in worn_ids():
		t += piece_weight(id)
	return t * nano_gift_mult("gear_weight")


func carry_capacity() -> float:
	var w: Dictionary = gear_data().get("weight", {})
	return float(w.get("carry", 22.0)) + float(w.get("per_realm", 9.0)) * realm + float(w.get("per_step", 0.6)) * step_index()


func weight_penalty() -> float:
	## 0 .. slow: how much slower all that weight makes you
	var over := total_weight() - carry_capacity()
	if over <= 0.0:
		return 0.0
	var w: Dictionary = gear_data().get("weight", {})
	return float(w.get("slow", 0.25)) * clampf(over / maxf(carry_capacity(), 1.0), 0.0, 1.0)


func gear_effects() -> Array:
	## the effects of everything worn: armour pieces as they are, jewellery
	## pooled (each extra gift of the same kind counts for less), the nano
	## tree's gifts per nano piece, and the cost of carrying it all
	var out := []
	var pool := {}           # key -> summed bonus (mult keys as v-1)
	var nano_n := 0
	var nano_jewels := 0
	for s in gear_slots():
		var sl := str(s[0])
		var id := worn(sl)
		if id == "" or count(id) <= 0 or not has_item_def(id):
			continue
		var d := item_def(id)
		if str(d.get("make", "")) in ["nano", "both"]:
			nano_n += 1
			if is_jewel(id):
				nano_jewels += 1
		if not d.has("effect"):
			continue
		var e := jewel_effect(id)
		if is_jewel(id):
			for k in e:
				if e[k] is Dictionary:
					continue
				var add := float(e[k]) if (k in ADDITIVE_KEYS or str(k).begins_with("craft_")) else float(e[k]) - 1.0
				pool[k] = float(pool.get(k, 0.0)) + add
		else:
			out.append(e)
	var jd := {}
	for k in pool:
		var v := float(pool[k])
		var additive: bool = k in ADDITIVE_KEYS or str(k).begins_with("craft_")
		if not additive:
			var a := absf(v)
			if a > 0.10:
				a = 0.10 + (a - 0.10) * 0.4        # the second ring of the same kind gives less
			a = minf(a, 0.35)
			v = signf(v) * a
			jd[k] = 1.0 + v
		else:
			jd[k] = v
	if not jd.is_empty():
		out.append(jd)
	var nd := {}
	if nano_n > 0:
		if nano_gift("nano_regen") > 0.0:
			nd["regen"] = nano_gift("nano_regen") * nano_n
		if nano_gift("nano_swarm") > 0.0:
			nd["swarm_mult"] = 1.0 + nano_gift("nano_swarm") * nano_n
		if nano_gift("jewel_speed") > 0.0 and nano_jewels > 0:
			nd["attack_speed"] = 1.0 + nano_gift("jewel_speed") * nano_jewels
	if not nd.is_empty():
		out.append(nd)
	var pen := weight_penalty()
	if pen > 0.0:
		out.append({"move_mult": 1.0 - pen, "attack_speed": 1.0 - pen * 0.5})
	return out


func gear_summary() -> Dictionary:
	return {"hp": worn_hp(), "ward": snappedf(total_ward(), 0.1), "cut": int(round((1.0 - ward_factor()) * 100.0)),
		"weight": snappedf(total_weight(), 0.1), "carry": snappedf(carry_capacity(), 0.1), "slow": int(round(weight_penalty() * 100.0)),
		"nano": worn_ids().filter(func(i): return str(item_def(i).get("make", "")) in ["nano", "both"]).size()}


func merge_effects(a: Dictionary, b: Dictionary, scale: float = 1.0) -> Dictionary:
	var o := a.duplicate(true)
	for k in b:
		if b[k] is Dictionary:
			continue
		var v := float(b[k])
		if k in ADDITIVE_KEYS or str(k).begins_with("craft_"):
			o[k] = snappedf(float(o.get(k, 0.0)) + v * scale, 0.001)
		else:
			o[k] = snappedf(float(o.get(k, 1.0)) * (1.0 + (v - 1.0) * scale), 0.0001)
	return o


# ---- materials: what things ARE ---------------------------------------------------

const TRAIT_WORDS := {
	"hard": ["iron", "steel", "ore", "plate", "stone", "scale", "shell", "slag"],
	"supple": ["silk", "thread", "cloth", "hide", "leather", "oil", "weave", "feather"],
	"vital": ["herb", "blood", "heart", "sap", "fruit", "salve", "meat"],
	"keen": ["tooth", "fang", "blade", "edge", "claw", "thorn", "venom", "sword", "spine"],
	"conductive": ["silver", "crystal", "glass", "copper", "eel", "wire", "spark", "storm"],
	"resonant": ["jade", "pearl", "bell", "song", "sing", "moon", "dream", "echo"],
	"warding": ["bone", "ward", "mirror", "shield", "bark", "clay", "frost"],
	"volatile": ["fire", "ember", "flame", "ash", "sulfur", "thunder", "lightning", "burn"],
	"binding": ["resin", "glue", "clay", "seal", "gold", "wax", "root"],
	"nano": ["nanite", "cog", "core", "machine", "circuit", "gear", "brass"],
	"seeking": ["dust", "spore", "eye", "star", "compass", "glow"],
	"living": ["petal", "flower", "moss", "seed", "spore", "leaf", "carp", "root", "fish"],
}


func material_traits(id: String) -> Dictionary:
	## {trait: level 1..5}: from crafting.json, from what an alloy was made of,
	## or -- for anything the forge adds later -- read from its name
	var b := base_id(id)
	if b == "":
		return {}
	var cd := craft_data()
	if cd.get("materials", {}).has(b):
		return cd["materials"][b].get("traits", {})
	if cd.get("products", {}).has(b):
		return cd["products"][b].get("traits", {})
	var d: Dictionary = items.get(b, {})
	if d.has("traits"):
		return d["traits"]
	match str(d.get("type", "")):
		"consumable":
			var t := {}
			if d.has("heal"):
				t["vital"] = 2
			if d.has("qi"):
				t["conductive"] = 2
			return t if not t.is_empty() else {"binding": 1}
		"treasure", "currency", "formula", "":
			return {}
	if d.has("stock") and items.has(str(d["stock"])):
		var st := material_traits(str(d["stock"])).duplicate()
		if str(d.get("type", "")) == "weapon":
			st["keen"] = int(st.get("keen", 0)) + 1
		return st
	if d.has("gem") and str(d["gem"]) != "":
		return material_traits(str(d["gem"]))
	var text := (str(d.get("name", b)) + " " + str(d.get("desc", ""))).to_lower()
	var out := {}
	for tr in TRAIT_WORDS:
		for w in TRAIT_WORDS[tr]:
			if text.contains(w):
				out[tr] = mini(int(out.get(tr, 0)) + 1, 3)
				break
	if str(d.get("type", "")) == "weapon":
		out["keen"] = int(out.get("keen", 0)) + 1
	if str(d.get("type", "")) in WEAR_TYPES:
		out["warding"] = int(out.get("warding", 0)) + 1
	if out.is_empty():
		out = {"binding": 1}
	return _top_traits(out, 3)


func material_element(id: String) -> String:
	var b := base_id(id)
	var cd := craft_data()
	if cd.get("materials", {}).has(b):
		return str(cd["materials"][b].get("element", "earth"))
	if cd.get("products", {}).has(b):
		return str(cd["products"][b].get("element", "earth"))
	var d: Dictionary = items.get(b, {})
	if d.has("element"):
		return str(d["element"])
	if d.has("stock"):
		return material_element(str(d["stock"]))
	var best := ""
	var bv := 0
	for tr in material_traits(id):
		if int(material_traits(id)[tr]) > bv:
			bv = int(material_traits(id)[tr])
			best = str(tr)
	return {"hard": "metal", "keen": "metal", "supple": "wood", "vital": "wood", "living": "wood", "volatile": "fire", "seeking": "fire",
		"warding": "earth", "binding": "earth", "conductive": "water", "resonant": "water", "nano": "metal"}.get(best, "earth")


func material_potency(id: String) -> float:
	## 1 (common) .. 5 (a boss's heart): how strongly its traits come through
	var v := float(items.get(base_id(id), {}).get("value", 4))
	var q := float(QUALITY[quality_index(id)]["mult"]) if base_id(id) != id else 1.0
	return clampf(1.0 + 0.5 * log(maxf(v, 4.0) / 4.0) / log(2.0), 1.0, 5.0) * q


func _top_traits(t: Dictionary, n: int) -> Dictionary:
	var keys := t.keys()
	keys.sort_custom(func(a, b): return int(t[a]) > int(t[b]) or (int(t[a]) == int(t[b]) and str(a) < str(b)))
	var o := {}
	for i in mini(n, keys.size()):
		o[keys[i]] = t[keys[i]]
	return o


func traits_to_effect(t: Dictionary, scale: float) -> Dictionary:
	var td: Dictionary = craft_data().get("traits", {})
	var e := {}
	for tr in t:
		var def: Dictionary = td.get(tr, {})
		if def.is_empty():
			continue
		var key := str(def["effect"])
		var amt := float(def.get("per", 0.01)) * float(t[tr]) * scale
		if key in ADDITIVE_KEYS or key.begins_with("craft_"):
			e[key] = snappedf(float(e.get(key, 0.0)) + amt, 0.001)
		else:
			e[key] = snappedf(float(e.get(key, 1.0)) * (1.0 + amt), 0.0001)
	return e


func trait_name(tr: String) -> String:
	return str(craft_data().get("traits", {}).get(tr, {}).get("name", tr.capitalize()))


func knows_material(id: String) -> bool:
	## you know what something IS once you've worked it, studied it, or know your craft well
	var b := base_id(id)
	return mat_known.has(b) or items.get(b, {}).has("traits") or craft_data().get("products", {}).has(b) \
		or skill_level("alchemy") >= 6 or skill_level("jewelcrafting") >= 6 or skill_level("smithing") >= 8


func traits_text(id: String) -> String:
	if not knows_material(id):
		return I18n.t("traits unknown -- work it, or study it")
	var t := material_traits(id)
	var parts := []
	for tr in _top_traits(t, 5):
		parts.append("%s %d" % [trait_name(tr), int(t[tr])])
	return "%s · %s" % [material_element(id), ", ".join(parts)]


func study_material(id: String) -> String:
	## give one up to learn what it is
	if knows_material(id):
		return I18n.t("You already know what %s is.") % item_name(id)
	if count(id) <= 0 or is_treasure(id) or is_equipped(id) and count(id) <= equipped_count(id):
		return I18n.t("You need one to spare.")
	remove_item(id, 1)
	mat_known[base_id(id)] = true
	add_skill_xp("alchemy", 4.0, I18n.t("studying ") + item_name(id))
	log_event("study", {"id": base_id(id)})
	return I18n.t("You break it down and learn it: %s -- %s.") % [item_name(id), traits_text(id)]


# ---- formulas ---------------------------------------------------------------------

func formula_def(fid: String) -> Dictionary:
	for f in craft_data().get("formulas", []):
		if str(f.get("id", "")) == fid:
			return f
	return {}


func knows_formula(fid: String) -> bool:
	if formulas_known.has(fid):
		return true
	for n in nano_nodes:
		if str(nano_node_def(str(n)).get("gives", {}).get("formula", "")) == fid:
			return true
	return false


func formula_usable(fid: String) -> bool:
	## a nano formula needs its node: the swarm has to know how to hold it
	var f := formula_def(fid)
	return f.has("needs") and (str(f.get("node", "")) == "" or nano_has(str(f["node"])))


func learn_formula(fid: String, how: String = "found") -> bool:
	if fid == "" or formula_def(fid).is_empty() or formulas_known.has(fid):
		return false
	formulas_known[fid] = how
	var f := formula_def(fid)
	message.emit(I18n.t("FORMULA: %s -- %s.") % [item_name(str(f.get("makes", fid))), recipe_text({"needs": f.get("needs", {})})])
	log_event("formula", {"id": fid, "how": how})
	return true


func formula_scrolls_for(role: String) -> Array:
	## [[id, price]] -- the formula scrolls this kind of trader has, a few a day
	var out := []
	var day := int(Time.get_unix_time_from_system() / 86400.0)
	var i := 0
	for f in craft_data().get("formulas", []):
		i += 1
		if int(f.get("price", 0)) <= 0 or not (role in f.get("sold", [])) or formulas_known.has(str(f["id"])):
			continue
		if (i + day) % 3 == 0 and out.size() > 0:
			continue               # not every scroll every day
		out.append(["scroll_" + str(f["id"]), int(f["price"])])
	return out


func formula_for(ids: Array) -> String:
	## the formula these things make together ("" = none): the same set of
	## materials, whatever the order
	var want := {}
	for id in ids:
		want[base_id(str(id))] = true
	for f in craft_data().get("formulas", []):
		var needs: Dictionary = f.get("needs", {})
		if needs.size() != want.size():
			continue
		var ok := true
		for k in needs:
			if not want.has(str(k)):
				ok = false
				break
		if ok:
			return str(f["id"])
	return ""


# ---- the bench: anything with anything ----------------------------------------------

func _bench_kind(base: String, adds: Array) -> String:
	if gear_family(base) != "":
		for a in adds:
			if gear_family(str(a)) == gear_family(base):
				return "merge"
		return "infuse"
	match str(item_def(base).get("type", "")):
		"consumable":
			return "brew"
		"material":
			return "alloy"
	return ""


func _combine_skill(base: String, kind: String, fid: String) -> String:
	if fid != "":
		return str(formula_def(fid).get("skill", "smithing"))
	if kind == "brew":
		return "alchemy" if item_def(base).has("qi") else "medicine"
	if kind in ["infuse", "merge"]:
		if is_jewel(base):
			return "jewelcrafting"
		return str(gear_data().get("classes", {}).get(str(item_def(base).get("class", "metal")), {}).get("skill", "smithing"))
	return {"metal": "smithing", "fire": "smithing", "earth": "jewelcrafting", "wood": "alchemy", "water": "alchemy"}.get(material_element(base), "alchemy")


func _sum_traits(ids: Array) -> Dictionary:
	var t := {}
	for id in ids:
		var mt := material_traits(str(id))
		for k in mt:
			t[k] = int(t.get(k, 0)) + int(mt[k])
	return t


func synergies_in(t: Dictionary) -> Array:
	var out := []
	for sy in craft_data().get("synergies", []):
		if int(t.get(str(sy["a"]), 0)) > 0 and int(t.get(str(sy["b"]), 0)) > 0:
			out.append(sy)
	return out


func combine_check(base: String, adds: Array) -> String:
	## "" if you can try it, else why not
	if base == "" or adds.is_empty():
		return I18n.t("Put something on the bench and something to work into it.")
	if adds.size() > 3:
		return I18n.t("Three things at most into one.")
	var need := {base: 1}
	for a in adds:
		need[str(a)] = int(need.get(str(a), 0)) + 1
	for id in need:
		if is_treasure(id) or str(item_def(id).get("type", "")) in ["currency", "formula", "treasure"] or not has_item_def(id):
			return I18n.t("%s can't be worked.") % item_name(id)
		if count(id) < int(need[id]):
			return I18n.t("You need %d %s.") % [int(need[id]), item_name(id)]
	var kind := _bench_kind(base, adds)
	if kind == "":
		return I18n.t("Nothing can be worked into %s.") % item_name(base)
	if kind == "merge" and not nano_has("singularity_forge"):
		return I18n.t("Two pieces into one needs the Singularity Forge (Nanoforge).")
	if kind in ["infuse", "merge"] and int(item_def(base).get("infusions", 0)) >= max_infusions(base):
		return I18n.t("%s can't hold anything more.") % item_name(base)
	return ""


func max_infusions(id: String) -> int:
	var arr: Array = craft_data().get("infusions", [2, 2, 3, 4, 5])
	return int(arr[clampi(int(item_def(id).get("qrank", quality_index(id))), 0, arr.size() - 1)])


func combine_preview(base: String, adds: Array) -> Dictionary:
	var why := combine_check(base, adds)
	var o: Dictionary = craft_data().get("odds", {})
	var all_ids := [base] + adds
	var fid := formula_for(all_ids)
	if fid != "" and not formula_usable(fid):
		fid = ""
	var kind := "formula" if fid != "" else _bench_kind(base, adds)
	if fid != "" and why == "":
		for k in formula_def(fid).get("needs", {}):
			if count(str(k)) < int(formula_def(fid)["needs"][k]):
				why = (I18n.t("You need %d %s for %s.") % [int(formula_def(fid)["needs"][k]), item_name(str(k)), item_name(str(formula_def(fid)["makes"]))]) if knows_formula(fid) \
					else "It feels close -- as if it wants more of one of these."
	var t := _sum_traits(adds if kind in ["infuse", "merge"] else all_ids)
	var syn := synergies_in(t)
	var steady := false
	for sy in syn:
		if bool(sy.get("steadies", false)):
			steady = true
	var be := material_element(base)
	var gen := 0
	var over := 0
	for a in adds:
		var ae := material_element(str(a))
		if ae == be:
			continue
		if GENERATES.get(be, "") == ae or GENERATES.get(ae, "") == be:
			gen += 1
		elif OVERCOMES.get(be, "") == ae or OVERCOMES.get(ae, "") == be:
			over += 1
	var sk := _combine_skill(base, kind, fid)
	var c := float(o.get("base", 0.55)) + float(o.get("per_skill", 0.03)) * skill_level(sk)
	c += float(o.get("binding", 0.045)) * int(t.get("binding", 0))
	if not steady:
		c += float(o.get("volatile", -0.05)) * int(t.get("volatile", 0))
	c += float(o.get("generates", 0.07)) * gen + float(o.get("overcomes", -0.06)) * over
	if fid != "":
		c -= 0.03 * int(formula_def(fid).get("difficulty", 0))
		if knows_formula(fid):
			c += float(o.get("formula", 0.22))
	if kind in ["infuse", "merge"]:
		c -= 0.06 * int(item_def(base).get("infusions", 0))
	if at_bench == "" and not road_bench():
		c += float(o.get("no_bench", -0.12))
	c += nano_gift("combine_success") + tech_effect("craft_success", 0.0) + tech_effect("craft_success_" + sk, 0.0)
	c += 0.05 * focus_bonus(sk)
	c = clampf(c, float(o.get("min", 0.08)), float(o.get("max", 0.96)))
	var luck := float(o.get("luck_base", 0.05)) + float(o.get("luck_volatile", 0.03)) * int(t.get("volatile", 0))
	luck += float(o.get("luck_resonant", 0.015)) * int(t.get("resonant", 0)) + float(o.get("luck_overcomes", 0.04)) * over + nano_gift("luck")
	luck = clampf(luck, 0.0, 0.4)
	var known_t := {}
	var hidden := 0
	for id in (adds if kind in ["infuse", "merge"] else all_ids):
		if knows_material(str(id)):
			var mt := material_traits(str(id))
			for k in mt:
				known_t[k] = int(known_t.get(k, 0)) + int(mt[k])
		else:
			hidden += 1
	var notes := []
	if gen > 0:
		notes.append(I18n.t("the elements feed each other"))
	if over > 0:
		notes.append(I18n.t("the elements fight (riskier -- and more surprising)"))
	if int(t.get("volatile", 0)) >= 3 and not steady:
		notes.append(I18n.t("volatile: it could go badly"))
	if steady:
		notes.append(I18n.t("bound: the volatility is caged"))
	if at_bench == "" and not road_bench():
		notes.append(I18n.t("no proper bench here"))
	if fid != "" and knows_formula(fid):
		notes.append(I18n.t("you know this formula"))
	if hidden > 0:
		notes.append(I18n.t("%d thing%s you don't understand yet") % [hidden, "" if hidden == 1 else "s"])
	var syn_names := []
	for sy in syn:
		if _syn_visible(sy, known_t):
			syn_names.append(str(sy["name"]))
	return {"ok": why == "", "why": why, "kind": kind, "formula": fid if (fid != "" and knows_formula(fid)) else "", "chance": c, "luck": luck,
		"skill": sk, "traits": known_t, "synergies": syn_names, "notes": notes, "steady": steady, "over": over, "gen": gen, "volatile": int(t.get("volatile", 0)),
		"_fid": fid, "_t": t, "_syn": syn}


func _syn_visible(sy: Dictionary, known_t: Dictionary) -> bool:
	return int(known_t.get(str(sy["a"]), 0)) > 0 and int(known_t.get(str(sy["b"]), 0)) > 0


func combine_attempt(base: String, adds: Array, roll: float = -1.0, lroll: float = -1.0) -> Dictionary:
	## {ok, success, lucky, item, text}: one try at the bench
	var pv := combine_preview(base, adds)
	if not bool(pv["ok"]):
		return {"ok": false, "text": str(pv["why"])}
	var kind := str(pv["kind"])
	var fid := str(pv["_fid"])
	var r := randf() if roll < 0.0 else roll
	var lr := randf() if lroll < 0.0 else lroll
	var sk := str(pv["skill"])
	var all_ids := [base] + adds
	for id in all_ids:
		mat_known[base_id(str(id))] = true          # you learn what things are by working them
	var success := r < float(pv["chance"])
	var lucky := lr < float(pv["luck"])
	var was_slot := ""
	for s in gear_slots():
		if worn(str(s[0])) == base:
			was_slot = str(s[0])
	var made := ""
	var text := ""
	if not success:
		counters["combine_fail"] = float(counters.get("combine_fail", 0.0)) + 1.0
		var lost := []
		for a in adds:
			if nano_gift("fail_refund") > 0.0 and randf() < nano_gift("fail_refund"):
				continue
			remove_item(str(a), 1)
			lost.append(item_name(str(a)))
		var backfire := int(pv["volatile"]) >= 3 and not bool(pv["steady"]) and r > float(pv["chance"]) + 0.3
		text = I18n.t("It doesn't take. %s") % ((I18n.t("Lost: %s.") % ", ".join(lost)) if lost.size() > 0 else I18n.t("The swarm caught what it threw off -- nothing lost."))
		if backfire:
			if kind in ["infuse", "merge"]:
				made = _scorch(base, was_slot)
				text += I18n.t(" It flares -- the %s comes out scorched.") % item_name(base)
			else:
				remove_item(base, 1)
				text += I18n.t(" It flares, and the %s is gone too.") % item_name(base)
		if lucky:
			text += " " + _lesson_from_failure(all_ids)
		add_skill_xp(sk, 6.0, "a mix that failed")
	else:
		match kind:
			"formula":
				made = _make_formula(fid, all_ids, lucky)
				text = I18n.t("You make %s.") % item_name(made)
			"infuse":
				made = _infuse(base, adds, pv, lucky)
				text = I18n.t("You work %s into it: %s.") % [", ".join(adds.map(func(a): return item_name(str(a)))), item_name(made)]
			"merge":
				made = _merge_pieces(base, adds, lucky)
				text = I18n.t("The forge folds them into one: %s.") % item_name(made)
			"brew":
				made = _brew(base, adds, pv, lucky)
				text = I18n.t("You make %s.") % item_name(made)
			"alloy":
				made = _alloy(base, adds, pv, lucky)
				text = I18n.t("You make %s.") % item_name(made)
		if was_slot != "" and made != "" and gear_family(made) != "":
			wear(made, was_slot)
		add_skill_xp(sk, 10.0 + 3.0 * adds.size(), "working at the bench")
		if lucky:
			text += " " + str(_last_luck)
		if fid != "" and not knows_formula(fid):
			learn_formula(fid, "found")
			text += I18n.t(" You've worked out a formula: you can make it again, and better.")
			log_event("discovery", {"what": "formula:" + fid})
	if success and made != "":
		var cin := {}
		for cid in all_ids:
			cin[base_id(str(cid))] = int(cin.get(base_id(str(cid)), 0)) + 1
		var ssig := "%s+%s" % [base_id(base), "+".join(adds.map(func(a): return base_id(str(a)))) ]
		craftbook_note("combine", made, cin, sk, {"sig": ssig + ":" + kind})
	_check_nano_secrets(all_ids)
	log_event("combine", {"base": base_id(base), "adds": adds.map(func(a): return base_id(str(a))), "kind": kind, "success": success, "lucky": lucky,
		"chance": snappedf(float(pv["chance"]), 0.01), "made": made})
	message.emit(text)
	stats_changed.emit()
	return {"ok": true, "success": success, "lucky": lucky, "item": made, "kind": kind, "text": text, "chance": pv["chance"]}


var _last_luck := ""


func _lesson_from_failure(ids: Array) -> String:
	## a failure that teaches: the formula these things were reaching for
	for f in craft_data().get("formulas", []):
		if knows_formula(str(f["id"])):
			continue
		for k in f.get("needs", {}):
			if base_id(str(ids[0])) == str(k) or (ids.size() > 1 and base_id(str(ids[1])) == str(k)):
				learn_formula(str(f["id"]), "found")
				return I18n.t("But in the wreck you see what it wanted to be: a formula, worked out.")
	return I18n.t("But you learned something about every one of them.")


func _register_custom(prefix: String, def: Dictionary) -> String:
	var n := int(counters.get("custom_seq", 0.0)) + 1
	counters["custom_seq"] = float(n)
	var id := "%s%d" % [prefix, n]
	custom_items[id] = def
	items[id] = def
	return id


func _plain_name(n: String) -> String:
	var i := n.find(" of ")
	return n.substr(0, i) if i > 0 else n


func _infuse(base: String, adds: Array, pv: Dictionary, lucky: bool) -> String:
	var d := item_def(base).duplicate(true)
	var t: Dictionary = pv["_t"]
	var eff: Dictionary = d.get("effect", {})
	var scale := 0.0
	for a in adds:
		scale += material_potency(str(a))
	scale = scale / maxf(adds.size(), 1) * (0.55 + 0.1 * adds.size())
	var add := traits_to_effect(_top_traits(t, 3), scale)
	if not is_jewel(base):
		add.erase("craft_success")
	var tuned := nano_gift_mult("tuned_mult")
	var syn_names := []
	for sy in pv["_syn"]:
		add = merge_effects(add, sy["effect"], tuned if bool(sy.get("tuned", false)) else 1.0)
		syn_names.append(str(sy["name"]))
		if sy["effect"].has("light"):
			d["weight"] = snappedf(piece_weight(base) * (1.0 - float(sy["effect"]["light"])), 0.1)
	add.erase("light")
	var nano_pts := int(t.get("nano", 0))
	if nano_pts >= 2 and nano_has("filament_spinning"):
		d["make"] = "both" if str(d.get("make", "crafted")) in ["crafted", "both"] else "nano"
		d["weight"] = snappedf(piece_weight(base) * 0.85, 0.1)
	if str(d.get("make", "")) == "both":
		var hm := nano_gift_mult("hybrid_mult")
		if hm != 1.0:
			add = merge_effects({}, add, hm)
	_last_luck = ""
	if lucky:
		var extra := synergies_in({"hard": 1, "binding": 1, "keen": 1, "volatile": 1, "conductive": 1, "resonant": 1, "vital": 1, "living": 1,
			"nano": 1, "warding": 1, "supple": 1, "seeking": 1}).filter(func(sy): return (int(t.get(str(sy["a"]), 0)) > 0 or int(t.get(str(sy["b"]), 0)) > 0) and not (str(sy["name"]) in syn_names))
		if extra.size() > 0:
			var pick: Dictionary = extra[randi() % extra.size()]
			add = merge_effects(add, pick["effect"], 0.6)
			add.erase("light")
			syn_names.append(str(pick["name"]))
			_last_luck = "UNEXPECTED: it took on something you didn't put in -- %s." % pick["name"]
		else:
			d["hp"] = int(round(float(d.get("hp", 0)) * 1.15))
			_last_luck = "UNEXPECTED: it came out finer than it had any right to."
	d["effect"] = merge_effects(eff, add)
	d["infusions"] = int(d.get("infusions", 0)) + 1
	d["qrank"] = quality_index(base)
	var word: String = syn_names[0] if syn_names.size() > 0 else trait_name(str(_top_traits(t, 1).keys()[0] if not t.is_empty() else "binding"))
	d["name"] = I18n.t("%s of the %s") % [_plain_name(str(d.get("name", base))), word] if int(d["infusions"]) == 1 else "%s (%s)" % [str(d["name"]), word]
	var aff: Array = d.get("affixes", []).duplicate()
	aff.append("%s: %s" % [word, effect_text(add)])
	d["affixes"] = aff
	d["value"] = int(float(d.get("value", 10)) * 1.4 + 10)
	d["desc"] = "%s\n%s" % [str(item_def(base).get("desc", "")).get_slice("\n", 0), "\n".join(aff)]
	d.erase("drop")
	remove_item(base, 1)
	for a in adds:
		remove_item(str(a), 1)
	var id := _register_custom("c27_", d)
	add_item(id, 1, false)
	return id


func _scorch(base: String, slot: String) -> String:
	var d := item_def(base).duplicate(true)
	for k in ["hp", "ward"]:
		if d.has(k):
			d[k] = snappedf(float(d[k]) * 0.85, 0.1) if k == "ward" else int(round(float(d[k]) * 0.85))
	d["name"] = "Scorched " + str(d.get("name", base))
	d["qrank"] = quality_index(base)
	d.erase("drop")
	remove_item(base, 1)
	var id := _register_custom("c27_", d)
	add_item(id, 1, false)
	if slot != "":
		wear(id, slot)
	return id


func _merge_pieces(base: String, adds: Array, lucky: bool) -> String:
	var d := item_def(base).duplicate(true)
	var eff: Dictionary = d.get("effect", {})
	_last_luck = ""
	for a in adds:
		var ad := item_def(str(a))
		eff = merge_effects(eff, ad.get("effect", {}), 0.6 if not lucky else 0.8)
		if d.has("hp"):
			d["hp"] = maxi(int(d["hp"]), int(ad.get("hp", 0))) + int(int(ad.get("hp", 0)) * 0.2)
		if d.has("ward"):
			d["ward"] = snappedf(maxf(float(d["ward"]), piece_ward(str(a))) + piece_ward(str(a)) * 0.2, 0.1)
	if lucky:
		_last_luck = "UNEXPECTED: the two fit together as if they'd been made for it."
	d["effect"] = eff
	d["name"] = "Folded " + _plain_name(str(d.get("name", base)))
	d["qrank"] = maxi(quality_index(base), 2)
	d.erase("drop")
	remove_item(base, 1)
	for a in adds:
		remove_item(str(a), 1)
	var id := _register_custom("c27_", d)
	add_item(id, 1, false)
	return id


func _brew(base: String, adds: Array, pv: Dictionary, lucky: bool) -> String:
	var d := item_def(base).duplicate(true)
	var t: Dictionary = pv["_t"]
	var boost := 1.0 + 0.15 * int(t.get("vital", 0)) + 0.1 * int(t.get("living", 0))
	var qboost := 1.0 + 0.15 * int(t.get("conductive", 0)) + 0.1 * int(t.get("resonant", 0))
	if d.has("heal"):
		d["heal"] = int(round(float(d["heal"]) * boost))
	if d.has("qi"):
		d["qi"] = int(round(float(d["qi"]) * qboost))
	d["name"] = "Potent " + str(d.get("name", base)) if not str(d.get("name", "")).begins_with("Potent") else str(d["name"])
	d["desc"] = "%s (strengthened at the bench)" % str(item_def(base).get("desc", ""))
	d["value"] = int(float(d.get("value", 5)) * 1.6)
	var key := "brew_%s_%s" % [base_id(base), str(hash(str(_top_traits(t, 3))))]
	remove_item(base, 1)
	for a in adds:
		remove_item(str(a), 1)
	var id := key
	if not items.has(id):
		custom_items[id] = d
		items[id] = d
	add_item(id, 2 if lucky else 1, false)
	_last_luck = "UNEXPECTED: enough for two." if lucky else ""
	return id


func _alloy(base: String, adds: Array, pv: Dictionary, lucky: bool) -> String:
	var t: Dictionary = (pv["_t"] as Dictionary).duplicate()
	for sy in pv["_syn"]:
		t[str(sy["a"])] = int(t.get(str(sy["a"]), 0)) + 1
		t[str(sy["b"])] = int(t.get(str(sy["b"]), 0)) + 1
	t = _top_traits(t, 4)
	var ids := ([base] + adds).map(func(a): return base_id(str(a)))
	ids.sort()
	var id := "alloy_%d" % absi(hash(",".join(ids)))
	if not items.has(id):
		var syn: Array = pv["_syn"]
		var word := str(syn[0]["name"]) if syn.size() > 0 else (trait_name(str(_top_traits(t, 1).keys()[0])) if not t.is_empty() else "Worked")
		var st := stock_info(base)
		var jm := jewel_metal(base)
		var short := "%s %s" % [word, st.get("name", jm.get("name", item_name(base)))]
		var v := 0
		for a in ids:
			v += int(items.get(str(a), {}).get("value", 4))
		var d := {"name": short, "short": short, "type": "material", "value": int(v * 1.2), "traits": t, "element": material_element(base),
			"desc": I18n.t("Your own work: %s, worked with %s.") % [item_name(base), ", ".join(adds.map(func(a): return item_name(str(a))))]}
		if not st.is_empty() or not jm.is_empty():
			d["stock_of"] = base_id(base)
		custom_items[id] = d
		items[id] = d
	remove_item(base, 1)
	for a in adds:
		remove_item(str(a), 1)
	add_item(id, 2 if lucky else 1, false)
	_last_luck = "UNEXPECTED: it came out as two." if lucky else ""
	return id


func _make_formula(fid: String, ids: Array, lucky: bool) -> String:
	var f := formula_def(fid)
	for k in f.get("needs", {}):
		remove_item(str(k), maxi(int(f["needs"][k]), 1))
	var n := int(f.get("n", 1)) + (1 if lucky else 0)
	add_item(str(f["makes"]), n, false)
	_last_luck = "UNEXPECTED: one more than the formula promised." if lucky else ""
	return str(f["makes"])


# ---- forging a piece from a stock ----------------------------------------------------

func forge_families() -> Array:
	var out := []
	for fam in gear_data().get("families", {}):
		out.append(str(fam))
	return out


func class_open(cl: String) -> bool:
	var node := str(gear_data().get("classes", {}).get(cl, {}).get("node", ""))
	return node == "" or nano_has(node)


func forge_stocks(fam: String) -> Array:
	## what you could make this kind of piece from, right now: [[id, have, need]]
	var fd: Dictionary = gear_data().get("families", {}).get(fam, {})
	var out := []
	for id in inventory:
		var sid := str(id)
		if count(sid) <= 0:
			continue
		if str(fd.get("kind", "")) == "jewel":
			var jm := jewel_metal(sid)
			if jm.is_empty() or (str(jm.get("node", "")) != "" and not nano_has(str(jm["node"]))):
				continue
		else:
			var st := stock_info(sid)
			if st.is_empty() or not (str(st.get("class", "")) in fd.get("classes", [])) or not class_open(str(st["class"])):
				continue
		out.append([sid, count(sid), int(fd.get("needs", 1))])
	out.sort_custom(func(a, b): return item_name(a[0]) < item_name(b[0]))
	return out


func forge_skill(fam: String, stock: String) -> String:
	if str(gear_data()["families"].get(fam, {}).get("kind", "")) == "jewel":
		return "jewelcrafting"
	return str(gear_data().get("classes", {}).get(str(stock_info(stock).get("class", "metal")), {}).get("skill", "smithing"))


func forge_tier(fam: String, stock: String) -> int:
	if str(gear_data()["families"].get(fam, {}).get("kind", "")) == "jewel":
		return int(round(float(jewel_metal(stock).get("potency", 1.0)) * 3.0))
	return int(stock_info(stock).get("tier", 1))


func forge_chance(fam: String, stock: String, gem: String = "") -> float:
	var sk := forge_skill(fam, stock)
	var t := forge_tier(fam, stock)
	var c := 0.78 + (skill_level(sk) - t * 0.45) * 0.06 + tech_effect("craft_success", 0.0) + tech_effect("craft_success_" + sk, 0.0)
	c += 0.03 * int(material_traits(stock).get("binding", 0))
	if gem != "":
		c -= 0.04 + 0.03 * int(material_traits(gem).get("volatile", 0))
	if at_bench == "" and not road_bench():
		c -= 0.12
	if (at_bench == "forge" or field_forge()) and sk == "smithing":
		c += 0.05
	c += 0.05 * focus_bonus(sk)
	return clampf(c, 0.1, 0.97)


func forge_check(fam: String, stock: String, gem: String = "") -> String:
	var fd: Dictionary = gear_data().get("families", {}).get(fam, {})
	if fd.is_empty():
		return I18n.t("Nobody makes that.")
	var ok := false
	for row in forge_stocks(fam):
		if str(row[0]) == stock:
			ok = true
	if not ok:
		return I18n.t("%s can't be made into a %s yet.") % [item_name(stock), str(fd.get("name", fam)).to_lower()]
	var need := int(fd.get("needs", 1))
	if count(stock) - equipped_count(stock) < need:
		return I18n.t("You need %d %s.") % [need, item_name(stock)]
	if gem != "":
		if gem == stock and count(gem) < need + 1:
			return I18n.t("You need one more %s for the setting.") % item_name(gem)
		if count(gem) - equipped_count(gem) < 1 or is_treasure(gem) or gear_family(gem) != "":
			return I18n.t("%s can't be set in it.") % item_name(gem)
	var cost := forge_tier(fam, stock) * 3
	if gold < cost:
		return I18n.t("It costs %d gold in fuel and fittings.") % cost
	return ""


func forge_piece(fam: String, stock: String, gem: String = "", roll: float = -1.0, qroll: float = -1.0, design: Dictionary = {}) -> Dictionary:
	var why := forge_check(fam, stock, gem)
	var dc := "jewel" if str(gear_data()["families"].get(fam, {}).get("kind", "")) == "jewel" else "forge"
	if why == "" and not Design.is_plain(design):
		why = Design.check(dc, design, skill_level(forge_skill(fam, stock)))
	if why != "":
		return {"ok": false, "text": why}
	var fd: Dictionary = gear_data()["families"][fam]
	var sk := forge_skill(fam, stock)
	var t := forge_tier(fam, stock)
	var need := int(fd.get("needs", 1))
	var chance := forge_chance(fam, stock, gem)
	gold -= t * 3
	var pl := craft_play_apply(roll, qroll)                # round 141c
	var r := float(pl["roll"]) if float(pl["roll"]) >= 0.0 else randf()
	if r >= chance:
		remove_item(stock, int(ceil(need / 2.0)))
		add_skill_xp(sk, 5.0 + t, "a piece that went wrong")
		var tx := I18n.t("The %s goes wrong in the making -- %d %s spoiled.") % [str(fd.get("name", fam)).to_lower(), int(ceil(need / 2.0)), item_name(stock)]
		message.emit(tx)
		log_event("forge", {"family": fam, "stock": base_id(stock), "success": false})
		return {"ok": true, "success": false, "text": tx}
	var q := craft_quality({"skill": sk, "difficulty": int(t / 2)}, "balanced", float(pl["qroll"]))
	remove_item(stock, need)
	if gem != "":
		remove_item(gem, 1)
	var made := ""
	var plain: bool = gear_data().get("stocks", {}).has(base_id(stock)) and base_id(stock) == stock
	var designed: bool = not Design.is_plain(design)
	if designed:
		Design.take(dc, design)
	if str(fd.get("kind", "")) == "jewel":
		var jid := "j_%s_%s_%s" % [base_id(stock), base_id(gem), fam]
		if gem != "" and not designed and items.has(jid) and base_id(stock) == stock and base_id(gem) == gem:
			made = with_quality(jid, q)
		else:
			var jd := jewel_def(stock, gem, fam)
			jd.erase("drop")
			jd["qrank"] = q
			made = _register_custom("c27_", _q_scaled(Design.apply(dc, jd, design), q))
	elif plain and gem == "" and not designed:
		made = with_quality(gear_id(base_id(stock), fam), q)
	else:
		var extra := material_traits(gem) if gem != "" else {}
		var pd := piece_def(stock, fam, extra)
		if gem != "":
			pd["effect"] = merge_effects(pd.get("effect", {}), traits_to_effect(_top_traits(material_traits(gem), 2), material_potency(gem) * 0.5))
			pd["name"] = I18n.t("%s set with %s") % [pd["name"], item_name(gem).to_lower()]
			pd["gem"] = base_id(gem)
		pd.erase("drop")
		pd["qrank"] = q
		made = _register_custom("c27_", _q_scaled(Design.apply(dc, pd, design), q))
	add_item(made, 1, false)
	add_skill_xp(sk, (10.0 + t * 2.0 + 4.0 * maxi(q - 1, 0)) * float(pl["xp"]), "forging")
	if designed and sys("heirloom") != null:
		sys("heirloom").ignite_by_design(design)
	counters["made:" + made] = float(counters.get("made:" + made, 0.0)) + 1.0
	if q >= 2:
		guild_event("craft_fine")
	guild_event("craft:" + sk)
	var fin := {stock: need}
	if gem != "":
		fin[gem] = 1
	craftbook_note("forge", made, fin, sk, {"fam": fam, "stock": stock, "gem": gem, "design": design if designed else {}, "q": q})
	var tx2 := "You make %s." % item_name(made)
	message.emit(tx2)
	log_event("forge", {"family": fam, "stock": base_id(stock), "gem": base_id(gem), "success": true, "made": made, "quality": QUALITY[q]["id"]})
	return {"ok": true, "success": true, "item": made, "quality": q, "text": tx2}


func _q_scaled(d: Dictionary, q: int) -> Dictionary:
	## a custom piece carries its quality in its own numbers (and its name)
	var m := float(QUALITY[q]["mult"])
	var o := d.duplicate(true)
	if o.has("hp"):
		o["hp"] = int(round(float(o["hp"]) * m))
	if o.has("ward"):
		o["ward"] = snappedf(float(o["ward"]) * m, 0.1)
	if o.has("effect"):
		o["effect"] = merge_effects({}, o["effect"], m)
	var qn := str(QUALITY[q]["name"])
	if qn != "":
		o["name"] = "%s %s" % [qn, o.get("name", "")]
	o["value"] = int(float(o.get("value", 10)) * m * m)
	return o


# ---- the nanotech tree ------------------------------------------------------------------

func nano_node_def(nid: String) -> Dictionary:
	for n in nanotech_data().get("nodes", []):
		if str(n.get("id", "")) == nid:
			return n
	return {}


func nano_has(nid: String) -> bool:
	return bool(nano_nodes.get(nid, false))


func nano_gift(key: String) -> float:
	var v := 0.0
	for nid in nano_nodes:
		var g = nano_node_def(str(nid)).get("gives", {}).get(key, 0.0)
		if not (g is bool) and not (g is String):
			v += float(g)
	return v


func nano_gift_mult(key: String) -> float:
	var v := 1.0
	for nid in nano_nodes:
		var g = nano_node_def(str(nid)).get("gives", {}).get(key, null)
		if g != null and not (g is bool) and not (g is String):
			v *= float(g)
	return v


func nano_state(nid: String) -> String:
	## "open" | "ready" | "locked" | "hidden"
	var n := nano_node_def(nid)
	if n.is_empty():
		return "hidden"
	if nano_has(nid):
		return "open"
	if bool(n.get("secret", false)) and not has_flag("nano_found:" + nid):
		return "hidden"
	return "ready" if nano_why(nid) == "" else "locked"


func nano_why(nid: String) -> String:
	var n := nano_node_def(nid)
	if nano_has(nid):
		return I18n.t("already part of you")
	if nanite_tier() < int(n.get("tier", 0)):
		return I18n.t("needs the swarm at %s") % tier_name(int(n.get("tier", 0)))
	for p in n.get("needs", []):
		if not nano_has(str(p)):
			return I18n.t("needs %s first") % nano_node_def(str(p)).get("name", p)
	for k in n.get("cost", {}):
		if count(str(k)) < int(n["cost"][k]):
			return I18n.t("needs %d %s (you have %d)") % [int(n["cost"][k]), item_name(str(k)), count(str(k))]
	return ""


func nano_unlock(nid: String) -> String:
	var st := nano_state(nid)
	if st == "hidden":
		return I18n.t("You don't know of anything like that.")
	var why := nano_why(nid)
	if why != "":
		return I18n.t("Not yet: %s.") % why
	var n := nano_node_def(nid)
	for k in n.get("cost", {}):
		remove_item(str(k), int(n["cost"][k]))
	nano_nodes[nid] = true
	integrate(15.0 + 10.0 * int(n.get("tier", 0)), "the nanoforge")
	var f := str(n.get("gives", {}).get("formula", ""))
	if f != "":
		formulas_known[f] = "taught"
	log_event("nano_node", {"id": nid})
	var t := I18n.t("NANOFORGE: %s -- %s") % [n.get("name", nid), n.get("desc", "")]
	message.emit(t)
	stats_changed.emit()
	return t


func _check_nano_secrets(ids: Array) -> void:
	var have := {}
	for i in ids:
		have[base_id(str(i))] = true
	for n in nanotech_data().get("nodes", []):
		var nid := str(n.get("id", ""))
		if not bool(n.get("secret", false)) or has_flag("nano_found:" + nid):
			continue
		var fb: Dictionary = n.get("found_by", {})
		var found := false
		if fb.has("with"):
			found = true
			for w in fb["with"]:
				if not have.has(str(w)):
					found = false
		if fb.has("failures") and float(counters.get("combine_fail", 0.0)) >= float(fb["failures"]):
			found = true
		if found:
			set_flag("nano_found:" + nid)
			message.emit("DISCOVERY: the swarm shows you something new -- %s. (Nanoforge, in your pack: I)" % n.get("name", nid))
			log_event("discovery", {"what": "nano:" + nid})


# ---- drops across the whole body ----------------------------------------------------

func drop_body_piece(d: int, boost: int = 0, pick: float = -1.0) -> String:
	## a piece of armour or jewellery for this depth (the catalogue's)
	var fams := WEAR_TYPES.duplicate()
	fams.erase("armor")
	var jewel := randf() < (0.12 + 0.08 * boost)
	var pool := gear_pool(d, (["ring", "toering", "bracelet", "choker", "necklace"] if jewel else fams))
	if pool.is_empty():
		return ""
	var id := with_quality(str(pool[int((randf() if pick < 0.0 else pick) * pool.size()) % pool.size()]), roll_quality(boost))
	message.emit(I18n.t("FOUND: %s!%s") % [item_name(id), Hook.compare(id)])
	log_event("gear_drop", {"id": id, "depth": d})
	add_item(id, 1)
	sfx("pickup")
	reveal_loot(id)
	return id


# ---- how it looks on you (Armour.gd draws it) ---------------------------------------

const LEGACY_LOOK := [["nanite", "nanoweave", [0.22, 0.27, 0.32]], ["robe", "cloth", [0.82, 0.8, 0.74]], ["silk", "cloth", [0.75, 0.8, 0.92]],
	["weave", "cloth", [0.6, 0.62, 0.55]], ["wrap", "cloth", [0.8, 0.72, 0.55]], ["vestment", "cloth", [0.9, 0.88, 0.8]], ["padded", "cloth", [0.6, 0.55, 0.45]],
	["leather", "leather", [0.42, 0.3, 0.2]], ["hide", "leather", [0.45, 0.32, 0.2]], ["bark", "leather", [0.4, 0.28, 0.18]], ["vest", "leather", [0.45, 0.33, 0.22]],
	["bone", "bone", [0.85, 0.82, 0.72]], ["coral", "bone", [0.9, 0.62, 0.55]], ["nacre", "bone", [0.92, 0.9, 0.95]], ["clay", "bone", [0.65, 0.4, 0.28]],
	["terracotta", "bone", [0.7, 0.42, 0.3]], ["jade", "jade", [0.35, 0.65, 0.45]], ["prism", "jade", [0.8, 0.85, 0.95]], ["coat", "leather", [0.35, 0.3, 0.3]]]


func piece_look(id: String) -> Dictionary:
	var d := item_def(id)
	if d.has("look"):
		return {"look": str(d["look"]), "color": d.get("color", [0.5, 0.5, 0.5]), "make": str(d.get("make", "crafted")), "gem_color": d.get("gem_color", [0.9, 0.9, 0.9]), "design": d.get("design", {})}
	var nm := str(d.get("name", id)).to_lower()
	if is_jewel(id):
		return {"look": "jewel", "color": [0.95, 0.8, 0.35] if nm.contains("gold") else [0.85, 0.87, 0.9], "make": "crafted",
			"gem_color": [0.95, 0.3, 0.2] if nm.contains("ruby") else ([0.3, 0.5, 0.95] if nm.contains("sapphire") else [0.35, 0.75, 0.45])}
	for row in LEGACY_LOOK:
		if nm.contains(str(row[0])):
			return {"look": str(row[1]), "color": row[2], "make": "nano" if str(row[0]) == "nanite" else "crafted"}
	return {"look": "metal", "color": [0.55, 0.56, 0.6], "make": "crafted"}


func worn_looks() -> Array:
	var out := []
	for s in gear_slots():
		var sl := str(s[0])
		if sl == "weapon":
			continue
		var id := worn(sl)
		if id == "" or count(id) <= 0 or not has_item_def(id):
			continue
		var lk := piece_look(id)
		lk["slot"] = sl
		lk["family"] = "armor" if gear_family(id) == "armor" else gear_family(id)
		out.append(lk)
	return out


# ======================================================================
# Round 28 -- no two fights the same.
# Robert, 2026-10-03: "keep working on the game, build it out now, make it
# more diverse". data/foes.json: fighting STYLES for every monster (from its
# own data, its name, or its kind), VARIANTS in a pack from floor 2, ELITES
# with affixes from floor 3, bosses ENRAGED at half health -- and RIVAL
# DISCIPLES from the valley's sects who stop you on the road for a bout.
# ======================================================================

var foes_def := {}
var combat_def := {}


func combat_data() -> Dictionary:
	if combat_def.is_empty():
		var d = _load_json("res://data/combat.json", {})
		combat_def = d if d is Dictionary else {}
	return combat_def


func register_key(id: String, floor_name: String) -> void:
	## round 32: a floor's key is an item like any other (it's used up at the gate)
	if not items.has(id):
		items[id] = {"name": "Key to %s" % floor_name, "type": "key", "value": 0, "desc": "Heavy iron, cold. The Keeper's gate on that floor opens to it."}


func puzzle_hint(order: Array) -> String:
	## the tablet by the levers: Dev's words when the writing room has them
	## (data/drafts/puzzle_hints.json: items with "first", "second", "third"
	## sentences using %s), else ours
	var dr = _load_json("res://data/drafts/puzzle_hints.json", {})
	if dr is Dictionary and (dr.get("items", []) as Array).size() > 0:
		var it = (dr["items"] as Array)[hash(str(order)) % (dr["items"] as Array).size()]
		if it is Dictionary and str(it.get("text", "")).count("%s") == 3:
			return str(it["text"]) % [order[0], order[1], order[2]]
	var lines := ["Three hands turned the stone. %s first, who dug it. Then %s, who shored it. %s last, who sealed it.",
		"The maker's rule: %s before %s, and %s only when the others are down.",
		"Sing it as the old ones did -- %s, %s, %s -- and the iron remembers."]
	return str(lines[hash(str(order)) % lines.size()]) % [str(order[0]).capitalize(), str(order[1]), str(order[2])]


func combat_cfg(section: String, key: String, d: float) -> float:
	return float(combat_data().get(section, {}).get(key, d))


func foes_data() -> Dictionary:
	if foes_def.is_empty():
		foes_def = _load_json("res://data/foes.json", {"styles": {"brawler": {}}, "keywords": {}, "affixes": {}})
	return foes_def


func foe_style(etype: String, st: Dictionary) -> String:
	## how a kind of monster fights: its own "style", else its name says so,
	## else (a monster, not a person) its kind picks one -- the same every time
	var F := foes_data()
	var s := str(st.get("style", ""))
	if s != "" and F.get("styles", {}).has(s):
		return s
	if bool(st.get("boss", false)) or bool(st.get("passive", false)):
		return "brawler"
	var nm := (str(st.get("name", etype)) + " " + etype).to_lower()
	for k in F.get("keywords", {}):
		for w in F["keywords"][k]:
			if nm.contains(str(w)):
				return str(k)
	if str(st.get("model", "orc")) == "human":
		return "brawler"
	var pool := ["brawler", "brawler", "brawler", "ranged", "charger", "guardian", "skulker", "swarmer"]
	return pool[absi(hash(etype)) % pool.size()]


func foes_codex_line(e) -> String:
	return str(e.describe()) if e != null and e.has_method("describe") else ""


# ---- rival disciples -----------------------------------------------------------------

const ELEMENT_COLOR := {"wood": [0.3, 0.6, 0.32], "fire": [0.75, 0.25, 0.2], "earth": [0.65, 0.5, 0.28], "metal": [0.82, 0.82, 0.86], "water": [0.25, 0.42, 0.75]}
const ELEMENT_WEAPON := {"wood": "staff", "fire": "saber", "earth": "hammer", "metal": "sword", "water": "spear"}


func valley_rivals(seed_day: int = -1) -> Array:
	## who walks the valley roads today: disciples of the sects -- not yours
	var F: Dictionary = foes_data().get("rivals", {})
	var sects: Array = valley_data().get("sects", []).filter(func(s): return str(s.get("id", "")) != str(sect.get("id", "")))
	if sects.is_empty():
		return []
	var day := seed_day if seed_day >= 0 else int(Time.get_unix_time_from_system() / 86400.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("rivals:%d" % day)
	var given: Array = F.get("given", ["Han"])
	var lines: Array = F.get("lines", ["Cross hands with me."])
	var out := []
	if rival_shen_live():
		# round 32: the story's rival walks the road until you beat him
		var s0: Dictionary = sects[rng.randi() % sects.size()]
		out.append({"name": "Shen", "sect": str(s0.get("id", "")), "sect_name": str(s0.get("name", I18n.t("a sect"))), "element": str(s0.get("element", "earth")),
			"line": "\"So you're the one filling the Lodge's book. Every record in it was mine. Let's see what you've got that I haven't.\"", "shen": true})
	for i in mini(int(F.get("count", 3)), sects.size()):
		var s: Dictionary = sects[(rng.randi() + i) % sects.size()]
		var nm := "%s %s" % ["Disciple", given[rng.randi() % given.size()]]
		while out.any(func(r): return r["name"] == nm):
			nm = "%s %s" % ["Disciple", given[rng.randi() % given.size()]]
		out.append({"name": nm, "sect": str(s.get("id", "")), "sect_name": str(s.get("name", I18n.t("a sect"))), "element": str(s.get("element", "earth")),
			"line": str(lines[rng.randi() % lines.size()])})
	return out


func rival_disciple_stats(r: Dictionary) -> Dictionary:
	## a disciple a little ahead of you -- a real test, never a slaughter
	var el := str(r.get("element", "earth"))
	var st := str(foes_data().get("rivals", {}).get("styles", {}).get(el, "brawler"))
	var lvl := step_index() + realm * 3
	var shen := bool(r.get("shen", false))             # round 32: the story's rival is a cut above
	return {"name": str(r.get("name", "Disciple")), "model": "human", "tint": ELEMENT_COLOR.get(el, [0.5, 0.5, 0.5]), "kind": ELEMENT_WEAPON.get(el, "sword"),
		"hp": int(round(max_hp() * (1.3 if shen else 0.9))), "damage": maxi(4, int(round(max_hp() * (0.09 if shen else 0.07)))), "speed": 4.4 if shen else 4.2, "aggro": 30.0, "range": 1.9,
		"cooldown": 1.1 if shen else 1.3, "qi": 0, "loot": {}, "passive": true, "style": st, "scale": 1.05 if shen else 1.0, "level": lvl + (3 if shen else 0)}


func duel_result(r: Dictionary, you_won: bool) -> void:
	var nm := str(r.get("name", "the disciple"))
	_rival_meet(nm, you_won)
	if you_won:
		var g := 20 + 15 * (realm + 1) + step_index() * 2
		add_item("gold", g, false)
		add_qi(10.0 * (realm + 1) + step_index() * 3.0, "a bout well fought")
		if not sect.is_empty():
			sect_contrib(6.0, "a bout won for your sect")
		message.emit(I18n.t("BOUT WON: %s yields and bows. \"You'll do.\" (+%d gold)") % [nm, g])
		log_event("duel_won", {"rival": nm, "sect": r.get("sect", "")})
		if bool(r.get("shen", false)) and not has_flag("story:shen_beaten"):
			set_flag("story:shen_beaten")                 # round 32: the story's rival, beaten
			if not ("The One Shen Couldn't Beat" in titles):
				titles.append(I18n.t("The One Shen Couldn't Beat"))
			gain_insight(5.0, "Shen")
			big_moment.emit("Shen Yields", "He gets up slowly. \"The book's yours,\" he says, and means it. He doesn't come back to the valley road. (Title: The One Shen Couldn't Beat. +5 insight.)")
			log_event("story_rival_beaten")
	else:
		add_skill_xp("survival", 6.0, "a bout lost")
		message.emit("BOUT LOST: you yield to %s. \"Again some day. Watch your feet.\"" % nm)
		log_event("duel_lost", {"rival": nm, "sect": r.get("sect", "")})
	stats_changed.emit()


# ======================================================================
# round 30 (Robert, 2026-10-03): bloodlines, and what keeps you coming back
#   * bloodlines (data/bloodlines.json): percentages with milestones; one
#     dominant and one secondary; a player may start with one, or carry a
#     hidden one that shines through; they wake around floor 20, and are
#     found in dead masters' legacies and in drops of old blood
#   * the daily trial (TrialGen.gd), the week's sect trials, trial marks and
#     the Trial Board, collections, rare world events, ascension
#     (data/retention.json)
#   * Steam (SteamLink.gd): achievements, stats, leaderboards, rich
#     presence, cloud saves -- only when the game runs under Steam
# ======================================================================

signal big_moment(title: String, body: String)        # HUD shows it as a window when nothing else is open
signal blood_choice(new_id: String)                   # a third line found: keep which?
signal banner(text: String, color: Color)             # a line across the screen (an event, a trial)

const TrialGen := preload("res://scripts/world/TrialGen.gd")
const BLOOD_KEYS := ["crit_chance", "dodge_chance", "burn_on_hit", "loot_luck", "rebirth", "low_hp_fury"]

var retention_live := true        # tools/playtest: off, so events, weekly goals and awakenings don't fire mid-test
var bloodline := {}               # {"dominant", "secondary", "purity": {id: %}, "hidden": {id: %}, "known": {id: true}, "awaken_at", "awake", "rebirth_day", "swap_at", "pending"}
var trials := {}                  # {"streak", "last_day", "done": {day: score}, "best": {day: score}, "run": {...}, "week", "goals", "progress", "claimed"}
var marks := 0                    # trial marks: the Trial Board's currency
var coll_claimed := {}            # "collection:tier" -> true
var world_events := {}            # level id -> {"id", "day"} ("" = nothing happened there today)
var ascension := {}               # {"count", "marks", "boons": {id: rank}, "best_depth"}
var blood_def := {}
var blood_words := {}
var retention_def := {}
var steam: Node = null
var audio: Node = null            # round 31: Audio.gd (music and sound)


func _round30_ready() -> void:
	_merge_round30_items()
	steam = preload("res://scripts/core/SteamLink.gd").new()
	steam.name = "SteamLink"
	add_child(steam)
	audio = preload("res://scripts/core/Audio.gd").new()
	audio.name = "Audio"
	add_child(audio)
	store = preload("res://scripts/core/Store.gd").new()      # round 58: what this copy of the game owns
	store.name = "Store"
	add_child(store)
	store.note.connect(func(t: String): message.emit(t))
	ads = preload("res://scripts/core/Ads.gd").new()         # round 58: the free tier's ads (phones, below floor 5)
	ads.name = "Ads"
	add_child(ads)
	store.changed.connect(func(): ads.start(ads.pick_backend()))     # (bought: the ads stop)
	buff_names["deep_blessing"] = "The deep's blessing"


# ---- round 58: the free floors ---------------------------------------------------------------
var store: Node = null
var ads: Node = null
var _after_load_note := ""
var last_hurt_at := 0.0           # (unix) Ads.gd: never an ad straight after a blow
var buff_names := {}              # buff id -> its name, for buffs that aren't items


func expansion_open(id: String) -> bool:
	## what an expansion's content checks (data/store.json "expansions")
	return store != null and store.owns_expansion(id)


func free_haven() -> String:
	## the deepest town you've reached that's still open (else the village)
	var best := "village"
	var best_d := 0
	for id in havens:
		var d: int = store.depth_of(str(id)) if store else 0
		if level_exists(str(id)) and not (store and store.level_locked(str(id))) and d > best_d:
			best = str(id)
			best_d = d
	return best


func take_after_load_note() -> String:
	var t := _after_load_note
	_after_load_note = ""
	return t


func sfx(name: String, vol: float = 1.0) -> void:
	if audio:
		audio.play(name, vol)


func sfx_at(name: String, pos: Vector3, vol: float = 1.0) -> void:
	if audio:
		audio.at(name, pos, vol)


func jingle(name: String) -> void:
	if audio:
		audio.jingle(name)


func blood_data() -> Dictionary:
	if blood_def.is_empty():
		var d = _load_json("res://data/bloodlines.json", {})
		blood_def = d if d is Dictionary else {}
		var w = _load_json("res://data/bloodline_words.json", {})      # Dev's own words win (the writing room)
		blood_words = w if w is Dictionary else {}
		# the writing room's "bloodlines" brief: Dev's drafts, one per line
		var dr = _load_json("res://data/drafts/bloodlines.json", {})
		if dr is Dictionary:
			var lw: Dictionary = blood_words.get("lines", {}) if blood_words.get("lines", {}) is Dictionary else {}
			for it in dr.get("items", []):
				if it is Dictionary and str(it.get("line", "")) != "" and not lw.has(str(it["line"])):
					lw[str(it["line"])] = it
			blood_words["lines"] = lw
	return blood_def


func retention_data() -> Dictionary:
	if retention_def.is_empty():
		var d = _load_json("res://data/retention.json", {})
		retention_def = d if d is Dictionary else {}
		# Dev's words for the trial's twists and the world's events (the
		# writing room's "trial_twists" and "world_events" briefs, round 31)
		for pair in [["trial_twists", retention_def.get("daily", {}).get("mods", {}), "twist"], ["world_events", retention_def.get("events", {}).get("list", {}), "event"]]:
			var dr = _load_json("res://data/drafts/%s.json" % pair[0], {})
			var table: Dictionary = pair[1]
			if dr is Dictionary and table is Dictionary:
				for it in dr.get("items", []):
					var key := str(it.get(pair[2], "")) if it is Dictionary else ""
					if table.has(key):
						for k in ["name", "desc"]:
							if str(it.get(k, "")) != "":
								table[key][k] = str(it[k])
	return retention_def


func _merge_round30_items() -> void:
	## a drop of each line's blood: use it and that line's purity rises
	var lines: Dictionary = blood_data().get("lines", {})
	for id in lines:
		var L := blood_line(str(id))
		items["essence_" + str(id)] = {"name": I18n.t("Drop of %s Blood") % lines[id].get("name", id), "type": "consumable", "blood": str(id), "value": 140,
			"desc": "A bead of old blood that won't dry, warm as a living thing. %s" % L.get("desc", "")}


# ---- bloodlines ---------------------------------------------------------------

func blood_line(id: String) -> Dictionary:
	var L: Dictionary = (blood_data().get("lines", {}) as Dictionary).get(id, {}).duplicate(true)
	var w = (blood_words.get("lines", {}) as Dictionary).get(id, {}) if blood_words.get("lines", {}) is Dictionary else {}
	if w is Dictionary:
		for k in ["name", "desc", "stir", "power50"]:
			if str(w.get(k, "")) != "":
				L[k] = str(w[k])
	return L


func blood_ids() -> Array:
	var ids: Array = (blood_data().get("lines", {}) as Dictionary).keys()
	ids.sort()
	return ids


func blood_new_game(rng_seed: int) -> void:
	## Who you are by birth: most people carry no great blood; some carry
	## it plainly; some carry it hidden, and it shows itself later.
	var B := blood_data()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var af: Array = B.get("awaken_floor", [20, 20])
	bloodline = {"dominant": "", "secondary": "", "purity": {}, "hidden": {}, "known": {},
		"awaken_at": rng.randi_range(int(af[0]), int(af[1])), "awake": false}
	var ids := blood_ids()
	if ids.is_empty():
		return
	var st: Dictionary = B.get("start", {})
	var r := rng.randf()
	var vis := float(st.get("visible_chance", 0.08))
	if r < vis:
		var id: String = ids[rng.randi() % ids.size()]
		var pr: Array = st.get("visible_purity", [8, 16])
		bloodline["purity"][id] = snappedf(rng.randf_range(float(pr[0]), float(pr[1])), 0.1)
		bloodline["known"][id] = true
		bloodline["dominant"] = id
	elif r < vis + float(st.get("hidden_chance", 0.25)):
		var hid: String = ids[rng.randi() % ids.size()]
		var hp_: Array = st.get("hidden_purity", [4, 12])
		bloodline["hidden"][hid] = snappedf(rng.randf_range(float(hp_[0]), float(hp_[1])), 0.1)


func blood_awake() -> bool:
	return bool(bloodline.get("awake", false))


func blood_dominant() -> String:
	return str(bloodline.get("dominant", ""))


func blood_secondary() -> String:
	return str(bloodline.get("secondary", ""))


func purity(id: String) -> float:
	return float((bloodline.get("purity", {}) as Dictionary).get(id, 0.0))


func blood_milestone(p: float) -> Dictionary:
	## the highest milestone a purity has reached ({} below the first)
	var best := {}
	for m in blood_data().get("milestones", []):
		if p >= float(m.get("at", 999)):
			best = m
	return best


func blood_effect() -> Dictionary:
	## what your blood gives: the dominant line in full, the secondary at a
	## share -- nothing until it has woken
	if not blood_awake():
		return {}
	var out := {}
	var share := float(blood_data().get("secondary_share", 0.5))
	for pair in [[blood_dominant(), 1.0], [blood_secondary(), share]]:
		var id: String = pair[0]
		if id == "":
			continue
		var p := purity(id)
		var ms: Dictionary = blood_line(id).get("milestones", {})
		var ats: Array = ms.keys()
		ats.sort_custom(func(a, b): return float(a) < float(b))
		for at in ats:
			if p >= float(at):
				out = merge_effects(out, ms[at], float(pair[1]))
	return out


func _blood_gain_mult() -> float:
	return float(active_event().get("blood_mult", 1.0))


func add_purity(id: String, amount: float, why: String = "") -> String:
	## Purity rises (or a new line enters your blood). Returns what happened.
	if id == "" or amount <= 0.0 or not (blood_data().get("lines", {}) as Dictionary).has(id):
		return ""
	amount *= _blood_gain_mult()
	var P: Dictionary = bloodline.get("purity", {})
	if not blood_awake() and not P.has(id):
		# before it wakes, new blood settles in quietly
		var H: Dictionary = bloodline.get("hidden", {})
		H[id] = minf(float(H.get(id, 0.0)) + amount, 100.0)
		bloodline["hidden"] = H
		return "hidden"
	if not P.has(id):
		if blood_dominant() == "":
			bloodline["dominant"] = id
		elif blood_secondary() == "":
			bloodline["secondary"] = id
		else:
			# one dominant, one secondary: a third has to be decided
			bloodline["pending"] = {"id": id, "amount": amount, "why": why}
			blood_choice.emit(id)
			message.emit("New blood stirs -- %s. You can only carry two lines; decide what becomes of it." % blood_line(id).get("name", id))
			return "pending"
		P[id] = 0.0
		var known: Dictionary = bloodline.get("known", {})
		known[id] = true
		bloodline["known"] = known
		message.emit(I18n.t("BLOODLINE: %s enters your blood%s.") % [blood_line(id).get("name", id), I18n.t(" as your dominant line") if blood_dominant() == id else " as your secondary line"])
		log_event("blood_found", {"line": id, "why": why})
		if steam:
			steam.achieve("BLOOD_FOUND")
		if blood_dominant() == id and why != "the story":
			story_owed_on_blood.call_deferred(id)       # round 32: what the story promised your blood
	if id == blood_secondary():
		amount *= 0.6              # a secondary line refines more slowly
	var before := float(P.get(id, 0.0))
	var after := minf(before + amount, 100.0)
	P[id] = snappedf(after, 0.01)
	bloodline["purity"] = P
	_blood_milestones(id, before, after)
	stats_changed.emit()
	return "rose"


func _blood_milestones(id: String, before: float, after: float) -> void:
	var L := blood_line(id)
	for m in blood_data().get("milestones", []):
		var at := float(m.get("at", 999))
		if before < at and after >= at:
			var nm := "%s: %s (%d%%)" % [L.get("name", id), m.get("name", ""), int(at)]
			var gift := effect_text(L.get("milestones", {}).get(str(int(at)), {}))
			message.emit(I18n.t("BLOODLINE -- %s. %s") % [nm, gift])
			log_event("blood_milestone", {"line": id, "at": int(at)})
			if steam:
				steam.achieve("BLOOD_%d" % int(at))
				steam.stat("blood_purity", int(after))
			if int(at) == 50 and str(L.get("power50", "")) != "":
				big_moment.emit(nm, "%s\n\nYour dominant line gives this in full; a secondary line, half." % L.get("power50", ""))
			elif int(at) == 100:
				big_moment.emit(nm, "Your %s blood runs pure. Nothing in you is borrowed now." % L.get("name", id))


func resolve_blood_choice(choice: String) -> String:
	## "secondary": the new line replaces your secondary; "dominant": it takes
	## the lead (your dominant becomes secondary, the old secondary thins
	## away); "refine": burn it to feed your dominant; "refuse"
	var pend: Dictionary = bloodline.get("pending", {})
	if pend.is_empty():
		return ""
	bloodline.erase("pending")
	var id := str(pend.get("id", ""))
	var amt := float(pend.get("amount", 0.0))
	var P: Dictionary = bloodline.get("purity", {})
	match choice:
		"secondary":
			P.erase(blood_secondary())
			bloodline["secondary"] = id
		"dominant":
			P.erase(blood_secondary())
			bloodline["secondary"] = blood_dominant()
			bloodline["dominant"] = id
		"refine":
			bloodline["purity"] = P
			add_purity(blood_dominant(), amt * 0.5, "refined")
			message.emit("You burn the stranger's blood away; your %s line drinks what's left." % blood_line(blood_dominant()).get("name", ""))
			return "refined"
		_:
			message.emit("You let the strange blood go.")
			return "refused"
	P[id] = 0.0
	bloodline["purity"] = P
	var known: Dictionary = bloodline.get("known", {})
	known[id] = true
	bloodline["known"] = known
	log_event("blood_found", {"line": id, "why": str(pend.get("why", "")), "choice": choice})
	add_purity(id, amt, str(pend.get("why", "")))
	return choice


func swap_blood() -> String:
	## your secondary line takes the lead (once in a while: blood resettles slowly)
	if blood_secondary() == "":
		return I18n.t("You carry only one line.")
	var wait := float(blood_data().get("swap_cooldown_hours", 20)) * 3600.0
	var since := Time.get_unix_time_from_system() - float(bloodline.get("swap_at", 0.0))
	if since < wait:
		return I18n.t("Your blood is still settling from the last change (%s).") % _dur(wait - since)
	var d := blood_dominant()
	bloodline["dominant"] = blood_secondary()
	bloodline["secondary"] = d
	bloodline["swap_at"] = Time.get_unix_time_from_system()
	log_event("blood_swap", {"dominant": blood_dominant()})
	stats_changed.emit()
	return I18n.t("%s leads now; %s follows.") % [blood_line(blood_dominant()).get("name", ""), blood_line(blood_secondary()).get("name", "")]


func blood_floor_reached(d: int) -> void:
	## every new floor: hidden blood thickens; at the awakening floor it all wakes
	if not retention_live:
		return
	var H: Dictionary = bloodline.get("hidden", {})
	var g := float(blood_data().get("gain", {}).get("hidden_per_floor", 0.4))
	for id in H:
		H[id] = minf(float(H[id]) + g, 100.0)
	if not blood_awake() and d >= int(bloodline.get("awaken_at", 20)):
		awaken_blood()


func awaken_blood(rng_seed: int = -1) -> Array:
	## Around floor 20: the blood wakes. A line you were born with comes alive;
	## a hidden one shines through; with nothing at all, a faint natural line
	## sometimes surfaces. Returns the lines that woke.
	if blood_awake():
		return []
	bloodline["awake"] = true
	var woke := []
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed if rng_seed >= 0 else hash("blood|%s|%d" % [background, int(playtime)])
	var H: Dictionary = bloodline.get("hidden", {})
	var hids: Array = H.keys()
	hids.sort_custom(func(a, b): return float(H[a]) > float(H[b]))
	bloodline["hidden"] = {}
	for id in hids:
		var res := add_purity(str(id), float(H[id]), "shone through")
		if res != "pending":
			woke.append(str(id))
	if blood_dominant() == "" and rng.randf() < float(blood_data().get("natural_chance", 0.3)):
		var ids := blood_ids()
		var nid: String = ids[rng.randi() % ids.size()]
		var np: Array = blood_data().get("natural_purity", [3, 8])
		add_purity(nid, rng.randf_range(float(np[0]), float(np[1])), "natural")
		woke.append(nid)
	if blood_dominant() != "" and not woke.has(blood_dominant()):
		woke.push_front(blood_dominant())
	log_event("blood_awaken", {"lines": woke})
	if steam:
		steam.achieve("BLOOD_AWAKEN")
	var body := "Deep in the earth, something in your veins answers the deep.\n\n"
	if woke.is_empty():
		body += I18n.t("Nothing answers in you -- plain blood, for now. But blood can be found: in dead masters' legacies, in the drops of old blood the strong leave behind. One dominant line, one secondary; every one has its milestones (10%, 25%, 50%, 75%, 100%).")
	else:
		for id in woke:
			var L := blood_line(str(id))
			body += "%s (%d%%): %s\n%s\n\n" % [L.get("name", id), int(purity(str(id))), L.get("desc", ""), L.get("stir", "")]
		body += I18n.t("Purity rises as you use what you are: drops of old blood, the legacies of masters of your line, kin you defeat, breakthroughs, sitting at shrines. Milestones at 10%, 25%, 50%, 75% and 100% each give something; your dominant line gives in full, your secondary at half.")
	big_moment.emit("Your Blood Wakes", body)
	jingle("blood")
	stats_changed.emit()
	story_check("blood_awake", true)              # round 32: Lin has a question
	return woke


func blood_kill(stats_: Dictionary) -> void:
	## defeating your blood's kin refines it (a dragon-blooded cultivator who
	## fights drakes grows more like one)
	if not blood_awake():
		return
	var nm := ("%s %s" % [stats_.get("name", ""), stats_.get("id", "")]).to_lower()
	var G: Dictionary = blood_data().get("gain", {})
	for id in [blood_dominant(), blood_secondary()]:
		if id == "":
			continue
		for w in blood_line(id).get("kin", []):
			if nm.contains(str(w)):
				add_purity(id, float(G.get("kin_boss", 1.5)) if bool(stats_.get("boss", false)) else float(G.get("kin_kill", 0.12)), "kin")
				break


func blood_essence_drop(stats_: Dictionary, d: int) -> String:
	## a drop of old blood, from the strong, deep down (returns the item id or "")
	if not blood_awake() or not retention_live:
		return ""
	var E: Dictionary = blood_data().get("essence", {})
	if d < int(E.get("from_depth", 20)):
		return ""
	var ch := float(E.get("boss", 0.35)) if bool(stats_.get("boss", false)) else (float(E.get("elite", 0.05)) if bool(stats_.get("elite", false)) else 0.0)
	ch *= float(active_event().get("essence_mult", 1.0))
	if ch <= 0.0 or randf() >= ch:
		return ""
	var id := ""
	var r := randf()
	if r < 0.4 and blood_dominant() != "":
		id = blood_dominant()
	elif r < 0.6 and blood_secondary() != "":
		id = blood_secondary()
	else:
		var ids := blood_ids()
		id = ids[randi() % ids.size()]
	add_item("essence_" + id, 1)
	log_event("blood_essence", {"line": id})
	return "essence_" + id


func blood_essence(id: String) -> void:
	var G: Dictionary = blood_data().get("gain", {})
	var r: Array = G.get("essence", [3, 7])
	add_purity(id, randf_range(float(r[0]), float(r[1])), "essence")


func blood_inheritance(key: String, grants: Dictionary) -> String:
	## a dead master's legacy may carry their blood (a level file can name it:
	## "grants": {"bloodline": "azure_dragon"}; otherwise, deep down, a chance)
	var id := str(grants.get("bloodline", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("legacyblood|" + key)
	if id == "":
		if not blood_awake() or reach_depth() < int(blood_data().get("essence", {}).get("from_depth", 20)):
			return ""
		if rng.randf() >= float(blood_data().get("inheritance_chance", 0.4)):
			return ""
		var ids := blood_ids()
		id = ids[rng.randi() % ids.size()]
	var r: Array = blood_data().get("gain", {}).get("inheritance", [6, 12])
	add_purity(id, rng.randf_range(float(r[0]), float(r[1])), "inheritance")
	return id


func try_rebirth() -> bool:
	## Vermilion Phoenix: once a day, a killing blow leaves you standing
	if tech_effect("rebirth", 0.0) < 1.0:
		return false
	var day := today()
	if str(bloodline.get("rebirth_day", "")) == day:
		return false
	bloodline["rebirth_day"] = day
	hp = maxi(1, int(round(max_hp() * float(blood_data().get("rebirth_heal", 0.4)))))
	message.emit("REBIRTH -- the phoenix in your blood refuses this ending. You rise.")
	log_event("blood_rebirth", {})
	stats_changed.emit()
	return true


func crit_mult() -> float:
	var c := tech_effect("crit_chance", 0.0)
	if c > 0.0 and randf() < c:
		return float(blood_data().get("crit_mult", 1.8))
	return 1.0


func dodges() -> bool:
	var c := minf(tech_effect("dodge_chance", 0.0), 0.35)
	return c > 0.0 and randf() < c


func fury_mult() -> float:
	var f := tech_effect("low_hp_fury", 0.0)
	if f > 0.0 and hp < max_hp() * float(blood_data().get("fury_below", 0.4)):
		return 1.0 + f
	return 1.0


func blood_aura_color() -> Color:
	## the faint glow you carry once your dominant line is Manifest (50%)
	if not blood_awake() or blood_dominant() == "" or purity(blood_dominant()) < 50.0:
		return Color(0, 0, 0, 0)
	var c: Array = blood_line(blood_dominant()).get("color", [1, 1, 1])
	return Color(float(c[0]), float(c[1]), float(c[2]), 1.0)


func blood_rows() -> Array:
	## for the journal: [name, purity, milestone name, role, desc]
	var out := []
	for pair in [[blood_dominant(), "dominant"], [blood_secondary(), "secondary"]]:
		var id: String = pair[0]
		if id == "":
			continue
		var L := blood_line(id)
		out.append([str(L.get("name", id)), purity(id), str(blood_milestone(purity(id)).get("name", "faint")), str(pair[1]), str(L.get("desc", "")), id])
	return out


# ---- what's on this floor: the day's trial, a rare event -----------------------------

func zone_effect() -> Dictionary:
	## the place you're in: the daily trial's twists, a world event
	var out := {}
	if TrialGen.is_trial(current_level):
		for m in trial_mods(TrialGen.day_of(current_level)):
			var md: Dictionary = retention_data().get("daily", {}).get("mods", {}).get(m, {})
			if md.has("qi_mult"):
				out["qi_mult"] = float(out.get("qi_mult", 1.0)) * float(md["qi_mult"])
			if md.has("your_damage"):
				out["damage_mult"] = float(out.get("damage_mult", 1.0)) * float(md["your_damage"])
	var ev := active_event()
	if ev.has("qi_mult"):
		out["qi_mult"] = float(out.get("qi_mult", 1.0)) * float(ev["qi_mult"])
	return out


func level_mod(level_def: Dictionary, key: String) -> float:
	## for a foe: the trial's twists and the floor's event, multiplied
	var v := 1.0
	for m in level_def.get("trial_mods", []):
		v *= float(retention_data().get("daily", {}).get("mods", {}).get(str(m), {}).get(key, 1.0))
	var ev := event_for(str(level_def.get("id", "")))
	v *= float(ev.get(key, 1.0))
	var W = sys("world")                             # round 44: night's hunger, the season, the air down there
	if W:
		v *= W.foe_mod(str(level_def.get("id", "")), level_def, key)
	return v


func no_regen_here() -> bool:
	if not TrialGen.is_trial(current_level):
		return false
	for m in trial_mods(TrialGen.day_of(current_level)):
		if float(retention_data().get("daily", {}).get("mods", {}).get(m, {}).get("no_regen", 0.0)) > 0.0:
			return true
	return false


func diff_reward() -> float:
	## round 139: 1.0 on Standard; what the chosen difficulty pays on kills (qi, and the odds of an extra find)
	var d = sys("difficulty")
	var bo = sys("boons")                                                  # round 144: a hardship taken for the trip pays a little
	return 1.0 + (d.reward() if d != null else 0.0) + (bo.reward() if bo != null else 0.0)


func challenge_mult() -> float:
	## ascension: every climb after the first, the deep is harder (and richer)
	return 1.0 + float(retention_data().get("ascension", {}).get("foe_scale_per", 0.25)) * int(ascension.get("count", 0))


func event_for(level_id: String) -> Dictionary:
	var e: Dictionary = world_events.get(level_id, {})
	if e.is_empty() or str(e.get("day", "")) != today() or str(e.get("id", "")) == "":
		return {}
	var d: Dictionary = retention_data().get("events", {}).get("list", {}).get(str(e["id"]), {}).duplicate()
	d["id"] = str(e["id"])
	return d


func active_event() -> Dictionary:
	return event_for(current_level)


func roll_world_event(level_id: String, level_def: Dictionary) -> Dictionary:
	## Now and then a floor isn't itself today: a Blood Moon, a Spirit Tide, a
	## wandering master... Decided once per floor per day; the longer it's
	## been since the last one, the likelier the next.
	if not retention_live:
		return {}
	var d := int(level_def.get("depth", 0))
	var E: Dictionary = retention_data().get("events", {})
	if d < int(E.get("min_depth", 2)) or bool(level_def.get("trial", false)) or bool(level_def.get("arena", false)) \
			or level_id.begins_with("tribulation:") or TowerGen.is_tower(level_id) or str(level_def.get("theme", "")) in ["village", "settlement"]:
		return {}
	var e: Dictionary = world_events.get(level_id, {})
	if str(e.get("day", "")) == today():
		return event_for(level_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("event|%s|%s|%d" % [level_id, today(), int(counters.get("event_pity", 0.0))])
	var ch := minf(float(E.get("base_chance", 0.05)) + float(E.get("pity_step", 0.012)) * float(counters.get("event_pity", 0.0)), float(E.get("max_chance", 0.3)))
	var pick := ""
	if rng.randf() < ch:
		var pool := []
		var total := 0.0
		var lst: Dictionary = E.get("list", {})
		var keys: Array = lst.keys()
		keys.sort()
		for k in keys:
			if d >= int(lst[k].get("min_depth", 0)):
				pool.append(k)
				total += float(lst[k].get("weight", 1))
		var r := rng.randf() * total
		for k in pool:
			r -= float(lst[k].get("weight", 1))
			if r <= 0.0:
				pick = str(k)
				break
	world_events[level_id] = {"id": pick, "day": today()}
	if pick == "":
		counters["event_pity"] = float(counters.get("event_pity", 0.0)) + 1.0
		return {}
	counters["event_pity"] = 0.0
	log_event("world_event", {"event": pick, "level": level_id})
	return event_for(level_id)


func force_event(level_id: String, id: String) -> void:
	## (tests, and the Trial Board's rumour of one)
	world_events[level_id] = {"id": id, "day": today()}


# ---- the daily trial ---------------------------------------------------------------

func trial_mods(day: String = "") -> Array:
	var D: Dictionary = retention_data().get("daily", {})
	return TrialGen.mods_for(day if day != "" else today(), D.get("mods", {}), D.get("mods_per_day", [1, 2]))


func trial_mod_names(day: String = "") -> Array:
	var out := []
	for m in trial_mods(day):
		var md: Dictionary = retention_data().get("daily", {}).get("mods", {}).get(m, {})
		out.append("%s -- %s" % [md.get("name", m), md.get("desc", "")])
	return out


func trial_depth() -> int:
	## the trial meets you where you are: as deep as you've reached (and there's a floor's foes for)
	var want := reach_depth()
	var best := 1
	for e in enemies:
		var f := int(enemies[e].get("floor", -1))
		if f > 0 and f <= want and not bool(enemies[e].get("passive", false)):
			best = maxi(best, f)
	return best


func trial_level_def(level_id: String) -> Dictionary:
	var d := trial_depth()
	var pool := []
	var boss := ""
	for e in enemies:
		var ed: Dictionary = enemies[e]
		if int(ed.get("floor", -1)) != d or bool(ed.get("passive", false)):
			continue
		if bool(ed.get("boss", false)):
			boss = str(e)
		else:
			pool.append(str(e))
	var day := TrialGen.day_of(level_id)
	return TrialGen.generate(level_id, d, pool, boss, trial_mods(day), retention_data().get("daily", {}))


func trial_done_today() -> bool:
	return (trials.get("done", {}) as Dictionary).has(today())


func start_trial() -> void:
	trials["run"] = {"day": today(), "t0": playtime, "hp_lost": 0, "kills": 0, "elites": 0, "done": false}
	log_event("daily_trial_start", {"mods": trial_mods()})
	go_to(TrialGen.make_id(today()), "<")


func in_trial() -> bool:
	return TrialGen.is_trial(current_level)


func trial_note_kill(was_elite: bool) -> void:
	var run: Dictionary = trials.get("run", {})
	if run.is_empty() or not in_trial():
		return
	run["kills"] = int(run.get("kills", 0)) + 1
	if was_elite:
		run["elites"] = int(run.get("elites", 0)) + 1
	trials["run"] = run


func trial_note_hurt(amount: int) -> void:
	var run: Dictionary = trials.get("run", {})
	if not run.is_empty() and in_trial():
		run["hp_lost"] = int(run.get("hp_lost", 0)) + amount
		trials["run"] = run


func trial_check_clear(tree: SceneTree) -> void:
	## the last foe in the trial falls: it's done
	if tree == null or not in_trial():
		return
	var left := 0
	for e in tree.get_nodes_in_group("enemy"):
		if not bool(e.stats.get("passive", false)):
			left += 1
	if left == 0:
		trial_complete()


func trial_score(run: Dictionary) -> int:
	var S: Dictionary = retention_data().get("daily", {}).get("score", {})
	var secs := maxf(playtime - float(run.get("t0", playtime)), 0.0)
	return maxi(0, int(float(S.get("base", 1000)) + float(S.get("per_kill", 40)) * int(run.get("kills", 0)) + float(S.get("elite", 60)) * int(run.get("elites", 0))
		- float(S.get("per_second", 2)) * secs - float(S.get("per_hp_lost", 1)) * int(run.get("hp_lost", 0))))


func _days_between(a: String, b: String) -> int:
	if a == "" or b == "":
		return 9999
	var ta := Time.get_unix_time_from_datetime_string(a + "T12:00:00")
	var tb := Time.get_unix_time_from_datetime_string(b + "T12:00:00")
	return int(round((tb - ta) / 86400.0))


func trial_complete() -> Dictionary:
	var run: Dictionary = trials.get("run", {})
	if run.is_empty() or bool(run.get("done", false)):
		return {}
	run["done"] = true
	trials["run"] = run
	var day := str(run.get("day", today()))
	var score := trial_score(run)
	var best: Dictionary = trials.get("best", {})
	var improved := score > int(best.get(day, -1))
	if improved:
		best[day] = score
	trials["best"] = best
	var done: Dictionary = trials.get("done", {})
	var first := not done.has(day)
	var lines := ["Score %d (%d foes, %d elites, %d health lost)." % [score, int(run.get("kills", 0)), int(run.get("elites", 0)), int(run.get("hp_lost", 0))]]
	if first:
		done[day] = score
		trials["done"] = done
		# the streak: coming back is rewarded; a missed day only costs a little
		var gap := _days_between(str(trials.get("last_day", "")), day)
		var streak := int(trials.get("streak", 0))
		if gap == 1:
			streak += 1
		elif gap > 1:
			streak = maxi(0, streak - (gap - 1)) + 1        # each missed day wears it down by one
		else:
			streak = maxi(streak, 1)
		trials["streak"] = streak
		trials["last_day"] = day
		var R: Dictionary = retention_data().get("daily", {}).get("reward", {})
		var d := trial_depth()
		var g := int(R.get("gold_per_depth", 30)) * d
		gold += g
		var mk := int(R.get("marks", 3)) + int(R.get("streak_marks", 1)) * mini(streak, int(R.get("streak_cap", 7)))
		marks += mk
		gain_insight(float(R.get("insight", 3.0)), "the daily trial")
		var mats := []
		for i in int(R.get("material_rolls", 2)):
			var m := drop_body_piece(d, 1) if i == 0 else ""
			if m != "":
				mats.append(item_name(m))
		lines.append(I18n.t("+%d gold, +%d trial marks (streak %d day%s), +%.0f insight%s.") % [g, mk, streak, "" if streak == 1 else "s",
			float(R.get("insight", 3.0)), (", " + ", ".join(mats)) if mats.size() > 0 else ""])
		lines.append(I18n.t("Spend marks at the Trial Board in Eliet. A new trial is posted tomorrow."))
		log_event("daily_trial_done", {"score": score, "streak": streak})
		if steam:
			steam.achieve("TRIAL_FIRST")
			if streak >= 7:
				steam.achieve("TRIAL_STREAK_7")
	else:
		lines.append(I18n.t("(Today's rewards are already yours%s.)") % (I18n.t(" -- but that's a new best") if improved else ""))
	if steam:
		steam.leaderboard("daily_" + day.replace("-", ""), score)
	big_moment.emit("Trial Cleared", "\n".join(lines))
	jingle("trial")
	stats_changed.emit()
	return {"score": score, "first": first}


# ---- the week's sect trials ---------------------------------------------------------

func week_key() -> int:
	## weeks counted from a Monday (1970-01-01 was a Thursday)
	return int(floor((Time.get_unix_time_from_system() / 86400.0 + 3.0) / 7.0))


func weekly_goals() -> Array:
	_ensure_week()
	return trials.get("goals", [])


func _ensure_week() -> void:
	var wk := week_key()
	if int(trials.get("week", -1)) == wk and trials.get("goals", []) is Array and not (trials["goals"] as Array).is_empty():
		return
	var W: Dictionary = retention_data().get("weekly", {})
	var pool: Array = (W.get("pool", []) as Array).duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("week|%d" % wk)
	var goals := []
	while goals.size() < int(W.get("goals_per_week", 3)) and pool.size() > 0:
		var g: Dictionary = pool[rng.randi() % pool.size()]
		pool.erase(g)
		goals.append(g)
	trials["week"] = wk
	trials["goals"] = goals
	trials["progress"] = {}
	trials["claimed"] = {}


func weekly_note(kind: String) -> void:
	if not retention_live or kind.begins_with("weekly_"):
		return
	_ensure_week()
	var P: Dictionary = trials.get("progress", {})
	var C: Dictionary = trials.get("claimed", {})
	for g in trials.get("goals", []):
		var ev = g.get("event", "")
		var hit: bool = (ev is Array and kind in ev) or str(ev) == kind
		if not hit:
			continue
		var gid := str(g.get("id", ""))
		P[gid] = int(P.get(gid, 0)) + 1
		if int(P[gid]) >= int(g.get("need", 1)) and not C.has(gid):
			C[gid] = true
			var R: Dictionary = retention_data().get("weekly", {}).get("reward", {})
			marks += int(R.get("marks", 6))
			gold += int(R.get("gold", 250))
			trials["claimed"] = C
			trials["progress"] = P
			gain_insight(float(R.get("insight", 5.0)), "the week's sect trial")
			message.emit(I18n.t("WEEKLY TRIAL DONE: %s -- +%d marks, +%d gold.") % [str(g.get("text", "")) % int(g.get("need", 1)), int(R.get("marks", 6)), int(R.get("gold", 250))])
			log_event("weekly_done", {"goal": gid})
			if C.size() >= (trials.get("goals", []) as Array).size():
				var A: Dictionary = R.get("all_three", {})
				marks += int(A.get("marks", 10))
				if str(A.get("item", "")) != "":
					add_item(str(A["item"]), int(A.get("count", 1)))
				message.emit("All of this week's sect trials done: +%d marks." % int(A.get("marks", 10)))
				log_event("weekly_all", {})
				if steam:
					steam.achieve("WEEK_ALL")
	trials["progress"] = P
	trials["claimed"] = C


func weekly_rows() -> Array:
	var out := []
	var P: Dictionary = trials.get("progress", {})
	for g in weekly_goals():
		var gid := str(g.get("id", ""))
		out.append([str(g.get("text", "")) % int(g.get("need", 1)), mini(int(P.get(gid, 0)), int(g.get("need", 1))), int(g.get("need", 1)), (trials.get("claimed", {}) as Dictionary).has(gid)])
	return out


func week_left_text() -> String:
	var next_monday := (week_key() + 1) * 7 - 3
	return _dur(next_monday * 86400.0 - Time.get_unix_time_from_system())


# ---- the Trial Board's marks -----------------------------------------------------------

func shop_rows() -> Array:
	return retention_data().get("shop", [])


func buy_with_marks(sid: String) -> String:
	for s in shop_rows():
		if str(s.get("id", "")) != sid:
			continue
		var cost := int(s.get("cost", 99))
		if bool(s.get("essence", false)) and not blood_awake():
			return I18n.t("The keeper shakes her head: \"Your blood hasn't woken. Come back when it has -- deep down, around the twentieth floor.\"")
		if marks < cost:
			return I18n.t("You need %d marks (you have %d).") % [cost, marks]
		if bool(s.get("essence", false)):
			var id: String = blood_dominant() if blood_dominant() != "" else str(blood_ids()[randi() % blood_ids().size()])
			marks -= cost
			add_item("essence_" + id, 1)
			log_event("marks_spent", {"on": sid})
			return I18n.t("A drop of %s blood, sealed in wax.") % blood_line(id).get("name", id)
		if bool(s.get("formula", false)):
			var unknown := []
			for fid in craft_data().get("formulas", {}):
				if not knows_formula(str(fid)):
					unknown.append(str(fid))
			if unknown.is_empty():
				return I18n.t("You know every formula the keeper has.")
			marks -= cost
			var f: String = unknown[randi() % unknown.size()]
			learn_formula(f, "bought")
			log_event("marks_spent", {"on": sid})
			return I18n.t("A formula: %s.") % formula_def(f).get("name", f)
		if s.has("item") and str(items.get(str(s["item"]), {}).get("type", "")) == "material" and not has_home() and not (sys("tester") != null and sys("tester").vault_on()) \
				and count(str(s["item"])) + int(s.get("count", 1)) > pouch_cap():
			return I18n.t("Your pouch can't hold that many %s (%d) and you have no chest at home yet -- use some first. Nothing was spent.") % [item_name(str(s["item"])), pouch_cap()]
		marks -= cost
		if s.has("insight"):
			gain_insight(float(s["insight"]), "the trial-keeper's notes")
		if s.has("item"):
			add_item(str(s["item"]), int(s.get("count", 1)))
		log_event("marks_spent", {"on": sid})
		stats_changed.emit()
		return I18n.t("%s: yours.") % s.get("name", sid)
	return ""


# ---- collections ---------------------------------------------------------------------

func collections() -> Array:
	## [{"id", "name", "have", "total"}] -- the things worth completing
	var out := []
	var foes := []
	var beasts := []
	for e in enemies:
		var ed: Dictionary = enemies[e]
		if int(ed.get("floor", -1)) <= 0:
			continue
		if bool(ed.get("passive", false)):
			beasts.append(str(e))
		else:
			foes.append(str(e))
	out.append({"id": "bestiary", "name": I18n.t("Bestiary (foes defeated)"), "have": foes.filter(func(x): return int(kills.get(x, 0)) > 0).size(), "total": foes.size()})
	out.append({"id": "beasts", "name": I18n.t("Beasts hunted"), "have": beasts.filter(func(x): return int(kills.get(x, 0)) > 0).size(), "total": beasts.size()})
	var mats: Array = (craft_data().get("materials", {}) as Dictionary).keys()
	out.append({"id": "materials", "name": I18n.t("Materials understood"), "have": mats.filter(func(x): return mat_known.has(x)).size(), "total": mats.size()})
	var lms: Array = valley_data().get("landmarks", [])
	out.append({"id": "landmarks", "name": I18n.t("Valley landmarks"), "have": lms.filter(func(l): return has_flag("landmark:%s" % l.get("name", ""))).size(), "total": lms.size()})
	var dr: Array = discovery_rows()
	out.append({"id": "discoveries", "name": I18n.t("Discoveries"), "have": dr.filter(func(r): return bool(r[2])).size(), "total": dr.size()})
	out.append({"id": "bloodlines", "name": I18n.t("Bloodlines known"), "have": (bloodline.get("known", {}) as Dictionary).size(), "total": blood_ids().size()})
	return out.filter(func(c): return int(c["total"]) > 0)


func check_collections() -> Array:
	if not retention_live:
		return []
	var C: Dictionary = retention_data().get("collections", {})
	var tiers: Array = C.get("tiers", [25, 50, 75, 100])
	var got := []
	for c in collections():
		var pct := 100.0 * float(c["have"]) / maxf(float(c["total"]), 1.0)
		for i in tiers.size():
			var key := "%s:%d" % [c["id"], int(tiers[i])]
			if pct >= float(tiers[i]) and not coll_claimed.has(key):
				coll_claimed[key] = true
				var mk := int((C.get("reward_marks", []) as Array)[i]) if i < (C.get("reward_marks", []) as Array).size() else 3
				marks += mk
				gain_insight(float((C.get("reward_insight", []) as Array)[i]) if i < (C.get("reward_insight", []) as Array).size() else 2.0, "a collection")
				message.emit(I18n.t("COLLECTION -- %s %d%%: +%d trial marks.") % [c["name"], int(tiers[i]), mk])
				log_event("collection", {"id": c["id"], "tier": int(tiers[i])})
				got.append(key)
				if steam and int(tiers[i]) == 100:
					steam.achieve("COLL_" + str(c["id"]).to_upper())
	return got


func collection_nudge() -> String:
	## "almost there": the collection nearest its next tier
	var best := ""
	var best_left := 1 << 30
	var tiers: Array = retention_data().get("collections", {}).get("tiers", [25, 50, 75, 100])
	for c in collections():
		for t in tiers:
			var need := int(ceil(float(t) / 100.0 * float(c["total"])))
			if int(c["have"]) < need:
				var left := need - int(c["have"])
				if left < best_left:
					best_left = left
					best = I18n.t("%s: %d more for %d%%") % [str(c["name"]).get_slice(" (", 0), left, int(t)]
				break
	return best if best_left <= 3 else ""


func bestiary_mult(etype: String) -> float:
	## you hit what you've studied harder: 10 of a kind, then 50
	var B: Dictionary = retention_data().get("collections", {}).get("bestiary", {})
	var k := int(kills.get(etype, 0))
	if k >= int(B.get("mastered", 50)):
		return float(B.get("mastered_bonus", 1.1))
	if k >= int(B.get("studied", 10)):
		return float(B.get("studied_bonus", 1.04))
	return 1.0


# ---- ascension ---------------------------------------------------------------------------

func can_ascend() -> String:
	var A: Dictionary = retention_data().get("ascension", {})
	if reach_depth() >= int(A.get("unlock_depth", 25)) or realm >= int(A.get("unlock_realm", 3)):
		return ""
	return I18n.t("Reach floor %d or %s first.") % [int(A.get("unlock_depth", 25)), realm_info(int(A.get("unlock_realm", 3)))["name"]]


func ascension_marks() -> int:
	var A: Dictionary = retention_data().get("ascension", {})
	var coll := 0
	for c in collections():
		coll += int(c["have"])
	coll = maxi(0, coll - int(ascension.get("coll_paid", 0)))      # round 57: what you kept from a past life was paid for then
	return int(float(A.get("marks_per_depth", 1.0)) * reach_depth() + float(A.get("marks_per_realm", 6.0)) * realm + float(A.get("marks_per_collection", 0.5)) * coll)


func boon_rank(bid: String) -> int:
	return int((ascension.get("boons", {}) as Dictionary).get(bid, 0))


func boon_cost(bid: String) -> int:
	var b: Dictionary = retention_data().get("ascension", {}).get("boons", {}).get(bid, {})
	var r := boon_rank(bid)
	var costs: Array = b.get("cost", [])
	return int(costs[r]) if r < costs.size() and r < int(b.get("max", 0)) else -1


func buy_boon(bid: String) -> String:
	var c := boon_cost(bid)
	if c < 0:
		return I18n.t("That boon is as strong as it gets.")
	if int(ascension.get("marks", 0)) < c:
		return I18n.t("You need %d heavenly marks.") % c
	ascension["marks"] = int(ascension.get("marks", 0)) - c
	var B: Dictionary = ascension.get("boons", {})
	B[bid] = boon_rank(bid) + 1
	ascension["boons"] = B
	log_event("boon", {"id": bid, "rank": B[bid]})
	stats_changed.emit()
	return I18n.t("%s, rank %d.") % [retention_data().get("ascension", {}).get("boons", {}).get(bid, {}).get("name", bid), B[bid]]


func ascension_effect() -> Dictionary:
	var out := {}
	var Bd: Dictionary = retention_data().get("ascension", {}).get("boons", {})
	for bid in ascension.get("boons", {}):
		var r := boon_rank(str(bid))
		var b: Dictionary = Bd.get(str(bid), {})
		if b.has("qi_mult"):
			out["qi_mult"] = 1.0 + float(b["qi_mult"]) * r
		if b.has("hp_mult"):
			out["hp_mult"] = 1.0 + float(b["hp_mult"]) * r
	return out


func heirloom_count() -> int:
	return 1 + boon_rank("heirloom")


func ascend() -> String:
	## Begin the climb again, stronger: the deep gets harder, your boons and
	## your blood (part of it) come with you, and what you've learned stays.
	var why := can_ascend()
	if why != "":
		return why
	var A: Dictionary = retention_data().get("ascension", {})
	var earned := ascension_marks()
	var asc := ascension.duplicate(true)
	asc["count"] = int(asc.get("count", 0)) + 1
	asc["marks"] = int(asc.get("marks", 0)) + earned
	var coll_now := 0
	for c in collections():
		coll_now += int(c["have"])
	asc["coll_paid"] = maxi(int(asc.get("coll_paid", 0)), coll_now)
	asc["best_depth"] = maxi(int(asc.get("best_depth", 0)), reach_depth())
	# round 37: what you did in a past life still counts toward mastery
	var ever: Dictionary = asc.get("ever", {})
	for e in ["story:ending_sealed", "story:ending_delver"]:
		if has_flag(e):
			ever[e] = true
	for lid in bloodline.get("purity", {}):
		if float(bloodline["purity"][lid]) >= 100.0:
			ever["pure:" + str(lid)] = true
	asc["ever"] = ever
	# what comes with you
	var keep := {"achievements": achievements.duplicate(), "coll_claimed": coll_claimed.duplicate(), "trials": trials.duplicate(true), "marks": marks,
		"mat_known": mat_known.duplicate(), "formulas_known": formulas_known.duplicate(), "discoveries": discoveries.duplicate(), "kills": kills.duplicate()}
	var heir := []
	var worn := worn_ids()
	worn.sort_custom(func(a, b): return _piece_score(str(a)) > _piece_score(str(b)))
	if weapon != "":
		heir.append(weapon)
	for id in worn:
		if heir.size() >= heirloom_count() + (1 if weapon != "" else 0):
			break
		if not heir.has(id):
			heir.append(str(id))
	var kb := float(A.get("keep_blood", 0.6))
	for bid in asc.get("boons", {}):
		kb += float(A.get("boons", {}).get(str(bid), {}).get("keep_blood", 0.0)) * int(asc["boons"][bid])
	var old_blood := bloodline.duplicate(true)
	var custom := custom_items.duplicate(true)
	var old_weapon := weapon
	new_game()
	for k in keep:
		set(k, keep[k])
	ascension = asc
	# the blood comes with you, thinner -- and wakes again in the deep
	var P: Dictionary = {}
	for id in old_blood.get("purity", {}):
		P[id] = snappedf(float(old_blood["purity"][id]) * minf(kb, 1.0), 0.01)
	bloodline["purity"] = P
	bloodline["dominant"] = str(old_blood.get("dominant", ""))
	bloodline["secondary"] = str(old_blood.get("secondary", ""))
	bloodline["known"] = old_blood.get("known", {})
	bloodline["hidden"] = {}
	for id in heir:
		if custom.has(id):
			custom_items[id] = custom[id]
			items[id] = custom[id]
		add_item(str(id), 1, false)
		if str(id) == old_weapon:
			equip(str(id))
		else:
			wear(str(id))
	var Bd: Dictionary = A.get("boons", {})
	gold += int(Bd.get("start_gold", {}).get("gold", 150)) * boon_rank("start_gold")
	insight += float(Bd.get("clear_mind", {}).get("insight", 5.0)) * boon_rank("clear_mind")
	log_event("ascend", {"count": asc["count"], "marks": earned})
	if steam:
		steam.achieve("ASCEND_1")
		steam.stat("ascensions", int(asc["count"]))
	message.emit(I18n.t("ASCENSION %d: you begin again, with %d heavenly marks to spend at the Trial Board.") % [int(asc["count"]), int(asc["marks"])])
	save_game()
	go_to("village", "P")
	return ""


# ---- coming back -------------------------------------------------------------------------

func welcome_lines() -> Array:
	## what's new since you were last here (for the welcome window)
	var out := []
	if not trial_done_today():
		out.append(I18n.t("A new daily trial is posted at the Trial Board: %s.") % ", ".join(trial_mods().map(func(m): return str(retention_data().get("daily", {}).get("mods", {}).get(m, {}).get("name", m)))))
	var st := int(trials.get("streak", 0))
	if st > 1:
		out.append(I18n.t("Your trial streak: %d days (it only fades a little if you miss one).") % st)
	var open := weekly_rows().filter(func(r): return not bool(r[3]))
	if open.size() > 0:
		out.append(I18n.t("This week's sect trials: %s (%s left).") % ["; ".join(open.map(func(r): return "%s %d/%d" % [r[0], r[1], r[2]])), week_left_text()])
	var nudge := collection_nudge()
	if nudge != "":
		out.append(I18n.t("Almost there -- ") + nudge + ".")
	return out


func r30_save() -> Dictionary:
	return {"bloodline": bloodline, "trials": trials, "marks": marks, "coll_claimed": coll_claimed, "world_events": world_events, "ascension": ascension,
		"taming_perks": taming_perks, "mq": mq, "buffs": buffs, "hm": hm, "fog_seen": fog_seen, "attrs": attrs,
		"char_name": char_name, "look": look, "born": born, "fog_frac": fog_frac,
		"inscriptions": inscriptions, "talisman_ready": talisman_ready,
		"contracts": contracts, "companion2": companion2, "systems": _systems_save()}


func r30_load(d: Dictionary) -> void:
	for k in ["bloodline", "trials", "coll_claimed", "world_events", "ascension"]:
		var v = d.get(k, {})
		set(k, v if v is Dictionary else {})
	marks = int(d.get("marks", 0))
	taming_perks = d.get("taming_perks", []) if d.get("taming_perks", []) is Array else []
	mq = d.get("mq", {}) if d.get("mq", {}) is Dictionary else {}
	buffs = d.get("buffs", {}) if d.get("buffs", {}) is Dictionary else {}
	hm = d.get("hm", {}) if d.get("hm", {}) is Dictionary else {}
	fog_seen = d.get("fog_seen", {}) if d.get("fog_seen", {}) is Dictionary else {}
	attrs = d.get("attrs", {}) if d.get("attrs", {}) is Dictionary else {}
	char_name = str(d.get("char_name", ""))
	look = d.get("look", {}) if d.get("look", {}) is Dictionary else {}
	born = d.get("born", {}) if d.get("born", {}) is Dictionary else {}
	fog_frac = d.get("fog_frac", {}) if d.get("fog_frac", {}) is Dictionary else {}
	r38_load(d)
	r39_load(d)
	_systems_load(d.get("systems", {}) if d.get("systems", {}) is Dictionary else {})
	if bloodline.is_empty():
		# a save from before bloodlines: born now, the same odds as anyone
		blood_new_game(hash(background + str(int(playtime))))
	if TrialGen.is_trial(current_level):
		current_level = "village"
		spawn_tag = "P"


# ======================================================================
# round 32 -- the story (Robert: "people and story")
# A main storyline across the floors: eight acts, each fired by something
# you did (a floor reached, a floor's master killed, the blood waking), told
# in a window, then waiting with the named townsperson in Eliet -- a scene
# and two choices with real consequences. The townspeople's arcs advance
# on those choices (new lines, one-time gifts), a rival can enter the
# valley, and the story ends in one of two ways on floor 25. Everything is
# flags (saved with the rest): story:<act>:open, story:<act>:done, and the
# choice's own flag. Words: data/story.json; Dev's win (data/drafts/story.json).
# ======================================================================

var story_def := {}


func story_data() -> Dictionary:
	if story_def.is_empty():
		var d = _load_json("res://data/story.json", {})
		story_def = (d if d is Dictionary else {}).duplicate(true)
		if not story_def.has("acts"):
			story_def["acts"] = []
		if not story_def.has("arcs"):
			story_def["arcs"] = {}
		var dr = _load_json("res://data/drafts/story.json", {})      # the writing room's words
		if dr is Dictionary:
			for it in dr.get("items", []):
				if not (it is Dictionary):
					continue
				for a in story_def["acts"]:
					if str(a.get("id", "")) != str(it.get("act", it.get("id", ""))):
						continue
					for k in ["name", "told", "say"]:
						if str(it.get(k, "")).strip_edges() != "":
							a[k] = str(it[k])
					var ch: Array = it.get("choices", [])
					if ch.is_empty():
						# the writing room's flat shape: choice_a / after_a, choice_b / after_b
						ch = [{"text": it.get("choice_a", ""), "after": it.get("after_a", "")}, {"text": it.get("choice_b", ""), "after": it.get("after_b", "")}]
					for i in mini(ch.size(), (a.get("choices", []) as Array).size()):
						var c = ch[i]
						var txt := str(c.get("text", "")) if c is Dictionary else str(c)
						if txt.strip_edges() != "":
							a["choices"][i]["text"] = txt
						if c is Dictionary and str(c.get("after", "")).strip_edges() != "":
							a["choices"][i]["after"] = str(c["after"])
	return story_def


func story_acts() -> Array:
	return story_data().get("acts", [])


func story_act(id: String) -> Dictionary:
	for a in story_acts():
		if str(a.get("id", "")) == id:
			return a
	return {}


func story_state(id: String) -> String:
	## "" (not yet), "open" (told, the townsperson waits), "done" (chosen)
	if has_flag("story:%s:done" % id):
		return "done"
	if has_flag("story:%s:open" % id):
		return "open"
	return ""


func story_check(trigger: String, value = true) -> Array:
	## something happened: open every act it fires. Returns the ids opened.
	var opened := []
	for a in story_acts():
		var id := str(a.get("id", ""))
		if id == "" or story_state(id) != "":
			continue
		var tr: Dictionary = a.get("trigger", {})
		if not tr.has(trigger):
			continue
		var need = tr[trigger]
		var fires := false
		match trigger:
			"floor_reached":
				fires = int(value) >= int(need)
			"boss_floor":
				fires = int(value) == int(need)
			_:
				fires = bool(need) and bool(value)
		if fires:
			_story_open(a)
			opened.append(id)
	return opened


func _story_open(a: Dictionary) -> void:
	var id := str(a.get("id", ""))
	set_flag("story:%s:open" % id)
	flags["story:%s:at" % id] = float(playtime)
	log_event("story_open", {"act": id})
	bump("story_acts")
	big_moment.emit(str(a.get("name", I18n.t("The Story"))), I18n.t("%s\n\n(%s is waiting to talk, in Eliet.)") % [str(a.get("told", "")), str(a.get("who", I18n.t("Someone")))])
	jingle("discovery")


func story_act_for(npc_name: String) -> Dictionary:
	## the act this townsperson has waiting (told, not yet chosen), if any
	for a in story_acts():
		if str(a.get("who", "")) == npc_name and story_state(str(a.get("id", ""))) == "open":
			return a
	return {}


func story_can_choose(choice: Dictionary) -> String:
	## "" if you can take this choice, else why not
	var need := int(choice.get("need_gold", 0))
	if need > 0 and gold < need:
		return I18n.t("You'd need %d gold for that (you have %d).") % [need, gold]
	return ""


func story_choose(act_id: String, idx: int) -> String:
	## take a choice: its consequences land, the act is done. Returns what happens next (the "after" text).
	var a := story_act(act_id)
	if a.is_empty() or story_state(act_id) != "open":
		return ""
	var ch: Array = a.get("choices", [])
	if idx < 0 or idx >= ch.size():
		return ""
	var c: Dictionary = ch[idx]
	var why := story_can_choose(c)
	if why != "":
		return why
	var happened := _story_apply(c.get("effect", {}), str(a.get("who", "")))
	if str(c.get("set", "")) != "":
		set_flag(str(c["set"]))
	set_flag("story:%s:done" % act_id)
	flags["story:%s:choice" % act_id] = idx
	log_event("story_choice", {"act": act_id, "choice": idx, "set": str(c.get("set", ""))})
	bump("story_choices")
	if steam:
		steam.achieve("story_" + act_id)
	stats_changed.emit()
	var txt := str(c.get("after", ""))
	if not happened.is_empty():
		txt += "\n\n(" + "; ".join(happened) + ")"
	return txt


func _story_apply(e: Dictionary, who: String) -> Array:
	## the consequences of a choice; returns short lines of what changed
	var out := []
	if e.has("gold"):
		var g := int(e["gold"])
		if g >= 0:
			add_item("gold", g, false)
			out.append(I18n.t("+%d gold") % g)
		else:
			gold = maxi(0, gold + g)
			out.append(I18n.t("%d gold") % g)
	if e.has("gold_frac"):
		var g2 := int(round(gold * float(e["gold_frac"])))
		gold = maxi(0, gold + g2)
		out.append(I18n.t("%d gold") % g2)
	if e.has("insight"):
		gain_insight(float(e["insight"]), "the story")
		out.append(I18n.t("+%d insight") % int(e["insight"]))
	if e.has("guild_rep"):
		for gid in e["guild_rep"]:
			if in_guild(str(gid)):
				add_guild_rep(str(gid), float(e["guild_rep"][gid]))
				out.append(I18n.t("+%d %s standing") % [int(e["guild_rep"][gid]), guild_name(str(gid))])
			else:
				flags["story:rep_owed:" + str(gid)] = float(flags.get("story:rep_owed:" + str(gid), 0.0)) + float(e["guild_rep"][gid])
				out.append(I18n.t("the %s will remember this when you join") % guild_name(str(gid)))
	if e.has("sect_contrib"):
		var n := float(e["sect_contrib"])
		if sect.is_empty():
			flags["story:contrib_owed"] = float(flags.get("story:contrib_owed", 0.0)) + n     # paid when you join one
			out.append(I18n.t("%d contribution waits in whichever sect you join") % int(n))
		else:
			sect_contrib(n, "the story")
			out.append(I18n.t("+%d sect contribution") % int(n))
	if e.has("item"):
		for id in e["item"]:
			add_item(str(id), int(e["item"][id]), false)
			out.append("%s x%d" % [item_name(str(id)), int(e["item"][id])])
	if e.has("title"):
		var t := str(e["title"])
		if not (t in titles):
			titles.append(t)
		out.append(I18n.t("title: ") + t)
	if e.has("essence"):
		var bid := blood_dominant()
		if bid == "":
			var ids: Array = (blood_data().get("lines", {}) as Dictionary).keys()
			ids.sort()
			if not ids.is_empty():
				bid = str(ids[hash(background) % ids.size()])
		if bid != "":
			retention_data()                                   # makes the essence items
			var eid := "essence_" + bid
			if items.has(eid):
				add_item(eid, int(e["essence"]), false)
				out.append("%s x%d" % [item_name(eid), int(e["essence"])])
	if e.has("purity") and float(e["purity"]) < 0.0:
		# the draught: your blood goes a little quiet, for good
		var bid3 := blood_dominant()
		if bid3 != "":
			var P: Dictionary = bloodline.get("purity", {})
			P[bid3] = maxf(1.0, float(P.get(bid3, 0.0)) + float(e["purity"]))
			bloodline["purity"] = P
			out.append(I18n.t("%d%% purity") % int(e["purity"]))
	elif e.has("purity"):
		var bid2 := blood_dominant()
		if bid2 != "":
			add_purity(bid2, float(e["purity"]), "the story")
			out.append(I18n.t("+%d%% purity") % int(e["purity"]))
		else:
			flags["story:purity_owed"] = float(flags.get("story:purity_owed", 0.0)) + float(e["purity"])
			out.append(I18n.t("your blood thickens; it will show when a line is yours"))
	if e.has("dao_heart"):
		dao_heart += float(e["dao_heart"])
		out.append(I18n.t("+%d%% dao heart") % int(e["dao_heart"]))
	if e.has("gear"):
		for i in int(e["gear"]):
			var gid := drop_gear(maxi(1, reach_depth()), 3)
			if gid != "":
				out.append(item_name(gid))
	if e.has("shop_discount"):
		flags["story:shop_discount"] = float(e["shop_discount"])
		flags["story:shop_discount_who"] = who
		out.append(I18n.t("%s's prices: %d%% off for you") % [who, int(float(e["shop_discount"]) * 100)])
	if e.has("flag"):
		set_flag(str(e["flag"]))
	return out


func story_owed_on_join() -> void:
	## contribution promised by the story lands when you join a sect
	var n := float(flags.get("story:contrib_owed", 0.0))
	if n > 0.0 and not sect.is_empty():
		flags.erase("story:contrib_owed")
		sect_contrib(n, "the story")
		message.emit("Your name was known here before you came: +%d contribution." % int(n))


func story_owed_on_blood(id: String) -> void:
	var n := float(flags.get("story:purity_owed", 0.0))
	if n > 0.0 and id != "":
		flags.erase("story:purity_owed")
		add_purity(id, n, "the story")


func shop_discount(npc_name: String) -> float:
	if str(flags.get("story:shop_discount_who", "")) == npc_name:
		return clampf(float(flags.get("story:shop_discount", 0.0)), 0.0, 0.9)
	return 0.0


func story_arc_text(npc_name: String) -> String:
	## what this townsperson says now, after what you chose -- the newest line
	## that applies -- and anything they've been meaning to give you (once)
	var rows: Array = story_data().get("arcs", {}).get(npc_name, [])
	var line := ""
	var gifts := []
	for i in rows.size():
		var r: Dictionary = rows[i]
		if not has_flag(str(r.get("after", ""))):
			continue
		line = str(r.get("line", ""))
		var gk := "story:gift:%s:%d" % [npc_name, i]
		if r.has("gift") and not has_flag(gk):
			set_flag(gk)
			gifts.append(_story_gift(r["gift"]))
	var out := line
	for g in gifts:
		if g != "":
			out += ("\n" if out != "" else "") + g
	return out


func _story_gift(g: Dictionary) -> String:
	if g.has("item"):
		var got := []
		for id in g["item"]:
			add_item(str(id), int(g["item"][id]), false)
			got.append("%s x%d" % [item_name(str(id)), int(g["item"][id])])
		return I18n.t("(They give you %s.)") % ", ".join(got)
	if g.has("gold"):
		add_item("gold", int(g["gold"]), false)
		return I18n.t("(They give you %d gold.)") % int(g["gold"])
	if g.has("gear"):
		var id := drop_gear(maxi(1, reach_depth()), 2)
		return I18n.t("(They give you %s.)") % item_name(id) if id != "" else ""
	if g.has("formula"):
		for f in craft_data().get("formulas", []):
			var fid := str(f.get("id", ""))
			if fid != "" and not formulas_known.has(fid):
				learn_formula(fid, "a gift")
				return I18n.t("(They teach you a formula: %s.)") % item_name(str(f.get("makes", fid)))
		return ""
	return ""


func story_rows() -> Array:
	## for the journal: [name, state, the line you chose]
	var out := []
	for a in story_acts():
		var id := str(a.get("id", ""))
		var st := story_state(id)
		if st == "":
			continue
		var chosen := ""
		if st == "done":
			var idx := int(flags.get("story:%s:choice" % id, 0))
			var ch: Array = a.get("choices", [])
			if idx < ch.size():
				chosen = str(ch[idx].get("text", ""))
		out.append([str(a.get("name", id)), st, chosen, str(a.get("who", ""))])
	return out


func story_ending() -> String:
	if has_flag("story:ending_sealed"):
		return "sealed"
	if has_flag("story:ending_delver"):
		return "delver"
	return ""


func story_sealed() -> bool:
	return story_ending() == "sealed" and not has_flag("story:seal_broken")


func break_seal() -> void:
	set_flag("story:seal_broken")
	log_event("seal_broken")
	big_moment.emit("The Seal Breaks", "The stone you set over the shaft comes up. Eliet watches you go down. Whatever you are now, the deep is still a mirror.")


func story_boss_killed(d: int) -> void:
	story_check("boss_floor", d)


# ---- round 33: the end of this game (Robert: "we can stop at level 50 for this
# game with a sequel or expansion pack"). The forge's last floor has a master
# called the Heart of the Deep, and the stairs past it lead to "ending".
signal ending_requested

func finale_check(tree: SceneTree) -> String:
	## "" if the way into the Heart is open, else why not
	for e in tree.get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e._dead and bool(e.stats.get("boss", false)):
			return I18n.t("The Heart still beats. Its master stands between you and it.")
	return ""


func finished() -> bool:
	return has_flag("story:finished")


func finale() -> void:
	## you walked into the Heart of the Deep and it let you go
	var first := not finished()
	set_flag("story:finished")
	counters["finished"] = float(counters.get("finished", 0.0)) + 1.0
	if not ("Heart of the Deep" in titles):
		titles.append(I18n.t("Heart of the Deep"))
	log_event("finished", {"depth": reach_depth(), "playtime": int(playtime), "ascension": int(ascension.get("count", 0))})
	if steam:
		steam.achieve("FINISHED")
		steam.stat("finished", int(counters["finished"]))
	jingle("achievement")
	if first:
		story_check("finished", true)       # Mo's last scene waits in Eliet
	stats_changed.emit()
	ending_requested.emit()


func epilogue_lines() -> Array:
	## the ending screen: what became of everyone, by what you chose
	var E: Dictionary = story_data().get("epilogue", {})
	var dr = _load_json("res://data/drafts/epilogue.json", {})
	if dr is Dictionary:
		for it in dr.get("items", []):
			if it is Dictionary and str(it.get("key", "")) != "" and str(it.get("text", "")).strip_edges() != "":
				E[str(it["key"])] = str(it["text"])
	var out := [str(E.get("opening", ""))]
	for key in ["sealed", "delver", "mo_forgiven", "mo_blamed", "wen_free", "wen_bound", "gave_share", "led_lodge", "spared_lodge", "draught", "no_draught", "shen_beaten", "envoy_no", "stayed", "went_east"]:
		var fl := "story:%s" % key
		if key in ["sealed", "delver"]:
			fl = "story:ending_" + key
		if has_flag(fl) and E.has(key):
			out.append(str(E[key]))
	if partner != "" and E.has("partner"):
		out.append(str(E["partner"]) % partner)
	elif not companion.is_empty() and E.has("companion"):
		out.append(str(E["companion"]) % str(companion.get("name", "")))
	if not familiar.is_empty() and E.has("familiar"):
		out.append(str(E["familiar"]) % familiar_title())
	if blood_dominant() != "" and E.has("blood"):
		out.append(str(E["blood"]) % str(blood_line(blood_dominant()).get("name", "")))
	if home_stage() >= 3 and E.has("home"):
		out.append(str(E["home"]))
	out.append(str(E.get("closing", "")))
	return out.filter(func(l): return str(l).strip_edges() != "")


func credits_lines() -> Array:
	return ["DUNGEON CRAWL ELITE", "a cultivation dungeon crawl",
		"", "Made by Robert, with Dev (the HomeAI box) writing the words and forging the floors, and Claude building the engine.",
		"Godot Engine 4 (MIT). Kenney's asset packs (CC0): nature, mini-dungeon, fantasy town, audio. Quaternius' monster models and the Bestiary (see LICENSE-bestiary.txt). GodotSteam (MIT).",
		"Music made by the game's own tools/music_gen.py.",
		"", I18n.t("You: %s, %s. %d floors. %s played. %d of %d achievements.") % [cultivation_label(), ", ".join(titles.slice(0, 3)) if not titles.is_empty() else "untitled", reach_depth(), _dur(playtime), achievements.size(), achievement_defs.size()]]


func rival_shen_live() -> bool:
	return has_flag("rival_shen") and not has_flag("story:shen_beaten")


# ======================================================================
# round 32 -- companions and pets grown up (Robert's fourth pick)
#   companions: a fighting style, gear of their own, levels, a life bar
#   familiars: stages (grown, fierce, spirit beast) as the bond deepens
#   taming: a skill, and a tree of perks (one choice a tier)
#   home: the plot grows into a cottage, a courtyard, a compound
# Words and numbers: data/companions.json. A companion's growth lives in
# their bond (bonds[name]: style, xp, gear) so it survives parting ways.
# ======================================================================

var companions_def := {}
var taming_perks := []           # the perk ids you chose (saved)


func companions_data() -> Dictionary:
	if companions_def.is_empty():
		var d = _load_json("res://data/companions.json", {})
		companions_def = d if d is Dictionary else {}
	return companions_def


# ---- companions ---------------------------------------------------------------
# Round 39 (Robert: "party of two"): every companion function takes the party
# SLOT it's about -- 0 the one who walks at your shoulder (`companion`), 1 the
# second (`companion2`, once the party has room). Their style, level and gear
# live in their bond (bonds[name]), so they keep them between journeys.

func cslot(slot: int = 0) -> Dictionary:
	return companion2 if slot == 1 else companion


func party_slots() -> Array:
	## the slots with someone in them
	var out := []
	for s in [0, 1]:
		if not cslot(s).is_empty():
			out.append(s)
	return out


func in_party(name: String) -> int:
	## which slot they're in (-1: not travelling with you)
	for s in [0, 1]:
		if str(cslot(s).get("name", "")) == name and name != "":
			return s
	return -1


func comp_bond(slot: int = 0) -> Dictionary:
	var cc := cslot(slot)
	return bond(str(cc.get("name", ""))) if not cc.is_empty() else {}


func companion_style(slot: int = 0) -> String:
	if cslot(slot).is_empty():
		return ""
	var st := str(comp_bond(slot).get("style", "striker"))
	return st if (companions_data().get("styles", {}) as Dictionary).has(st) else "striker"


func style_def(id: String = "", slot: int = 0) -> Dictionary:
	var S: Dictionary = companions_data().get("styles", {})
	return S.get(id if id != "" else companion_style(slot), S.get("striker", {}))


func set_companion_style(id: String, slot: int = 0) -> bool:
	var cc := cslot(slot)
	if cc.is_empty() or not (companions_data().get("styles", {}) as Dictionary).has(id):
		return false
	comp_bond(slot)["style"] = id
	log_event("companion_style", {"npc": cc.get("name", ""), "style": id})
	message.emit(I18n.t("%s will fight as a %s from now on.") % [cc.get("name", ""), style_def(id).get("name", id)])
	companion_changed.emit()
	return true


func companion_xp_total(slot: int = 0) -> float:
	return float(comp_bond(slot).get("xp", 0.0)) if not cslot(slot).is_empty() else 0.0


func companion_level(slot: int = 0) -> int:
	var L: Dictionary = companions_data().get("levels", {})
	var xp := companion_xp_total(slot)
	var lv := 0
	for need in L.get("xp", [0]):
		if xp >= float(need):
			lv += 1
	return maxi(0, lv - 1)


func companion_level_name(slot: int = 0) -> String:
	var names: Array = companions_data().get("levels", {}).get("names", ["green"])
	return str(names[mini(companion_level(slot), names.size() - 1)])


func companion_xp(n: float, why: String = "", slot: int = 0) -> void:
	var cc := cslot(slot)
	if cc.is_empty() or n <= 0.0:
		return
	var before := companion_level(slot)
	var b := comp_bond(slot)
	b["xp"] = float(b.get("xp", 0.0)) + n
	if companion_level(slot) > before:
		message.emit(I18n.t("%s has grown: %s now (level %d).") % [cc.get("name", ""), companion_level_name(slot), companion_level(slot)])
		log_event("companion_level", {"npc": cc.get("name", ""), "level": companion_level(slot)})
		jingle("levelup")
		stats_changed.emit()


func companion_gear(gslot: String, slot: int = 0) -> String:
	return str((comp_bond(slot).get("gear", {}) as Dictionary).get(gslot, "")) if not cslot(slot).is_empty() else ""


func give_companion_gear(id: String, slot: int = 0) -> String:
	## hand them a weapon or armour from your pouch; what they had comes back to you
	var cc := cslot(slot)
	if cc.is_empty() or not has_item_def(id) or count(id) <= 0:
		return I18n.t("You don't have that.")
	var t := str(item_def(id).get("type", ""))
	if t != "weapon" and t != "armor":
		return I18n.t("They can only carry a weapon or armour.")
	var b := comp_bond(slot)
	var g: Dictionary = b.get("gear", {})
	var old := str(g.get(t, ""))
	remove_item(id, 1)
	if old != "":
		add_item(old, 1, false)
	g[t] = id
	b["gear"] = g
	log_event("companion_gear", {"npc": cc.get("name", ""), "id": id})
	companion_changed.emit()
	stats_changed.emit()
	return I18n.t("%s takes the %s%s.") % [cc.get("name", ""), item_name(id), (I18n.t(" and hands you back the %s") % item_name(old)) if old != "" else ""]


func take_companion_gear(gslot: String, slot: int = 0) -> String:
	if cslot(slot).is_empty():
		return ""
	var b := comp_bond(slot)
	var g: Dictionary = b.get("gear", {})
	var old := str(g.get(gslot, ""))
	if old == "":
		return I18n.t("They carry nothing there.")
	g.erase(gslot)
	b["gear"] = g
	add_item(old, 1, false)
	companion_changed.emit()
	return I18n.t("You take back the %s.") % item_name(old)


func _ally_dmg() -> float:
	## round 122: a Tiger Spirit / Wind-Fleet boon on your companions and beasts
	var ax = sys("arts")
	return ax.ally_dmg_mult() if ax != null else 1.0


func _ally_take() -> float:
	var ax = sys("arts")
	return ax.ally_take_mult() if ax != null else 1.0


func companion_damage(slot: int = 0) -> int:
	## their strike: cultivation like yours, their weapon, their style, their level, and the warmth between you
	if cslot(slot).is_empty():
		return 0
	var w := companion_gear("weapon", slot)
	var bonus := int(item_def(w).get("damage", 0)) if w != "" and has_item_def(w) else 0
	var warmth := float(comp_bond(slot).get("warmth", 0.0))
	var lv := companion_level(slot)
	var per := float(companions_data().get("levels", {}).get("damage_per_level", 0.08))
	return maxi(1, int(round((9 + step_index() * 2 + realm * 6 + bonus) * float(style_def("", slot).get("damage", 1.0)) * (1.0 + per * lv) * (0.5 + warmth / 500.0) * tech_effect("damage_mult", 1.0) * _ally_dmg())))


func companion_max_hp(slot: int = 0) -> int:
	if cslot(slot).is_empty():
		return 0
	var H: Dictionary = companions_data().get("hp", {})
	var a := companion_gear("armor", slot)
	var armor := int(item_def(a).get("hp", 0)) if a != "" and has_item_def(a) else 0      # armour is I18n.t("+N max HP") here
	var per := float(companions_data().get("levels", {}).get("hp_per_level", 0.1))
	return maxi(10, int(round(max_hp() * float(H.get("base_frac", 0.7)) * (1.0 + per * companion_level(slot)) + armor * float(H.get("armor_mult", 2.5)) * 0.4)))


func companion_hp(slot: int = 0) -> int:
	var cc := cslot(slot)
	if cc.is_empty():
		return 0
	if not cc.has("hp"):
		cc["hp"] = companion_max_hp(slot)
	return int(cc["hp"])


func companion_down(slot: int = 0) -> bool:
	var cc := cslot(slot)
	return not cc.is_empty() and float(cc.get("down_until", 0.0)) > playtime


func companion_hurt(amount: int, source: String = "", slot: int = 0) -> void:
	var cc := cslot(slot)
	if cc.is_empty() or companion_down(slot):
		return
	amount = maxi(1, int(round(amount * _ally_take())))        # round 122: Mountain Skin reaches them too
	cc["hp"] = maxi(0, companion_hp(slot) - amount)
	if int(cc["hp"]) <= 0:
		var secs := float(companions_data().get("hp", {}).get("down_seconds", 90))
		cc["down_until"] = playtime + secs
		message.emit(I18n.t("%s goes down (%s)! They'll be back on their feet in %s -- or when you rest.") % [cc.get("name", ""), source, _dur(secs)])
		log_event("companion_down", {"npc": cc.get("name", ""), "by": source})
		sfx("hurt", 0.7)
	stats_changed.emit()


func companion_tick(delta: float, slot: int = 0) -> void:
	## slow mending on their feet; up again when the count runs out
	var cc := cslot(slot)
	if cc.is_empty():
		return
	if companion_down(slot):
		return
	if cc.has("down_until"):
		cc.erase("down_until")
		cc["hp"] = int(companion_max_hp(slot) * 0.5)
		message.emit("%s is up again." % cc.get("name", ""))
	var mx := companion_max_hp(slot)
	if companion_hp(slot) < mx:
		cc["hp"] = mini(mx, companion_hp(slot) + maxi(1, int(round(mx * float(companions_data().get("hp", {}).get("regen_per_sec", 0.015)) * delta))))


func companion_revive(slot: int = -1) -> void:
	## -1: everyone in the party (a night's rest)
	for s in ([0, 1] if slot < 0 else [slot]):
		var cc := cslot(s)
		if cc.is_empty():
			continue
		cc.erase("down_until")
		cc["hp"] = companion_max_hp(s)


func companion_intercept(amount: int, near: bool, slot: int = 0) -> int:
	## a Guard steps into a blow meant for you (so much of the time); returns what still reaches you
	var cc := cslot(slot)
	if cc.is_empty() or companion_down(slot) or not near:
		return amount
	var g := float(style_def("", slot).get("guard", 0.0))
	if g <= 0.0 or randf() >= g:
		return amount
	companion_hurt(amount, "a blow meant for you", slot)
	message.emit(I18n.t("%s takes the blow for you (-%d).") % [cc.get("name", ""), amount])
	log_event("companion_guard", {"npc": cc.get("name", "")})
	return 0


func companion_rows(slot: int = 0) -> Array:
	## for the journal, the talk window and the party page: [label, value]
	if cslot(slot).is_empty():
		return []
	var out := [["Style", str(style_def("", slot).get("name", I18n.t("Striker")))], ["Level", "%d (%s), %d xp" % [companion_level(slot), companion_level_name(slot), int(companion_xp_total(slot))]],
		["Life", "%d / %d%s" % [companion_hp(slot), companion_max_hp(slot), I18n.t(" -- DOWN") if companion_down(slot) else ""]], ["Strike", str(companion_damage(slot))]]
	for gs in ["weapon", "armor"]:
		var g := companion_gear(gs, slot)
		out.append([gs.capitalize(), item_name(g) if g != "" else "nothing"])
	return out


# ---- familiars: stages, bites, the taming tree -------------------------------

func _bst(b: Dictionary) -> Dictionary:
	## round 39: the beast a familiar_* function is about ({}: the one at your heel)
	return familiar if b.is_empty() else b


func familiar_stage(beast: Dictionary = {}) -> int:
	var f := _bst(beast)
	if f.is_empty():
		return 0
	var st: Array = companions_data().get("familiar", {}).get("stages", [])
	var b := float(f.get("bond", 0.0))
	var i := 0
	for k in st.size():
		if b >= float(st[k].get("bond", 0)):
			i = k
	return i


func familiar_stage_def(beast: Dictionary = {}) -> Dictionary:
	var st: Array = companions_data().get("familiar", {}).get("stages", [])
	return st[familiar_stage(beast)] if familiar_stage(beast) < st.size() else {}


func familiar_title(beast: Dictionary = {}) -> String:
	var f := _bst(beast)
	var t := str(familiar_stage_def(beast).get("title", ""))
	var mn = sys("menagerie")
	if mn != null:
		var fm: Dictionary = mn.form_of(f)
		if not fm.is_empty() and str(fm.get("title", "")) != "":
			t = I18n.t(str(fm["title"]))                  # round 153: its role's name for what it has become
	return (I18n.t("%s the %s") % [f.get("name", ""), t]) if t != "" else str(f.get("name", ""))


func familiar_effect_mult(beast: Dictionary = {}) -> float:
	## how much more a grown familiar gives (its stage, its contract, and Thick Hide)
	return float(familiar_stage_def(beast).get("effect", 1.0)) * (1.34 if has_perk("thick_hide") else 1.0) * float(contract_tier_def(beast).get("mult", 1.0))


func familiar_bite(beast: Dictionary = {}) -> int:
	## what its bite does (0: it doesn't bite yet)
	var frac := float(familiar_stage_def(beast).get("bite", 0.0))
	if frac <= 0.0:
		return 0
	return maxi(1, int(round(damage() * frac * (1.5 if has_perk("sharp_fangs") else 1.0) * float(contract_tier_def(beast).get("bite", 1.0)) * _ally_dmg())))


func familiar_find_seconds(base: float) -> float:
	var s := base
	if has_perk("keen_nose"):
		s /= 1.5
	if has_perk("quick_paws"):
		s /= 1.3
	return s


func familiar_stage_check(before: int, beast: Dictionary = {}) -> void:
	var f := _bst(beast)
	var now := familiar_stage(beast)
	if now > before:
		var sd := familiar_stage_def(beast)
		var told := str(sd.get("told", "%s has grown.")) % str(f.get("name", ""))
		big_moment.emit("%s -- %s" % [f.get("name", ""), str(sd.get("title", "")).capitalize()], told)
		log_event("familiar_stage", {"stage": now, "species": f.get("species", "")})
		jingle("discovery")
		if now >= 2:
			jingle("levelup")
			slow_mo(0.3, 0.5)                                   # round 153: a form is a moment
			var mn2 = sys("menagerie")
			if mn2 != null:
				var fm2: Dictionary = mn2.form_of(f)
				if not fm2.is_empty():
					message.emit(I18n.t("%s becomes %s.") % [str(f.get("name", "")), I18n.t(str(fm2["title"]))])
					if bool(fm2["awakened"]):
						message.emit(I18n.t("Awakened: %s.") % I18n.t(str(fm2["desc"])))
		familiar_changed.emit()
		stats_changed.emit()


func has_perk(id: String) -> bool:
	return id in taming_perks


func taming_level() -> int:
	return skill_level("taming")


func taming_tiers() -> Array:
	## every tier: [tier def, chosen id or "", open?]
	var out := []
	for t in companions_data().get("taming", {}).get("tiers", []):
		var chosen := ""
		for side in ["a", "b"]:
			if has_perk(str(t[side].get("id", ""))):
				chosen = str(t[side]["id"])
		out.append([t, chosen, chosen == "" and taming_level() >= int(t.get("skill", 1))])
	return out


func choose_perk(id: String) -> String:
	for row in taming_tiers():
		var t: Dictionary = row[0]
		for side in ["a", "b"]:
			if str(t[side].get("id", "")) == id:
				if row[1] != "":
					return I18n.t("You've already chosen for that tier.")
				if not row[2]:
					return I18n.t("You need Taming %d for that.") % int(t.get("skill", 1))
				taming_perks.append(id)
				log_event("taming_perk", {"id": id})
				message.emit(I18n.t("TAMING: %s -- %s") % [t[side].get("name", id), t[side].get("desc", "")])
				familiar_changed.emit()
				stats_changed.emit()
				return ""
	return I18n.t("No such perk.")


func taming_xp(kind: String) -> void:
	var T: Dictionary = companions_data().get("taming", {})
	add_skill_xp("taming", float(T.get("xp_" + kind, 1.0)), kind)


func tame_need_mult() -> float:
	return 0.5 if has_perk("wild_call") else 1.0


# ---- the home grows -------------------------------------------------------------

func home_stage() -> int:
	return int(home.get("stage", 0)) if has_home() else 0


func home_stage_def(i: int = -1) -> Dictionary:
	var st: Array = companions_data().get("compound", {}).get("stages", [])
	var k := home_stage() if i < 0 else i
	return st[k] if k >= 0 and k < st.size() else {}


func home_next_stage() -> Dictionary:
	return home_stage_def(home_stage() + 1)


func home_upgrade_check() -> String:
	## "" if you can build the next stage now, else why not
	var nx := home_next_stage()
	if nx.is_empty():
		return I18n.t("There's nothing more to build.")
	if gold < int(nx.get("cost", 0)):
		return I18n.t("It costs %d gold (you have %d).") % [int(nx.get("cost", 0)), gold]
	var short := []
	for id in nx.get("needs", {}):
		var have := count(str(id)) + int((stash_ref()).get(str(id), 0))
		if have < int(nx["needs"][id]):
			short.append("%s %d/%d" % [item_name(str(id)), have, int(nx["needs"][id])])
	if not short.is_empty():
		return I18n.t("It needs ") + ", ".join(short) + "."
	return ""


func home_upgrade() -> String:
	var why := home_upgrade_check()
	if why != "":
		return why
	var nx := home_next_stage()
	gold -= int(nx.get("cost", 0))
	for id in nx.get("needs", {}):
		var left := int(nx["needs"][id])
		var from_pouch := mini(left, count(str(id)))
		if from_pouch > 0:
			remove_item(str(id), from_pouch)
			left -= from_pouch
		if left > 0:
			var st: Dictionary = stash_ref()
			st[str(id)] = int(st.get(str(id), 0)) - left
			if int(st[str(id)]) <= 0:
				st.erase(str(id))
			home["stash"] = st
	home["stage"] = home_stage() + 1
	log_event("home_upgrade", {"stage": home_stage(), "id": nx.get("id", "")})
	note_place("Home grew into %s" % str(nx.get("name", "")))
	big_moment.emit("Your home is now %s" % str(nx.get("name", "")), str(nx.get("desc", "")))
	jingle("achievement")
	if steam:
		steam.achieve("home_" + str(nx.get("id", "")))
	stats_changed.emit()
	return ""


func home_rested_mult() -> float:
	var m := 1.0
	for i in range(1, home_stage() + 1):
		m = maxf(m, float(home_stage_def(i).get("rested_mult", 1.0)))
	return m


func home_has_shrine() -> bool:
	for i in range(1, home_stage() + 1):
		if bool(home_stage_def(i).get("shrine", false)):
			return true
	return false


func home_away_lines(hours: float) -> Array:
	## what a compound does for yours while you're gone
	var out := []
	var xp_h := 0.0
	var bond_h := 0.0
	for i in range(1, home_stage() + 1):
		xp_h = maxf(xp_h, float(home_stage_def(i).get("away_xp_per_hour", 0.0)))
		bond_h = maxf(bond_h, float(home_stage_def(i).get("away_bond_per_hour", 0.0)))
	for ps in party_slots():                       # round 39: both of a party of two train
		if xp_h > 0.0:
			companion_xp(hours * xp_h, "training at home", ps)
			out.append(I18n.t("%s trained in the yard: +%d experience.") % [cslot(ps).get("name", ""), int(hours * xp_h)])
	if bond_h > 0.0 and not familiar.is_empty():
		var before := familiar_stage()
		grow_bond(hours * bond_h)
		familiar_stage_check(before)
		out.append(I18n.t("%s was fed and walked: bond +%d.") % [familiar.get("name", ""), int(hours * bond_h)])
	return out


# ======================================================================
# round 34 -- the climb has to be earned (Robert: "days and hours of play
# time, each level a little harder, bottlenecks that need more training,
# items, alchemy to push through; more crafting, more quests, a main
# storyline quest that keeps players going in the right direction")
#   gates     the stairs down to floors 6/11/16/... refuse until you meet
#             the need (data/gates.json): a realm, a skill, a story act, a
#             crafted item used up on the way down
#   buffs     crafted consumables that last a while (whetstone, incense...)
#   main quest  chapters with goals the game checks itself; report to a
#             townsperson for the reward; the HUD always shows the next goal
#   errands   Elder Mo's per-floor kill and gather errands, from each
#             floor's own foes and materials
#   curve     every floor a little harder (data/combat.json "curve")
# ======================================================================

var gates_def := {}
var mq_def := {}
var mq := {}                    # {"chapter": int, "done": {id: true}} (saved)
var buffs := {}                 # id -> {"until": unix, "effect": {...}} (saved)


func gates_data() -> Dictionary:
	if gates_def.is_empty():
		var d = _load_json("res://data/gates.json", {})
		gates_def = (d if d is Dictionary else {}).duplicate(true)
		var dr = _load_json("res://data/drafts/gates.json", {})
		if dr is Dictionary:
			for it in dr.get("items", []):
				if it is Dictionary:
					for g in gates_def.get("gates", []):
						if int(g.get("floor", 0)) == int(it.get("floor", -1)) and str(it.get("text", "")).strip_edges() != "":
							g["text"] = str(it["text"])
	return gates_def


func gate_for(d: int) -> Dictionary:
	for g in gates_data().get("gates", []):
		if int(g.get("floor", 0)) == d:
			return g
	return {}


func floor_depth(level_id: String) -> int:
	if level_id.begins_with("floor"):
		return int(level_id.trim_prefix("floor").get_slice(":", 0))
	return 0


func gate_passed(d: int) -> bool:
	return has_flag("gate:%d:passed" % d)


func gate_missing(d: int) -> Array:
	## what you still lack for the gate to floor d (empty: it's open)
	var g := gate_for(d)
	if g.is_empty() or gate_passed(d):
		return []
	var need: Dictionary = g.get("need", {})
	var out := []
	if need.has("realm") and realm < int(need["realm"]):
		var rn := str(realm_info(int(need["realm"]))["name"])
		out.append(rn if rn.contains("Realm") else I18n.t("the %s realm") % rn)
	if need.has("skill"):
		var sk: Dictionary = need["skill"]
		if skill_level(str(sk.get("id", ""))) < int(sk.get("level", 1)):
			out.append("%s %d" % [skill_name(str(sk.get("id", ""))), int(sk.get("level", 1))])
	if need.has("weapon_skill") and skill_level(weapon_skill()) < int(need["weapon_skill"]):
		out.append(I18n.t("%s %d (the weapon you carry)") % [skill_name(weapon_skill()), int(need["weapon_skill"])])
	if need.has("story") and story_state(str(need["story"])) != "done":
		var a := story_act(str(need["story"]))
		out.append(I18n.t("the story: %s (%s, in Eliet)") % [a.get("name", need["story"]), a.get("who", "someone")])
	if need.has("item") and count(str(need["item"])) <= 0:
		out.append("a %s" % item_name(str(need["item"])))
	if need.has("weapon_runes") and weapon_runes() < int(need["weapon_runes"]):
		out.append(I18n.t("%d runes in the weapon you carry (rune craft)") % int(need["weapon_runes"]))
	return out


func gate_check(level_id: String) -> String:
	## "" if the stairs down to this floor will take you, else what's missing (with the floor's words)
	var d := floor_depth(level_id)
	if d <= 0:
		return ""
	var miss := gate_missing(d)
	if miss.is_empty():
		return ""
	var g := gate_for(d)
	return I18n.t("%s\n\nYou lack: %s.\n(%s)") % [str(g.get("text", "")), ", ".join(miss), str(g.get("hint", ""))]


func gate_pass(level_id: String) -> void:
	## the stairs take you: the gate's item is used up, and it stays open
	var d := floor_depth(level_id)
	var g := gate_for(d)
	if g.is_empty() or gate_passed(d):
		return
	var need: Dictionary = g.get("need", {})
	if need.has("item"):
		remove_item(str(need["item"]), 1)
		message.emit(I18n.t("The %s is spent. The way to floor %d stays open.") % [item_name(str(need["item"])), d])
	set_flag("gate:%d:passed" % d)
	log_event("gate_passed", {"floor": d})
	bump("gates_passed")
	gain_insight(3.0, "a gate passed")
	jingle("discovery")
	if steam:
		steam.achieve("GATE_%d" % d)


func next_gate() -> Dictionary:
	## the first gate you haven't passed at or past where you've reached
	var best := {}
	for g in gates_data().get("gates", []):
		var d := int(g.get("floor", 0))
		if not gate_passed(d) and (best.is_empty() or d < int(best.get("floor", 999))):
			best = g
	return best


# ---- buffs ----------------------------------------------------------------------

func add_buff(id: String, effect: Dictionary, seconds: float) -> void:
	buffs[id] = {"until": _now() + seconds, "effect": effect.duplicate()}
	log_event("buff", {"id": id, "seconds": int(seconds)})
	stats_changed.emit()


func active_buffs() -> Dictionary:
	var now := _now()
	for k in buffs.keys():
		if float(buffs[k].get("until", 0.0)) <= now:
			buffs.erase(k)
	return buffs


func buff_left(id: String) -> float:
	return maxf(0.0, float(active_buffs().get(id, {}).get("until", 0.0)) - _now())


func buff_lines() -> Array:
	var out := []
	for k in active_buffs():
		out.append("%s (%s)" % [str(buff_names.get(str(k), item_name(str(k)))), _dur(buff_left(str(k)))])
	var psn = sys("poison")                                       # round 138
	if psn != null:
		if psn.poisoned():
			out.append(I18n.t("Poisoned (%ds)") % int(ceil(psn.p_left)))
		if psn.coat_hits > 0:
			out.append(psn.coat_text())
	return out


# ---- the main quest ---------------------------------------------------------------

func mq_data() -> Dictionary:
	if mq_def.is_empty():
		var d = _load_json("res://data/main_quest.json", {})
		mq_def = (d if d is Dictionary else {}).duplicate(true)
		if not mq_def.has("chapters"):
			mq_def["chapters"] = []
		var dr = _load_json("res://data/drafts/main_quest.json", {})
		if dr is Dictionary:
			for it in dr.get("items", []):
				if not (it is Dictionary):
					continue
				for c in mq_def["chapters"]:
					if str(c.get("id", "")) == str(it.get("chapter", it.get("id", ""))):
						for k in ["name", "brief"]:
							if str(it.get(k, "")).strip_edges() != "":
								c[k] = str(it[k])
	return mq_def


func mq_chapters() -> Array:
	return mq_data().get("chapters", [])


func mq_index() -> int:
	return clampi(int(mq.get("chapter", 0)), 0, mq_chapters().size())


func mq_chapter() -> Dictionary:
	var i := mq_index()
	return mq_chapters()[i] if i < mq_chapters().size() else {}


func mq_finished_all() -> bool:
	return mq_index() >= mq_chapters().size()


func mq_goal_done(g: Dictionary) -> bool:
	if g.has("talk"):
		return float(counters.get("talk:" + str(g["talk"]), 0.0)) > 0.0
	if g.has("floor"):
		return reach_depth() >= int(g["floor"])
	if g.has("boss"):
		return float(counters.get("boss_floor:%d" % int(g["boss"]), 0.0)) > 0.0
	if g.has("realm"):
		return realm >= int(g["realm"])
	if g.has("craft"):
		return float(counters.get("crafted:" + str(g["craft"]), 0.0)) > 0.0
	if g.has("item"):
		return count(str(g["item"])) >= int(g.get("count", 1))
	if g.has("skill"):
		return skill_level(str(g["skill"].get("id", ""))) >= int(g["skill"].get("level", 1))
	if g.has("weapon_skill"):
		return skill_level(weapon_skill()) >= int(g["weapon_skill"])
	if g.has("gate"):
		return gate_passed(int(g["gate"]))
	if g.has("story"):
		return story_state(str(g["story"])) == "done"
	if g.has("guild"):
		return not guilds.is_empty()
	if g.has("home"):
		return home_stage() >= int(g["home"])
	if g.has("blood"):
		return blood_awake()
	if g.has("finished"):
		return finished()
	if g.has("sect"):
		return not sect.is_empty()
	if g.has("learn"):
		return skill_known(str(g["learn"]))           # round 38
	if g.has("runes"):
		return runes_worn() >= int(g["runes"])
	if g.has("weapon_runes"):
		return weapon_runes() >= int(g["weapon_runes"])
	if g.has("rune_word"):
		return runewords_found() >= int(g["rune_word"])
	return false


func mq_goal_text(g: Dictionary) -> String:
	return str(g.get("text", "..."))


func mq_progress() -> Array:
	## the current chapter's goals: [text, done]
	var out := []
	for g in mq_chapter().get("goals", []):
		out.append([mq_goal_text(g), mq_goal_done(g)])
	return out


func mq_next_goal() -> String:
	for row in mq_progress():
		if not row[1]:
			return str(row[0])
	return ""


func mq_ready() -> bool:
	var c := mq_chapter()
	if c.is_empty():
		return false
	for g in c.get("goals", []):
		if not mq_goal_done(g):
			return false
	return true


func mq_reporter() -> String:
	return str(mq_chapter().get("who", ""))


func mq_complete() -> String:
	## the chapter's reward lands and the next opens; returns the lines of what you got
	var c := mq_chapter()
	if c.is_empty() or not mq_ready():
		return ""
	var rw: Dictionary = c.get("reward", {})
	var got := []
	if rw.has("gold"):
		add_item("gold", int(rw["gold"]), false)
		got.append(I18n.t("%d gold") % int(rw["gold"]))
	if rw.has("qi"):
		add_qi(float(rw["qi"]), "the road down")
		got.append("%d qi" % int(rw["qi"]))
	for id in rw.get("items", {}):
		add_item(str(id), int(rw["items"][id]), false)
		got.append("%s x%d" % [item_name(str(id)), int(rw["items"][id])])
	if rw.has("insight"):
		gain_insight(float(rw["insight"]), "the road down")
		got.append(I18n.t("+%d insight") % int(rw["insight"]))
	if rw.has("title") and not (str(rw["title"]) in titles):
		titles.append(str(rw["title"]))
		got.append(I18n.t("title: ") + str(rw["title"]))
	var done: Dictionary = mq.get("done", {})
	done[str(c.get("id", ""))] = true
	mq["done"] = done
	mq["chapter"] = mq_index() + 1
	log_event("chapter_done", {"chapter": c.get("id", "")})
	bump("chapters")
	jingle("achievement")
	if steam:
		steam.achieve("CHAPTER_" + str(c.get("id", "")).to_upper())
	var nxt := mq_chapter()
	var body := "%s\n\n(%s)" % [str(c.get("name", "")), ", ".join(got)]
	if not nxt.is_empty():
		body += I18n.t("\n\nNext: %s -- %s") % [nxt.get("name", ""), nxt.get("brief", "")]
	else:
		body += I18n.t("\n\nThe road down is walked. What's left is yours.")
	big_moment.emit("Chapter done: %s" % c.get("name", ""), body)
	stats_changed.emit()
	return ", ".join(got)


func mq_auto() -> void:
	## a chapter with nobody to report to completes itself
	if not mq_chapter().is_empty() and mq_reporter() == "" and mq_ready():
		mq_complete()


func mq_line() -> String:
	## the HUD's standing line: the chapter and its next goal
	var c := mq_chapter()
	if c.is_empty():
		return ""
	if mq_ready():
		return I18n.t("%s: report to %s") % [c.get("name", ""), mq_reporter()] if mq_reporter() != "" else ""
	return "%s: %s" % [c.get("name", ""), mq_next_goal()]


# ---- Elder Mo's errands ----------------------------------------------------------

func errand_defs() -> Dictionary:
	## one kill errand and one gather errand per floor you've reached, from
	## the floor's own foes and materials (quest ids errand:kill:N / errand:gather:N)
	var E: Dictionary = mq_data().get("errands", {})
	var out := {}
	var kc: Array = E.get("kill_count", [6, 0.5])
	var gc: Array = E.get("gather_count", [4, 0.3])
	for n in range(1, reach_depth() + 1):
		var def := load_level_def("floor%d" % n)
		if def.is_empty() or str(def.get("theme", "dungeon")) != "dungeon":
			continue
		var weak := ""
		var weak_hp := 1 << 30
		for ch in def.get("enemies", {}):
			var et := str(def["enemies"][ch])
			var st: Dictionary = enemies.get(et, {})
			if st.is_empty() or bool(st.get("boss", false)) or bool(st.get("passive", false)):
				continue
			if int(st.get("hp", 999)) < weak_hp:
				weak_hp = int(st.get("hp", 999))
				weak = et
		var fname := str(def.get("name", "floor %d" % n))
		if weak != "":
			var need := int(kc[0] + kc[1] * n)
			out["errand:kill:%d" % n] = {"name": "Thin %s" % fname.get_slice(", ", 1) if fname.contains(", ") else "Thin floor %d" % n, "order": 100 + n * 2, "errand": true, "floor": n,
				"desc": I18n.t("Elder Mo wants %d of floor %d's %s dead -- they've been coming up the shaft.") % [need, n, str(enemies[weak].get("name", weak)).to_lower()],
				"goal": {"kill": weak, "count": need, "since": true}, "reward": {"gold": int(E.get("gold_per_floor", 18)) * n, "qi": int(E.get("qi_per_floor", 25)) * n}}
		# the floor's first material: what its chests and nodes give
		var mat := ""
		for ch in def.get("chests", {}):
			for id in def["chests"][ch].get("loot", {}):
				if str(items.get(id, {}).get("type", "")) == "material" and mat == "":
					mat = str(id)
		if mat != "":
			var gneed := int(gc[0] + gc[1] * n)
			out["errand:gather:%d" % n] = {"name": "Bring up %s" % item_name(mat), "order": 101 + n * 2, "errand": true, "floor": n,
				"desc": I18n.t("The village can use %d %s from floor %d. Elder Mo pays.") % [gneed, item_name(mat), n],
				"goal": {"have": mat, "count": gneed, "take": true}, "reward": {"gold": int(E.get("gold_per_floor", 18)) * n + 10, "qi": int(E.get("qi_per_floor", 25)) * n / 2}}
	return out


func errand_ready(qid: String) -> bool:
	var q: Dictionary = errand_defs().get(qid, {})
	var goal: Dictionary = q.get("goal", {})
	if goal.has("kill"):
		# counted from when you took it
		var base := int(flags.get("errand_base:" + qid, 0))
		return int(kills.get(goal["kill"], 0)) - base >= int(goal.get("count", 1))
	if goal.has("have"):
		return count(goal["have"]) >= int(goal.get("count", 1))
	return false


func errand_accept(qid: String) -> void:
	var q: Dictionary = errand_defs().get(qid, {})
	if q.is_empty():
		return
	quests[qid] = "active"
	var goal: Dictionary = q.get("goal", {})
	if goal.has("kill"):
		flags["errand_base:" + qid] = int(kills.get(goal["kill"], 0))
	log_event("errand", {"id": qid})


func errand_turn_in(qid: String) -> String:
	var q: Dictionary = errand_defs().get(qid, {})
	if q.is_empty() or not errand_ready(qid):
		return ""
	var goal: Dictionary = q.get("goal", {})
	if goal.get("take", false) and goal.has("have"):
		remove_item(goal["have"], int(goal.get("count", 1)))
	quests[qid] = "done"
	var rw: Dictionary = q.get("reward", {})
	add_item("gold", int(rw.get("gold", 0)), false)
	add_qi(float(rw.get("qi", 0)), "an errand")
	log_event("errand_done", {"id": qid})
	bump("errands")
	guild_event("errand")
	return I18n.t("%s: +%d gold, +%d qi.") % [q.get("name", ""), int(rw.get("gold", 0)), int(rw.get("qi", 0))]


func errands_open() -> Array:
	## [qid, def, state] for Elder Mo: active ones, then up to three new ones from the deepest floors
	var defs := errand_defs()
	var ids: Array = defs.keys()
	ids.sort_custom(func(a, b): return int(defs[a]["floor"]) > int(defs[b]["floor"]))
	var out := []
	var fresh := 0
	for qid in ids:
		var st := str(quests.get(qid, ""))
		if st == "active":
			out.append([qid, defs[qid], st])
		elif st == "" and fresh < 3:
			out.append([qid, defs[qid], ""])
			fresh += 1
	return out


# ---- the curve ---------------------------------------------------------------------

func expected_player(n: int) -> Dictionary:
	## the cultivator a floor is tuned for (the floor forge's expected(): step 3n, realm step/10)
	var st := 3 * n
	var r := int(st / 10)
	return {"hp": (100.0 + 14.0 * st + 40.0 * r + 36.0 * n) * 1.15, "damage": (9.0 + 2.0 * st + 6.0 * r + 5.8 * n) * 1.3}


func adaptive_ramp(d: int) -> float:
	## round 136: 0..max -- how far ahead of floor d's expected cultivator you are. Foes grow by this much (up to 25%),
	## never shrink: a floor's base strength is the floor for everyone.
	var A: Dictionary = combat_data().get("adaptive", {})
	if not bool(A.get("enabled", true)) or d < 1:
		return 0.0
	var e := expected_player(d)
	var ratio := sqrt((float(max_hp()) / float(e["hp"])) * (float(damage()) / float(e["damage"])))
	var ahead := clampf((ratio - 1.0) / maxf(float(A.get("full_at", 0.6)), 0.05), 0.0, 1.0)
	return ahead * float(A.get("max", 0.25))


func curve_mult(d: int, key: String) -> float:
	## every floor a little harder than the last (on top of what the floor says)
	var C: Dictionary = combat_data().get("curve", {})
	var from := int(C.get("from_floor", 3))
	if d < from:
		return 1.0
	var steps := mini(d, int(C.get("cap_floor", 60))) - from + 1
	return 1.0 + float(C.get(key + "_per_floor", 0.0)) * steps


# ======================================================================
# round 34 -- hidden masters (Robert: "put hidden masters throughout the
# game"). Twelve of them, each standing somewhere disguised as somebody
# ordinary (data/hidden_masters.json). Talk to them enough -- and be
# strong enough -- and they show who they are, set a test, and, passed,
# teach a technique nobody else knows. State: hm[id] = {"stage":
# "revealed"|"done", "base": number the test counts from, "at": unix,
# "foe": the enemy a kill test counts}.
# ======================================================================

var hm_def := {}
var hm := {}


func hm_data() -> Dictionary:
	if hm_def.is_empty():
		var d = _load_json("res://data/hidden_masters.json", {})
		hm_def = (d if d is Dictionary else {}).duplicate(true)
		if not hm_def.has("masters"):
			hm_def["masters"] = []
		var dr = _load_json("res://data/drafts/hidden_masters.json", {})
		if dr is Dictionary:
			for it in dr.get("items", []):
				if not (it is Dictionary):
					continue
				for m in hm_def["masters"]:
					if str(m.get("id", "")) != str(it.get("id", "")):
						continue
					for k in ["name", "disguise", "reveal_text", "done_text", "after", "hint"]:
						if str(it.get(k, "")).strip_edges() != "":
							m[k] = str(it[k])
					if it.get("lines", null) is Array and (it["lines"] as Array).size() >= 2:
						m["lines"] = it["lines"]
		for m in hm_def["masters"]:
			var t: Dictionary = m.get("reward", {}).get("technique", {})
			if not t.is_empty() and not technique_defs.has(str(t.get("id", ""))):
				var td := t.duplicate(true)
				td["hint"] = str(m.get("hint", ""))
				td["unlock"] = {"master": str(m.get("id", ""))}
				td["master"] = true
				technique_defs[str(t["id"])] = td
	return hm_def


func hm_master(id: String) -> Dictionary:
	for m in hm_data().get("masters", []):
		if str(m.get("id", "")) == id:
			return m
	return {}


func hm_masters_at(level_id: String) -> Array:
	return hm_data().get("masters", []).filter(func(m): return str(m.get("place", "")) == level_id)


func hm_stage(id: String) -> String:
	return str(hm.get(id, {}).get("stage", ""))


func hm_place_depth(m: Dictionary) -> int:
	return floor_depth(str(m.get("place", "")))


func hm_extra_talks(m: Dictionary) -> int:
	## round 119: the deeper the master hides, the more conversations before they show themselves
	var df: Dictionary = hm_data().get("difficulty", {})
	var d := hm_place_depth(m)
	var free := int(df.get("free_depth", 6))
	if d <= free:
		return 0
	return int((d - free) / maxi(1, int(df.get("floors_per_extra_talk", 8))))


func hm_reveal_missing(id: String) -> Array:
	var m := hm_master(id)
	var r: Dictionary = m.get("reveal", {})
	var out := []
	if float(counters.get("hm_talk:" + id, 0.0)) < float(r.get("talks", 1)) + float(hm_extra_talks(m)):
		out.append("talks")
	if r.has("realm") and realm < int(r["realm"]):
		out.append("realm")
	if r.has("skill") and skill_level(str(r["skill"].get("id", ""))) < int(r["skill"].get("level", 1)):
		out.append("skill")
	if r.has("story") and story_state(str(r["story"])) != "done":
		out.append("story")
	return out


func hm_talk(id: String) -> String:
	## one conversation with the disguise; returns "reveal" when they show who they are
	var m := hm_master(id)
	if m.is_empty():
		return ""
	if hm_stage(id) != "":
		return hm_stage(id)
	counters["hm_talk:" + id] = float(counters.get("hm_talk:" + id, 0.0)) + 1.0
	if hm_reveal_missing(id).is_empty():
		hm_reveal(id)
		return "reveal"
	return ""


func hm_line(id: String) -> String:
	var m := hm_master(id)
	var lines: Array = m.get("lines", ["..."])
	var n := int(counters.get("hm_talk:" + id, 0.0))
	return str(lines[clampi(n - 1, 0, lines.size() - 1)])


func hm_reveal(id: String) -> void:
	var m := hm_master(id)
	var t: Dictionary = m.get("test", {})
	var st := {"stage": "revealed", "at": _now(), "base": 0.0}
	match str(t.get("kind", "")):
		"sit":
			st["base"] = float(counters.get("shrine_seconds", 0.0))
		"kill":
			var foe := str(t.get("enemy", ""))
			if foe == "__floor_weak":
				foe = _weakest_foe(str(m.get("place", "")))
			st["foe"] = foe
			st["base"] = float(kills.get(foe, 0))
		"craft_skill":
			st["base"] = float(counters.get("crafted_skill:" + str(t.get("skill", "")), 0.0))
		"craft":
			st["base"] = float(counters.get("crafted:" + str(t.get("item", "")), 0.0))
	hm[id] = st
	log_event("hm_reveal", {"id": id})
	bump("masters_found")
	jingle("discovery")
	if steam:
		steam.achieve("MASTER_FOUND")
	stats_changed.emit()


func _weakest_foe(level_id: String) -> String:
	var def := load_level_def(level_id)
	var best := ""
	var bh := 1 << 30
	for ch in def.get("enemies", {}):
		var et := str(def["enemies"][ch])
		var s: Dictionary = enemies.get(et, {})
		if s.is_empty() or bool(s.get("boss", false)) or bool(s.get("passive", false)):
			continue
		if int(s.get("hp", 999)) < bh:
			bh = int(s.get("hp", 999))
			best = et
	return best if best != "" else "goblin"


func hm_test_progress(id: String) -> Array:
	## [have, need] for the master's test (have >= need: passed)
	var m := hm_master(id)
	var t: Dictionary = m.get("test", {})
	var st: Dictionary = hm.get(id, {})
	var base := float(st.get("base", 0.0))
	match str(t.get("kind", "")):
		"sit":
			return [int(float(counters.get("shrine_seconds", 0.0)) - base), int(t.get("seconds", 600))]
		"bring":
			var have := 0
			var need := 0
			for it in t.get("items", {}):
				need += int(t["items"][it])
				have += mini(count(str(it)), int(t["items"][it]))
			return [have, need]
		"kill":
			return [int(kills.get(str(st.get("foe", "goblin")), 0)) - int(base), int(t.get("count", 10))]
		"craft_skill":
			return [int(float(counters.get("crafted_skill:" + str(t.get("skill", "")), 0.0)) - base), int(t.get("count", 1))]
		"craft":
			return [int(float(counters.get("crafted:" + str(t.get("item", "")), 0.0)) - base), int(t.get("count", 1))]
		"wait":
			var hrs := int((_now() - float(st.get("at", _now()))) / 3600.0)
			return [hrs, int(t.get("hours", 12))]
		"boss":
			return [1 if float(counters.get("boss_floor:%d" % hm_place_depth(m), 0.0)) > 0.0 else 0, 1]
		"boss_floor":
			return [1 if float(counters.get("boss_floor:%d" % int(t.get("floor", 1)), 0.0)) > 0.0 else 0, 1]
		"give_gold":
			return [mini(gold, int(t.get("gold", 100))), int(t.get("gold", 100))]
		"mastery":
			var ok := 0
			if skill_level(weapon_skill()) >= int(t.get("weapon", 10)):
				ok += 1
			var best := 0.0
			for b in bloodline.get("purity", {}):
				best = maxf(best, float(bloodline["purity"][b]))
			if best >= float(t.get("purity", 50)):
				ok += 1
			return [ok, 2]
	return [0, 1]


func hm_test_ready(id: String) -> bool:
	if hm_stage(id) != "revealed":
		return false
	var p := hm_test_progress(id)
	return int(p[0]) >= int(p[1])


func hm_complete(id: String) -> String:
	## the test is passed: what it costs is paid, the teaching lands
	if not hm_test_ready(id):
		return ""
	var m := hm_master(id)
	var t: Dictionary = m.get("test", {})
	match str(t.get("kind", "")):
		"bring":
			for it in t.get("items", {}):
				remove_item(str(it), int(t["items"][it]))
		"give_gold":
			gold -= int(t.get("gold", 0))
	var rw: Dictionary = m.get("reward", {})
	var got := []
	var tech: Dictionary = rw.get("technique", {})
	if not tech.is_empty():
		hm_data()
		learn(str(tech["id"]), "master")
		got.append(str(tech.get("name", "")))
	if rw.has("craft"):
		var cn := teach_craft(str(rw["craft"]))         # round 38: a craft taught
		if cn != "":
			got.append(I18n.t("the craft: ") + cn)
	if rw.has("title") and not (str(rw["title"]) in titles):
		titles.append(str(rw["title"]))
		got.append(I18n.t("title: ") + str(rw["title"]))
	if rw.has("insight"):
		gain_insight(float(rw["insight"]), "a hidden master")
		got.append(I18n.t("+%d insight") % int(rw["insight"]))
	for it in rw.get("items", {}):
		add_item(str(it), int(rw["items"][it]), false)
		got.append("%s x%d" % [item_name(str(it)), int(rw["items"][it])])
	hm[id]["stage"] = "done"
	log_event("hm_done", {"id": id})
	bump("masters_taught")
	jingle("achievement")
	if steam:
		steam.achieve("MASTER_" + id.to_upper())
		if hm_count_done() >= hm_data().get("masters", []).size():
			steam.achieve("ALL_MASTERS")
	big_moment.emit(str(m.get("name", "")), "%s\n\n(%s)" % [str(m.get("done_text", "")), ", ".join(got)])
	stats_changed.emit()
	return ", ".join(got)


func hm_count_done() -> int:
	var n := 0
	for k in hm:
		if str(hm[k].get("stage", "")) == "done":
			n += 1
	return n


func hm_count_found() -> int:
	return hm.size()


func hm_hint() -> String:
	## a rumour of the next master you haven't found, somewhere you can reach
	for m in hm_data().get("masters", []):
		var id := str(m.get("id", ""))
		if hm.has(id):
			continue
		if hm_place_depth(m) <= reach_depth() + 2:
			return str(m.get("hint", ""))
	return ""


func _place_label(level_id: String) -> String:
	if level_id == "village":
		return "Eliet"
	if level_id == "valley":
		return I18n.t("the valley road")
	if FrontierGen.is_frontier(level_id):
		return FrontierGen.name_of(level_id)
	if level_id.begins_with("floor"):
		return I18n.t("floor %d") % floor_depth(level_id)
	return level_id



# ======================================================================
# round 35 -- fog of war (scripts/FogOfWar.gd). What you've explored of each
# floor, kept as a bit per map cell (base64), saved with the game.
# ======================================================================

var fog_seen := {}              # level_id -> base64 bits (row-major over the level's grid)


func fog_load(level_id: String, grid: Array) -> Dictionary:
	var out := {}
	var b64 := str(fog_seen.get(level_id, ""))
	if b64 == "":
		return out
	var bytes := Marshalls.base64_to_raw(b64)
	var w := 0
	for row in grid:
		w = maxi(w, str(row).length())
	for y in grid.size():
		for x in str(grid[y]).length():
			var i := y * w + x
			if i / 8 < bytes.size() and (bytes[i / 8] >> (i % 8)) & 1:
				out[Vector2i(x, y)] = true
	return out


func fog_store(level_id: String, seen: Dictionary, grid: Array) -> void:
	if TrialGen.is_trial(level_id) or ScavengeGen.is_scavenge(level_id):
		return                                   # (a place drawn fresh each time keeps nothing)
	var w := 0
	for row in grid:
		w = maxi(w, str(row).length())
	var bytes := PackedByteArray()
	bytes.resize(int(ceil(w * grid.size() / 8.0)))
	for c in seen:
		var i: int = c.y * w + c.x
		if i >= 0 and i / 8 < bytes.size():
			bytes[i / 8] = bytes[i / 8] | (1 << (i % 8))
	fog_seen[level_id] = Marshalls.raw_to_base64(bytes)


func sight_bonus() -> int:
	## cells of sight beyond the base: a lantern lit, a familiar's nose, an art
	var b := int(round(tech_effect("sight", 0.0)))
	b += int(round(tech_effect("sense_radius", 0.0) / 3.0))
	return clampi(b, 0, 8)




# ======================================================================
# round 36 -- the character: earned attributes, titles that mean something,
# and the level-up window (Robert: "a level up screen where I can see my
# player stats ... the nanite and qi system complementary to player stats,
# abilities and titles ... everything is earned ... clear progression").
# data/character.json.
# ======================================================================

signal level_up(info: Dictionary)          # {"kind": "step"|"realm", "label", "before", "after", "points"}

var char_def := {}
var attrs := {}                            # attribute id -> points spent (saved)


func char_data() -> Dictionary:
	if char_def.is_empty():
		var d = _load_json("res://data/character.json", {})
		char_def = d if d is Dictionary else {}
	return char_def


func attr_ids() -> Array:
	return ["body", "might", "agility", "spirit"]


func attr_points_earned() -> int:
	## counted from what you've done, never stored: it can't drift
	var P: Dictionary = char_data().get("points", {})
	var steps := realm * SUBLEVELS + (sublevel - 1)
	var n := steps * int(P.get("per_step", 1)) + realm * int(P.get("per_realm", 3))
	n += int(born.get("free", 0))                    # what creation left you to spend
	n += mq_index() * int(P.get("per_chapter", 1))
	n += hm_count_done() * int(P.get("per_master", 1))
	return n


func attr_points_spent() -> int:
	var n := 0
	for k in attrs:
		n += int(attrs[k])
	return n


func attr_points_free() -> int:
	return maxi(0, attr_points_earned() - attr_points_spent())


func attr_spend(id: String, n: int = 1) -> bool:
	if not (id in attr_ids()) or n <= 0 or attr_points_free() < n:
		return false
	attrs[id] = int(attrs.get(id, 0)) + n
	log_event("attr_spend", {"attr": id, "n": n})
	stats_changed.emit()
	return true


func attr_respec_cost() -> int:
	return int(char_data().get("points", {}).get("respec_gold_per_realm", 150)) * (realm + 1)


func attr_respec() -> String:
	if attr_points_spent() <= 0:
		return I18n.t("There's nothing to take back.")
	var c := attr_respec_cost()
	if gold < c:
		return I18n.t("Unlearning costs %d gold (you have %d).") % [c, gold]
	gold -= c
	attrs = {}
	log_event("attr_respec", {"gold": c})
	stats_changed.emit()
	return ""


func attribute_effect() -> Dictionary:
	var A: Dictionary = char_data().get("attributes", {})
	var out := {}
	for id in attr_ids():
		var pts := attr_total(str(id))
		var e: Dictionary = A.get(str(id), {}).get("effect", {})
		for k in e:
			_fold_effect(out, str(k), float(e[k]) * pts)
	return out


func _fold_effect(out: Dictionary, k: String, v: float) -> void:
	## add v to an effect dict: multipliers (x_mult, attack_speed) start from 1
	var additive := k in ADDITIVE_KEYS or k.begins_with("craft_")
	if additive:
		out[k] = float(out.get(k, 0.0)) + v
	else:
		out[k] = float(out.get(k, 1.0)) + v


func title_gift(t: String) -> Dictionary:
	var C := char_data()
	var T: Dictionary = C.get("titles", {})
	if T.has(t):
		return T[t]
	var low := t.to_lower()
	for row in C.get("title_words", []):
		if low.contains(str(row[0])):
			return row[1]
	return C.get("title_default", {"hp_mult": 0.01})


func title_effect() -> Dictionary:
	var out := {}
	var raw := {}
	for t in titles:
		var g := title_gift(str(t))
		for k in g:
			raw[k] = float(raw.get(k, 0.0)) + float(g[k])
	var cap := float(char_data().get("title_cap", 0.15))
	for k in raw:
		_fold_effect(out, str(k), minf(float(raw[k]), cap if not (str(k) == "regen") else 3.0))
	return out


func title_gift_text(t: String) -> String:
	var parts := []
	var g := title_gift(t)
	for k in g:
		parts.append(gift_text(str(k), float(g[k])))
	return ", ".join(parts)


func gift_text(k: String, v: float) -> String:
	## "+3% health" for a gift's key and amount (amounts as added: 0.03 = 3%)
	var names := {"hp_mult": "health", "damage_mult": "damage", "attack_speed": "attack speed", "move_mult": "speed", "dodge_chance": "to slip a blow",
		"crit_chance": "to strike true", "qi_mult": "qi", "meditate_mult": "from sitting", "swarm_mult": "swarm growth", "loot_luck": "loot luck",
		"craft_success": "craft success", "damage_taken": "damage taken", "sight": "sight"}
	if k == "regen":
		return I18n.t("+%.1f health a second") % v
	if k == "sight":
		return I18n.t("+%d sight") % int(v)
	return "+%s%% %s" % [str(snappedf(v * 100.0, 0.1)).trim_suffix(".0"), names.get(k, k)]


# ---- what the character sheet and the level-up window show ----------------------

func stat_value(key: String) -> float:
	match key:
		"max_hp":
			return float(max_hp())
		"damage":
			return float(damage())
		"attack_speed":
			return attack_speed()
		"taken":
			return tech_effect("damage_taken", 1.0) * ward_factor()
		"crit":
			return tech_effect("crit_chance", 0.0)
		"dodge":
			return minf(tech_effect("dodge_chance", 0.0), 0.35)
		"move":
			return tech_effect("move_mult", 1.0)
		"regen":
			return tech_effect("regen", 0.0)
		"qi_gain":
			return tech_effect("qi_mult", 1.0) * growth_mult()
		"meditate":
			return tech_effect("meditate_mult", 1.0)
		"swarm":
			return tech_effect("swarm_mult", 1.0)
	return 0.0


func stat_text(key: String, v: float) -> String:
	match key:
		"max_hp", "damage":
			return str(int(round(v)))
		"taken":
			return "%d%%" % int(round(v * 100.0))
		"crit", "dodge":
			return "%s%%" % str(snappedf(v * 100.0, 0.1))
		"regen":
			return "%.1f" % v
	return "x%.2f" % v


func stat_snapshot() -> Dictionary:
	var out := {}
	for row in char_data().get("stats", []):
		out[str(row[1])] = stat_value(str(row[1]))
	return out


func stat_rows(before: Dictionary = {}) -> Array:
	## [label, now text, change text ("" if none)]
	var out := []
	for row in char_data().get("stats", []):
		var key := str(row[1])
		var v := stat_value(key)
		var ch := ""
		if before.has(key) and absf(float(before[key]) - v) > 0.0005:
			ch = "%s -> %s" % [stat_text(key, float(before[key])), stat_text(key, v)]
		out.append([str(row[0]), stat_text(key, v), ch])
	return out


func stat_sources(key: String) -> Array:
	## where a stat comes from: [source, text] -- cultivation, gear, swarm, blood, titles, attributes, arts
	var out := []
	match key:
		"max_hp":
			out.append(["Cultivation", I18n.t("%d base (%s)") % [100 + step_index() * 14 + realm * 40, cultivation_label()]])
			if worn_hp() > 0:
				out.append(["What you wear", "+%d" % worn_hp()])
		"damage":
			var bonus := int(item_def(weapon).get("damage", 0)) if weapon != "" and has_item_def(weapon) else 0
			out.append(["Cultivation", I18n.t("%d base") % (9 + step_index() * 2 + realm * 6)])
			if bonus > 0:
				out.append(["Weapon", I18n.t("+%d (%s, %d%% from how well you know it)") % [bonus, item_name(weapon), int(round(proficiency_mult(weapon) * 100.0))]])
	var mk: String = {"max_hp": "hp_mult", "damage": "damage_mult", "attack_speed": "attack_speed", "crit": "crit_chance", "dodge": "dodge_chance", "move": "move_mult",
		"regen": "regen", "qi_gain": "qi_mult", "meditate": "meditate_mult", "swarm": "swarm_mult", "taken": "damage_taken"}.get(key, "")
	if mk == "":
		return out
	var named := [["The swarm (%s)" % tier_name(), nanite_effect()], ["Attributes", attribute_effect()], ["Titles", title_effect()], ["Your blood", blood_effect()],
		["Elements", affinity_effect()], ["Meridians", lattice_effect()], ["Dao heart", dao_heart_effect()],
		["Your path", _paths_fx()]]
	var gsum := {}
	for e in gear_effects():
		for k in e:
			_fold_effect(gsum, str(k), (float(e[k]) - (0.0 if (str(k) in ADDITIVE_KEYS or str(k).begins_with("craft_")) else 1.0)))
	named.append(["What you wear", gsum])
	var tsum := {}
	for tid in techniques:
		var te: Dictionary = technique_defs.get(tid, {}).get("effect", {})
		if te.has(mk):
			_fold_effect(tsum, mk, float(te[mk]) - (0.0 if (mk in ADDITIVE_KEYS) else 1.0))
	named.append(["Techniques", tsum])
	var bsum := {}
	for k in active_buffs():
		var be: Dictionary = buffs[k].get("effect", {})
		if be.has(mk):
			_fold_effect(bsum, mk, float(be[mk]) - (0.0 if (mk in ADDITIVE_KEYS) else 1.0))
	named.append(["In effect now", bsum])
	for pair in named:
		var e: Dictionary = pair[1]
		if not e.has(mk):
			continue
		var v := float(e[mk])
		var add := v if (mk in ADDITIVE_KEYS) else v - 1.0
		if mk == "damage_taken":
			add = 1.0 - v
			if absf(add) > 0.0005:
				out.append([pair[0], I18n.t("-%s%% damage taken") % str(snappedf(add * 100.0, 0.1))])
			continue
		if absf(add) > 0.0005:
			out.append([pair[0], gift_text(mk, add)])
	if key == "taken" and ward_factor() < 0.999:
		out.append(["Ward (what you wear)", I18n.t("blows %d%% weaker") % int(round((1.0 - ward_factor()) * 100.0))])
	return out


func level_up_note(before: Dictionary, kind: String) -> void:
	var info := {"kind": kind, "label": cultivation_label(), "before": before, "rows": stat_rows(before), "points": attr_points_free(),
		"gained": int(char_data().get("points", {}).get("per_realm" if kind == "realm" else "per_step", 1)) + (int(char_data().get("points", {}).get("per_step", 1)) if kind == "realm" else 0)}
	counters["levelups"] = float(counters.get("levelups", 0.0)) + 1.0
	level_up.emit(info)



# ---- round 36: who you are (character creation) ------------------------------------
# A name, a look, a past (BACKGROUNDS), then seven questions (data/creation.json):
# every answer is worth one point -- an attribute you start with, or a free
# point to spend -- and sometimes a small gift. "born" keeps what you were
# born with: {"attrs": {id: n}, "free": n, "answers": {qid: index}}.

var char_name := ""
var look := {}
var born := {}
var creation_def := {}


func creation_data() -> Dictionary:
	if creation_def.is_empty():
		var d = _load_json("res://data/creation.json", {})
		creation_def = (d if d is Dictionary else {}).duplicate(true)
		var dr = _load_json("res://data/drafts/creation.json", {})
		if dr is Dictionary:
			for it in dr.get("items", []):
				if not (it is Dictionary):
					continue
				for q in creation_def.get("questions", []):
					if str(q.get("id", "")) != str(it.get("id", "")):
						continue
					if str(it.get("ask", "")).strip_edges() != "":
						q["ask"] = str(it["ask"])
					var ans: Array = it.get("answers", [])
					for i in mini(ans.size(), (q.get("answers", []) as Array).size()):
						if str(ans[i]).strip_edges() != "":
							q["answers"][i]["text"] = str(ans[i])
	return creation_def


func needs_creation() -> bool:
	return background == "" or not has_flag("creation_done")


func attr_born(id: String) -> int:
	return int((born.get("attrs", {}) as Dictionary).get(id, 0))


func attr_total(id: String) -> int:
	return attr_born(id) + int(attrs.get(id, 0))


func answer_hint(r: Dictionary) -> String:
	## round 62: what an answer gives, said plainly beside it ("+1 Spirit, 2 insight")
	var bits := []
	for k in r.get("attrs", {}):
		bits.append("+%d %s" % [int(r["attrs"][k]), str(k).capitalize()])
	if int(r.get("free", 0)) > 0:
		bits.append(I18n.t("+%d free point") % int(r["free"]))
	if int(r.get("lean", 0)) > 0:
		bits.append(I18n.t("+%d to your strongest") % int(r["lean"]))
	var g: Dictionary = r.get("gift", {})
	if g.has("gold"):
		bits.append(I18n.t("%d gold") % int(g["gold"]))
	if g.has("insight"):
		bits.append(I18n.t("%d insight") % int(g["insight"]))
	for id in g.get("items", {}):
		bits.append("%s x%d" % [item_name(str(id)), int(g["items"][id])])
	for sk in g.get("skill_xp", {}):
		bits.append(I18n.t("%s practice") % skill_name(str(sk)))
	if g.has("warmth"):
		bits.append(I18n.t("Eliet likes you"))
	if not (g.get("rep", {}) as Dictionary).is_empty():
		bits.append(I18n.t("a name in the deep"))
	return ", ".join(bits)


func creation_tally(answers: Dictionary) -> Dictionary:
	## what a set of answers adds up to: {"attrs", "free", "gifts": [...], "lean"}
	var a := {"body": 0, "might": 0, "agility": 0, "spirit": 0}
	var free := 0
	var lean := 0
	var gifts := []
	for q in creation_data().get("questions", []):
		var qid := str(q.get("id", ""))
		if not answers.has(qid):
			continue
		var i := int(answers[qid])
		var ans: Array = q.get("answers", [])
		if i < 0 or i >= ans.size():
			continue
		var r: Dictionary = ans[i]
		for k in r.get("attrs", {}):
			a[str(k)] = int(a.get(str(k), 0)) + int(r["attrs"][k])
		free += int(r.get("free", 0))
		lean += int(r.get("lean", 0))
		if r.has("gift"):
			gifts.append(r["gift"])
	if lean > 0:
		# what you lean toward most (ties: the order body, might, agility, spirit)
		var best := "body"
		for k in ["body", "might", "agility", "spirit"]:
			if int(a[k]) > int(a[best]):
				best = k
		a[best] = int(a[best]) + lean
	return {"attrs": a, "free": free, "gifts": gifts}


func creation_finish(name_: String, look_: Dictionary, answers: Dictionary) -> String:
	## seal who you are: the start you were born with, the free points, the gifts
	if has_flag("creation_done"):
		return "already"
	var t := creation_tally(answers)
	char_name = name_.strip_edges().left(24) if name_.strip_edges() != "" else _default_name(str(look_.get("sex", "m")))
	look = look_.duplicate(true)
	born = {"attrs": t["attrs"], "free": int(t["free"]), "answers": answers.duplicate()}
	for g in t["gifts"]:
		if g.has("gold"):
			add_item("gold", int(g["gold"]), false)
		for id in g.get("items", {}):
			add_item(str(id), int(g["items"][id]), false)
		if g.has("insight"):
			gain_insight(float(g["insight"]), "who you are")
		for sk in g.get("skill_xp", {}):
			add_skill_xp(str(sk), float(g["skill_xp"][sk]), "who you are")
		if g.has("warmth"):
			for who in ["Elder Mo", "Trader Wen", "Smith Hale", "Apothecary Lin", "Captain Rhee"]:
				warm_bond(who, float(g["warmth"]))
		for gid in g.get("rep", {}):
			flags["story:rep_owed:" + str(gid)] = float(flags.get("story:rep_owed:" + str(gid), 0.0)) + float(g["rep"][gid])
	for q in creation_data().get("questions", []):                       # round 142b: how you want your first days to go
		var qa: Array = q.get("answers", [])
		var qi := int(answers.get(str(q.get("id", "")), -1))
		if qi >= 0 and qi < qa.size() and str((qa[qi] as Dictionary).get("pace", "")) != "":
			set_flag("pace:" + str(qa[qi]["pace"]))
	set_flag("creation_done")
	hp = max_hp()
	log_event("creation", {"name": char_name, "attrs": t["attrs"], "free": int(t["free"])})
	note_place("%s, setting out" % char_name)
	stats_changed.emit()
	save_game()
	return ""


func _default_name(sex: String) -> String:
	var N: Array = creation_data().get("names", {}).get(sex, ["Wei"])
	return str(N[hash(str(Time.get_unix_time_from_system())) % N.size()])



var _hitstop_until := 0


func hit_stop(secs: float) -> void:
	## round 37: the world holds its breath for a moment on a heavy blow
	var m: float = preload("res://scripts/core/Access.gd").motion()      # round 146: none is steady, reduced is half
	if m <= 0.0:
		return
	Engine.time_scale = 0.08
	_hitstop_until = Time.get_ticks_msec() + int(secs * m * 1000.0)


func slow_mo(scale: float, secs: float) -> void:
	## round 60: a perfect dodge -- the world slows for a breath (real seconds)
	if preload("res://scripts/core/Access.gd").motion() <= 0.0:
		return
	Engine.time_scale = clampf(scale, 0.05, 1.0)
	_hitstop_until = Time.get_ticks_msec() + int(secs * 1000.0)



# ======================================================================
# round 37 -- balance and mastery (Robert: "take days to complete and even
# when you do there is always more to do ... impossible to pull a quick
# perfect game but you can do well with balance; balance may provide the
# strongest growth possibilities"). data/character.json "balance", "mastery".
# ======================================================================

var fog_frac := {}               # level id -> how much of it you've explored (FogOfWar)


func _evenness(vals: Array) -> float:
	## 1 when every value is the same, toward 0 as one dwarfs the rest
	if vals.is_empty():
		return 0.0
	var mx := 0.0
	var mn := 1e9
	for v in vals:
		mx = maxf(mx, float(v))
		mn = minf(mn, float(v))
	if mx <= 0.0:
		return 0.0
	return clampf(mn / mx, 0.0, 1.0)


func _best_level(ids: Array) -> int:
	var b := 0
	for sk in ids:
		b = maxi(b, skill_level(str(sk)))
	return b


func balance_parts() -> Array:
	## [name, 0..1, how it's read]
	var B: Dictionary = char_data().get("balance", {})
	var av := []
	var tot := 0
	for id in attr_ids():
		av.append(attr_total(id))
		tot += attr_total(id)
	var attr_e := _evenness(av) if tot >= int(B.get("min_total", 4)) else 0.0
	var paths := [_best_level(B.get("combat_skills", [])), _best_level(B.get("craft_skills", [])), _best_level(B.get("gather_skills", []))]
	var path_e := _evenness(paths)
	var roads_e := 0.0
	if realm >= 1 or nanite_tier() >= 1:
		roads_e = clampf(1.0 - absf(float(nanite_tier() - realm)) / 3.0, 0.0, 1.0)
	var el := []
	for e in ELEMENTS:
		el.append(float(affinity.get(e, 0.0)))
	var el_e := _evenness(el) if (el.reduce(func(a, b): return a + b, 0.0) as float) >= 10.0 else 0.0
	return [["Attributes", attr_e, "Body %d / Might %d / Agility %d / Spirit %d" % av],
		["Paths", path_e, "fighting %d, making %d, finding %d" % paths],
		["The two roads", roads_e, I18n.t("%s, swarm tier %d") % [realm_name(), nanite_tier()]],
		["Elements", el_e, " / ".join(el.map(func(v): return str(int(v))))]]


func balance() -> float:
	var t := 0.0
	var parts := balance_parts()
	for p in parts:
		t += float(p[1])
	return t / maxf(1.0, float(parts.size()))


func balance_mult() -> float:
	var B: Dictionary = char_data().get("balance", {})
	return 1.0 + float(B.get("max_bonus", 0.6)) * pow(balance(), float(B.get("curve", 1.6)))


func mastery_parts() -> Array:
	## [category, have, total] -- everything the game holds
	var M: Dictionary = char_data().get("mastery", {})
	var out := []
	var floors := 0
	for k in fog_frac:
		if str(k).begins_with("floor") and float(fog_frac[k]) >= float(M.get("explored_frac", 0.9)):
			floors += 1
	out.append(["floors", I18n.t("Floors explored"), floors, 50])
	out.append(["chapters", I18n.t("The road down"), mq_index(), mq_chapters().size()])
	var acts := 0
	for a in story_acts():
		if story_state(str(a.get("id", ""))) == "done":
			acts += 1
	out.append(["story", I18n.t("The story"), acts, story_acts().size()])
	var ends := 0
	for e in ["story:ending_sealed", "story:ending_delver"]:
		if has_flag(e) or bool((ascension.get("ever", {}) as Dictionary).get(e, false)):
			ends += 1
	out.append(["endings", I18n.t("Endings seen"), ends, 2])
	out.append(["masters", I18n.t("Hidden masters"), hm_count_done(), hm_data().get("masters", []).size()])
	var gates := 0
	for g in gates_data().get("gates", []):
		if gate_passed(int(g.get("floor", 0))):
			gates += 1
	out.append(["gates", I18n.t("Gates passed"), gates, gates_data().get("gates", []).size()])
	var known_titles := (char_data().get("titles", {}) as Dictionary).size()
	out.append(["titles", I18n.t("Titles"), mini(titles.size(), known_titles), known_titles])
	out.append(["achievements", I18n.t("Achievements"), achievements.size(), maxi(1, achievement_defs.size())])
	var ch := 0
	var ct := 0
	for c in collections():
		ch += int(c.get("have", 0))
		ct += int(c.get("total", 0))
	out.append(["collections", I18n.t("Collections"), ch, maxi(1, ct)])
	var foes := 0
	var foe_total := 0
	for e in enemies:
		if bool(enemies[e].get("passive", false)) or str(e) == "heart_demon":
			continue
		foe_total += 1
		if int(kills.get(e, 0)) > 0:
			foes += 1
	out.append(["bestiary", I18n.t("Bestiary"), foes, maxi(1, foe_total)])
	var pure := 0
	var lines: Dictionary = blood_data().get("lines", {})
	for id in lines:
		if float((bloodline.get("purity", {}) as Dictionary).get(id, 0.0)) >= 100.0 or bool((ascension.get("ever", {}) as Dictionary).get("pure:" + str(id), false)):
			pure += 1
	out.append(["bloodlines", I18n.t("Bloodlines made pure"), pure, maxi(1, lines.size())])
	out.append(["realms", I18n.t("Realms"), realm, int(M.get("realm_cap", 13))])
	var sk_tot := 0
	var cap := int(M.get("skill_cap", 30))
	for sid in skill_defs:
		sk_tot += mini(skill_level(str(sid)), cap)
	out.append(["skills", I18n.t("Skills mastered"), sk_tot, cap * maxi(1, skill_defs.size())])
	out.append(["runewords", I18n.t("Rune words spoken"), runewords_found(), maxi(1, runes_data().get("words", []).size())])     # round 38
	if sys("cleansing"):                                # round 40
		out.append(["cleansing", I18n.t("Meridians cleansed"), sys("cleansing").total_grades(), sys("cleansing").max_grades()])
	if sys("research"):
		out.append(["research", I18n.t("Swarm research"), sys("research").researched.size(), maxi(1, (sys("research").data.get("nodes", {}) as Dictionary).size())])
	if sys("lore"):                                     # round 42
		out.append(["history", I18n.t("The history of Eliet"), sys("lore").history_found.size(), maxi(1, (sys("lore").data.get("history", []) as Array).size())])
	out.append(["ascension", I18n.t("Ascensions"), mini(int(ascension.get("count", 0)), int(M.get("ascension_cap", 5))), int(M.get("ascension_cap", 5))])
	return out


func mastery() -> float:
	var W: Dictionary = char_data().get("mastery", {}).get("weights", {})
	var t := 0.0
	var w := 0.0
	for p in mastery_parts():
		var wk := float(W.get(str(p[0]), 1.0))
		t += wk * clampf(float(p[2]) / maxf(1.0, float(p[3])), 0.0, 1.0)
		w += wk
	return t / maxf(1.0, w)


# ======================================================================
# round 38 -- rune craft and talismans (Robert: "build rune craft and
# talisman into mid-tier game"). data/runes.json; Dev's words: brief "runes".
# ======================================================================

var rune_def := {}
var inscriptions := {}           # gear id -> [rune ids, in the order they were set]
var talisman_ready := ""         # the talisman key 4 burns (a base id)


func runes_data() -> Dictionary:
	if rune_def.is_empty():
		var d = _load_json("res://data/runes.json", {})
		rune_def = (d if d is Dictionary else {}).duplicate(true)
	return rune_def


func _merge_runes() -> void:
	## the two crafts, their items and their recipes join the game's own
	var R := runes_data()
	var words := {}
	for f in ["res://data/drafts/runes.json", "res://data/drafts/rune_words.json"]:        # Dev's words
		var dr = _load_json(f, {})
		if dr is Dictionary:
			for it in dr.get("items", []):
				if it is Dictionary and str(it.get("id", "")) != "":
					words[str(it["id"])] = it
	for sid in R.get("skills", {}):
		if not skill_defs.has(sid):
			skill_defs[sid] = R["skills"][sid].duplicate(true)
	var b: Dictionary = R.get("blank", {})
	if not b.is_empty():
		_rune_item(str(b["id"]), {"name": b.get("name", ""), "type": "material", "value": int(b.get("value", 10)), "desc": b.get("desc", "")}, words)
		_rune_recipe(str(b["id"]), b, "runecraft")
	for rid in R.get("runes", {}):
		var r: Dictionary = R["runes"][rid]
		_rune_item(rid, {"name": r.get("name", rid), "type": "rune", "value": int(r.get("value", 50)), "desc": r.get("desc", ""), "mark": r.get("mark", "")}, words)
		_rune_recipe(rid, r, "runecraft")
	for mid in R.get("talisman_mats", {}):
		var m: Dictionary = R["talisman_mats"][mid]
		_rune_item(mid, {"name": m.get("name", mid), "type": "material", "value": int(m.get("value", 10)), "desc": m.get("desc", "")}, words)
		_rune_recipe(mid, m, "talismans")
	for tid in R.get("talismans", {}):
		var t: Dictionary = R["talismans"][tid]
		_rune_item(tid, {"name": t.get("name", tid), "type": "talisman", "value": int(t.get("value", 40)), "desc": t.get("desc", ""), "gate": int(t.get("gate", 0))}, words)
		_rune_recipe(tid, t, "talismans")
	for w in R.get("words", []):
		var dw: Dictionary = words.get(str(w.get("id", "")), {})
		for k in ["name", "hint"]:
			if str(dw.get(k, "")).strip_edges() != "":
				w[k] = str(dw[k])


func _rune_item(id: String, def: Dictionary, words: Dictionary) -> void:
	var dw: Dictionary = words.get(id, {})
	for k in ["name", "desc"]:
		if str(dw.get(k, "")).strip_edges() != "":
			def[k] = str(dw[k])
	if not items.has(id):
		items[id] = def
	else:
		for k in def:                       # (the forge never writes these; ours is the truth)
			items[id][k] = def[k]


func _rune_recipe(id: String, d: Dictionary, skill: String) -> void:
	if not _recipe_for(id).is_empty():
		return
	recipes.append({"makes": id, "needs": (d.get("needs", {}) as Dictionary).duplicate(), "gold": int(d.get("gold", 0)),
		"skill": skill, "difficulty": int(d.get("difficulty", 0)), "round38": true})


# ---- knowing a craft ------------------------------------------------------------------

func skill_known(sid: String) -> bool:
	## most skills anyone can pick up; rune craft and talismans must be taught
	if not bool(skill_defs.get(sid, {}).get("teach", false)):
		return true
	return skills.has(sid)


func teach_craft(sid: String) -> String:
	if skill_known(sid):
		return ""
	skills[sid] = float(runes_data().get("taught_xp", 90))
	set_flag("craft:" + sid)
	log_event("craft_taught", {"skill": sid})
	message.emit(I18n.t("You know %s now. (%s)") % [skill_name(sid), str(skill_defs.get(sid, {}).get("desc", ""))])
	stats_changed.emit()
	return skill_name(sid)


func craft_teacher_hint(sid: String) -> String:
	var m := hm_master(str(skill_defs.get(sid, {}).get("teacher", "")))
	return str(m.get("hint", "Someone in the deep knows it."))


# ---- runes ----------------------------------------------------------------------------

func is_rune(id: String) -> bool:
	return str(item_def(id).get("type", "")) == "rune"


func rune_info(id: String) -> Dictionary:
	return runes_data().get("runes", {}).get(base_id(id), {})


func rune_mark(id: String) -> String:
	return str(rune_info(id).get("mark", item_name(id)))


func rune_part(id: String) -> String:
	## "weapon" or "wear": which half of a rune's gift a piece takes
	return "weapon" if gear_family(id) == "weapon" else "wear"


func rune_sockets(id: String) -> int:
	if id == "" or gear_family(id) == "" or not skill_known("runecraft"):
		return 0
	var lvl := skill_level("runecraft")
	var n := 0
	for row in runes_data().get("sockets", {}).get(rune_part(id), [[0, 1]]):
		if lvl >= int(row[0]):
			n = int(row[1])
	return n


func runes_on(id: String) -> Array:
	return inscriptions.get(id, []) if inscriptions.get(id, []) is Array else []


func inscribe_chance(gear: String, rune: String) -> float:
	var I: Dictionary = runes_data().get("inscribe", {})
	var c := float(I.get("base", 0.62)) + float(skill_level("runecraft") - int(rune_info(rune).get("difficulty", 0))) * float(I.get("per_level", 0.06))
	c -= 0.05 * runes_on(gear).size()          # a crowded piece is harder to cut true
	c += tech_effect("craft_success", 0.0) + tech_effect("craft_success_runecraft", 0.0)
	return clampf(c, float(I.get("min", 0.15)), float(I.get("max", 0.97)))


func inscribe(gear: String, rune: String, roll: float = -1.0) -> Dictionary:
	## {ok, success, text, word}. A slip cracks the rune; the piece is never harmed.
	if not skill_known("runecraft"):
		return {"ok": false, "text": I18n.t("You don't know how to set a rune. ") + craft_teacher_hint("runecraft")}
	if count(gear) <= 0 or gear_family(gear) == "":
		return {"ok": false, "text": "That isn't something you can inscribe."}
	if count(rune) <= 0 or not is_rune(rune):
		return {"ok": false, "text": "You have no %s." % item_name(rune)}
	var have := runes_on(gear)
	if have.size() >= rune_sockets(gear):
		return {"ok": false, "text": I18n.t("%s holds no more runes (%d). Scour it, or grow your craft.") % [item_name(gear), rune_sockets(gear)]}
	var chance := inscribe_chance(gear, rune)
	var r := randf() if roll < 0.0 else roll
	var diff := int(rune_info(rune).get("difficulty", 0))
	remove_item(rune, 1)
	if r >= chance:
		add_skill_xp("runecraft", (8.0 + diff * 3.0) * 0.4, "a cracked rune")
		log_event("inscribe", {"gear": gear, "rune": rune, "success": false})
		sfx("thud", 0.6)
		var t := I18n.t("The %s cracks under the chisel. %s is unmarked -- and you know a little more about why.") % [item_name(rune), item_name(gear)]
		message.emit(t)
		stats_changed.emit()
		return {"ok": true, "success": false, "text": t}
	have = have.duplicate()
	have.append(rune)
	inscriptions[gear] = have
	add_skill_xp("runecraft", 8.0 + diff * 3.0, "inscribing")
	bump("runes_set")
	sfx("stamp", 0.8)
	log_event("inscribe", {"gear": gear, "rune": rune, "success": true})
	var t2 := I18n.t("%s takes the %s.") % [item_name(gear), rune_mark(rune)]
	var w := rune_word_on(gear)
	if not w.is_empty():
		var wid := str(w.get("id", ""))
		if not has_flag("runeword:" + wid):
			set_flag("runeword:" + wid)
			gain_insight(4.0, "a rune word")
			jingle("discovery")
			big_moment.emit(I18n.t("A rune word: %s") % str(w.get("name", "")), I18n.t("The marks on %s run together and speak: %s.\n\n(%s)") % [item_name(gear), str(w.get("name", "")), effect_text(w.get("effect", {}))])
		t2 += I18n.t(" The runes speak: %s.") % str(w.get("name", ""))
	message.emit(t2)
	stats_changed.emit()
	return {"ok": true, "success": true, "text": t2, "word": str(w.get("id", ""))}


func scour_cost(gear: String) -> int:
	return int(runes_data().get("inscribe", {}).get("scour_gold", 25)) * runes_on(gear).size()


func scour(gear: String) -> String:
	## take the runes off: they're ground away, the piece is clean
	var n := runes_on(gear).size()
	if n == 0:
		return I18n.t("There's nothing carved on it.")
	var c := scour_cost(gear)
	if gold < c:
		return I18n.t("Scouring costs %d gold.") % c
	gold -= c
	inscriptions.erase(gear)
	log_event("scour", {"gear": gear, "n": n})
	stats_changed.emit()
	return I18n.t("%s is scoured clean (%d rune%s ground away).") % [item_name(gear), n, "" if n == 1 else "s"]


func rune_word_on(gear: String) -> Dictionary:
	var have: Array = runes_on(gear).map(func(r): return base_id(str(r)))
	var part := rune_part(gear)
	for w in runes_data().get("words", []):
		var on := str(w.get("on", "any"))
		if on != "any" and on != part:
			continue
		if have == (w.get("runes", []) as Array):
			return w
	return {}


func rune_word_known(wid: String) -> bool:
	return has_flag("runeword:" + wid)


func runewords_found() -> int:
	var n := 0
	for w in runes_data().get("words", []):
		if rune_word_known(str(w.get("id", ""))):
			n += 1
	return n


func _rune_q(r: String) -> float:
	var q := float(QUALITY[clampi(quality_index(r), 0, QUALITY.size() - 1)]["mult"])
	return 1.0 + (q - 1.0) * float(runes_data().get("quality_weight", 0.5))


func rune_effects() -> Array:
	## what the runes on everything you wear give: the weapon's in full, the
	## rest pooled (a second rune of the same gift counts for less), and
	## the words they speak
	var out := []
	var pool := {}
	var seen := {}
	var P: Dictionary = runes_data().get("wear_pool", {})
	for s in gear_slots():
		var id := worn(str(s[0]))
		if id == "" or seen.has(id) or count(id) <= 0 or runes_on(id).is_empty():
			continue
		seen[id] = true
		var part := rune_part(id)
		for r in runes_on(id):
			var e: Dictionary = rune_info(str(r)).get(part, {})
			if part == "weapon":
				out.append(merge_effects({}, e, _rune_q(str(r))))
			else:
				for k in e:
					var add := float(e[k]) if (k in ADDITIVE_KEYS or str(k).begins_with("craft_")) else float(e[k]) - 1.0
					pool[k] = float(pool.get(k, 0.0)) + add * _rune_q(str(r))
		var w := rune_word_on(id)
		if not w.is_empty():
			out.append(w.get("effect", {}))
	var pd := {}
	for k in pool:
		var v := float(pool[k])
		if k in ADDITIVE_KEYS or str(k).begins_with("craft_"):
			pd[k] = v
			continue
		var a := absf(v)
		var soft := float(P.get("soft", 0.08))
		if a > soft:
			a = soft + (a - soft) * float(P.get("after", 0.4))
		a = minf(a, float(P.get("cap", 0.25)))
		pd[k] = 1.0 + signf(v) * a
	if not pd.is_empty():
		out.append(pd)
	return out


func inscription_text(gear: String) -> String:
	var have := runes_on(gear)
	if have.is_empty():
		return ""
	var t := "Runes: %s" % " · ".join(have.map(func(r): return rune_mark(str(r))))
	var w := rune_word_on(gear)
	if not w.is_empty():
		t += "  -- \"%s\"" % str(w.get("name", ""))
	return t


func weapon_runes() -> int:
	return runes_on(weapon).size() if weapon != "" else 0


func runes_worn() -> int:
	var n := 0
	var seen := {}
	for s in gear_slots():
		var id := worn(str(s[0]))
		if id != "" and not seen.has(id):
			seen[id] = true
			n += runes_on(id).size()
	return n


# ---- talismans --------------------------------------------------------------------------

func is_talisman(id: String) -> bool:
	return str(item_def(id).get("type", "")) == "talisman"


func talisman_use(id: String) -> Dictionary:
	return runes_data().get("talismans", {}).get(base_id(id), {}).get("use", {})


func talismans_carried() -> Array:
	## base ids of the talismans in your pouch that can be burned, in data order
	var out := []
	for tid in runes_data().get("talismans", {}):
		if str(talisman_use(tid).get("kind", "")) == "seal":
			continue
		for id in inventory:
			if base_id(id) == tid and count(id) > 0:
				out.append(tid)
				break
	return out


func talisman_cycle() -> String:
	var c := talismans_carried()
	if c.is_empty():
		talisman_ready = ""
		return I18n.t("You carry no talismans.") + ("" if skill_known("talismans") else " (" + craft_teacher_hint("talismans") + ")")
	var i := c.find(talisman_ready)
	talisman_ready = str(c[(i + 1) % c.size()])
	return I18n.t("Talisman ready [4]: %s (%d).") % [item_name(talisman_ready), _talisman_count(talisman_ready)]


func _talisman_count(base: String) -> int:
	var n := 0
	for id in inventory:
		if base_id(id) == base:
			n += count(id)
	return n


func talisman_potency(id: String) -> float:
	## its quality, and the hand that drew it
	var q := float(QUALITY[clampi(quality_index(id), 0, QUALITY.size() - 1)]["mult"])
	return q * (1.0 + 0.02 * skill_level("talismans"))


func talisman_take(base: String = "") -> Dictionary:
	## burn the best one of this kind you carry: {id, use, potency} ({} = none)
	var asked := base != ""
	if base == "":
		base = talisman_ready
	if asked and _talisman_count(base) <= 0:
		return {}                            # (you asked for that one, and have none)
	if base == "" or _talisman_count(base) <= 0:
		var c := talismans_carried()
		if c.is_empty():
			return {}
		base = str(c[0])
		talisman_ready = base
	var best := ""
	var bq := -1
	for id in inventory:
		if base_id(id) == base and count(id) > 0 and quality_index(id) > bq:
			best = id
			bq = quality_index(id)
	if best == "":
		return {}
	var use := talisman_use(best)
	if str(use.get("kind", "")) == "seal":
		return {}
	var pot := talisman_potency(best)
	remove_item(best, 1)
	match str(use.get("kind", "")):
		"buff":
			var eff := merge_effects({}, use.get("effect", {}), pot)
			add_buff(base, eff, float(use.get("seconds", 20)))
		"heal":
			heal(int(round(float(max_hp()) * float(use.get("frac", 0.3)) * pot)))
		"sight":
			add_buff(base, use.get("effect", {}), float(use.get("seconds", 300)) * pot)
	add_skill_xp("talismans", 2.0, "a talisman burned")
	bump("talismans_burned")
	log_event("talisman", {"id": best})
	if _talisman_count(base) <= 0:
		var c2 := talismans_carried()
		talisman_ready = str(c2[0]) if c2.size() > 0 else ""
	stats_changed.emit()
	return {"id": best, "base": base, "use": use, "potency": pot}


func talisman_line() -> String:
	if talisman_ready == "" or _talisman_count(talisman_ready) <= 0:
		var c := talismans_carried()
		if c.is_empty():
			return ""
		talisman_ready = str(c[0])
	return "[4] %s ×%d" % [item_name(talisman_ready), _talisman_count(talisman_ready)]


func r38_save() -> Dictionary:
	return {"inscriptions": inscriptions, "talisman_ready": talisman_ready}


func r38_load(d: Dictionary) -> void:
	inscriptions = d.get("inscriptions", {}) if d.get("inscriptions", {}) is Dictionary else {}
	talisman_ready = str(d.get("talisman_ready", ""))


# ======================================================================
# round 39 -- the party: two companions, a roster to call back, contract
# beasts (Robert: "can we have companion, contract beast, bonds, etc." --
# "party of two" -- beasts: "all of the above can be unlocked").
# data/party.json; the menu's Party and Bonds pages (Hub.gd).
# ======================================================================

var party_def := {}
var _rest_t := 0.0


func party_data() -> Dictionary:
	if party_def.is_empty():
		var d = _load_json("res://data/party.json", {})
		party_def = (d if d is Dictionary else {}).duplicate(true)
		var dr = _load_json("res://data/drafts/contracts.json", {})       # Dev's words (brief "contracts")
		if dr is Dictionary:
			for it in dr.get("items", []):
				if not (it is Dictionary):
					continue
				for t in party_def.get("beasts", {}).get("tiers", []):
					if str(t.get("id", "")) != str(it.get("id", "")):
						continue
					if str(it.get("name", "")).strip_edges() != "":
						t["name"] = str(it["name"]).strip_edges()
					if str(it.get("told", "")).count("%s") == 1:
						t["told"] = str(it["told"])
	return party_def


# ---- companions: a party of two, and the roster ---------------------------------------

func party_cap() -> int:
	var need: Dictionary = party_data().get("companions", {}).get("second_slot", {"realm": 4})
	return 2 if realm >= int(need.get("realm", 4)) else 1


func party_size() -> int:
	return party_slots().size()


func party_free_slot() -> int:
	## the first empty place (-1: the party's full)
	if companion.is_empty():
		return 0
	if party_cap() >= 2 and companion2.is_empty():
		return 1
	return -1


func second_slot_text() -> String:
	var need: Dictionary = party_data().get("companions", {}).get("second_slot", {"realm": 4})
	return I18n.t("A second companion can travel with you from %s.") % realm_name_of(int(need.get("realm", 4)))


func realm_name_of(r: int) -> String:
	return str(realm_info(r).get("name", "realm %d" % r))


func roster() -> Array:
	## everyone who has travelled with you, closest first
	var out := []
	for k in flags:
		if str(k).begins_with("travelled:"):
			out.append(str(k).trim_prefix("travelled:"))
	out.sort_custom(func(a, b): return float(bond(a).get("warmth", 0.0)) > float(bond(b).get("warmth", 0.0)))
	return out


func in_settlement() -> bool:
	return current_level == "village" or havens.has(current_level)


func can_recall(name: String) -> String:
	## "" if you can call them to your side from here, else why not
	if in_party(name) >= 0:
		return I18n.t("%s is already with you.") % name
	if not has_flag("travelled:" + name):
		return I18n.t("%s has never travelled with you.") % name
	if float(bond(name).get("warmth", 0.0)) < float(party_data().get("companions", {}).get("recall_warmth", 45)) and not (sys("menagerie") != null and sys("menagerie").is_sworn(name)):
		return I18n.t("%s isn't close enough to you to drop everything and come.") % name
	if not in_settlement():
		return I18n.t("Send word from a town -- %s can't find you down here.") % name
	if party_free_slot() < 0:
		return I18n.t("Your party is full. Send someone home first.") if party_cap() >= 2 else I18n.t("Your party is full. ") + second_slot_text()
	return ""


func recall(name: String) -> String:
	var why := can_recall(name)
	if why != "":
		return why
	var bd := bond(name)
	var t: Array = bd.get("tint", [0.9, 0.95, 1.0])
	var nc := {"name": name, "persona": str(bd.get("persona", name)), "home": str(bd.get("home", "village")),
		"tint": t, "partner": partner == name}
	if party_free_slot() == 1:
		companion2 = nc
	else:
		companion = nc
	warm_bond(name, 1.0)
	log_event("companion_recalled", {"npc": name})
	message.emit("COMPANION: %s comes when you send for them." % name)
	companion_changed.emit()
	stats_changed.emit()
	return ""


func swap_party() -> void:
	## the second walks at your shoulder, the first behind
	if companion2.is_empty():
		return
	var t := companion
	companion = companion2
	companion2 = t
	companion_changed.emit()


# ---- contract beasts ----------------------------------------------------------------------

func beast_data() -> Dictionary:
	return party_data().get("beasts", {})


func contract_cap() -> int:
	var n := 1
	for row in beast_data().get("roster", [[0, 2]]):
		if taming_level() >= int(row[0]):
			n = int(row[1])
	return n


func _summon_need_ok(need: Dictionary) -> bool:
	return taming_level() >= int(need.get("taming", 0)) and realm >= int(need.get("realm", 0))


func summon_cap() -> int:
	var n := 1
	for row in beast_data().get("summon", []):
		if _summon_need_ok(row.get("need", {})):
			n = maxi(n, int(row.get("slots", 1)))
	return n


func next_summon_text() -> String:
	for row in beast_data().get("summon", []):
		if not _summon_need_ok(row.get("need", {})):
			var nd: Dictionary = row.get("need", {})
			return I18n.t("%d at your side from Taming %d and %s.") % [int(row.get("slots", 1)), int(nd.get("taming", 0)), realm_name_of(int(nd.get("realm", 0)))]
	return ""


func beasts_out() -> Array:
	## the beasts at your side now, the lead first (not one off exploring)
	var out := []
	if not familiar.is_empty() and not bool(familiar.get("away", false)):
		out.append(familiar)
	for c in contracts:
		if not is_same(c, familiar) and bool(c.get("out", false)) and not bool(c.get("away", false)):
			out.append(c)
	return out


func summoned_beast(i: int) -> Dictionary:
	## the i-th beast at your side (0: the lead) -- what a Familiar node shows
	if i == 0:
		return familiar if not bool(familiar.get("away", false)) else {}
	var others := beasts_out().filter(func(c): return not is_same(c, familiar))
	return others[i - 1] if i - 1 < others.size() else {}


func _out_count() -> int:
	var n := 0
	for c in contracts:
		if bool(c.get("out", false)):
			n += 1
	return n


func beast_count() -> int:
	## contracts that are beasts (golems are built, and don't use a taming slot)
	var n := 0
	for c in contracts:
		if not bool(c.get("construct", false)):
			n += 1
	return n


func can_tame_more() -> bool:
	return beast_count() < contract_cap()


func summon_beast(i: int) -> String:
	if i < 0 or i >= contracts.size():
		return I18n.t("No such contract.")
	var c: Dictionary = contracts[i]
	if bool(c.get("out", false)):
		return I18n.t("%s is already at your side.") % c.get("name", "")
	if bool(c.get("breeding", false)):
		return I18n.t("%s is in the stable.") % c.get("name", "")
	if _out_count() >= summon_cap():
		return I18n.t("You can hold %d at your side. %s") % [summon_cap(), next_summon_text()]
	c["out"] = true
	if familiar.is_empty():
		c["lead"] = true
		familiar = c
	log_event("beast_summoned", {"name": c.get("name", "")})
	message.emit("%s steps out of your spirit space." % c.get("name", ""))
	familiar_changed.emit()
	stats_changed.emit()
	return ""


func rest_beast(i: int) -> String:
	if i < 0 or i >= contracts.size():
		return I18n.t("No such contract.")
	var c: Dictionary = contracts[i]
	if bool(c.get("away", false)):
		return I18n.t("%s is off exploring.") % c.get("name", "")
	if not bool(c.get("out", false)):
		return ""
	c["out"] = false
	if is_same(c, familiar):
		c.erase("lead")
		familiar = {}
		for o in contracts:                  # another at your side steps up
			if bool(o.get("out", false)):
				o["lead"] = true
				familiar = o
				break
	log_event("beast_rested", {"name": c.get("name", "")})
	message.emit("%s goes back into your spirit space to rest." % c.get("name", ""))
	familiar_changed.emit()
	stats_changed.emit()
	return ""


func make_lead(i: int) -> String:
	if i < 0 or i >= contracts.size():
		return I18n.t("No such contract.")
	var c: Dictionary = contracts[i]
	if is_same(c, familiar):
		return ""
	if bool(c.get("breeding", false)):
		return I18n.t("%s is in the stable.") % c.get("name", "")
	if bool(familiar.get("away", false)):
		return I18n.t("%s is off exploring -- wait for it to come home.") % familiar.get("name", "")
	if not familiar.is_empty():
		familiar.erase("lead")
		if not bool(c.get("out", false)):
			familiar["out"] = false          # (they swap places)
	c["out"] = true
	c["lead"] = true
	familiar = c
	message.emit("%s walks at your heel now." % c.get("name", ""))
	familiar_changed.emit()
	stats_changed.emit()
	return ""


func release_beast(i: int) -> String:
	if i < 0 or i >= contracts.size():
		return I18n.t("No such contract.")
	var c: Dictionary = contracts[i]
	if bool(c.get("away", false)):
		return I18n.t("%s is off exploring.") % c.get("name", "")
	if bool(c.get("breeding", false)):
		return I18n.t("%s is in the stable.") % c.get("name", "")
	rest_beast(i)
	contracts.remove_at(i)
	log_event("beast_released", {"name": c.get("name", ""), "species": c.get("species", "")})
	message.emit("You release %s from its contract. It looks back once, and goes." % c.get("name", ""))
	familiar_changed.emit()
	stats_changed.emit()
	return ""


func rename_beast(i: int, nm: String) -> String:
	nm = nm.strip_edges().left(24)
	if i < 0 or i >= contracts.size() or nm == "":
		return I18n.t("That's no name.")
	if bool(contracts[i].get("breeding", false)):
		return I18n.t("%s is in the stable.") % contracts[i].get("name", "")
	for c in contracts:
		if str(c.get("name", "")) == nm:
			return I18n.t("Another of yours has that name.")
	contracts[i]["name"] = nm
	familiar_changed.emit()
	return ""


func contract_tier_def(beast: Dictionary = {}) -> Dictionary:
	var tiers: Array = beast_data().get("tiers", [])
	var t := int(_bst(beast).get("tier", 0))
	return tiers[clampi(t, 0, tiers.size() - 1)] if tiers.size() > 0 else {}


func deepen_missing(i: int) -> Array:
	## what you still need to deepen this contract ([] = ready; ["max"] = can't go further)
	if i < 0 or i >= contracts.size():
		return ["no such contract"]
	var c: Dictionary = contracts[i]
	var tiers: Array = beast_data().get("tiers", [])
	var nt := int(c.get("tier", 0)) + 1
	if nt >= tiers.size():
		return ["max"]
	var need: Dictionary = tiers[nt].get("need", {})
	var out := []
	if float(c.get("bond", 0.0)) < float(need.get("bond", 0)):
		out.append(I18n.t("bond %d") % int(need["bond"]))
	if realm < int(need.get("realm", 0)):
		out.append(realm_name_of(int(need["realm"])))
	for it in need.get("items", {}):
		if count(str(it)) < int(need["items"][it]):
			out.append("%d %s" % [int(need["items"][it]), item_name(str(it))])
	if gold < int(need.get("gold", 0)):
		out.append(I18n.t("%d gold") % int(need["gold"]))
	return out


func deepen_contract(i: int) -> String:
	var miss := deepen_missing(i)
	if not miss.is_empty():
		return I18n.t("It can't go deeper.") if miss == ["max"] else I18n.t("Not yet: ") + ", ".join(miss) + "."
	var c: Dictionary = contracts[i]
	var tiers: Array = beast_data().get("tiers", [])
	var nt := int(c.get("tier", 0)) + 1
	var need: Dictionary = tiers[nt].get("need", {})
	for it in need.get("items", {}):
		remove_item(str(it), int(need["items"][it]))
	gold -= int(need.get("gold", 0))
	c["tier"] = nt
	add_skill_xp("taming", 25.0 * nt, "a contract deepened")
	gain_insight(2.0 * nt, "a contract deepened")
	log_event("contract_deepened", {"name": c.get("name", ""), "tier": str(tiers[nt].get("id", ""))})
	bump("contracts_deepened")
	jingle("discovery")
	big_moment.emit("%s -- %s" % [c.get("name", ""), tiers[nt].get("name", "")], str(tiers[nt].get("told", I18n.t("%s is bound closer."))) % str(c.get("name", "")))
	familiar_changed.emit()
	stats_changed.emit()
	return ""


func beast_rows(c: Dictionary) -> Array:
	## [label, value] for the Party page
	var fe: Dictionary = enemies.get(str(c.get("species", "")), {}).get("familiar", {}).get("effect", {})
	var grow := (1.0 + float(c.get("bond", 0.0)) / 100.0) * familiar_effect_mult(c)
	var scaled := {}
	for k in fe:
		if k in ["gather_chance", "sense_radius", "gather_bonus", "heal_on_kill"] or str(k).begins_with("craft_"):
			scaled[k] = snappedf(float(fe[k]) * grow, 0.01)
		else:
			scaled[k] = snappedf(1.0 + (float(fe[k]) - 1.0) * grow, 0.001)
	var MNs = sys("menagerie")                      # round 141b: its role's gift counts too
	if MNs != null:
		var rs := {}
		MNs._scale(MNs.role_of(c).get("effect", {}), grow, rs)
		for k in rs:
			if k in ADDITIVE_KEYS or str(k).begins_with("craft_"):
				scaled[k] = snappedf(float(scaled.get(k, 0.0)) + float(rs[k]), 0.01)
			else:
				scaled[k] = snappedf(float(scaled.get(k, 1.0)) * float(rs[k]), 0.001)
	var out := [["Kind", str(enemies.get(str(c.get("species", "")), {}).get("name", c.get("species", "")))],
		["Bond", "%d / 200%s" % [int(c.get("bond", 0.0)), (" (" + str(familiar_stage_def(c).get("title", "")) + ")") if str(familiar_stage_def(c).get("title", "")) != "" else ""]],
		["Contract", str(contract_tier_def(c).get("name", "Bonded"))],
		["Gives", effect_text(scaled) + ("" if is_same(c, familiar) else " (x%.1f while it follows the lead)" % float(beast_data().get("second_share", 0.6)))]]
	if familiar_bite(c) > 0:
		out.append(["Bite", str(familiar_bite(c))])
	return out


func _rest_tick(delta: float) -> void:
	## beasts resting in your spirit space still grow, slowly
	_rest_t += delta
	if _rest_t < 60.0:
		return
	_rest_t = 0.0
	var per := float(beast_data().get("rest_bond_per_minute", 0.1))
	for c in contracts:
		if not bool(c.get("out", false)):
			grow_bond(per, c)


func r39_save() -> Dictionary:
	return {"contracts": contracts, "companion2": companion2}


func r39_load(d: Dictionary) -> void:
	contracts = d.get("contracts", []) if d.get("contracts", []) is Array else []
	companion2 = d.get("companion2", {}) if d.get("companion2", {}) is Dictionary else {}
	if contracts.is_empty() and not familiar.is_empty():
		# a save from before contracts: your familiar is your first
		familiar["out"] = true
		familiar["lead"] = true
		if not familiar.has("tier"):
			familiar["tier"] = 0
		contracts = [familiar]
	else:
		var lead := {}
		for c in contracts:
			if bool(c.get("lead", false)):
				lead = c
		if not lead.is_empty() and lead.has("away") != familiar.has("away"):
			if familiar.has("away"):
				lead["away"] = true
			else:
				lead.erase("away")
		familiar = lead                     # one dictionary, not two copies
	if companion2.has("name"):
		flags["travelled:" + str(companion2["name"])] = true



# ======================================================================
# round 40 -- the modular systems (scripts/systems/GameSystem.gd says how
# they're shaped). Robert: "build it to make sense and modular -- if we
# build a modular game it will make updates easier."
# ======================================================================

const SYSTEM_SCRIPTS := [
	["poison", "res://scripts/systems/Poison.gd"],         # round 138: coatings, antidotes, venom
	["dao", "res://scripts/systems/Dao.gd"],               # round 139: dao sense, eight daos, a way of your own
	["difficulty", "res://scripts/systems/Difficulty.gd"], # round 139: foe tiers and self-set handicaps
	["synergy", "res://scripts/systems/Synergy.gd"],       # the swarm and qi, bound
	["mind", "res://scripts/systems/Mind.gd"],             # where your sitting goes
	["cleansing", "res://scripts/systems/Cleansing.gd"],   # meridian nodes, major and minor
	["research", "res://scripts/systems/Research.gd"],     # the swarm's tree: designs, wetware ... power armour
	["lore", "res://scripts/systems/Lore.gd"],             # round 42: words that give something -- tips and history
	["world", "res://scripts/systems/World.gd"],           # round 44: the calendar, the hour, the weather, festivals
	["factions", "res://scripts/systems/Factions.gd"],     # round 44: five peoples who remember what you did
	["settlements", "res://scripts/systems/Settlements.gd"],   # round 44: camps in the deep that grow
	["ruins", "res://scripts/systems/Ruins.gd"],           # round 44: dig sites, relics, the Old Age timeline
	["legacies", "res://scripts/systems/Legacies.gd"],     # round 51: minor, major and heavenly inheritances, laid out anew each game
	["quests", "res://scripts/systems/Quests.gd"],         # round 52: side quests from the people of Eliet and the deep's towns
	["reaches", "res://scripts/systems/Reaches.gd"],       # round 56: the deep's reaches -- lands past every floor's edge
	["floorrun", "res://scripts/systems/FloorRun.gd"],     # round 61: a floor's tally and verdict, the descent streak
	["travel", "res://scripts/systems/Travel.gd"],         # round 63: waystones and quick travel
	["pursuit", "res://scripts/systems/Pursuit.gd"],       # round 63: downtime -- goals pursued while you're away, regulated
	["heirloom", "res://scripts/systems/Heirloom.gd"],        # round 120: the Heirloom set
	["balance", "res://scripts/systems/Balance.gd"],       # round 119: the two roads, Imbalance, the Even Road
	["lives", "res://scripts/systems/Lives.gd"],           # round 121: the end-of-life card
	["opening", "res://scripts/systems/Opening.gd"],       # round 121: the first half hour -- first blood, first road, first floor
	["arts", "res://scripts/systems/Arts.gd"],             # round 122: the ki arts library -- support arts, sect and path arts, resonance
	["paths", "res://scripts/systems/Paths.gd"],           # round 121: nine classes -- ranks earned by deeds, an art, a keystone
	["craftbook", "res://scripts/systems/CraftBook.gd"],   # round 137: the crafting journal -- recipes, supplies, herbology, bestiary
	["craftplay", "res://scripts/systems/CraftPlay.gd"],   # round 141c: a mini-game for every craft
	["cooking", "res://scripts/systems/Cooking.gd"],           # round 164: meals with buffs
	["firsthour", "res://scripts/systems/FirstHour.gd"],       # round 163: the guided first hour
	["goals", "res://scripts/systems/DailyGoals.gd"],         # round 162: today's three goals
	["breeding", "res://scripts/systems/Breeding.gd"],       # round 161: the stable -- pair two beasts, hatch a young one with a lineage
	["menagerie", "res://scripts/systems/Menagerie.gd"],   # round 141b: beast roles and deeds, wayfarers (human companions who can swear to you)
	["tester", "res://scripts/systems/Tester.gd"],   # round 156: account-wide test kit (vault, portable table, god mode)
	["seek", "res://scripts/systems/Seek.gd"],   # round 155: both human companions can search
	["constructs", "res://scripts/systems/Constructs.gd"],   # round 154: golems, the mech suit, voyages
	["pull", "res://scripts/systems/Pull.gd"],             # round 152: teasers, omens, barks, petting, streak titles
	["stories", "res://scripts/systems/WayfarerStories.gd"],   # round 143: a three-chapter story for each wayfarer
	["commissions", "res://scripts/systems/Commissions.gd"],   # round 143: the commission board (menu > Craft)
	["nanite_mind", "res://scripts/systems/NaniteMind.gd"],   # round 146: the swarm wakes: a voice shaped by your play
	["workshop", "res://scripts/systems/Workshop.gd"],            # round 148: the road workshop and the sects' techniques
	["inner_world", "res://scripts/systems/InnerWorld.gd"],   # round 147: the inner world -- biosphere, habitat, practice ground, Dao pool
	["aspect", "res://scripts/systems/Aspect.gd"],             # round 146: aspecting the nanites to an element (active meditation)
	["garden", "res://scripts/systems/Garden.gd"],             # round 145: three herb plots at your lodging (menu > Road)
	["collection", "res://scripts/systems/Collection.gd"],     # round 145: completion percentages and silhouettes (menu > Road)
	["boons", "res://scripts/systems/Boons.gd"],               # round 144: a blessing and a hardship per trip, the pedlar, the shrine, the quarry (menu > Road)
	["atlas", "res://scripts/systems/Atlas.gd"],           # round 75: where you've been, and what you found there (the Map page)
]
var systems := {}
var sitting := false             # sitting to meditate (anywhere -- not just at a shrine)


func _init_systems() -> void:
	for row in SYSTEM_SCRIPTS:
		var s = load(str(row[1])).new()
		s.name = "System_" + str(row[0])
		s.id = str(row[0])
		add_child(s)
		systems[str(row[0])] = s
	for s2 in systems.values():
		s2.setup(self)


func sys(sid: String):
	return systems.get(sid, null)


func _systems_reset() -> void:
	for s in systems.values():
		s.reset()


func _systems_save() -> Dictionary:
	var out := {}
	for k in systems:
		out[k] = systems[k].save_state()
	return out


func _systems_load(d: Dictionary) -> void:
	for k in systems:
		var v = d.get(k, {})
		systems[k].reset()
		systems[k].load_state(v if v is Dictionary else {})


func _systems_tick(delta: float) -> void:
	for s in systems.values():
		s.tick(delta)
	if not sitting and sys("mind"):
		var bg: float = sys("mind").bg_rate()
		if bg > 0.0:
			# the swarm works on whatever's waiting -- the research under way and the node being cleansed
			var r_on: bool = sys("research") != null and sys("research").current != ""
			var c_on: bool = sys("cleansing") != null and sys("cleansing").current() != ""
			if r_on or c_on:
				var sh := {"cultivate": 0.0, "research": (0.5 if c_on else 1.0) if r_on else 0.0, "cleanse": (0.5 if r_on else 1.0) if c_on else 0.0}
				for s2 in systems.values():
					s2.background(delta * bg, sh)


# ======================================================================
# Round 43 -- inheritance crystals.
# Robert, 2026-10-04: "A base requirement for inheritances is needed. If the
# character finds one and can't use it at all, or yet, they can condense the
# inheritance into an inheritance crystal for later use or sale."
#
# THE BASE REQUIREMENT: a legacy asks for the higher of the realm its level
# file names and the realm of every art it teaches (a floor that names none
# asks a realm for every four floors down). Below it, the will turns you away.
# OF NO USE: everything it would teach, you already know, and it carries
# nothing else.
# THE CRYSTAL: either way -- or simply because you'd rather -- the will can be
# condensed into an Inheritance Crystal: carried, absorbed once you're ready
# (Pack: Absorb), or sold to a trader. Condensed, the seat is empty for good.
# ======================================================================

var _inh_data := {}


func inheritance_data() -> Dictionary:
	## data/inheritance.json (round 43)
	if _inh_data.is_empty():
		var d = _load_json("res://data/inheritance.json", {})
		_inh_data = d if d is Dictionary and not d.is_empty() else {"floors_per_realm": 4, "max_default_realm": 12, "crystal_value": {"base": 120, "per_art": 250, "qi_sqrt": 4.0}}
	return _inh_data


func inheritance_default_realm(floor_n: int) -> int:
	var per := maxi(1, int(inheritance_data().get("floors_per_realm", 4)))
	return clampi(floor_n / per, 1, int(inheritance_data().get("max_default_realm", 12)))


func inheritance_need(needs: int, grants: Dictionary) -> int:
	## the base requirement: the named realm, or the realm of the hardest art it teaches
	var r := maxi(needs, 0)
	for tid in grants.get("techniques", []):
		r = maxi(r, int(technique_defs.get(str(tid), {}).get("realm", 0)))
	return r


func inheritance_new(grants: Dictionary) -> Array:
	## what in it would be new to you (names); [] = it can't give you anything
	var out := []
	for id in grants.get("items", {}):
		if item_def(str(id)).is_empty():
			continue
		out.append(item_name(str(id)))
	for tid in grants.get("techniques", []):
		if technique_defs.has(str(tid)) and not techniques.has(str(tid)):
			out.append(str(technique_defs[str(tid)].get("name", tid)))
	if float(grants.get("qi", 0.0)) > 0.0:
		out.append("%d qi" % int(grants["qi"]))
	return out


func inheritance_state(needs: int, grants: Dictionary) -> String:
	## "ready", "locked" (below the base requirement) or "useless" (nothing in it for you)
	if realm < inheritance_need(needs, grants):
		return "locked"
	if inheritance_new(grants).is_empty():
		return "useless"
	return "ready"


func crystal_value(need: int, grants: Dictionary) -> int:
	## what a trader pays for one: the depth of the legacy, and what's in it
	var cv: Dictionary = inheritance_data().get("crystal_value", {})
	var v := int(cv.get("base", 120)) * (1 + need) * (1 + need)
	for id in grants.get("items", {}):
		v += int(item_def(str(id)).get("value", 0)) * int(grants["items"][id])
	v += int(cv.get("per_art", 250)) * (1 + need) * (grants.get("techniques", []) as Array).size()
	v += int(sqrt(maxf(float(grants.get("qi", 0.0)), 0.0)) * float(cv.get("qi_sqrt", 4.0)))
	return v


func condense_inheritance(key: String, master: String, needs: int, grants: Dictionary) -> String:
	## a dead master's will, condensed for later: returns the crystal's id ("" if already gone)
	if has_flag(key):
		return ""
	var need := inheritance_need(needs, grants)
	var the := "the " if master.to_lower().begins_with("the ") else ""
	var short_name := master.substr(4) if the != "" else master
	var parts := []
	for id in grants.get("items", {}):
		parts.append(item_name(str(id)))
	for tid in grants.get("techniques", []):
		parts.append(str(technique_defs.get(str(tid), {}).get("name", tid)))
	if float(grants.get("qi", 0.0)) > 0.0:
		parts.append("%d qi" % int(grants["qi"]))
	var def := {"name": I18n.t("Inheritance Crystal of %s%s") % [the, short_name.capitalize()], "type": "crystal",
		"value": crystal_value(need, grants),
		"desc": I18n.t("The will and legacy of %s, pressed into a cold green stone. Absorb it at %s or above. It holds: %s.") % [master, realm_name_of(need), ", ".join(parts) if parts.size() > 0 else "only a memory"],
		"crystal": {"key": key, "master": master, "need": need, "grants": grants.duplicate(true)}}
	var id := register_custom_item(def)
	add_item(id, 1, false)
	set_flag(key)
	set_flag(key + ":crystal")
	counters["crystals_condensed"] = float(counters.get("crystals_condensed", 0.0)) + 1.0
	log_event("inheritance_condensed", {"master": master, "need": need})
	message.emit(I18n.t("CONDENSED: %s's legacy is a crystal in your pack now -- absorb it at %s, or sell it.") % [master, realm_name_of(need)])
	note_place("Condensed the inheritance of %s into a crystal" % master)
	stats_changed.emit()
	return id


func is_crystal(id: String) -> bool:
	return str(item_def(id).get("type", "")) == "crystal" and item_def(id).get("crystal", null) is Dictionary


func crystal_info(id: String) -> Dictionary:
	return item_def(id).get("crystal", {}) if is_crystal(id) else {}


func crystal_ready(id: String) -> String:
	## "" if you can absorb it now, else why not
	if not is_crystal(id) or count(id) <= 0:
		return I18n.t("You don't have that crystal.")
	var c := crystal_info(id)
	var need := int(c.get("need", 0))
	if realm < need:
		return I18n.t("The crystal is cold in your hand. It opens to %s -- you're %s.") % [realm_name_of(need), realm_name_of(realm)]
	return ""


func absorb_crystal(id: String) -> String:
	var why := crystal_ready(id)
	if why != "":
		return why
	var c := crystal_info(id)
	var g = c.get("grants", {})
	var grants: Dictionary = g if g is Dictionary else {}
	var master := str(c.get("master", "a nameless master"))
	var fresh := inheritance_new(grants)
	remove_item(id, 1)
	counters["legacies"] = float(counters.get("legacies", 0.0)) + 1.0
	log_event("inheritance", {"master": master, "from": "crystal"})
	message.emit("INHERITANCE: the crystal melts into your palm -- you receive the legacy of %s." % master)
	for iid in grants.get("items", {}):
		add_item(str(iid), int(grants["items"][iid]))
	for tid in grants.get("techniques", []):
		learn(str(tid), "inheritance:" + master)
	if float(grants.get("qi", 0.0)) > 0.0:
		add_qi(float(grants["qi"]), master + "'s legacy")
	var bl := blood_inheritance(str(c.get("key", id)), grants)
	if bl != "":
		message.emit(I18n.t("In the legacy, a trace of %s's blood: %s.") % [master, blood_line(bl).get("name", bl)])
	note_place(I18n.t("Absorbed the crystal of ") + master)
	stats_changed.emit()
	return I18n.t("You absorb the legacy of %s%s.") % [master, (": " + ", ".join(fresh)) if fresh.size() > 0 else " -- there was nothing in it you didn't already have"]


# ======================================================================
# Round 46 -- traps and secrets you have to notice.
# Robert, 2026-10-04: "Be more subtle with traps and secrets." Hidden walls
# and (past the first floor) traps give nothing away until you notice them;
# noticing builds while you're near one -- standing still is best, sprinting
# past you'll never see it, Survival makes you quicker. Spirit Sense notices
# whatever's hidden within its reach. data/subtlety.json.
# ======================================================================

var _subtle := {}


func subtlety(kind: String) -> Dictionary:
	if _subtle.is_empty():
		var d = _load_json("res://data/subtlety.json", {})
		_subtle = d if d is Dictionary and not d.is_empty() else {"secret": {}, "trap": {}}
	return _subtle.get(kind, {})


func notice_rate(kind: String, who) -> float:
	## how fast (per second) you notice a hidden thing of this kind, right now
	var c := subtlety(kind)
	var r := float(c.get("base", 0.15)) + float(c.get("per_survival", 0.02)) * skill_level("survival")
	var v := Vector3.ZERO
	if who != null and who is CharacterBody3D:
		v = (who as CharacterBody3D).velocity
	var speed := Vector2(v.x, v.z).length()
	if speed < 0.5:
		r *= float(c.get("still_mult", 3.0))          # stopped to look
	elif speed > 6.5:
		r *= float(c.get("sprint_mult", 0.25))        # running past
	return r


const Data = preload("res://data/gear.json")
const PlayerData = preload("res://data/character.json")

func grant_item(id: String, quality: int = 1, how: String = "found") -> String:
	var def: Dictionary = item_def(id)
	if def.is_empty():
		return I18n.t("Item not found.")
	if def.get("type") == "treasure":
		if count(id) > 0:
			return I18n.t("Item already granted.")
		inventory[id] = 1
		note_item(id)
		message.emit(I18n.t("TREASURE: %s -- %s") % [item_name(id), def.get("desc", "")])
		log_event("treasure", {"id": id})
		if def.has("sips"):
			counters["gourd_sips"] = float(def["sips"])
		stats_changed.emit()
		return I18n.t("Item granted: %s") % item_name(id)
	if def.get("type") == "formula":
		learn_formula(str(def.get("formula", "")), how)
		stats_changed.emit()
		return I18n.t("Formula learned: %s") % item_name(id)
	if def.get("type") == "material" and count(id) + 1 > pouch_cap():
		return I18n.t("Your pouch is full. Item not granted.")
	inventory[id] = count(id) + 1
	note_item(id)
	_auto_wear(id)
	message.emit("Item granted: %s" % item_name(id))
	stats_changed.emit()
	return I18n.t("Item granted: %s") % item_name(id)


const MAX_INVENTORY_SIZE = 50

func check_inventory_space() -> bool:
	return PlayerData.inventory.size() < MAX_INVENTORY_SIZE


func _load_item_def(id: String) -> Dictionary:
	var items: Dictionary = _load_json("res://data/items.json", {})
	if id in items:
		return items[id] as Dictionary
	var gear: Dictionary = _load_json("res://data/gear.json", {})
	if id in gear:
		return gear[id] as Dictionary
	return {}


# --- func grant_item (full) ---


func consume(item_id: String, amount: int) -> bool:
	if not inventory.has(item_id):
		return false
	if inventory[item_id] < amount:
		return false
	inventory[item_id] -= amount
	if inventory[item_id] == 0:
		inventory.erase(item_id)
	stats_changed.emit()
	return true


func is_consumed(item_id: String) -> bool:
	return inventory.has(item_id) and inventory[item_id] > 0
