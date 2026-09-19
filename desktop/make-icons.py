#!/usr/bin/env python3
"""Draw the app icon (a candle flame) and write the PNG/ICO files Tauri bundles.

No image library on purpose — this has to run anywhere, including a bare CI box.
    python3 desktop/make-icons.py
"""
import math, os, struct, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "src-tauri", "icons")

BG      = (0x12, 0x12, 0x1A)
FLAME_E = (0xC8, 0x7A, 0x22)   # ขอบเปลวไฟ
FLAME_C = (0xFF, 0xF4, 0xD6)   # ใจกลาง
WAX     = (0xE6, 0xDE, 0xCA)
WAX_D   = (0xBC, 0xB2, 0x9C)
WICK    = (0x2A, 0x24, 0x20)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def draw(n):
    """Render one n×n RGBA frame. Sampled 3×3 per pixel so the edges are not jagged."""
    px = bytearray(n * n * 4)
    S = 3
    for y in range(n):
        for x in range(n):
            r = g = b = a = 0.0
            for sy in range(S):
                for sx in range(S):
                    u = (x + (sx + 0.5) / S) / n          # 0..1
                    v = (y + (sy + 0.5) / S) / n
                    c = sample(u, v)
                    if c:
                        r += c[0]; g += c[1]; b += c[2]; a += 1.0
            m = S * S
            if a > 0:
                i = (y * n + x) * 4
                px[i]     = int(round(r / a))
                px[i + 1] = int(round(g / a))
                px[i + 2] = int(round(b / a))
                px[i + 3] = int(round(255 * a / m))
    return bytes(px)


def sample(u, v):
    """Colour at (u,v) in the unit square, or None where the icon is transparent."""
    # พื้นหลังสี่เหลี่ยมมุมมน
    rad, inset = 0.22, 0.03
    x, y = u - 0.5, v - 0.5
    hx, hy = 0.5 - inset - rad, 0.5 - inset - rad
    dx, dy = max(abs(x) - hx, 0.0), max(abs(y) - hy, 0.0)
    if math.hypot(dx, dy) > rad:
        return None
    col = BG

    # แท่งเทียน
    if 0.60 <= v <= 0.90 and abs(u - 0.5) <= 0.115:
        edge = min(1.0, (0.115 - abs(u - 0.5)) / 0.05)
        col = lerp(WAX_D, WAX, edge)
        if v <= 0.625 and abs(u - 0.5) <= 0.115:
            col = lerp(col, WAX_D, 0.5)

    # ไส้เทียน
    if 0.545 <= v <= 0.615 and abs(u - 0.5) <= 0.012:
        col = WICK

    # เปลวไฟ: วงรีที่บีบให้แหลมด้านบน
    cx, top, bot = 0.5, 0.16, 0.575
    if top <= v <= bot:
        t = (v - top) / (bot - top)                  # 0 ยอด → 1 โคน
        half = 0.150 * math.sqrt(max(0.0, 1 - (1 - t) ** 2)) * (t ** 0.35)
        half = max(half, 0.004)
        d = abs(u - cx) / half if half > 0 else 9
        if d <= 1.0:
            col = lerp(FLAME_C, FLAME_E, min(1.0, d ** 1.6))
        elif d <= 1.9:                                # แสงเรือง
            k = (1.9 - d) / 0.9
            col = lerp(col, FLAME_E, 0.30 * k * k)
    return col


def png(n, rgba):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + rgba[y * n * 4:(y + 1) * n * 4] for y in range(n))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def ico(frames):
    """frames: [(size, png bytes)] — PNG-compressed entries, which Windows Vista and later read."""
    head = struct.pack("<HHH", 0, 1, len(frames))
    offset = 6 + 16 * len(frames)
    dirs, blobs = b"", b""
    for size, data in frames:
        dirs += struct.pack("<BBBBHHII", size if size < 256 else 0, size if size < 256 else 0,
                            0, 0, 1, 32, len(data), offset)
        blobs += data
        offset += len(data)
    return head + dirs + blobs


def main():
    os.makedirs(OUT, exist_ok=True)
    sizes = [16, 32, 48, 64, 128, 256]
    pngs = {n: png(n, draw(n)) for n in sizes}
    files = {
        "icon.png": pngs[256], "128x128@2x.png": pngs[256],
        "128x128.png": pngs[128], "32x32.png": pngs[32],
        "Square30x30Logo.png": pngs[32], "Square44x44Logo.png": pngs[48],
        "Square71x71Logo.png": pngs[64], "Square89x89Logo.png": pngs[128],
        "Square107x107Logo.png": pngs[128], "Square142x142Logo.png": pngs[128],
        "Square150x150Logo.png": pngs[128], "Square284x284Logo.png": pngs[256],
        "Square310x310Logo.png": pngs[256], "StoreLogo.png": pngs[48],
    }
    for name, data in files.items():
        open(os.path.join(OUT, name), "wb").write(data)
    open(os.path.join(OUT, "icon.ico"), "wb").write(ico([(n, pngs[n]) for n in sizes]))
    print("wrote %d png + icon.ico into %s" % (len(files), os.path.relpath(OUT, HERE)))


if __name__ == "__main__":
    main()
