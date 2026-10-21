#!/usr/bin/env python3
"""Floors 6-9 below Shellhaven -- the five-element walk (2026-10-02).
Built by Claude from Dev's v39-v42 drafts (Dev's room ideas, kept where
they worked) after review: those drafts had 8-11 rooms, template rooms,
floor 9 without a boss, floor 8's stairs in a "Trap Room 3" away from the
Emperor, techniques taught twice. Run with the HomeAI folder as argv[1]."""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)


def ex(up, down, up_label, down_label):
    return {"<": {"to": up, "arrive": ">", "label": up_label, "down": False},
            ">": {"to": down, "arrive": "<", "label": down_label}}


FLOORS = {
 "floor6": {
  "id": "floor6", "name": "Floor 6, The Strangling Grove", "theme": "dungeon", "depth": 6,
  "ambient": [0.3, 0.45, 0.3],
  "enemies": {"n": "thornling", "k": "rootbound_monk", "G": "grove_mother", "s": "moss_stag"},
  "layout": {"seed": 6, "corridor_traps": 3, "secret_passages": 1, "rooms": [
   {"name": "The Root-Choked Stairwell", "size": [8, 6], "has": ["<", "L*2", "x*2", "h", "n"]},
   {"name": "The Drowned Orchard", "size": [14, 9], "has": ["L*2", "~*8", "&", "t*3", "n*2", "h*2"]},
   {"name": "The Hall of Strangling Vines", "size": [18, 5], "has": ["L*3", "n*3", "t*2", "h"]},
   {"name": "The Herb Terraces", "size": [12, 8], "has": ["L*2", "h*6", "n*2", "C"]},
   {"name": "The Meditation Hall", "size": [10, 8], "has": ["L*2", "k", "c*4", "Y"]},
   {"name": "The Seed Granary", "size": [9, 6], "has": ["L", "b*3", "n*2", "D"]},
   {"name": "The Moss-Stag Clearing", "size": [12, 9], "has": ["L*2", "s*2", "t*3", "h*3"]},
   {"name": "The Resin Pond", "size": [10, 8], "has": ["L", "~*5", "h*2", "k", "o"]},
   {"name": "The Root Hollow", "size": [6, 5], "secret": True, "has": ["L", "R", "V"]},
   {"name": "The Cracked Rock", "size": [8, 6], "has": ["L", "^", "o*2", "n*2"]},
   {"name": "The Weeping Willow Court", "size": [10, 9], "has": ["L*2", "t*2", "?", "k", "h*2"]},
   {"name": "The Sect's Ruined Library", "size": [9, 7], "has": ["L*2", "b*2", "k", "E", "Q"]},
   {"name": "The Thorn Gate", "size": [12, 6], "has": ["L*2", "n*3", "k", "x*2"]},
   {"name": "The Heartwood Throne", "size": [16, 12], "has": ["L*4", "G", ">", "n*2", "t*4"]}]},
  "chests": {
   "C": {"loot": {"spirit_resin": [2, 4], "gold": [40, 70]}, "note": "a terrace-keeper's seed box"},
   "D": {"loot": {"heartwood": [1, 2], "spirit_herb": [2, 4], "gold": [30, 60]}, "note": "a sealed grain bin, roots curled around it"},
   "V": {"loot": {"heartwood": [2, 3], "verdant_pill": [1, 2], "breakthrough_pill": [1, 1], "gold": [120, 200]}, "note": "the sect's last seed vault"},
   "E": {"loot": {"spirit_resin": [1, 3], "qi_pill": [1, 2]}, "note": "a scholar's book-box, swollen shut", "hidden": True}},
  "lore": {
   "Y": {"title": "The Last Sitting",
         "text": "Sixty monks sat down in this hall to meditate through the drought. The rain came, and the roots came with it. "
                 "They are still sitting -- some of them. If one stands up, do not wait to see which way he walks."},
   "R": {"title": "What the Roots Know", "teaches": "evergreen_body",
         "text": "Cut a root and it grows two. Burn the grove and it greens by spring. The sect learned this from the trees too late "
                 "to save the sect, but not too late to write it down: be cut, and grow back."},
   "Q": {"title": "The Gardener's Ledger",
         "text": "Day 112. The mother-tree asked for water again. We gave it blood by mistake -- Han cut his hand on a thorn. "
                 "It has not asked for water since. Day 113. Han is missing."}},
  "riddles": {"?": {"title": "The Willow's Question",
   "question": "I wear a ring for every year I live, yet I have never married. What am I?",
   "options": ["A tree", "A bell", "A sect elder"], "answer": 0,
   "reward": {"items": {"verdant_pill": 1}, "qi": 300}}},
  "exits": ex("floor5", "floor7", "Up to Shellhaven", "Down to the Ember Forges"),
 },
 "floor7": {
  "id": "floor7", "name": "Floor 7, The Ember Forges", "theme": "dungeon", "depth": 7,
  "ambient": [0.55, 0.32, 0.22],
  "enemies": {"i": "cinder_imp", "j": "slag_brute", "F": "furnace_sovereign", "e": "ember_salamander"},
  "layout": {"seed": 7, "corridor_traps": 3, "secret_passages": 1, "rooms": [
   {"name": "The Slag-River Bridge", "size": [16, 5], "has": ["<", "L*2", "i*2", "x*2"]},
   {"name": "The Anvil Hall", "size": [14, 9], "has": ["L*3", "c*4", "j", "i*2", "C", "A"]},
   {"name": "The Bellows Chamber", "size": [10, 8], "has": ["L*2", "b*3", "i*2", "j"]},
   {"name": "The Ore Stores", "size": [9, 7], "has": ["L", "o*6", "i", "b*2"]},
   {"name": "The Cooling Pit", "size": [10, 8], "has": ["L", "~*6", "&", "j", "h"]},
   {"name": "The Firestone Vein", "size": [8, 7], "has": ["L", "^*2", "o*2", "i*2"]},
   {"name": "The Salamander Nest", "size": [10, 7], "has": ["L", "e*2", "h*3", "x*2"]},
   {"name": "The Quenching Trough", "size": [8, 6], "has": ["L", "~*3", "i*2", "D"]},
   {"name": "The Master's Workshop", "size": [6, 5], "secret": True, "has": ["L", "R", "V"]},
   {"name": "The Mould Gallery", "size": [18, 5], "has": ["L*3", "i*2", "j", "c*4"]},
   {"name": "The Slag Heap", "size": [10, 9], "has": ["L", "x*4", "j*2", "o*2", "E"]},
   {"name": "The Tool Crib", "size": [7, 6], "has": ["L*2", "b*2", "?", "h"]},
   {"name": "The Hall of Fallen Hammers", "size": [12, 8], "has": ["L*2", "j*2", "i*2", "Y", "c*2"]},
   {"name": "The Furnace Sovereign's Crucible", "size": [16, 12], "has": ["L*4", "F", ">", "i", "j", "c*4"]}]},
  "chests": {
   "C": {"loot": {"slag_iron": [1, 3], "gold": [50, 80]}, "note": "an anvil-master's strongbox"},
   "D": {"loot": {"firestone": [1, 2], "ember_root": [2, 3]}, "note": "a quencher's crate, still warm"},
   "V": {"loot": {"firestone": [2, 4], "slag_iron": [2, 3], "magma_pill": [1, 2], "breakthrough_pill": [1, 1], "gold": [150, 240]},
         "note": "the master smith's own chest"},
   "E": {"loot": {"slag_iron": [2, 4], "gold_nugget": [1, 2]}, "note": "a box of slag-sorted nuggets, buried in the heap", "hidden": True}},
  "lore": {
   "A": {"title": "The Foundry Oath",
         "text": "We swore on the first anvil: no fire in these halls goes out while one of us still lives. We kept it. "
                 "The fires are still burning. Count the hammers on the wall and you will know how long we kept it."},
   "R": {"title": "The Master's Breath", "teaches": "ember_meridians",
         "text": "Forty years at the bellows taught me one thing: fire does not burn wood, it burns air. Breathe your qi the way "
                 "the bellows breathe the forge -- short, hard, all the way down -- and your strikes will land hot."},
   "Y": {"title": "The Fallen Hammers",
         "text": "Each hammer hangs where its smith fell. The last hook is empty. The Sovereign keeps it for whoever comes "
                 "down here next."}},
  "riddles": {"?": {"title": "The Tool Crib Lock",
   "question": "The more you feed me, the hungrier I grow. Give me water and I die. What am I?",
   "options": ["A salamander", "A smith", "A furnace's fire"], "answer": 2,
   "reward": {"items": {"magma_pill": 1}, "qi": 350}}},
  "exits": ex("floor6", "floor8", "Up to the Strangling Grove", "Down to the Terracotta Barrows"),
 },
 "floor8": {
  "id": "floor8", "name": "Floor 8, The Terracotta Barrows", "theme": "dungeon", "depth": 8,
  "ambient": [0.45, 0.38, 0.3],
  "enemies": {"u": "clay_soldier", "v": "clay_cavalier", "X": "buried_emperor", "q": "burrow_mole"},
  "layout": {"seed": 8, "corridor_traps": 3, "secret_passages": 1, "rooms": [
   {"name": "The Barrow Stair", "size": [9, 6], "has": ["<", "L*2", "u", "x"]},
   {"name": "The First Rank", "size": [20, 6], "has": ["L*3", "u*3", "c*4"]},
   {"name": "The Second Rank", "size": [20, 6], "has": ["L*3", "u*3", "v"]},
   {"name": "The Chariot Pit", "size": [14, 10], "has": ["L*2", "v*2", "b*2", "x*2", "C"]},
   {"name": "The Clay Armoury", "size": [10, 8], "has": ["L*2", "c*2", "u*2", "D"]},
   {"name": "The Kiln Hall", "size": [10, 7], "has": ["L*2", "u", "o*3", "x*2"]},
   {"name": "The Mole Warren", "size": [9, 7], "has": ["L", "q*2", "h*3", "o*2"]},
   {"name": "The Jade Quarry", "size": [12, 8], "has": ["L*2", "^*2", "o*3", "u*2"]},
   {"name": "The General's Tent", "size": [7, 6], "secret": True, "has": ["L", "R", "V", "=*2"]},
   {"name": "The Hall of Offerings", "size": [12, 9], "has": ["L*3", "Y", "b*2", "?", "h*2"]},
   {"name": "The Hall of Ministers", "size": [10, 7], "has": ["L*2", "u*2", "v", "c*2"]},
   {"name": "The Collapsed Barrow", "size": [9, 8], "has": ["L", "x*4", "u*2", "K"]},
   {"name": "The Spirit Road", "size": [18, 5], "has": ["L*3", "v*2", "=*4"]},
   {"name": "The Buried Emperor's Tomb", "size": [16, 12], "has": ["L*4", "X", ">", "u*2", "c*6"]}]},
  "chests": {
   "C": {"loot": {"ancient_clay": [2, 4], "gold": [60, 100]}, "note": "a charioteer's war chest"},
   "D": {"loot": {"ancient_clay": [1, 3], "emperor_jade": [0, 1]}, "note": "a rack-master's clay coffer"},
   "V": {"loot": {"emperor_jade": [2, 3], "earthmarrow_pill": [1, 2], "breakthrough_pill": [1, 1], "gold": [180, 300]},
         "note": "the general's campaign chest"},
   "K": {"loot": {"emperor_jade": [1, 2], "gold_nugget": [1, 3]}, "note": "a grave-robber's stash, never collected", "hidden": True}},
  "lore": {
   "Y": {"title": "The Emperor's Decree",
         "text": "BY ORDER: the army shall stand guard in death as in life. Every soldier shall be made in the likeness of a living "
                 "man. Every living man shall be made into a soldier. -- the Third Year of the Endless Reign."},
   "R": {"title": "The General's Drill Book", "teaches": "terracotta_stance",
         "text": "Lesson one: a soldier who cannot be moved cannot be beaten. Plant your feet as if you had been fired in a kiln. "
                 "Let them strike; clay does not flinch. Lesson two: do not become clay. The Emperor's soldiers forgot lesson two."}},
  "riddles": {"?": {"title": "The Offering Bowl",
   "question": "I was dug from the earth, shaped by hands, baked in fire and given a face. I have stood a thousand years and never taken a step. What am I?",
   "options": ["A statue of the Emperor", "A clay soldier", "A kiln"], "answer": 1,
   "reward": {"items": {"earthmarrow_pill": 1}, "qi": 450}}},
  "exits": ex("floor7", "floor9", "Up to the Ember Forges", "Down to the Sword Grave"),
 },
 "floor9": {
  "id": "floor9", "name": "Floor 9, The Sword Grave", "theme": "dungeon", "depth": 9,
  "ambient": [0.35, 0.4, 0.5],
  "enemies": {"z": "sword_wraith", "y": "grave_keeper", "W": "sword_saint_shade", "r": "steel_crow"},
  "layout": {"seed": 9, "corridor_traps": 3, "secret_passages": 1, "rooms": [
   {"name": "The Grave Descent", "size": [9, 6], "has": ["<", "L*2", "z", "x*2"]},
   {"name": "The Valley of Swords", "size": [20, 12], "has": ["L*4", "z*3", "c*8", "h*2"]},
   {"name": "The Broken Sect Gate", "size": [10, 6], "has": ["L*2", "=*2", "y", "A"]},
   {"name": "The Crow Roost", "size": [9, 8], "has": ["L", "r*2", "x*2", "h"]},
   {"name": "The Disciples' Graveyard", "size": [14, 9], "has": ["L*3", "z*2", "y", "c*4", "?"]},
   {"name": "The Grave-Steel Forge", "size": [12, 8], "has": ["L*2", "^*2", "o*3", "y", "C"]},
   {"name": "The Still Pool", "size": [10, 8], "has": ["L", "~*6", "&", "h*2"]},
   {"name": "The Hall of Broken Blades", "size": [16, 6], "has": ["L*3", "z*3", "c*4", "D"]},
   {"name": "The Last Disciple's Hut", "size": [7, 6], "secret": True, "has": ["L", "I", "V", "h*2"]},
   {"name": "The Hall of Sheathed Blades", "size": [10, 7], "has": ["L*2", "y*2", "b*2"]},
   {"name": "The Wind-Cut Ravine", "size": [18, 5], "has": ["L*2", "z*3", "x*2"]},
   {"name": "The Meditation Cliff", "size": [8, 7], "has": ["L*2", "Z", "h*2", "Y"]},
   {"name": "The Mound of Ten Thousand", "size": [12, 10], "has": ["L*2", "z*2", "y", "c*6", "K"]},
   {"name": "The Saint's Duelling Ground", "size": [18, 14], "has": ["L*4", "W", ">", "c*4"]}]},
  "chests": {
   "C": {"loot": {"grave_steel": [2, 3], "gold": [80, 140]}, "note": "a sword-smith's quench chest"},
   "D": {"loot": {"grave_steel": [1, 2], "sword_qi_pill": [1, 1]}, "note": "a box of broken hilts, and something under them"},
   "V": {"loot": {"sword_qi_pill": [1, 2], "breakthrough_pill": [1, 1], "gold": [200, 320]}, "note": "the disciple's travelling chest"},
   "K": {"loot": {"grave_steel": [2, 4], "sapphire_shard": [1, 2]}, "note": "a blade-wrapped bundle under the mound", "hidden": True}},
  "lore": {
   "A": {"title": "The Sect Gate",
         "text": "THE SECT OF THE STANDING BLADE. One sword for every disciple, planted the day they took their vows, drawn the day "
                 "they died. Look at the valley. Count the swords that were never drawn."},
   "Y": {"title": "Carved on the Meditation Cliff",
         "text": "Before the duel he sat here three days without moving. On the fourth day he stood and said: I have decided. "
                 "That is all sword intent is -- a decision you do not take back."}},
  "inheritances": {"I": {"master": "the Sword Saint's Last Disciple", "hidden": True, "needs_realm": 3,
   "text": "An old woman sits with an empty scabbard across her knees. \"Sixty years I have waited for someone the Grave did not "
           "frighten off. My master's sword is gone -- he carried it into the duel he lost. His sheath remains, and his intent. "
           "Take both. And when you face his shade, do not hesitate. He never did.\"",
   "grants": {"items": {"saints_sheath": 1}, "techniques": ["sword_intent"], "qi": 800}}},
  "riddles": {"?": {"title": "The Graveyard Stone",
   "question": "I am drawn but never painted, sheathed but never dressed, and I have a point I never make in words. What am I?",
   "options": ["A brush", "A sword", "A wraith"], "answer": 1,
   "reward": {"items": {"sword_qi_pill": 1}, "qi": 550}}},
  "exits": ex("floor8", "floor10", "Up to the Terracotta Barrows", "Down to Lanternmere"),
 },
}


def main(homeai_dir):
    sys.path.insert(0, homeai_dir)
    import godot_levels as GL
    ok_all = True
    for fid, lv in FLOORS.items():
        text, notes = GL.normalize_text(json.dumps(lv), fid + ".json")
        r = GL.validate_text(text, GAME, fid + ".json")
        s = r["summary"]
        print(f"== {fid} ok={r['ok']} {r['errors'][:3]}")
        print("   ", {k: s.get(k) for k in ("rooms", "enemies", "bosses", "chests", "lore", "riddles", "inheritances",
                                            "animals", "gems", "fishing", "secrets", "traps", "ore", "herbs", "rows", "width")})
        print("    fixes:", [n for n in notes if not n.startswith("map drawn")])
        print("    rich:", GL.richness_notes(s))
        if r["ok"]:
            with open(os.path.join(GAME, "levels", fid + ".json"), "w", encoding="utf-8") as f:
                f.write(text)
        else:
            ok_all = False
    return ok_all


if __name__ == "__main__":
    sys.exit(0 if main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(GAME, "..", "homeai")) else 1)
