#!/usr/bin/env python3
"""Round 182: bring a reviewed workbook (tools/i18n/review_export.py) back into the game.

  python3 tools/i18n/review_import.py <reviewed.xlsx> [zh_CN] [--dry]

  - Strings sheet: every filled 'Correction' becomes an override (tools/i18n/override/<code>.json)
  - Glossary sheet: a filled 'Your choice' replaces the old word everywhere it was used for that English word
    (only in strings whose English contains the word, and never over a string the reviewer corrected by hand)
  - placeholders (%d, %s, {name}) must survive, or the row is refused and listed
Then rebuild the catalogs:  python3 tools/build_i18n.py
"""
import json, os, re, sys
from openpyxl import load_workbook

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
PH = r"%[+\-0-9.]*[sdf]|\{[a-z0-9_]+\}"


def same_ph(a, b):
    return sorted(re.findall(PH, a)) == sorted(re.findall(PH, b)) and a.count("\\n") + a.count("\n") == b.count("\\n") + b.count("\n")


def main(argv):
    dry = "--dry" in argv
    argv = [a for a in argv if a != "--dry"]
    if not argv:
        print(__doc__)
        return 2
    path = argv[0]
    code = argv[1] if len(argv) > 1 else "zh_CN"
    cat = json.load(open(os.path.join(GAME, "data", "i18n", code + ".json"), encoding="utf8"))
    ov_path = os.path.join(os.environ.get("REVIEW_OVERRIDE_DIR", os.path.join(GAME, "tools", "i18n", "override")), code + ".json")
    ov = json.load(open(ov_path, encoding="utf8")) if os.path.exists(ov_path) else {}
    wb = load_workbook(path)
    refused = []
    hand = {}
    s = wb["Strings"]
    for row in s.iter_rows(min_row=2, values_only=True):
        en, fix = row[2], row[4]
        if en is None or fix is None or str(fix).strip() == "":
            continue
        en, fix = str(en), str(fix).strip()
        if not same_ph(en, fix):
            refused.append(("string", en[:60], "placeholders or line breaks differ"))
            continue
        hand[en] = fix
    swaps = []
    g = wb["Glossary"]
    for row in g.iter_rows(min_row=2, values_only=True):
        en, cur, choice = row[0], row[1], row[5]
        if en is None or choice is None or str(choice).strip() == "":
            continue
        en, choice = str(en), str(choice).strip()
        cur = str(cur or "")
        if "/" in choice:
            refused.append(("glossary", en, "pick one term (got '%s')" % choice))
            continue
        swaps.append((en, cur, choice))
    auto = {}
    for en, cur, choice in swaps:
        auto[en] = choice
        if cur == "" or cur == choice:
            continue
        pat = re.compile(r"\b" + re.escape(en) + r"\b", re.I)
        for k, v in cat.items():
            if k in hand or not pat.search(k):
                continue
            base = auto.get(k, ov.get(k, v))
            if cur in base:
                auto[k] = base.replace(cur, choice)
    changed = {}
    for k, v in auto.items():
        if same_ph(k, v):
            changed[k] = v
        else:
            refused.append(("glossary", k[:60], "placeholders differ after the swap"))
    changed.update(hand)
    print("REVIEW IMPORT %s: %d hand corrections, %d glossary choices -> %d strings changed by the glossary, %d refused" % (
        code, len(hand), len(swaps), len(changed) - len(hand), len(refused)))
    for r in refused[:40]:
        print("  refused  %s: %s  (%s)" % r)
    if dry:
        return 0
    ov.update(changed)
    os.makedirs(os.path.dirname(ov_path), exist_ok=True)
    with open(ov_path, "w", encoding="utf8") as f:
        json.dump(dict(sorted(ov.items())), f, ensure_ascii=False, indent=0)
    print("wrote %s (%d overrides). Now run: python3 tools/build_i18n.py" % (ov_path, len(ov)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
