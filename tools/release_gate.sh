#!/bin/bash
# RELEASE GATE: nothing ships unless every line here passes.   Usage: GODOT=/path/to/godot tools/release_gate.sh   (from anywhere)
cd "$(dirname "$0")/.."
G=${GODOT:-godot}; FAIL=0
run() { n=$1; shift; out=$("$@" 2>&1); rc=$?; line=$(echo "$out" | grep -E "CHECK|passed|SMOKE DONE|COMPILE ALL|RANGED" | tail -1); echo "$n: ${line:-no summary}"; if [ $rc -ne 0 ] || echo "$out" | grep -qE "SCRIPT ERROR|Parse Error| [1-9][0-9]* failed"; then FAIL=1; echo "  ^^^ FAILED"; fi; }
for t in compile_all touch_layout_check xr_check fair_check hook_check gauntlet_check ui_hot_check lite_check frontier_check guide_check paths_check opening_check lives_check rollout_check ranged_check design_check heirloom_check legacy_line_check menu_tabs_check smoke; do
  f=tools/$t.gd; [ -f $f ] || f=tools/dev_checks/$t.gd
  run $t timeout 400 $G --headless --path . --script res://$f
done
EXP=$(python3 -c "import sys;sys.path.insert(0,'tools/server');from elite_server import data_hash;print(data_hash('data'))")
ELITE_EXPECT_HASH=$EXP run foundation_check timeout 200 $G --headless --path . --script res://tools/foundation_check.gd
run adaptive_check timeout 100 $G --headless --path . --script res://tools/adaptive_check.gd
run craftbook_check timeout 120 $G --headless --path . --script res://tools/craftbook_check.gd
run craft_page_check timeout 150 $G --headless --path . --script res://tools/craft_page_check.gd
run dao_check timeout 120 $G --headless --path . --script res://tools/dao_check.gd
run dao_page_check timeout 150 $G --headless --path . --script res://tools/dao_page_check.gd
run poison_check timeout 120 $G --headless --path . --script res://tools/poison_check.gd
run bag_check timeout 120 $G --headless --path . --script res://tools/bag_check.gd
run menagerie_check timeout 150 $G --headless --path . --script res://tools/menagerie_check.gd
run breeding_check timeout 150 $G --headless --path . --script res://tools/breeding_check.gd
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
ARTS=1 SEED=11 FRAMES=2500 run mash_fuzz_arts timeout 120 $G --headless --path . --script res://tools/mash_fuzz.gd
SEED=12 FRAMES=2500 run mash_fuzz timeout 120 $G --headless --path . --script res://tools/mash_fuzz.gd
run i18n_check timeout 150 $G --headless --path . --script res://tools/i18n_check.gd
run server_engine python3 tools/server/test_engine.py
run server_handshake python3 tools/server/handshake_test.py
run server_ladder python3 tools/server/ladder_test.py
run server_spread python3 tools/server/spread_test.py
run server_fuzz python3 tools/server/fuzz_test.py
run server_e2e python3 tools/server/e2e_test.py
[ $FAIL -eq 0 ] && echo "RELEASE GATE: PASS" || echo "RELEASE GATE: FAIL"
exit $FAIL
