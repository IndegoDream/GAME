#!/usr/bin/env python3
"""Round 141: wrap the English words the game builds on screen in I18n.t("...") so they join the catalog.
Dry run by default (python3 tools/i18n_wrap.py), --apply writes (and keeps a .bak-claude-i18n-20261017 beside every file changed).
Only literals in places that end up on screen are touched (text assignments, label/button helpers, parts.append, return of a phrase...)."""
import re, sys, glob, os, shutil, json
APPLY = "--apply" in sys.argv
FILES = [a for a in sys.argv[1:] if not a.startswith("--")] or (
    ["scripts/core/Game.gd", "scripts/ui/Hub.gd", "scripts/ui/HUD.gd", "scripts/core/Kit.gd"] + sorted(glob.glob("scripts/systems/*.gd")) +
    sorted(glob.glob("scripts/actors/*.gd")) + sorted(glob.glob("scripts/world/*.gd")) + sorted(glob.glob("scripts/net/*.gd")))
LIT = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
# a line is "on screen" if it carries one of these
CTX = re.compile(r'(\.text\s*=|\btext\s*=|\.append\(|_say\(|_label\(|_btn\(|\bnote\(|\btoast\(|\bpopup\(|_hint\(|\.tooltip_text\s*=|\btitle\s*=|\bhead\(|_head\(|_title\(|\bshow_message\(|\bflash\(|\bsay\(|\breturn\s+("|\()|\+=\s*"|\+\s*"|"\s*\+|%\s*\[)')
SKIP_LINE = re.compile(r'^\s*(#|match |const |@export|signal |class_name|extends|func .*-> .*:\s*$)')
EXC = set(json.load(open('tools/i18n/exclude_wrap.json', encoding='utf8')))
def worthy(s: str) -> bool:
    if s in EXC: return False
    if len(s) < 3: return False
    if "res://" in s or "user://" in s or ".json" in s or ".gd" in s or ".png" in s or ".tscn" in s: return False
    if re.fullmatch(r"[a-z0-9_@.\-:/#%+]+", s): return False        # ids, keys, formats
    if not re.search(r"[A-Za-z]{3}", s): return False
    if not (" " in s or re.match(r"[A-Z][a-z]{3,}", s)): return False   # one lowercase word is probably an id
    if re.fullmatch(r"[A-Z0-9_]+", s): return False                  # constants
    return True
def wrapped_already(line, start):
    pre = line[:start]
    return pre.endswith("tr(") or pre.endswith("I18n.t(") or pre.endswith("atr(") or pre.endswith("translate(")
total = 0; per = {}
for f in FILES:
    if not os.path.exists(f): continue
    src = open(f, encoding="utf8").read().split("\n")
    out = []; ch = 0; depth = 0; skipping = False
    for ln in src:
        # a const / static var initialiser that runs over several lines is not run-time text: leave it be
        if skipping or re.match(r"\s*(const|static var|@export|@onready)\b", ln):
            code = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', ln.split("#")[0])
            depth += code.count("[") + code.count("{") + code.count("(") - code.count("]") - code.count("}") - code.count(")")
            skipping = depth > 0
            if not skipping: depth = 0
            out.append(ln); continue
        if SKIP_LINE.match(ln) or not CTX.search(ln):
            out.append(ln); continue
        # do not touch dictionary keys / comparisons / match arms on the same line
        new = []; pos = 0
        for m in LIT.finditer(ln):
            s = m.group(1)
            a, b = m.span()
            after = ln[b:b + 3]
            before = ln[:a].rstrip()
            if (not worthy(s) or wrapped_already(ln, a) or after.lstrip().startswith(":") or before.endswith(("==", "!=", "in", "get(", "has(", "get_node(", "load(", "preload(", "[", "emit_signal(", "call(", "call_deferred(", "has_method(", "connect(", "set(", "begins_with(", "ends_with(", "contains(", "find(", "split(", "replace(", "join(", "str_to_var(", "StringName(", "&"))
                    or ln[b:b + 1] == "]"):
                continue
            new.append((a, b, s))
        if not new:
            out.append(ln); continue
        for a, b, s in reversed(new):
            ln = ln[:a] + 'I18n.t("' + s + '")' + ln[b:]
            ch += 1
        out.append(ln)
    if ch:
        per[f] = ch; total += ch
        if APPLY:
            shutil.copy(f, f + ".bak-claude-i18n-20261017")
            open(f, "w", encoding="utf8").write("\n".join(out))
print("literals wrapped%s: %d in %d files" % ("" if APPLY else " (dry run)", total, len(per)))
for f, c in sorted(per.items(), key=lambda x: -x[1])[:25]: print("  %5d %s" % (c, f))
