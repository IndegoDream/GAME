#!/usr/bin/env python3
"""World bosses: one per open region, stirring on a rotating schedule. Idempotent. Run in the project root."""
import json, os, shutil
def load(p): return json.load(open(p))
def save(p, d):
    if not os.path.exists(p + '.bak-wboss'): shutil.copy(p, p + '.bak-wboss')
    json.dump(d, open(p, 'w'), indent=1, ensure_ascii=False)
fr = load('data/frontier.json'); en = load('data/enemies.json'); it = load('data/items.json')
# region -> (boss title, relic name, relic type, effect, relic blurb)
WB = {
 'crash_site':  ("Beacon Prime",            "Signal Ring",        'ring',   {"qi_mult": 1.08},        "a ring humming the beacon's last call"),
 'launch_yard': ("The Skyhook Colossus",    "Pad-Lock Amulet",    'amulet', {"hp_mult": 1.10},        "a clamp that once held a ship to the sky"),
 'ashen_moon':  ("Moonwake Sovereign",      "Ashglass Ring",      'ring',   {"loot_luck": 1.10},      "grey glass that remembers a warmer light"),
 'glass_desert':("The Shard Emperor",       "Prism Amulet",       'amulet', {"damage_mult": 1.08},    "a shard that bends every blow toward its mark"),
 'whisperwood': ("Ancient of Whispers",     "Heartwood Ring",     'ring',   {"hp_mult": 1.08, "regen": 0.5}, "a ring that grows a leaf each spring"),
 'mistfen':     ("The Drowned Queen",       "Fenlight Amulet",    'amulet', {"gather_chance": 0.12},  "a bottled marsh-light that points to herbs"),
 'bonefields':  ("Marshal of the Unburied", "Marshal's Signet",   'ring',   {"damage_mult": 1.10},    "a signet pressed in grave-wax"),
 'jadehill':    ("The Terrace Warden",      "Jade Sage Amulet",   'amulet', {"meditate_mult": 1.25},  "carved by someone who sat very still"),
 'sunken_mere': ("Leviathan of the Mere",   "Tidepearl Ring",     'ring',   {"qi_mult": 1.10},        "a pearl with a slow tide inside"),
 'stormcliffs': ("The Thunder Regent",      "Stormcoil Amulet",   'amulet', {"attack_speed": 1.10},   "copper wound around a trapped storm"),
 'emberwaste':  ("The Magma Sovereign",     "Cinder Crown Ring",  'ring',   {"damage_mult": 1.12},    "a ring that is always slightly too warm"),
 'frostmere':   ("The Winter Throne",       "Rimeheart Amulet",   'amulet', {"hp_mult": 1.14},        "a frozen heart that beats once an hour"),
 'sandglass':   ("Khet, Keeper of Hours",   "Hourglass Amulet",   'amulet', {"meditate_mult": 1.35, "qi_mult": 1.05}, "sand that falls upward when you rest"),
 'blighted_wood':("The Rot King's Shadow",  "Blightroot Ring",    'ring',   {"damage_mult": 1.15, "hp_mult": 1.05}, "a root-ring that bites back"),
}
it['worldboss_core'] = {"name": "World-Boss Core", "type": "material", "value": 400, "element": "metal",
    "desc": "The still-warm heart of something that only stirs now and then. Rare crafters pay dearly."}
idx = 0
for rid, (title, rname, rtype, eff, blurb) in WB.items():
    r = fr['regions'].get(rid)
    if not r: continue
    base = en.get(r.get('boss')) or max((e for e in en.values() if e.get('frontier') and e.get('boss') and e.get('floor') == r['depth']), key=lambda e: e['hp'], default=None)
    if base is None:
        base = max((e for e in en.values() if e.get('boss') and e.get('floor', 0) <= r['depth']), key=lambda e: e.get('floor', 0))
    wid = 'wb_' + rid
    relic = 'relic_' + rid
    t = base.get('tint', [0.8, 0.8, 0.8])
    e = dict(base)
    e.update({"name": title, "hp": int(base['hp'] * 2.4), "damage": int(base['damage'] * 1.5), "qi": int(base.get('qi', 0) * 2),
              "scale": round(base.get('scale', 2.0) * 1.35, 2), "tint": [min(1, c * 0.6 + 0.35) for c in t], "boss": True, "world_boss": True,
              "loot": {"gold": [base['loot'].get('gold', [900, 1200])[0] * 3, base['loot'].get('gold', [900, 1200])[1] * 3],
                       "worldboss_core": [1, 2], relic: [1, 1], "qi_pill": [3, 5]}})
    e.pop('frontier', None); e['frontier'] = True
    en[wid] = e
    it[relic] = {"name": rname, "type": rtype, "value": 900, "effect": eff, "desc": "Dropped by " + title + " -- " + blurb + "."}
    r['world_boss'] = wid
    r['wb_slot'] = idx
    idx += 1
save('data/enemies.json', en); save('data/items.json', it); save('data/frontier.json', fr)
print('world bosses:', idx)
