#!/usr/bin/env python3
"""Round 141: pull every translatable English string out of data/*.json that is not yet in the catalog,
split into chunks (tier A names, B short text, C long text) under tools/i18n/todo/. Run from the game folder."""
import glob, json, re, os, sys
KEYS = {"name","title","label","desc","hint","blurb","summary","tenets","text","say","lines","line","body","story","intro","tip","tips","verb","prompt"}
NAMEK = {"name","title","label"}
SKIP_FILES = {"writing_room.json","ui.json","i18n","build_info.json","performance_settings.json","audio.json","balance.json"}
SKIP_VALUES = {"New Consumable","A newly added consumable item.","...","","cinzel-latin-ext-700.woff2"}
have = set(json.load(open("data/i18n/es.json", encoding="utf8")).keys())
found = {}  # string -> first key
NOTEXT = {"id","kind","type","model","anim","sound","sfx","file","path","icon","slot","sect","element","biome","tag","tags","note","notes","comment","voice","font","color","colour","mesh","scene","texture","trigger","need","needs","requires","after","unlock","skill","stat","effect","giver_at","place","key","hotkey","action","verb_id","target","fx","pattern","family","group","shape","hair","dress","head","banner","opener"}
def looks_text(s):
    if " " in s.strip(): return True
    return bool(re.match(r"[A-Z][a-z]{3,}", s))
def ok(s):
    if re.search(r"^Round \d+|scripts/|\.py\b|\.gd\b|\bdata/|HomeAI|Robert[,:']|godot_|\(Claude|\bDev's writing", s): return False
    if s in SKIP_VALUES or s in have: return False
    if not re.search(r"[A-Za-z]{2}", s): return False
    if re.fullmatch(r"[a-z0-9_@.\-/]+", s): return False   # an id / path
    return True
def walk(o, f, k=None):
    if isinstance(o, dict):
        for kk, v in o.items(): walk(v, f, kk)
    elif isinstance(o, list):
        for v in o: walk(v, f, k)
    elif isinstance(o, str) and k not in NOTEXT and ok(o) and looks_text(o):
        found.setdefault(o, (k, f))
for p in sorted(glob.glob("data/*.json") + glob.glob("data/drafts/*.json")):
    fn = os.path.basename(p)
    if fn in SKIP_FILES: continue
    try: walk(json.load(open(p, encoding="utf8")), fn)
    except Exception as e: print("skip", fn, e)
# words the game builds in code: I18n.t("...") literals (GDScript escapes undone)
code = {}
def unesc(x):
    return re.sub(r'\\(n|t|"|\\)', lambda m: {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}[m.group(1)], x)
for p in glob.glob("scripts/**/*.gd", recursive=True):
    for m in re.finditer(r'I18n\.t\("((?:[^"\\\n]|\\.)*)"\)', open(p, encoding="utf8").read()):
        k = unesc(m.group(1))
        if k not in have and k not in found: code.setdefault(k, p)
gd = {}
CONSTRX = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
for p in glob.glob("scripts/**/*.gd", recursive=True):
    depth = 0; skipping = False
    for ln in open(p, encoding="utf8").read().split("\n"):
        if skipping or re.match(r"\s*(const|static var)\b", ln):
            for m in CONSTRX.finditer(ln.split("#")[0]):
                k = unesc(m.group(1))
                if k not in have and k not in found and k not in code and re.search(r"[A-Za-z]{3}", k) and looks_text(k) and not re.fullmatch(r"[A-Za-z0-9_@.\-/:%]+", k) or (k not in have and k not in found and k not in code and re.fullmatch(r"[A-Z][a-z]{3,}( [A-Za-z\-']+)*", k)):
                    gd.setdefault(k, p)
            c2 = CONSTRX.sub('""', ln.split("#")[0])
            depth += c2.count("[") + c2.count("{") + c2.count("(") - c2.count("]") - c2.count("}") - c2.count(")")
            skipping = depth > 0
            if not skipping: depth = 0
# every capitalised phrase the scripts contain (shown through a Label as it stands, or filled in with % first and matched as a template)
LITX = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
for p in glob.glob("scripts/**/*.gd", recursive=True):
    if ".bak" in p: continue
    for ln in open(p, encoding="utf8").read().split("\n"):
        cd = ln.split(" # ")[0] if " # " in ln else ln
        if cd.strip().startswith("#"): continue
        for m in LITX.finditer(cd):
            k = unesc(m.group(1))
            if k in have or k in found or k in code or k in gd: continue
            if len(k) < 4 or "res://" in k or "user://" in k or re.search(r"\.(json|gd|png|tscn|ogg|wav|cfg|txt|glb|tres)\b", k): continue
            if re.search(r"[a-z][A-Z]", k) and " " not in k: continue
            if not re.match(r"[A-Z\"'(\[\-+\d%]", k): continue
            if re.fullmatch(r"[A-Za-z0-9_@.\-/:%#+*]+", k) and not re.fullmatch(r"[A-Z][a-z]{3,}", k): continue
            if not re.search(r"[A-Za-z]{3}", k) or (k.isupper() and " " not in k): continue
            gd[k] = p
tiers = {"A": [], "B": [], "C": [], "S": []}
for k in gd: code.setdefault(k, gd[k])
tiers["S"] = sorted(code)
for s, (k, f) in list(found.items()):
    t = "A" if k in NAMEK or len(s) <= 40 else ("B" if len(s) <= 160 else "C")
    tiers[t].append(s)
for fn in glob.glob("tools/i18n/todo/*.json"): os.remove(fn)
tot = 0
for t, arr in tiers.items():
    if t != "S": arr.sort(key=lambda s: (found[s][1], s))
    cur, size, n = [], 0, 0
    def flush():
        global cur, size, n
        if cur:
            n += 1
            json.dump(cur, open("tools/i18n/todo/%s%02d.json" % (t, n), "w", encoding="utf8"), ensure_ascii=False, indent=0)
        cur, size = [], 0
    for s in arr:
        cur.append(s); size += len(s)
        if size >= 7000 or len(cur) >= 220: flush()
    flush()
    print(t, len(arr), "strings", sum(len(s) for s in arr), "chars")
