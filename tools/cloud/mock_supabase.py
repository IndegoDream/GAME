"""A tiny stand-in for Supabase auth + PostgREST, for tools/cloud_check.gd (no network, no account).
   python3 mock_supabase.py <port>   -- state is in memory; GET /__state shows it."""
import json, sys, time, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
ANON = "test-anon-key"
USERS = {"robert@example.com": {"id": "u-1", "password": "correct horse"}}
TOKENS = {}
ROWS = {}
STATS = {"refreshes": 0, "logins": 0, "posts": 0}
ENTS = {}                      # (user, product) -> {"state", "token"}
OWNERS = {}                    # token -> user id (one purchase, one account)
def mint(email):
    n = len(TOKENS) + 1
    t = "tok%d" % n
    TOKENS[t] = email
    return {"access_token": t, "refresh_token": "ref-" + email, "expires_in": 3600, "expires_at": time.time() + 3600,
            "user": {"id": USERS[email]["id"], "email": email}}
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, code, obj=None):
        b = b"" if obj is None else json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}") if n else {}
    def _user(self):
        if self.headers.get("apikey") != ANON: return None
        a = self.headers.get("Authorization", "")
        return TOKENS.get(a[7:]) if a.startswith("Bearer ") else None
    def do_GET(self):
        u = urllib.parse.urlparse(self.path); q = urllib.parse.parse_qs(u.query)
        if u.path == "/__state": return self._send(200, {"rows": {"%s|%s|%s" % k: v["saved_at"] for k, v in ROWS.items()}, "stats": STATS})
        if u.path == "/rest/v1/entitlements":
            em = self._user()
            if not em: return self._send(401, {"message": "JWT expired"})
            uid = USERS[em]["id"]
            return self._send(200, [{"product": p, "state": v["state"]} for (uu, p), v in ENTS.items() if uu == uid])
        if u.path == "/rest/v1/game_saves":
            em = self._user()
            if not em: return self._send(401, {"message": "JWT expired"})
            uid = USERS[em]["id"]; game = q.get("game", [""])[0].replace("eq.", ""); out = []
            for (ru, rg, rs), v in sorted(ROWS.items(), key=lambda kv: kv[0][2]):
                if ru != uid or rg != game: continue
                if "slot" in q and int(q["slot"][0].replace("eq.", "")) != rs: continue
                out.append(dict(v, slot=rs))
            return self._send(200, out)
        self._send(404, {"message": "nope"})
    def do_POST(self):
        u = urllib.parse.urlparse(self.path); q = urllib.parse.parse_qs(u.query); b = self._body()
        if u.path == "/auth/v1/token":
            if self.headers.get("apikey") != ANON: return self._send(401, {"message": "bad key"})
            if q.get("grant_type") == ["password"]:
                us = USERS.get(b.get("email"))
                if not us or us["password"] != b.get("password"): return self._send(400, {"error": "invalid_grant", "error_description": "Invalid login credentials"})
                STATS["logins"] += 1; return self._send(200, mint(b["email"]))
            if q.get("grant_type") == ["refresh_token"]:
                rt = b.get("refresh_token", "")
                if not rt.startswith("ref-"): return self._send(400, {"error": "invalid_grant", "error_description": "bad refresh"})
                STATS["refreshes"] += 1; return self._send(200, mint(rt[4:]))
        if u.path == "/auth/v1/signup":
            em = b.get("email")
            if em in USERS: return self._send(422, {"msg": "User already registered"})
            USERS[em] = {"id": "u-%d" % (len(USERS) + 1), "password": b.get("password")}
            return self._send(200, {"id": USERS[em]["id"], "email": em})       # (email confirmation on: no session)
        if u.path == "/auth/v1/logout": return self._send(204)
        if u.path == "/functions/v1/verify-purchase":
            em = self._user()
            if not em: return self._send(401, {"error": "sign in first"})
            uid = USERS[em]["id"]; prod = b.get("product", "")
            if b.get("reconcile"):
                e = ENTS.get((uid, prod))
                if e and e["token"].startswith("refund"): e["state"] = "refunded"
                return self._send(200, {"product": prod, "state": e["state"] if e else "none"})
            tok = b.get("purchaseToken", "")
            if OWNERS.get(tok, uid) != uid: return self._send(403, {"error": "this purchase already belongs to another account"})
            if not tok.startswith(("good", "refund")): return self._send(402, {"error": "pending or unknown purchase state"})
            OWNERS[tok] = uid; ENTS[(uid, prod)] = {"state": "active", "token": tok}
            return self._send(200, {"product": prod, "state": "active"})
        if u.path == "/rest/v1/game_saves":
            em = self._user()
            if not em: return self._send(401, {"message": "JWT expired"})
            if b.get("user_id") != USERS[em]["id"]: return self._send(403, {"message": "row-level security"})
            STATS["posts"] += 1
            ROWS[(b["user_id"], b["game"], int(b["slot"]))] = {k: b[k] for k in ("saved_at", "device", "summary", "data")}
            return self._send(201)
        self._send(404, {"message": "nope"})
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
