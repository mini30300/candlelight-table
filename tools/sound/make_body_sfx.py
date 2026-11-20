#!/usr/bin/env python3
"""Body sounds of the arena (0.14, item 1b): footsteps and panting, into godot/assets/body_sfx/.

The footsteps are CC0 recordings from OpenGameArt; the panting is synthesized here (two voices, soft and hard tiers,
inhale and exhale, three takes each). The script reads downloaded files, so run it with the system Python, isolated:

    /usr/bin/python3 -I tools/sound/make_body_sfx.py --fetch DIR     # DIR: a new, empty folder for the download
    /usr/bin/python3 -I tools/sound/make_body_sfx.py --rebuild DIR   # again from an earlier --fetch folder
    /usr/bin/python3 -I tools/sound/make_body_sfx.py --synth-steps   # no network: synthesize the footsteps too
    /usr/bin/python3 -I tools/sound/make_body_sfx.py --check [--src DIR]
    /usr/bin/python3 -I tools/sound/make_body_sfx.py --mix OUT.wav   # a 10 s listening mix, checked numerically

--fetch reads the pack's page and uses the pack only when CC0 is one of its licences, checks the zip against the sha256
pinned below, decodes the takes with ffmpeg and writes the WAVs, body_sfx.json and CREDITS.md. When the download fails,
the hash differs or the page does not offer CC0, it says why and synthesizes the footsteps instead.
--check rebuilds in memory and compares with the committed files (breaths and synthesized steps byte for byte,
downloaded steps by the sha256 recorded in the manifest, or rebuilt from the zip in --src DIR), and checks formats,
lengths, peaks, the clean ends of every take, the 1 MB cap and the credits. Exit code 1 on any problem.
Deterministic: seeded noise only, no clock in the audio. Not run in CI: the outputs are committed.
After a rebuild, import once: godot --headless --path godot --import
"""
import argparse
import datetime
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
import wave
import zipfile
import zlib

import numpy as np
from scipy import signal

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(REPO, "godot", "assets", "body_sfx")
MANIFEST = "body_sfx.json"
GEN = "tools/sound/make_body_sfx.py"
SR_STEP = 32000
SR_BREATH = 22050
CAP_BYTES = 1 << 20
PEAK_MAX = int(32767 * 10 ** (-1 / 20))          # -1 dBFS

PACK = {
    "title": "Footsteps Leather, Cloth, Armor",
    "author": "HaelDB",
    "page": "https://opengameart.org/content/footsteps-leather-cloth-armor",
    "url": "https://opengameart.org/sites/default/files/footsteps.zip",
    "sha256": "94b5155d119d9378315c2b4457c00098d78a36f2a2c436d5145687d1d3bad257",
    "licence": "CC0 1.0",
    "licence_url": "https://creativecommons.org/publicdomain/zero/1.0/",
}
# zip member -> kind (leather = boots, armor = metal plates)
TAKES = [("footsteps/step_lth1.ogg", "step_boot"), ("footsteps/step_lth2.ogg", "step_boot"),
         ("footsteps/step_lth33.ogg", "step_boot"), ("footsteps/step_lth4.ogg", "step_boot"),
         ("footsteps/step_metal.ogg", "step_metal"), ("footsteps/step_metal (2).ogg", "step_metal"),
         ("footsteps/step_metal (3).ogg", "step_metal"), ("footsteps/step_metal (4).ogg", "step_metal")]
SYNTH_STEPS = {"step_boot": 6, "step_metal": 4}
STEP_GAP, PANT_GAP = 90, 150
LENS = {("in", "soft"): (0.50, 0.55, 0.60), ("out", "soft"): (0.55, 0.62, 0.68),
        ("in", "hard"): (0.30, 0.34, 0.38), ("out", "hard"): (0.36, 0.40, 0.44)}
PEAK_DB = {"soft": -12.0, "hard": -6.0}
VOICES = ("low", "high")
# slots at the top breathing rate (56 /min, inhale 45 %): the hard takes must fit
SLOT_IN, SLOT_OUT = 0.45 * 60 / 56, 0.55 * 60 / 56
# spectral tilt of the breath noise (one-pole low-pass) and its top: tuned so the octave bands follow the CC0 reference
# recording "Breathing Tired" (opengameart.org/content/breathing-tired, mikeask; used for measuring only, not shipped)
TILT_HZ, TOP_HZ = 1600.0, 7000.0


def pant_kinds():
    return [("pant_%s_%s_%s" % (part, tier, voice), part, tier, voice)
            for voice in VOICES for tier in ("soft", "hard") for part in ("in", "out")]


def seed_of(name):
    return zlib.crc32(name.encode("utf-8")) & 0xFFFFFFFF


# ---------- filters (RBJ cookbook biquads as sos rows) ----------

def _row(b, a):
    return np.array([b[0] / a[0], b[1] / a[0], b[2] / a[0], 1.0, a[1] / a[0], a[2] / a[0]])


def peak_eq(f0, q, db, sr):
    a_ = 10 ** (db / 40)
    w = 2 * np.pi * f0 / sr
    al = np.sin(w) / (2 * q)
    return _row([1 + al * a_, -2 * np.cos(w), 1 - al * a_], [1 + al / a_, -2 * np.cos(w), 1 - al / a_])


def shelf(kind, f0, db, sr):
    a_ = 10 ** (db / 40)
    w = 2 * np.pi * f0 / sr
    c, al = np.cos(w), np.sin(w) / 2 * np.sqrt(2.0)
    s = 2 * np.sqrt(a_) * al
    if kind == "low":
        b = [a_ * ((a_ + 1) - (a_ - 1) * c + s), 2 * a_ * ((a_ - 1) - (a_ + 1) * c), a_ * ((a_ + 1) - (a_ - 1) * c - s)]
        a = [(a_ + 1) + (a_ - 1) * c + s, -2 * ((a_ - 1) + (a_ + 1) * c), (a_ + 1) + (a_ - 1) * c - s]
    else:
        b = [a_ * ((a_ + 1) + (a_ - 1) * c + s), -2 * a_ * ((a_ - 1) + (a_ + 1) * c), a_ * ((a_ + 1) + (a_ - 1) * c - s)]
        a = [(a_ + 1) - (a_ - 1) * c + s, 2 * ((a_ - 1) - (a_ + 1) * c), (a_ + 1) - (a_ - 1) * c - s]
    return _row(b, a)


def butter(kind, f, sr, order=2):
    return signal.butter(order, f, kind, fs=sr, output="sos")


def fades(x, sr, a_ms, b_ms):
    """Raised-cosine fades that start and end exactly at zero (no click at a seam)."""
    x = x.copy()
    na, nb = max(2, int(sr * a_ms / 1000)), max(2, int(sr * b_ms / 1000))
    x[:na] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(na) / (na - 1))
    x[-nb:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(nb) / (nb - 1))
    return x


def norm_peak(x, db):
    return x * (10 ** (db / 20) / max(1e-12, float(np.max(np.abs(x)))))


def wav_bytes(x, sr):
    q = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
    b = io.BytesIO()
    with wave.open(b, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(q.tobytes())
    return b.getvalue()


def read_wav(data):
    with wave.open(io.BytesIO(data), "rb") as w:
        fmt = (w.getnchannels(), w.getsampwidth(), w.getframerate())
        pcm = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2") if fmt[1] == 2 else np.zeros(0, "<i2")
    return fmt, pcm


# ---------- panting ----------

def glottal(n, f0, rng, sr):
    """Rosenberg pulse train, 2 % jitter from the seeded rng, pitch falling 8 % over the breath ("huh")."""
    out = np.zeros(n)
    pos = 0.0
    while pos < n:
        per = sr / (f0 * (1 - 0.08 * pos / n) * (1 + rng.uniform(-0.02, 0.02)))
        tp, tn = 0.40 * per, 0.16 * per
        m = np.arange(int(np.ceil(per)))
        p = np.where(m < tp, 0.5 - 0.5 * np.cos(np.pi * m / tp),
                     np.where(m < tp + tn, np.cos(np.pi * (m - tp) / (2 * tn)), 0.0))
        a = int(pos)
        b = min(n, a + len(p))
        out[a:b] += p[:b - a]
        pos += per
    return np.diff(out, prepend=0.0)                  # radiation at the lips


def breath(name, part, tier, voice, sec):
    sr = SR_BREATH
    rng = np.random.default_rng(seed_of(name + "/%.2f" % sec))
    n, pre = int(round(sec * sr)), int(0.1 * sr)
    fm = np.array([600.0, 1250.0, 2600.0]) * (1.0 if voice == "low" else 1.18) * (1 + rng.uniform(-0.04, 0.04, 3))
    if part == "in":
        fm[0] *= 1.10
    formants = [peak_eq(f, q, g, sr) for f, q, g in zip(fm, (4.0, 5.0, 6.0), (9.0, 7.0, 5.0))]
    colour = [shelf("high", 3000, 4.0, sr)] if part == "in" else [shelf("low", 400, 3.0, sr), shelf("high", 3000, -3.0, sr)]
    tilt = signal.butter(1, TILT_HZ, "lowpass", fs=sr, output="sos")
    sos = np.vstack([butter("highpass", 60, sr), butter("bandpass", (250, TOP_HZ), sr), tilt] + formants + colour)
    x = signal.sosfilt(sos, rng.standard_normal(n + pre))[pre:]
    if tier == "hard" and part == "out":               # weak voicing under the noise
        f0 = 115.0 if voice == "low" else 210.0
        g = signal.sosfilt(np.vstack([butter("highpass", 60, sr)] + formants), glottal(n + pre, f0, rng, sr))[pre:]
        x = x + g * (np.std(x) / max(1e-12, np.std(g))) * 10 ** (-14 / 20)
    flutter = signal.sosfilt(butter("lowpass", 14, sr), rng.standard_normal(n + pre))[pre:]
    x = x * (1 + 0.12 * np.clip(flutter / max(1e-12, np.std(flutter)), -2, 2))   # airflow wobble
    t = np.arange(n) / n
    if part == "in":
        rise = 0.25 if tier == "hard" else 0.45
        env = np.where(t < rise, 0.5 - 0.5 * np.cos(np.pi * t / rise), 1.0)
        env = np.where(t > 0.75, env * (0.5 + 0.5 * np.cos(np.pi * (t - 0.75) / 0.25)), env)
    else:
        env = np.where(t < 0.12, 0.5 - 0.5 * np.cos(np.pi * t / 0.12), np.exp(-(t - 0.12) / 0.35))
    return norm_peak(fades(x * env, sr, 5, 5), PEAK_DB[tier])


# ---------- footsteps ----------

def clean_step(x, sr):
    """Recorded take: DC and rumble out, leading silence (-45 dBFS) off, at most 0.35 s, fades, peak -3 dBFS."""
    x = signal.sosfilt(butter("highpass", 40, sr), x - np.mean(x))
    on = np.flatnonzero(np.abs(x) > 10 ** (-45 / 20))
    if on.size == 0:
        raise ValueError("silent take")
    x = x[max(0, on[0] - int(0.002 * sr)):][:int(0.35 * sr)]
    loud = np.flatnonzero(np.abs(x) > np.max(np.abs(x)) * 10 ** (-50 / 20))
    x = x[:min(len(x), loud[-1] + int(0.012 * sr))]
    return norm_peak(fades(x, sr, 1, 10), -3.0)


def synth_step(kind, take):
    """Fallback without recordings: heel thump, contact click, toe click (walk-like takes), gear rattle, metal ring."""
    sr = SR_STEP
    rng = np.random.default_rng(seed_of("%s/%d" % (kind, take)))
    n = int(0.30 * sr)
    t = np.arange(n) / sr
    metal = kind == "step_metal"
    fa, fb = (80.0, 40.0) if metal else (110.0, 55.0)
    k = 1 + rng.uniform(-0.06, 0.06)
    f = (fb + (fa - fb) * np.exp(-t / 0.02)) * k                  # sweep down over about 60 ms
    x = np.sin(2 * np.pi * np.cumsum(f) / sr) * np.exp(-t / 0.025)
    click = signal.sosfilt(butter("bandpass", (1500, 5000), sr), rng.standard_normal(n)) * np.exp(-t / 0.004)
    x += 0.5 * click / max(1e-12, np.max(np.abs(click)))
    if not metal and take % 2 == 1:                                  # walk-like: a softer toe click later
        d = int(rng.uniform(0.07, 0.11) * sr)
        x[d:] += 0.25 * click[:n - d] / max(1e-12, np.max(np.abs(click)))
    rattle = np.zeros(n)
    for _ in range(int(rng.integers(3, 7))):
        rattle[int(rng.uniform(0.01, 0.08) * sr)] += rng.uniform(0.5, 1.0) * rng.choice((-1.0, 1.0))
    rattle = signal.sosfilt(butter("bandpass", (3000, 7000), sr), rattle)
    x += 10 ** (-24 / 20) * rattle / max(1e-12, np.max(np.abs(rattle)))
    if metal:
        ring = sum(np.sin(2 * np.pi * fr * (1 + rng.uniform(-0.03, 0.03)) * t) * np.exp(-t / rng.uniform(0.06, 0.12))
                   for fr in (420.0, 1130.0, 2210.0))
        x += 10 ** (-10 / 20) * ring / max(1e-12, np.max(np.abs(ring)))
    loud = np.flatnonzero(np.abs(x) > np.max(np.abs(x)) * 10 ** (-50 / 20))
    x = x[:min(n, loud[-1] + int(0.012 * sr))]
    return norm_peak(fades(x, sr, 1, 10), -3.0)


# ---------- the download (untrusted data: kept in its own folder, paths passed as arguments) ----------

def http_get(url, limit):
    req = urllib.request.Request(url, headers={"User-Agent": "sound-asset-builder/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read(limit + 1)
    if len(data) > limit:
        raise ValueError("%s is larger than %d bytes" % (url, limit))
    return data


def page_licences(html):
    """Licence names in the page's licence field, and whether its CC0 link is there."""
    i = html.find("field-name-field-art-licenses")
    if i < 0:
        return [], False
    j = html.find("field-name-", i + 40)
    block = html[i:j if j > 0 else i + 5000]
    names = re.findall(r"class=['\"]license-name['\"]>([^<]+)<", block)
    return names, "creativecommons.org/publicdomain/zero/1.0" in block and "CC0" in names


def decode(path, sr):
    cmd = ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-i", path,
           "-ac", "1", "-ar", str(sr), "-f", "f32le", "-acodec", "pcm_f32le", "pipe:1"]
    out = subprocess.run(cmd, check=True, capture_output=True, timeout=60).stdout
    return np.frombuffer(out, dtype="<f4").astype(np.float64)


def pack_steps(zip_path):
    """Steps from the pack's zip (sha256 checked); members read by their known names only, never extracted by path."""
    data = open(zip_path, "rb").read()
    got = hashlib.sha256(data).hexdigest()
    if got != PACK["sha256"]:
        raise ValueError("zip sha256 %s, pinned %s" % (got, PACK["sha256"]))
    work = tempfile.mkdtemp(prefix="takes_", dir=os.path.dirname(os.path.abspath(zip_path)))
    out, origin = {}, {}
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for i, (member, kind) in enumerate(TAKES):
            if z.getinfo(member).file_size > 2_000_000:
                raise ValueError(member + " is too large")
            p = os.path.join(work, "take_%02d.ogg" % i)
            with open(p, "wb") as f:
                f.write(z.read(member))
            name = "%s_%d.wav" % (kind, sum(1 for m, k in TAKES[:i] if k == kind))
            out[name] = wav_bytes(clean_step(decode(p, SR_STEP), SR_STEP), SR_STEP)
            origin[name] = member
    return out, origin


def saved_licences(dirpath):
    """The licence check again, on the page saved by --fetch."""
    names, cc0 = page_licences(open(os.path.join(dirpath, "page.html"), encoding="utf-8").read())
    if not cc0:
        raise ValueError("the saved page's licences are %s, not CC0" % (names or "unreadable"))
    return os.path.join(dirpath, "footsteps.zip"), names


def fetch(dirpath):
    """Page licence check + zip download into dirpath (new or empty). Returns (zip path, licence names) or raises."""
    os.makedirs(dirpath, exist_ok=True)
    if os.listdir(dirpath):
        raise SystemExit("--fetch needs a new, empty folder: " + dirpath)
    html = http_get(PACK["page"], 2_000_000).decode("utf-8", "replace")
    with open(os.path.join(dirpath, "page.html"), "w", encoding="utf-8") as f:
        f.write(html)
    names, cc0 = page_licences(html)
    if not cc0:
        raise ValueError("the page's licences are %s, not CC0" % (names or "unreadable"))
    if PACK["author"] not in html:
        print("note: author %s not found on the page" % PACK["author"])
    zp = os.path.join(dirpath, "footsteps.zip")
    with open(zp, "wb") as f:
        f.write(http_get(PACK["url"], 5_000_000))
    return zp, names


# ---------- build, write, check ----------

def build_breaths():
    files, kinds = {}, {}
    for kind, part, tier, voice in pant_kinds():
        names, lens = [], []
        for take, sec in enumerate(LENS[(part, tier)]):
            fn = "%s_%d.wav" % (kind, take)
            files[fn] = wav_bytes(breath(kind, part, tier, voice, sec), SR_BREATH)
            names.append(fn)
            lens.append(round(int(round(sec * SR_BREATH)) / SR_BREATH, 3))
        kinds[kind] = {"gap": PANT_GAP, "v": 1.0, "h": None, "files": names, "len": lens}
    return files, kinds


def build_synth_steps():
    files = {}
    for kind, n in SYNTH_STEPS.items():
        for take in range(n):
            files["%s_%d.wav" % (kind, take)] = wav_bytes(synth_step(kind, take), SR_STEP)
    return files


def step_kinds(files):
    kinds = {}
    for kind in ("step_boot", "step_metal"):
        names = sorted((f for f in files if f.startswith(kind + "_")), key=lambda f: int(f[len(kind) + 1:-4]))
        lens = [round(len(read_wav(files[f])[1]) / SR_STEP, 3) for f in names]
        kinds[kind] = {"gap": STEP_GAP, "v": 1.0, "h": None, "files": names, "len": lens}
    return kinds


def write_all(steps, origin, licence_names, why_synth):
    breaths, kinds = build_breaths()
    kinds = dict(step_kinds(steps), **kinds)
    files = dict(steps, **breaths)
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):                     # stale takes of our own kinds (and their imports)
        base = f[:-7] if f.endswith(".import") else f
        if base.endswith(".wav") and (base.startswith("step_") or base.startswith("pant_")) and base not in files:
            os.remove(os.path.join(OUT, f))
    for f, b in files.items():
        with open(os.path.join(OUT, f), "wb") as h:
            h.write(b)
    src = {"steps": "pack" if origin else "synth", "breaths": "synth",
           "files": {f: {"from": origin.get(f, "synth"), "sha256": hashlib.sha256(steps[f]).hexdigest()} for f in sorted(steps)}}
    if origin:
        src["pack"] = dict(PACK, page_licences=licence_names, checked=datetime.date.today().isoformat())
    m = {"format": 1, "generated_by": GEN, "sample_rate": {"step": SR_STEP, "pant": SR_BREATH}, "kinds": kinds, "sources": src}
    with open(os.path.join(OUT, MANIFEST), "w", encoding="utf-8") as h:
        json.dump(m, h, indent=1, sort_keys=True)
        h.write("\n")
    with open(os.path.join(OUT, "CREDITS.md"), "w", encoding="utf-8") as h:
        h.write(credits(src, why_synth))
    total = sum(len(b) for b in files.values())
    print("wrote %d WAVs (%d bytes), %s, CREDITS.md into %s" % (len(files), total, MANIFEST, os.path.relpath(OUT, REPO)))
    print("now import them once: godot --headless --path godot --import")


def credits(src, why_synth):
    L = ["# Body sounds: sources and licences", "",
         "Footsteps and panting of the arena (0.14, item 1b). Made by `%s`; do not edit the WAVs by hand." % GEN, ""]
    if src["steps"] == "pack":
        p = src["pack"]
        L += ["## Footsteps (recorded): `step_boot_*`, `step_metal_*`", "",
              "- Pack: \"%s\" by %s, %s" % (p["title"], p["author"], p["page"]),
              "- File: %s (sha256 `%s`)" % (p["url"], p["sha256"]),
              "- Licence: **%s** (public domain dedication), %s. The page lists %s; we use the pack under CC0."
              % (p["licence"], p["licence_url"], ", ".join(p["page_licences"])),
              "- Licence checked on the page on %s. CC0 needs no credit; we keep it for the record." % p["checked"],
              "- Processing: ffmpeg to mono 32 kHz, 40 Hz high-pass, leading silence cut at -45 dBFS, at most 0.35 s,",
              "  1 ms / 10 ms fades, peak -3 dBFS.", "", "| File | Take in the pack | sha256 of the WAV |", "| --- | --- | --- |"]
        L += ["| `%s` | `%s` | `%s` |" % (f, d["from"], d["sha256"]) for f, d in src["files"].items()]
    else:
        L += ["## Footsteps (synthesized): `step_boot_*`, `step_metal_*`", "",
              "- Made by the script from seeded noise and sine sweeps (heel thump, contact click, gear rattle, metal ring).",
              "- Why not the CC0 recordings: %s" % (why_synth or "built with --synth-steps")]
    L += ["", "## Panting (synthesized): `pant_{in,out}_{soft,hard}_{low,high}_*`", "",
          "- Made by the script from seeded white noise shaped by vocal-tract formants (low voice F1 600 / F2 1250 /",
          "  F3 2600 Hz, high voice x1.18), soft and hard tiers, inhale and exhale, three takes each; the hard exhale adds",
          "  a weak voiced \"huh\" (Rosenberg glottal pulses). No recordings, no third-party material.",
          "- The spectral tilt was tuned so the octave bands follow the CC0 recording \"Breathing Tired\" by mikeask",
          "  (https://opengameart.org/content/breathing-tired), used for measuring only; nothing of it is shipped.", ""]
    return "\n".join(L)


def check(src_dir):
    probs = []
    try:
        m = json.load(open(os.path.join(OUT, MANIFEST), encoding="utf-8"))
    except (OSError, ValueError) as e:
        print("FAIL  manifest: %s" % e)
        return 1
    kinds, sources = m.get("kinds", {}), m.get("sources", {})
    want = {"step_boot", "step_metal"} | {k for k, _, _, _ in pant_kinds()}
    if set(kinds) != want:
        probs.append("kinds %s, want %s" % (sorted(kinds), sorted(want)))
    total, listed, rms = 0, set(), {"soft": [], "hard": []}
    for k, d in sorted(kinds.items()):
        step = k.startswith("step_")
        if d.get("h", 0) is not None or d.get("gap") != (STEP_GAP if step else PANT_GAP):
            probs.append("%s: h must be null, gap %d" % (k, STEP_GAP if step else PANT_GAP))
        n_ok = 4 <= len(d["files"]) <= 8 if step else len(d["files"]) == 3
        if not n_ok or len(d.get("len", [])) != len(d["files"]):
            probs.append("%s: %d files, %d lens" % (k, len(d["files"]), len(d.get("len", []))))
        for i, f in enumerate(d["files"]):
            listed.add(f)
            try:
                data = open(os.path.join(OUT, f), "rb").read()
            except OSError:
                probs.append("missing " + f)
                continue
            total += len(data)
            fmt, pcm = read_wav(data)
            sec = len(pcm) / max(1, fmt[2])
            lo, hi = (0.08, 0.35) if step else \
                (0.45, 0.70) if "_soft_" in k else (0.25, SLOT_IN if "_in_" in k else SLOT_OUT)
            if fmt != (1, 2, SR_STEP if step else SR_BREATH):
                probs.append("%s: %s, want mono 16-bit %d Hz" % (f, fmt, SR_STEP if step else SR_BREATH))
            elif not lo <= sec <= hi or abs(sec - float(d["len"][i])) > 0.001:
                probs.append("%s: %.3f s (range %.2f-%.2f, manifest %s)" % (f, sec, lo, hi, d["len"][i]))
            elif int(np.max(np.abs(pcm.astype(np.int32)))) > PEAK_MAX or abs(int(pcm[0])) > 1 or abs(int(pcm[-1])) > 1:
                probs.append("%s: peak over -1 dBFS or an end that is not silent (click at a seam)" % f)
            if not step:
                rms[k.split("_")[2]].append(20 * np.log10(np.sqrt(np.mean((pcm / 32767.0) ** 2))))
    stray = sorted(f for f in os.listdir(OUT) if f.endswith(".wav") and f not in listed)
    if stray:
        probs.append("WAVs not in the manifest: %s" % stray)
    if total > CAP_BYTES:
        probs.append("total %d bytes over %d" % (total, CAP_BYTES))
    soft, hard = (float(np.mean(rms[t])) if rms[t] else 0.0 for t in ("soft", "hard"))
    print("takes %d, %d bytes; breath RMS soft %.1f dBFS, hard %.1f dBFS" % (len(listed), total, soft, hard))
    if not (-30 <= soft <= -18 and -24 <= hard <= -12 and hard - soft >= 4):
        probs.append("breath RMS per tier out of range (soft -30..-18, hard -24..-12, hard >= soft + 4 dB)")
    rebuilt = build_breaths()[0]
    if sources.get("steps") == "synth":
        rebuilt.update(build_synth_steps())
    elif src_dir:
        try:
            rebuilt.update(pack_steps(os.path.join(src_dir, "footsteps.zip"))[0])
        except (OSError, ValueError, subprocess.SubprocessError, KeyError) as e:
            probs.append("cannot rebuild the steps from %s: %s" % (src_dir, e))
    for f, b in sorted(rebuilt.items()):
        try:
            old = open(os.path.join(OUT, f), "rb").read()
        except OSError:
            continue
        if old != b:
            a, c = read_wav(old)[1].astype(np.int32), read_wav(b)[1].astype(np.int32)
            if len(a) != len(c) or int(np.max(np.abs(a - c))) > 1:
                probs.append("%s differs from a rebuild" % f)
    if sources.get("steps") == "pack":
        for f, d in sources.get("files", {}).items():
            try:
                if hashlib.sha256(open(os.path.join(OUT, f), "rb").read()).hexdigest() != d.get("sha256"):
                    probs.append("%s: sha256 differs from the manifest" % f)
            except OSError:
                probs.append("missing " + f)
        cr = open(os.path.join(OUT, "CREDITS.md"), encoding="utf-8").read() if os.path.exists(os.path.join(OUT, "CREDITS.md")) else ""
        p = sources.get("pack", {})
        need = [p.get("page", "?"), p.get("url", "?"), p.get("author", "?"), "CC0"] + list(sources.get("files", {}))
        miss = [s for s in need if s not in cr]
        if miss:
            probs.append("CREDITS.md lacks %s" % miss)
    for s in probs:
        print("FAIL  " + s)
    print("ok" if not probs else "%d problem(s)" % len(probs))
    return 1 if probs else 0


# ---------- the listening mix: a 10 s sprint, fatigue rising, soft then hard panting ----------

CADENCE = ((0.0, 90.0), (1.45, 103.0), (3.0, 164.0), (5.0, 180.0), (6.5, 195.0))


def mix(path):
    sr, dur = SR_STEP, 10.0
    m = json.load(open(os.path.join(OUT, MANIFEST), encoding="utf-8"))
    take = {}
    for k, d in m["kinds"].items():
        take[k] = []
        for f in d["files"]:
            fmt, pcm = read_wav(open(os.path.join(OUT, f), "rb").read())
            x = pcm / 32767.0
            take[k].append(x if fmt[2] == sr else signal.resample_poly(x, sr, fmt[2]))
    n = int(dur * sr)
    buses = {"step": np.zeros(n), "soft": np.zeros(n), "hard": np.zeros(n)}
    seams = {b: [] for b in buses}

    def put(bus, x, at, gain, pitch):
        if pitch != 1.0:
            x = np.interp(np.arange(0, len(x) - 1, pitch), np.arange(len(x)), x)
        i = int(round(at * sr))
        idx = (i + np.arange(len(x))) % n          # wraps: the mix loops seamlessly
        np.add.at(buses[bus], idx, gain * x)
        seams[bus].extend([i % n, (i + len(x)) % n])

    fat = lambda t: 0.25 + 0.75 * t / dur          # fatigue e rises through both tiers
    steps, t, k = [], 0.05, 0
    while t < dur:
        v = 2.7 if t < 2.0 else 5.6
        e = fat(t)
        put("step", take["step_boot"][k % len(take["step_boot"])], t, (0.55 if v < 3 else 0.8) * (1 + 0.2 * e),
            1.02 if k % 2 == 0 else 0.98)
        steps.append(t)
        k += 1
        t += 60.0 / float(np.interp(v, *zip(*CADENCE)))
    t, j, hard = 0.1, 0, False
    while t < dur:
        e = fat(t)
        nxt = [s for s in steps if t <= s <= t + 0.25]
        t = nxt[0] if nxt else t                    # inhale snaps to a foot strike (stride coupling)
        hard = e >= 0.55 or (hard and e >= 0.5)
        tier = "hard" if hard else "soft"
        per = 60.0 / (16 + 40 * e)
        g = 0.15 + 0.65 * (lambda s: s * s * (3 - 2 * s))(min(1.0, max(0.0, (e - 0.2) / 0.7)))
        put(tier, take["pant_in_%s_low" % tier][j % 3], t, g, 1.0)
        put(tier, take["pant_out_%s_low" % tier][(j + 1) % 3], t + 0.45 * per, g, 1.0)
        j += 1
        t += per
    y = buses["step"] + buses["soft"] + buses["hard"]
    with open(path, "wb") as h:
        h.write(wav_bytes(y, sr))
    db = lambda x: 20 * np.log10(max(1e-9, float(np.sqrt(np.mean(x ** 2)))))
    cut = int(4.0 * sr)                             # e reaches 0.55 at 4 s
    peak = 20 * np.log10(float(np.max(np.abs(y))))
    r_soft, r_hard, r_step = db(buses["soft"][:cut]), db(buses["hard"][cut:]), db(buses["step"])
    # a click = a jump where a take starts or ends, against that bus's own jumps (the loop's wrap included)
    worst, n_seams = 0.0, 0
    for b, x in buses.items():
        d = np.abs(np.diff(np.concatenate([x[-1:], x])))
        at = np.array(sorted(set(seams[b])), dtype=int)
        n_seams += len(at)
        worst = max(worst, float(np.max(d[at])) / max(1e-12, float(np.percentile(d, 99.9))))
    print("mix %s: peak %.1f dBFS; RMS steps %.1f, soft panting (0-4 s) %.1f, hard panting (4-10 s) %.1f dBFS; "
          "largest jump at %d seams = %.3f x the 99.9th percentile of its bus" % (path, peak, r_step, r_soft, r_hard, n_seams, worst))
    ok = peak <= -1.0 and -48 <= r_soft <= -28 and -30 <= r_hard <= -14 and r_hard - r_soft >= 6 \
        and -30 <= r_step <= -12 and worst <= 0.1
    print("ok" if ok else "FAIL  mix out of range (peak <= -1 dBFS; soft -48..-28, hard -30..-14 and 6 dB louder; "
          "steps -30..-12; seam jumps under 0.1 x the bus's 99.9th percentile)")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--fetch", metavar="DIR", help="download the CC0 footsteps into DIR (new, empty) and build all")
    g.add_argument("--rebuild", metavar="DIR", help="build all again from an earlier --fetch folder")
    g.add_argument("--synth-steps", action="store_true", help="build all, footsteps synthesized (no network)")
    g.add_argument("--check", action="store_true", help="compare the committed files with a rebuild")
    g.add_argument("--mix", metavar="OUT_WAV", help="render a 10 s listening mix and check it")
    ap.add_argument("--src", metavar="DIR", help="with --check: the --fetch folder, to rebuild the steps from its zip")
    a = ap.parse_args()
    if a.check:
        return check(a.src)
    if a.mix:
        return mix(a.mix)
    if a.synth_steps:
        write_all(build_synth_steps(), {}, [], None)
        return 0
    try:
        zp, names = saved_licences(a.rebuild) if a.rebuild else fetch(os.path.abspath(a.fetch))
        steps, origin = pack_steps(zp)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.SubprocessError) as e:
        why = "%s: %s" % (type(e).__name__, e)
        print("the CC0 footsteps are not usable (%s); synthesizing them instead" % why)
        write_all(build_synth_steps(), {}, [], why)
        return 0
    write_all(steps, origin, names, None)
    return 0


if __name__ == "__main__":
    sys.exit(main())
