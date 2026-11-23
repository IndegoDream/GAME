#!/usr/bin/env python3
"""validate an auto_*.json: every key -> list of 9 non-empty strings, same printf placeholders (in order) as the key."""
import json, re, sys
ph = re.compile(r'%(?:\.\d+)?[sdfi]|%%')
bad = 0
for path in sys.argv[1:]:
    d = json.load(open(path))
    for k, v in d.items():
        if not isinstance(v, list) or len(v) != 9 or any((not isinstance(x, str)) or not x.strip() for x in v):
            print("BAD SHAPE", path, k[:60]); bad += 1; continue
        want = ph.findall(k)
        for i, x in enumerate(v):
            if ph.findall(x) != want:
                print("BAD PLACEHOLDERS", path, i, k[:50], '->', x[:50]); bad += 1
    print(path, len(d), "entries")
print("PROBLEMS", bad)
sys.exit(1 if bad else 0)
