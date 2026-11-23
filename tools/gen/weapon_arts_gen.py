import json
W = {
 "sword": [
  ("flowing_cut", "Flowing Cut", "step", "leap_strike", 5, 7.0, 16, ["metal","water"], {"distance": 6.0, "radius": 2.6, "mult": 1.6, "stagger": 0.6},
   "A gliding lunge six metres forward that ends in a cut around you: 1.6x to everything within 2.6 m."),
  ("petal_flurry", "Thousand Petal Flurry", "strike", "flurry", 15, 6.0, 24, ["metal","wood"], {"hits": 6, "mult": 0.5, "reach": 3.2, "arc": 110.0, "interval": 0.09, "crit": 0.3},
   "Six cuts in a single breath at whatever is in front of you (0.5x each), each with a 30% chance to strike true."),
  ("mirror_stance", "Mirror Stance", "strike", "counter_stance", 30, 9.0, 18, ["metal","water"], {"secs": 1.6, "mult": 3.2, "stagger": 1.4},
   "Raise the blade and wait: the next blow aimed at you in 1.6 seconds is turned aside and answered for 3.2x, staggering them.")],
 "dagger": [
  ("shadow_step", "Shadow Step", "step", "blink", 5, 4.0, 14, ["water","metal"], {"range": 6.0, "iframes": 0.35, "behind": 1.0},
   "Vanish and step six metres (behind the nearest foe, if one is close), untouchable for a moment."),
  ("viper_flurry", "Viper Flurry", "strike", "flurry", 15, 5.0, 22, ["water","wood"], {"hits": 7, "mult": 0.4, "reach": 2.6, "arc": 90.0, "interval": 0.07, "bleed": 0.8},
   "Seven quick stabs (0.4x each); the last leaves a cut that bleeds for most of what they dealt again."),
  ("fan_of_knives", "Fan of Knives", "strike", "throw", 30, 7.0, 24, ["metal","fire"], {"range": 11.0, "width": 3.2, "mult": 1.3, "returns": 0.0, "bleed": 0.5},
   "A fan of thrown blades eleven metres ahead and three wide: 1.3x and a bleeding cut to all they find.")],
 "saber": [
  ("crescent_moon", "Crescent Moon", "strike", "arc_sweep", 5, 5.0, 22, ["metal","water"], {"radius": 4.2, "arc": 240.0, "mult": 1.5, "stagger": 0.4},
   "A wide crescent cut, 240 degrees and 4.2 m: 1.5x to everything it catches."),
  ("cyclone_edge", "Cyclone Edge", "strike", "whirlwind", 15, 8.0, 28, ["metal","wood"], {"radius": 3.2, "ticks": 5, "interval": 0.22, "mult": 0.65, "move": 1.15},
   "Spin with the blade out for a second: five turns, 0.65x to everything within 3.2 m each turn, and you can still move."),
  ("returning_crescent", "Returning Crescent", "strike", "throw", 30, 7.0, 24, ["metal","water"], {"range": 10.0, "width": 1.8, "mult": 1.2, "returns": 1.0},
   "Hurl the saber spinning ten metres out and back: 1.2x going, 1.2x coming home.")],
 "spear": [
  ("dragon_thrust", "Dragon Thrust", "strike", "lance_line", 5, 5.0, 22, ["metal","wood"], {"range": 7.0, "width": 1.4, "mult": 2.0, "knock": 4.0},
   "A thrust that carries its qi seven metres through every foe in line: 2x, and they are driven back."),
  ("vaulting_spear", "Vaulting Spear", "step", "leap_strike", 15, 8.0, 18, ["wood","earth"], {"distance": 8.0, "radius": 3.0, "mult": 1.7, "stagger": 1.0},
   "Plant the spear and vault eight metres, landing point-first: 1.7x within 3 m and a stagger."),
  ("hundred_points", "Hundred Points", "strike", "flurry", 30, 7.0, 28, ["metal","wood"], {"hits": 8, "mult": 0.45, "reach": 4.4, "arc": 50.0, "interval": 0.08},
   "Eight thrusts so fast they look like a hedge of points, 4.4 m straight ahead (0.45x each).")],
 "axe": [
  ("cleaving_arc", "Cleaving Arc", "strike", "shatter", 5, 6.0, 24, ["metal","earth"], {"reach": 3.4, "arc": 140.0, "mult": 1.7, "vs_staggered": 1.6, "vs_armoured": 1.7, "sunder": 6.0},
   "A downward cleave across 140 degrees: 1.7x, far more against the staggered and the armoured, whose plating it splits."),
  ("whirling_axe", "Whirling Axe", "strike", "whirlwind", 15, 9.0, 30, ["metal","fire"], {"radius": 3.0, "ticks": 4, "interval": 0.26, "mult": 0.85, "move": 1.0, "bleed": 0.4},
   "Four heavy turns with the axe out: 0.85x to everything within 3 m each turn, each cut bleeding."),
  ("hurled_axe", "Hurled Axe", "strike", "throw", 30, 7.0, 24, ["metal","earth"], {"range": 12.0, "width": 1.6, "mult": 1.8, "returns": 1.0, "stagger": 0.8},
   "Throw the axe twelve metres: it splits what it meets (1.8x) and spins back to your hand.")],
 "hammer": [
  ("earthbreaker", "Earthbreaker", "strike", "ground_slam", 5, 7.0, 28, ["earth","metal"], {"reach": 2.6, "radius": 3.6, "mult": 2.1, "stagger": 1.4},
   "Bring the hammer down into the ground ahead: a shock of 3.6 m, 2.1x and a long stagger."),
  ("meteor_drop", "Meteor Drop", "step", "leap_strike", 15, 10.0, 24, ["earth","fire"], {"distance": 7.0, "radius": 4.2, "mult": 2.2, "stagger": 1.5},
   "Leap high and fall hammer-first: 2.2x and a stagger within 4.2 m where you land."),
  ("fault_line", "Fault Line", "strike", "lance_line", 30, 7.0, 30, ["earth","metal"], {"range": 10.0, "width": 3.0, "mult": 1.9, "knock": 2.5},
   "Split the ground in a line ten metres long and three wide: 1.9x to all in it, thrown off their feet.")],
 "halberd": [
  ("reaping_sweep", "Reaping Sweep", "strike", "arc_sweep", 5, 6.0, 24, ["metal","wood"], {"radius": 4.8, "arc": 300.0, "mult": 1.4, "stagger": 0.6},
   "A sweep almost all the way round, 4.8 m long: 1.4x to everything it reaches."),
  ("hooking_pull", "Hooking Pull", "step", "pull", 15, 6.0, 16, ["metal","water"], {"range": 7.0, "mult": 1.0, "stagger": 1.5},
   "Hook a foe up to seven metres off and drag them to your feet, staggered (bosses are too heavy to move)."),
  ("halberd_storm", "Halberd Storm", "strike", "whirlwind", 30, 9.0, 30, ["metal","wood"], {"radius": 4.4, "ticks": 4, "interval": 0.25, "mult": 0.8, "move": 0.9, "knock": 3.0},
   "Spin the halberd at full length: four turns, 0.8x within 4.4 m each, throwing them back.")],
 "staff": [
  ("cloud_vault", "Cloud Vault", "step", "leap_strike", 5, 6.0, 14, ["wood","water"], {"distance": 7.0, "radius": 2.4, "mult": 1.2, "stagger": 1.0},
   "Pole-vault seven metres and land with a sweep: 1.2x and a stagger within 2.4 m."),
  ("monkey_flurry", "Monkey King's Flurry", "strike", "flurry", 15, 6.0, 20, ["wood","earth"], {"hits": 6, "mult": 0.5, "reach": 3.4, "arc": 160.0, "interval": 0.1, "stagger": 0.3},
   "Six spinning blows of the staff across a wide arc (0.5x each), each one rocking them."),
  ("still_lake", "Still Lake Stance", "strike", "counter_stance", 30, 8.0, 0, ["water","wood"], {"secs": 1.8, "mult": 2.6, "stagger": 1.8, "cool_heat": 25.0},
   "Hold the staff level and breathe: the next blow in 1.8 seconds is turned and answered for 2.6x, and your nanites cool by 25.")],
 "unarmed": [
  ("hundred_fists", "Hundred Fists", "strike", "flurry", 5, 5.0, 20, ["fire","earth"], {"hits": 9, "mult": 0.32, "reach": 2.4, "arc": 100.0, "interval": 0.06},
   "Nine blows in the time it takes to blink (0.32x each) on whatever stands in front of you."),
  ("mountain_palm", "Mountain Palm", "strike", "lance_line", 15, 6.0, 24, ["earth","fire"], {"range": 5.0, "width": 2.6, "mult": 1.9, "knock": 6.0},
   "An open palm that pushes the air itself five metres ahead: 1.9x and everything it hits is hurled back."),
  ("flowing_water", "Flowing Water Stance", "strike", "counter_stance", 30, 7.0, 16, ["water","wood"], {"secs": 1.5, "mult": 3.0, "stagger": 2.0},
   "Empty hands, soft knees: the next blow in 1.5 seconds slides past you and is answered for 3x with a long stagger.")],
 "bow": [
  ("rain_of_arrows", "Rain of Arrows", "strike", "volley", 5, 8.0, 24, ["wood","metal"], {"radius": 3.6, "arrows": 10, "mult": 0.55, "range": 22.0},
   "Loose ten arrows high: they come down within 3.6 m of the foe you face, up to 22 m off (0.55x each)."),
  ("gale_shot", "Piercing Gale Shot", "strike", "lance_line", 15, 6.0, 22, ["wood","metal"], {"range": 24.0, "width": 1.2, "mult": 2.1},
   "One arrow on a gale of qi: 24 metres straight through everything in its path, 2.1x."),
  ("scatter_shot", "Scatter Shot", "strike", "multi_bolt", 30, 6.0, 22, ["wood","fire"], {"range": 16.0, "targets": 5, "mult": 1.0, "cone": 0.2},
   "Five arrows at once, each to a different foe in front of you up to 16 m away (1x each).")],
 "crossbow": [
  ("bolt_barrage", "Bolt Barrage", "strike", "volley", 5, 9.0, 26, ["metal","earth"], {"radius": 2.8, "arrows": 7, "mult": 0.8, "range": 20.0},
   "Seven bolts cranked and loosed in a blur onto the foe you face (within 2.8 m, 0.8x each)."),
  ("pinning_bolt", "Pinning Bolt", "strike", "pin", 15, 7.0, 16, ["earth","metal"], {"range": 18.0, "secs": 3.0, "mult": 1.2},
   "A heavy bolt that pins the foe you face to the ground for three seconds, 1.2x."),
  ("siege_bolt", "Siege Bolt", "strike", "lance_line", 30, 8.0, 30, ["metal","fire"], {"range": 28.0, "width": 1.6, "mult": 2.6},
   "A bolt meant for gates: 28 metres through everything in line for 2.6x.")],
 "ki": [
  ("spirit_orbs", "Spirit Orbs", "strike", "multi_bolt", 5, 5.0, 20, ["fire","water"], {"range": 14.0, "targets": 4, "mult": 1.0, "cone": -0.3},
   "Four orbs of ki that each find a foe of their own within 14 m, in any direction (1x each)."),
  ("ki_lance", "Ki Lance", "strike", "lance_line", 15, 5.0, 22, ["fire","metal"], {"range": 18.0, "width": 1.4, "mult": 2.0},
   "Gather the pool into one line of light: 18 metres through everything, 2x."),
  ("qi_nova", "Qi Nova", "strike", "ground_slam", 30, 9.0, 32, ["fire","earth"], {"reach": 0.0, "radius": 5.2, "mult": 2.0, "stagger": 1.0},
   "Let it all go at once: a nova of ki 5.2 m around you, 2x and a stagger.")],
}
SK = {"sword":"Sword","dagger":"Dagger","saber":"Saber","spear":"Spear","axe":"Axe","hammer":"Hammer","halberd":"Halberd","staff":"Staff","unarmed":"Unarmed","bow":"Bow","crossbow":"Crossbow","ki":"Ki"}
arts=[]
for w, rows in W.items():
    for (aid,name,fam,tpl,lvl,cd,heat,br,params,desc) in rows:
        arts.append({"id": "w_"+aid, "name": name, "family": fam, "template": tpl, "cooldown": cd, "heat": heat, "route": [], "branches": br,
            "params": params, "desc": desc, "hint": "It comes to anyone who fights long enough with that kind of weapon.",
            "req": {"weapon": w, "level": lvl}, "weapon": w})
out={"_about": "Round 188 (Robert, 2026-11-08: 'There needs to be more variety in the martial arts and their special abilities for the type of skill it is'). Three arts for every kind of weapon, learned at skill 5, 15 and 30 of that weapon and used only with it in hand. They are arts like any other (scripts/systems/Arts.gd merges them; scripts/actors/ArtCaster.gd casts them): F or V, the quick keys R / F3 / F4 / F5, practice, mastery, branches. New ways of fighting for them: flurry, whirlwind, throw, volley, counter_stance, multi_bolt.", "levels": [5,15,30], "arts": arts}
json.dump(out, open('data/weapon_arts.json','w'), indent=1, ensure_ascii=False)
print(len(arts))
