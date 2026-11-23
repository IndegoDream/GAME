#!/usr/bin/env python3
"""2026-11-03: side quests for the Lands (data/sidequests.json). ADDS ~70 quests (7 per region), idempotent, backup .bak-lands.
Goals used are the ones the quest system already checks anywhere: gather (item count), event (kill/chest/secret/lore_read/parry/elite_kill
with an optional "where": the region's level id) and talk (pinned with giver_at). Run from the project root."""
import json, os, shutil, sys

def load(p): return json.load(open(p))
def save(p, d): json.dump(d, open(p, "w"), indent=1, ensure_ascii=False)

# region id: dict(giver, depth realm gate, mats, foes, boss, flavour)
REG = {
 "whisperwood": dict(name="Whisperwood", giver="Warden Isolde", realm=0, herb=("glowcap", "glowcap"), ore=("heartwood", "heartwood"), gem=("old_amber", "old amber"), small=("whisper_wolf", "whisper-wolves"), brute=("moss_ogre", "moss ogres"), boss=("elder_treant", "the Elder Treant"), gold=90,
    voice="the warden's low, patient voice", place="the old wood", skill="herbalism", thing="a blaze-marked tree"),
 "mistfen": dict(name="Mistfen", giver="Ferryman Oss", realm=1, herb=("bog_lotus", "bog lotus"), ore=("peat_core", "peat cores"), gem=("drowned_pearl", "drowned pearls"), small=("bog_wraith", "bog wraiths"), brute=("mire_hulk", "mire hulks"), boss=("hag_of_the_fen", "the Hag of the Fen"), gold=130,
    voice="the ferryman's dry drawl", place="the fen", skill="herbalism", thing="a pale light over the water"),
 "bonefields": dict(name="the Bonefields", giver="Gravewalker Hesk", realm=1, herb=("grave_bloom", "grave bloom"), ore=("battle_iron", "battle iron"), gem=("war_standard", "torn war standards"), small=("restless_soldier", "restless soldiers"), brute=("grave_knight", "grave knights"), boss=("general_of_the_fallen", "the General of the Fallen"), gold=150,
    voice="the gravewalker's flat, kind voice", place="the field", skill="mining", thing="a planted banner"),
 "jadehill": dict(name="Jadehill Terraces", giver="Rice-Factor Lin", realm=3, herb=("cloud_rice", "cloud rice"), ore=("terrace_jade", "terrace jade"), gem=("monkey_charm", "monkey charms"), small=("monkey_bandit", "monkey bandits"), brute=("terrace_guardian", "terrace guardians"), boss=("jade_hermit", "the Jade Hermit"), gold=260,
    voice="the factor's quick, friendly patter", place="the terraces", skill="herbalism", thing="a tended terrace wall"),
 "sunken_mere": dict(name="the Sunken Mere", giver="Diver Maru", realm=3, herb=("kelp_silk", "kelp silk"), ore=("serpent_scale", "serpent scales"), gem=("pearl_oyster", "mere pearls"), small=("drowned_one", "drowned ones"), brute=("kelp_horror", "kelp horrors"), boss=("mere_matriarch", "the Mere Matriarch"), gold=300,
    voice="the diver's wry, sunburnt voice", place="the mere", skill="fishing", thing="a rooftop above the water"),
 "stormcliffs": dict(name="the Stormcliffs", giver="Stormsmith Brae", realm=4, herb=("sky_lichen", "sky lichen"), ore=("thunder_iron", "thunder iron"), gem=("roc_quill", "roc quills"), small=("cliff_roc", "cliff rocs"), brute=("thunder_ram", "thunder rams"), boss=("storm_lord", "the Storm Lord"), gold=400,
    voice="the stormsmith's booming laugh", place="the cliffs", skill="smithing", thing="a lightning-struck stone"),
 "emberwaste": dict(name="the Emberwaste", giver="Cinder-Priest Vahl", realm=4, herb=("ash_blossom", "ash blossom"), ore=("firestone", "cinderstone"), gem=("magma_crab_shell", "magma-crab shells"), small=("cinder_imp_pack", "cinder imps"), brute=("ash_drake", "ash drakes"), boss=("caldera_tyrant", "the Caldera Tyrant"), gold=520,
    voice="the priest's dry, unhurried voice", place="the caldera", skill="smithing", thing="a shrine of ash"),
 "frostmere": dict(name="Frostmere", giver="Ice-Fisher Torvald", realm=5, herb=("frost_lotus", "frost lotus"), ore=("rime_crystal", "rime crystal"), gem=("snow_lynx_pelt", "snow-lynx pelts"), small=("ice_wight", "ice wights"), brute=("wendigo", "wendigos"), boss=("glacier_empress", "the Glacier Empress"), gold=640,
    voice="the ice-fisher's quiet murmur", place="the lake", skill="fishing", thing="a hole cut in the ice"),
 "sandglass": dict(name="the Sandglass Dunes", giver="Hourkeeper Isra", realm=5, herb=("desert_rose", "desert rose"), ore=("hourglass_sand", "hourglass sand"), gem=("sun_scarab", "sun scarabs"), small=("dune_scorpion", "dune scorpions"), brute=("sand_giant", "sand giants"), boss=("pharaoh_of_hours", "the Pharaoh of Hours"), gold=780,
    voice="the hourkeeper's amused, slow voice", place="the dunes", skill="herbalism", thing="a half-buried slab"),
 "blighted_wood": dict(name="the Blighted Deep Wood", giver="Last Warden Ysolde", realm=7, herb=("blight_bloom", "blight bloom"), ore=("warped_heartwood", "warped heartwood"), gem=("corrupted_antler", "corrupted antlers"), small=("spore_wraith", "spore wraiths"), brute=("wire_treant", "wire treants"), boss=("root_king", "the Root King"), gold=1300,
    voice="the warden's tired, exact voice", place="the blight", skill="herbalism", thing="a tree grown round a machine"),
}
# the second herb/ore pair is the region's own pickup events; here we use item counts
def mk(rid, r):
    L = "frontier:" + rid
    g = r["giver"]
    h_id, h_nm = r["herb"]; o_id, o_nm = r["ore"]; m_id, m_nm = r["gem"]; s_id, s_nm = r["small"]; b_id, b_nm = r["brute"]; boss_id, boss_nm = r["boss"]
    gold = r["gold"]; realm = r["realm"]; nm = r["name"]
    def ev(kind, count, **kw):
        e = {"kind": kind, "count": count, "where": L}
        if kw: e["match"] = kw
        return {"event": e}
    def q(suffix, name, kind, pitch, stages, ending, after=None):
        d = {"id": "land_%s_%s" % (rid, suffix), "kind": kind, "name": name, "giver": g, "giver_at": L, "place": L, "unlock": {"floor": 0, "realm": realm},
             "pitch": pitch, "stages": stages, "endings": {"default": ending}, "land": True}
        if after: d["unlock"]["after"] = "land_%s_%s" % (rid, after)
        return d
    def end(say, gold_mult=1.0, items=None, insight=0, title=None, skill=None, standing=None):
        rw = {"gold": int(gold * gold_mult), "qi_kills": int(15 * gold_mult) + 10}
        if items: rw["items"] = items
        if insight: rw["insight"] = insight
        if title: rw["title"] = title
        if skill: rw["skill_xp"] = {skill: int(120 * gold_mult) + 60}
        if standing: rw["standing"] = standing
        return {"say": say, "reward": rw}
    tk = {"log": "Return to %s" % g, "goal": {"talk": g, "where": L}, "say": ""}
    out = []
    out.append(q("gather", "First Hands in %s" % nm.title() if nm[0] != "t" else "First Hands in %s" % nm.title(), "gathering",
        "\"%s. Before I trust you with anything real, show me you can work this ground. Bring %s and %s, and we'll talk.\"" % (r["voice"].capitalize(), h_nm, o_nm),
        [{"log": "Gather 6 %s" % h_nm, "goal": {"gather": {"item": h_id, "count": 6}}, "say": ""}, {"log": "Gather 4 %s" % o_nm, "goal": {"gather": {"item": o_id, "count": 4}}, "say": ""}, tk],
        end("A nod, and a coin pouch. \"Good hands. There's more to do, if you want it.\"", 0.6, skill=r["skill"], standing={"eliet": 5})))
    out.append(q("thin", "Thin the %s" % s_nm.title(), "hunting",
        "\"They have grown bold. If you can bring down a dozen of the %s, the paths will be passable again.\"" % s_nm,
        [{"log": "Defeat 12 %s in %s" % (s_nm, nm), "goal": ev("kill", 12, type=s_id), "say": ""}, tk],
        end("\"Quiet again. For a day or two.\" A good payment, counted out slowly.", 0.9, skill=r["skill"]), after="gather"))
    out.append(q("brute", "The Big Ones", "hunting",
        "\"The %s are the real trouble. Five of them, and the rest will think twice.\"" % b_nm,
        [{"log": "Defeat 5 %s in %s" % (b_nm, nm), "goal": ev("kill", 5, type=b_id), "say": ""}, tk],
        end("\"I saw it from the ridge. I will not forget it.\"", 1.4, insight=1), after="thin"))
    out.append(q("rare", "Something Rare", "exploration",
        "\"There is a thing I need that only grows here, and only a few of them. Find %s -- three, and I'll make it worth your time.\"" % m_nm,
        [{"log": "Find 3 %s" % m_nm, "goal": {"gather": {"item": m_id, "count": 3}}, "say": ""}, tk],
        end("It is turned over in careful fingers. \"Yes. That's the one.\"", 1.2, items={m_id: 1}, insight=1), after="gather"))
    out.append(q("hidden", "What the Ground Hides", "exploration",
        "\"%s hides things -- and not always in the same place. Open two hidden doors, and a few chests. Then tell me what was inside.\"" % nm.capitalize(),
        [{"log": "Open 2 secret places in %s" % nm, "goal": ev("secret", 2), "say": ""}, {"log": "Open 3 chests in %s" % nm, "goal": ev("chest", 3), "say": ""}, tk],
        end("The giver reads each find in silence, and then smiles for the first time.", 1.2, insight=1), after="gather"))
    out.append(q("lore", "A Story on a Stone", "exploration",
        "\"There's a stone out there with words on it. I can't tell you more -- I can tell you the weather won't let me read it. Will you?\"",
        [{"log": "Read the lore stone in %s" % nm, "goal": ev("lore_read", 1), "say": ""}, tk],
        end("\"Ah. So that's what it says. Thank you.\" It is clear the answer is not entirely happy.", 0.8, insight=2), after="gather"))
    out.append(q("boss", "The Last Word of %s" % nm.title(), "master",
        "\"There's one more thing here that will not be talked down: %s. If you can end it, the whole region will breathe.\"" % boss_nm,
        [{"log": "Defeat %s" % boss_nm, "goal": ev("kill", 1, type=boss_id), "say": ""}, tk],
        end("\"It's done. I did not think I'd see it.\" A long silence, and then an offering that is not small.", 2.5, insight=3, title="Friend of %s" % nm.title(), standing={"eliet": 15}), after="brute"))
    return out

def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    p = os.path.join(root, "data/sidequests.json")
    b = p + ".bak-lands"
    if not os.path.exists(b): shutil.copy(p, b)
    s = load(p)
    have = {q["id"] for q in s["quests"]}
    n = 0
    for rid, r in REG.items():
        for q in mk(rid, r):
            if q["id"] not in have:
                s["quests"].append(q); n += 1
    save(p, s)
    print("added %d side quests (%d total)" % (n, len(s["quests"])))
main()
