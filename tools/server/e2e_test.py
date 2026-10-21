#!/usr/bin/env python3
"""End-to-end: starts a real server (dev mode, temp database, sped-up clock) and plays bot clients against it over WebSockets.
    python3 e2e_test.py"""
import asyncio, json, os, subprocess, sys, tempfile, time, math
from pathlib import Path
from websockets.asyncio.client import connect

HERE = Path(__file__).parent
PORT = 18765
URL = "ws://127.0.0.1:%d" % PORT
passed = failed = 0


def check(name, ok, extra=""):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print("  FAIL ", name, extra)


class Bot:
    def __init__(self, name):
        self.name = name
        self.ws = None
        self.q = asyncio.Queue()
        self.log = []
        self.me = 0
        self.pos = (0.0, 0.0)
        self.foes = {}
        self.haz = {}
        self.fight = False
        self.end = None

    async def open(self):
        self.ws = await connect(URL)
        self.task = asyncio.create_task(self.reader())

    async def reader(self):
        try:
            async for raw in self.ws:
                m = json.loads(raw)
                self.log.append(m)
                if m["t"] == "inst_start":
                    self.me = m["me"]
                if m["t"] == "i_state":
                    for p in m["p"]:
                        if p[0] == self.me:
                            self.pos = (p[1], p[2])
                    self.foes = {f[0]: f for f in m["f"]}
                if m["t"] == "i_hazard":
                    self.haz[m["h"]["id"]] = m["h"]
                if m["t"] == "i_boom":
                    self.haz.pop(m["id"], None)
                if m["t"] == "i_end":
                    self.end = m
                await self.q.put(m)
        except Exception:
            pass

    async def send(self, **kw):
        await self.ws.send(json.dumps(kw))

    async def wait(self, t, timeout=10, pred=None):
        end = time.time() + timeout
        while time.time() < end:
            try:
                m = await asyncio.wait_for(self.q.get(), timeout=max(0.05, end - time.time()))
            except asyncio.TimeoutError:
                break
            if m["t"] == t and (pred is None or pred(m)):
                return m
        return None

    async def fighter(self):
        """walks to the nearest foe and swings; steps out of telegraphed circles, into the safe zone"""
        while self.end is None and self.fight:
            tx = tz = None
            for h in list(self.haz.values()):
                if h["kind"] == "circle" and math.hypot(self.pos[0] - h["x"], self.pos[1] - h["z"]) < h["r"] + 0.7:
                    d = math.hypot(self.pos[0] - h["x"], self.pos[1] - h["z"]) or 1
                    tx, tz = self.pos[0] + (self.pos[0] - h["x"]) / d * 4, self.pos[1] + (self.pos[1] - h["z"]) / d * 4
                elif h["kind"] == "safe" and h.get("zones"):
                    z = min(h["zones"], key=lambda z: math.hypot(self.pos[0] - z[0], self.pos[1] - z[1]))
                    tx, tz = z[0], z[1]
            if tx is not None:
                self.pos = (tx, tz)
                await self.send(t="i_move", x=tx, z=tz, yaw=0)
            elif self.foes:
                best = min(self.foes.values(), key=lambda f: math.hypot(f[1] - self.pos[0], f[2] - self.pos[1]))
                d = math.hypot(best[1] - self.pos[0], best[2] - self.pos[1])
                if d > 3.0:
                    k = min(1.0, 2.0 / d)
                    self.pos = (self.pos[0] + (best[1] - self.pos[0]) * k, self.pos[1] + (best[2] - self.pos[1]) * k)
                    await self.send(t="i_move", x=self.pos[0], z=self.pos[1], yaw=0)
                await self.send(t="i_hit", foe=best[0], amt=500)       # the server clamps this to what the rank could do
            await asyncio.sleep(0.1)


async def main():
    tmp = tempfile.mkdtemp()
    env = dict(os.environ, ELITE_DEV="1", ELITE_PORT=str(PORT), ELITE_DB=os.path.join(tmp, "t.db"), ELITE_SPEED="2",
               ELITE_QUEUE_WAIT_RUN="2", ELITE_HOST="127.0.0.1", ELITE_EVENTS=os.path.join(tmp, "ev.json"))
    json.dump({"events": [{"id": "crater_titan", "kind": "world", "name": "The Crater Titan", "period_min": 1440, "duration_min": 1439, "offset_min": 0, "tier": 2, "bonus": 1.0}]}, open(os.path.join(tmp, "ev.json"), "w"))
    srv = subprocess.Popen([sys.executable, str(HERE / "elite_server.py")], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        for _ in range(50):
            await asyncio.sleep(0.2)
            try:
                w = await connect(URL)
                await w.close()
                break
            except Exception:
                pass
        else:
            print(srv.stdout.read())
            raise SystemExit("server did not start")

        # --- login gate
        x = Bot("x"); await x.open()
        await x.send(t="chat", ch="hub", text="hi")
        await x.send(t="hello", build=1, dev="")
        m = await x.wait("error", 3)
        check("no name, no entry", m is not None and m.get("code") == "auth")

        a, b, c = Bot("Alpha"), Bot("Bravo"), Bot("Charlie")
        for bot in (a, b, c):
            await bot.open()
            await bot.send(t="hello", build=1, dev=bot.name)
            w = await bot.wait("welcome", 3)
            check(bot.name + " welcome", w is not None and not w["has_char"])
        await a.send(t="create_char", name="A", realm=0, step=1)
        check("bad name refused", (await a.wait("char_error", 3)) is not None)
        for bot in (a, b, c):
            await bot.send(t="create_char", name=bot.name, realm=9, step=99)
            ch = await bot.wait("char", 3)
            check(bot.name + " created, import capped", ch is not None and ch["char"]["realm"] <= 3 and ch["char"]["step"] <= 10)

        # --- hub, chat
        for bot in (a, b, c):
            await bot.send(t="enter_hub")
            check(bot.name + " in hub", (await bot.wait("hub", 3)) is not None)
        await asyncio.sleep(0.5)
        await a.send(t="chat", ch="hub", text="hello world")
        m = await b.wait("chat", 3, lambda m: m["from"] == "Alpha")
        check("hub chat reaches others", m is not None and m["text"] == "hello world")
        await a.send(t="chat", ch="whisper", to="Bravo", text="psst")
        check("whisper", (await b.wait("chat", 3, lambda m: m["ch"] == "whisper")) is not None)
        await a.send(t="h_move", x=999, z=-999, yaw=0)
        await asyncio.sleep(0.6)
        st = [m for m in b.log if m["t"] == "h_state"]
        check("hub position clamped", st and all(abs(p[1]) <= 44.01 and abs(p[2]) <= 44.01 for p in st[-1]["p"]))

        # --- market + mail (before the run)
        await a.send(t="m_list", item="iron_ore", qty=1, price=5)
        m = await a.wait("market_error", 3)
        check("cannot sell what you don't have", m is not None)
        await a.send(t="mail_send", to="Bravo", subject="hello", body="mail body", gold=0)
        check("mail sent", (await a.wait("mail_ok", 3)) is not None)
        check("mail arrives live", (await b.wait("mail_new", 3)) is not None)
        await b.send(t="mail_list")
        m = await b.wait("mail", 3)
        check("mail in inbox", m is not None and len(m["rows"]) == 1)

        # --- party -> dungeon run
        await a.send(t="p_invite", name="Bravo")
        inv = await b.wait("p_invited", 3)
        check("invite delivered", inv is not None)
        await b.send(t="p_accept", pid=inv["pid"])
        check("party formed", (await a.wait("party", 3, lambda m: len(m.get("members", [])) == 2)) is not None)
        await b.send(t="p_start", kind="run", tier=1)
        check("only the leader starts", (await b.wait("party_error", 3)) is not None)
        await a.send(t="p_start", kind="run", tier=9)
        check("tier gate", (await a.wait("party_error", 3)) is not None)
        await a.send(t="p_start", kind="run", tier=1)
        s1 = await a.wait("inst_start", 5)
        s2 = await b.wait("inst_start", 5)
        check("run starts for both", s1 is not None and s2 is not None and s1["kind"] == "run")
        for bot in (a, b):
            bot.fight = True
        tasks = [asyncio.create_task(a.fighter()), asyncio.create_task(b.fighter())]
        t0 = time.time()
        while (a.end is None or b.end is None) and time.time() - t0 < 160:
            await asyncio.sleep(0.5)
        for bot in (a, b):
            bot.fight = False
        check("run ended for both", a.end is not None and b.end is not None, "elapsed %.0f" % (time.time() - t0))
        if a.end:
            print("   run result:", a.end["result"], "sim", a.end["time"], "s; reward", a.end["reward"], [(x["name"], x["downs"], x["dealt"]) for x in a.end["summary"]])
            check("run reward shape", set(a.end["reward"]) >= {"gold", "marks", "xp", "items"})
            if a.end["result"] == "won":
                check("won run paid gold", a.end["reward"]["gold"] > 0)
                check("online loot is materials only", all(k not in ("breakthrough_pill",) for k in a.end["reward"]["items"]))
                check("title earned", "Gate Runner 1" in a.end["char"]["titles"])
        await a.send(t="season")
        sm = await a.wait("season", 3)
        check("season ladder answers", sm is not None and "rows" in sm and "me" in sm and sm.get("past") is False)
        if sm and a.end and a.end["result"] == "won":
            check("a won run scored season points", sm["me"]["points"] >= 10 and sm["me"]["rank"] >= 1, str(sm["me"]))
            check("reward carries the points", a.end["reward"].get("season_points", 0) >= 10)
            check("ladder lists the winner", any(r["name"] == "Alpha" for r in sm["rows"]), str(sm["rows"]))
        await a.send(t="lb", board="boss_damage")
        m = await a.wait("lb", 3)
        check("leaderboard answers", m is not None and "rows" in m)

        # --- withdraw -> grant -> ack
        await asyncio.sleep(0.3)
        await a.send(t="inv")
        inv = (await a.wait("char", 3))["char"]["inv"]
        if inv:
            k = sorted(inv)[0]
            await a.send(t="withdraw", items={k: 1})
            g = await a.wait("grant", 3)
            check("withdraw yields a grant", g is not None and g["items"] == {k: 1})
            await a.send(t="inv")
            inv2 = (await a.wait("char", 3))["char"]["inv"]
            check("withdraw takes from the server", inv2.get(k, 0) == inv[k] - 1)
            await a.send(t="withdraw", items={k: 10 ** 6})
            check("cannot withdraw more than you own", (await a.wait("error", 3)) is not None)
            # drop and come back: the grant is still waiting until acked
            await a.ws.close()
            a2 = Bot("Alpha"); await a2.open()
            await a2.send(t="hello", build=1, dev="Alpha")
            await a2.wait("welcome", 3)
            g2 = await a2.wait("grant", 3)
            check("unacked grant is re-sent on login", g2 is not None)
            if g2:
                await a2.send(t="grant_ack", id=g2["id"])
                await asyncio.sleep(0.3)
                a3 = Bot("Alpha"); await a3.open()
                await a3.send(t="hello", build=1, dev="Alpha")
                await a3.wait("welcome", 3)
                check("acked grant is not re-sent", (await a3.wait("grant", 1.5)) is None)
                a = a3
        else:
            print("   (no materials won, withdraw not exercised)")

        # --- queue: solo player queues, gets a run after the wait
        await c.send(t="queue", kind="run", tier=1)
        check("queued", (await c.wait("queued", 3)) is not None)
        m = await c.wait("inst_start", 8)
        check("queue matched after the wait", m is not None)
        await c.send(t="i_leave")
        check("can leave an instance", (await c.wait("left_inst", 3)) is not None)

        # --- world event: join and leave
        await c.send(t="enter_hub")
        await c.wait("hub", 3)
        await c.send(t="event_join")
        m = await c.wait("inst_start", 4)
        check("world boss event is joinable", m is not None and m["kind"] == "world")
        if m:
            await c.send(t="i_leave")
            await c.wait("left_inst", 3)

        # --- reports, delete
        await b.send(t="report", name="Charlie", reason="test")
        check("report accepted", (await b.wait("reported", 3)) is not None)
        await b.send(t="delete_account", confirm="no")
        check("delete needs the word", (await b.wait("error", 3)) is not None)
        await b.send(t="delete_account", confirm="DELETE")
        check("account deleted", (await b.wait("account_deleted", 3)) is not None)
        b2 = Bot("Bravo"); await b2.open()
        await b2.send(t="hello", build=1, dev="Bravo")
        w = await b2.wait("welcome", 3)
        check("deleted account starts over", w is not None and not w["has_char"])
        await asyncio.sleep(0.3)
        check("server survived", srv.poll() is None)
    finally:
        srv.terminate()
        out = srv.stdout.read() if srv.stdout else ""
        if "Traceback" in out or "handler error" in out:
            print(out[-2000:])
            global failed
            failed += 1
    print("E2E TEST %d passed, %d failed" % (passed, failed))
    return failed


sys.exit(1 if asyncio.run(main()) else 0)
