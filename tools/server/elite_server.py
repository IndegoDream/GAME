#!/usr/bin/env python3
"""Elite Online -- the server for Dungeon Crawl Elite's shared world (round 125).

    python3 elite_server.py                      (reads ELITE_* environment variables; see README.md)
    ELITE_DEV=1 python3 elite_server.py          (no accounts needed: any name logs in -- for testing only)

One process, one SQLite file. WebSocket + JSON. Accounts are Supabase accounts (the token is checked against Supabase
auth); everything the server owns -- online characters, gold, marks, materials, the market, mail, leaderboards -- is in
the SQLite file. A solo save is never written here and nothing here writes a solo save (the only bridge is `grant`:
materials the server hands over, taken from the server first and acknowledged by the game)."""
import asyncio, hashlib, json, math, os, random, re, sys, time, urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from store import Store, BOARDS
import engine

HERE = Path(__file__).parent
VERSION = 1
HASH_FILES = ("enemies.json", "items.json", "gates.json", "online_events.json")   # the data the server and game must agree on (same list in Online.gd)


SEASON_EPOCH = 1792368000.0        # Monday 2026-10-19 00:00 UTC: season 1 starts here (season 0 = before launch)
POINTS = {"run": 10, "raid": 30, "world": 20}      # per tier on a win (the world Titan: flat)


def season_info(now=None, days=56):
    """which season it is, and when it ends"""
    now = time.time() if now is None else now
    length = days * 86400.0
    n = int((now - SEASON_EPOCH) // length) + 1 if now >= SEASON_EPOCH else 0
    return {"season": n, "ends": SEASON_EPOCH + n * length if n >= 1 else SEASON_EPOCH, "days": days}


def season_rewards(season):
    def fn(rank, points):
        out = []
        if rank == 1:
            out.append("Season %d Champion" % season)
        if rank <= 3:
            out.append("Season %d Podium" % season)
        if rank <= 10:
            out.append("Ladder Elite %d" % season)
        if points >= 50:
            out.append("Season %d Veteran" % season)
        return out
    return fn


def data_hash(d):
    import hashlib
    h = hashlib.sha256()
    for n in HASH_FILES:
        try:
            h.update((n + ":" + hashlib.sha256(Path(d, n).read_bytes()).hexdigest() + "\n").encode())
        except Exception:
            h.update((n + ":missing\n").encode())
    return h.hexdigest()
SUBLEVELS = 10
HUB_CAP = 40
HUB_BOUNDS = 44.0


def env(name, default=""):
    return os.environ.get("ELITE_" + name, default)


# ---- party level spread (round 138) -----------------------------------------------------------------------------------------------------------
# Robert, 2026-10-17: raids and challenges are about the party's levels. More than 5 levels between the lowest and highest hero
# docks every member's rewards: 10% at a spread of 6, +5% a level to 30% at 10, then +10% a level to a 75% cap (at 15). So nobody
# carries a much weaker hero for a prize. It applies to dungeon runs and raids (a party's work); open world bosses pay by damage already.
SPREAD_FREE = 5
SPREAD_CAP = 0.75
SPREAD_KINDS = ("run", "raid")


def spread_penalty(spread):
    """fraction of every reward lost for a level spread (0 .. 0.75)"""
    s = int(spread)
    if s <= SPREAD_FREE:
        return 0.0
    if s <= 10:
        return round(0.10 + 0.05 * (s - 6), 4)
    return min(SPREAD_CAP, round(0.30 + 0.10 * (s - 10), 4))


def level_spread(levels):
    levels = [int(x) for x in levels]
    return (max(levels) - min(levels)) if levels else 0


def apply_spread(rw, pen, rng):
    """cut a reward by pen: xp, gold, marks, season points round down; items round at random so one item at 10% is a 10% chance to lose it"""
    if pen <= 0:
        return rw
    keep = 1.0 - pen
    for k in ("xp", "gold", "marks"):
        if k in rw:
            rw[k] = int(rw[k] * keep)
    kept = {}
    for k, n in rw.get("items", {}).items():
        x = n * keep
        m = int(x) + (1 if rng.random() < (x - int(x)) else 0)
        if m > 0:
            kept[k] = m
    rw["items"] = kept
    return rw


def best_window(entries, size_hi):
    """entries: [(level, wait_key, item)] oldest first. The group (up to size_hi) around the longest waiter with the smallest level spread."""
    if not entries:
        return []
    anchor = entries[0]
    by_level = sorted(entries, key=lambda e: (e[0], e[1]))
    i0 = by_level.index(anchor)
    best = None
    for lo in range(max(0, i0 - size_hi + 1), i0 + 1):
        for hi in range(i0, min(len(by_level), lo + size_hi)):
            win = by_level[lo:hi + 1]
            spread = win[-1][0] - win[0][0]
            if spread > SPREAD_FREE:
                continue
            key = (-len(win), spread)
            if best is None or key < best[0]:
                best = (key, win)
    if best is None:
        best = (None, [anchor])
    return [e[2] for e in best[1]]


class Config:
    def __init__(self):
        self.host = env("HOST", "0.0.0.0")
        self.port = int(env("PORT", "8765"))
        self.db = env("DB", str(HERE / "elite.db"))
        self.data_dir = Path(env("DATA", str(HERE.parent.parent / "data")))
        self.dev = env("DEV", "") == "1"
        self.supabase_url = env("SUPABASE_URL", "").rstrip("/")
        self.supabase_anon = env("SUPABASE_ANON", "")
        self.min_build = int(env("MIN_BUILD", "0"))
        self.season_days = int(env("SEASON_DAYS", "56"))
        self.strict_data = env("STRICT_DATA", "") == "1"      # refuse clients whose game data differs from the server's
        self.allowlist = env("ALLOWLIST", "")           # a text file, one email or account id per line (closed beta); empty = everyone
        self.import_max_realm = int(env("IMPORT_MAX_REALM", "3"))
        self.queue_wait_run = float(env("QUEUE_WAIT_RUN", "15"))
        self.queue_wait_raid = float(env("QUEUE_WAIT_RAID", "45"))
        self.raid_min = int(env("RAID_MIN", "3"))
        self.rate = float(env("RATE", "60"))            # messages per second a client may send, on average
        self.max_conn = int(env("MAX_CONN", "400"))
        self.speed = float(env("SPEED", "1"))             # test only: run the world faster than real time


def load_json(p, default):
    try:
        return json.loads(Path(p).read_text(encoding="utf-8"))
    except Exception:
        return default


DEFAULT_EVENTS = {"events": [
    {"id": "crater_titan", "kind": "world", "name": "The Crater Titan", "period_min": 60, "duration_min": 12, "offset_min": 0, "tier": 5, "bonus": 1.0},
    {"id": "raid_night", "kind": "bonus", "name": "Raid Night (raid rewards x1.5)", "period_min": 10080, "duration_min": 180, "offset_min": 5880, "bonus": 1.5},
]}

BANNED_NAME_WORDS = ["admin", "moderator", "fuck", "shit", "nigg", "cunt", "rape", "hitler"]
CHAT_BAD = ["fuck", "shit", "cunt", "nigg", "faggot", "retard"]


def filter_chat(text):
    t = text
    for w in CHAT_BAD:
        t = re.sub(re.escape(w), "*" * len(w), t, flags=re.I)
    return t


class Session:
    def __init__(self, ws, server):
        self.ws = ws
        self.server = server
        self.q = asyncio.Queue()
        self.account = None
        self.char = None
        self.where = "login"          # login | char | hub | instance
        self.hub = None
        self.hx = self.hz = 0.0
        self.hyaw = 0.0
        self.anim = "idle"
        self.party = None
        self.inst = None
        self.queue = None
        self.tokens = server.cfg.rate * 2
        self.t_tokens = time.time()
        self.chat_times = []
        self.last_seen = time.time()
        self.closed = False
        self.strikes = 0

    def send(self, msg):
        if self.closed:
            return
        if self.q.qsize() > 600:
            self.closed = True                   # a client that can't keep up is dropped
            asyncio.get_event_loop().create_task(self.ws.close())
            return
        self.q.put_nowait(json.dumps(msg, separators=(",", ":")))

    async def bye(self):
        """close once everything queued (an error message, say) has been written"""
        for _ in range(40):
            if self.q.empty():
                break
            await asyncio.sleep(0.05)
        await asyncio.sleep(0.05)
        try:
            await self.ws.close()
        except Exception:
            pass

    async def writer(self):
        try:
            while True:
                raw = await self.q.get()
                await self.ws.send(raw)
        except Exception:
            self.closed = True

    def allow(self):
        now = time.time()
        self.tokens = min(self.server.cfg.rate * 2, self.tokens + (now - self.t_tokens) * self.server.cfg.rate)
        self.t_tokens = now
        if self.tokens < 1:
            return False
        self.tokens -= 1
        return True

    def pub(self):
        c = self.char
        return {"id": c["char_id"], "name": c["name"], "realm": c["realm"], "step": c["step"], "level": c["level"], "titles": c["titles"][-1:] }


class Party:
    _n = 0

    def __init__(self, leader):
        Party._n += 1
        self.id = Party._n
        self.leader = leader
        self.members = [leader]
        self.invites = set()

    def state(self):
        return {"t": "party", "id": self.id, "leader": self.leader.char["char_id"],
                "members": [s.pub() for s in self.members]}


class Server:
    def __init__(self, cfg=None):
        self.cfg = cfg or Config()
        self.store = Store(self.cfg.db)
        d = self.cfg.data_dir
        self.data = {"enemies": load_json(d / "enemies.json", {}), "items": load_json(d / "items.json", {})}
        self.gates = load_json(d / "gates.json", {}).get("gates", [])
        self.events_def = load_json(env("EVENTS", str(d / "online_events.json")), DEFAULT_EVENTS).get("events", [])
        self.dhash = data_hash(d)
        self.close_old_seasons()
        self.sessions = {}               # char_id -> Session
        self.conns = set()
        self.hubs = {}                   # shard n -> set of sessions
        self.parties = {}
        self.instances = {}              # iid -> {"inst", "sessions": {cid: Session}, "ended_at", "done"}
        self.queues = {"run": [], "raid": []}
        self.next_iid = 1
        self.world = {}                  # event id -> iid of its running instance
        self.token_cache = {}
        self.t0 = time.time()
        self.handlers = {}
        for name in dir(self):
            if name.startswith("h_"):
                self.handlers[name[2:]] = getattr(self, name)

    # ---- tiers ---------------------------------------------------------------------------------------------------
    @staticmethod
    def depth_of(tier):
        return 5 * int(tier)

    def need_realm(self, depth):
        need = 0
        for g in self.gates:
            if int(g.get("floor", 0)) <= depth:
                need = max(need, int(g.get("need", {}).get("realm", 0)))
        return need

    def tier_ok(self, char, tier):
        if not 1 <= tier <= 10:
            return "No such tier."
        need = self.need_realm(self.depth_of(tier))
        if char["realm"] < need:
            return "Tier %d needs realm %d (you are at realm %d here)." % (tier, need, char["realm"])
        return ""

    # ---- login -------------------------------------------------------------------------------------------------------
    def verify(self, token):
        """-> (account_id, email) or None. Supabase decides; the answer is remembered for five minutes."""
        key = hashlib.sha256(token.encode()).hexdigest()
        hit = self.token_cache.get(key)
        if hit and hit[0] > time.time():
            return hit[1]
        if not self.cfg.supabase_url:
            return None
        req = urllib.request.Request(self.cfg.supabase_url + "/auth/v1/user", headers={"apikey": self.cfg.supabase_anon, "Authorization": "Bearer " + token})
        try:
            with urllib.request.urlopen(req, timeout=8) as r:
                d = json.loads(r.read().decode())
        except Exception:
            return None
        if not d.get("id"):
            return None
        who = (d["id"], d.get("email", ""))
        self.token_cache[key] = (time.time() + 300, who)
        return who

    def allowed(self, account_id, email):
        if not self.cfg.allowlist:
            return True
        try:
            rows = {l.strip().lower() for l in Path(self.cfg.allowlist).read_text().splitlines() if l.strip() and not l.startswith("#")}
        except Exception:
            return False
        return account_id.lower() in rows or email.lower() in rows

    # ---- the connection --------------------------------------------------------------------------------------------------
    async def handle(self, ws):
        if len(self.conns) >= self.cfg.max_conn:
            await ws.close(1013, "full")
            return
        s = Session(ws, self)
        self.conns.add(s)
        wt = asyncio.create_task(s.writer())
        try:
            async for raw in ws:
                s.last_seen = time.time()
                if not s.allow():
                    s.strikes += 1
                    if s.strikes > 200:
                        break
                    continue
                try:
                    msg = json.loads(raw)
                    t = msg.get("t", "")
                    if not isinstance(t, str):
                        continue
                except Exception:
                    continue
                if s.where == "login" and t not in ("hello", "ping"):
                    continue
                fn = self.handlers.get(t)
                if fn is None:
                    s.send({"t": "error", "msg": "unknown message"})
                    continue
                try:
                    res = fn(s, msg)
                    if asyncio.iscoroutine(res):
                        await res
                except (ValueError, TypeError, OverflowError, AttributeError, KeyError):
                    s.send({"t": "error", "msg": "bad message"})       # malformed input from a client: refused, not a server fault
                except Exception as e:                       # one bad message never takes the server down
                    print("handler error", t, repr(e), file=sys.stderr)
                    s.send({"t": "error", "msg": "server error"})
        except Exception:
            pass
        finally:
            wt.cancel()
            self.drop(s)

    def drop(self, s):
        s.closed = True
        self.conns.discard(s)
        if s.char:
            self.leave_queue(s)
            self.leave_party(s)
            self.hub_leave(s)
            if s.inst:
                rec = self.instances.get(s.inst)
                if rec:
                    rec["inst"].leave(s.char["char_id"])
                    rec["sessions"].pop(s.char["char_id"], None)
            if self.sessions.get(s.char["char_id"]) is s:
                del self.sessions[s.char["char_id"]]
            self.store.save_char(s.char)

    # ---- handlers: account and character ---------------------------------------------------------------------------------------
    async def h_hello(self, s, m):
        if s.where != "login":
            return
        build = int(m.get("build", 0))
        if build < self.cfg.min_build:
            s.send({"t": "error", "code": "old_build", "msg": "This version is too old for the online world. Please update the game."})
            await s.bye()
            return
        s.data_ok = (not m.get("data")) or str(m.get("data")) == self.dhash       # clients that send no hash are not judged
        if not s.data_ok and self.cfg.strict_data:
            s.send({"t": "error", "code": "data_mismatch", "msg": "Your game data does not match the online world. Please update the game."})
            await s.bye()
            return
        if m.get("token"):
            loop = asyncio.get_event_loop()
            who = await loop.run_in_executor(None, self.verify, str(m["token"]))
        elif self.cfg.dev and m.get("dev"):
            nm = re.sub(r"[^A-Za-z0-9 _-]", "", str(m["dev"]))[:16] or "dev"
            who = ("dev:" + nm.lower(), nm.lower() + "@dev.local")
        else:
            who = None
        if who is None:
            s.send({"t": "error", "code": "auth", "msg": "Sign in (Pause menu > Cloud save) before going through the Gate."})
            await s.bye()
            return
        aid, email = who
        if not self.allowed(aid, email):
            s.send({"t": "error", "code": "closed_beta", "msg": "The online world is in a closed beta. Your account isn't on the list yet."})
            await s.bye()
            return
        acct = self.store.account(aid, email)
        if acct["banned"]:
            s.send({"t": "error", "code": "banned", "msg": "This account is suspended. " + acct.get("ban_reason", "")})
            await s.bye()
            return
        s.account = acct
        c = self.store.char_of(aid)
        if c:
            old = self.sessions.get(c["char_id"])
            if old is not None and old is not s:
                old.send({"t": "error", "code": "other_login", "msg": "You signed in somewhere else."})
                asyncio.get_event_loop().create_task(old.bye())
                self.drop(old)
            s.char = c
            self.sessions[c["char_id"]] = s
            s.where = "char"
        else:
            s.where = "nochar"
        s.send({"t": "welcome", "version": VERSION, "data_ok": getattr(s, "data_ok", True), "data_hash": self.dhash, "server_time": time.time(), "has_char": c is not None, "char": self.char_pub(c) if c else None,
                "events": self.event_list(), "tiers": {str(t): {"depth": self.depth_of(t), "need_realm": self.need_realm(self.depth_of(t))} for t in range(1, 11)}})
        if c:
            for g in self.store.pending_grants(c["char_id"]):
                s.send({"t": "grant", "id": g["id"], "items": g["items"]})

    def char_pub(self, c):
        return {"id": c["char_id"], "name": c["name"], "realm": c["realm"], "step": c["step"], "level": c["level"], "xp": c["xp"],
                "gold": c["gold"], "marks": c["marks"], "titles": c["titles"], "inv": c["inv"]}

    def h_ping(self, s, m):
        s.send({"t": "pong", "n": m.get("n", 0), "server_time": time.time()})

    def h_create_char(self, s, m):
        if s.where != "nochar":
            return
        realm = max(0, min(int(m.get("realm", 0)), self.cfg.import_max_realm))      # a solo character is imported at a capped rank
        step = max(1, min(int(m.get("step", 1)), SUBLEVELS))
        if int(m.get("realm", 0)) > self.cfg.import_max_realm:
            step = 1
        c, err = self.store.create_char(s.account["account_id"], str(m.get("name", "")), realm, step, BANNED_NAME_WORDS)
        if c is None:
            s.send({"t": "char_error", "msg": err})
            return
        s.char = c
        self.sessions[c["char_id"]] = s
        s.where = "char"
        s.send({"t": "char", "char": self.char_pub(c)})

    def h_delete_account(self, s, m):
        if m.get("confirm") != "DELETE" or not s.account:
            s.send({"t": "error", "msg": "Send confirm: DELETE to delete the account."})
            return
        aid = s.account["account_id"]
        s.send({"t": "account_deleted"})
        self.drop(s)
        self.store.delete_account(aid)
        asyncio.get_event_loop().create_task(s.bye())

    # ---- the hub ---------------------------------------------------------------------------------------------------------------------
    def hub_join(self, s):
        for n in sorted(self.hubs):
            if len(self.hubs[n]) < HUB_CAP:
                break
        else:
            n = len(self.hubs) + 1
        self.hubs.setdefault(n, set())
        s.hub = n
        s.where = "hub"
        s.hx, s.hz = random.uniform(-3, 3), random.uniform(-3, 3)
        self.hubs[n].add(s)
        s.send({"t": "hub", "shard": n, "players": [{**o.pub(), "x": o.hx, "z": o.hz} for o in self.hubs[n]]})
        for o in self.hubs[n]:
            if o is not s:
                o.send({"t": "h_join", "p": {**s.pub(), "x": s.hx, "z": s.hz}})

    def hub_leave(self, s):
        if s.hub is not None and s.hub in self.hubs:
            self.hubs[s.hub].discard(s)
            for o in self.hubs[s.hub]:
                o.send({"t": "h_leave", "id": s.char["char_id"]})
            if not self.hubs[s.hub]:
                del self.hubs[s.hub]
        s.hub = None

    def h_enter_hub(self, s, m):
        if s.where in ("char", "hub") and s.char:
            if s.where == "hub":
                return
            self.hub_join(s)

    def h_h_move(self, s, m):
        if s.where != "hub":
            return
        x = max(-HUB_BOUNDS, min(HUB_BOUNDS, float(m.get("x", 0))))
        z = max(-HUB_BOUNDS, min(HUB_BOUNDS, float(m.get("z", 0))))
        s.hx, s.hz, s.hyaw = x, z, float(m.get("yaw", 0))
        s.anim = str(m.get("anim", "idle"))[:12]

    def h_leave_hub(self, s, m):
        if s.where == "hub":
            self.hub_leave(s)
            s.where = "char"
            self.leave_queue(s)
            s.send({"t": "left_hub"})

    # ---- chat ---------------------------------------------------------------------------------------------------------------------------
    def h_chat(self, s, m):
        if not s.char or s.where == "login":
            return
        now = time.time()
        s.chat_times = [t for t in s.chat_times if now - t < 10]
        if len(s.chat_times) >= 5:
            s.send({"t": "chat_error", "msg": "Slow down."})
            return
        acct = self.store.account(s.account["account_id"])
        if acct["muted_until"] > now:
            s.send({"t": "chat_error", "msg": "You are muted."})
            return
        text = filter_chat(str(m.get("text", ""))[:200]).strip()
        if not text:
            return
        s.chat_times.append(now)
        ch = str(m.get("ch", "hub"))
        msg = {"t": "chat", "ch": ch, "from": s.char["name"], "text": text}
        if ch == "hub" and s.hub is not None:
            for o in self.hubs.get(s.hub, ()):
                o.send(msg)
        elif ch == "party" and s.party:
            for o in s.party.members:
                o.send(msg)
        elif ch == "inst" and s.inst:
            rec = self.instances.get(s.inst)
            if rec:
                for o in rec["sessions"].values():
                    o.send(msg)
        elif ch == "whisper":
            to = self.store.char_by_name(str(m.get("to", "")))
            o = self.sessions.get(to["char_id"]) if to else None
            if o is None:
                s.send({"t": "chat_error", "msg": "Nobody by that name is here."})
            else:
                msg["to"] = o.char["name"]
                o.send(msg)
                s.send(msg)

    def h_report(self, s, m):
        if s.char:
            self.store.report(s.char["char_id"], str(m.get("name", "")), str(m.get("reason", "")))
            s.send({"t": "reported"})

    # ---- parties -----------------------------------------------------------------------------------------------------------------------------
    def h_p_invite(self, s, m):
        if s.where not in ("hub",) or not s.char:
            return
        o = None
        tc = self.store.char_by_name(str(m.get("name", "")))
        if tc:
            o = self.sessions.get(tc["char_id"])
        if o is None or o is s or o.where != "hub":
            s.send({"t": "party_error", "msg": "Nobody by that name is in the hub."})
            return
        if o.party is not None:
            s.send({"t": "party_error", "msg": "%s is already in a party." % o.char["name"]})
            return
        if s.party is None:
            s.party = Party(s)
            self.parties[s.party.id] = s.party
        if s.party.leader is not s:
            s.send({"t": "party_error", "msg": "Only the leader invites."})
            return
        if len(s.party.members) >= 8:
            s.send({"t": "party_error", "msg": "The party is full."})
            return
        s.party.invites.add(o.char["char_id"])
        o.send({"t": "p_invited", "pid": s.party.id, "from": s.char["name"]})
        s.send(s.party.state())

    def h_p_accept(self, s, m):
        p = self.parties.get(int(m.get("pid", 0)))
        if p is None or s.char["char_id"] not in p.invites or s.party is not None or s.where != "hub":
            s.send({"t": "party_error", "msg": "That invitation is gone."})
            return
        p.invites.discard(s.char["char_id"])
        p.members.append(s)
        s.party = p
        self.leave_queue(s)
        for o in p.members:
            o.send(p.state())

    def leave_party(self, s):
        p = s.party
        if p is None:
            return
        s.party = None
        if s in p.members:
            p.members.remove(s)
        if not p.members:
            self.parties.pop(p.id, None)
            return
        if p.leader is s:
            p.leader = p.members[0]
        for o in p.members:
            o.send(p.state())
        s.send({"t": "party", "id": 0, "leader": 0, "members": []})

    def h_p_leave(self, s, m):
        self.leave_party(s)

    def h_p_kick(self, s, m):
        p = s.party
        if p is None or p.leader is not s:
            return
        for o in list(p.members):
            if o is not s and o.char["name"].lower() == str(m.get("name", "")).lower():
                self.leave_party(o)

    def h_p_start(self, s, m):
        """the leader starts a dungeon run or a raid for the whole party"""
        kind = str(m.get("kind", "run"))
        tier = int(m.get("tier", 1))
        if s.where != "hub":
            return
        members = s.party.members if s.party else [s]
        if s.party and s.party.leader is not s:
            s.send({"t": "party_error", "msg": "Only the leader starts."})
            return
        if kind not in ("run", "raid"):
            return
        mx = 4 if kind == "run" else 8
        if len(members) > mx:
            s.send({"t": "party_error", "msg": "Too many for a %s (%d at most)." % (kind, mx)})
            return
        for o in members:
            err = self.tier_ok(o.char, tier)
            if err:
                s.send({"t": "party_error", "msg": "%s: %s" % (o.char["name"], err)})
                return
            if o.where != "hub":
                s.send({"t": "party_error", "msg": "%s isn't in the hub." % o.char["name"]})
                return
        pen = spread_penalty(level_spread([o.char["level"] for o in members]))
        if pen > 0:
            for o in members:
                o.send({"t": "party_note", "msg": "Levels are %d apart: rewards for the whole party are cut by %d%%." % (level_spread([x.char["level"] for x in members]), round(pen * 100))})
        self.start_instance(kind, tier, members)

    def h_queue(self, s, m):
        kind = str(m.get("kind", "run"))
        tier = int(m.get("tier", 1))
        if s.where != "hub" or kind not in self.queues or s.party is not None:
            s.send({"t": "queue_error", "msg": "Leave your party to queue alone (or have the leader start)."})
            return
        err = self.tier_ok(s.char, tier)
        if err:
            s.send({"t": "queue_error", "msg": err})
            return
        self.leave_queue(s)
        s.queue = (kind, tier, time.time())
        self.queues[kind].append(s)
        s.send({"t": "queued", "kind": kind, "tier": tier})

    def leave_queue(self, s):
        if s.queue:
            try:
                self.queues[s.queue[0]].remove(s)
            except ValueError:
                pass
            s.queue = None

    def h_unqueue(self, s, m):
        if s.queue:
            self.leave_queue(s)
            s.send({"t": "unqueued"})

    def match_queues(self):
        now = time.time()
        for kind, waitmax, size_lo, size_hi in (("run", self.cfg.queue_wait_run, 2, 4), ("raid", self.cfg.queue_wait_raid, self.cfg.raid_min, 8)):
            q = self.queues[kind]
            tiers = {}
            for s in q:
                tiers.setdefault(s.queue[1], []).append(s)
            for tier, grp in tiers.items():
                grp.sort(key=lambda x: x.queue[2])
                oldest = now - grp[0].queue[2]
                if len(grp) >= size_hi or (len(grp) >= size_lo and oldest >= waitmax * 0.5) or (len(grp) >= 1 and kind == "run" and oldest >= waitmax):
                    pick = best_window([(int(x.char["level"]), x.queue[2], x) for x in grp], size_hi)
                    if len(pick) < size_lo:
                        if oldest < waitmax:
                            continue              # nobody close enough in level yet: wait a little longer
                        pick = grp[:size_hi]      # waited the full time: go, penalty and all (the party was warned)
                    for x in pick:
                        self.leave_queue(x)
                    self.start_instance(kind, tier, pick)

    # ---- instances ------------------------------------------------------------------------------------------------------------------------------
    def start_instance(self, kind, tier, sessions, world_id=None):
        iid = self.next_iid
        self.next_iid += 1
        depth = self.depth_of(tier)
        chars = [s.char for s in sessions]
        inst = engine.Instance(iid, kind, tier, depth, chars, self.data, rng=random.Random(iid * 7919 + int(time.time()) % 1000))
        rec = {"inst": inst, "sessions": {s.char["char_id"]: s for s in sessions}, "ended_at": None, "paid": False, "world_id": world_id}
        self.instances[iid] = rec
        for s in sessions:
            self.leave_queue(s)
            self.hub_leave(s)
            s.where = "instance"
            s.inst = iid
            s.send({"t": "inst_start", "id": iid, "kind": kind, "tier": tier, "depth": depth, "radius": inst.R,
                    "spread": level_spread([c["level"] for c in chars]) if kind in SPREAD_KINDS else 0,
                    "penalty": spread_penalty(level_spread([c["level"] for c in chars])) if kind in SPREAD_KINDS else 0.0,
                    "me": s.char["char_id"], "hpmax": round(inst.player_hp()), "members": [s2.pub() for s2 in sessions], "boss": self.data["enemies"][inst.boss_type].get("name", "")})
        return iid

    def h_i_move(self, s, m):
        rec = self.instances.get(s.inst) if s.inst else None
        if rec:
            rec["inst"].move(s.char["char_id"], float(m.get("x", 0)), float(m.get("z", 0)), float(m.get("yaw", 0)))

    def h_i_hit(self, s, m):
        rec = self.instances.get(s.inst) if s.inst else None
        if rec:
            rec["inst"].hit(s.char["char_id"], int(m.get("foe", 0)), float(m.get("amt", 0)))

    def h_i_leave(self, s, m):
        rec = self.instances.get(s.inst) if s.inst else None
        if rec:
            rec["inst"].leave(s.char["char_id"])
            rec["sessions"].pop(s.char["char_id"], None)
        s.inst = None
        s.where = "char"
        s.send({"t": "left_inst"})

    def finish_instance(self, rec):
        inst = rec["inst"]
        if rec["paid"]:
            return
        rec["paid"] = True
        rec["ended_at"] = time.time()
        rewards = inst.rewards()
        bonus = self.bonus_now()
        elapsed = inst.result_t - inst.cfg["start_delay"]
        summary = inst.summary()
        pen = 0.0
        spread = 0
        if inst.kind in SPREAD_KINDS:
            lv = []
            for cid in rewards:
                c0 = self.store.char_by_id(cid)
                if c0 is not None:
                    lv.append(c0["level"])
            spread = level_spread(lv)
            pen = spread_penalty(spread)
        for cid, rw in rewards.items():
            c = self.store.char_by_id(cid)
            if c is None:
                continue
            live = self.sessions.get(cid)
            if live is not None:
                c = live.char                 # the session's copy is the one in memory
            if inst.kind == "raid" and inst.result == "won":
                rw["marks"] = int(rw["marks"] * bonus)
                rw["gold"] = int(rw["gold"] * bonus)
            if pen > 0:
                apply_spread(rw, pen, inst.rng)
                rw["spread"] = spread
                rw["penalty"] = pen
            c["gold"] += rw["gold"]
            c["marks"] += rw["marks"]
            c["xp"] += rw["xp"]
            while c["xp"] >= 100 * c["level"] * c["level"] and c["level"] < 99:
                c["xp"] -= 100 * c["level"] * c["level"]
                c["level"] += 1
            for k, n in rw["items"].items():
                c["inv"][k] = c["inv"].get(k, 0) + n
            title = None
            if inst.result == "won":
                title = {"run": "Gate Runner %d" % inst.tier, "raid": "Raid Slayer %d" % inst.tier, "world": "Titan Breaker"}[inst.kind]
                if title not in c["titles"]:
                    c["titles"].append(title)
                    rw["title"] = title
                self.store.add_score("kills", c, next((x["kills"] for x in summary if x["id"] == cid), 0))
                if inst.kind == "run":
                    self.store.post_score("run_time_t%d" % inst.tier, c, elapsed)
                elif inst.kind == "raid":
                    self.store.post_score("raid_time", c, elapsed)
            if inst.result == "won":
                pts = int(POINTS.get(inst.kind, 0) * (inst.tier if inst.kind in ("run", "raid") else 1) * (1.0 - pen))
                self.store.add_season_points(self.season()["season"], c, pts)
                rw["season_points"] = pts
            self.store.add_score("boss_damage", c, next((x["dealt"] for x in summary if x["id"] == cid), 0))
            self.store.save_char(c)
            if live is not None:
                live.send({"t": "i_end", "result": inst.result, "time": round(elapsed, 1), "reward": rw, "summary": summary, "char": self.char_pub(c)})

    # ---- world events ----------------------------------------------------------------------------------------------------------------------------
    def event_windows(self, now=None):
        now = now or time.time()
        out = []
        for e in self.events_def:
            period = e["period_min"] * 60.0
            dur = e["duration_min"] * 60.0
            off = e.get("offset_min", 0) * 60.0
            k = math.floor((now - off) / period)
            start = off + k * period
            if now < start + dur:
                out.append({"id": e["id"], "kind": e["kind"], "name": e["name"], "start": start, "end": start + dur, "active": start <= now,
                            "tier": e.get("tier", 5), "bonus": e.get("bonus", 1.0)})
            else:
                nxt = off + (k + 1) * period
                out.append({"id": e["id"], "kind": e["kind"], "name": e["name"], "start": nxt, "end": nxt + dur, "active": False,
                            "tier": e.get("tier", 5), "bonus": e.get("bonus", 1.0)})
        return out

    def season(self):
        return season_info(days=int(self.cfg.season_days))

    def close_old_seasons(self):
        """called now and then: any finished season gets its standings archived and its titles given, once"""
        cur = self.season()["season"]
        done = 0
        for sn in range(1, cur):
            done += self.store.close_season(sn, season_rewards(sn))
        return done

    def h_season(self, s, m):
        info = self.season()
        sn = info["season"]
        want = m.get("season")
        if isinstance(want, int) and 1 <= want < sn:
            rows = [{"name": r["name"], "points": r["points"]} for r in self.store.db.execute("select name,points from season_archive where season=? order by rank limit 10", (want,)).fetchall()]
            s.send({"t": "season", "season": want, "past": True, "rows": rows})
            return
        s.send({"t": "season", "season": sn, "ends": info["ends"], "past": False, "rows": self.store.season_top(sn, 10),
                "me": self.store.season_me(sn, s.char) if s.char else {"points": 0, "rank": 0}, "server_time": time.time()})

    def event_list(self):
        return self.event_windows()

    def bonus_now(self):
        b = 1.0
        for w in self.event_windows():
            if w["active"] and w["kind"] == "bonus":
                b = max(b, w["bonus"])
        return b

    def scheduler(self):
        for w in self.event_windows():
            if w["kind"] != "world":
                continue
            key = (w["id"], int(w["start"]))
            rec = self.instances.get(self.world.get(key)) if key in self.world else None
            if w["active"] and key not in self.world:
                iid = self.start_instance("world", w["tier"], [], world_id=key)
                self.world[key] = iid
                self.instances[iid]["inst"].phase_t = 5.0
                for s in list(self.sessions.values()):
                    if s.where == "hub":
                        s.send({"t": "event_start", "event": w, "iid": iid})
            elif key in self.world and not w["active"]:
                r = self.instances.get(self.world[key])
                if r and r["inst"].phase not in ("won", "failed"):
                    r["inst"]._finish("failed")

    def h_event_join(self, s, m):
        if s.where != "hub":
            return
        for key, iid in self.world.items():
            r = self.instances.get(iid)
            if r and r["inst"].phase not in ("won", "failed") and (not m.get("id") or key[0] == m.get("id")):
                err = self.tier_ok(s.char, r["inst"].tier)
                if err:
                    s.send({"t": "party_error", "msg": err})
                    return
                mem = r["inst"].join(s.char)
                if mem is None:
                    s.send({"t": "party_error", "msg": "The event is full."})
                    return
                self.leave_queue(s)
                self.leave_party(s)
                self.hub_leave(s)
                r["sessions"][s.char["char_id"]] = s
                s.where = "instance"
                s.inst = iid
                inst = r["inst"]
                s.send({"t": "inst_start", "id": iid, "kind": inst.kind, "tier": inst.tier, "depth": inst.depth, "radius": inst.R, "me": s.char["char_id"], "hpmax": round(inst.player_hp()),
                        "members": [o.pub() for o in r["sessions"].values()], "boss": self.data["enemies"][inst.boss_type].get("name", ""),
                        "late": True, "foes": [f.pub() for f in inst.foes.values() if f.alive], "hazards": [h.pub() for h in inst.hazards]})
                return
        s.send({"t": "party_error", "msg": "No event is running right now."})

    # ---- boards, market, mail, inventory ------------------------------------------------------------------------------------------------------------
    def h_lb(self, s, m):
        b = str(m.get("board", ""))
        if b in BOARDS:
            s.send({"t": "lb", "board": b, "rows": self.store.top(b, 10), "better": BOARDS[b]})

    def h_events(self, s, m):
        s.send({"t": "events", "events": self.event_list(), "server_time": time.time()})

    def h_inv(self, s, m):
        if s.char:
            s.send({"t": "char", "char": self.char_pub(s.char)})

    def h_m_list(self, s, m):
        item = str(m.get("item", ""))
        if self.data["items"].get(item, {}).get("type") != "material":
            s.send({"t": "market_error", "msg": "Only materials can be sold here."})
            return
        lid, err = self.store.list_item(s.char, item, int(m.get("qty", 0)), int(m.get("price", 0)))
        s.send({"t": "market_ok", "id": lid} if lid else {"t": "market_error", "msg": err})
        s.send({"t": "char", "char": self.char_pub(s.char)})

    def h_m_search(self, s, m):
        s.send({"t": "market", "rows": self.store.listings(str(m.get("item", "")) or None)})

    def h_m_buy(self, s, m):
        ok, err = self.store.buy(s.char, int(m.get("id", 0)), int(m.get("qty", 1)))
        s.send({"t": "market_ok"} if ok else {"t": "market_error", "msg": err})
        s.send({"t": "char", "char": self.char_pub(s.char)})

    def h_m_cancel(self, s, m):
        s.send({"t": "market_ok"} if self.store.cancel(s.char, int(m.get("id", 0))) else {"t": "market_error", "msg": "Not yours, or already gone."})
        s.send({"t": "char", "char": self.char_pub(s.char)})

    def h_mail_list(self, s, m):
        s.send({"t": "mail", "rows": self.store.inbox(s.char["char_id"])})

    def h_mail_claim(self, s, m):
        self.store.claim_mail(s.char, int(m.get("id", 0)))
        s.send({"t": "char", "char": self.char_pub(s.char)})
        s.send({"t": "mail", "rows": self.store.inbox(s.char["char_id"])})

    def h_mail_delete(self, s, m):
        self.store.delete_mail(s.char, int(m.get("id", 0)))
        s.send({"t": "mail", "rows": self.store.inbox(s.char["char_id"])})

    def h_mail_send(self, s, m):
        to = self.store.char_by_name(str(m.get("to", "")))
        if to is None:
            s.send({"t": "mail_error", "msg": "No such character."})
            return
        gold = max(0, int(m.get("gold", 0)))
        if gold > s.char["gold"]:
            s.send({"t": "mail_error", "msg": "Not enough gold."})
            return
        s.char["gold"] -= gold
        self.store.save_char(s.char)
        self.store.send_mail(to["char_id"], s.char["name"], filter_chat(str(m.get("subject", "(no subject)"))), filter_chat(str(m.get("body", ""))), {}, gold)
        s.send({"t": "mail_ok"})
        s.send({"t": "char", "char": self.char_pub(s.char)})
        o = self.sessions.get(to["char_id"])
        if o:
            o.send({"t": "mail_new"})

    def h_withdraw(self, s, m):
        """materials leave for the solo game: taken from the server inventory, kept as a pending grant until the game acknowledges"""
        items = {str(k): int(v) for k, v in (m.get("items") or {}).items() if int(v) > 0 and self.data["items"].get(str(k), {}).get("type") == "material"}
        if not items:
            s.send({"t": "error", "msg": "Nothing to take."})
            return
        gid = self.store.make_grant(s.char, items)
        if gid is None:
            s.send({"t": "error", "msg": "You don't have that."})
            return
        s.send({"t": "grant", "id": gid, "items": items})
        s.send({"t": "char", "char": self.char_pub(s.char)})

    def h_grant_ack(self, s, m):
        self.store.ack_grant(s.char["char_id"], int(m.get("id", 0)))

    # ---- the clock ------------------------------------------------------------------------------------------------------------------------------------------
    async def loop(self):
        last = time.time()
        acc = 0.0
        n = 0
        while True:
            await asyncio.sleep(0.05)
            now = time.time()
            acc += (now - last) * self.cfg.speed
            last = now
            while acc >= engine.TICK:
                acc -= engine.TICK
                n += 1
                self.step(n)

    def step(self, n):
        for iid in list(self.instances):
            rec = self.instances[iid]
            inst = rec["inst"]
            inst.tick(engine.TICK)
            for to, msg in inst.drain():
                if to is None:
                    for s in list(rec["sessions"].values()):
                        s.send(msg)
                elif to in rec["sessions"]:
                    rec["sessions"][to].send(msg)
            if inst.result and not rec["paid"]:
                self.finish_instance(rec)
            if rec["paid"] and (time.time() - rec["ended_at"] > 120 or not rec["sessions"]):
                for s in rec["sessions"].values():
                    if s.inst == iid:
                        s.inst = None
                        s.where = "char"
                del self.instances[iid]
                for key, v in list(self.world.items()):
                    if v == iid:
                        pass
            elif inst.kind == "world" and not rec["sessions"] and inst.phase == "countdown":
                pass
        if n % 2 == 0:                                   # hub positions at 5 Hz
            for shard, members in self.hubs.items():
                if len(members) > 1:
                    snap = [[s.char["char_id"], round(s.hx, 2), round(s.hz, 2), round(s.hyaw, 2), s.anim] for s in members]
                    msg = {"t": "h_state", "p": snap}
                    for s in members:
                        s.send(msg)
        if n % 3000 == 0:
            self.close_old_seasons()
        if n % 10 == 0:
            self.match_queues()
            self.scheduler()
        if n % 300 == 0:
            for s in list(self.conns):
                if time.time() - s.last_seen > 90:
                    s.closed = True
                    asyncio.get_event_loop().create_task(s.ws.close())

    async def run(self):
        try:
            from websockets.asyncio.server import serve
        except ImportError:
            from websockets import serve
        async with serve(self.handle, self.cfg.host, self.cfg.port, max_size=2 ** 16, ping_interval=20, ping_timeout=30):
            print("Elite Online %d listening on %s:%d (%s)" % (VERSION, self.cfg.host, self.cfg.port, "DEV, no accounts" if self.cfg.dev else "accounts via Supabase"), flush=True)
            await self.loop()


def admin(argv):
    """python3 elite_server.py admin ban|unban|mute|reports|char <args>"""
    cfg = Config()
    st = Store(cfg.db)
    cmd = argv[0] if argv else "help"
    if cmd == "reports":
        for r in st.db.execute("select * from reports order by id desc limit 50"):
            print(dict(r))
    elif cmd in ("ban", "unban"):
        c = st.char_by_name(argv[1])
        if not c:
            print("no such character")
            return
        st.ban(c["account_id"], " ".join(argv[2:]), cmd == "ban")
        print(cmd, c["name"], c["account_id"])
    elif cmd == "mute":
        c = st.char_by_name(argv[1])
        st.mute(c["account_id"], float(argv[2]) * 60)
        print("muted", c["name"], argv[2], "min")
    elif cmd == "char":
        print(st.char_by_name(argv[1]))
    else:
        print(admin.__doc__)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "admin":
        admin(sys.argv[2:])
    else:
        asyncio.run(Server().run())
