#!/usr/bin/env python3
"""Floor 10, Lanternmere -- the floating market on the Last Water
(2026-10-02). The second settlement: a market of barges and platforms
lashed together on a black underground lake -- the last of the sea the
Sleeping Tortoise dreams of (Mother Kesh, Shellhaven: "She's dreaming of
the sea. A sea that isn't there any more."). Outfits the floors below the
Sword Grave. Run with the HomeAI folder on sys.path."""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)

LEVEL = {
 "id": "floor10", "name": "Floor 10, Lanternmere", "theme": "settlement", "depth": 10,
 "ground": "deck", "ambient": [0.48, 0.58, 0.74],
 "layout": {"seed": 10, "secret_passages": 0, "rooms": [
  {"name": "The Cliff Stair", "size": [9, 6], "has": ["<", "L*2", "x*2", "R"]},
  {"name": "The Ferry Landing", "size": [12, 7], "has": ["L*3", "~*4", "&", "Q"]},
  {"name": "The Barge Market", "size": [16, 10], "has": ["L*4", "M", "b*4", "~*3", "G"]},
  {"name": "The Drifting Lantern", "size": [11, 8], "has": ["I", "L*3", "H", "b*2", "N"]},
  {"name": "Lantern Square", "size": [14, 11], "has": ["f", "P", "L*4", "Y", "K"]},
  {"name": "The Smithy Raft", "size": [12, 6], "has": ["F", "L*2", "H", "b*2"]},
  {"name": "The Salt-Pill Stall", "size": [10, 7], "has": ["A", "L*2", "h*3"]},
  {"name": "Guild Row on the Pontoons", "size": [16, 7], "has": ["B", "C", "E", "L*3", "=*3"]},
  {"name": "The Delvers' Hall", "size": [10, 7], "has": ["D", "U", "L*2", "=*2"]},
  {"name": "The Net-Menders' Deck", "size": [12, 8], "has": ["L*2", "~*4", "&*2", "O", "h"]},
  {"name": "The Sunken Shrine", "size": [7, 6], "secret": True, "has": ["L", "V", "J", "~*2"]},
  {"name": "The Lamp Tower", "size": [8, 8], "has": ["Z", "L*4", "W", "?"]},
  {"name": "The Fighting Barge", "size": [14, 10], "has": ["L*4", "=*4", "j"]},
  {"name": "The Academy Pontoon", "size": [10, 7], "has": ["L*2", "=*2", "e"]},
  {"name": "The Deep Mooring", "size": [10, 7], "has": [">", "L*2", "~*3", "X"]}]},
 "npcs": {
  "Q": {"role": "villager", "name": "Ferrywoman Ilse", "stays": True,
        "line": "Mind the gap between the barges. The water's colder than it looks, and it looks very cold.",
        "lines": ["I've poled this ferry for twenty years. Never once touched the bottom. Nobody has.",
                  "Sometimes the whole market drifts a little, all together. Like something underneath took a breath."],
        "persona": "Ferrywoman Ilse, who poles the ferry from the cliff stair to the market: weathered, unhurried, superstitious about the water and proud of never having fallen in."},
  "M": {"role": "merchant", "name": "Cassiel Vane",
        "line": "Everything that floats, I sell. Everything that sinks, I've already sold.",
        "stock": ["sword_qi_pill", "earthmarrow_pill", "magma_pill", "resin_salve", "moonpetal_tonic", "breakthrough_pill", "terracotta_scale", "emperor_jade_pendant"],
        "persona": "Cassiel Vane, the richest merchant on the Last Water: silver-tongued, ring-heavy, generous to regulars and merciless to everyone else."},
  "G": {"role": "villager", "name": "Brin Saltfoot",
        "line": "Fresh glowfin! Fresh-ish glowfin! Glowfin!",
        "lines": ["The eels glow brighter the deeper you fish. Down past the moorings they glow like lanterns. Nobody fishes down there twice.",
                  "My granda said this lake was the sea once. All of it. And the sea's not gone, it's just -- sleeping somewhere."],
        "persona": "Brin Saltfoot, a loud, sunburnt-looking fishmonger who has never seen the sun, sells glowfin eels from a barrel, and believes every story his grandfather told him."},
  "I": {"role": "innkeeper", "name": "Mother Orla", "price": 20,
        "line": "A hammock that rocks you to sleep, a bowl of eel broth, and twenty gold. The lake does the rest.",
        "lines": ["Delvers came back up from below the Sword Grave last week. Wouldn't say what they saw. Paid double to sleep with the lamps lit.",
                  "If you hear singing from under the water, don't answer it. That's all. Just don't.",
                  "There's a shrine under the Net-Menders' Deck. Sank before my time. The menders still leave it a fish every morning."],
        "persona": "Mother Orla, keeper of the Drifting Lantern inn: vast, warm, unshockable, who has fed three generations of delvers and buried more of them than she'll say."},
  "N": {"role": "villager", "name": "Corin Ashwake",
        "line": "Sit, if you like. I'm writing the lake a poem. It hasn't answered yet.",
        "lines": ["I came down to find the edge of the world. It turns out the edge is wet.",
                  "If you're going deeper, I'd come. Someone should write down what's down there before it eats us."],
        "persona": "Corin Ashwake, a wandering poet-cultivator with ink-stained fingers and a light sword he barely uses: curious, gentle, braver than he looks, keeping a journal of every wonder below the earth -- he would gladly travel with someone who keeps going down."},
  "F": {"role": "smith", "name": "Haldor Rivet",
        "line": "Forging on a raft keeps you honest. Drop a hammer here and it's gone for good.",
        "persona": "Haldor Rivet, smith of the Smithy Raft: one-eyed, careful, and obsessed with grave steel since the first piece came up from the Sword Grave."},
  "A": {"role": "alchemist", "name": "Wren of the Salt-Pills",
        "line": "Salt from the Last Water draws poison out of anything. Even pills. Especially pills.",
        "persona": "Wren of the Salt-Pills, an alchemist who brews with lake salt: precise, cool, faintly amused by everyone."},
  "B": {"role": "guild", "guild": "blacksmiths", "name": "Forgewarden Hask",
        "line": "The Blacksmiths' Guild keeps a hall wherever there's fire. Even on water.",
        "persona": "Forgewarden Hask of the Blacksmiths' Guild: gruff, exacting, and secretly delighted by good work."},
  "C": {"role": "guild", "guild": "alchemists", "name": "Adept Mirelle",
        "line": "The Circle's pontoon is the quiet one. We prefer our explosions planned.",
        "persona": "Adept Mirelle of the Alchemists' Circle: soft-spoken, ambitious, and keenly interested in anything brought up from the deep."},
  "E": {"role": "guild", "guild": "healers", "name": "Brother Tamsel",
        "line": "The Healers' House floats too. We go where the hurt is.",
        "persona": "Brother Tamsel of the Healers' House: young, earnest, tireless, and much braver about blood than about water."},
  "D": {"role": "guild", "guild": "adventurers", "name": "Captain Vey",
        "line": "The Lodge pays for what you clear below. And more for what you bring back alive.",
        "persona": "Captain Vey of the Adventurers' Lodge: scarred, dry, counts the delvers out and counts them back in."},
  "U": {"role": "guild", "guild": "gatherers", "name": "Netmaster Joss",
        "line": "Ore, herb, fish or feather -- the Hall buys it all and asks no questions.",
        "persona": "Netmaster Joss of the Gatherers' Hall: cheerful, sharp, and the best fisher on the Last Water."},
  "O": {"role": "villager", "name": "Old Mender Pell",
        "line": "Every morning I leave the shrine a fish. Every morning the fish is gone.",
        "lines": ["There's a seam in the deck boards by the water where the nets never tangle. That's where the old shrine went down.",
                  "Lantern-light doesn't reach the bottom of this lake. Something down there makes its own."],
        "persona": "Old Mender Pell, who has mended nets on the same deck for fifty years and speaks to the lake like an old friend."},
  "K": {"role": "villager", "name": "Lanternwright Agna",
        "line": "Every lantern on the Last Water passed through my hands. Want one? It'll outlast you.",
        "lines": ["A lantern lit from the Charter flame never goes out on its own. Only when its barge goes down.",
                  "I made one for the Lamp Tower that burns blue. Sabine won't use it. Says the blue ones draw things up from below."],
        "persona": "Lanternwright Agna, who makes every lantern in Lanternmere: blunt, funny, burn-scarred hands, and fiercely proud of her craft."},
  "j": {"role": "tournament", "name": "Ringmaster Kesk", "tier": 10,
        "line": "On the Fighting Barge the ring floats -- lose your footing and you're in the lake. Three bouts. Bring your best.",
        "persona": "Ringmaster Kesk, who runs the Fighting Barge: thin, sharp-eyed, fair to a fault, keeps a ledger of every bout ever fought on the Last Water."},
  "e": {"role": "academy", "name": "Proctor Ilvane",
        "line": "The Academy keeps a pontoon here for its disciples below the Sword Grave. Rank trials, the library, field tasks.",
        "persona": "Proctor Ilvane of the Lotus Ascent Academy: young for a proctor, ambitious, kind to disciples who work and merciless to those who don't."},
  "W": {"role": "villager", "name": "Lampkeeper Sabine", "stays": True,
        "line": "The Lamp Tower is the only light the delvers can see from below. As long as it burns, they find their way home.",
        "lines": ["I keep a count of every delver who passes the Deep Mooring. I keep another count of the ones who come back."],
        "persona": "Lampkeeper Sabine, who tends the Lamp Tower: solemn, devoted, keeps two tallies on her wall and will not say what the gap between them means."},
  "X": {"role": "villager", "name": "Mooring-Guard Dace", "stays": True,
        "line": "Below the Deep Mooring the stair goes down into the dark. Nobody's mapped what's under the Sword Grave. Yet.",
        "persona": "Mooring-Guard Dace, who watches the stair down from the Deep Mooring: bored, brave, and desperate for someone to tell him what's down there."}},
 "chests": {
  "V": {"loot": {"sapphire_shard": [2, 3], "glowfin_eel": [2, 4], "gold": [80, 140]}, "note": "a drowned offering chest, barnacled shut"},
  "J": {"loot": {"breakthrough_pill": [1, 1], "moonpetal": [2, 4]}, "note": "the shrine-keepers' last tithe", "hidden": True}},
 "lore": {
  "R": {"title": "Carved Into the Cliff Stair",
        "text": "WE FOLLOWED THE WATER DOWN. Under it, smaller, in another hand: the water was here first. "
                "It is older than the stone around it. It remembers being a sea."},
  "Y": {"title": "The Lantern Charter",
        "text": "Here the barge-folk bound their boats together and swore: no barge sinks alone. Every lantern on the "
                "Last Water is lit from this square's flame, and every new one is a promise to the others."},
  "S": {"title": "-", "text": "-"}},
 "riddles": {"?": {"title": "The Lamp Tower's Question",
   "question": "The more of me there is, the less you see. I fill every hold and every sky below the earth. A single flame defeats me. What am I?",
   "options": ["Water", "Darkness", "Silence"], "answer": 1,
   "reward": {"items": {"sword_qi_pill": 1, "glowfin_eel": 2}, "qi": 400}}},
 "exits": {"<": {"to": "floor9", "arrive": ">", "label": "Up to the Sword Grave", "down": False},
           ">": {"to": "floor11", "arrive": "<", "label": "Down into the dark"}},
}
# the sunken shrine's stone (V is its chest; the stone is "u")
LEVEL["lore"].pop("S")
LEVEL["lore"]["u"] = {"title": "What the Shrine Remembers",
  "text": "Barnacles over the words, but the words are still there: A great one swam here when this was a sea. "
          "When the sea went away she went with it, upward, to sleep until it returns. Keep the water. Keep it for her."}
LEVEL["layout"]["rooms"][10]["has"].append("u")


def main(homeai_dir):
    sys.path.insert(0, homeai_dir)
    import godot_levels as GL
    text, notes = GL.normalize_text(json.dumps(LEVEL), "floor10.json")
    r = GL.validate_text(text, GAME, "floor10.json")
    print("ok", r["ok"], r["errors"])
    print("notes", notes)
    print("warnings", r["warnings"])
    print("settlement notes", GL.richness_notes(r["summary"], "settlement"))
    if r["ok"]:
        with open(os.path.join(GAME, "levels", "floor10.json"), "w", encoding="utf-8") as f:
            f.write(text)
        print("\n".join(json.loads(text)["map"]))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(GAME, "..", "homeai"))
