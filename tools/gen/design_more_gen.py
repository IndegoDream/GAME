#!/usr/bin/env python3
"""More ways to make a piece your own: motifs, trims, dyes, cuts, settings, polishes, vials, tinctures, seals, preps. Idempotent."""
import json, os, shutil
P='data/design_traits.json'; I='data/items.json'
d=json.load(open(P)); items=json.load(open(I))
if not os.path.exists(P+'.bak-more'): shutil.copy(P,P+'.bak-more')
def add(sec,grp,key,name,desc,ms,**kw):
    for c in kw.get('cost',{}):
        assert c in items,c
    d[sec][grp].setdefault(key,dict(name=name,desc=desc,min_skill=ms,**kw))
F='forge'
add(F,'motifs','scaled','Scaled plates','Overlapping scales. More ward, a little slower.',2,ward_mult=1.08,weight_mult=1.1,effect={"attack_speed":0.98},look="studs")
add(F,'motifs','feathered','Feathered','Light plumes and cutaways. Quicker, less ward.',2,ward_mult=0.93,weight_mult=0.88,effect={"attack_speed":1.03},look="filigree")
add(F,'motifs','spiral','Spiral lines','Wound lines that lead qi round. Qi and calm.',3,value_mult=1.15,effect={"qi_mult":1.02,"meditate_mult":1.02},look="filigree")
add(F,'motifs','thorned','Thorned','Hooked spines. You hit harder; so does everything else.',3,effect={"damage_mult":1.03,"damage_taken":1.02},look="studs")
add(F,'motifs','lacquered','Lacquered','Layered and polished. Tougher, worth more, heavier.',3,ward_mult=1.05,value_mult=1.25,weight_mult=1.06,look="flare")
add(F,'motifs','sunburst','Sunburst','Rays of inlay. Finds go your way.',4,value_mult=1.2,effect={"loot_luck":0.02},look="runic",glow=[1.0,0.82,0.35])
add(F,'motifs','moonlit','Moonlit','Cold lines that drink the dark. A stiller mind, a softer guard.',4,ward_mult=0.95,effect={"meditate_mult":1.04},look="runic",glow=[0.6,0.7,1.0])
add(F,'motifs','stormwork','Stormwork','Forked lines of arc-light. Fast, and the lightning gets you too.',5,effect={"attack_speed":1.04,"damage_taken":1.02},look="runic",glow=[0.7,0.5,1.0])
add(F,'motifs','dragonbone','Dragonbone ridges','Ridged like a spine. Strong everywhere, heavy everywhere.',6,ward_mult=1.12,hp_mult=1.03,weight_mult=1.25,value_mult=1.4,look="flare")
add(F,'trims','copper','Copper trim','Costs a brass cog. Warm and cheap. A little worth.',1,cost={"brass_cog":1},value_mult=1.08,color=[0.8,0.5,0.3])
add(F,'trims','obsidian','Obsidian edge','Costs an obsidian edge. Hard black edging; keen.',3,cost={"obsidian_edge":1},effect={"damage_mult":1.01},color=[0.1,0.1,0.14])
add(F,'trims','moonsilver','Moonsilver','Costs mirror silver. Pale and calm.',3,cost={"mirror_silver":1},effect={"meditate_mult":1.02},value_mult=1.2,color=[0.75,0.85,1.0])
add(F,'trims','ruby','Ruby studs','Costs a rough ruby. Fierce.',3,cost={"rough_ruby":1},effect={"damage_mult":1.015},color=[0.8,0.1,0.18])
add(F,'trims','pearl','Pearl inlay','Costs a pearl. Gentle waters, gentle worth.',3,cost={"pearl_oyster":1},effect={"hp_mult":1.015},value_mult=1.2,color=[0.95,0.93,0.88])
add(F,'trims','starlight','Star-iron trim','Costs star iron. Heavier, luckier.',4,cost={"star_iron":1},effect={"loot_luck":0.015},weight_mult=1.04,color=[0.6,0.65,0.95])
add(F,'trims','imperial','Imperial gilt','Costs an imperial seal. Rich, heavy, a purse for thieves.',5,cost={"imperial_seal":1},value_mult=1.7,effect={"loot_luck":0.03},weight_mult=1.05,color=[1.0,0.84,0.25])
for k,n,ds,ms,eff,col in [
 ('ember','Ember orange','Fire-lit. A bit fiercer.',1,{"damage_mult":1.015},[0.9,0.4,0.1]),
 ('violet','Violet dusk','Deep purple. Qi settles.',1,{"qi_mult":1.015},[0.35,0.2,0.55]),
 ('teal','Sea teal','Cool water-green. Steadier lungs.',1,{"hp_mult":1.015},[0.1,0.5,0.5]),
 ('ivory','Ivory','Warm white. Looks expensive.',1,{},[0.93,0.9,0.8]),
 ('ash','Ash grey','Quiet grey. Hard to notice.',1,{"dodge_chance":0.008},[0.45,0.45,0.48]),
 ('rose','Rose','Soft pink. Calm minds.',1,{"meditate_mult":1.015},[0.85,0.45,0.55]),
 ('verdant','Verdant','Leaf green. Herbs come easier.',2,{"gather_chance":0.03},[0.25,0.6,0.25]),
 ('storm','Storm blue','Dark blue-grey. Quick.',2,{"attack_speed":1.015},[0.2,0.3,0.5]),
 ('saffron','Saffron','Bright gold-orange. Finds.',2,{"loot_luck":0.015},[0.95,0.65,0.1]),
 ('plum','Plum','Dark wine. Sturdier.',2,{"hp_mult":1.01,"damage_taken":0.995},[0.35,0.12,0.25]),
 ('frost','Frost white','Icy pale. A cold calm.',2,{"meditate_mult":1.02},[0.8,0.92,0.98]),
 ('obsid','Obsidian black','Total black. A little dodge, a little gloom.',3,{"dodge_chance":0.012},[0.04,0.04,0.06]),
 ('sunset','Sunset','Orange to red. Fierce and showy.',3,{"damage_mult":1.02},[0.95,0.4,0.25]),
 ('aurora','Aurora green','Shifting green-blue. Qi flows.',4,{"qi_mult":1.025},[0.2,0.85,0.65])]:
    add(F,'dyes',k,n,ds,ms,effect=eff,color=col)
J='jewel'
add(J,'cuts','marquise','Marquise','Long and sharp. Hits land harder.',3,effect={"damage_mult":1.02},value_mult=1.1)
add(J,'cuts','star','Star cut','Rays of light. Worth much more.',4,effect={"qi_mult":1.02},value_mult=1.3)
add(J,'cuts','briolette','Briolette','Teardrop facets all round. A lucky finder.',4,effect={"loot_luck":0.02},value_mult=1.15)
add(J,'cuts','heartstone','Heartstone cut','Warm, rounded. A fuller heart.',3,effect={"hp_mult":1.02})
add(J,'cuts','void','Void cut','Takes light in. Calm, deep and cheap to sell.',5,effect={"meditate_mult":1.05},value_mult=0.9)
add(J,'settings','prong','Crown prongs','Lets the light in. A little more qi, a little less guard.',2,effect={"qi_mult":1.015,"damage_taken":1.005})
add(J,'settings','cage','Wire cage','Holds loosely and lightly. Quicker hands.',3,effect={"attack_speed":1.02})
add(J,'settings','inlay','Flush inlay','Sits low. Safe: less taken.',3,effect={"damage_taken":0.99})
add(J,'settings','ward','Warded setting','Rune-cut seat. More dodge, less strike.',4,effect={"dodge_chance":0.015,"damage_mult":0.99})
add(J,'polishes','satin','Satin','Soft glow. Calm.',1,effect={"meditate_mult":1.01},value_mult=1.05)
add(J,'polishes','frosted','Frosted','Like sea-glass. Quiet worth.',2,value_mult=1.1)
add(J,'polishes','opalescent','Opalescent','Shifting colours. Worth a lot.',3,value_mult=1.4)
add(J,'polishes','sunwashed','Sun-washed','Warm shine. Lucky.',3,effect={"loot_luck":0.01},value_mult=1.1)
A='alchemy'
add(A,'vials','gourd','Gourd flask','Fat and slow. Makes a stronger dose, rarely.',2,heal_mult=1.18,item_qi_mult=1.18,value_mult=0.85)
add(A,'vials','crystal','Crystal vial','Clear and fine. Sells well.',3,value_mult=1.3)
add(A,'vials','bamboo','Bamboo tube','Light and cheap. A little weaker.',1,heal_mult=0.95,item_qi_mult=0.95,value_mult=0.9)
add(A,'tinctures','moon','Moonpetal infusion','x',1) if False else None
add(A,'tinctures','venom','Venom-reed tincture','Costs a venom reed. Sharp: more qi, less healing.',3,cost={"venom_reed":1},item_qi_mult=1.2,heal_mult=0.9,value_mult=1.1)
add(A,'tinctures','lotus','Frost-lotus tincture','Costs a frost lotus. Cooling: more healing.',3,cost={"frost_lotus":1},heal_mult=1.15,value_mult=1.1)
add(A,'tinctures','pearl','Pearl-dust tincture','Costs a pearl. Fine and rich.',4,cost={"pearl_oyster":1},heal_mult=1.1,item_qi_mult=1.1,value_mult=1.25)
add(A,'seals','amber','Amber seal','Costs old amber. Keeps for years: sells high.',3,cost={"old_amber":1},value_mult=1.3)
add(A,'seals','ghost','Ghost-oil seal','Costs ghost-lantern oil. Slightly stronger.',4,cost={"ghost_lantern_oil":1},heal_mult=1.08,item_qi_mult=1.08)
M='medicine'
add(M,'preps','salve','Thick salve','Heals more; sells less.',1,heal_mult=1.2,value_mult=0.9)
add(M,'preps','compress','Cool compress','Slow, gentle. A little more qi.',2,item_qi_mult=1.1,heal_mult=0.95)
add(M,'preps','elixir','Clear elixir','Light but potent. Worth more.',3,heal_mult=1.1,value_mult=1.2)
add(M,'tinctures','lotus','Frost-lotus tincture','Costs a frost lotus. Cooling: more healing.',3,cost={"frost_lotus":1},heal_mult=1.15,value_mult=1.1)
add(M,'tinctures','pearl','Pearl-dust tincture','Costs a pearl. Fine and rich.',4,cost={"pearl_oyster":1},heal_mult=1.1,item_qi_mult=1.1,value_mult=1.25)
json.dump(d,open(P,'w'),indent=1,ensure_ascii=False)
print({s:{g:len(v) for g,v in d[s].items() if isinstance(v,dict)} for s in ('forge','jewel','alchemy','medicine')})
