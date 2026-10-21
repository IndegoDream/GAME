#!/bin/bash
# starts a development server on :18766 and runs the Godot client check against it   (run from the project folder)
cd "$(dirname "$0")"
DB=$(mktemp -d)/t.db
ELITE_DEV=1 ELITE_PORT=18766 ELITE_HOST=127.0.0.1 ELITE_DB=$DB ELITE_SPEED=${ELITE_SPEED:-4} python3 elite_server.py > /tmp/elite_check_server.log 2>&1 &
SP=$!
sleep 1.5
cd ../..
${GODOT:-godot} --headless --path . --script res://tools/online_check.gd 2>&1 | grep -vE "^\s*$"
RC=${PIPESTATUS[0]}
kill $SP 2>/dev/null
exit $RC
