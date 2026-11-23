#!/usr/bin/env python3
"""Writes data/mysteries.json -- the game's mysteries and treasure hunts (2026-11-03).

Robert, 2026-11-03: "more mystery and intrigue -- a treasure hunt, a whodunit, conspiracies, secret societies".
Read by scripts/systems/Quests.gd (_mysteries). Each quest is an ordinary side quest plus:
  find.place / find.near / find.subtle   -- where a clue lies and whether it is marked
  choices[].needs                        -- an accusation you can only make holding the proof
  "clues"                                -- every clue is an item you keep; its text is readable in the bag
Dev: rewrite the words freely (keep ids, items and NPC names). Run: python3 tools/gen/mysteries_gen.py
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "data", "mysteries.json")

clues = {
    # --- The Empty Strongbox (whodunit, Eliet + Shellhaven) ---
    "mc_soot_print": {"name": "Soot Thumbprint", "text": "Fine black soot on the strongbox lid, smelling of camphor. Forge soot is coarse and smells of iron. This is lamp-black -- from a still."},
    "mc_marked_coin": {"name": "Silver Coin in the Ford", "text": "A silver coin stamped with Trader Wen's own mark, the little scale. Dropped in the shallows beside a trail of crushed moon-mint."},
    "mc_lotus_tally": {"name": "Bead-Seller's Tally", "text": "From Shellhaven: one moon-lotus, paid in nine silver, each stamped with a little scale. Signed 'L., of Eliet -- for the child.'"},
    # --- The Founders' Cache (treasure hunt, Eliet -> Floor 1 -> Floor 3) ---
    "tc_verdigris_disc": {"name": "Verdigris Disc", "text": "Green copper, palm-sized. A fox on one face. On the other: 'Where the water leaves Eliet, the old stone keeps the second word.'"},
    "tc_river_stone": {"name": "Carved River-Stone", "text": "'DOWN. The third word waits at the foot of the first stair down -- where every goblin passes and none looks.'"},
    "tc_black_tablet": {"name": "Soot-Black Tablet", "text": "'And the last word waits where the drowned seam's water lies stillest. Bring the disc.'"},
    "tc_founders_box": {"name": "The Founders' Tin Box", "text": "Sealed with wax, a fox pressed into it. A ring in oilcloth, and a note in three hands: 'For whoever listened.'"},
    # --- The Cut Lift Rope (whodunit, Shellhaven) ---
    "mc_rope_end": {"name": "Cut Rope's End", "text": "Cut clean with a hooked blade -- a net-mender's hook, not a knife. Tarred hemp, with a few fish scales caught in the tar."},
    "mc_wet_hook": {"name": "Scrubbed Net-Hook", "text": "Scrubbed, but tar sits in the hinge with a scale or two. Tied to it, a purse heavy with Dagna Ironvent's foundry tokens."},
    # --- The Ninth Lamp (conspiracy, the deep) ---
    "nl_lamp_badge": {"name": "Badge of Nine Rays", "text": "A brass lamp with nine rays. One ray is scratched out, carefully, the way you'd cross out a name."},
    "nl_ferry_ledger": {"name": "Lanternmere Ferry Ledger", "text": "The expedition's year. Nine names crossing down. A year later, eight crossing back up -- each marked with a little lamp. None of them ever reached Eliet."},
    "nl_cipher_wheel": {"name": "Cipher Wheel", "text": "Two bronze rings. Set the lamp to the fox and the letters read: 'WE KEEP THE DOOR SHUT FROM BELOW. LET MO BELIEVE US DEAD.'"},
    # --- The Missing Stags (whodunit, the Lands) ---
    "lc_jade_snare": {"name": "Jade-Wire Snare", "text": "A snare of green wire, too fine to be iron. Jadehill's terrace folk tie their vines with wire like this."},
    "lc_velvet_tally": {"name": "Torn Ledger Page", "text": "From a rice-factor's book: 'antler velvet, twelve sets -- to the Marrow Forge, paid in battle iron.' Twelve new moons; twelve stags."},
    # --- The Cartographer's Last Map (treasure hunt, the Lands) ---
    "lc_map_case": {"name": "Oilskin Map Case", "text": "A drowned cartographer's case. The map is gone; on the lid, scratched: 'Where the standard was planted and never fought for, count three paces east of the truth.'"},
    "lc_brass_rule": {"name": "Brass Rule", "text": "A cartographer's rule, engraved down its length: 'Seven hundred terraces, four hundred tended. The rest keep my second leg of the road.'"},
    "lc_compass_card": {"name": "Compass Card", "text": "A card from inside a compass. On the back: 'Three cuts and a dot. The road is behind you. So is the last of me.'"},
    "lc_last_map": {"name": "The Cartographer's Last Map", "text": "The whole deep, drawn by one hand: every Land, every road, and in the margins, little notes to whoever finds it -- 'go slow here', 'the water lies', 'be kind to the trees'."},
}

uniques = {
    "founders_signet": {"name": "Founders' Signet", "desc": "A plain ring with a fox inside the band. Whoever wears it hears a little more: hidden things show from a step further away, and +5% insight from everything.", "effect": {"loot_luck": 0.05, "insight_mult": 1.05}, "value": 900},
    "cartographers_compass": {"name": "Cartographer's Compass", "desc": "It never points north. It points at whatever you haven't found yet: +6% loot luck, and you see a little further in the dark.", "effect": {"loot_luck": 0.06, "sight": 0.5}, "value": 3200},
    "lamp_of_nine_rays": {"name": "Lamp of Nine Rays", "desc": "The Ninth Lamp's own badge, worn openly. The dark gives a little way: blows land 6% lighter.", "effect": {"damage_taken": 0.94}, "value": 2400},
}

quests = [
    {
        "id": "myst_empty_strongbox", "kind": "mystery", "name": "The Empty Strongbox", "giver": "Trader Wen", "giver_at": "village", "place": "village",
        "unlock": {"floor": 1},
        "pitch": "\"Someone emptied my strongbox last night. Not broken -- opened. Ninety silver, every coin stamped with my mark. I don't want a hanging. I want to know who, and why. Will you look?\"",
        "stages": [
            {"log": "Look over Trader Wen's stall for anything the thief left", "goal": {"find": {"place": "village", "near": "M", "item": "mc_soot_print", "what": "a soot mark on the strongbox", "look": "mark"}},
             "say": "A thumbprint of fine black soot on the lid. It smells of camphor -- lamp-black from a still, not the coarse soot of a forge."},
            {"log": "Ask Smith Hale about the soot", "goal": {"talk": "Smith Hale", "where": "village"},
             "say": "Hale wipes his hands and shows you: coarse as gravel. \"Camphor? Not mine. That's lamp-black -- an alchemist's still. Pell was up at midnight hauling ore for me. Ask him what he saw.\""},
            {"log": "Ask Old Pell what he saw that night", "goal": {"talk": "Old Pell", "where": "village"},
             "say": "\"Midnight? Lin's lamp was lit -- it's always lit -- and someone went down to the ford with a little bundle. Small. Hurrying. I thought it was the wind.\""},
            {"log": "Search the ford where Pell saw someone hurrying", "goal": {"find": {"place": "village", "near": "water", "item": "mc_marked_coin", "what": "something glinting in the shallows", "look": "satchel"}},
             "say": "A silver coin, stamped with Wen's little scale, lying in the shallows. Beside it a trail of crushed moon-mint -- the kind that only grows by the apothecary's beds."},
            {"log": "Ask Apothecary Lin about the moon-mint at the ford", "goal": {"talk": "Apothecary Lin", "where": "village"},
             "say": "Lin goes very still. \"Moon-mint grows by my beds. Anyone could tread it.\" She doesn't look at you. \"Rin has the grey cough again. That's all I'll say.\" Moon-lotus cures the grey cough. Only Shellhaven's bead-sellers carry it."},
            {"log": "Find out what Shellhaven's traders remember (Floor 5)", "goal": {"find": {"floor": 5, "place": "floor5", "near": "M", "item": "mc_lotus_tally", "what": "a bead-seller's tally", "look": "satchel"}},
             "say": "A bead-seller's tally slip, pinned under a stone: one moon-lotus, nine silver, each coin stamped with a little scale. Signed 'L., of Eliet -- for the child.'"},
            {"log": "Tell Trader Wen who emptied his strongbox", "goal": {"talk": "Trader Wen", "where": "village"},
             "say": "Wen folds his arms. \"Well? Who opened my box?\"",
             "choices": [
                 {"text": "Apothecary Lin. She bought moon-lotus for Rin's cough -- here's the tally.", "ending": "truth", "needs": {"mc_lotus_tally": 1}},
                 {"text": "Old Pell. He was up at midnight, and he's always short.", "ending": "pell"},
                 {"text": "A goblin came up the stair. It happens.", "ending": "goblin"},
                 {"text": "Leave it. I'll pay the ninety silver back myself.", "ending": "pay", "needs": {"gold": 90}}]},
        ],
        "endings": {
            "truth": {"say": "Wen reads the tally twice. Then he goes to Lin's door himself. Raised voices, then quiet, then Rin coughing -- and laughing. Wen comes back lighter. \"Nine silver for a child's breath. I'd have given it if she'd asked. She'll work it off in salves.\" Lin presses a little flask into your hand on your way out and says nothing at all.",
                      "reward": {"gold": 120, "insight": 3, "items": {"healing_salve": 3}, "bond": {"Apothecary Lin": 25, "Trader Wen": 15}, "title": "The Village Detective"}},
            "pell": {"say": "Pell doesn't argue. That's the worst of it. Two days later Rin tells you, crying, whose lamp was lit that night. Pell doesn't meet your eyes for a long time.",
                     "reward": {"gold": 40, "bond": {"Old Pell": -20}}},
            "goblin": {"say": "Wen looks at you a long moment. \"A goblin. With a key.\" He doesn't believe you, but he lets it go. Lin, passing, gives you a look that's half thanks and half shame.",
                       "reward": {"insight": 1, "bond": {"Apothecary Lin": 10, "Trader Wen": -10}}},
            "pay": {"say": "You count out ninety silver of your own. Wen takes it, puzzled. Lin finds out -- in a village this size, everyone does -- and Rin's cough is gone by the next market day.",
                    "reward": {"pay": 90, "insight": 4, "bond": {"Apothecary Lin": 30, "Little Rin": 20, "Trader Wen": 10}}},
        },
    },
    {
        "id": "treasure_founders_cache", "kind": "treasure", "name": "The Founders' Cache", "giver": "Elder Mo", "giver_at": "village", "place": "village",
        "unlock": {"floor": 1},
        "pitch": "\"The Founders' Stone says the fountain is listening. My grandfather thought that was a poem. I think it's directions. Ninety years and nobody's looked properly. You're young. Look.\"\n\n(No markers on a treasure hunt: the riddle is the map. Something glints when you're right on top of it.)",
        "stages": [
            {"log": "'The fountain is listening.' Search close around the fountain, low, where the water drips", "goal": {"find": {"place": "village", "near": "fountain", "subtle": True, "item": "tc_verdigris_disc", "what": "a green disc under the fountain's lip", "look": "mark"}},
             "say": "Wedged under the fountain's lip: a green copper disc. A fox on one face. On the other: 'Where the water leaves Eliet, the old stone keeps the second word.'"},
            {"log": "'Where the water leaves Eliet, the old stone keeps the second word.' Follow the stream", "goal": {"find": {"place": "village", "near": "water", "subtle": True, "item": "tc_river_stone", "what": "a carved river-stone", "look": "mark"}},
             "say": "A smooth river-stone in the reeds, carved deep: 'DOWN. The third word waits at the foot of the first stair down -- where every goblin passes and none looks.'"},
            {"log": "'Where every goblin passes and none looks' -- by the way down on Floor 1", "goal": {"find": {"floor": 1, "near": "stairs", "subtle": True, "item": "tc_black_tablet", "what": "a soot-black tablet", "look": "mark"}},
             "say": "Under the grime by the stair down, a tablet black with old soot: 'And the last word waits where the drowned seam's water lies stillest. Bring the disc.'"},
            {"log": "'Where the drowned seam's water lies stillest' -- Floor 3", "goal": {"find": {"floor": 3, "near": "water", "subtle": True, "item": "tc_founders_box", "what": "a wax-sealed tin box", "look": "relic"}},
             "say": "A tin box sealed with wax, the fox pressed into it. The disc fits the lid like a key. Inside: a ring wrapped in oilcloth, and a note in three hands -- 'For whoever listened.'"},
            {"log": "Bring the Founders' box to Elder Mo", "goal": {"talk": "Elder Mo", "where": "village"},
             "say": "Mo turns the ring over and over. \"Three hands. Whoever they were, they knew we'd need someone who listens.\" He closes your fingers round it. \"Keep it. Keep listening.\""},
        ],
        "endings": {"default": {"say": "The Founders' Signet is yours. Somewhere under Eliet, three people who built a village smile at a joke ninety years long.",
                                "reward": {"gold": 150, "insight": 5, "items": {"founders_signet": 1}, "bond": {"Elder Mo": 20}, "title": "One Who Listened"}}},
    },
    {
        "id": "myst_cut_rope", "kind": "mystery", "name": "The Cut Lift Rope", "giver": "Warden Tolle", "giver_at": "floor5", "place": "floor5",
        "unlock": {"floor": 5},
        "pitch": "\"Somebody cut the lift rope at the north shaft. Clean cut, not a fray. If Fen the Porter hadn't been late he'd have been in the cage. Find out who before they try again -- quietly. Shellhaven talks.\"",
        "stages": [
            {"log": "Look at the cut rope by Fen the Porter's lift", "goal": {"find": {"floor": 5, "place": "floor5", "near": "G", "item": "mc_rope_end", "what": "the cut end of the lift rope", "look": "mark"}},
             "say": "Cut clean with a hooked blade -- a net-mender's hook, not a knife. Tarred hemp, a few fish scales stuck in the tar."},
            {"log": "Ask Fen the Porter why he was late", "goal": {"talk": "Fen the Porter", "where": "floor5"},
             "say": "\"Late? I was hauling Mother Kesh's nets. Who uses a hook? Everyone who mends nets. Kesh. Hollin. Me, when I'm paid.\""},
            {"log": "Ask Mother Kesh about her net-hook", "goal": {"talk": "Mother Kesh", "where": "floor5"},
             "say": "\"My hook's on its nail.\" It is. Then, quieter: \"Hollin borrowed it Tuesday. Brought it back wet.\""},
            {"log": "Look around Hollin Brask's place for the borrowed hook", "goal": {"find": {"floor": 5, "place": "floor5", "near": "I", "item": "mc_wet_hook", "what": "a scrubbed net-hook", "look": "satchel"}},
             "say": "A net-hook, scrubbed hard -- but tar sits in the hinge, with a scale or two. Tied to it, a purse heavy with Dagna Ironvent's foundry tokens."},
            {"log": "Ask Dagna Ironvent why Hollin has her tokens", "goal": {"talk": "Dagna Ironvent", "where": "floor5"},
             "say": "\"Hollin? I paid him for -- salvage.\" She stops. \"The north cage hauls Oru's ore. If it's down, mine goes up first. That's all. I never told him to CUT anything.\""},
            {"log": "Tell Warden Tolle who cut the rope", "goal": {"talk": "Warden Tolle", "where": "floor5"},
             "say": "Tolle doesn't look up from his ledger. \"Well?\"",
             "choices": [
                 {"text": "Hollin cut it, for Dagna's tokens. Here's the hook.", "ending": "truth", "needs": {"mc_wet_hook": 1}},
                 {"text": "Dagna Ironvent paid for it. Hollin was only the hand.", "ending": "dagna", "needs": {"mc_wet_hook": 1}},
                 {"text": "Fen staged it to get out of a day's work.", "ending": "fen"}]},
        ],
        "endings": {
            "truth": {"say": "Tolle reads the hook like a letter. Hollin is hauling ore for Oru by nightfall -- for nothing, for a year. Dagna pays for a new rope, steel-cored, and has to look at it every day.",
                      "reward": {"gold": 160, "insight": 3, "bond": {"Warden Tolle": 20, "Fen the Porter": 20}, "title": "Shellhaven's Quiet Eye"}},
            "dagna": {"say": "Tolle nods slowly. \"The one who pays is the one who cuts.\" Dagna loses her lift rights for a season. Hollin keeps his tokens and his head down, and you're never sure he learned anything.",
                      "reward": {"gold": 120, "insight": 2, "bond": {"Warden Tolle": 10}}},
            "fen": {"say": "Fen is fined a week's pay. A month later the north rope is cut again -- and this time the cage was full.",
                    "reward": {"gold": 30, "bond": {"Fen the Porter": -25}}},
        },
    },
    {
        "id": "myst_ninth_lamp", "kind": "mystery", "name": "The Ninth Lamp", "giver": "Captain Rhee", "giver_at": "village", "place": "village",
        "unlock": {"floor": 7},
        "pitch": "\"The Lantern Stone says nine went down with Mo and only Mo came back. Lodge books say otherwise. Someone paid for eight lamps to be lit on the eighth night of every winter -- and they still are. I'd like to know who's paying.\"",
        "stages": [
            {"log": "Ask Elder Mo about the first expedition", "goal": {"talk": "Elder Mo", "where": "village"},
             "say": "Mo's face closes like a door. \"Nine went down. One came back. That's all the stone needs to say.\" His hand goes to his coat, where something hangs on a cord."},
            {"log": "Look for what the expedition left on Floor 7", "goal": {"find": {"floor": 7, "item": "nl_lamp_badge", "what": "a brass badge", "look": "satchel"}},
             "say": "A brass badge: a lamp with nine rays. One ray is scratched out -- carefully, the way you'd cross out a name."},
            {"log": "Lanternmere's ferry has crossed the water for a hundred years. Look for its ledger (Floor 10)", "goal": {"find": {"floor": 10, "place": "floor10", "near": "Q", "item": "nl_ferry_ledger", "what": "an old ferry ledger", "look": "satchel"}},
             "say": "The expedition's year. Nine names crossing down. A year later, eight crossing back up, each with a little lamp drawn beside it. None of them ever reached Eliet."},
            {"log": "Ask Ferrywoman Ilse about the eight who came back up", "goal": {"talk": "Ferrywoman Ilse", "where": "floor10"},
             "say": "\"My grandmother rowed them. Lamps on their coats. They paid her to forget their faces.\" She points down, not up. \"They went somewhere that isn't Eliet.\""},
            {"log": "Look for whatever the Lamp keeps on Floor 12", "goal": {"find": {"floor": 12, "item": "nl_cipher_wheel", "what": "a bronze cipher wheel", "look": "relic"}},
             "say": "Two bronze rings. Set the lamp against the fox and the letters read: 'WE KEEP THE DOOR SHUT FROM BELOW. LET MO BELIEVE US DEAD.'"},
            {"log": "The Lamp's warden walks Floor 14. Make it talk -- or make it stop", "goal": {"hunt": {"floor": 14, "name": "Warden of the Ninth Lamp", "type": "strongest", "hp_mult": 4.0}},
             "say": "The warden falls and its mask splits: under it, a face older than it should be, and a lamp tattoo with eight rays. \"Tell Mo,\" it says, \"the door is still shut.\""},
            {"log": "Decide what Elder Mo should know", "goal": {"talk": "Elder Mo", "where": "village"},
             "say": "Mo is waiting at the Lantern Stone, as if he knew you'd come. \"You found them.\" It isn't a question.",
             "choices": [
                 {"text": "Tell him the truth: the eight are alive below, holding a door shut.", "ending": "tell"},
                 {"text": "Keep their secret. Burn the ledger in front of him.", "ending": "keep", "needs": {"nl_ferry_ledger": 1}},
                 {"text": "Pin the nine-rayed badge on your own coat, and say nothing.", "ending": "join", "needs": {"nl_lamp_badge": 1, "nl_cipher_wheel": 1}}]},
        ],
        "endings": {
            "tell": {"say": "Mo sits down on the stone. For a long time he just breathes. \"Eight lamps,\" he says at last. \"I lit them every winter for dead men.\" He laughs, and it breaks in the middle. \"I'll keep lighting them.\"",
                     "reward": {"gold": 400, "insight": 6, "bond": {"Elder Mo": 30}}},
            "keep": {"say": "The ledger curls in the fire. Mo watches it burn and doesn't ask what it said. Somewhere far below, a door stays shut, and the eight who hold it will never know you were there.",
                     "reward": {"gold": 250, "insight": 8, "title": "Keeper of the Lamp's Secret"}},
            "join": {"say": "Mo sees the badge and goes white, then very quiet. \"Nine rays,\" he says. \"They scratched mine out.\" He touches the empty place where his own ray should be. \"Then it's yours now. Hold the door.\"",
                     "reward": {"gold": 300, "insight": 10, "items": {"lamp_of_nine_rays": 1}, "title": "Of the Ninth Lamp", "bond": {"Elder Mo": 15}}},
        },
    },
    {
        "id": "myst_missing_stags", "kind": "mystery", "name": "The Missing Stags", "giver": "Warden Isolde", "giver_at": "frontier:whisperwood", "place": "frontier:whisperwood",
        "unlock": {"floor": 9},
        "pitch": "\"I count the stags at every new moon. Every new moon for a year there has been one fewer. The wolves are fed. The wood is quiet about it, which is how I know someone is lying to it. Find out who.\"",
        "stages": [
            {"log": "Look around Whisperwood's paths for whatever takes the stags", "goal": {"find": {"place": "frontier:whisperwood", "near": "spawn", "item": "lc_jade_snare", "what": "a snare in the ferns", "look": "mark"}},
             "say": "A snare of fine green wire, staked where the stags come down to drink. Not iron. Jade wire -- the kind Jadehill's terrace folk tie their vines with."},
            {"log": "Show the snare to Mossmother Ketta", "goal": {"talk": "Mossmother Ketta", "where": "frontier:whisperwood"},
             "say": "Ketta sniffs it. \"Jade wire, yes. And this --\" a smear on the loop \"-- is antler velvet. Nobody snares a stag for meat with wire this fine. They want the velvet. Rice-factors buy velvet; Jadehill grows rich on it.\""},
            {"log": "Find out who buys antler velvet in the Jadehill Terraces", "goal": {"find": {"place": "frontier:jadehill", "near": "npc:Rice-Factor Lin", "item": "lc_velvet_tally", "what": "a torn ledger page", "look": "satchel"}},
             "say": "A page torn from a rice-factor's book, blown into the terrace channel: 'antler velvet, twelve sets -- to the Marrow Forge, paid in battle iron.' Twelve new moons. Twelve stags."},
            {"log": "Ask Gravewalker Hesk what the Marrow Forge wants with velvet", "goal": {"talk": "Gravewalker Hesk", "where": "frontier:bonefields"},
             "say": "Hesk doesn't look up from the graves. \"Velvet goes in bone-steel, to make it bend before it breaks. The Forge pays in battle iron from this field. The dead don't need it. Somebody sells it on, and somebody snares your stags to pay for it.\""},
            {"log": "Tell Warden Isolde who is taking the stags", "goal": {"talk": "Warden Isolde", "where": "frontier:whisperwood"},
             "say": "Isolde waits with her hand on a wolf's ruff. \"Well?\"",
             "choices": [
                 {"text": "Rice-Factor Lin buys the velvet and sells it to the Marrow Forge. Here's her page.", "ending": "truth", "needs": {"lc_velvet_tally": 1}},
                 {"text": "It's the wolves after all.", "ending": "wolves"},
                 {"text": "Mossmother Ketta -- she knew far too much about velvet.", "ending": "ketta"}]},
        ],
        "endings": {
            "truth": {"say": "Isolde walks to Jadehill herself. The snares stop. At the next new moon the count is right, and at the one after there is a fawn that wasn't there before. She tells you its name and makes you promise not to tell anyone.",
                      "reward": {"gold": 520, "insight": 6, "bond": {"Warden Isolde": 25, "Mossmother Ketta": 10}, "title": "Friend of the Whisperwood"}},
            "wolves": {"say": "Isolde looks at you, then at the wolf at her knee, and doesn't say anything. The count keeps falling. One day the wolf isn't at her knee any more.",
                       "reward": {"gold": 80, "bond": {"Warden Isolde": -20}}},
            "ketta": {"say": "Ketta packs her hollow log and moves deeper in, where no one will find her. The count keeps falling. Some things you can't take back.",
                      "reward": {"gold": 60, "bond": {"Mossmother Ketta": -30, "Warden Isolde": -10}}},
        },
    },
    {
        "id": "treasure_cartographer", "kind": "treasure", "name": "The Cartographer's Last Map", "giver": "Ferryman Oss", "giver_at": "frontier:mistfen", "place": "frontier:mistfen",
        "unlock": {"floor": 11},
        "pitch": "\"There was a woman who mapped the whole deep. She drowned in my fen with her map case on her back. Thirty years I've poled past the place. I'm too old to dive. You aren't.\"\n\n(No markers on a treasure hunt: the riddle is the map. Something glints when you're right on top of it.)",
        "stages": [
            {"log": "Search the reeds below Ferryman Oss's landing, where the cartographer drowned", "goal": {"find": {"place": "frontier:mistfen", "near": "npc:Ferryman Oss", "subtle": True, "item": "lc_map_case", "what": "an oilskin map case", "look": "satchel"}},
             "say": "Tangled in the reeds: an oilskin map case. Empty. On the lid, scratched with a pin: 'Where the standard was planted and never fought for, count three paces east of the truth.'"},
            {"log": "'Where the standard was planted and never fought for' -- the Bonefields' carved words", "goal": {"find": {"place": "frontier:bonefields", "near": "lore", "subtle": True, "item": "lc_brass_rule", "what": "a brass rule", "look": "mark"}},
             "say": "Three paces east of the standard, half-buried: a brass rule. Engraved down its length: 'Seven hundred terraces, four hundred tended. The rest keep my second leg of the road.'"},
            {"log": "'Seven hundred terraces, four hundred tended' -- the tally on Jadehill's wall", "goal": {"find": {"place": "frontier:jadehill", "near": "lore", "subtle": True, "item": "lc_compass_card", "what": "a compass card", "look": "mark"}},
             "say": "Pressed into the mortar beside the tally: a compass card. On the back: 'Three cuts and a dot. The road is behind you. So is the last of me.'"},
            {"log": "'Three cuts and a dot' -- the blaze on Whisperwood's tree", "goal": {"find": {"place": "frontier:whisperwood", "near": "lore", "subtle": True, "item": "lc_last_map", "what": "a waxed tube in the roots", "look": "relic"}},
             "say": "In the roots under the blaze: a waxed tube. Inside, the whole deep, drawn by one hand -- and, rolled inside the map, her compass."},
            {"log": "Bring the cartographer's map to Ferryman Oss", "goal": {"talk": "Ferryman Oss", "where": "frontier:mistfen"},
             "say": "Oss unrolls it on his knees and is quiet for a long time. \"She drew my ferry,\" he says. \"Look. Little boat. Little man.\" He rolls it up again and gives it back. \"It's yours. She'd want it walked.\""},
        ],
        "endings": {"default": {"say": "The Cartographer's Compass is yours. It never points north.",
                                "reward": {"gold": 700, "insight": 8, "items": {"cartographers_compass": 1}, "bond": {"Ferryman Oss": 25}, "title": "Who Walked Her Map"}}},
    },
]

doc = {
    "_note": "Mysteries and treasure hunts (2026-11-03). Side quests read by scripts/systems/Quests.gd (_mysteries). find.place/near/subtle place a clue where its words say; choices[].needs means you need that proof to make that charge. Written by tools/gen/mysteries_gen.py -- Dev may rewrite the words (keep ids and NPC names).",
    "clues": clues,
    "uniques": uniques,
    "quests": quests,
}
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=1, ensure_ascii=False)
    f.write("\n")
print("wrote", os.path.normpath(OUT), len(quests), "quests,", len(clues), "clues")
