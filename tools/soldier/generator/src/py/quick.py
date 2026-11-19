# ภาพเร็วจากเมช (จุดกระจาย + z-buffer) สำหรับปรับรูปทรงระหว่างทาง ; ภาพจริงใช้ Godot
import numpy as np
from PIL import Image
from skimage.measure import marching_cubes


def mc(g, level=0.0):
    V, F, Nn, _ = marching_cubes(g.F, level, spacing=(g.h, g.h, g.h), allow_degenerate=False)
    V = V + g.lo
    return V, F, -Nn          # skimage ให้นอร์มอลชี้ไปทางค่ามาก (นอกตัว = บวก) -> กลับเป็นชี้ออก?


def vnormals(V, F):
    n = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    N = np.zeros_like(V)
    for k in range(3):
        np.add.at(N, F[:, k], n)
    return N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)


def render(V, N, path, yaws=(0, 45, 90, 180), size=600, centre=None, extent=None, col=(0.86, 0.68, 0.58), C=None):
    if centre is None:
        centre = 0.5 * (V.min(0) + V.max(0))
    if extent is None:
        extent = float(np.max(V.max(0) - V.min(0))) * 1.04
    imgs = []
    for yaw in yaws:
        a = np.radians(yaw)
        R = np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]])
        P = (V - centre) @ R.T            # มองจาก +Z (หน้าหุ่น) เมื่อ yaw = 0
        Nr = N @ R.T
        s = size / extent
        px = np.round(P[:, 0] * -s + size / 2).astype(int)   # ซ้ายหุ่น (+X) อยู่ขวาภาพ เมื่อมองจากหน้า
        px = np.round(-P[:, 0] * -s + size / 2).astype(int) if False else np.round(P[:, 0] * s + size / 2).astype(int)
        py = np.round(-P[:, 1] * s + size / 2).astype(int)
        fp = max(1, int(np.ceil(0.0042 * s)))          # รอยจุดกว้างพอปิดช่องระหว่างจุดยอด
        offs = [(dx, dy) for dx in range(-(fp // 2), fp - fp // 2) for dy in range(-(fp // 2), fp - fp // 2)]
        vis = Nr[:, 2] > -0.2
        base_idx = np.nonzero(vis)[0]
        px = np.concatenate([px[base_idx] + dx for dx, dy in offs])
        py = np.concatenate([py[base_idx] + dy for dx, dy in offs])
        rep = np.tile(base_idx, len(offs))
        ok = (px >= 0) & (px < size) & (py >= 0) & (py < size)
        px, py, rep = px[ok], py[ok], rep[ok]
        order = np.argsort(P[rep, 2], kind="stable")
        px, py, idx = px[order], py[order], rep[order]
        L = np.array([0.35, 0.6, 0.72]); L /= np.linalg.norm(L)
        sh = np.clip(Nr[idx] @ L, 0, 1)
        wrap = np.clip((Nr[idx] @ L + 0.4) / 1.4, 0, 1)
        base = np.asarray(col) if C is None else C[idx]
        lum = (0.32 + 0.55 * wrap + 0.18 * sh ** 8)[:, None]
        rgb = np.clip(base * lum, 0, 1)
        img = np.full((size, size, 3), 0.13)
        img[py, px] = rgb
        imgs.append((img * 255).astype(np.uint8))
    Image.fromarray(np.hstack(imgs)).save(path)
    return path
