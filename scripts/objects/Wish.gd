extends Node
## A wish at a settlement's smith: say what you want made, in your own
## words (Robert, 2026-10-02: "allow them to request up to 3 items the AI
## with randomly generated"). Three wishes per settlement -- they come back
## at the next settlement you reach -- and a fee in gold. The smith (the
## box's own model, or Artisan's tables when it's down) designs it; chance
## decides how good a casting it is (quality and strength both roll).
## Lives as a child of the smith's NPC node while you're talking.

const LLM := preload("res://scripts/core/LLMCall.gd")
const ArtisanLib := preload("res://scripts/objects/Artisan.gd")

var npc_name := "The smith"
var settlement := ""
var place := ""
var made := ""             # the item id it made (tests read this)
var _llm: Node


func one_shot() -> bool:
	return true


func closing_line() -> String:
	return "(%d wish(es) left here.)" % Game.wishes_left(settlement)


func _ready() -> void:
	_llm = LLM.new()
	add_child(_llm)


func say(text: String, cb: Callable) -> void:
	text = text.strip_edges().left(300)
	if text == "":
		return
	if Game.wishes_left(settlement) <= 0:
		cb.call("(%s shakes their head. \"Three's what I make for anyone, per season. Find another forge.\")" % npc_name)
		return
	if not Game.use_wish(settlement):
		cb.call("(\"That's %d gold for the work. Come back with it.\")" % Game.wish_fee())
		return
	var p := Game.play_profile()
	_llm.ask(ArtisanLib.wish_prompt(npc_name, text, p), func(d): cb.call(finish(text, p, d, randf(), randf())), 260, 0.9)


func finish(text: String, p: Dictionary, d, roll: float, qroll: float) -> String:
	var design: Dictionary = d if d is Dictionary and d.has("name") else ArtisanLib.design(p, text, roll)
	var def := Game.finalize_design(design, Game.reach_depth(), roll, "Wished for at " + place)
	made = Game.grant_custom_item(def, Game.roll_quality(0, qroll), "Wished for at " + place)
	var line := str(design.get("line", "")).strip_edges()
	if line == "":
		line = "\"There. Not quite what you said -- better, maybe.\""
	return "%s: %s\n\n%s -- %s" % [npc_name, line, Game.item_name(made), str(Game.item_def(made).get("desc", ""))]
