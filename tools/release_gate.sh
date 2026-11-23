#!/bin/bash
# RELEASE GATE: nothing ships unless every line here passes.   Usage: GODOT=/path/to/godot tools/release_gate.sh   (from anywhere)
cd "$(dirname "$0")/.."
G=${GODOT:-godot}; PY=${PYTHON:-python3}; FAIL=0
run() { n=$1; shift; out=$("$@" 2>&1); rc=$?; line=$(echo "$out" | grep -E "CHECK|passed|SMOKE DONE|COMPILE ALL|RANGED" | tail -1); echo "$n: ${line:-no summary}"; if [ $rc -ne 0 ] || echo "$out" | grep -qE "SCRIPT ERROR|Parse Error| [1-9][0-9]* failed"; then FAIL=1; echo "  ^^^ FAILED"; printf '%s\n' "$out" | grep -E 'FAIL:|  FAIL |SCRIPT ERROR|Parse Error|Error|Exception' | head -20; fi; }
for t in compile_all device_profile_check touch_layout_check xr_check fair_check hook_check gauntlet_check ui_hot_check lite_check frontier_check guide_check paths_check opening_check lives_check rollout_check ranged_check design_check heirloom_check legacy_line_check menu_tabs_check smoke; do
  f=tools/$t.gd; [ -f $f ] || f=tools/dev_checks/$t.gd
  run $t timeout 400 $G --headless --path . --script res://$f
done
EXP=$("$PY" -c "import sys;sys.path.insert(0,'tools/server');from elite_server import data_hash;print(data_hash('data'))") || { echo "RELEASE GATE: data hash failed"; exit 1; }
[ -n "$EXP" ] || { echo "RELEASE GATE: empty data hash"; exit 1; }
ELITE_EXPECT_HASH=$EXP run foundation_check timeout 200 $G --headless --path . --script res://tools/foundation_check.gd
run everything_probe timeout 1500 $G --headless --path . --script res://tools/everything_probe.gd
run adaptive_check timeout 100 $G --headless --path . --script res://tools/adaptive_check.gd
run craftbook_check timeout 120 $G --headless --path . --script res://tools/craftbook_check.gd
run craft_page_check timeout 150 $G --headless --path . --script res://tools/craft_page_check.gd
run dao_check timeout 120 $G --headless --path . --script res://tools/dao_check.gd
run dao_page_check timeout 150 $G --headless --path . --script res://tools/dao_page_check.gd
run poison_check timeout 120 $G --headless --path . --script res://tools/poison_check.gd
run bag_check timeout 120 $G --headless --path . --script res://tools/bag_check.gd
run menagerie_check timeout 150 $G --headless --path . --script res://tools/menagerie_check.gd
run breeding_check timeout 150 $G --headless --path . --script res://tools/breeding_check.gd
run genome_check timeout 150 $G --headless --path . --script res://tools/genome_check.gd
run eggs_check timeout 150 $G --headless --path . --script res://tools/eggs_check.gd
run foundry_check timeout 150 $G --headless --path . --script res://tools/foundry_check.gd
run crew_check timeout 150 $G --headless --path . --script res://tools/crew_check.gd
run bionics_check timeout 150 $G --headless --path . --script res://tools/bionics_check.gd
run tattoo_check timeout 150 $G --headless --path . --script res://tools/tattoo_check.gd
run farm_check timeout 150 $G --headless --path . --script res://tools/farm_check.gd
run r177_save_check timeout 150 $G --headless --path . --script res://tools/r177_save_check.gd
run tailor_check timeout 150 $G --headless --path . --script res://tools/tailor_check.gd
run lineage_check timeout 150 $G --headless --path . --script res://tools/lineage_check.gd
run stable_ui_check timeout 150 $G --headless --path . --script res://tools/stable_ui_check.gd
run goals_check timeout 100 $G --headless --path . --script res://tools/goals_check.gd
run firsthour_check timeout 100 $G --headless --path . --script res://tools/firsthour_check.gd
run cooking_check timeout 100 $G --headless --path . --script res://tools/cooking_check.gd
run photo_check timeout 150 $G --headless --path . --script res://tools/photo_check.gd
run pad_check timeout 100 $G --headless --path . --script res://tools/pad_check.gd
run craftplay_check timeout 150 $G --headless --path . --script res://tools/craftplay_check.gd
run sitpose_check timeout 150 $G --headless --path . --script res://tools/sitpose_check.gd
run access_check timeout 150 $G --headless --path . --script res://tools/access_check.gd
run pace_check timeout 150 $G --headless --path . --script res://tools/pace_check.gd
run cmstory_check timeout 150 $G --headless --path . --script res://tools/cmstory_check.gd
run boons_check timeout 150 $G --headless --path . --script res://tools/boons_check.gd
run collect_check timeout 150 $G --headless --path . --script res://tools/collect_check.gd
run aspect_check timeout 150 $G --headless --path . --script res://tools/aspect_check.gd
run nmind_check timeout 150 $G --headless --path . --script res://tools/nmind_check.gd
run inner_check timeout 150 $G --headless --path . --script res://tools/inner_check.gd
run workshop_check timeout 150 $G --headless --path . --script res://tools/workshop_check.gd
run juice_check timeout 100 $G --headless --path . --script res://tools/juice_check.gd
run world_check timeout 150 $G --headless --path . --script res://tools/world_check.gd
run menulock_check timeout 60 $G --headless --path . --script res://tools/menulock_check.gd
run pull_check timeout 150 $G --headless --path . --script res://tools/pull_check.gd
run constructs_check timeout 150 $G --headless --path . --script res://tools/constructs_check.gd
run seek_check timeout 150 $G --headless --path . --script res://tools/seek_check.gd
run harmony_check timeout 150 $G --headless --path . --script res://tools/harmony_check.gd
run tester_check timeout 150 $G --headless --path . --script res://tools/tester_check.gd
run assist_check timeout 100 $G --headless --path . --script res://tools/assist_check.gd
run focus_check timeout 150 $G --headless --path . --script res://tools/focus_check.gd
run menu_walk_check timeout 150 $G --headless --path . --script res://tools/menu_walk_check.gd
run talk_menu_check timeout 60 $G --headless --path . --script res://tools/talk_menu_check.gd
run quick_check timeout 60 $G --headless --path . --script res://tools/quick_check.gd
run stream_check timeout 150 $G --headless --path . --script res://tools/stream_check.gd
run warm_check timeout 120 $G --headless --path . --script res://tools/warm_check.gd
run infinite_check timeout 60 $G --headless --path . --script res://tools/infinite_check.gd
run controls_check timeout 60 $G --headless --path . --script res://tools/controls_check.gd
run locks_check timeout 90 $G --headless --path . --script res://tools/locks_check.gd
run veil_check timeout 120 $G --headless --path . --script res://tools/veil_check.gd
run leak_check timeout 150 $G --headless --path . --script res://tools/leak_check.gd
run mystery_check timeout 300 $G --headless --path . --script res://tools/mystery_check.gd
run solo_world_check timeout 600 $G --headless --path . --script res://tools/solo_world_check.gd
run art_pack_check timeout 600 $G --headless --path . --script res://tools/art_pack_check.gd
run audio_check timeout 300 $G --headless --path . --script res://tools/audio_check.gd
run world_sound_check timeout 300 $G --headless --path . --script res://tools/world_sound_check.gd      # round 184
run world_sfx_test "$PY" tools/world_sfx_test.py
run perf_check timeout 600 $G --headless --path . --script res://tools/perf_check.gd      # round 186: Eliet light enough to draw
run perf_probe_check timeout 900 $G --headless --path . --script res://tools/perf_probe_check.gd      # round 188: the in-play slowness probe puts everything back
run fellowship_check timeout 900 $G --headless --path . --script res://tools/fellowship_check.gd      # round 188: guilds, the chat, your own sect -- and none of it is power
run guild_ui_check timeout 900 $G --headless --path . --script res://tools/guild_ui_check.gd      # round 188: the Guild page and the chat box through the real menus
run weapon_arts_check timeout 900 $G --headless --path . --script res://tools/weapon_arts_check.gd      # round 188: three arts per kind of weapon, each cast for real
run qol190_check timeout 600 $G --headless --path . --script res://tools/qol190_check.gd      # round 190: points by five / all / evenly; the fountain keeps counting
"$PY" tools/server/mock_ollama.py 11434 >/dev/null 2>&1 & MOLL=$!; sleep 1
run gpu_courtesy_check timeout 200 $G --headless --path . --script res://tools/gpu_courtesy_check.gd      # round 192: a local AI holding the card is asked to let go
kill $MOLL 2>/dev/null
run auto_res_check timeout 400 $G --headless --path . --script res://tools/auto_res_check.gd      # round 192: picture size follows the GPU
run online_open_check timeout 400 $G --headless --path . --script res://tools/online_open_check.gd      # round 194: no Gate in a store build until the shared world is public
run perf195_check timeout 300 $G --headless --path . --script res://tools/perf195_check.gd      # round 195: effect list built once; quicker safe save
run perf198_check timeout 300 $G --headless --path . --script res://tools/perf198_check.gd      # round 198: Use all, quest index, bag grid kept, idle foes rest
run polish199_check timeout 300 $G --headless --path . --script res://tools/polish199_check.gd      # round 199: boss young aren't bosses, errands cached, symbol font, page effect hold
run round200_check timeout 300 $G --headless --path . --script res://tools/round200_check.gd      # round 200: boss ease, sections built with their tab, spread button
run use_many_check timeout 300 $G --headless --path . --script res://tools/use_many_check.gd
run pet_motion_check timeout 200 $G --headless --path . --script res://tools/pet_motion_check.gd
run gate_reach_check timeout 900 $G --headless --path . --script res://tools/gate_reach_check.gd
run playtest timeout 1500 $G --headless --path . --script res://tools/playtest.gd
ELIET_DEMO=1 run demo_probe timeout 300 $G --headless --path . --script res://tools/demo_probe.gd
if command -v xvfb-run >/dev/null; then run wide_check timeout 300 xvfb-run -a -s "-screen 0 1600x900x24" $G --path . --rendering-driver opengl3 --resolution 1280x720 --script res://tools/wide_check.gd; else echo "wide_check: skipped (needs xvfb-run or a display)"; fi
ARTS=1 SEED=11 FRAMES=2500 run mash_fuzz_arts timeout 120 $G --headless --path . --script res://tools/mash_fuzz.gd
SEED=12 FRAMES=2500 run mash_fuzz timeout 120 $G --headless --path . --script res://tools/mash_fuzz.gd
run i18n_check timeout 150 $G --headless --path . --script res://tools/i18n_check.gd
"$PY" tools/cloud/mock_supabase.py 8793 >/dev/null 2>&1 & MOCK=$!; sleep 1
run playstats_check timeout 200 $G --headless --path . --script res://tools/playstats_check.gd -- 8793
kill $MOCK 2>/dev/null
"$PY" tools/cloud/mock_supabase.py 8791 >/dev/null 2>&1 & MOCK2=$!; sleep 1
run cloud_check timeout 300 $G --headless --path . --script res://tools/cloud_check.gd -- 8791      # round 194: in the gate at last (with account deletion)
kill $MOCK2 2>/dev/null
run supabase_functions bash -c "cd supabase/tests && node verify_purchase_test.mjs && node delete_account_test.mjs"      # round 194
run stats_report_test "$PY" tools/stats_report_test.py
run review_test "$PY" tools/i18n/review_test.py
run music_subtle_test "$PY" tools/music_subtle_test.py
run looks_check timeout 200 $G --headless --path . --script res://tools/looks_check.gd
run mods_check timeout 200 $G --headless --path . --script res://tools/mods_check.gd
if [ -n "$PGLITE_DIR" ] && [ -d "$PGLITE_DIR/node_modules/@electric-sql/pglite" ]; then cp supabase/tests/run_sql_tests.mjs "$PGLITE_DIR/"; GD=$PWD; pushd "$PGLITE_DIR" >/dev/null; MIGRATIONS="$GD/supabase/migrations" run supabase_sql timeout 120 node run_sql_tests.mjs; popd >/dev/null; else echo "supabase_sql: skipped (set PGLITE_DIR to a folder with @electric-sql/pglite)"; fi
run server_engine "$PY" tools/server/test_engine.py
run server_handshake "$PY" tools/server/handshake_test.py
run server_ladder "$PY" tools/server/ladder_test.py
run server_spread "$PY" tools/server/spread_test.py
run server_fuzz "$PY" tools/server/fuzz_test.py
run server_e2e "$PY" tools/server/e2e_test.py
GODOT=$G run online_client timeout 500 bash tools/server/run_online_check.sh
[ $FAIL -eq 0 ] && echo "RELEASE GATE: PASS" || echo "RELEASE GATE: FAIL"
exit $FAIL
