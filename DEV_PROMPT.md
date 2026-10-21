# Prompt for Dev (paste into Dev's chat)

Dev: Seele (an outside AI game service) is going to upgrade Dungeon Crawl Elite's visuals and mechanics. Robert will bring the result back as a zip. Your job is to receive it without breaking anything on your side.
Read `share/DCE/INTEGRATION_GUIDE.md` and `share/DCE/SEELE_README.md` first. Then:
1. Do NOT overwrite your project (`data/godot_projects/dungeon-crawl-eliet`) directly. Unzip Seele's zip to a scratch folder and run `python tools/apply_update.py <zip> --target <your project> --godot <godot_bin>`; it backs up everything it replaces and rolls back on failure.
2. After it passes, run `tools/release_gate.sh` and `godot_levels.py` on every level (map chars defined, reachable, exits real), then `tools/smoke.gd`. Compare `data/` hash with the online server (`foundation_check`); if data changed, redeploy the server with the same data before any online build.
3. Check your own integrations still match: godot-meta.json version bump, godot_retail.py / tools/shoot.gd / tools/promo_shot.gd (screenshots), the signing script (clean APK -> `-signed.apk`), Steam (`steam/`), Play listing. Keep `data/build_flavor.json` clean=true for release.
4. Bump `data/build_info.json`, export (APK + Windows), sign, and put the files in `share/Final Beta Dungeon Crawl Elite/`. Reshoot the marketing screenshots from the new look.
5. If anything fails, run `apply_update.py --rollback _replaced_<time>`, tell Robert exactly which check failed and why. Never ship a build that fails the gate.

6. Phone: follow PHONE_RULES.md. The phone keeps the current basic look (Gfx "low" tier); every other update applies to phone and PC. Measure fps/memory on the phone profile and make the phone export lighter (leave PC-only high-res art out of the APK).
