#!/usr/bin/env python3
"""Round 121: code-made sounds for the distance weapons (free, no samples).
   python3 ranged_sfx.py <out_dir>   -> bow_draw.ogg bow_release.ogg bolt_release.ogg ki_shot.ogg ki_charge.ogg
Pure python + ffmpeg (wav -> ogg)."""
import math, random, struct, subprocess, sys, os, wave

SR = 22050
random.seed(121)


def env_exp(t, k):
    return math.exp(-k * t)


def write_wav(path, samples):
    peak = max(1e-6, max(abs(s) for s in samples))
    g = 0.85 / peak
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * g)) * 32767)) for s in samples))


def lowpass(xs, a):
    out = []
    y = 0.0
    for x in xs:
        y += a * (x - y)
        out.append(y)
    return out


def bow_release():
    n = int(SR * 0.32)
    xs = []
    for i in range(n):
        t = i / SR
        # a string's twang: a fundamental with a fast decay, a thump, a breath of noise
        f = 150.0 + 90.0 * env_exp(t, 18.0)
        s = math.sin(2 * math.pi * f * t) * env_exp(t, 14.0)
        s += 0.5 * math.sin(2 * math.pi * f * 2.01 * t) * env_exp(t, 24.0)
        s += (random.random() * 2 - 1) * 0.35 * env_exp(t, 60.0)
        s += 0.4 * math.sin(2 * math.pi * 70.0 * t) * env_exp(t, 30.0)
        xs.append(s)
    return xs


def bolt_release():
    n = int(SR * 0.28)
    xs = []
    for i in range(n):
        t = i / SR
        click = (random.random() * 2 - 1) * env_exp(t, 140.0)
        thump = math.sin(2 * math.pi * (85.0 - 20.0 * t * 4) * t) * env_exp(t, 22.0)
        twang = 0.45 * math.sin(2 * math.pi * 210.0 * t) * env_exp(t, 20.0)
        xs.append(click * 0.9 + thump * 1.0 + twang)
    return xs


def bow_draw():
    n = int(SR * 0.55)
    raw = [(random.random() * 2 - 1) for _ in range(n)]
    xs = lowpass(raw, 0.09)
    out = []
    for i, x in enumerate(xs):
        t = i / SR
        a = min(1.0, t / 0.12) * (1.0 - max(0.0, (t - 0.45) / 0.1))
        creak = math.sin(2 * math.pi * (90.0 + 120.0 * t) * t) * 0.18
        out.append((x * 2.2 + creak) * a * 0.6)
    return out


def ki_shot():
    n = int(SR * 0.38)
    xs = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = 380.0 + 900.0 * (t / 0.38) ** 0.7
        ph += 2 * math.pi * f / SR
        s = math.sin(ph) * 0.7 + 0.3 * math.sin(ph * 2.5) * env_exp(t, 9.0)
        s += (random.random() * 2 - 1) * 0.12 * env_exp(t, 8.0)
        a = min(1.0, t / 0.02) * env_exp(t, 6.5)
        xs.append(s * a)
    return xs


def ki_charge():
    n = int(SR * 0.7)
    xs = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = 200.0 + 520.0 * (t / 0.7) ** 1.5
        ph += 2 * math.pi * f / SR
        a = min(1.0, t / 0.2) * (1.0 - max(0.0, (t - 0.55) / 0.15))
        xs.append((math.sin(ph) * 0.55 + math.sin(ph * 1.5) * 0.25 * math.sin(2 * math.pi * 11 * t)) * a * 0.5)
    return xs


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name, fn in [("bow_draw", bow_draw), ("bow_release", bow_release), ("bolt_release", bolt_release), ("ki_shot", ki_shot), ("ki_charge", ki_charge)]:
        wav = os.path.join("/tmp", name + ".wav")
        write_wav(wav, fn())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", os.path.join(out, name + ".ogg")], check=True)
        os.remove(wav)
        print("wrote", name)


main()
