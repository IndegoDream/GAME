"""Round 59: the game's music and ambience, second edition (our own -- no
licences). Robert: "I almost always turn off both the sound effects and music
because it gets boring." So, instead of five two-minute loops:

  music/      pieces, not loops: each has an intro, a theme (A) that comes
              back changed, a second part (B) and a real ending, built from a
              motif so it can be hummed. Several per place, in different keys,
              tempos and lead instruments. Audio.gd plays one, then lets the
              place breathe (silence -- the ambience carries it) before the next.
  combat/     short loops, mostly drums, that come in under a fight and go away
              after it.
  ambience/   seamless stereo beds for every kind of place: a cave's drips and
              room tone, a town's murmur and hearth, the valley's wind and
              stream, birds by day and crickets by night, lava's roar, the
              storm's thunder, the clockwork deep's hum ...
  sfx/        the few sounds the game called for and didn't have (dig), more
              takes of the ones heard most (hits, swings, steps), and new ones
              for later rounds (the wind-up before a heavy blow, rare loot,
              a floor cleared).

python3 tools/music_gen2.py <assets/audio dir> [only-name ...]
Instruments are synthesised: guzheng (additive pluck with bends), dizi flute,
erhu (bowed, sliding), xiao (low flute), string pad, FM bells, taiko and
small drums, woodblock, gong, and (deep down) a cold synth arpeggio.
"""
import numpy as np, subprocess, sys, os, wave
from scipy.signal import fftconvolve, butter, sosfilt, lfilter

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/audio"
ONLY = set(sys.argv[2:])
# r117 (music school): MUSIC_HARMONISE=1 puts the tune's strong-beat notes on notes that agree with the chord under them (the
# tunes are the same, only the clashing notes move); MUSIC_FOLDER names the output folder (default "music2", the original).
HARMONISE = os.environ.get("MUSIC_HARMONISE", "") == "1"
MUSIC_FOLDER = os.environ.get("MUSIC_FOLDER", "music2")

SCALES = {
    "gong": [0, 2, 4, 7, 9],        # major pentatonic
    "yu": [0, 3, 5, 7, 10],         # minor pentatonic
    "shang": [0, 2, 5, 7, 10],      # suspended, open
    "zhi": [0, 2, 5, 7, 9],
    "hira": [0, 2, 3, 7, 8],        # hirajoshi: dark
    "insen": [0, 1, 5, 7, 10],      # in-sen: very dark
}


def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def bp(lo, hi, order=2):
    return butter(order, [lo / (SR / 2), hi / (SR / 2)], btype="band", output="sos")


def lp(f, order=2):
    return butter(order, f / (SR / 2), btype="low", output="sos")


def hp(f, order=2):
    return butter(order, f / (SR / 2), btype="high", output="sos")


# ---------------------------------------------------------------- instruments

def env_adsr(n, a, d, s, r, sustain_secs=None):
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    out = np.ones(n) * s
    a_n = min(a_n, n)
    out[:a_n] = np.linspace(0, 1, a_n, endpoint=False)
    d_end = min(n, a_n + d_n)
    out[a_n:d_end] = np.linspace(1, s, d_end - a_n, endpoint=False)
    if r_n > 0 and n > r_n:
        out[-r_n:] *= np.linspace(1, 0, r_n)
    return out


def pluck(hz, secs, rng, bright=0.5, amp=0.5, bend=0.0, decay=2.6):
    """guzheng: harmonics that die faster the higher they are, a plucking
    position comb, slight inharmonicity, a pick click, sometimes a press-bend"""
    n = int(SR * secs)
    t = np.arange(n) / SR
    out = np.zeros(n)
    kmax = int(min(28, (SR / 2 * 0.9) / hz))
    pos = 0.13 + 0.1 * rng.random()
    f_mult = np.ones(n)
    if bend:
        f_mult = 1 + bend * (1 - np.exp(-t / 0.12)) * np.exp(-t / 1.4)
    phase_base = 2 * np.pi * hz * np.cumsum(f_mult) / SR
    for k in range(1, kmax + 1):
        a = abs(np.sin(np.pi * k * pos)) / k ** (1.25 - 0.55 * bright)
        dk = decay / (1 + 0.32 * (k - 1) * (1.25 - bright))
        inh = np.sqrt(1 + 0.00007 * k * k)
        out += a * np.exp(-t / dk) * np.sin(k * inh * phase_base + rng.random() * 6.28)
    att = int(0.003 * SR)
    out[:att] *= np.linspace(0, 1, att)
    click = sosfilt(bp(1800, 6000), rng.standard_normal(int(0.012 * SR))) * np.exp(-np.arange(int(0.012 * SR)) / (0.003 * SR))
    out[:len(click)] += click * 0.05 * (0.5 + bright)
    rel = int(0.04 * SR)
    out[-rel:] *= np.linspace(1, 0, rel)
    return out / max(1e-6, np.abs(out).max()) * amp


def flute(hz, secs, rng, amp=0.3, breath=0.05, low=False):
    """dizi (or, low, a xiao): soft attack, delayed vibrato, breath, a little membrane buzz"""
    n = int(SR * secs)
    t = np.arange(n) / SR
    vib_depth = 0.0045 * np.clip((t - 0.35) / 0.5, 0, 1)
    f = hz * (1 + vib_depth * np.sin(2 * np.pi * (5.0 + rng.random()) * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    w = np.sin(ph) + 0.28 * np.sin(2 * ph + 0.4) + (0.05 if low else 0.13) * np.sin(3 * ph) + (0.0 if low else 0.05) * np.sin(4 * ph)
    if not low:     # dizi membrane: a buzz that rides the louder parts
        w += 0.04 * np.sign(np.sin(ph)) * (0.6 + 0.4 * np.sin(2 * np.pi * 3 * t))
    noise = sosfilt(bp(max(200, hz * 1.5), min(SR / 2 - 100, hz * 4)), rng.standard_normal(n)) * breath * 3
    e = env_adsr(n, 0.12 if not low else 0.2, 0.2, 0.85, min(0.5, secs * 0.4))
    e *= 1 + 0.15 * np.sin(2 * np.pi * 0.7 * t)     # breathing
    return (w * 0.6 + noise) * e * amp


def erhu(hz, secs, rng, amp=0.3, from_hz=None):
    """bowed two-string fiddle: band-limited saw, nasal formants, vibrato, slides in"""
    n = int(SR * secs)
    t = np.arange(n) / SR
    f = np.full(n, float(hz))
    if from_hz:
        sl = min(n, int(0.09 * SR))
        f[:sl] = np.geomspace(from_hz, hz, sl)
    f *= 1 + 0.006 * np.clip((t - 0.25) / 0.4, 0, 1) * np.sin(2 * np.pi * 5.6 * t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    w = np.zeros(n)
    kmax = int(min(30, (SR / 2 * 0.9) / hz))
    for k in range(1, kmax + 1):
        fk = k * hz
        formant = np.exp(-((fk - 750) / 450) ** 2) * 1.6 + np.exp(-((fk - 1700) / 500) ** 2) * 0.9 + 0.25
        w += formant * np.sin(k * ph) / k
    bow = sosfilt(bp(1500, 6000), rng.standard_normal(n)) * 0.04
    e = env_adsr(n, 0.08, 0.1, 0.9, min(0.35, secs * 0.3))
    return (w * 0.5 + bow) * e * amp


def pad(midis, secs, rng, amp=0.2, dark=0.5):
    """strings/choir pad: detuned soft saws, slow swell"""
    n = int(SR * secs)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for m in midis:
        hz = midi_hz(m)
        for det in (-0.006, 0.0, 0.0055):
            ph = 2 * np.pi * hz * (1 + det) * t + rng.random() * 6.28
            kmax = int(min(10 - int(dark * 5), (SR / 2 * 0.8) / hz))
            for k in range(1, max(2, kmax) + 1):
                out += np.sin(k * ph) / (k ** 1.4)
    out *= env_adsr(n, min(1.6, secs * 0.35), 0.5, 0.9, min(2.0, secs * 0.4))
    out *= 1 + 0.08 * np.sin(2 * np.pi * 0.21 * t)
    return out / max(1e-6, np.abs(out).max()) * amp


def bell(hz, secs, rng, amp=0.3, ratio=3.5, index=2.4):
    n = int(SR * secs)
    t = np.arange(n) / SR
    idx = index * np.exp(-t / 0.8)
    out = np.sin(2 * np.pi * hz * t + idx * np.sin(2 * np.pi * hz * ratio * t))
    out += 0.3 * np.sin(2 * np.pi * hz * 2.76 * t) * np.exp(-t / 0.9)
    out *= np.exp(-t / (secs * 0.35))
    att = int(0.002 * SR)
    out[:att] *= np.linspace(0, 1, att)
    return out * amp


def synth_arp(hz, secs, rng, amp=0.15):
    """cold, techy (the deep's machines): pulse wave through a closing filter"""
    n = int(SR * secs)
    t = np.arange(n) / SR
    ph = (hz * t) % 1.0
    w = np.where(ph < 0.3, 1.0, -1.0)
    w = sosfilt(lp(min(SR / 2 - 100, hz * 6)), w)
    return w * np.exp(-t / 0.35) * amp


def taiko(secs, rng, amp=0.8, pitch=58.0):
    n = int(SR * secs)
    t = np.arange(n) / SR
    f = pitch * (1 + 1.2 * np.exp(-t / 0.04))
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.42)
    skin = sosfilt(bp(80, 900), rng.standard_normal(n)) * np.exp(-t / 0.05) * 0.6
    return (body + skin) * amp


def small_drum(secs, rng, amp=0.4):
    n = int(SR * secs)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * 190 * (1 + 0.5 * np.exp(-t / 0.02)) * t) * np.exp(-t / 0.12)
    snap = sosfilt(bp(1200, 5000), rng.standard_normal(n)) * np.exp(-t / 0.03) * 0.5
    return (body + snap) * amp


def woodblock(secs, rng, amp=0.3, hz=900):
    n = int(SR * secs)
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * hz * t) + 0.4 * np.sin(2 * np.pi * hz * 2.3 * t)) * np.exp(-t / 0.035) * amp


def gong(secs, rng, amp=0.5):
    n = int(SR * secs)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for r, a in [(1, 1), (1.47, .6), (2.09, .45), (2.56, .3), (3.4, .2), (4.1, .15)]:
        out += a * np.sin(2 * np.pi * 92 * r * t * (1 + 0.004 * np.sin(2 * np.pi * 0.7 * t)) + rng.random() * 6)
    swell = np.clip(t / 0.25, 0, 1) * np.exp(-t / (secs * 0.4))
    return out * swell * amp / 2.5


# ---------------------------------------------------------------- mixing

class Mix:
    def __init__(self, secs):
        self.n = int(SR * secs)
        self.L = np.zeros(self.n)
        self.R = np.zeros(self.n)

    def add(self, sig, at, pan=0.0, gain=1.0):
        i0 = int(at * SR)
        if i0 >= self.n or i0 < 0:
            return
        m = min(len(sig), self.n - i0)
        lg = np.cos((pan + 1) * np.pi / 4) * gain
        rg = np.sin((pan + 1) * np.pi / 4) * gain
        self.L[i0:i0 + m] += sig[:m] * lg
        self.R[i0:i0 + m] += sig[:m] * rg

    def add_wrap(self, sig, at, pan=0.0, gain=1.0):
        """for loops: what runs past the end comes in at the start"""
        i0 = int(at * SR) % self.n
        lg = np.cos((pan + 1) * np.pi / 4) * gain
        rg = np.sin((pan + 1) * np.pi / 4) * gain
        idx = (np.arange(len(sig)) + i0) % self.n
        np.add.at(self.L, idx, sig * lg)
        np.add.at(self.R, idx, sig * rg)


def reverb(mix, secs, wet, rng, loop=False, predelay=0.02):
    n = int(SR * secs)
    out = []
    for ch, seed_off in ((mix.L, 0), (mix.R, 1)):
        r2 = np.random.default_rng(int(rng.integers(1 << 30)) + seed_off)
        tt = np.arange(n) / SR
        ir = r2.standard_normal(n) * np.exp(-tt / (secs / 5.0))
        ir = sosfilt(lp(5000), ir)
        ir = np.concatenate([np.zeros(int(predelay * SR)), ir])
        ir /= np.sqrt((ir ** 2).sum())
        w = fftconvolve(ch, ir)
        if loop:
            tail = w[len(ch):]
            w = w[:len(ch)].copy()
            k = min(len(tail), len(w))
            w[:k] += tail[:k]
        else:
            w = w[:len(ch)]
        out.append(ch * (1 - wet) + w * wet * 1.8)
    mix.L, mix.R = out


def finish(mix, name, folder, target_rms=0.085, quality="1"):
    st = np.stack([mix.L, mix.R])
    st = sosfilt(hp(28), st, axis=1)
    if folder != "sfx":
        st = sosfilt(lp(9500, 2), st, axis=1)
    rms = np.sqrt((st ** 2).mean()) + 1e-9
    st *= target_rms / rms
    st = np.tanh(st * 1.15) / np.tanh(1.15)          # soft ceiling
    peak = np.abs(st).max()
    if peak > 0.94:
        st *= 0.94 / peak
    d = os.path.join(OUT, folder)
    os.makedirs(d, exist_ok=True)
    wav = os.path.join(d, name + ".wav")
    pcm = (st.T * 32767).astype(np.int16)
    with wave.open(wav, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", quality, os.path.join(d, name + ".ogg")], check=True)
    os.remove(wav)
    print("%-9s %-22s %6.1f s" % (folder, name, mix.n / SR), flush=True)


# ---------------------------------------------------------------- composing

RHYTHMS = [[1, 1, 2], [2, 1, 1], [1.5, 0.5, 2], [3, 1], [1, 1, 1, 1], [0.5, 0.5, 1, 2], [2, 2], [1, 0.5, 0.5, 2], [4]]


def degree_semis(scale, d):
    return SCALES[scale][d % 5] + 12 * (d // 5)


def make_motif(rng, bars=2, start=7, lo=3, hi=12, calm=False):
    notes = []
    d = start
    pool = RHYTHMS[:] if not calm else [[2, 2], [3, 1], [4], [1, 1, 2], [2, 1, 1]]
    for b in range(bars):
        pat = pool[rng.integers(len(pool))]
        for dur in pat:
            notes.append([d, dur])
            step = rng.choice([-2, -1, -1, 1, 1, 2, 0, -3, 3], p=[.1, .2, .17, .2, .15, .08, .04, .03, .03])
            d = int(np.clip(d + step, lo, hi))
    return notes


def answer(motif, rng, end_deg):
    a = [n[:] for n in motif]
    for i in range(len(a) // 2, len(a)):
        a[i][0] = int(a[i][0] + rng.choice([-1, 0, 1, -2]))
    a[-1][0] = end_deg
    if a[-1][1] < 2:
        a[-1][1] += 1
        a[-2][1] = max(0.5, a[-2][1] - 1) if len(a) > 1 else a[-2][1]
    return a


def vary(phrase, rng, ornament=0.3):
    out = []
    for d, dur in phrase:
        if dur >= 2 and rng.random() < ornament:
            out.append([d + int(rng.choice([1, -1])), 0.25])     # a grace note
            out.append([d, dur - 0.25])
        elif dur >= 1 and rng.random() < ornament * 0.5:
            out.append([d, dur / 2])
            out.append([d + int(rng.choice([1, -1, 2])), dur / 2])
        else:
            out.append([d, dur])
    return out


CHORD_OK = (0, 3, 4, 7, 8, 9)      # against a chord root: unison/octave, minor/major third, fifth, minor/major sixth
CHORD_CLASH = (1, 2, 6, 10, 11)    # minor/major second, tritone, minor/major seventh


def harmonise(phrase, scale, prog, key=0):
    """move the strong-beat notes (beats 1 and 3 of each bar) that clash with the chord on that bar to the nearest scale
    degree that agrees with it. Uses no randomness, keeps every duration, and leaves the phrase's last note (its cadence)
    alone. The chord for bar i is prog[i % len(prog)], counted from the start of the phrase, as the accompaniment does."""
    out = [n[:] for n in phrase]
    pos = 0.0
    for i, (d, dur) in enumerate(phrase):
        bar = int(pos // 4)
        beat = pos % 4
        root = prog[bar % len(prog)]
        if beat in (0.0, 2.0) and i < len(phrase) - 1 and (degree_semis(scale, d) - root) % 12 in CHORD_CLASH:
            best = None
            for shift in (1, -1, 2, -2, 3, -3):
                if (degree_semis(scale, d + shift) - root) % 12 in CHORD_OK:
                    best = shift
                    break
            if best is not None:
                out[i][0] = d + best
        pos += dur
    return out


def invert(motif, pivot):
    return [[pivot - (d - pivot), dur] for d, dur in motif]


def bars_of(phrase):
    return sum(n[1] for n in phrase) / 4.0


def play_line(mix, phrase, t0, beat, key, scale, voice, rng, pan=0.0, gain=1.0, octave=0, prev=None):
    t = t0
    last_hz = prev
    for d, dur in phrase:
        m = key + degree_semis(scale, d) + 12 * octave
        hz = midi_hz(m)
        secs = dur * beat
        if voice == "guzheng":
            bend = 0.06 if (dur >= 2 and rng.random() < 0.3) else 0.0
            s = pluck(hz, max(secs, 1.6) + 1.4, rng, bright=0.55, amp=0.5, bend=bend)
        elif voice == "dizi":
            s = flute(hz, secs * 0.97 + 0.15, rng, amp=0.42)
        elif voice == "xiao":
            s = flute(hz, secs * 0.97 + 0.2, rng, amp=0.5, low=True, breath=0.07)
        elif voice == "erhu":
            s = erhu(hz, secs * 0.98 + 0.12, rng, amp=0.38, from_hz=last_hz if (last_hz and rng.random() < 0.5) else None)
        elif voice == "bell":
            s = bell(hz, max(secs, 1.5) + 2.0, rng, amp=0.3)
        else:
            s = synth_arp(hz, secs + 0.3, rng)
        mix.add(s, max(0.0, t + rng.normal(0, 0.012)), pan=pan, gain=gain * rng.uniform(0.82, 1.0))
        last_hz = hz
        t += secs
    return t, last_hz


def accompany(mix, bar_t, beat, chord_root, key, rng, style, density):
    """the guzheng's broken fifths under the tune, a bar at a time"""
    base = key - 12 + chord_root
    tones = [0, 7, 12, 14, 19, 24] if style.get("bright", 0.5) > 0.45 else [0, 7, 12, 15, 19]
    for b in range(4):
        if rng.random() < density * 0.75 or (b == 0 and rng.random() < 0.9):
            m = base + tones[rng.integers(len(tones))]
            mix.add(pluck(midi_hz(m), 2.4, rng, bright=0.3, amp=rng.uniform(0.18, 0.27)), bar_t + b * beat + rng.normal(0, 0.01), pan=rng.uniform(-0.5, 0.5))
        if density > 0.8 and rng.random() < 0.3:
            m = base + tones[rng.integers(len(tones))]
            mix.add(pluck(midi_hz(m), 1.8, rng, bright=0.3, amp=0.16), bar_t + (b + 0.5) * beat, pan=rng.uniform(-0.6, 0.6))


def piece(name, folder, seed, style):
    rng = np.random.default_rng(seed)
    bpm = style["bpm"]
    beat = 60.0 / bpm
    bar = beat * 4
    key = style["key"]
    scale = style["scale"]
    prog = style["prog"]
    lead_a, lead_b = style["leads"]
    # the shape: intro, A, A', B, A'', ending
    motif = make_motif(rng, 2, start=int(rng.integers(5, 9)), calm=style.get("calm", False))
    phr1 = motif + answer(motif, rng, end_deg=8)                 # ends open (on the fifth)
    phr2 = motif + answer(motif, rng, end_deg=5)                 # ends home
    A = phr1 + phr2
    motif_b = invert(make_motif(rng, 2, start=int(rng.integers(6, 10)), calm=True), 8)
    B = motif_b + answer(motif_b, rng, end_deg=8) + vary(motif_b, rng) + answer(motif_b, rng, end_deg=7)
    if HARMONISE:
        A = harmonise(A, scale, prog, key)
        B = harmonise(B, scale, style.get("prog_b", prog[::-1]), key)
    intro_bars = style.get("intro", 3)
    total_bars = intro_bars + bars_of(A) * 2 + bars_of(B) + bars_of(A) + 2
    secs = total_bars * bar + 9.0
    mix = Mix(secs)

    def chords(t_start, n_bars, gain=1.0, prog_use=prog):
        for i in range(int(n_bars)):
            r = prog_use[i % len(prog_use)]
            mids = [key - 24 + r, key - 17 + r, key - 12 + r]
            if style.get("pad", True):
                mix.add(pad(mids, bar + 1.5, rng, amp=0.16 * gain, dark=style.get("dark", 0.5)), t_start + i * bar, pan=0.0)

    def drone_line(t_start, n_bars, gain=1.0):
        n = int((n_bars * bar + 3) * SR)
        tt = np.arange(n) / SR
        hz = midi_hz(key - 24)
        d = (np.sin(2 * np.pi * hz * tt) + 0.4 * np.sin(2 * np.pi * hz * 1.5 * tt) + 0.25 * np.sin(2 * np.pi * hz * 2 * tt))
        d *= env_adsr(n, 2.0, 0.5, 1.0, 2.5) * (0.8 + 0.2 * np.sin(2 * np.pi * tt / 17.0))
        mix.add(d * 0.06 * gain * style.get("drone", 1.0), t_start)

    t = 0.0
    # intro: the drone and the harmony alone, a few notes from the motif's opening
    drone_line(0, total_bars)
    chords(t, intro_bars, gain=0.8)
    for i in range(intro_bars):
        accompany(mix, t + i * bar, beat, prog[i % len(prog)], key, rng, style, style["acc"] * 0.5)
    t += intro_bars * bar
    # A
    sec_len = bars_of(A)
    chords(t, sec_len)
    for i in range(int(sec_len)):
        accompany(mix, t + i * bar, beat, prog[i % len(prog)], key, rng, style, style["acc"])
        if style.get("perc", 0) > 0 and i % 2 == 1:
            mix.add(taiko(1.2, rng, amp=0.25 * style["perc"]), t + i * bar, pan=-0.1)
    end, h = play_line(mix, A, t, beat, key, scale, lead_a, rng, pan=0.15, gain=1.0)
    t += sec_len * bar
    # A': the tune on the other voice, ornamented; the first an octave down underneath
    chords(t, sec_len, gain=1.1)
    for i in range(int(sec_len)):
        accompany(mix, t + i * bar, beat, prog[i % len(prog)], key, rng, style, min(1.0, style["acc"] + 0.2))
        if style.get("perc", 0) > 0 and i % 2 == 1:
            mix.add(taiko(1.2, rng, amp=0.3 * style["perc"]), t + i * bar)
    play_line(mix, vary(A, rng, 0.4), t, beat, key, scale, lead_b, rng, pan=-0.2, gain=0.95)
    if style.get("counter", True):
        play_line(mix, [[d - 5, dur] for d, dur in A[::2] for _ in [0]], t, beat * 2, key, scale, "guzheng", rng, pan=0.4, gain=0.35)
    t += sec_len * bar
    # B: somewhere else -- the other chords, quieter, the tune turned over
    b_len = bars_of(B)
    prog_b = style.get("prog_b", prog[::-1])
    chords(t, b_len, gain=0.85, prog_use=prog_b)
    for i in range(int(b_len)):
        accompany(mix, t + i * bar, beat, prog_b[i % len(prog_b)], key, rng, style, style["acc"] * 0.7)
    play_line(mix, B, t, beat, key, scale, style.get("lead_c", lead_b), rng, pan=0.0, gain=0.9)
    if style.get("bells", 0):
        for i in range(0, int(b_len), 2):
            mix.add(bell(midi_hz(key + 24 + prog_b[i % len(prog_b)]), 4.0, rng, amp=0.12 * style["bells"]), t + i * bar + beat * 2, pan=rng.uniform(-0.7, 0.7))
    t += b_len * bar
    # A'': home, the first voice again, the accompaniment fullest
    chords(t, sec_len, gain=1.0)
    for i in range(int(sec_len)):
        accompany(mix, t + i * bar, beat, prog[i % len(prog)], key, rng, style, min(1.0, style["acc"] + 0.1))
    play_line(mix, vary(A, rng, 0.2), t, beat, key, scale, lead_a, rng, pan=0.1)
    t += sec_len * bar
    # the ending: the home chord rings out
    mix.add(pad([key - 24, key - 17, key - 12, key - 5], 8.0, rng, amp=0.18, dark=style.get("dark", 0.5)), t)
    mix.add(pluck(midi_hz(key), 6.0, rng, bright=0.5, amp=0.45), t, pan=0.1)
    mix.add(pluck(midi_hz(key + 7), 6.0, rng, bright=0.5, amp=0.3), t + beat * 0.5, pan=-0.2)
    if style.get("gong_end"):
        mix.add(gong(7.0, rng, amp=0.35), t)
    reverb(mix, style.get("verb", 2.4), style.get("wet", 0.3), rng)
    # fade the very end, and in at the start
    fi = int(1.5 * SR)
    for ch in (mix.L, mix.R):
        ch[:fi] *= np.linspace(0, 1, fi)
        fo = int(5 * SR)
        ch[-fo:] *= np.linspace(1, 0, fo) ** 2
    finish(mix, name, folder, target_rms=style.get("rms", 0.06))


def combat(name, seed, key, bpm, boss=False, deep=False):
    """a fight's loop: drums first, a low ostinato, a drone; 16 bars, seamless"""
    rng = np.random.default_rng(seed)
    beat = 60.0 / bpm
    bar = beat * 4
    bars = 16
    mix = Mix(bars * bar)
    kick = [0, 1.5, 2, 3.5] if not boss else [0, 0.75, 1.5, 2, 2.5, 3, 3.5]
    for b in range(bars):
        t0 = b * bar
        for k in kick:
            if b % 4 == 3 and k > 2:
                continue
            mix.add_wrap(taiko(1.0, rng, amp=0.9 if k == 0 else 0.6, pitch=52 if boss else 60), t0 + k * beat, pan=rng.uniform(-0.15, 0.15))
        for e in range(8):
            if rng.random() < (0.7 if b % 4 != 3 else 0.95):
                mix.add_wrap(small_drum(0.4, rng, amp=0.22 + 0.1 * (e % 2 == 0)), t0 + e * beat / 2, pan=0.35)
        if b % 4 == 3:                     # a fill into the next phrase
            for e in range(8):
                mix.add_wrap(small_drum(0.3, rng, amp=0.3), t0 + 2 * beat + e * beat / 4, pan=-0.3)
        for e in range(4):
            mix.add_wrap(woodblock(0.2, rng, amp=0.12), t0 + (e + 0.5) * beat, pan=-0.5)
        # ostinato: root, fifth, octave, low -- erhu (or the cold synth, deep down)
        pat = [0, 0, 7, 0, 12, 7, 0, 10] if not boss else [0, 0, 1, 0, 7, 6, 0, 3]
        for e, iv in enumerate(pat):
            m = key - 12 + iv + (0 if b % 8 < 4 else (5 if not boss else 1))
            if deep:
                s = synth_arp(midi_hz(m + 12), beat / 2 + 0.2, rng, amp=0.2)
            else:
                s = erhu(midi_hz(m), beat / 2 * 0.9, rng, amp=0.22)
            mix.add_wrap(s, t0 + e * beat / 2, pan=0.2)
        if b % 4 == 0:
            mix.add_wrap(pad([key - 24, key - 17], bar * 4, rng, amp=0.14, dark=0.8), t0)
    if boss:
        mix.add_wrap(gong(6.0, rng, amp=0.5), 0)
        mix.add_wrap(gong(6.0, rng, amp=0.35), 8 * bar)
    reverb(mix, 1.4, 0.18, rng, loop=True)
    finish(mix, name, "combat", target_rms=0.11)


# ---------------------------------------------------------------- ambience

def seamless_noise(rng, secs, sos, extra=4.0):
    n = int(SR * secs)
    m = int(SR * min(extra, secs / 2.0))
    x = sosfilt(sos, rng.standard_normal(n + m))
    out = x[:n].copy()
    ramp = np.linspace(0, 1, m)
    out[:m] = x[n:n + m] * np.sqrt(1 - ramp) + x[:m] * np.sqrt(ramp)
    return out


def brown(rng, secs, cutoff=180):
    return seamless_noise(rng, secs, lp(cutoff, 2))


def lfo(secs, rate, depth, phase=0.0):
    t = np.arange(int(SR * secs)) / SR
    # a whole number of cycles over the loop, so it joins up
    cyc = max(1, round(rate * secs))
    return 1 + depth * np.sin(2 * np.pi * cyc / secs * t + phase)


def drip(rng, amp=0.3):
    n = int(SR * 0.35)
    t = np.arange(n) / SR
    f0 = rng.uniform(1300, 3200)
    f = f0 * (1 + 0.6 * np.exp(-t / 0.012))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.045) * amp


def chirp(rng, amp=0.2):
    """a small bird: a few quick up-and-down whistles"""
    notes = []
    for i in range(int(rng.integers(2, 6))):
        n = int(SR * rng.uniform(0.04, 0.12))
        t = np.arange(n) / SR
        f0 = rng.uniform(2800, 5200)
        f = f0 * (1 + rng.uniform(-0.25, 0.35) * t / t[-1])
        s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / t[-1]) ** 0.7
        notes.append(s)
        notes.append(np.zeros(int(SR * rng.uniform(0.02, 0.09))))
    return np.concatenate(notes) * amp


def cricket(rng, secs, amp=0.05):
    n = int(SR * secs)
    t = np.arange(n) / SR
    f = rng.uniform(4200, 5200)
    carrier = np.sin(2 * np.pi * f * t)
    pulse = (np.sin(2 * np.pi * 30 * t) > 0.2).astype(float)
    cyc = max(1, round(secs / rng.uniform(0.6, 1.1)))
    chirp_gate = (np.sin(2 * np.pi * cyc / secs * t + rng.random() * 6) > 0.55).astype(float)
    g = sosfilt(lp(60), pulse * chirp_gate)
    return carrier * g * amp


def crackle(rng, amp=0.3):
    n = int(SR * rng.uniform(0.004, 0.02))
    return rng.standard_normal(n) * np.exp(-np.arange(n) / (n / 4)) * amp


def babble(rng, secs, voices=6, amp=0.1):
    """a distant crowd: formant-filtered noise with a speech-like rhythm"""
    out = np.zeros(int(SR * secs))
    t = np.arange(len(out)) / SR
    for v in range(voices):
        f1 = rng.uniform(350, 800)
        src = seamless_noise(rng, secs, bp(f1, f1 * 2.4))
        cyc = max(1, round(secs * rng.uniform(3.0, 5.0)))
        syll = np.clip(np.sin(2 * np.pi * cyc / secs * t + rng.random() * 6), 0, 1) ** 2
        phrase = np.clip(np.sin(2 * np.pi * max(1, round(secs / rng.uniform(4, 9))) / secs * t + rng.random() * 6) + 0.3, 0, 1)
        out += src * syll * phrase
    return sosfilt(lp(1800), out) * amp


def thunder(rng, amp=0.6):
    n = int(SR * 7)
    t = np.arange(n) / SR
    x = sosfilt(lp(220, 2), rng.standard_normal(n))
    env = np.clip(t / 0.3, 0, 1) * np.exp(-t / 1.8) * (1 + 0.5 * np.sin(2 * np.pi * 1.3 * t) ** 2)
    crack = sosfilt(bp(600, 4000), rng.standard_normal(n)) * np.exp(-t / 0.15) * 0.3
    return (x * env * 3 + crack) * amp


def groan(rng, amp=0.15):
    """metal far off: a slow inharmonic moan"""
    n = int(SR * rng.uniform(2.5, 4.5))
    t = np.arange(n) / SR
    f = rng.uniform(70, 140) * (1 + 0.15 * np.sin(np.pi * t / t[-1]))
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.5 * np.sin(2 * np.pi * np.cumsum(f * 2.71) / SR)
    return s * np.sin(np.pi * t / t[-1]) ** 2 * amp


def scatter(mix, secs, rng, rate, maker, pan=(-0.9, 0.9), gain=1.0):
    t = 0.0
    while True:
        t += rng.exponential(1.0 / rate)
        if t >= secs:
            break
        mix.add_wrap(maker(), t, pan=rng.uniform(*pan), gain=gain)


def ambience(name, kind, secs=64, seed=0):
    rng = np.random.default_rng(seed + 500)
    mix = Mix(secs)

    def bed(sig, pan=0.0, gain=1.0, spread=0.0):
        if spread > 0:     # two takes, one each side, for width
            other = np.roll(sig, int(SR * 1.7))
            mix.L += sig * gain * (1 - spread * 0.3)
            mix.R += other * gain * (1 - spread * 0.3)
        else:
            mix.add_wrap(sig, 0, pan=pan, gain=gain)

    def wind(lo, hi, gain, rate=0.05, gust=0.5):
        w = seamless_noise(rng, secs, bp(lo, hi))
        bed(w * lfo(secs, rate, gust) * lfo(secs, rate * 3.1, 0.25, 1.0), gain=gain, spread=1.0)

    if kind in ("cave", "crypt", "deep", "water", "silk", "machine"):
        bed(brown(rng, secs, 140) * lfo(secs, 0.03, 0.3), gain=0.35, spread=1.0)
    if kind == "cave":
        wind(150, 600, 0.10)
        scatter(mix, secs, rng, 0.45, lambda: drip(rng, rng.uniform(0.08, 0.25)))
        scatter(mix, secs, rng, 0.04, lambda: groan(rng, 0.05), pan=(-0.4, 0.4))
    elif kind == "crypt":
        wind(220, 900, 0.16, rate=0.04, gust=0.7)
        scatter(mix, secs, rng, 0.15, lambda: drip(rng, rng.uniform(0.05, 0.14)))
        scatter(mix, secs, rng, 0.05, lambda: crackle(rng, 0.25), gain=0.6)       # something settling
    elif kind == "deep":
        bed(brown(rng, secs, 70) * lfo(secs, 0.02, 0.5), gain=0.5, spread=1.0)
        wind(100, 400, 0.1, rate=0.02)
        scatter(mix, secs, rng, 0.08, lambda: groan(rng, 0.12), pan=(-0.6, 0.6))
        scatter(mix, secs, rng, 0.2, lambda: drip(rng, 0.1))
    elif kind == "water":
        lap = seamless_noise(rng, secs, bp(200, 1400))
        bed(lap * np.clip(lfo(secs, 0.3, 0.8), 0, None) ** 1.5 * 0.5, gain=0.25, spread=1.0)
        scatter(mix, secs, rng, 1.4, lambda: drip(rng, rng.uniform(0.06, 0.2)))
    elif kind == "arcane":
        wind(800, 3000, 0.05, rate=0.03, gust=0.3)
        bed(brown(rng, secs, 120), gain=0.18, spread=1.0)
        scat = [64, 67, 69, 72, 74, 76, 79]
        scatter(mix, secs, rng, 0.35, lambda: bell(midi_hz(scat[rng.integers(len(scat))] + 12), 5.0, rng, amp=0.05, ratio=2.0, index=1.2))
    elif kind == "forest_under":
        wind(300, 1500, 0.08, rate=0.06)
        def bubble():
            n = int(SR * 0.08); t = np.arange(n) / SR
            return np.sin(2 * np.pi * np.cumsum(rng.uniform(300, 700) * (1 + 3 * t)) / SR) * np.exp(-t / 0.02) * 0.12
        scatter(mix, secs, rng, 0.9, bubble)
        bed(cricket(rng, secs, 0.012), gain=1.0, pan=0.4)
        scatter(mix, secs, rng, 0.12, lambda: drip(rng, 0.08))
    elif kind == "fire":
        bed(brown(rng, secs, 110) * lfo(secs, 0.07, 0.4), gain=0.7, spread=1.0)
        roar = seamless_noise(rng, secs, bp(80, 400))
        bed(roar * lfo(secs, 0.11, 0.5), gain=0.2, spread=1.0)
        scatter(mix, secs, rng, 9.0, lambda: crackle(rng, rng.uniform(0.05, 0.3)), gain=0.5)
        scatter(mix, secs, rng, 0.05, lambda: groan(rng, 0.06))
    elif kind == "storm":
        wind(200, 1200, 0.22, rate=0.07, gust=0.8)
        scatter(mix, secs, rng, 0.06, lambda: thunder(rng, rng.uniform(0.3, 0.6)), pan=(-0.6, 0.6))
        rain = seamless_noise(rng, secs, bp(1500, 7000))
        bed(rain, gain=0.03, spread=1.0)
    elif kind == "frost":
        w = seamless_noise(rng, secs, bp(500, 700, 3))
        bed(w * lfo(secs, 0.05, 0.7) * lfo(secs, 0.17, 0.3), gain=0.35, spread=1.0)
        wind(150, 900, 0.14, rate=0.04, gust=0.8)
        scatter(mix, secs, rng, 0.25, lambda: bell(rng.uniform(2000, 3600), 1.0, rng, amp=0.02, ratio=1.4, index=0.6))
    elif kind == "machine":
        t = np.arange(int(SR * secs)) / SR
        hum = (np.sin(2 * np.pi * 55 * t) + 0.5 * np.sin(2 * np.pi * 110 * t) + 0.2 * np.sin(2 * np.pi * 165 * t)) * lfo(secs, 0.05, 0.2)
        bed(hum, gain=0.03, spread=0.0)
        tick_rate = 1.0
        k = 0.0
        while k < secs:
            mix.add_wrap(woodblock(0.08, rng, amp=0.05, hz=2200 if int(k) % 2 else 1800), k, pan=0.3)
            k += tick_rate
        scatter(mix, secs, rng, 0.07, lambda: groan(rng, 0.1))
        scatter(mix, secs, rng, 0.2, lambda: synth_arp(rng.uniform(400, 900), 0.2, rng, amp=0.02))
    elif kind == "silk":
        rust = seamless_noise(rng, secs, bp(2000, 8000))
        bed(rust * np.clip(lfo(secs, 0.13, 1.0), 0, None) ** 3, gain=0.03, spread=1.0)
        wind(200, 700, 0.06, rate=0.03)
    elif kind == "town":
        bed(babble(rng, secs, voices=7, amp=0.35), gain=1.0, spread=1.0)
        bed(brown(rng, secs, 200), gain=0.12, spread=1.0)
        scatter(mix, secs, rng, 4.0, lambda: crackle(rng, rng.uniform(0.04, 0.18)), pan=(-0.3, 0.1), gain=0.4)   # a hearth
        def clank():
            return bell(rng.uniform(900, 1400), 0.8, rng, amp=0.06, ratio=1.41, index=3.0)
        scatter(mix, secs, rng, 0.25, clank, pan=(0.3, 0.8))                                               # a smith
    elif kind in ("village_day", "valley_day"):
        wind(300, 2500, 0.10 if kind == "village_day" else 0.16, rate=0.05, gust=0.6)
        scatter(mix, secs, rng, 0.5 if kind == "village_day" else 0.35, lambda: chirp(rng, rng.uniform(0.03, 0.08)))
        if kind == "valley_day":
            stream = seamless_noise(rng, secs, bp(600, 4000))
            bed(stream * lfo(secs, 0.5, 0.15), gain=0.05, spread=1.0)
        else:
            bed(babble(rng, secs, voices=3, amp=0.12), gain=1.0, spread=1.0)
    elif kind in ("village_night", "valley_night"):
        wind(200, 1200, 0.07, rate=0.03, gust=0.5)
        for i in range(4):
            bed(cricket(rng, secs, rng.uniform(0.01, 0.025)), gain=1.0, pan=rng.uniform(-0.8, 0.8))
        if kind == "valley_night":
            stream = seamless_noise(rng, secs, bp(600, 4000))
            bed(stream, gain=0.04, spread=1.0)
        def owl():
            n = int(SR * 0.5); t = np.arange(n) / SR
            return np.sin(2 * np.pi * 380 * (1 - 0.08 * t) * t) * np.sin(np.pi * t / t[-1]) ** 2 * 0.05
        scatter(mix, secs, rng, 0.03, owl)
    reverb(mix, 1.8 if kind in ("cave", "crypt", "deep", "water", "machine") else 0.9,
           0.35 if kind in ("cave", "crypt", "deep", "water") else 0.15, rng, loop=True)
    finish(mix, name, "ambience", target_rms=0.05, quality="0")


# ---------------------------------------------------------------- sfx

def sfx_out(name, sig):
    m = Mix(len(sig) / SR)
    m.add(sig, 0)
    d = os.path.join(OUT, "sfx")
    st = np.stack([m.L, m.R])
    peak = np.abs(st).max()
    st *= 0.8 / max(peak, 1e-6)
    wav = os.path.join(d, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((st.T * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "3", os.path.join(d, name + ".ogg")], check=True)
    os.remove(wav)
    print("sfx       %s" % name, flush=True)


def take(src, dst, rate, gain_db, lp_hz=None):
    """another take of a recorded sound: a touch faster or slower, brighter or duller"""
    d = os.path.join(OUT, "sfx")
    af = "asetrate=44100*%.3f,aresample=44100,volume=%.1fdB" % (rate, gain_db)
    if lp_hz:
        af += ",lowpass=f=%d" % lp_hz
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", os.path.join(d, src + ".ogg"), "-af", af, "-c:a", "libvorbis", "-q:a", "3", os.path.join(d, dst + ".ogg")], check=True)
    print("sfx take  %s <- %s" % (dst, src), flush=True)


def make_sfx():
    rng = np.random.default_rng(77)
    # dig: the game asked for it and it wasn't there
    for i in (1, 2, 3):
        n = int(SR * 0.45); t = np.arange(n) / SR
        thud = sosfilt(lp(500), rng.standard_normal(n)) * np.exp(-t / 0.07) * 2
        grit = sosfilt(bp(1500, 6000), rng.standard_normal(n)) * np.exp(-((t - 0.05) / 0.08) ** 2) * 0.5
        sfx_out("dig%d" % i, thud + grit)
    # the wind-up before a heavy blow (round 60): a rising, bright whoosh
    n = int(SR * 0.7); t = np.arange(n) / SR
    sweep = seamless_noise(rng, 0.7, bp(400, 3000)) * (t / t[-1]) ** 2
    tone = np.sin(2 * np.pi * np.cumsum(300 + 900 * (t / t[-1]) ** 2) / SR) * (t / t[-1]) ** 3 * 0.4
    sfx_out("windup", sweep + tone)
    # rare and wondrous loot (round 61)
    for nm, notes in (("loot_rare", [72, 76, 79]), ("loot_epic", [72, 76, 79, 84, 88])):
        sig = np.zeros(int(SR * 2.8))
        for i, m in enumerate(notes):
            b = bell(midi_hz(m), 2.2, rng, amp=0.4, ratio=2.0, index=1.5)
            i0 = int(i * 0.09 * SR)
            sig[i0:i0 + len(b)] += b[:len(sig) - i0]
        shimmer = sosfilt(bp(5000, 12000), rng.standard_normal(len(sig))) * np.exp(-np.arange(len(sig)) / (SR * 0.6)) * 0.05
        sfx_out(nm, sig + shimmer)
    # a floor cleared (round 61): low gong and a rising pluck figure
    sig = np.zeros(int(SR * 3.5))
    g = gong(3.5, rng, amp=0.5); sig[:len(g)] += g
    for i, m in enumerate([62, 66, 69, 74]):
        p = pluck(midi_hz(m), 2.0, rng, amp=0.4)
        i0 = int((0.15 + i * 0.12) * SR)
        sig[i0:i0 + len(p)] += p[:len(sig) - i0]
    sfx_out("floor_clear", sig)
    # more takes of what's heard most, so it doesn't repeat
    for base, n_have in (("hit_flesh", 2), ("hit_heavy", 2), ("hit_metal", 2), ("swing", 2), ("hurt", 2), ("mine", 2)):
        k = n_have + 1
        for (rate, g, lpf) in ((0.92, -1.0, None), (1.07, -0.5, None), (0.86, -2.0, 4000)):
            take("%s%d" % (base, 1 + (k % n_have)), "%s%d" % (base, k), rate, g, lpf)
            k += 1
    for base in ("step_grass", "step_stone"):
        for i, (rate, g) in enumerate(((0.94, -1.5), (1.05, -1.0))):
            take("%s%d" % (base, 1 + i), "%s%d" % (base, 5 + i), rate, g, 5000)


# ---------------------------------------------------------------- the set list

STYLES = {
    # the village: warm, major, flute and zither
    "village_1": dict(bpm=72, key=62, scale="gong", prog=[0, 9, 5, 7], leads=("dizi", "guzheng"), acc=0.65, verb=1.8, wet=0.25, bright=0.6, drone=0.6),
    "village_2": dict(bpm=66, key=65, scale="zhi", prog=[0, 5, 2, 7], leads=("guzheng", "dizi"), acc=0.55, verb=1.8, wet=0.28, bright=0.6, perc=0.4),
    "village_3": dict(bpm=78, key=60, scale="gong", prog=[0, 7, 9, 5], leads=("erhu", "dizi"), acc=0.7, verb=1.6, wet=0.25, bright=0.55),
    "village_night_1": dict(bpm=58, key=57, scale="yu", prog=[0, 8, 3, 10], leads=("xiao", "guzheng"), acc=0.35, verb=2.6, wet=0.35, bright=0.4, calm=True, dark=0.6),
    "village_night_2": dict(bpm=54, key=62, scale="shang", prog=[0, 5, 10, 7], leads=("guzheng", "xiao"), acc=0.3, verb=2.8, wet=0.38, bright=0.4, calm=True, bells=0.5, dark=0.6),
    # the valley: open, airy, wide
    "valley_1": dict(bpm=64, key=67, scale="shang", prog=[0, 5, 7, 5], leads=("dizi", "erhu"), acc=0.5, verb=3.0, wet=0.35, bright=0.6, calm=True),
    "valley_2": dict(bpm=70, key=64, scale="gong", prog=[0, 9, 4, 7], leads=("guzheng", "dizi"), acc=0.6, verb=2.6, wet=0.3, bright=0.6, bells=0.4),
    "valley_3": dict(bpm=60, key=69, scale="zhi", prog=[0, 2, 5, 7], leads=("xiao", "guzheng"), acc=0.45, verb=3.2, wet=0.38, bright=0.5, calm=True),
    # the dungeon, floors 1-9: minor, sparse, wary
    "dungeon_1": dict(bpm=62, key=50, scale="yu", prog=[0, 8, 3, 10], leads=("guzheng", "xiao"), acc=0.4, verb=2.8, wet=0.38, bright=0.35, dark=0.7, rms=0.05),
    "dungeon_2": dict(bpm=68, key=52, scale="hira", prog=[0, 8, 5, 7], leads=("erhu", "guzheng"), acc=0.45, verb=2.6, wet=0.36, bright=0.35, dark=0.7, perc=0.5, rms=0.05),
    "dungeon_3": dict(bpm=56, key=48, scale="yu", prog=[0, 3, 8, 7], leads=("xiao", "erhu"), acc=0.3, verb=3.0, wet=0.4, bright=0.3, dark=0.8, calm=True, bells=0.4, rms=0.05),
    # the deep, floors 10-29: darker, bells, the erhu alone
    "deep_1": dict(bpm=54, key=47, scale="hira", prog=[0, 1, 8, 7], leads=("erhu", "bell"), acc=0.3, verb=3.4, wet=0.42, bright=0.25, dark=0.85, bells=0.7, gong_end=True, rms=0.05),
    "deep_2": dict(bpm=60, key=45, scale="insen", prog=[0, 5, 1, 10], leads=("xiao", "guzheng"), acc=0.35, verb=3.2, wet=0.4, bright=0.25, dark=0.9, perc=0.4, rms=0.05),
    "deep_3": dict(bpm=50, key=49, scale="yu", prog=[0, 8, 10, 3], leads=("guzheng", "erhu"), acc=0.25, verb=3.6, wet=0.45, bright=0.3, dark=0.85, calm=True, bells=0.6, rms=0.05),
    # the abyss, floors 30-50: the machines the swarm left -- cold synth under old instruments
    "abyss_1": dict(bpm=64, key=44, scale="insen", prog=[0, 1, 7, 6], leads=("synth", "erhu"), lead_c="bell", acc=0.35, verb=3.0, wet=0.4, bright=0.2, dark=0.9, perc=0.5, rms=0.05),
    "abyss_2": dict(bpm=58, key=46, scale="hira", prog=[0, 8, 1, 7], leads=("erhu", "synth"), acc=0.3, verb=3.4, wet=0.42, bright=0.25, dark=0.9, bells=0.6, gong_end=True, rms=0.05),
    # a town in the deep: a little warmth underground
    "haven_1": dict(bpm=66, key=55, scale="zhi", prog=[0, 5, 7, 2], leads=("guzheng", "erhu"), acc=0.55, verb=2.2, wet=0.3, bright=0.45, dark=0.6, perc=0.3),
    "haven_2": dict(bpm=60, key=58, scale="yu", prog=[0, 3, 5, 10], leads=("dizi", "guzheng"), acc=0.5, verb=2.4, wet=0.32, bright=0.45, dark=0.6, calm=True),
    # the title
    "title_1": dict(bpm=60, key=57, scale="yu", prog=[0, 8, 3, 7], leads=("xiao", "erhu"), acc=0.45, verb=3.2, wet=0.38, bright=0.45, dark=0.6, bells=0.5, gong_end=True, intro=4),
}

if __name__ == "__main__":
    for i, (name, st) in enumerate(STYLES.items()):
        if ONLY and name not in ONLY:
            continue
        piece(name, MUSIC_FOLDER, 5900 + i * 13, st)
    for name, seed, key, bpm, boss, deep in (("combat_1", 1, 50, 118, False, False), ("combat_2", 2, 52, 126, False, False),
                                             ("combat_deep_1", 3, 47, 112, False, True), ("combat_deep_2", 4, 45, 120, False, True),
                                             ("boss_1", 5, 48, 104, True, False), ("boss_2", 6, 46, 112, True, True)):
        if ONLY and name not in ONLY:
            continue
        combat(name, 6100 + seed, key, bpm, boss, deep)
    for i, kind in enumerate(["cave", "crypt", "deep", "water", "arcane", "forest_under", "fire", "storm", "frost", "machine", "silk", "town",
                              "village_day", "village_night", "valley_day", "valley_night"]):
        if ONLY and kind not in ONLY:
            continue
        ambience(kind, kind, secs=64, seed=i)
    if not ONLY or "sfx" in ONLY:
        make_sfx()
