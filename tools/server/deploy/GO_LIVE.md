# Taking co-op live (round 182)

Co-op is built: parties of up to 8, join codes, dungeon runs, raids, matchmaking, world events, market, mail and
season ladders, simulated on the server (tools/server, 54 end-to-end checks + the Godot client check). What it needs is
a place to run where players can reach it. Today the game points at the HomeAI box over Tailscale, which only your
own devices can reach.

## Choices (Robert decides: these cost money or touch accounts)
1. **Host**: a small VPS (1 vCPU / 1-2 GB) is plenty to start -- the server is one Python process and one SQLite file.
2. **Domain**: a name for it (play.yourdomain.com) so it gets TLS (wss://).
3. **Supabase project** for accounts and cloud saves (supabase/README.md has the enable plan; new migration 04 adds
   the play_stats table).

## Steps once chosen
1. `cp tools/server/deploy/.env.example tools/server/deploy/.env` and fill it in.
2. `docker compose -f tools/server/deploy/docker-compose.yml up -d --build`
3. In `data/online.json` set `"url": "wss://YOUR_DOMAIN"` and rebuild the game. (The Gate window also lets a tester type it.)
4. Set `ELITE_MIN_BUILD` to the new build so old copies are told to update.
5. Closed beta first: `ELITE_ALLOWLIST`.
6. Watch: `docker compose logs -f elite`; moderation: `docker compose exec elite python3 /app/server/elite_server.py admin reports`.

Rollback: `docker compose down` -- the game plays fully offline as before; online heroes stay in the volume.
