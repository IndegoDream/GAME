#!/usr/bin/env python3
"""Round 182: read opt-in play stats and show where balance hurts.

  python3 tools/stats_report.py FILE_OR_DIR [...]   [--csv out.csv]

Takes any mix of:
  - playstats.jsonl files from a device (user://playstats.jsonl: one row per line), install = the file name
  - a JSON or CSV export of the Supabase play_stats table (columns install, data)

Per floor: players who reached it, falls there, falls per player, bosses beaten, sittings that ended there,
players whose furthest floor it is (where people stop), and the median minutes played when first reaching it.
A floor is flagged when its falls per player jump by more than half over the floor before, or when more than a
quarter of the players who reached it stopped there.
"""
import csv, json, os, statistics, sys
from collections import defaultdict


def rows_from(path):
    name = os.path.basename(path)
    if path.endswith(".jsonl"):
        with open(path, encoding="utf-8") as f:
            for ln in f:
                ln = ln.strip()
                if ln:
                    try:
                        r = json.loads(ln)
                    except ValueError:
                        continue
                    if isinstance(r, dict) and "data" in r:
                        yield str(r.get("install", name)), r["data"]
                    elif isinstance(r, dict):
                        yield name, r
    elif path.endswith(".json"):
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
        for r in d if isinstance(d, list) else d.get("rows", []):
            data = r.get("data")
            if isinstance(data, str):
                data = json.loads(data)
            if isinstance(data, dict):
                yield str(r.get("install", name)), data
    elif path.endswith(".csv"):
        with open(path, encoding="utf-8", newline="") as f:
            for r in csv.DictReader(f):
                try:
                    data = json.loads(r.get("data") or "{}")
                except ValueError:
                    continue
                if isinstance(data, dict):
                    yield str(r.get("install", name)), data


def gather(args):
    files = []
    for a in args:
        if os.path.isdir(a):
            for fn in sorted(os.listdir(a)):
                if fn.endswith((".jsonl", ".json", ".csv")):
                    files.append(os.path.join(a, fn))
        elif os.path.exists(a):
            files.append(a)
    out = []
    for p in files:
        out.extend(rows_from(p))
    return out


def report(rows):
    reach = defaultdict(set)          # floor -> installs
    first_min = defaultdict(dict)     # floor -> install -> minutes when first reached
    falls = defaultdict(int)
    bosses = defaultdict(int)
    ends = defaultdict(int)
    furthest = {}
    causes = defaultdict(lambda: defaultdict(int))
    for inst, r in rows:
        k = str(r.get("k", ""))
        f = int(r.get("f", 0) or 0)
        if f <= 0:
            continue
        m = int(r.get("m", 0) or 0)
        if k == "enter_level":
            reach[f].add(inst)
            if inst not in first_min[f] or m < first_min[f][inst]:
                first_min[f][inst] = m
            furthest[inst] = max(furthest.get(inst, 0), f)
        elif k == "death":
            falls[f] += 1
            reach[f].add(inst)
            causes[f][str(r.get("cause", "?")) or "?"] += 1
        elif k == "boss_kill":
            bosses[f] += 1
        elif k == "session_end":
            ends[f] += 1
    stop = defaultdict(int)
    for inst, f in furthest.items():
        stop[f] += 1
    floors = sorted(set(reach) | set(falls) | set(bosses))
    table = []
    prev = None
    for f in floors:
        n = len(reach[f])
        fpp = falls[f] / n if n else 0.0
        mins = list(first_min[f].values())
        top = sorted(causes[f].items(), key=lambda x: -x[1])[:2]
        flags = []
        if prev is not None and prev > 0 and fpp > prev * 1.5 and falls[f] >= 3:
            flags.append("falls jump")
        if n >= 4 and stop[f] / n > 0.25 and f != max(floors):
            flags.append("players stop here")
        table.append({"floor": f, "players": n, "falls": falls[f], "falls_per_player": round(fpp, 2), "bosses_beaten": bosses[f],
                      "sittings_ended": ends[f], "furthest_for": stop[f], "median_min_to_reach": int(statistics.median(mins)) if mins else None,
                      "top_causes": ", ".join("%s x%d" % c for c in top), "flags": "; ".join(flags)})
        prev = fpp
    return table


def main(argv):
    out_csv = None
    if "--csv" in argv:
        i = argv.index("--csv")
        out_csv = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    if not argv:
        print(__doc__)
        return 2
    rows = gather(argv)
    installs = {i for i, _ in rows}
    table = report(rows)
    print("PLAY STATS: %d rows from %d players, %d floors" % (len(rows), len(installs), len(table)))
    print("%5s %7s %6s %8s %6s %6s %6s %8s  %s" % ("floor", "players", "falls", "per-plyr", "bosses", "ended", "stop", "min-in", "flags / top causes"))
    for t in table:
        print("%5d %7d %6d %8.2f %6d %6d %6d %8s  %s%s" % (t["floor"], t["players"], t["falls"], t["falls_per_player"], t["bosses_beaten"],
              t["sittings_ended"], t["furthest_for"], t["median_min_to_reach"] if t["median_min_to_reach"] is not None else "-",
              ("[" + t["flags"] + "] ") if t["flags"] else "", t["top_causes"]))
    flagged = [t for t in table if t["flags"]]
    print("STATS REPORT DONE %d floors, %d flagged" % (len(table), len(flagged)))
    if out_csv:
        with open(out_csv, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(table[0].keys()) if table else ["floor"])
            w.writeheader()
            w.writerows(table)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
