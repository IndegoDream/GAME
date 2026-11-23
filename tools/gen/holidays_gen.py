#!/usr/bin/env python3
"""2026-11-03: holidays. Adds to data/world.json: "holidays" (real-calendar, shown on the player's own date) and "world_holidays"
(the valley's own calendar: a 5-day season, so a year is 20 days). Idempotent; backup .bak-holidays. Run from the project root."""
import json, os, shutil, sys
def C(*a): return [list(x) for x in a]
RED=(1.0,0.35,0.35); GOLD=(1.0,0.8,0.4); GREEN=(0.45,0.9,0.5); WHITE=(0.95,0.95,1.0); BLUE=(0.5,0.7,1.0); PINK=(1.0,0.6,0.8); ORANGE=(1.0,0.55,0.2); PURPLE=(0.7,0.45,0.95)
# rule: {"month","day","span"} or {"easter":offset,"span"} or {"nth":n,"weekday":0-6 (0=Sun),"month"} or {"table":{year:[month,day]},"span"}
HOLIDAYS = [
 dict(id="new_year", name="New Year's Day", rule={"month": 1, "day": 1, "span": 2}, desc="Eliet counts down the last night of the year and starts the next one together. A fresh start, they say, is a thing you can pick up with both hands.", discount=0.12, gift={"qi_pill": 2, "healing_salve": 3}, colors=C(GOLD, WHITE, BLUE), effect={"insight_mult": 1.1}),
 dict(id="lunar_new_year", name="Lunar New Year", rule={"table": {2026: [2, 17], 2027: [2, 6], 2028: [1, 26], 2029: [2, 13], 2030: [2, 3], 2031: [1, 23], 2032: [2, 11], 2033: [1, 31], 2034: [2, 19], 2035: [2, 8]}, "span": 3}, desc="Red lanterns, red paper and long tables. The elder hands out little red packets, and the smiths set off cracker-charges for luck.", discount=0.15, gift={"lucky_charm": 1, "qi_pill": 2}, colors=C(RED, GOLD, ORANGE), effect={"loot_luck": 0.06}),
 dict(id="valentine", name="Hearts' Eve", rule={"month": 2, "day": 14, "span": 1}, desc="Ribbons on every door and small gifts under the lanterns. Even the grumpy ones leave something out.", discount=0.1, gift={"bone_broth": 2, "healing_salve": 2}, colors=C(PINK, RED, WHITE), effect={"meditate_mult": 1.08}),
 dict(id="st_patrick", name="Clover Day", rule={"month": 3, "day": 17, "span": 1}, desc="Green ribbons and a very loud band. The traders say a clover found today is worth a gold piece, though they say a lot of things.", discount=0.1, gift={"lucky_charm": 1, "bone_broth": 2}, colors=C(GREEN, GOLD, WHITE), effect={"loot_luck": 0.05}),
 dict(id="easter", name="Spring Awakening", rule={"easter": 0, "span": 2}, desc="Painted eggs hidden around the village and a basket for every child. The first new green of the year is blessed at dawn.", discount=0.12, gift={"spirit_herb": 4, "healing_salve": 2}, colors=C(PINK, GREEN, GOLD, BLUE), effect={"gather_chance": 0.06}),
 dict(id="earth_day", name="Day of Green Hands", rule={"month": 4, "day": 22, "span": 1}, desc="The village plants a tree for every herb it has pulled up this year. The herbalists show off.", discount=0.1, gift={"spirit_herb": 5}, colors=C(GREEN, WHITE), effect={"gather_chance": 0.08}),
 dict(id="independence", name="Fireworks Night", rule={"month": 7, "day": 4, "span": 1}, desc="The smiths pack the sky with sparks and the whole valley sits on the hillside to watch. Loud, bright, and good for the spirits.", discount=0.12, gift={"ember_pill": 1, "whetstone": 2}, colors=C(RED, WHITE, BLUE), effect={"damage_mult": 1.05}),
 dict(id="halloween", name="Hollow Night", rule={"month": 10, "day": 29, "span": 3}, desc="Carved gourds on every step, and the dead are welcome for the night. The traders hand out sweets, and the children are not to be trusted.", discount=0.1, gift={"qi_incense": 2, "ember_pill": 1}, colors=C(ORANGE, PURPLE, WHITE), effect={"qi_mult": 1.08}),
 dict(id="diwali", name="Festival of a Thousand Lamps", rule={"table": {2026: [11, 8], 2027: [10, 29], 2028: [10, 17], 2029: [11, 5], 2030: [10, 26], 2031: [11, 14], 2032: [11, 2], 2033: [10, 22], 2034: [11, 10], 2035: [10, 30]}, "span": 3}, desc="A thousand small lamps along every road and every sill. Sweets pass from hand to hand, and nothing is allowed to stay dark.", discount=0.15, gift={"qi_pill": 2, "lucky_charm": 1}, colors=C(GOLD, ORANGE, PINK, PURPLE), effect={"insight_mult": 1.12}),
 dict(id="thanksgiving", name="Harvest Table", rule={"nth": 4, "weekday": 4, "month": 11, "span": 1}, desc="Every house sets out a plate for whoever walks past. The Harvest Table runs the length of the square, and no one counts the portions.", discount=0.2, gift={"bone_broth": 4, "lucky_charm": 1}, colors=C(ORANGE, GOLD, (0.7, 0.4, 0.2)), effect={"hp_mult": 1.06}),
 dict(id="christmas", name="Midwinter Gifts", rule={"month": 12, "day": 24, "span": 3}, desc="Evergreen boughs in every window, one gift for everyone in the village, and a long quiet supper. Even the deep feels a little less cold.", discount=0.15, gift={"qi_pill": 3, "healing_salve": 3, "lucky_charm": 1}, colors=C(RED, GREEN, GOLD, WHITE), effect={"meditate_mult": 1.12, "loot_luck": 0.05}),
 dict(id="new_year_eve", name="Year's End", rule={"month": 12, "day": 31, "span": 1}, desc="Counting the year's good and bad. Bells at midnight, and a toast for everyone who did not make it home.", discount=0.1, gift={"qi_incense": 2}, colors=C(GOLD, BLUE, WHITE), effect={"insight_mult": 1.1}),
]
# the valley's own: (season, day of season 1-5), the existing festival is day 3
WORLD = [
 dict(season="thaw", day=1, id="founders_day", name="Founders' Day", desc="Eliet remembers the first expedition and the first fire. Every house puts a lantern in the window for the ones who went down first.", discount=0.12, gift={"qi_pill": 2, "whetstone": 1}, colors=C(GOLD, WHITE), effect={"insight_mult": 1.08}),
 dict(season="thaw", day=5, id="root_dawn", name="Root-Dawn", desc="At first light the herbalists lay the season's first harvest on the stones. Everything that grows grows a little better today.", discount=0.1, gift={"spirit_herb": 5}, colors=C(GREEN, GOLD), effect={"gather_chance": 0.1}),
 dict(season="blaze", day=1, id="forge_feast", name="The Forge Feast", desc="The smiths open the forges to everyone. Anyone can hammer a nail and be called a smith for the day.", discount=0.1, gift={"whetstone": 3, "iron_ore": 4}, colors=C(ORANGE, RED), effect={"craft_quality": 0.04}),
 dict(season="blaze", day=5, id="tower_vigil", name="Tower Vigil", desc="The sects light beacons on every tower, and the valley stays awake to watch them burn. A night for climbers.", discount=0.1, gift={"ember_pill": 2}, colors=C(RED, WHITE, GOLD), effect={"attack_speed": 1.04}),
 dict(season="harvest", day=1, id="gleaning", name="Gleaning Day", desc="The fields are open to anyone who will carry a basket. The leavings are always the best of it.", discount=0.15, gift={"bone_broth": 3, "spirit_herb": 3}, colors=C(ORANGE, GOLD), effect={"loot_luck": 0.06}),
 dict(season="harvest", day=5, id="lamp_walk", name="The Lamp Walk", desc="A slow procession from the village to the first stair, a lamp in every hand. They leave the lamps at the top, to light the way down.", discount=0.1, gift={"qi_pill": 2, "healing_salve": 2}, colors=C(GOLD, ORANGE, PINK), effect={"meditate_mult": 1.08}),
 dict(season="frost", day=1, id="first_snow", name="First Snow", desc="Children out in the street before dawn to meet it. The traders hand out hot drinks.", discount=0.1, gift={"bone_broth": 3}, colors=C(WHITE, BLUE), effect={"hp_mult": 1.05}),
 dict(season="frost", day=5, id="rest_night", name="Night of Rest", desc="Everything shuts, even the forges. The valley sleeps on purpose, and the old say that dreams are clearest tonight.", discount=0.08, gift={"qi_incense": 3}, colors=C(BLUE, PURPLE, WHITE), effect={"meditate_mult": 1.15}),
]
def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    p = os.path.join(root, "data/world.json")
    b = p + ".bak-holidays"
    if not os.path.exists(b): shutil.copy(p, b)
    w = json.load(open(p))
    w["holidays"] = HOLIDAYS
    w["world_holidays"] = WORLD
    json.dump(w, open(p, "w"), indent=1, ensure_ascii=False)
    print("holidays: %d real, %d world" % (len(HOLIDAYS), len(WORLD)))
main()
