"""Ambient music loops for Dungeon Crawl Eliet (round 31): pentatonic plucks
(Karplus-Strong, like a guzheng) and breathy flute tones over a slow drone,
rendered to seamless OGG loops. Our own: no license to worry about."""
import numpy as np, subprocess, sys, os

SR = 44100
OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)

PENTA = [0, 2, 4, 7, 9]           # major pentatonic (gong mode)
MINOR = [0, 3, 5, 7, 10]          # minor pentatonic (yu mode)


def note_hz(root, semis):
    return root * 2 ** (semis / 12.0)


def pluck(hz, secs, bright=0.5, amp=0.5, rng=None):
    n = int(SR * secs)
    N = max(2, int(SR / hz))
    buf = (rng.random(N) * 2 - 1) * amp
    out = np.zeros(n)
    k = 0.5 - 0.5 * bright * 0.6
    for i in range(n):
        v = buf[i % N]
        nxt = buf[(i + 1) % N]
        buf[i % N] = (v * k + nxt * (1 - k)) * 0.996
        out[i] = v
    return out


def flute(hz, secs, amp=0.25, rng=None):
    t = np.arange(int(SR * secs)) / SR
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.minimum(t * 2, 1)
    w = np.sin(2 * np.pi * hz * vib * t) + 0.35 * np.sin(2 * np.pi * 2 * hz * t) + 0.12 * np.sin(2 * np.pi * 3 * hz * t)
    breath = rng.standard_normal(len(t)) * 0.015
    env = np.minimum(t / 0.35, 1) * np.minimum((secs - t) / 0.6, 1)
    env = np.clip(env, 0, 1) ** 1.5
    return (w * 0.3 + breath) * env * amp


def drone(hz, secs, amp=0.12, rng=None):
    t = np.arange(int(SR * secs)) / SR
    w = (np.sin(2 * np.pi * hz * t) + 0.5 * np.sin(2 * np.pi * hz * 1.5 * t + 0.3)
         + 0.3 * np.sin(2 * np.pi * hz * 2 * t) + 0.2 * np.sin(2 * np.pi * hz * 0.5 * t))
    slow = 0.75 + 0.25 * np.sin(2 * np.pi * t / 23.0)
    return w * slow * amp


def reverb(x, secs=1.6, mix=0.35, rng=None):
    n = int(SR * secs)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (SR * secs / 4.0))
    ir[0] = 1.0
    ir /= np.abs(ir).sum() ** 0.5
    wet = np.convolve(x, ir)[: len(x)]
    wet /= max(np.abs(wet).max(), 1e-6)
    return x * (1 - mix) + wet * mix * np.abs(x).max()


def render(name, secs, root, scale, drone_hz, density, flute_p, bright, dark, seed):
    rng = np.random.default_rng(seed)
    mix = drone(drone_hz, secs, amp=0.14 if dark else 0.1, rng=rng)
    if dark:
        mix += drone(drone_hz * 0.5, secs, amp=0.08, rng=rng)
    t = 0.0
    beat = 60.0 / 52
    last = None
    while t < secs - 4:
        step = beat * rng.choice([1, 1, 2, 2, 3, 4]) * (1.6 if dark else 1.0)
        if rng.random() < density:
            deg = rng.choice(scale) + 12 * rng.choice([0, 0, 1, 1, 2] if not dark else [-1, 0, 0, 1])
            if last is not None and rng.random() < 0.6:
                deg = last + rng.choice([-2, -1, 1, 2]) * 0
                deg = rng.choice(scale) + 12 * (last // 12)
            last = deg
            hz = note_hz(root, deg)
            if rng.random() < flute_p and not dark:
                s = flute(hz, min(rng.uniform(1.5, 4.0), secs - t), amp=0.22, rng=rng)
            else:
                s = pluck(hz, min(rng.uniform(2.0, 5.0), secs - t), bright=bright, amp=rng.uniform(0.25, 0.5), rng=rng)
            i0 = int(t * SR)
            mix[i0:i0 + len(s)] += s[: len(mix) - i0]
            if rng.random() < 0.35:        # a fifth or octave with it
                hz2 = note_hz(root, deg + rng.choice([7, 12, -12]))
                s2 = pluck(hz2, min(3.0, secs - t), bright=bright * 0.8, amp=0.2, rng=rng)
                i1 = i0 + int(SR * rng.uniform(0.0, 0.35))
                mix[i1:i1 + len(s2)] += s2[: len(mix) - i1]
        t += step
    mix = reverb(mix, secs=2.2 if dark else 1.4, mix=0.4 if dark else 0.3, rng=rng)
    # seamless loop: crossfade the last 4 s into the first 4 s
    xf = int(SR * 4)
    head = mix[:xf].copy()
    tail = mix[-xf:].copy()
    ramp = np.linspace(0, 1, xf)
    mix[:xf] = head * ramp + tail * (1 - ramp)
    mix = mix[:-xf]
    mix = mix / max(np.abs(mix).max(), 1e-6) * 0.7
    wav = os.path.join(OUT, name + ".wav")
    pcm = (mix * 32767).astype(np.int16)
    import wave
    with wave.open(wav, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "3", os.path.join(OUT, name + ".ogg")], check=True)
    os.remove(wav)
    print(name, len(mix) / SR)


render("village", 96, 220.0, PENTA, 110.0, 0.75, 0.3, 0.6, False, 1)
render("valley", 110, 196.0, PENTA, 98.0, 0.6, 0.45, 0.5, False, 2)
render("dungeon", 120, 146.8, MINOR, 55.0, 0.35, 0.0, 0.3, True, 3)
render("deep", 120, 123.5, MINOR, 41.2, 0.25, 0.0, 0.2, True, 4)
render("title", 90, 261.6, PENTA, 130.8, 0.5, 0.5, 0.55, False, 5)
