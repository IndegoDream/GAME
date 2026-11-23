"""
Round 184 (Robert: "keep working on making the details of the game better, more immersive"):
the small sounds of a world -- made here, like the music (tools/music_gen2.py, whose helpers this uses).

  python3 tools/world_sfx_gen.py assets/audio [only-group ...]

  steps      what your feet say on snow, water, sand, metal and wood (5 kinds x 4 takes)
  spots      one-off sounds placed somewhere around you by Audio.gd's spot director:
             birdsong, a dove, an owl, frogs, wind chimes, a far smithy and a woodcutter,
             a temple bell, stones settling, the deep's rumble, a gust, far thunder,
             fire pops, steam, gears, a crypt's hollow wind, bones, lapping water,
             bubbles, crystals humming, leaves, a passing fly, cicadas
  weather    four loops under the place's own bed: light rain, heavy rain, soft wind, hard wind

Groups: steps, spots, weather.  Seeds are fixed, so a re-run makes the same files.
"""
import os, sys, wave, subprocess
import numpy as np
from scipy.signal import sosfilt

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import music_gen2 as M          # noqa: E402  (SR, Mix, filters, finish, seamless_noise, bell, gong, thunder ...)

SR = M.SR
OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/audio"
ONLY = set(sys.argv[2:])
M.OUT = OUT


def t_of(n):
    return np.arange(n) / SR


def env(n, a, d):
    """a quick rise then an exponential fall (seconds)"""
    t = t_of(n)
    return np.clip(t / max(a, 1e-4), 0, 1) * np.exp(-np.maximum(t - a, 0) / max(d, 1e-4))


def tone(f, n, phase=0.0):
    """a sine whose pitch may move: f is a number or an array of Hz"""
    f = np.broadcast_to(np.asarray(f, dtype=float), (n,))
    return np.sin(2 * np.pi * np.cumsum(f) / SR + phase)


def noise(rng, n):
    return rng.standard_normal(n)


def place(dst, sig, at):
    i0 = int(at * SR)
    if i0 >= len(dst):
        return
    m = min(len(sig), len(dst) - i0)
    dst[i0:i0 + m] += sig[:m]


def far(sig, cutoff=3000, verb=0.0, rng=None):
    """heard from some way off: the top dulled, a little room behind it"""
    s = sosfilt(M.lp(cutoff, 2), sig)
    if verb > 0 and rng is not None:
        n = int(SR * 0.9)
        ir = rng.standard_normal(n) * np.exp(-t_of(n) / 0.22)
        ir = sosfilt(M.lp(2500), ir)
        ir /= np.sqrt((ir ** 2).sum())
        w = M.fftconvolve(s, ir)[:len(s) + n]
        dry = np.concatenate([s, np.zeros(len(w) - len(s))])
        s = dry * (1 - verb) + w * verb * 1.6
    return s


def out(name, sig, peak=0.8, fade=0.006):
    """mono -> a centred stereo .ogg in sfx/ (the 3D players place it)"""
    sig = np.asarray(sig, dtype=float)
    sig = sosfilt(M.hp(30), sig)
    k = int(SR * fade)
    if k > 0 and len(sig) > 2 * k:
        sig[:k] *= np.linspace(0, 1, k)
        sig[-k:] *= np.linspace(1, 0, k)
    pk = np.abs(sig).max()
    sig = sig * (peak / max(pk, 1e-6))
    d = os.path.join(OUT, "sfx")
    os.makedirs(d, exist_ok=True)
    wav = os.path.join(d, name + ".wav")
    pcm = (np.stack([sig, sig]).T * 32767).astype(np.int16)
    with wave.open(wav, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "3", os.path.join(d, name + ".ogg")], check=True)
    os.remove(wav)
    print("sfx       %-16s %5.2f s" % (name, len(sig) / SR), flush=True)


# ================================================================ steps

def step_snow(rng):
    n = int(SR * 0.26)
    s = np.zeros(n)
    # the crunch: many tiny breaks in packed snow, thickest a moment after the heel lands
    for _ in range(int(rng.integers(55, 85))):
        at = abs(rng.normal(0.07, 0.045))
        g = int(SR * rng.uniform(0.0015, 0.006))
        grain = noise(rng, g) * np.exp(-t_of(g) / (g / SR / 3)) * rng.uniform(0.3, 1.0)
        place(s, grain, at)
    s = sosfilt(M.bp(1400, 7500), s) * 0.9
    thump = sosfilt(M.lp(260), noise(rng, n)) * env(n, 0.006, 0.05) * 2.2
    return s + thump


def step_water(rng):
    n = int(SR * 0.32)
    t = t_of(n)
    splash = sosfilt(M.bp(450, 3800), noise(rng, n)) * env(n, 0.004, 0.07)
    slosh = sosfilt(M.bp(120, 600), noise(rng, n)) * env(n, 0.02, 0.12) * 1.4
    s = splash + slosh
    for _ in range(int(rng.integers(2, 5))):      # a few drops thrown up, falling back
        m = int(SR * rng.uniform(0.02, 0.05))
        f0 = rng.uniform(500, 1300)
        b = tone(f0 * (1 + 1.2 * t_of(m) / t_of(m)[-1]), m) * np.sin(np.pi * t_of(m) / t_of(m)[-1]) * rng.uniform(0.15, 0.35)
        place(s, b, rng.uniform(0.05, 0.2))
    return s


def step_sand(rng):
    n = int(SR * 0.22)
    hush = sosfilt(M.bp(1800, 9000), noise(rng, n)) * env(n, 0.012, 0.06)
    s = hush * 0.8
    for _ in range(int(rng.integers(10, 22))):    # grit shifting under the sole
        g = int(SR * rng.uniform(0.001, 0.003))
        place(s, noise(rng, g) * rng.uniform(0.2, 0.6), abs(rng.normal(0.05, 0.03)))
    thump = sosfilt(M.lp(220), noise(rng, n)) * env(n, 0.008, 0.04) * 1.6
    return s + thump


def step_metal(rng):
    n = int(SR * 0.3)
    t = t_of(n)
    base = rng.uniform(380, 520)
    ring = np.zeros(n)
    for r, a, d in ((1.0, 1.0, 0.09), (2.43, 0.6, 0.06), (4.1, 0.35, 0.04), (6.7, 0.2, 0.025)):
        ring += tone(base * r * rng.uniform(0.98, 1.02), n) * a * np.exp(-t / d)
    knock = sosfilt(M.bp(150, 1200), noise(rng, n)) * env(n, 0.002, 0.018) * 1.6
    return ring * 0.35 + knock


def step_wood(rng):
    n = int(SR * 0.24)
    t = t_of(n)
    body = tone(rng.uniform(105, 160) * (1 - 0.15 * t / t[-1]), n) * np.exp(-t / 0.05)
    knock = sosfilt(M.bp(300, 1600), noise(rng, n)) * env(n, 0.002, 0.022) * 1.4
    s = body * 0.9 + knock
    if rng.random() < 0.5:                         # an old board answers
        m = int(SR * 0.12)
        cr = sosfilt(M.bp(700, 1400), noise(rng, m) * (np.sin(2 * np.pi * 70 * t_of(m)) > 0.6)) * np.sin(np.pi * t_of(m) / t_of(m)[-1]) * 0.35
        place(s, cr, 0.06)
    return s


def make_steps():
    rng = np.random.default_rng(1840)
    for nm, fn, pk in (("step_snow", step_snow, 0.75), ("step_water", step_water, 0.8), ("step_sand", step_sand, 0.6),
                       ("step_metal", step_metal, 0.7), ("step_wood", step_wood, 0.8)):
        for i in range(1, 5):
            out("%s%d" % (nm, i), fn(rng), peak=pk)


# ================================================================ spots

def bird_song(rng):
    """a songbird: a phrase of warbles and trills, never the same twice"""
    parts = []
    for _ in range(int(rng.integers(3, 7))):
        kind = rng.random()
        if kind < 0.4:      # a warble
            m = int(SR * rng.uniform(0.08, 0.22))
            tt = t_of(m)
            f = rng.uniform(2600, 4600) * (1 + rng.uniform(-0.3, 0.3) * tt / tt[-1]) + rng.uniform(150, 500) * np.sin(2 * np.pi * rng.uniform(18, 38) * tt)
            s = tone(f, m) * np.sin(np.pi * tt / tt[-1]) ** 0.6
        elif kind < 0.7:    # a trill of quick notes
            k = int(rng.integers(4, 9))
            f0 = rng.uniform(3000, 5200)
            seg = []
            for j in range(k):
                m = int(SR * rng.uniform(0.022, 0.04))
                tt = t_of(m)
                seg.append(tone(f0 * (1 + 0.2 * tt / tt[-1]), m) * np.sin(np.pi * tt / tt[-1]))
                seg.append(np.zeros(int(SR * 0.012)))
            s = np.concatenate(seg)
        else:               # a clear whistle, falling
            m = int(SR * rng.uniform(0.15, 0.32))
            tt = t_of(m)
            s = tone(rng.uniform(2200, 3600) * (1 - 0.25 * tt / tt[-1]), m) * np.sin(np.pi * tt / tt[-1]) ** 0.8
        parts += [s, np.zeros(int(SR * rng.uniform(0.04, 0.18)))]
    sig = np.concatenate(parts)
    return far(sig, 7000, 0.15, rng)


def coo(rng):
    """a wood dove: hoo-HOOO, hoo, hoo"""
    sig = np.zeros(int(SR * 2.6))
    f0 = rng.uniform(430, 520)
    at = 0.05
    for dur, rise, g in ((0.22, 0.04, 0.6), (0.55, 0.1, 1.0), (0.25, -0.02, 0.7), (0.28, -0.03, 0.65)):
        m = int(SR * dur)
        tt = t_of(m)
        f = f0 * (1 + rise * np.sin(np.pi * tt / tt[-1])) * (1 + 0.006 * np.sin(2 * np.pi * 6 * tt))
        s = (tone(f, m) + 0.18 * tone(2 * f, m)) * np.sin(np.pi * tt / tt[-1]) ** 1.5 * g
        s += sosfilt(M.bp(300, 900), noise(rng, m)) * np.sin(np.pi * tt / tt[-1]) * 0.05
        place(sig, s, at)
        at += dur + rng.uniform(0.08, 0.18)
    return far(sig, 2400, 0.2, rng)


def owl(rng):
    """a tawny owl at night: a hoot, a pause, a long wavering hoooo"""
    sig = np.zeros(int(SR * 3.4))
    f0 = rng.uniform(340, 420)
    for at, dur, wav in ((0.05, 0.35, 0.0), (1.1, 0.12, 0.0), (1.35, 1.1, 1.0)):
        m = int(SR * dur)
        tt = t_of(m)
        f = f0 * (1 + 0.05 * np.sin(np.pi * tt / tt[-1])) * (1 + 0.03 * wav * np.sin(2 * np.pi * 9 * tt))
        s = tone(f, m) * np.sin(np.pi * tt / tt[-1]) ** 1.2
        s += sosfilt(M.bp(250, 800), noise(rng, m)) * np.sin(np.pi * tt / tt[-1]) * 0.08
        place(sig, s, at)
    return far(sig, 1800, 0.35, rng)


def frog(rng):
    sig = np.zeros(int(SR * 1.4))
    f = rng.uniform(260, 420)
    for k in range(int(rng.integers(2, 4))):
        m = int(SR * rng.uniform(0.18, 0.28))
        tt = t_of(m)
        pulses = (np.sin(2 * np.pi * rng.uniform(22, 32) * tt) > 0.3).astype(float)
        buzz = np.sign(np.sin(2 * np.pi * np.cumsum(np.full(m, f)) / SR))
        s = sosfilt(M.bp(f * 0.8, f * 4), buzz) * sosfilt(M.lp(120), pulses) * np.sin(np.pi * tt / tt[-1])
        place(sig, s, 0.05 + k * rng.uniform(0.32, 0.45))
    return far(sig, 2500, 0.15, rng)


def chime(rng):
    """wind chimes on a porch: a few bars struck by the breeze"""
    sig = np.zeros(int(SR * 4.0))
    scale = [0, 2, 4, 7, 9, 12, 14, 16]
    root = M.midi_hz(84 + int(rng.integers(-2, 3)))
    at = 0.02
    for _ in range(int(rng.integers(3, 7))):
        f = root * 2 ** (scale[int(rng.integers(len(scale)))] / 12)
        m = int(SR * 2.6)
        tt = t_of(m)
        s = (tone(f, m) * np.exp(-tt / 1.1) + 0.4 * tone(f * 2.76, m) * np.exp(-tt / 0.4) + 0.15 * tone(f * 5.4, m) * np.exp(-tt / 0.15))
        s *= np.clip(tt / 0.002, 0, 1) * rng.uniform(0.35, 1.0)
        place(sig, s, at)
        at += rng.uniform(0.12, 0.5)
    return far(sig, 6000, 0.2, rng)


def anvil(rng):
    """the smith at work, across the square: a few ringing blows"""
    sig = np.zeros(int(SR * 2.4))
    base = rng.uniform(820, 980)
    at = 0.03
    for k in range(int(rng.integers(2, 5))):
        m = int(SR * 0.7)
        tt = t_of(m)
        s = np.zeros(m)
        for r, a, d in ((1.0, 1.0, 0.25), (2.38, 0.6, 0.15), (3.9, 0.35, 0.09), (5.6, 0.2, 0.05)):
            s += tone(base * r, m) * a * np.exp(-tt / d)
        s += sosfilt(M.bp(1500, 6000), noise(rng, m)) * np.exp(-tt / 0.006) * 1.5
        place(sig, s * (0.6 if k % 2 else 1.0), at)
        at += rng.choice([0.42, 0.48, 0.55])
    return far(sig, 3200, 0.3, rng)


def woodchop(rng):
    sig = np.zeros(int(SR * 1.8))
    at = 0.03
    for k in range(int(rng.integers(1, 3))):
        m = int(SR * 0.4)
        tt = t_of(m)
        thock = tone(rng.uniform(140, 190) * (1 - 0.2 * tt / tt[-1]), m) * np.exp(-tt / 0.05)
        knock = sosfilt(M.bp(250, 1400), noise(rng, m)) * np.exp(-tt / 0.03) * 1.5
        s = thock + knock
        if rng.random() < 0.5:     # the split
            place(s, sosfilt(M.bp(1200, 5000), noise(rng, int(SR * 0.08))) * np.exp(-t_of(int(SR * 0.08)) / 0.02) * 0.6, 0.03)
        place(sig, s, at)
        at += rng.uniform(0.9, 1.2)
    return far(sig, 2600, 0.35, rng)


def temple_bell(rng):
    n = int(SR * 6.5)
    tt = t_of(n)
    f = rng.uniform(170, 210)
    s = np.zeros(n)
    for r, a, d in ((0.5, 0.5, 3.5), (1.0, 1.0, 2.6), (1.19, 0.5, 1.8), (2.0, 0.35, 1.2), (2.7, 0.2, 0.7)):
        s += tone(f * r * (1 + 0.0015 * np.sin(2 * np.pi * 0.9 * tt)), n) * a * np.exp(-tt / d)
    s *= np.clip(tt / 0.01, 0, 1)
    return far(s, 2000, 0.4, rng)


def pebbles(rng):
    """stones settling somewhere in the dark: a trickle, then the last one"""
    sig = np.zeros(int(SR * 1.6))
    at = 0.02
    k = int(rng.integers(5, 13))
    for i in range(k):
        g = int(SR * rng.uniform(0.006, 0.02))
        f = rng.uniform(1800, 5000)
        click = (tone(f, g) * 0.6 + noise(rng, g) * 0.5) * np.exp(-t_of(g) / (g / SR / 4))
        place(sig, click * rng.uniform(0.3, 1.0) * (1 - 0.5 * i / k), at)
        at += rng.exponential(0.07) + 0.015
    m = int(SR * 0.2)
    place(sig, sosfilt(M.bp(300, 2000), noise(rng, m)) * np.exp(-t_of(m) / 0.03) * 0.8, at + 0.08)
    return far(sig, 4500, 0.45, rng)


def rumble(rng):
    n = int(SR * rng.uniform(3.5, 5.0))
    tt = t_of(n)
    sub = sosfilt(M.lp(85, 2), noise(rng, n)) * 4.0
    grit = sosfilt(M.bp(150, 700), noise(rng, n)) * 0.25
    e = np.sin(np.pi * tt / tt[-1]) ** 1.5 * (1 + 0.4 * np.sin(2 * np.pi * 1.7 * tt) ** 2)
    return (sub + grit) * e


def wind_gust(rng):
    n = int(SR * rng.uniform(3.0, 4.5))
    tt = t_of(n)
    x = noise(rng, n)
    # a band that sweeps up as the gust comes and down as it goes (in blocks, close enough)
    s = np.zeros(n)
    blocks = 24
    for b in range(blocks):
        i0, i1 = b * n // blocks, (b + 1) * n // blocks
        c = 250 + 650 * np.sin(np.pi * (b + 0.5) / blocks) ** 1.5
        s[i0:i1] = sosfilt(M.bp(c * 0.6, c * 1.8), x[max(0, i0 - 2000):i1])[-(i1 - i0):]
    whistle = sosfilt(M.bp(1100, 1300, 3), x) * 0.35
    e = np.sin(np.pi * tt / tt[-1]) ** 2
    return (s + whistle * e) * e


def thunder_far(rng):
    s = M.thunder(rng, 1.0)
    return far(s, 900, 0.5, rng)


def fire_pop(rng):
    sig = np.zeros(int(SR * 0.9))
    for _ in range(int(rng.integers(5, 14))):
        place(sig, M.crackle(rng, rng.uniform(0.2, 0.7)), abs(rng.normal(0.25, 0.18)))
    m = int(SR * 0.05)
    place(sig, sosfilt(M.bp(200, 1500), noise(rng, m)) * np.exp(-t_of(m) / 0.008) * 1.6, rng.uniform(0.05, 0.5))
    return far(sig, 7000, 0.1, rng)


def steam_hiss(rng):
    n = int(SR * rng.uniform(1.3, 2.2))
    tt = t_of(n)
    s = sosfilt(M.hp(2800), noise(rng, n)) * np.clip(tt / 0.06, 0, 1) * np.exp(-np.maximum(tt - tt[-1] * 0.5, 0) / 0.35)
    return far(s, 9000, 0.25, rng)


def gear_clank(rng):
    sig = np.zeros(int(SR * 1.6))
    at = 0.02
    for k in range(int(rng.integers(3, 8))):           # a ratchet ...
        g = int(SR * 0.03)
        place(sig, sosfilt(M.bp(1500, 5000), noise(rng, g)) * np.exp(-t_of(g) / 0.004) * 0.6, at)
        at += 0.06 + rng.uniform(0, 0.02)
    m = int(SR * 0.8)                                  # ... and the clank as it catches
    tt = t_of(m)
    base = rng.uniform(300, 420)
    s = sum(tone(base * r, m) * a * np.exp(-tt / d) for r, a, d in ((1, 1, 0.25), (2.7, 0.5, 0.12), (4.4, 0.3, 0.07)))
    place(sig, s * 0.7 + sosfilt(M.lp(400), noise(rng, m)) * np.exp(-tt / 0.03) * 1.2, at + 0.05)
    return far(sig, 4000, 0.4, rng)


def moan(rng):
    """air through a crypt's passages: a hollow, wavering breath"""
    n = int(SR * rng.uniform(3.0, 4.2))
    tt = t_of(n)
    x = noise(rng, n)
    s = np.zeros(n)
    blocks = 30
    for b in range(blocks):
        i0, i1 = b * n // blocks, (b + 1) * n // blocks
        c = 180 + 120 * np.sin(np.pi * (b + 0.5) / blocks) + 25 * np.sin(b * 1.3)
        s[i0:i1] = sosfilt(M.bp(c * 0.92, c * 1.08, 3), x[max(0, i0 - 4000):i1])[-(i1 - i0):]
    e = np.sin(np.pi * tt / tt[-1]) ** 2
    return far(s * e * 3.0, 1500, 0.5, rng)


def bones(rng):
    sig = np.zeros(int(SR * 0.9))
    for _ in range(int(rng.integers(10, 22))):
        g = int(SR * rng.uniform(0.004, 0.012))
        f = rng.uniform(900, 2600)
        place(sig, (tone(f, g) + noise(rng, g) * 0.4) * np.exp(-t_of(g) / (g / SR / 5)) * rng.uniform(0.3, 1), abs(rng.normal(0.22, 0.13)))
    return far(sig, 5000, 0.35, rng)


def water_lap(rng):
    n = int(SR * 1.4)
    tt = t_of(n)
    s = np.zeros(n)
    for at in (0.0, rng.uniform(0.45, 0.65)):
        m = int(SR * 0.6)
        tm = t_of(m)
        place(s, sosfilt(M.bp(140, 900), noise(rng, m)) * np.sin(np.pi * tm / tm[-1]) ** 2, at)
    for _ in range(int(rng.integers(1, 4))):
        m = int(SR * 0.03)
        tm = t_of(m)
        place(s, tone(rng.uniform(400, 900) * (1 + 1.5 * tm / tm[-1]), m) * np.sin(np.pi * tm / tm[-1]) * 0.25, rng.uniform(0.1, 1.1))
    return far(s, 3000, 0.3, rng)


def bubble(rng):
    sig = np.zeros(int(SR * 0.8))
    at = 0.01
    for _ in range(int(rng.integers(3, 7))):
        m = int(SR * rng.uniform(0.02, 0.05))
        tm = t_of(m)
        place(sig, tone(rng.uniform(280, 700) * (1 + 1.4 * tm / tm[-1]), m) * np.sin(np.pi * tm / tm[-1]), at)
        at += rng.uniform(0.04, 0.12)
    return far(sig, 3500, 0.3, rng)


def crystal_hum(rng):
    n = int(SR * 3.4)
    tt = t_of(n)
    root = M.midi_hz(76 + int(rng.choice([0, 2, 5, 7])))
    s = np.zeros(n)
    for r, a in ((1.0, 1.0), (1.5, 0.5), (2.0, 0.35), (3.01, 0.15)):
        s += tone(root * r, n) * a + tone(root * r * 1.004, n) * a * 0.6      # beating
    e = np.clip(tt / 0.7, 0, 1) * np.exp(-np.maximum(tt - 1.2, 0) / 0.8)
    return far(s * e, 7000, 0.35, rng)


def leaf_rustle(rng):
    n = int(SR * rng.uniform(0.9, 1.6))
    tt = t_of(n)
    s = np.zeros(n)
    for _ in range(int(rng.integers(60, 120))):
        g = int(SR * rng.uniform(0.003, 0.012))
        place(s, noise(rng, g) * np.hanning(g) * rng.uniform(0.2, 1.0), rng.uniform(0, tt[-1]))
    s = sosfilt(M.bp(1800, 8000), s)
    return s * np.sin(np.pi * tt / tt[-1]) ** 0.8


def fly_by(rng):
    n = int(SR * 1.8)
    tt = t_of(n)
    f0 = rng.uniform(180, 230)
    f = f0 * (1.07 - 0.14 * tt / tt[-1]) * (1 + 0.02 * np.sin(2 * np.pi * 7 * tt))
    ph = 2 * np.pi * np.cumsum(f) / SR
    buzz = sum(np.sin(k * ph) / k for k in range(1, 9))
    e = np.exp(-((tt - 0.9) / 0.45) ** 2)
    return sosfilt(M.bp(200, 4000), buzz) * e


def cicada(rng):
    n = int(SR * rng.uniform(3.0, 4.5))
    tt = t_of(n)
    f = rng.uniform(4200, 6000)
    carrier = tone(f, n) + 0.5 * noise(rng, n) * 0.3
    am = 0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(110, 180) * tt)
    e = np.clip(tt / 0.8, 0, 1) * np.clip((tt[-1] - tt) / 1.0, 0, 1)
    return far(sosfilt(M.bp(3500, 8000), carrier * am) * e, 8000, 0.15, rng)


def drip_far(rng):
    sig = np.zeros(int(SR * 1.2))
    place(sig, M.far_drip(rng, 1.0), 0.01)
    if rng.random() < 0.5:                      # and its echo off the far wall
        place(sig, M.far_drip(rng, 0.35), rng.uniform(0.25, 0.5))
    return far(sig, 2600, 0.5, rng)


SPOTS = [
    ("drip_far", drip_far, 4, 0.6),
    ("bird_song", bird_song, 4, 0.7), ("coo", coo, 2, 0.7), ("owl", owl, 2, 0.75), ("frog", frog, 2, 0.6),
    ("chime", chime, 3, 0.6), ("anvil", anvil, 2, 0.7), ("woodchop", woodchop, 2, 0.75), ("temple_bell", temple_bell, 1, 0.7),
    ("pebbles", pebbles, 3, 0.65), ("rumble", rumble, 2, 0.8), ("wind_gust", wind_gust, 3, 0.7), ("thunder_far", thunder_far, 2, 0.85),
    ("fire_pop", fire_pop, 3, 0.6), ("steam_hiss", steam_hiss, 2, 0.5), ("gear_clank", gear_clank, 3, 0.65), ("moan", moan, 2, 0.6),
    ("bones", bones, 2, 0.6), ("water_lap", water_lap, 3, 0.65), ("bubble", bubble, 2, 0.55), ("crystal_hum", crystal_hum, 2, 0.5),
    ("leaf_rustle", leaf_rustle, 3, 0.55), ("fly_by", fly_by, 1, 0.5), ("cicada", cicada, 2, 0.45),
]


def make_spots():
    rng = np.random.default_rng(1841)
    rng_d = np.random.default_rng(1849)
    for nm, fn, k, pk in SPOTS:
        for i in range(1, k + 1):
            out(nm if k == 1 else "%s%d" % (nm, i), fn(rng_d if nm == "drip_far" else rng), peak=pk, fade=0.02)


# ================================================================ weather loops

def make_weather():
    secs = 64
    for name, seed in (("rain_light", 1), ("rain_heavy", 2), ("wind_soft", 3), ("wind_hard", 4)):
        if ONLY and name not in ONLY and "weather" not in ONLY:
            continue
        rng = np.random.default_rng(1842 + seed)
        mix = M.Mix(secs)
        n = mix.n
        tt = t_of(n)
        if name.startswith("rain"):
            heavy = name == "rain_heavy"
            hiss = M.seamless_noise(rng, secs, M.bp(500, 9000)) * (0.5 if heavy else 0.22)
            body = M.seamless_noise(rng, secs, M.bp(150, 900)) * (0.35 if heavy else 0.12)
            other = np.roll(hiss, int(SR * 2.3))
            mix.L += hiss + body
            mix.R += other + np.roll(body, int(SR * 1.1))
            rate = 70 if heavy else 28
            def drop():
                g = int(SR * rng.uniform(0.004, 0.02))
                f = rng.uniform(1200, 5000)
                return (tone(f * (1 + 0.5 * np.exp(-t_of(g) / 0.003)), g) * 0.5 + noise(rng, g) * 0.5) * np.exp(-t_of(g) / (g / SR / 3)) * rng.uniform(0.02, 0.09)
            M.scatter(mix, secs, rng, rate, drop)
            # drops off the eaves, slower and fatter
            M.scatter(mix, secs, rng, 1.2 if heavy else 0.6, lambda: M.far_drip(rng, rng.uniform(0.06, 0.14)))
            if heavy:
                gust = M.seamless_noise(rng, secs, M.bp(200, 800)) * M.lfo(secs, 0.07, 0.8) * 0.2
                mix.L += gust
                mix.R += np.roll(gust, int(SR * 3))
            M.finish(mix, name, "ambience", target_rms=0.05 if heavy else 0.03, quality="1")
        else:
            hard = name == "wind_hard"
            lo = M.seamless_noise(rng, secs, M.bp(90, 600)) * M.lfo(secs, 0.05, 0.7) * (0.6 if hard else 0.35)
            hi = M.seamless_noise(rng, secs, M.bp(700, 2600)) * M.lfo(secs, 0.09, 0.9, 1.3) * (0.25 if hard else 0.1)
            mix.L += lo + hi
            mix.R += np.roll(lo, int(SR * 2.7)) + np.roll(hi, int(SR * 1.9))
            if hard:
                wh = M.seamless_noise(rng, secs, M.bp(1150, 1300, 3)) * np.clip(M.lfo(secs, 0.03, 1.0) - 1.2, 0, 1) * 0.6
                mix.L += wh
                mix.R += np.roll(wh, int(SR * 5))
            M.finish(mix, name, "ambience", target_rms=0.045 if hard else 0.025, quality="1")


if __name__ == "__main__":
    if not ONLY or "steps" in ONLY:
        make_steps()
    if not ONLY or "spots" in ONLY:
        make_spots()
    make_weather()
