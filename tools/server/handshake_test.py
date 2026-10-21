#!/usr/bin/env python3
"""Data-hash handshake: matching hash passes, wrong hash is flagged (and refused in strict mode), no hash is not judged."""
import asyncio, json, os, subprocess, sys, tempfile
from pathlib import Path
from websockets.asyncio.client import connect
HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
from elite_server import data_hash
DATA = HERE.parent.parent / "data"
passed = failed = 0


def check(n, ok, extra=""):
    global passed, failed
    if ok: passed += 1
    else:
        failed += 1; print("  FAIL", n, extra)


async def hello(port, **kw):
    w = await connect("ws://127.0.0.1:%d" % port)
    await w.send(json.dumps(dict(t="hello", build=1, dev="Probe", **kw)))
    out = []
    try:
        while True:
            m = json.loads(await asyncio.wait_for(w.recv(), 3))
            out.append(m)
            if m["t"] in ("welcome", "error"):
                break
    except Exception:
        pass
    await w.close()
    return out[-1] if out else {}


async def run(port, strict):
    tmp = tempfile.mkdtemp()
    env = dict(os.environ, ELITE_DEV="1", ELITE_PORT=str(port), ELITE_DB=tmp + "/t.db", ELITE_HOST="127.0.0.1", ELITE_STRICT_DATA="1" if strict else "")
    p = subprocess.Popen([sys.executable, str(HERE / "elite_server.py")], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        await asyncio.sleep(0.2)
        try:
            w = await connect("ws://127.0.0.1:%d" % port); await w.close(); break
        except Exception:
            pass
    try:
        good = data_hash(DATA)
        a = await hello(port, data=good)
        check("matching hash welcomes (strict=%s)" % strict, a.get("t") == "welcome" and a.get("data_ok") is True and a.get("data_hash") == good, str(a))
        b = await hello(port, data="0" * 64)
        if strict:
            check("wrong hash refused", b.get("t") == "error" and b.get("code") == "data_mismatch", str(b))
        else:
            check("wrong hash flagged, not refused", b.get("t") == "welcome" and b.get("data_ok") is False, str(b))
        c = await hello(port)
        check("no hash is not judged", c.get("t") == "welcome" and c.get("data_ok") is True, str(c))
    finally:
        p.terminate()


async def main():
    await run(18771, False)
    await run(18772, True)
    h1 = data_hash(DATA)
    t = tempfile.mkdtemp()
    for n in ("enemies.json", "items.json", "gates.json", "online_events.json"):
        (Path(t) / n).write_bytes((DATA / n).read_bytes())
    check("hash stable across copies", data_hash(t) == h1)
    (Path(t) / "items.json").write_bytes((DATA / "items.json").read_bytes() + b" ")
    check("hash changes when data changes", data_hash(t) != h1)
    print("HANDSHAKE %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)

asyncio.run(main())
