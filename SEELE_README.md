# Dungeon Crawl Elite -- package for Seele (polish pass, November 2026)

**What it is:** a 3D cultivation dungeon crawler in Godot 4.6.3 (GDScript). PC (Forward+) and Android (Compatibility) from one
project. Eliet Village, the valley, ten lands, 50 floors, cultivation, crafting, companions, guilds and sects, 10 languages.
Version 0.64.0. This is the CLEAN build: no test kit, no god mode (data/build_flavor.json {"clean": true}).

**Open:** project.godot in Godot 4.6.3. Main scene Main.tscn. The base you receive is git commit noted in BASE_COMMIT.txt.

## The rule for this pass: FEATURE FREEZE
The Steam demo goes to Steam Next Fest (Feb 22, 2027) and Google Play launches from mid-January. Until demo players report
back, the game takes **bug fixes, speed, balance, wording and visual polish only -- no new systems, no new content.**

## What we want from you, in order
1. **PC frame rate -- check it on a real display.** Round 195 found the big CPU cost: tech_effect() rebuilt the
   player's whole effect list (131 entries) on every call, several times a frame -- the village went from 27 ms to
   7 ms a frame headless (per-frame readers now use Game.fx_now() / max_hp(true); tech_effect() stays exact). Please
   confirm 60 fps in the village, valley and a busy floor with the editor's profiler, and fix what is left.
   Note: Performance.TIME_PROCESS (crumbs "proc=") is the worst frame of each second, not an average --
   tools/_cpu_wall.gd measures average wall time per frame.
   Rounds 196-200 took the rest we could find headless: the hitch after fights and on each kill (Game.fx_hold),
   "Use all" (4.5 -> 0.4 ms a pill), every menu page's redraw (tools/_hubfill.gd times them; long tab sections are now
   built when their tab is first shown -- Hub._lazy / PageTabs), idle foes (Enemy._rest_slide), and a font trap: any
   label with a tick, arrow or CJK letter made the engine ask the OS for a font (UiStyle.symbols_font, DEV_GUIDE round 199).
   Still open on his PC: the first ~20 s after arriving on a new floor ran at 4-5 fps once (floor 24), then recovered --
   likely shader preparation; the probe's "settling" line will show it.
2. **GPU cost per feature** (scripts/core/PerfProbe.gd writes perf_probe.txt: frame time with each feature switched off).
   In his last probe the sun's shadows were the largest single cost. 137 OmniLights in the village (no shadows).
   Keep the Low/Medium/High tiers; AutoRes (scripts/core/AutoRes.gd) lowers the 3D resolution when the GPU is busy.
3. **Feel:** combat hit feel, camera, readability of menus. Visual-only changes are welcome.
4. **Phone:** read PHONE_RULES.md. The phone keeps its basic look; every non-art fix applies to both.

## Do not break (see INTEGRATION_GUIDE.md for the full list)
- Autoloads `Game` and `MemLog`, public functions and signals, save keys, data ids.
- data/*.json must stay **LF line endings** (the online server hashes data/; CRLF breaks it).
- Store rules: nothing sold gives power (tools/fair_check.gd). Ads only on the phone free tier past floor 5.
- New round-193/194 pieces: GpuCourtesy.gd (asks a local AI on the same PC to free the graphics card), AutoRes.gd,
  CloudSave.delete_account + supabase/functions/delete-account (Google Play's account-deletion rule),
  Online.open_to_players() (store builds hide the Elite Online Gate until a public server exists).
- Round 200 balance: data/combat.json "boss_ease" (floor masters past 25 ease; tools/balance_report.gd shows the trade).
- New player-facing text through tr()/I18n.t(); add translations in tools/i18n/part_*.txt and run tools/build_i18n.py.

## Proof it still works
`GODOT=<godot 4.6.3> bash tools/release_gate.sh` -- 123 steps, all must pass. Quick: tools/compile_all.gd (0 failed).
Return the full project as one zip plus a short change list (CHANGES_SEELE.md). Robert applies it with APPLY_UPDATE.bat.
