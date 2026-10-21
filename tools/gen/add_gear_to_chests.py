#!/usr/bin/env python3
"""Floors 1-9: the best chest on each floor (in the secret room, or the
richest one) also holds a piece of gear rolled for that floor. Idempotent."""
import json, os, sys
GAME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def best_chest(d):
    lay = d.get("layout") or {}
    secret = set()
    for r in lay.get("rooms") or []:
        if r.get("secret"):
            secret |= {str(i)[:1] for i in r.get("has") or []}
    chests = d.get("chests") or {}
    in_secret = [k for k in chests if k in secret]
    if in_secret:
        return in_secret[0]
    return max(chests, key=lambda k: max((v[1] if isinstance(v, list) else v) for v in chests[k]["loot"].values())) if chests else None


def main(homeai):
    sys.path.insert(0, homeai)
    import godot_levels as GL
    for n in range(1, 10):
        p = os.path.join(GAME, "levels", f"floor{n}.json")
        d = json.load(open(p))
        if d.get("theme") != "dungeon":
            continue
        k = best_chest(d)
        if not k:
            continue
        d["chests"][k]["loot"]["random_gear"] = [1, 1]
        text = json.dumps(d, indent=2) + "\n"
        if "layout" in d:
            src = GL.authoring_text(text)
            text, _ = GL.normalize_text(src, f"floor{n}.json")
        r = GL.validate_text(text, GAME, f"floor{n}.json")
        print(f"floor{n}: chest {k} +random_gear ok={r['ok']} {r['errors'][:2]}")
        if r["ok"]:
            open(p, "w").write(text)


if __name__ == "__main__":
    main(sys.argv[1])
