"""The fight simulation for online instances: dungeon runs, raids and world bosses.

Pure Python, no sockets: the server feeds it player input (`move`, `hit`, `leave`) and a clock (`tick`), and reads out
messages (`drain`) to send to the members. That makes it testable without a network.

What the SERVER decides (so a changed save or a hacked client can't change it):
  * every foe's health, position, targets, attacks and when they land (all damage to players is a telegraphed zone
    the server resolves against the positions it knows -- players dodge by moving, there is no client-side blocking)
  * the health players have, who is down, revives, wipes, and when an instance ends
  * the damage a hit may do: the client reports hits (it knows its own arts and weapon), the server clamps each hit and
    each second's total to what that character's rank could plausibly do
  * all rewards (gold, marks, materials, xp, titles) and the leaderboard entries
What it trusts the client for: where the player is (speed-limited and kept inside the arena)."""
import math, random
from collections import deque

TICK = 0.1
SUBS = 10
CASTER_WORDS = ("wraith", "mage", "shaman", "archer", "spirit", "sentinel", "drone", "witch", "priest", "caster", "oracle", "lantern")

# difficulty knobs (all in one place so they can be tuned without touching the logic)
CFG = {
    "hp_factor": {"run": 9.0, "raid": 9.0, "world": 8.0},   # player health = hp_factor x the tier's boss damage
    "ttk_weak": 7.0, "ttk_brute": 16.0, "ttk_boss_run": 200.0, "ttk_boss_raid": 420.0, "ttk_boss_world": 480.0,
    "efficiency": 0.55,          # how much of its "paper" damage a party really lands (dodging, deaths, travel)
    "member_hp_scale": 0.0,
    "enrage_after": {"run": 240.0, "raid": 480.0, "world": 600.0},
    "player_speed_cap": 15.0,    # metres per second the client may claim
    "hit_range": 24.0,           # furthest a reported hit may be from the player (arts reach far)
    "dps_window": 2.0, "dps_mult": 14.0, "hit_mult": 8.0,
    "revive_secs": 3.0, "revive_range": 3.0, "revive_hp": 0.4,
    "orb_chance": 0.14, "orb_heal": 0.2,
    "start_delay": 4.0, "intermission": 6.0,
    "arena": {"run": 16.0, "raid": 24.0, "world": 30.0},
}


def hit_base(realm, step, depth):
    """what an ordinary strike could deal for this rank at this tier (the solo game's formula, with a modest weapon)"""
    si = realm * 10 + (step - 1)
    return 9 + 2 * si + 6 * realm + 6 * depth


class Foe:
    def __init__(self, fid, etype, st, hp, x, z, boss=False, add=False, role="melee"):
        self.id = fid
        self.etype = etype
        self.name = st.get("name", etype)
        self.hp = float(hp)
        self.max_hp = float(hp)
        self.x, self.z = x, z
        self.speed = float(st.get("speed", 3.0)) * 0.9
        self.dmg = float(st.get("damage", 10))
        self.rng = float(st.get("range", 1.8))
        self.cool = float(st.get("cooldown", 1.4))
        self.scale = float(st.get("scale", 1.0))
        self.boss = boss
        self.add = add
        self.role = role
        self.cd = 1.0 + random.random()
        self.recover = 0.0
        self.target = None
        self.target_t = 0.0
        self.alive = True
        self.invuln = 0.0
        self.state = "idle"
        self.enrage = 1.0
        self.phase = 0
        self.bcd = 3.0
        self.loot = st.get("loot", {})

    def pub(self):
        return {"id": self.id, "type": self.etype, "name": self.name, "hp": round(self.hp), "max": round(self.max_hp),
                "x": round(self.x, 2), "z": round(self.z, 2), "boss": self.boss, "add": self.add, "scale": round(self.scale, 2)}


class Member:
    def __init__(self, char, x, z, max_hp):
        self.char = char
        self.id = char["char_id"]
        self.name = char["name"]
        self.x, self.z = x, z
        self.yaw = 0.0
        self.max_hp = float(max_hp)
        self.hp = float(max_hp)
        self.alive = True
        self.dealt = 0.0
        self.taken = 0.0
        self.kills = 0
        self.downs = 0
        self.revive_prog = 0.0
        self.last_move = None
        self.hits = deque()
        self.clamps = 0
        self.left = False
        self.joined_at = 0.0
        self.self_rev = 0
        self.down_t = 0.0

    def rank(self):
        return int(self.char["realm"]), int(self.char["step"])


class Hazard:
    _n = 0

    def __init__(self, kind, x, z, r, t, dmg, src="", zones=None, on_boom=None):
        Hazard._n += 1
        self.id = Hazard._n
        self.kind = kind            # "circle" | "safe" (damages everyone NOT inside a zone)
        self.x, self.z, self.r = x, z, r
        self.t = t
        self.total = t
        self.dmg = dmg
        self.src = src
        self.zones = zones or []
        self.on_boom = on_boom

    def pub(self):
        d = {"id": self.id, "kind": self.kind, "x": round(self.x, 2), "z": round(self.z, 2), "r": round(self.r, 2), "t": round(self.t, 2), "src": self.src}
        if self.zones:
            d["zones"] = [[round(a, 2), round(b, 2), round(c, 2)] for a, b, c in self.zones]
        return d


class Instance:
    """kind: "run" (party, rooms of waves, a boss), "raid" (party/raid, one boss with phases), "world" (open to everyone, one big boss)"""

    def __init__(self, iid, kind, tier, depth, chars, data, rng=None, cfg=None):
        self.id = iid
        self.kind = kind
        self.tier = tier
        self.depth = depth
        self.data = data                 # {"enemies": {...}, "items": {...}}
        self.rng = rng or random.Random()
        self.cfg = dict(CFG)
        if cfg:
            self.cfg.update(cfg)
        self.R = self.cfg["arena"][kind]
        self.t = 0.0
        self.phase = "countdown"         # countdown | active | breather | won | failed
        self.phase_t = self.cfg["start_delay"]
        self.out = []                    # [(recipient char_id or None for all, message)]
        self.members = {}
        self.foes = {}
        self.hazards = []
        self.orbs = {}
        self.next_id = 1
        self.rooms = 4 if kind == "run" else 1
        self.room = 0
        self.result = None
        self.result_t = 0.0
        self.boss_ref = None
        self.max_members = {"run": 4, "raid": 8, "world": 24}[kind]
        self.contrib = {}
        self.solo = len(chars) == 1
        self.pool, self.boss_type = self._pick_types()
        self.boss_dmg = float(self.data["enemies"][self.boss_type].get("damage", 60)) if self.boss_type else 60.0
        for c in chars:
            self.join(c, announce=False)
        self.tell({"t": "i_phase", "ph": "countdown", "secs": self.phase_t, "kind": kind, "tier": tier, "depth": depth, "radius": self.R,
                   "boss": self.data["enemies"][self.boss_type]["name"] if self.boss_type else ""})

    # ---- picking what to fight --------------------------------------------------------------------------
    def _pick_types(self):
        en = self.data["enemies"]
        floors = sorted({int(v["floor"]) for v in en.values() if "floor" in v and isinstance(v["floor"], int)})
        pool_f = None
        boss_f = None
        for f in reversed(floors):
            if f > self.depth:
                continue
            foes = [k for k, v in en.items() if v.get("floor") == f and not v.get("passive") and not v.get("boss") and v.get("damage", 0) > 0]
            bosses = [k for k, v in en.items() if v.get("floor") == f and v.get("boss") and not v.get("final")]
            if pool_f is None and foes:
                pool_f = sorted(foes)
            if boss_f is None and bosses:
                boss_f = sorted(bosses)[0]
            if pool_f and boss_f:
                break
        if pool_f is None:
            pool_f = sorted(k for k, v in en.items() if not v.get("passive") and not v.get("boss"))[:6]
        if boss_f is None:
            boss_f = sorted(k for k, v in en.items() if v.get("boss"))[0]
        return pool_f, boss_f

    # ---- members ------------------------------------------------------------------------------------------
    def player_hp(self):
        solo = 1.9 if (self.kind == "run" and self.solo) else 1.0      # a lone runner is tougher: nobody to cover them
        return self.cfg["hp_factor"][self.kind] * self.boss_dmg * solo

    def join(self, char, announce=True):
        if char["char_id"] in self.members or len(self.members) >= self.max_members:
            return None
        ang = self.rng.random() * math.tau
        x, z = math.cos(ang) * 3.0, math.sin(ang) * 3.0 + self.R * 0.55
        m = Member(char, x, z, self.player_hp())
        m.self_rev = 1 if self.kind == "run" else 0          # a second wind: a solo runner can get up once
        m.joined_at = self.t
        self.members[m.id] = m
        self.contrib.setdefault(m.id, 0.0)
        if announce:
            self.tell({"t": "i_join", "id": m.id, "name": m.name, "x": x, "z": z})
            self._rescale_for_join()
        return m

    def leave(self, cid):
        m = self.members.get(cid)
        if m and not m.left:
            m.left = True
            m.alive = False
            self.tell({"t": "i_left", "id": cid})
            if self.kind != "world" and all(x.left for x in self.members.values()) and self.phase not in ("won", "failed"):
                self._finish("failed")

    def active_members(self):
        return [m for m in self.members.values() if not m.left]

    def living(self):
        return [m for m in self.members.values() if m.alive and not m.left]

    # ---- the numbers a party is worth -----------------------------------------------------------------------------
    def party_dps(self):
        n = 0.0
        for m in self.active_members():
            r, s = m.rank()
            n += 2.2 * hit_base(r, s, self.depth) * (1.0 + 0.02 * (m.char.get("level", 1) - 1))
        return max(n, 20.0) * self.cfg["efficiency"]

    def _foe_hp(self, role):
        ttk = {"weak": self.cfg["ttk_weak"], "brute": self.cfg["ttk_brute"], "boss_run": self.cfg["ttk_boss_run"],
               "boss_raid": self.cfg["ttk_boss_raid"], "boss_world": self.cfg["ttk_boss_world"]}[role]
        return self.party_dps() * ttk

    def _rescale_for_join(self):
        """a world boss grows as people join (its health goes up, its fraction stays)"""
        if self.kind != "world" or self.boss_ref is None or not self.boss_ref.alive:
            return
        b = self.boss_ref
        frac = b.hp / b.max_hp
        b.max_hp = self._foe_hp("boss_world")
        b.hp = b.max_hp * frac
        self.tell({"t": "i_foe_hp", "id": b.id, "hp": round(b.hp), "max": round(b.max_hp)})

    # ---- spawning ------------------------------------------------------------------------------------------------
    def _spawn(self, etype, hp, boss=False, add=False, at=None):
        st = self.data["enemies"][etype]
        name = st.get("name", etype).lower()
        role = "caster" if any(w in name or w in etype for w in CASTER_WORDS) and not boss else "melee"
        if at is None:
            ang = self.rng.random() * math.tau
            rad = self.R * (0.35 + 0.5 * self.rng.random())
            at = (math.cos(ang) * rad, math.sin(ang) * rad - self.R * 0.35)
        f = Foe(self.next_id, etype, st, hp, at[0], at[1], boss, add, role)
        if boss:
            f.scale = max(f.scale, 1.8)
        self.next_id += 1
        self.foes[f.id] = f
        self.tell({"t": "i_spawn", "foe": f.pub()})
        return f

    def _spawn_wave(self, n, brutes=0):
        for i in range(n):
            et = self.rng.choice(self.pool)
            role = "brute" if (i < brutes or "brute" in et) else "weak"
            self._spawn(et, self._foe_hp(role) / max(n * 0.55, 1.0) * (1.4 if role == "brute" else 1.0))

    def _start_room(self):
        self.room += 1
        n = len(self.active_members())
        if self.kind == "run":
            if self.room < self.rooms:
                self._spawn_wave(2 + self.room + n, brutes=max(0, self.room - 1))
                self.tell({"t": "i_phase", "ph": "room", "room": self.room, "of": self.rooms, "text": "Room %d of %d" % (self.room, self.rooms)})
            else:
                b = self._spawn(self.boss_type, self._foe_hp("boss_run"), boss=True, at=(0.0, -self.R * 0.45))
                b.phase = 0
                self.boss_ref = b
                self.tell({"t": "i_phase", "ph": "boss", "room": self.room, "of": self.rooms, "text": b.name})
        else:
            kind = "boss_raid" if self.kind == "raid" else "boss_world"
            b = self._spawn(self.boss_type, self._foe_hp(kind), boss=True, at=(0.0, -self.R * 0.4))
            self.boss_ref = b
            self.tell({"t": "i_phase", "ph": "boss", "room": 1, "of": 1, "text": b.name})
        self.phase = "active"

    # ---- output ------------------------------------------------------------------------------------------------------
    def tell(self, msg, to=None):
        self.out.append((to, msg))

    def drain(self):
        o, self.out = self.out, []
        return o

    # ---- player input ------------------------------------------------------------------------------------------------------
    def move(self, cid, x, z, yaw=0.0):
        m = self.members.get(cid)
        if m is None or m.left:
            return
        if m.last_move is not None:
            dt = max(self.t - m.last_move, 0.02)
            maxd = self.cfg["player_speed_cap"] * dt + 0.5
            d = math.hypot(x - m.x, z - m.z)
            if d > maxd:
                k = maxd / d
                x = m.x + (x - m.x) * k
                z = m.z + (z - m.z) * k
        m.last_move = self.t
        r = math.hypot(x, z)
        if r > self.R:
            x, z = x * self.R / r, z * self.R / r
        if m.alive:
            m.x, m.z, m.yaw = x, z, yaw

    def hit(self, cid, foe_id, amt):
        """the client says: I hit this foe for about this much. The server decides what that is worth."""
        m = self.members.get(cid)
        f = self.foes.get(foe_id)
        if m is None or f is None or not m.alive or not f.alive or self.phase != "active" or m.left:
            return 0
        if math.hypot(f.x - m.x, f.z - m.z) > self.cfg["hit_range"]:
            return 0
        amt = float(amt)
        if not (amt > 0) or amt != amt:
            return 0
        r, s = m.rank()
        base = hit_base(r, s, self.depth) * (1.0 + 0.02 * (m.char.get("level", 1) - 1))
        cap = base * self.cfg["hit_mult"]
        if amt > cap:
            amt = cap
            m.clamps += 1
        # a rolling total: the last couple of seconds can't add up to more than a character could manage
        w = self.cfg["dps_window"]
        while m.hits and self.t - m.hits[0][0] > w:
            m.hits.popleft()
        spent = sum(a for _, a in m.hits)
        room = base * self.cfg["dps_mult"] * (w / 2.0) - spent
        if room <= 0:
            m.clamps += 1
            return 0
        if amt > room:
            amt = room
            m.clamps += 1
        if f.invuln > 0:
            return 0
        amt = min(amt, f.hp)
        m.hits.append((self.t, amt))
        f.hp -= amt
        m.dealt += amt
        self.contrib[m.id] = self.contrib.get(m.id, 0.0) + amt
        self.tell({"t": "i_dmg", "id": f.id, "amt": round(amt), "by": m.id, "hp": round(f.hp)})
        if f.hp <= 0:
            self._foe_dies(f, m)
        return amt

    def _foe_dies(self, f, killer):
        f.alive = False
        f.hp = 0
        killer.kills += 1
        self.tell({"t": "i_gone", "id": f.id, "why": "dead", "by": killer.id})
        if self.rng.random() < self.cfg["orb_chance"] and not f.boss:
            oid = self.next_id
            self.next_id += 1
            self.orbs[oid] = (f.x, f.z)
            self.tell({"t": "i_orb", "id": oid, "x": round(f.x, 2), "z": round(f.z, 2)})
        if f.boss:
            for o in self.foes.values():
                if o.add and o.alive:
                    o.alive = False
                    self.tell({"t": "i_gone", "id": o.id, "why": "boss_dead"})
            self.hazards = []
            self._finish("won")

    # ---- the clock ---------------------------------------------------------------------------------------------------------------
    def tick(self, dt=TICK):
        self.t += dt
        if self.phase in ("won", "failed"):
            return
        for m in self.members.values():
            if m.alive is False and not m.left:
                pass
        if self.phase == "countdown":
            if self.kind == "world" and not self.active_members():
                return                         # a world boss waits for its first challenger
            self.phase_t -= dt
            if self.phase_t <= 0:
                self._start_room()
        elif self.phase == "breather":
            self.phase_t -= dt
            if self.phase_t <= 0:
                self._start_room()
        elif self.phase == "active":
            self._active(dt)
        self._snapshot()

    def _active(self, dt):
        alive_foes = [f for f in self.foes.values() if f.alive]
        living = self.living()
        if not living:
            if self.kind == "world" and not self.active_members():
                return                         # nobody is here right now; the event window decides when it ends
            if len(self.members) == 1 and any(m.self_rev > 0 and not m.left for m in self.members.values()):
                self._revives(dt)              # a second wind is still coming
                return
            self._finish("failed")
            return
        for f in alive_foes:
            self._think(f, living, dt)
        self._hazards(dt)
        self._revives(dt)
        self._orbs(living)
        if self.kind == "run" and not self.boss_ref and not [f for f in self.foes.values() if f.alive]:
            self._room_cleared()
        # time limits
        limit = {"run": 900.0, "raid": 1500.0, "world": 900.0}[self.kind]
        if self.t > limit:
            self._finish("failed")

    def _room_cleared(self):
        for m in self.members.values():
            if m.left:
                continue
            if not m.alive:
                m.alive = True
                m.hp = m.max_hp * self.cfg["revive_hp"]
                self.tell({"t": "i_up", "id": m.id, "hp": round(m.hp)})
            else:
                m.hp = min(m.max_hp, m.hp + m.max_hp * 0.35)
        self.phase = "breather"
        self.phase_t = self.cfg["intermission"]
        self.tell({"t": "i_phase", "ph": "breather", "secs": self.phase_t, "text": "Room cleared"})

    # ---- foe behaviour -----------------------------------------------------------------------------------------------------------
    def _nearest(self, f, living):
        best, bd = None, 1e9
        for m in living:
            d = math.hypot(m.x - f.x, m.z - f.z)
            if d < bd:
                best, bd = m, d
        return best, bd

    def _think(self, f, living, dt):
        f.invuln = max(0.0, f.invuln - dt)
        if f.recover > 0:
            f.recover -= dt
            f.state = "wind"
            return
        f.cd -= dt
        tgt = next((m for m in living if m.id == f.target), None)
        f.target_t -= dt
        if tgt is None or f.target_t <= 0:
            tgt, _ = self._nearest(f, living)
            f.target = tgt.id if tgt else None
            f.target_t = 2.5
        if tgt is None:
            return
        d = math.hypot(tgt.x - f.x, tgt.z - f.z)
        if f.boss:
            self._boss_think(f, tgt, living, dt)
            if f.recover > 0:
                return
        if f.role == "caster":
            keep = 9.0
            if d < keep - 1.5:
                self._step(f, tgt, -1.0, dt)
            elif d > keep + 2.0:
                self._step(f, tgt, 1.0, dt)
            f.state = "chase"
            if f.cd <= 0 and d < 14.0:
                self._hazard("circle", tgt.x, tgt.z, 2.1, 1.1, f.dmg * 0.9, f.name)
                f.cd = 3.2 + self.rng.random()
                f.state = "wind"
            return
        reach = f.rng + 0.2
        if d > reach:
            self._step(f, tgt, 1.0, dt)
            f.state = "chase"
        elif f.cd <= 0:
            wind = 0.55 if "brute" not in f.etype and not f.boss else 0.9
            self._hazard("circle", f.x, f.z, f.rng + 0.9, wind, f.dmg * f.enrage, f.name)
            f.recover = wind + 0.25
            f.cd = f.cool
            f.state = "wind"
        else:
            f.state = "idle"
        self._separate(f)

    def _step(self, f, tgt, sign, dt):
        dx, dz = tgt.x - f.x, tgt.z - f.z
        d = math.hypot(dx, dz) or 1.0
        v = f.speed * dt * sign
        f.x += dx / d * v
        f.z += dz / d * v
        r = math.hypot(f.x, f.z)
        if r > self.R:
            f.x, f.z = f.x * self.R / r, f.z * self.R / r

    def _separate(self, f):
        for o in self.foes.values():
            if o is f or not o.alive:
                continue
            dx, dz = f.x - o.x, f.z - o.z
            d = math.hypot(dx, dz)
            if 0 < d < 1.1:
                k = (1.1 - d) * 0.5
                f.x += dx / d * k
                f.z += dz / d * k

    # ---- the boss's repertoire ------------------------------------------------------------------------------------------------------
    def _phase_marks(self):
        return [1.0, 0.5] if self.kind == "run" else [1.0, 0.7, 0.4, 0.15]

    def _boss_think(self, b, tgt, living, dt):
        marks = self._phase_marks()
        frac = b.hp / b.max_hp
        want = 0
        for i, m in enumerate(marks):
            if frac <= m + 1e-9 and (i > 0 or frac < 1.0):
                want = i
        if want > b.phase:
            b.phase = want
            b.invuln = 2.5
            b.recover = 2.0
            self.hazards = [h for h in self.hazards if h.src != b.name]
            self.tell({"t": "i_say", "id": b.id, "text": self._line(want), "phase": want})
            n = 2 + want
            for _ in range(n):
                et = self.rng.choice(self.pool)
                a = self._spawn(et, self._foe_hp("weak") / 4.0 * 0.6, add=True,
                                at=(b.x + self.rng.uniform(-4, 4), b.z + self.rng.uniform(-4, 4)))
            return
        limit = self.cfg["enrage_after"][self.kind]
        if self.t > limit:
            b.enrage = 1.0 + 0.25 * int((self.t - limit) / 20.0 + 1)
        b.bcd -= dt
        if b.bcd > 0:
            return
        abil = ["slam", "volley"]
        if b.phase >= 1:
            abil.append("charge")
        if self.kind != "run" and b.phase >= 2:
            abil.append("safe")
        if b.phase >= 1 and not any(f.alive and f.add for f in self.foes.values()) and self.rng.random() < 0.3:
            abil.append("adds")
        a = self.rng.choice(abil)
        gap = (3.4 - 0.35 * b.phase) * {1: 1.9, 2: 1.4, 3: 1.15}.get(len(living), 1.0)      # fewer challengers, a slower repertoire
        b.bcd = max(1.6, gap) + self.rng.random() * 0.8
        dmg = b.dmg * b.enrage
        names = [m for m in living]
        if a == "slam":
            self._hazard("circle", b.x, b.z, b.rng + 3.4, 1.0, dmg * 1.2, b.name)
            b.recover = 1.2
            self.tell({"t": "i_say", "id": b.id, "text": "", "ability": "slam"})
        elif a == "volley":
            k = min(len(names), 2 + b.phase)
            for m in self.rng.sample(names, k):
                self._hazard("circle", m.x, m.z, 2.4, 1.4, dmg, b.name)
            self.tell({"t": "i_say", "id": b.id, "text": "", "ability": "volley"})
        elif a == "charge":
            m = self.rng.choice(names)
            tx, tz = m.x, m.z

            def leap(inst=self, boss=b, x=tx, z=tz):
                boss.x, boss.z = x, z
            self._hazard("circle", tx, tz, 3.2, 1.1, dmg * 1.4, b.name, on_boom=leap)
            b.recover = 1.2
            self.tell({"t": "i_say", "id": b.id, "text": "", "ability": "charge"})
        elif a == "safe":
            zones = []
            for _ in range(3):
                for _try in range(20):
                    ang = self.rng.random() * math.tau
                    rad = self.R * 0.65 * math.sqrt(self.rng.random())
                    zx, zz = math.cos(ang) * rad, math.sin(ang) * rad
                    if all(math.hypot(zx - ox, zz - oz) > 7.0 for ox, oz, _ in zones):
                        zones.append((zx, zz, 4.2))
                        break
            self._hazard("safe", 0.0, 0.0, self.R, 3.4, dmg * 2.2, b.name, zones=zones)
            b.recover = 1.0
            self.tell({"t": "i_say", "id": b.id, "text": "", "ability": "safe"})
        elif a == "adds":
            for _ in range(2 + b.phase):
                self._spawn(self.rng.choice(self.pool), self._foe_hp("weak") / 4.0 * 0.6, add=True,
                            at=(b.x + self.rng.uniform(-5, 5), b.z + self.rng.uniform(-5, 5)))
            b.recover = 1.0
            self.tell({"t": "i_say", "id": b.id, "text": "", "ability": "adds"})

    def _line(self, phase):
        lines = ["", "It is only getting started.", "You are in its way.", "The floor itself is turning on you.", "Now it is angry."]
        return lines[min(phase, len(lines) - 1)]

    # ---- hazards, damage, revives, orbs -----------------------------------------------------------------------------------------------------
    def _hazard(self, kind, x, z, r, t, dmg, src, zones=None, on_boom=None):
        h = Hazard(kind, x, z, r, t, dmg, src, zones, on_boom)
        self.hazards.append(h)
        self.tell({"t": "i_hazard", "h": h.pub()})
        return h

    def _hazards(self, dt):
        keep = []
        for h in self.hazards:
            h.t -= dt
            if h.t > 0:
                keep.append(h)
                continue
            hit = []
            for m in self.living():
                if h.kind == "circle":
                    inside = math.hypot(m.x - h.x, m.z - h.z) <= h.r
                else:
                    inside = not any(math.hypot(m.x - zx, m.z - zz) <= zr for zx, zz, zr in h.zones)
                if inside:
                    self._hurt(m, h.dmg, h.src)
                    hit.append(m.id)
            if h.on_boom:
                h.on_boom()
            self.tell({"t": "i_boom", "id": h.id, "hit": hit})
        self.hazards = keep

    def _hurt(self, m, dmg, src):
        dmg = round(dmg)
        m.hp -= dmg
        m.taken += dmg
        self.tell({"t": "i_hurt", "id": m.id, "amt": dmg, "hp": max(0, round(m.hp)), "src": src})
        if m.hp <= 0 and m.alive:
            m.alive = False
            m.hp = 0
            m.downs += 1
            m.revive_prog = 0.0
            m.down_t = 0.0
            self.tell({"t": "i_down", "id": m.id})

    def _revives(self, dt):
        need = self.cfg["revive_secs"]
        rr = self.cfg["revive_range"]
        for m in self.members.values():
            if m.alive or m.left:
                continue
            helpers = [o for o in self.living() if math.hypot(o.x - m.x, o.z - m.z) <= rr]
            if helpers:
                m.revive_prog += dt
                if m.revive_prog >= need:
                    m.alive = True
                    m.hp = m.max_hp * self.cfg["revive_hp"]
                    m.revive_prog = 0.0
                    self.tell({"t": "i_up", "id": m.id, "hp": round(m.hp)})
            else:
                m.revive_prog = max(0.0, m.revive_prog - dt * 0.5)
                m.down_t += dt
                if m.self_rev > 0 and m.down_t >= 8.0:
                    m.self_rev -= 1
                    m.alive = True
                    m.hp = m.max_hp * 0.4
                    self.tell({"t": "i_up", "id": m.id, "hp": round(m.hp), "wind": True})

    def _orbs(self, living):
        for oid in list(self.orbs):
            x, z = self.orbs[oid]
            for m in living:
                if math.hypot(m.x - x, m.z - z) <= 1.6 and m.hp < m.max_hp:
                    m.hp = min(m.max_hp, m.hp + m.max_hp * self.cfg["orb_heal"])
                    del self.orbs[oid]
                    self.tell({"t": "i_orb_gone", "id": oid, "by": m.id, "hp": round(m.hp)})
                    break

    # ---- the end and what it's worth ---------------------------------------------------------------------------------------------------------------
    def _finish(self, result):
        if self.phase in ("won", "failed"):
            return
        self.phase = result
        self.result = result
        self.result_t = self.t
        self.hazards = []

    def snapshot_players(self):
        return [[m.id, round(m.x, 2), round(m.z, 2), round(m.yaw, 2), round(m.hp), 1 if m.alive else 0] for m in self.members.values() if not m.left]

    def _snapshot(self):
        foes = [[f.id, round(f.x, 2), round(f.z, 2), round(f.hp), f.state] for f in self.foes.values() if f.alive]
        self.tell({"t": "i_state", "n": int(self.t / TICK), "p": self.snapshot_players(), "f": foes})

    def summary(self):
        return [{"id": m.id, "name": m.name, "dealt": round(m.dealt), "taken": round(m.taken), "kills": m.kills, "downs": m.downs,
                 "share": round(self.contrib.get(m.id, 0.0) / max(sum(self.contrib.values()), 1.0), 3)} for m in self.members.values()]

    def rewards(self):
        """{char_id: {"gold", "marks", "xp", "items": {...}}} for a won instance (nothing for a failed one except a little xp)"""
        out = {}
        total = max(sum(self.contrib.values()), 1.0)
        mult = {"run": 1.0, "raid": 3.0, "world": 2.0}[self.kind]
        allowed = {k for k, v in self.data["items"].items() if v.get("type") == "material"}
        loot = {}
        for f in self.foes.values():
            for k, r in (f.loot or {}).items():
                if k in allowed:
                    loot[k] = r
        boss = self.data["enemies"][self.boss_type]
        for k, r in (boss.get("loot") or {}).items():
            if k in allowed:
                loot[k] = r
        for m in self.members.values():
            share = self.contrib.get(m.id, 0.0) / total
            if self.result != "won":
                out[m.id] = {"gold": 0, "marks": 0, "xp": int(10 * self.tier), "items": {}}
                continue
            if self.kind == "world" and share < 0.01:
                out[m.id] = {"gold": 0, "marks": 1, "xp": 0, "items": {}}
                continue
            gold = int(self.depth * 40 * mult * (0.6 + 0.4 * min(1.0, share * len(self.members)))) + self.rng.randint(0, self.depth * 10)
            marks = int(round((3 + self.tier * 2) * mult))
            items = {}
            for k, r in loot.items():
                lo, hi = (r if isinstance(r, list) and len(r) >= 2 else (int(r), int(r)))
                n = self.rng.randint(int(lo), int(hi))
                if self.kind == "world":
                    n = max(1, int(n * (0.5 + min(share * 4, 1.5))))
                if n > 0:
                    items[k] = n
            out[m.id] = {"gold": gold, "marks": marks, "xp": int(60 * self.tier * mult), "items": items}
        return out
