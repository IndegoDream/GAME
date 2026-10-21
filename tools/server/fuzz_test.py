#!/usr/bin/env python3
"""Fuzz: every handler gets garbage (wrong types, huge numbers, NaN, negatives, nested junk). The server must stay up, answer a fresh
client afterwards, never crash a handler (stderr 'handler error'), and gold/items must never go up from garbage."""
import asyncio, itertools, json, os, subprocess, sys, tempfile
from pathlib import Path
from websockets.asyncio.client import connect
HERE = Path(__file__).parent
PORT = 18773
JUNK = [None, "abc", "", -1, 0, 10**30, -10**30, 1e308, float("nan"), True, [], [1, "a", None], {}, {"a": {"b": [1]}}, "x" * 5000, "<script>", "💥"]
SKIP = {"hello", "delete_account"}
passed = failed = 0


def check(n, ok, extra=""):
    global passed, failed
    if ok: passed += 1
    else:
        failed += 1; print("  FAIL", n, extra)


BG = {}


async def _reader(w, buf):
    try:
        async for raw in w:
            buf.append(json.loads(raw))
    except Exception:
        pass


async def drain(w, secs=0.2):
    """a well-behaved client reads continuously (the server drops clients that don't); this returns what arrived in `secs`"""
    if id(w) not in BG:
        BG[id(w)] = []
        asyncio.create_task(_reader(w, BG[id(w)]))
    await asyncio.sleep(secs)
    out = BG[id(w)][:]
    BG[id(w)].clear()
    return out


def tolerant(w):
    raw = w.send
    async def send(x):
        try:
            await raw(x)
        except Exception:
            pass
    w.send = send
    return w


async def main():
    sys.path.insert(0, str(HERE))
    import elite_server
    names = sorted(n[2:] for n in dir(elite_server.Server) if n.startswith("h_") and n[2:] not in SKIP)
    tmp = tempfile.mkdtemp()
    env = dict(os.environ, ELITE_DEV="1", ELITE_PORT=str(PORT), ELITE_DB=tmp + "/t.db", ELITE_HOST="127.0.0.1", ELITE_RATE="100000")
    p = subprocess.Popen([sys.executable, str(HERE / "elite_server.py")], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    for _ in range(50):
        await asyncio.sleep(0.2)
        try:
            w = await connect("ws://127.0.0.1:%d" % PORT); await w.close(); break
        except Exception:
            pass
    try:
        w = tolerant(await connect("ws://127.0.0.1:%d" % PORT))
        await drain(w, 0.01)
        await w.send(json.dumps(dict(t="hello", build=1, dev="Fuzzer")))
        await drain(w)
        await w.send(json.dumps(dict(t="create_char", name="Fuzzer", realm=0, step=1)))
        ch = [m for m in await drain(w) if m["t"] == "char"]
        check("char created", bool(ch))
        gold0 = ch[0]["char"]["gold"] if ch else 0
        await w.send(json.dumps(dict(t="enter_hub")))
        await drain(w)
        sent = 0
        for n in names:
            if w.close_code is not None:
                check("connection survived before handler " + n, False)
                break
            keys = ["to", "gold", "items", "foe", "amt", "x", "z", "yaw", "text", "ch", "id", "name", "kind", "price", "qty", "item", "subject", "body", "target", "who", "reason", "tier", "event", "q", "page", "shard", "n", "count"]
            for j in JUNK:
                for k in keys[:: 3 if j in ("x" * 5000,) else 1]:
                    await w.send(json.dumps({"t": n, k: j}, allow_nan=True)); sent += 1
                if sent % 40 == 0:
                    await asyncio.sleep(0.03)
                jj = j if not (isinstance(j, str) and len(j) > 1000) else j[:1000]
                await w.send(json.dumps({"t": n, **{k: jj for k in keys}}, allow_nan=True)); sent += 1
                if sent % 40 == 0:
                    await asyncio.sleep(0.03)
            await drain(w, 0.05)
        await drain(w, 0.5)
        print("  closed before bare phase:", w.close_code)
        for n in names:                                   # also bare, and with raw non-JSON / non-object frames
            await w.send(json.dumps({"t": n})); await asyncio.sleep(0.05)
            if w.close_code is not None:
                print("  closed after bare", n); break
        for raw in ["", "{", "[]", "null", "123", '"t"', '{"t": 5}', '{"t": []}', '{"t": null}']:
            await w.send(raw)
        await drain(w, 0.5)
        print("  sent %d hostile messages; ws closed=%s" % (sent, w.close_code))
        print("  fuzzed connection %s (a flooding client may be dropped; that is allowed)" % ("dropped" if w.close_code is not None else "still open"))
        w2 = await connect("ws://127.0.0.1:%d" % PORT)
        await drain(w2, 0.01)
        await w2.send(json.dumps(dict(t="hello", build=1, dev="Fresh")))
        fresh = await drain(w2, 1.0)
        check("fresh client still welcomed", any(m["t"] == "welcome" for m in fresh))
        check("server process alive", p.poll() is None)
        w3 = await connect("ws://127.0.0.1:%d" % PORT)     # gold check through a re-login
        await drain(w3, 0.01)
        await w3.send(json.dumps(dict(t="hello", build=1, dev="Fuzzer")))
        wel = [m for m in await drain(w3, 1.0) if m["t"] == "welcome"]
        gold1 = wel[0]["char"]["gold"] if wel and wel[0].get("char") else None
        check("gold never rose from garbage", gold1 is not None and gold1 <= gold0, "%s -> %s" % (gold0, gold1))
    finally:
        p.terminate()
        err = p.stderr.read()
        errs = [l for l in err.splitlines() if "handler error" in l]
        check("no handler raised (%d)" % len(errs), not errs, "\n".join(sorted(set(errs))[:12]))
    print("FUZZ %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)

asyncio.run(main())
