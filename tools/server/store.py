"""Persistent state for the Elite online server (SQLite, one file).

Accounts come from Supabase auth (the account id is the Supabase user id); everything the SERVER owns lives here:
online characters, their gold / marks / materials, the market, mail, leaderboards, reports, bans.
A solo save never writes here and nothing here writes a solo save (the only bridge is `grants`, below)."""
import json, re, sqlite3, time

NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9 _'-]{2,15}$")
BOARDS = {                      # board -> "low" (smaller is better) or "high"
    "run_time_t1": "low", "run_time_t2": "low", "run_time_t3": "low", "run_time_t4": "low", "run_time_t5": "low",
    "run_time_t6": "low", "run_time_t7": "low", "run_time_t8": "low", "run_time_t9": "low", "run_time_t10": "low",
    "raid_time": "low", "boss_damage": "high", "kills": "high", "event_score": "high",
}


class Store:
    def __init__(self, path=":memory:"):
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("pragma journal_mode=wal")
        self.db.executescript("""
        create table if not exists accounts(account_id text primary key, email text, created real, banned integer default 0,
                                            ban_reason text default '', muted_until real default 0);
        create table if not exists chars(char_id integer primary key autoincrement, account_id text unique, name text unique collate nocase,
                                         realm integer, step integer, level integer default 1, xp integer default 0,
                                         gold integer default 0, marks integer default 0, inv text default '{}', titles text default '[]',
                                         flags text default '{}', created real, last_seen real);
        create table if not exists listings(id integer primary key autoincrement, seller integer, item text, qty integer, price integer,
                                            created real, status text default 'open');
        create table if not exists mail(id integer primary key autoincrement, to_char integer, from_name text, subject text, body text,
                                        items text default '{}', gold integer default 0, created real, read integer default 0, claimed integer default 0);
        create table if not exists scores(board text, char_id integer, name text, value real, extra text default '', updated real,
                                          primary key(board, char_id));
        create table if not exists reports(id integer primary key autoincrement, reporter integer, target text, reason text, created real);
        create table if not exists season_points(season integer, char_id integer, name text, points integer default 0, updated real,
                                                 primary key(season, char_id));
        create table if not exists season_archive(season integer, rank integer, char_id integer, name text, points integer);
        create table if not exists meta(k text primary key, v text);
        create table if not exists grants(id integer primary key autoincrement, char_id integer, items text, created real, acked integer default 0);
        """)
        self.db.commit()

    # ---- accounts ------------------------------------------------------------------------------
    def account(self, account_id, email=""):
        r = self.db.execute("select * from accounts where account_id=?", (account_id,)).fetchone()
        if r is None:
            self.db.execute("insert into accounts(account_id,email,created) values(?,?,?)", (account_id, email, time.time()))
            self.db.commit()
            r = self.db.execute("select * from accounts where account_id=?", (account_id,)).fetchone()
        return dict(r)

    def ban(self, account_id, reason="", on=True):
        self.db.execute("update accounts set banned=?, ban_reason=? where account_id=?", (1 if on else 0, reason, account_id))
        self.db.commit()

    def mute(self, account_id, secs):
        self.db.execute("update accounts set muted_until=? where account_id=?", (time.time() + secs, account_id))
        self.db.commit()

    def delete_account(self, account_id):
        """Account deletion (Google Play requires it): the character, mail, listings and scores go; the audit line stays."""
        c = self.char_of(account_id)
        if c:
            cid = c["char_id"]
            for t, col in (("listings", "seller"), ("mail", "to_char"), ("scores", "char_id"), ("grants", "char_id")):
                self.db.execute("delete from %s where %s=?" % (t, col), (cid,))
            self.db.execute("delete from chars where char_id=?", (cid,))
        self.db.execute("delete from accounts where account_id=?", (account_id,))
        self.db.commit()

    # ---- characters ----------------------------------------------------------------------------
    def char_of(self, account_id):
        r = self.db.execute("select * from chars where account_id=?", (account_id,)).fetchone()
        return self._char(r)

    def char_by_name(self, name):
        return self._char(self.db.execute("select * from chars where name=?", (name,)).fetchone())

    def char_by_id(self, cid):
        return self._char(self.db.execute("select * from chars where char_id=?", (cid,)).fetchone())

    @staticmethod
    def _char(r):
        if r is None:
            return None
        d = dict(r)
        d["inv"] = json.loads(d["inv"] or "{}")
        d["titles"] = json.loads(d["titles"] or "[]")
        d["flags"] = json.loads(d.get("flags") or "{}")
        return d

    def create_char(self, account_id, name, realm, step, banned_words=()):
        name = (name or "").strip()
        if not NAME_RE.match(name):
            return None, "Names are 3-16 letters, numbers, spaces, ' _ or -, starting with a letter."
        low = name.lower().replace(" ", "")
        for w in banned_words:
            if w and w in low:
                return None, "That name isn't allowed."
        if self.char_of(account_id):
            return None, "This account already has an online character."
        if self.char_by_name(name):
            return None, "That name is taken."
        now = time.time()
        cur = self.db.execute("insert into chars(account_id,name,realm,step,created,last_seen) values(?,?,?,?,?,?)",
                              (account_id, name, int(realm), int(step), now, now))
        self.db.commit()
        return self.char_by_id(cur.lastrowid), ""

    def save_char(self, c):
        self.db.execute("update chars set realm=?,step=?,level=?,xp=?,gold=?,marks=?,inv=?,titles=?,flags=?,last_seen=? where char_id=?",
                        (c["realm"], c["step"], c["level"], c["xp"], c["gold"], c["marks"], json.dumps(c["inv"]), json.dumps(c["titles"]), json.dumps(c["flags"]),
                         time.time(), c["char_id"]))
        self.db.commit()

    # ---- inventory (server-held materials) -----------------------------------------------------------
    def add_items(self, c, items):
        for k, n in items.items():
            if n > 0:
                c["inv"][k] = c["inv"].get(k, 0) + int(n)
        self.save_char(c)

    def take_items(self, c, items):
        for k, n in items.items():
            if c["inv"].get(k, 0) < n:
                return False
        for k, n in items.items():
            c["inv"][k] -= n
            if c["inv"][k] <= 0:
                del c["inv"][k]
        self.save_char(c)
        return True

    # ---- the market ----------------------------------------------------------------------------------
    FEE = 0.05

    def list_item(self, c, item, qty, price):
        if qty < 1 or price < 1 or price > 10_000_000:
            return None, "Quantity and price must be positive."
        if not self.take_items(c, {item: qty}):
            return None, "You don't have that many."
        cur = self.db.execute("insert into listings(seller,item,qty,price,created) values(?,?,?,?,?)", (c["char_id"], item, qty, price, time.time()))
        self.db.commit()
        return cur.lastrowid, ""

    def listings(self, item=None, limit=50):
        q = "select l.*, c.name as seller_name from listings l join chars c on c.char_id=l.seller where l.status='open'"
        a = []
        if item:
            q += " and l.item=?"
            a.append(item)
        q += " order by l.price asc, l.id asc limit ?"
        a.append(limit)
        return [dict(r) for r in self.db.execute(q, a).fetchall()]

    def buy(self, c, listing_id, qty):
        r = self.db.execute("select * from listings where id=? and status='open'", (listing_id,)).fetchone()
        if r is None:
            return False, "That listing is gone."
        if r["seller"] == c["char_id"]:
            return False, "That's your own listing."
        qty = int(qty)
        if qty < 1 or qty > r["qty"]:
            return False, "Not that many for sale."
        cost = qty * r["price"]
        if c["gold"] < cost:
            return False, "Not enough gold."
        seller = self.char_by_id(r["seller"])
        c["gold"] -= cost
        c["inv"][r["item"]] = c["inv"].get(r["item"], 0) + qty
        self.save_char(c)
        pay = int(cost * (1 - self.FEE))
        left = r["qty"] - qty
        self.db.execute("update listings set qty=?, status=? where id=?", (left, "open" if left > 0 else "sold", listing_id))
        self.db.commit()
        if seller:
            self.send_mail(seller["char_id"], "Market", "Sold: %s x%d" % (r["item"], qty), "Your listing sold for %d gold (after the %d%% fee)." % (pay, int(self.FEE * 100)), {}, pay)
        return True, ""

    def cancel(self, c, listing_id):
        r = self.db.execute("select * from listings where id=? and status='open' and seller=?", (listing_id, c["char_id"])).fetchone()
        if r is None:
            return False
        self.db.execute("update listings set status='cancelled' where id=?", (listing_id,))
        self.db.commit()
        self.add_items(c, {r["item"]: r["qty"]})
        return True

    # ---- mail -----------------------------------------------------------------------------------------
    def send_mail(self, to_char, from_name, subject, body, items=None, gold=0):
        self.db.execute("insert into mail(to_char,from_name,subject,body,items,gold,created) values(?,?,?,?,?,?,?)",
                        (to_char, from_name, subject[:60], body[:500], json.dumps(items or {}), int(gold), time.time()))
        self.db.commit()

    def inbox(self, cid, limit=40):
        rows = self.db.execute("select * from mail where to_char=? order by id desc limit ?", (cid, limit)).fetchall()
        out = []
        for r in rows:
            d = dict(r)
            d["items"] = json.loads(d["items"] or "{}")
            out.append(d)
        return out

    def claim_mail(self, c, mail_id):
        r = self.db.execute("select * from mail where id=? and to_char=?", (mail_id, c["char_id"])).fetchone()
        if r is None:
            return False
        if not r["claimed"]:
            items = json.loads(r["items"] or "{}")
            c["gold"] += int(r["gold"])
            for k, n in items.items():
                c["inv"][k] = c["inv"].get(k, 0) + int(n)
            self.save_char(c)
            self.db.execute("update mail set claimed=1, read=1 where id=?", (mail_id,))
            self.db.commit()
        return True

    def delete_mail(self, c, mail_id):
        self.db.execute("delete from mail where id=? and to_char=? and (claimed=1 or (items='{}' and gold=0))", (mail_id, c["char_id"]))
        self.db.commit()

    # ---- leaderboards ----------------------------------------------------------------------------------
    def post_score(self, board, c, value, extra=""):
        better = BOARDS.get(board)
        if better is None:
            return False
        r = self.db.execute("select value from scores where board=? and char_id=?", (board, c["char_id"])).fetchone()
        if r is not None and ((better == "low" and value >= r["value"]) or (better == "high" and value <= r["value"])):
            return False
        self.db.execute("insert or replace into scores(board,char_id,name,value,extra,updated) values(?,?,?,?,?,?)",
                        (board, c["char_id"], c["name"], float(value), extra, time.time()))
        self.db.commit()
        return True

    def add_score(self, board, c, delta):
        """cumulative boards (kills, boss_damage)"""
        r = self.db.execute("select value from scores where board=? and char_id=?", (board, c["char_id"])).fetchone()
        v = (r["value"] if r else 0) + delta
        self.db.execute("insert or replace into scores(board,char_id,name,value,updated) values(?,?,?,?,?)", (board, c["char_id"], c["name"], v, time.time()))
        self.db.commit()

    def top(self, board, n=10):
        better = BOARDS.get(board)
        if better is None:
            return []
        order = "asc" if better == "low" else "desc"
        return [dict(r) for r in self.db.execute("select name,value,extra from scores where board=? order by value %s limit ?" % order, (board, n)).fetchall()]

    # ---- seasons (the ladder: points from wins, a fresh board each season, titles when one closes) -------------------
    def add_season_points(self, season, c, pts):
        if pts <= 0:
            return
        r = self.db.execute("select points from season_points where season=? and char_id=?", (season, c["char_id"])).fetchone()
        v = (r["points"] if r else 0) + int(pts)
        self.db.execute("insert or replace into season_points(season,char_id,name,points,updated) values(?,?,?,?,?)",
                        (season, c["char_id"], c["name"], v, time.time()))
        self.db.commit()

    def season_top(self, season, n=10):
        return [dict(r) for r in self.db.execute("select name,points from season_points where season=? order by points desc, updated asc limit ?", (season, n)).fetchall()]

    def season_me(self, season, c):
        r = self.db.execute("select points from season_points where season=? and char_id=?", (season, c["char_id"])).fetchone()
        if r is None:
            return {"points": 0, "rank": 0}
        better = self.db.execute("select count(*) from season_points where season=? and (points>? or (points=? and updated<(select updated from season_points where season=? and char_id=?)))",
                                 (season, r["points"], r["points"], season, c["char_id"])).fetchone()[0]
        return {"points": r["points"], "rank": better + 1}

    def close_season(self, season, rewards_fn):
        """Close a finished season exactly once: archive the standings and give each ranked character the titles rewards_fn(rank, points) names.
        Safe to call again (a marker says it was done). Returns the number of characters rewarded."""
        key = "closed:%d" % season
        if self.db.execute("select 1 from meta where k=?", (key,)).fetchone():
            return 0
        rows = self.db.execute("select char_id,name,points from season_points where season=? order by points desc, updated asc", (season,)).fetchall()
        n = 0
        for i, r in enumerate(rows):
            rank = i + 1
            self.db.execute("insert into season_archive(season,rank,char_id,name,points) values(?,?,?,?,?)", (season, rank, r["char_id"], r["name"], r["points"]))
            got = rewards_fn(rank, r["points"])
            if got:
                c = self.char_by_id(r["char_id"])
                if c is not None:
                    for t in got:
                        if t not in c["titles"]:
                            c["titles"].append(t)
                    self.save_char(c)
                    n += 1
        self.db.execute("insert into meta(k,v) values(?,?)", (key, str(time.time())))
        self.db.commit()
        return n

    # ---- reports / grants -----------------------------------------------------------------------------
    def report(self, reporter, target, reason):
        self.db.execute("insert into reports(reporter,target,reason,created) values(?,?,?,?)", (reporter, target[:20], reason[:200], time.time()))
        self.db.commit()

    def make_grant(self, c, items):
        """items leaving for a solo save: taken from the server inventory now, kept as pending until the client acknowledges"""
        if not self.take_items(c, items):
            return None
        cur = self.db.execute("insert into grants(char_id,items,created) values(?,?,?)", (c["char_id"], json.dumps(items), time.time()))
        self.db.commit()
        return cur.lastrowid

    def pending_grants(self, cid):
        return [{"id": r["id"], "items": json.loads(r["items"])} for r in
                self.db.execute("select * from grants where char_id=? and acked=0 order by id", (cid,)).fetchall()]

    def ack_grant(self, cid, gid):
        self.db.execute("update grants set acked=1 where id=? and char_id=?", (gid, cid))
        self.db.commit()
