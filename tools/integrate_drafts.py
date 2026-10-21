"""integrate_drafts.py -- Dev's drafts into the game's valley (data/valley.json).

Dev's writing room (HomeAI godot_writers.py) drafts the world's words into
data/drafts/<brief>.json -- DRAFTS: the game never loads them. This is the
step that takes the good ones and builds them in:

  sects     -> up to six sect seats in the valley, each with its creed, its
               nanite way, its entry trial, its elder, its rival, and its
               three arts turned into real, usable ki arts (engine templates
               chosen by the sect's element; the art keeps Dev's name and
               words)
  towers    -> up to three towers of nine trial floors (Dev's towers first;
               any slot Dev hasn't written yet is filled from TOWERS below,
               so the valley is never missing a tower)

It keeps what's already integrated (a sect stays in the slot it was given)
and only adds. Run it from the game folder:

    python3 tools/integrate_drafts.py            (writes data/valley.json)
    python3 tools/integrate_drafts.py --check    (prints what it would do)
"""
import json
import re
import sys
from pathlib import Path

GAME = Path(__file__).resolve().parent.parent
OUT = GAME / "data" / "valley.json"
DRAFTS = GAME / "data" / "drafts"
MAX_SECTS = 6
MAX_TOWERS = 3

# the engine's art templates, by family and element (Game.gd ART_TEMPLATES)
STRIKE_FOR = {"fire": "collapsing_palm", "metal": "severing_finger", "earth": "qi_burst", "water": "severing_finger", "wood": "qi_burst"}
STEP_FOR = {"fire": "hollow_step", "metal": "hollow_step", "earth": "wind_step", "water": "wind_step", "wood": "cloud_ladder"}
GUARD_FOR = {"fire": "returning_tide", "metal": "iron_shell", "earth": "iron_shell", "water": "returning_tide", "wood": "returning_tide"}
TRIAL_FOR = {"metal": {"kind": "combat", "need": 4, "seconds": 75}, "fire": {"kind": "combat", "need": 5, "seconds": 75},
             "earth": {"kind": "endurance", "seconds": 60}, "water": {"kind": "stillness", "seconds": 120},
             "wood": {"kind": "stillness", "seconds": 150}}
DISCIPLE_NAMES = ["Hu", "Lan", "Mei", "Shen", "Bao", "Ren", "Qiu", "Tao", "Yan", "Zhi", "Ping", "Wen"]

# Claude's towers -- used only for slots Dev hasn't written yet
TOWERS = [
    {"name": "The Stair of Patient Stone", "stands": "south of the river, a squat grey tower half swallowed by moss, an hour's walk from Eliet",
     "legend": "The first cultivators of the valley built it to test their children: nine rooms, each harder than the last, and a bell at the top that only rings for someone who has climbed every stair. Nobody remembers who last rang it. The moss on the bell says it has been a long time.",
     "floors": [
        {"name": "The Threshold Room", "kind": "combat", "trial": "Goblins have made a nest of the first room. Clear them out; the stair beyond will not open while they squat on it."},
        {"name": "The Five Pillars", "kind": "puzzle", "trial": "Five pillars, five elements. Wake them in the order the world makes things: wood feeds fire, fire makes earth, earth bears metal, metal gathers water."},
        {"name": "The Hall of Old Bones", "kind": "combat", "trial": "Someone was buried here who did not want to stay buried. Put them back."},
        {"name": "The Long Breath", "kind": "endurance", "trial": "The room fills with things that want you gone. Hold your ground until the stone remembers you."},
        {"name": "The Teacher's Question", "kind": "insight", "trial": "A carved face asks you one question about the way of qi. Answer it truly."},
        {"name": "The Flooded Stair", "kind": "combat", "trial": "Water seeps in from the river and brings drowned things with it."},
        {"name": "The Overcoming Pillars", "kind": "puzzle", "trial": "The pillars again -- but now in the order things defeat each other: water quenches fire, fire melts metal, metal cuts wood, wood splits earth, earth dams water."},
        {"name": "The Narrowing Room", "kind": "endurance", "trial": "The walls press close. So do the things that live in them. Last."},
        {"name": "The Bell Chamber", "kind": "combat", "trial": "The tower's guardian waits under the bell. It was a student once."}],
     "summit": "The bell is green with age, and when you strike it the sound goes out across the whole valley. Somewhere far off, someone looks up.",
     "look": "barrows", "tier": 1, "realm": 0},
    {"name": "Hollowwind Spire", "stands": "on the western ridge above the river, a white spire that whistles when the wind is high",
     "legend": "The Spire was a nanite observatory before the sects came: its rooms still hum with machines that watch the sky. The sects use it now as a proving ground. They say the wind at the top carries the voices of everyone who fell on the way.",
     "floors": [
        {"name": "The Listening Gallery", "kind": "combat", "trial": "The Spire's old sentinels still walk their rounds. They do not know their masters are gone."},
        {"name": "The Orrery Room", "kind": "puzzle", "trial": "The great orrery is jammed. Set its five elemental spheres turning in the order of creation."},
        {"name": "The Wind Corridor", "kind": "endurance", "trial": "Gusts and the things that ride them. Keep your feet."},
        {"name": "The Archivist's Riddle", "kind": "insight", "trial": "A cracked machine asks you a question. It has been waiting a long time for a right answer."},
        {"name": "The Broken Telescope", "kind": "combat", "trial": "Something nests in the lens housing. It doesn't like visitors."},
        {"name": "The Reversed Orrery", "kind": "puzzle", "trial": "The second orrery runs backwards: wake the spheres in the order of overcoming."},
        {"name": "The Storm Landing", "kind": "endurance", "trial": "The storm comes in through the open windows. So does everything it carries."},
        {"name": "The Watcher's Question", "kind": "insight", "trial": "The Spire's last machine asks whether you understand what you're climbing toward."},
        {"name": "The Whistling Crown", "kind": "combat", "trial": "At the top, the wind takes shape. Defeat it and the Spire falls silent for the first time in years."}],
     "summit": "From the crown you can see every sect in the valley, and the roof of Eliet, small as a coin. The wind drops. The Spire is listening to you now.",
     "look": "cloudruins", "tier": 2, "realm": 2},
    {"name": "The Nine-Bell Pagoda", "stands": "at the head of the valley under the northern peaks, red lacquer gone black with age",
     "legend": "Nine roofs, nine bells, nine trials, and at the top a seat where, the sects say, the first Immortal of the valley sat down to rest and never stood up. Every bell rung is a breath he didn't take. The sects send only their strongest; most come back down without ringing more than three.",
     "floors": [
        {"name": "The First Bell", "kind": "combat", "trial": "The pagoda's keepers are clay and memory. They fight like the soldiers they were made to be."},
        {"name": "The Second Bell", "kind": "endurance", "trial": "The bell rings by itself, and every ring brings something new through the doors."},
        {"name": "The Third Bell", "kind": "puzzle", "trial": "Nine bells hang in five colours. Ring the elements in the order of creation, or the bells ring you."},
        {"name": "The Fourth Bell", "kind": "insight", "trial": "A voice asks what you have learned. It knows if you're lying."},
        {"name": "The Fifth Bell", "kind": "combat", "trial": "The Immortal's honour guard. They have been waiting to be tested for a very long time."},
        {"name": "The Sixth Bell", "kind": "puzzle", "trial": "The colours again, in the order of overcoming. The pagoda doesn't forgive a wrong note."},
        {"name": "The Seventh Bell", "kind": "endurance", "trial": "The floor tilts, the walls breathe, the guardians come in waves. Hold."},
        {"name": "The Eighth Bell", "kind": "insight", "trial": "The last question before the seat. What will you do with what you find?"},
        {"name": "The Ninth Bell", "kind": "combat", "trial": "The seat at the top is not empty."}],
     "summit": "The Immortal's seat is warm. When you sit, for one long breath you can feel every root of the valley and every stone under it -- and then it's only a chair again, and you are someone who has climbed the Nine-Bell Pagoda.",
     "look": "sanctum", "tier": 3, "realm": 4},
]
TIER_REALM = {1: 0, 2: 2, 3: 4}
TIER_LOOK = {1: "barrows", 2: "cloudruins", 3: "sanctum"}


def slug(s):
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")[:40]


def _read(p, default):
    try:
        return json.loads(Path(p).read_text(encoding="utf-8"))
    except Exception:
        return default


def drafts(brief):
    d = _read(DRAFTS / ("%s.json" % brief), {})
    return d.get("items", []) if isinstance(d, dict) else []


# what Dev's own words say the art does picks the engine template first;
# the element is only the fallback
KEYWORDS = {
    "strike": [("qi_burst", r"\bwaves?\b|burst|shockwave|\bring\b|around|all sides|explo|blast|quake"),
               ("collapsing_palm", r"palm|crush|knock|smash|fist|blow|cleave|break"),
               ("severing_finger", r"beam|thread|needle|pierc|range|distan|torrent|arrow|bolt|lance|spear|strike from afar")],
    "step": [("hollow_step", r"vanish|behind|shadow|blink|unexpected|unseen|appear|teleport"),
             ("cloud_ladder", r"leap|jump|air|climb|float|soar|fly|ascend"),
             ("wind_step", r"dash|swift|rush|dodge|glide|slide|flow|dance|step")],
    "guard": [("returning_tide", r"reflect|return|parry|redirect|counter|turn back|deflect|mirror"),
              ("iron_shell", r"harden|skin|absorb|endure|shield|armou?r|bark|stone|wall|impervious")],
}


def template_for(fam, el, words):
    w = (words or "").lower()
    for tmpl, rx in KEYWORDS[fam]:
        if re.search(rx, w):
            return tmpl
    return {"strike": STRIKE_FOR, "step": STEP_FOR, "guard": GUARD_FOR}[fam][el]


def build_sect(item, slot):
    el = str(item.get("element", "earth")).lower()
    if el not in STRIKE_FOR:
        el = "earth"
    sid = slug(item["name"])
    arts = []
    fam_of = {"attack": "strike", "defence": "guard", "movement": "step"}
    rank_of = {"movement": 1, "defence": 2, "attack": 3}
    seen = set()
    for a in item.get("arts", []):
        kind = str(a.get("kind", "attack")).lower()
        if kind not in fam_of or kind in seen:
            continue
        seen.add(kind)
        fam = fam_of[kind]
        arts.append({"id": "sect_%s_%s" % (sid, fam), "name": a.get("name", kind.title()), "kind": kind, "what": a.get("what", ""),
                     "family": fam, "template": template_for(fam, el, "%s %s" % (a.get("name", ""), a.get("what", ""))), "rank": rank_of[kind]})
    # (a sect missing a kind gets none for it -- never an invented art)
    arts.sort(key=lambda a: a["rank"])
    elder = item.get("elder", {}) if isinstance(item.get("elder"), dict) else {}
    disc = [DISCIPLE_NAMES[(slot * 2) % len(DISCIPLE_NAMES)], DISCIPLE_NAMES[(slot * 2 + 1) % len(DISCIPLE_NAMES)]]
    return {"id": sid, "slot": slot, "by": "Dev", "name": item["name"], "element": el, "seat": item.get("seat", ""),
            "creed": item.get("creed", ""), "nanite_way": item.get("nanite_way", ""), "entry_trial": item.get("entry_trial", ""),
            "trial": TRIAL_FOR[el], "elder": {"name": elder.get("name", "the Elder"), "persona": elder.get("persona", "")},
            "rival": item.get("rival", ""), "arts": arts, "disciples": ["Disciple " + n for n in disc]}


def build_tower(t, slot, by):
    floors = list(t.get("floors", []))[:9]
    # Dev writes three to nine floors of a tower; the rest come from the
    # tower that stood in that slot before (Claude's), floor for floor
    fill = TOWERS[slot]["floors"] if slot < len(TOWERS) else []
    while len(floors) < 9:
        k = len(floors)
        floors.append(dict(fill[k]) if k < len(fill) else {"name": "Floor %d" % (k + 1), "kind": "combat", "trial": "Something waits here."})
    for i, f in enumerate(floors):
        k = str(f.get("kind", "combat")).lower()
        f["kind"] = k if k in ("combat", "puzzle", "endurance", "insight") else "combat"
    floors[8]["kind"] = "combat"            # the summit always has its guardian
    tier = slot + 1
    return {"id": slug(t["name"]), "slot": slot, "by": by, "name": t["name"], "stands": t.get("stands", ""), "legend": t.get("legend", ""),
            "floors": floors, "summit": t.get("summit", ""), "tier": tier, "realm": TIER_REALM[tier],
            "look": t.get("look", TIER_LOOK[tier])}


def integrate(check=False):
    cur = _read(OUT, {})
    sects = list(cur.get("sects", []))
    have = {s["name"].lower() for s in sects}
    for item in drafts("sects"):
        if len(sects) >= MAX_SECTS:
            break
        if not isinstance(item, dict) or not item.get("name") or item["name"].lower() in have:
            continue
        sects.append(build_sect(item, len(sects)))
        have.add(item["name"].lower())
    towers = [t for t in cur.get("towers", []) if t.get("by") == "Dev"]
    for t in drafts("towers"):
        if len(towers) >= MAX_TOWERS:
            break
        if isinstance(t, dict) and t.get("name") and slug(t["name"]) not in {x["id"] for x in towers}:
            towers.append(build_tower(t, len(towers), "Dev"))
    slots = len(towers)
    for i in range(slots, MAX_TOWERS):
        towers.append(build_tower(json.loads(json.dumps(TOWERS[i])), i, "Claude"))
    for i, t in enumerate(towers):          # keep slots in order of tier
        t["slot"] = i
        t["tier"] = i + 1
        t["realm"] = TIER_REALM[i + 1]
        t.setdefault("look", TIER_LOOK[i + 1])
    # landmarks, the nanite codex, rumours: Dev's words as written (checked by
    # his writing room); new ones added, none replaced
    def collect(key, brief, cap):
        have_l = list(cur.get(key, []))
        names = {str(x.get("name", "")).lower() for x in have_l}
        for it in drafts(brief):
            if len(have_l) >= cap:
                break
            if isinstance(it, dict) and it.get("name") and str(it["name"]).lower() not in names:
                have_l.append(dict(it, by="Dev"))
                names.add(str(it["name"]).lower())
        return have_l
    landmarks = collect("landmarks", "landmarks", 12)
    codex = collect("codex", "nanite_codex", 12)
    rumours = collect("rumours", "rumours", 5)
    out = {"note": "The valley around Eliet (Robert, 2026-10-02: 'towers to climb and sects outside of the dungeon -- the dungeon is the primary way to progress but not the only way'). "
                   "Built by tools/integrate_drafts.py from Dev's drafts (data/drafts/) -- sects and towers written by Dev's local model and checked by his writing room; "
                   "any tower slot Dev hasn't written yet is Claude's. Game.gd round-24 block reads this file.",
           "ranks": [["Outer Disciple", 0, 0], ["Inner Disciple", 100, 1], ["Core Disciple", 300, 2], ["Elder's Disciple", 800, 3]],
           "sects": sects, "towers": towers, "landmarks": landmarks, "codex": codex, "rumours": rumours}
    if check:
        print("sects:", [s["name"] for s in sects])
        print("towers:", [(t["name"], t["by"]) for t in towers])
        print("landmarks: %d, codex: %d, rumours: %d" % (len(landmarks), len(codex), len(rumours)))
        return out
    OUT.write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print("wrote %s: %d sects, %d towers (%d by Dev), %d landmarks, %d codex entries, %d rumours" % (
        OUT, len(sects), len(towers), sum(1 for t in towers if t["by"] == "Dev"), len(landmarks), len(codex), len(rumours)))
    return out


if __name__ == "__main__":
    integrate(check="--check" in sys.argv)
