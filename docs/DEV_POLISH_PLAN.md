# Dev's polish plan — Dungeon Crawl Elite  (handed over 2026-10-06)

## The goal
Make the game **smooth** (no hitches, nothing that feels janky), **mechanically balanced** (every floor fair
and fun on the cultivator the game expects there), and **packageable** — a retail kit per platform that Robert
can upload without further work. Robert's pay model never changes: phones = floors 1-5 free, ads below at natural
breaks, ONE purchase `full_game` removes ads; Steam = paid full game + free demo (floors 1-5) + "Expansions to come".

## Rules you already know (do not break)
Back up before replacing. Never deploy `levels/` or forge data from outside the box (the forge refines levels here).
You write the words. Never echo API keys or the keystore password. Work while Robert is away (10 min after he talks).
Every change goes through the workshop gate: parse → symbols → engine → playtest → smoke.

## The measure: `tools/balance_report.gd`
Run: `godot --headless --path . --script res://tools/balance_report.gd -- user://balance.json`
Thresholds live in `data/combat.json` "balance". Targets on every floor, for the expected cultivator:
- three typical foes need >= 7 s to kill the player (no lethal packs); one typical foe dies in <= 11 s (no sponges)
- boss takes 15-150 s to kill, and kills the player in >= 14 s
- lethality changes <= 40% floor to floor (no spikes, no cliffs)
Last report: 6 floors flagged. Known: floor 5 has no boss and jumps; floors 6 and 8 spike; floors 10/15/20 report
"no foes spawned" (hubs? confirm and teach the report to skip them); bosses on floors 1-2 were just buffed 30%
(unmeasured). Fix by changing numbers in `data/*.json` first (combat.json curve, enemies.json hp/damage, foes.json
affixes) — only touch code when data cannot do it. Re-run after every change; keep `PLAYTEST` and `SMOKE` green.

## The plan, in order
1. **Measure** — run balance_report; save the output as the baseline in save-data. 
2. **Balance pass** — clear every flag above, one floor band at a time (1-5, 6-15, 16-30, 31-50). After each band:
   playtest + smoke. Elites/affixes at depth: check swift+vampiric+frenzied combos are not instant-lethal.
3. **Smoothness pass** — use game_eyes (screenshots) and the playtest timings: find frame-time spikes (level build,
   foe spawn waves, effect bursts), long loads, input lag at menus; fix the worst three; record before/after.
4. **Queue already waiting** — w001/w002 (retry now: your answer hygiene was fixed), f001 masks + mask-maker quests
   (w003-w005), w006 roads and lamp posts (roadway = no-drop zone unless deliberate), f002 travelled-area map
   (w007-w008). Keep them separate from balance changes so each can be rolled back alone.
5. **Packaging** — `godot_retail.kit("steam"|"google-play"|"web")` (in `godot_retail.py`) writes
   `data/godot_retail/<slug>/<version>/<platform>/`: builds, store screenshots, capsules/icon/feature graphic,
   STORE-PAGE / LISTING text, privacy policy, CHECKLIST. Test it on the box (screenshots are slow: run 3-4 shots in
   the background), wire the phrases "package the game for steam / google play / web / everything" and "retail package"
   into dev_actions, add tests. The old `play-listing/PLAY-LISTING.md` (0.57) is outdated — the kit supersedes it.
6. **Release check** — before any kit: demo pck holds only floors 1-5; Store backend per platform (full / google /
   demo); ads only on phones past floor 5; version bumped; saves shared between demo and full on Steam.
7. **Report** — one short morning-brief line per finished step; stop and ask Robert only for what is his (below).

## What only Robert can do
- Restart HomeAI once (Invest tab, home page, overlay routes).
- Real AdMob ad-unit ids and the Steam app ids (`store.json` steam.full_app_id / demo_app_id, `steam_appid.txt`).
- Say "I accept the Android SDK license" if he wants Android builds made on the box.
- Create the Play Console and Steamworks listings and upload the kit (the CHECKLIST.md in each kit lists the clicks).

## Done means
balance_report: 0 flagged · playtest and smoke green · three retail kits generated and read through · queue empty ·
a final one-page summary for Robert on the desk.
