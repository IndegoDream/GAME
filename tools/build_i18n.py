#!/usr/bin/env python3
"""Round 140: build data/i18n/<code>.json from tools/i18n/part*.txt (rows: English||zh_CN||es||pt_BR||ru||de||fr||ja||ko||tr).
Auto-translate: every Label/Button whose text equals an English key shows the translation; anything missing stays English.
Checks every row has all nine and that %d/%s placeholders survive. Run from the game folder: python3 tools/build_i18n.py"""
import glob, json, os, re, sys
PH = r"%[+\-0-9.]*[sdf]|\{[a-z0-9_]+\}"
LANGS = ["zh_CN", "es", "pt_BR", "ru", "de", "fr", "ja", "ko", "tr"]
cat = {l: {} for l in LANGS}
bad = 0
n = 0
for f in sorted(glob.glob("tools/i18n/part*.txt")):
    for ln, line in enumerate(open(f, encoding="utf8").read().split("\n"), 1):
        if not line.strip():
            continue
        parts = line.split("||")
        if len(parts) != 10:
            print("%s:%d has %d fields: %s" % (f, ln, len(parts), line[:60])); bad += 1; continue
        en = parts[0]
        ph = sorted(re.findall(PH, en))
        for l, t in zip(LANGS, parts[1:]):
            if sorted(re.findall(PH, t)) != ph:
                print("%s:%d placeholders differ in %s: %s" % (f, ln, l, en[:50])); bad += 1
            if t.strip() == "":
                print("%s:%d empty %s" % (f, ln, l)); bad += 1
            cat[l][en] = t
        n += 1
# Round 141: names, descriptions and story, translated in bulk (tools/i18n_extract.py lists what is missing): {english: [nine translations]}
for f in sorted(glob.glob("tools/i18n/auto/*.json")):
    d = json.load(open(f, encoding="utf8"))
    for en, row in d.items():
        if len(row) != 9:
            print("%s: %d translations for %s" % (f, len(row), en[:40])); bad += 1; continue
        ph = sorted(re.findall(PH, en))
        for l, t in zip(LANGS, row):
            if sorted(re.findall(PH, t)) != ph or t.strip() == "":
                print("%s: placeholder/empty in %s: %s" % (f, l, en[:40])); bad += 1
            if en not in cat[l]:
                cat[l][en] = t
        n += 1
# per-language corrections applied last: tools/i18n/override/<code>.json {english: translation}
for l in LANGS:
    f = "tools/i18n/override/%s.json" % l
    if os.path.exists(f):
        for en, t in json.load(open(f, encoding="utf8")).items():
            if sorted(re.findall(PH, en)) != sorted(re.findall(PH, t)):
                print("override placeholders differ:", l, en[:40]); bad += 1
            else:
                cat[l][en] = t
os.makedirs("data/i18n", exist_ok=True)
for l in LANGS:
    json.dump(cat[l], open("data/i18n/%s.json" % l, "w", encoding="utf8"), ensure_ascii=False, indent=0)
print("rows", n, "languages", len(LANGS), "problems", bad)
sys.exit(1 if bad else 0)
