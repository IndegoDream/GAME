#!/usr/bin/env python3
"""Floor 5, Shellhaven -- the town on the sleeping tortoise (2026-10-02).
Built by Claude from Robert's settlement vision after Dev's first draft
(v36) came back without a single townsperson (its brief never contained the
settlement rules -- fixed in godot_bridge.project_brief). Run with the
HomeAI folder on sys.path: it draws the map with godot_levels/godot_layout."""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)

LEVEL = {
 "id": "floor5", "name": "Floor 5, Shellhaven", "theme": "settlement", "depth": 5, "breathing": True,
 "layout": {"seed": 5, "secret_passages": 0, "rooms": [
  {"name": "The Stair Landing", "size": [9, 6], "has": ["<", "L*2", "x*2", "R"]},
  {"name": "The Shell Gate", "size": [10, 6], "has": ["L*2", "=*2", "Q"]},
  {"name": "The Mossmarket", "size": [16, 9], "has": ["L*3", "M", "b*3", "h*2", "G"]},
  {"name": "The Breathing Stone", "size": [14, 11], "has": ["f", "P", "L*4", "Y", "K"]},
  {"name": "The Warm Scale Inn", "size": [10, 7], "has": ["I", "L*2", "H", "b*2", "N"]},
  {"name": "Vent Row", "size": [14, 6], "has": ["F", "B", "L*2", "H*2"]},
  {"name": "Apothecary Terrace", "size": [10, 7], "has": ["A", "C", "L*2", "h*3"]},
  {"name": "The House of Mending", "size": [9, 7], "has": ["E", "L*2", "h*2", "H"]},
  {"name": "The Scale Homes", "size": [14, 8], "has": ["H*4", "L*2", "O", "h"]},
  {"name": "The Moss Gardens", "size": [12, 9], "has": ["h*6", "L*2", "a*2", "~*3", "&", "J"]},
  {"name": "Brann's Cellar", "size": [6, 5], "secret": True, "has": ["L", "D", "V"]},
  {"name": "The Tortoise's Brow", "size": [9, 7], "has": ["Z", "L*3", "U", "?"]},
  {"name": "The Exam Hall", "size": [12, 8], "has": ["L*3", "=*2", "X", "c*2"]},
  {"name": "The Ring of Moss", "size": [12, 9], "has": ["L*3", "=*4", "j"]},
  {"name": "The Lower Stair", "size": [10, 6], "has": [">", "L*2", "x*2", "W"]}]},
 "enemies": {"a": "cave_hare"},
 "npcs": {
  "Q": {"role": "villager", "name": "Warden Tolle", "stays": True,
        "line": "Up or down, stranger? Mind the steps -- they shift when she breathes.",
        "lines": ["Thirty years I've kept this gate. I remember every face that came down the stair. I'll remember yours.",
                  "Most who come down are running from something up there. Most stay."],
        "persona": "Warden Tolle, keeper of Shellhaven's gate: a broad, slow-talking man who has counted every soul that came down the stair for thirty years and remembers their names."},
  "M": {"role": "merchant", "name": "Old Nettle",
        "line": "Salves, pills, tea from the shell-moss. Everything the Grove will try to take from you, I sell back.",
        "stock": ["resin_salve", "shell_tea", "verdant_pill", "magma_pill", "moonpetal_tonic", "qi_pill", "breakthrough_pill", "barkskin_mail"],
        "persona": "Old Nettle, Shellhaven's merchant: a dry, bargaining woman with moss-green fingernails who has outlived three business partners and trusts coin more than promises."},
  "G": {"role": "villager", "name": "Fen the Porter",
        "line": "Need something carried? Up the shell, down the shell, I know every handhold.",
        "lines": ["They say the Grove below was a garden once. A sect's garden. Then the garden started gardening them.",
                  "I've never seen the sky. Is it really that big? Bigger than the cavern?",
                  "If you go down, bring me back a firestone from the Forges. Just one. I want to know what warm feels like without the tortoise."],
        "persona": "Fen, a wiry porter who hauls goods up and down the tortoise's shell for coin: cheerful, nosy, always hungry, and secretly aching to see the surface sky."},
  "K": {"role": "villager", "name": "Mother Kesh", "stays": True,
        "line": "She dreams, you know. The tortoise. I hear her when I sleep.",
        "lines": ["She's dreaming of the sea. A sea that isn't there any more.",
                  "Put your hand on the Breathing Stone. Warm, isn't it? That's her breath, coming up through the shell.",
                  "Ask the old face at her brow a question and she'll ask you one back. Think before you answer."],
        "persona": "Mother Kesh, the oldest woman in Shellhaven, half-blind and sharp-tongued, who claims the tortoise speaks to her in dreams."},
  "I": {"role": "innkeeper", "name": "Hollin Brask", "price": 12,
        "line": "A bed by the warm wall, a bowl of shell-moss stew, and a door that locks. Twelve gold.",
        "lines": ["The roots below have been creeping up the Lower Stair. Last week a vine came through the floor and took a man's boot.",
                  "Someone saw a stag made of moss down in the Grove. Fed it a turnip. It followed them halfway home.",
                  "There's a monk down there who never stopped meditating. The roots grew right through him. They say he still breathes.",
                  "The Grove Mother? Don't let anyone tell you she's a story."],
        "persona": "Hollin Brask, keeper of the Warm Scale Inn: big-handed, soft-voiced, a former delver who lost two fingers in the Grove and now feeds everyone who comes back up."},
  "N": {"role": "villager", "name": "Ysolde",
        "line": "Don't mind me. I'm waiting for someone strong enough to go deeper.",
        "lines": ["My sect went down to the Sword Grave. I came down to bury them. The Grave wouldn't give them back.",
                  "When you're ready to go deeper, come and find me. I'll know if you're ready."],
        "persona": "Ysolde of the Broken Sect, a sword cultivator in her thirties whose sect-brothers were lost in the Sword Grave below: quiet, dry-humoured, fiercely loyal once trust is earned, and determined to go down again with someone she can rely on."},
  "F": {"role": "smith", "name": "Dagna Ironvent",
        "line": "The tortoise breathes out hotter than any bellows. Best forge under the earth. What are we making?",
        "persona": "Dagna Ironvent, smith of Vent Row: soot to the elbows, loud, generous, and ruthlessly honest about bad steel."},
  "B": {"role": "guild", "guild": "blacksmiths", "name": "Forgemaster Oru",
        "line": "The Blacksmiths' Guild measures you by what you make. Show me your work.",
        "persona": "Forgemaster Oru, master of the Blacksmiths' Guild hall in Shellhaven: precise, quiet, and impossible to impress."},
  "A": {"role": "alchemist", "name": "Lio of the Seven Jars",
        "line": "Seven jars, seven cures. Eight, if you bring me Grove resin.",
        "persona": "Lio of the Seven Jars, Shellhaven's apothecary: young, nervous, brilliant, and always smelling faintly of burnt moonpetal."},
  "C": {"role": "guild", "guild": "alchemists", "name": "Circle-Keeper Venn",
        "line": "The Circle keeps its secrets in its pills. Earn them.",
        "persona": "Circle-Keeper Venn of the Alchemists' Circle: elegant, ambitious, and politely contemptuous of the Healers' House."},
  "E": {"role": "guild", "guild": "healers", "name": "Sister Amaranth",
        "line": "The Healers' House turns no one away -- but we remember who helped us mend the others.",
        "persona": "Sister Amaranth of the Healers' House: patient, tired, kind, and quietly furious at the Alchemists' Circle for selling cures it should give away."},
  "O": {"role": "villager", "name": "Tamsin the Lamplighter",
        "line": "Every lantern in Shellhaven, twice a night. I talk to the moss while I go. It doesn't talk back. Mostly.",
        "lines": ["There's a seam in the shell behind the gardens where the moss won't grow. Old Brann the Scale-Keeper used to go in there and not come out for days.",
                  "The moss glows brighter when she's dreaming well. It's been bright all month."],
        "persona": "Tamsin, Shellhaven's lamplighter: quick, curious, a little odd, who walks every lantern route twice a night and knows every hidden seam in the shell."},
  "X": {"role": "academy", "name": "Examiner Sun Liyan",
        "line": "The Lotus Ascent Academy tests applicants here, where the deep begins. Strength, knowledge, craft -- all three, or nothing.",
        "persona": "Examiner Sun Liyan of the Lotus Ascent Academy: precise, unhurried, impossible to flatter, quietly delighted by any applicant who surprises her."},
  "j": {"role": "tournament", "name": "Ringmaster Bodo",
        "line": "Three bouts on the moss, one champion! Rivals from every sect come through Shellhaven -- the good ones come back.",
        "persona": "Ringmaster Bodo, who runs the Ring of Moss: loud, generous, a former champion with a ruined knee and an excellent memory for grudges."},
  "W": {"role": "villager", "name": "Sentry Molle", "stays": True,
        "line": "Below is the Grove. The roots have been reaching up again. If you go, go armed -- and come back.",
        "lines": ["We lost three this month to the thornlings. Little things. Fast. Don't let them get behind you."],
        "persona": "Sentry Molle, who guards the Lower Stair: young, stern, frightened and hiding it."}},
 "chests": {
  "D": {"loot": {"tortoise_scale": 1, "gold": [30, 60]}, "note": "Brann's sealed chest, warm to the touch"},
  "J": {"loot": {"spirit_herb": [2, 4], "moonpetal": [1, 3]}, "note": "a gardener's buried jar", "hidden": True}},
 "lore": {
  "R": {"title": "The First Lantern",
        "text": "Here the first of us set down a lantern and saw, by its light, that the hill in front of us had an eye. "
                "We did not run. Where would we have run to? We built on her back instead, and she let us."},
  "Y": {"title": "The Breathing Stone",
        "text": "Warm to the touch, and every fourteen heartbeats it sighs. The children of Shellhaven are told: if the Stone ever "
                "stops, run up the stair and do not look back. The grown-ups tell each other the same thing, more quietly."},
  "U": {"title": "What the Tortoise Dreams",
        "text": "Chiselled around the great closed eye: She swam in a sea that is gone. She came down here to sleep until it comes "
                "back. Do not wake her. Do not let anything else wake her."},
  "V": {"title": "Brann's Last Note",
        "text": "If you are reading this, the moss let you in. The scale is hers -- she shed it the year I came down, and it has "
                "kept me warm for forty winters. Keep it close. Don't sell it. -- Brann, Scale-Keeper"}},
 "riddles": {"?": {"title": "The Old Face at Her Brow",
   "question": "I carry my house but am never at home. I am slower than moss, and I will outlive the stone. What am I?",
   "options": ["A snail", "A tortoise", "A river"], "answer": 1,
   "reward": {"items": {"shell_tea": 2, "qi_pill": 1}, "qi": 200}}},
 "exits": {"<": {"to": "floor4", "arrive": ">", "label": "Up to the Nanite Sanctum", "down": False},
           ">": {"to": "floor6", "arrive": "<", "label": "Down to the Strangling Grove"}},
}


def main(homeai_dir):
    sys.path.insert(0, homeai_dir)
    import godot_levels as GL
    text, notes = GL.normalize_text(json.dumps(LEVEL), "floor5.json")
    r = GL.validate_text(text, GAME, "floor5.json")
    print("ok", r["ok"], r["errors"])
    print("notes", notes)
    print("warnings", r["warnings"])
    print("settlement notes", GL.richness_notes(r["summary"], "settlement"))
    if r["ok"]:
        with open(os.path.join(GAME, "levels", "floor5.json"), "w", encoding="utf-8") as f:
            f.write(text)
        print("\n".join(json.loads(text)["map"]))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(GAME, "..", "homeai"))
