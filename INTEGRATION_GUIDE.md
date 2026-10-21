# How everything connects (the do-not-break list)
Give this to Seele AND Dev. Anything on this list must keep working after an upgrade.

## 1. Entry points (Godot)
- Main scene `res://Main.tscn` + `Main.gd`. Two autoloads in project.godot, exact names: `Game` = scripts/core/Game.gd, `MemLog` = scripts/core/MemLog.gd. Hundreds of scripts call `Game.xxx`; never rename/remove them or their public functions/signals.
- Game systems are registered in Game.gd (`sys("tester")`, `sys(...)` list near the end of Game.gd). Add systems, don't renumber.
- Godot 4.6.3 only. Keep Forward+ on PC, Compatibility on mobile (project.godot renderer settings).

## 2. Content is DATA (JSON). The engine reads it by file name and key
- `levels/<id>.json` (village, floor1..floor50, writing_room, ...): text map + monsters/chests/exits. Validated by Dev's `godot_levels.py` (every map char defined, everything reachable).
- `data/*.json` (items, enemies, recipes, quests, techniques, arts, balance, economy, dao, breeding, ...): keys are read by name. You may change numbers and add entries; do NOT rename existing ids/keys (saves and the online server reference them).
- `data/i18n/*.json` (10 languages) built from `tools/i18n/`; new text must use `tr()`/`I18n.t()`; rebuild with `python tools/build_i18n.py`.
- `data/build_info.json` (build number) and `data/build_flavor.json` {"clean": true} = release build with the test kit OFF. Keep clean=true for anything shipped. `godot-meta.json` is Dev's version ledger -- leave it.

## 3. Saves and the player's computer (outside the project, never touched by updates)
- `user://save*.json` (slots, `<save_base>_account.json`), `settings.json`, `controls.json`, `playlog.jsonl`, `crumbs.txt`, `memlog.json`. Do not change save key names without a migration function (see `migrate_to_slots` in Game.gd).
- Input actions are defined in code (Game.gd ~line 2150-2190) and shown by Controls.gd; players can rebind them. Keep action names (`vault_dump` excluded in clean builds).

## 4. Things on the other side of the wall
- Online world: `tools/server/elite_server.py` (+ `engine.py`). The client sends/receives the same data files; a hash of `data/` is checked (`tools/foundation_check.gd`). If you change data/ the server must be redeployed with the same data. Do not touch `tools/server/elite.db`.
- Supabase / cloud save / accounts: `scripts/core/CloudSave.gd`, `scripts/net/*` -- keep request/response shapes.
- Steam (`scripts/core/SteamLink.gd`, `steam/`) and Google Play/AdMob (`Ads.gd`, `AdMobBridge.gd`, `Store.gd`): keep the function names; the store flavour is chosen by export features (`play`, `steam`, `demo`).
- Dev (the HomeAI box AI) edits levels/data through Godot Studio, builds, signs APKs and makes store kits (`godot_retail.py`) from this folder.

## 5. Rules of the design
- Fair pay: paid things are convenience/cosmetic only, never power. No cheats in shipped builds.
- Phone and PC get the same features. Touch UI (`TouchUI`) and menu fit (`Hub._fit`, `Gfx.fit_small_window`) must keep every menu usable on small screens.

## 5b. Phone
The phone keeps the basic "low" look and a strict speed/memory budget -- see PHONE_RULES.md. Gfx.gd quality tiers decide this; do not change which tier the phone uses.

## 6. Proof it still works (run before handing back)
`GODOT=<godot 4.6.3> bash tools/release_gate.sh` -- every line must pass (compile_all, smoke over all levels, ~100 checks, server tests).
Quick check: `godot --headless --path . --script res://tools/compile_all.gd` (0 failed) and `res://tools/smoke.gd`.

## 7. Applying the result safely (Robert)
Drag Seele's returned zip onto `APPLY_UPDATE.bat` (or `python tools/apply_update.py new.zip`). It refuses a package missing the core files or autoloads, backs up every file it replaces into `_replaced_<time>/`, never deletes anything, keeps your clean/test flavour setting, and (with GODOT set) compiles + smoke-tests and rolls back by itself on any failure. Undo anytime: `python tools/apply_update.py --rollback _replaced_<time>`.
