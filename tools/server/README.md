# Elite Online -- the server (round 125)

One Python process (`elite_server.py`), one SQLite file, JSON over WebSocket. The game's **Gate** (a violet pad in the village and the valley)
connects here. Everything the shared world owns lives in the database -- online heroes, gold, marks, materials, the market, mail,
leaderboards, titles. **A solo save is never written here, and nothing here writes a solo save.** The one bridge is a *grant*: crafting
materials the player takes out of the Vault are removed from the server first, handed to the game, and acknowledged by the game.

## Run it

    pip install -r requirements.txt            # websockets
    ELITE_DEV=1 ./run_server.sh                # testing: any name logs in, no accounts
    ./run_server.sh                            # real: accounts checked against Supabase (below)

Docker: `docker build -f tools/server/Dockerfile -t elite-online .` from the project folder; `docker run -p 8765:8765 -v elitedata:/var/lib/elite -e ELITE_SUPABASE_URL=... -e ELITE_SUPABASE_ANON=... elite-online`.
Behind TLS (Caddy / nginx / Cloudflare) the game connects with `wss://your.host`; set it in the Gate window -> Server address.
The default address in the game is `ws://100.96.204.37:8765` (the HomeAI box over Tailscale).

## Settings (environment variables, all `ELITE_...`)

| name | default | meaning |
|---|---|---|
| HOST / PORT | 0.0.0.0 / 8765 | where to listen |
| DB | tools/server/elite.db | the SQLite file (back it up) |
| DATA | ../../data | the game's data folder (enemies.json, items.json, gates.json, online_events.json) |
| DEV | (off) | 1 = any name logs in, no accounts |
| SUPABASE_URL / SUPABASE_ANON | | the project the game's Cloud save uses; the server asks it who a token belongs to |
| MIN_BUILD | 0 | clients older than this build number are told to update |
| ALLOWLIST | (everyone) | a text file, one email or account id per line: a closed beta |
| IMPORT_MAX_REALM | 3 | the highest realm a new online hero can begin at |
| RAID_MIN / QUEUE_WAIT_RUN / QUEUE_WAIT_RAID | 3 / 15 / 45 | matchmaking |
| RATE / MAX_CONN | 60 / 400 | per-client message rate, total connections |
| EVENTS | DATA/online_events.json | world-event schedule |
| SPEED | 1 | tests only: run the world faster than real time |

## What the server decides (and what it trusts)

The server owns the dungeon simulation: foes, their health and movement, the telegraphed circles and what they hit, who is down, who is raised,
rewards, titles and leaderboards. A client sends where it stands and *reports* the blows it lands; the server clamps each report to what that
rank could do (and a rolling total per second), checks reach, and ignores a player who is down. Loot online is crafting materials, gold, marks and
experience only -- never gear or breakthrough pills. This is "trusted but clamped": a modified client can be a little stronger than it should be
inside a fight, but cannot give itself items, gold or rank.

## Before real players

1. A Supabase project for the game (the Cloud save and the Gate share it). Run `tools/cloud/cloud_setup.sql` in it, put the URL and anon key in the game's `data/cloud.json` and the two ELITE_SUPABASE_* variables here.
2. A host with a public name and TLS, and `ELITE_MIN_BUILD` set to the current build.
3. Optional: `ELITE_ALLOWLIST` for a closed beta. Moderation: `python3 elite_server.py admin reports | ban NAME [reason] | unban NAME | mute NAME MINUTES | char NAME`.
4. Not done yet: checking a Play Store / Steam purchase on the server (the game can already require the full game, `data/online.json`), and online gear.

## Tests

    python3 test_engine.py        # the simulation, anti-cheat clamps, the store
    python3 e2e_test.py           # a real server and bot clients over WebSockets
    ./run_online_check.sh         # (project folder) the Godot client against a real server; set GODOT=path/to/godot

## Messages (client -> server)

hello, create_char, delete_account, ping, enter_hub, h_move, leave_hub, chat, report, p_invite, p_accept, p_leave, p_kick, p_start, queue, unqueue,
i_move, i_hit, i_leave, event_join, events, lb, inv, m_list, m_search, m_buy, m_cancel, mail_list, mail_claim, mail_delete, mail_send, withdraw, grant_ack.

## Data handshake (round 130)
The client sends a SHA-256 over enemies/items/gates/online_events in `hello`; the server compares with its own (`data_hash`). Mismatch: flagged (`data_ok:false` in welcome). Set `ELITE_STRICT_DATA=1` to refuse mismatched clients (`data_mismatch`) - turn on for the live MMO. Run `tools/release_gate.sh` before every release.
