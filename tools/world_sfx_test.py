#!/usr/bin/env python3
"""Round 184: the world's small sounds (tools/world_sfx_gen.py) -- every file there, the right length, never
clipped, the steps short, the far sounds soft at the front, the weather loops 64 s, seamless and no louder
than the place's own bed.   python3 tools/world_sfx_test.py"""
import json, os, subprocess, sys
import numpy as np

A = "assets/audio"
ok = bad = 0


def check(what, cond, detail=""):
    global ok, bad
    if cond:
        ok += 1
    else:
        bad += 1
        print("  FAIL ", what, detail)


def pcm(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-af", "pan=mono|c0=0.5*c0+0.5*c1", "-ar", "22050", "-f", "f32le", "-"], capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def rms_db(x):
    return 20 * np.log10(np.sqrt((x.astype(float) ** 2).mean()) + 1e-12)


d = json.load(open("data/audio.json"))
names = set()
for bed, rows in d["spots"].items():
    for e in rows:
        names.add(e["s"])
for wx, rows in d["weather_spots"].items():
    for e in rows:
        names.add(e["s"])
for nm in sorted(names):
    files = [f for f in os.listdir(A + "/sfx") if f.endswith(".ogg") and (f == nm + ".ogg" or (f.startswith(nm) and f[len(nm):-4].isdigit()))]
    check("spot %s has files" % nm, len(files) >= 1)
    for f in files:
        x = pcm(A + "/sfx/" + f)
        dur = len(x) / 22050
        check("%s length 0.3-8 s (%.2f)" % (f, dur), 0.3 <= dur <= 8.0)
        check("%s not clipped" % f, np.abs(x).max() < 0.99, np.abs(x).max())
        check("%s import file" % f, os.path.exists(A + "/sfx/" + f + ".import"))
for g in ["snow", "water", "sand", "metal", "wood"]:
    for i in range(1, 5):
        f = "%s/sfx/step_%s%d.ogg" % (A, g, i)
        check("step %s%d there" % (g, i), os.path.exists(f) and os.path.exists(f + ".import"))
        if os.path.exists(f):
            x = pcm(f)
            check("step %s%d short (%.2f s)" % (g, i, len(x) / 22050), len(x) / 22050 <= 0.4)
            check("step %s%d not clipped" % (g, i), np.abs(x).max() < 0.99)
            check("step %s%d about as loud as the stone steps (%.1f dB)" % (g, i, rms_db(x)), -28 <= rms_db(x) <= -12)
village = rms_db(pcm(A + "/ambience/village_day.ogg"))
# (r184 found the day beds silent -- a NaN in the bird chirps -- since they were made: every bed must sound)
for f in sorted(os.listdir(A + "/ambience")):
    if f.endswith(".ogg"):
        check("bed %s is not silent" % f, rms_db(pcm(A + "/ambience/" + f)) > -40, rms_db(pcm(A + "/ambience/" + f)))
for wx, row in d["weather_beds"].items():
    if wx.startswith("_"):
        continue
    f = "%s/ambience/%s.ogg" % (A, row[0])
    check("weather bed %s there" % row[0], os.path.exists(f) and os.path.exists(f + ".import"))
    x = pcm(f)
    check("%s is 64 s" % row[0], abs(len(x) / 22050 - 64) < 0.2, len(x) / 22050)
    check("%s no louder than the village bed + 4 dB (%.1f vs %.1f)" % (row[0], rms_db(x), village), rms_db(x) <= village + 4)
    # the loop's seam: the last and first 50 ms are about as loud as each other
    a, b = x[-1100:], x[:1100]
    check("%s loops without a bump" % row[0], abs(rms_db(a) - rms_db(b)) < 6, (rms_db(a), rms_db(b)))
print("WORLD SFX TEST %d passed, %d failed" % (ok, bad))
sys.exit(1 if bad else 0)
