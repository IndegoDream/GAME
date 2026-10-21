#!/usr/bin/env python3
"""Safe drop-in update.  Usage:
   python tools/apply_update.py <new_project_folder_or_zip> [--target <project folder>] [--godot <path to godot exe>] [--force-flavor]
   python tools/apply_update.py --rollback <_replaced_YYYYmmdd_HHMMSS folder> [--target <project folder>]
Does: (1) checks the new package really is this game, (2) copies every file it is about to overwrite into _replaced_<time>/ (exact paths),
(3) copies the new files in (never deletes anything that is not in the package), (4) if --godot is given, compiles every script and
runs the data/level checks; if anything fails it rolls back by itself.  Saves/settings live outside the project (user://) and are never touched."""
import os, sys, shutil, zipfile, time, subprocess, tempfile, json, argparse

REQUIRED = ["project.godot", "Main.tscn", "Main.gd", "scripts/core/Game.gd", "scripts/core/MemLog.gd", "data/items.json", "data/enemies.json", "levels/village.json"]
KEEP_LOCAL = {"data/build_flavor.json"}          # not overwritten unless --force-flavor (decides clean vs test build)
SKIP = (".git/", ".godot/", "build/", "_replaced_", ".backups/", "__pycache__/")

def die(m): print("STOP:", m); sys.exit(1)

def walk(root):
    for d, ds, fs in os.walk(root):
        for f in fs:
            p = os.path.join(d, f); rel = os.path.relpath(p, root).replace("\\", "/")
            if any(rel.startswith(s) or ("/" + s) in "/" + rel for s in SKIP) or f.endswith(".bak") or ".bak-" in f: continue
            yield rel

def restore(rep, target):
    n = 0
    for rel in walk(rep):
        if rel == "_NEW_FILES.txt": continue
        dst = os.path.join(target, rel); os.makedirs(os.path.dirname(dst), exist_ok=True); shutil.copy2(os.path.join(rep, rel), dst); n += 1
    nf = os.path.join(rep, "_NEW_FILES.txt")
    if os.path.exists(nf):
        for rel in open(nf).read().split("\n"):
            if rel.strip() and os.path.exists(os.path.join(target, rel)): os.remove(os.path.join(target, rel))
    print("rolled back %d files" % n)

ap = argparse.ArgumentParser(); ap.add_argument("src", nargs="?"); ap.add_argument("--target", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ap.add_argument("--godot"); ap.add_argument("--rollback"); ap.add_argument("--force-flavor", action="store_true"); a = ap.parse_args()
target = os.path.abspath(a.target)
if a.rollback: restore(os.path.abspath(a.rollback), target); sys.exit(0)
if not a.src: die("give the new folder or zip")
src = os.path.abspath(a.src); tmp = None
if zipfile.is_zipfile(src):
    tmp = tempfile.mkdtemp(prefix="dce_new_"); print("unzipping..."); zipfile.ZipFile(src).extractall(tmp); src = tmp
    kids = [k for k in os.listdir(src)]
    if "project.godot" not in kids and len(kids) == 1 and os.path.isdir(os.path.join(src, kids[0])): src = os.path.join(src, kids[0])
for r in REQUIRED:
    if not os.path.exists(os.path.join(src, r)): die("new package is missing %s -- not applying (nothing changed)" % r)
pg = open(os.path.join(src, "project.godot"), encoding="utf8").read()
for need in ('Game="*res://scripts/core/Game.gd"', 'MemLog="*res://scripts/core/MemLog.gd"'):
    if need not in pg: die("autoload line missing in new project.godot: %s -- Seele changed the engine entry points; not applying" % need)
stamp = time.strftime("%Y%m%d_%H%M%S"); rep = os.path.join(target, "_replaced_" + stamp); newfiles = []; changed = 0
for rel in walk(src):
    if rel in KEEP_LOCAL and not a.force_flavor: continue
    s = os.path.join(src, rel); d = os.path.join(target, rel)
    if os.path.exists(d):
        if open(s, "rb").read() == open(d, "rb").read(): continue
        os.makedirs(os.path.dirname(os.path.join(rep, rel)), exist_ok=True); shutil.copy2(d, os.path.join(rep, rel))
    else: newfiles.append(rel)
    os.makedirs(os.path.dirname(d), exist_ok=True); shutil.copy2(s, d); changed += 1
os.makedirs(rep, exist_ok=True); open(os.path.join(rep, "_NEW_FILES.txt"), "w").write("\n".join(newfiles))
print("updated %d files (%d new). Old copies are in %s" % (changed, len(newfiles), rep))
ok = True
if a.godot:
    for cmd in (["res://tools/compile_all.gd"], ["res://tools/smoke.gd"]):
        r = subprocess.run([a.godot, "--headless", "--path", target, "--script"] + cmd, capture_output=True, text=True)
        out = r.stdout + r.stderr; print(cmd[0], "->", [l for l in out.split("\n") if "failed" in l or "COMPILE" in l or "SMOKE" in l][-1:])
        if r.returncode != 0 or "SCRIPT ERROR" in out or "Parse Error" in out or any((" %d failed" % i) in out for i in range(1, 1000)): ok = False
    if not ok: print("CHECKS FAILED -> rolling back"); restore(rep, target); sys.exit(2)
    print("checks passed")
else: print("(no --godot given: checks skipped. Open the project once in Godot and run tools/release_gate.sh.)")
if tmp: shutil.rmtree(tmp, ignore_errors=True)
print("DONE. To undo: python tools/apply_update.py --rollback \"%s\"" % rep)
