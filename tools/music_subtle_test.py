#!/usr/bin/env python3
"""Round 183c: the refined pieces really are more subtle than the full ones -- quieter, shorter, and a settings file
saved before the change moves to them once (Gfx.load_settings)."""
import os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
A = os.path.join(os.path.dirname(HERE), "assets", "audio")
ok = fail = 0
def check(n, c, d=""):
    global ok, fail
    if c: ok += 1
    else:
        fail += 1; print("  FAIL  " + n + ("  [" + str(d) + "]" if d else ""))
def lufs_secs(p):
    e = subprocess.run(["ffmpeg", "-i", p, "-af", "ebur128", "-f", "null", "-"], capture_output=True, text=True).stderr
    i = float([l for l in e.splitlines() if l.strip().startswith("I:")][-1].split()[1])
    m = re.search(r"Duration: (\d+):(\d+):([\d.]+)", e)
    return i, int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))
names = sorted(f[:-4] for f in os.listdir(os.path.join(A, "music2_new")) if f.endswith(".ogg"))
check("19 pieces in each style", len(names) == 19 and all(os.path.exists(os.path.join(A, "music3_subtle", n + ".ogg")) for n in names))
quieter = shorter = 0
for n in names:
    lf, sf = lufs_secs(os.path.join(A, "music2_new", n + ".ogg"))
    ls, ss = lufs_secs(os.path.join(A, "music3_subtle", n + ".ogg"))
    quieter += ls <= lf - 2.5
    shorter += ss < sf * 0.8
    check("%s: refined is no louder than -20 LUFS" % n, ls <= -20.0, ls)
check("every refined piece at least 2.5 LU quieter than the full one (%d/19)" % quieter, quieter == 19)
check("every refined piece clearly shorter (%d/19)" % shorter, shorter == 19)
g = open(os.path.join(os.path.dirname(HERE), "scripts", "core", "Gfx.gd")).read()
check("an old settings file moves to the refined pieces once", '"music_v": "1"' in g and 'settings["music_style"] = "subtle"' in g and 'settings["music_v"] = "2"' in g)
check("the fuller styles stay selectable", '["subtle", "new", "original", "classic"]' in g)
print("MUSIC SUBTLE TEST %d passed, %d failed" % (ok, fail))
sys.exit(1 if fail else 0)
