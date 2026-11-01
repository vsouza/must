#!/usr/bin/env python3
"""Gera os glyphs SDF (PBF) do mapa a partir das fontes do bundle.

Uso: python3 scripts/gen-glyphs.py   (precisa de freetype-py e numpy)
Saída: Must/DesignSystem/MapStyle/glyphs/<fontstack>/<start>-<end>.pbf

Formato igual ao do node-fontnik / font-maker: fonte a 24 px, borda 3 px, raio 8, cutoff 0.25.
Kanji, hiragana e katakana não precisam de PBF: o MapLibre desenha no aparelho com a fonte de
`MLNIdeographicFontFamilyName` (Zen Kaku Gothic New, no Info.plist).
"""
import math
import os
import sys

import freetype
import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..")
FONTS = os.path.join(ROOT, "Must/Resources/Fonts")
OUT = os.path.join(ROOT, "Must/DesignSystem/MapStyle/glyphs")

SIZE, BUFFER, RADIUS, CUTOFF = 24, 3, 8, 0.25

# (nome do fontstack, arquivo, eixos variáveis {tag: valor})
STACKS = [
    ("Archivo SemiBold", "Archivo.ttf", {"wght": 600}),
    ("Archivo Bold", "Archivo.ttf", {"wght": 700}),
    ("Zen Kaku Gothic New Medium", "ZenKakuGothicNew-Medium.ttf", {}),
]
# latim, latim estendido, pontuação (· – ’ …), formas de largura cheia
RANGES = [0, 256, 512, 7680, 8192, 12288, 65280]

INF = 1e20


def edt1d(f, n):
    """Transformada de distância 1D (Felzenszwalb & Huttenlocher), como no tiny-sdf."""
    d = [0.0] * n
    v = [0] * n
    z = [0.0] * (n + 1)
    k = 0
    z[0] = -INF
    z[1] = INF
    for q in range(1, n):
        s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k])
        while s <= z[k]:
            k -= 1
            s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k])
        k += 1
        v[k] = q
        z[k] = s
        z[k + 1] = INF
    k = 0
    for q in range(n):
        while z[k + 1] < q:
            k += 1
        d[q] = (q - v[k]) ** 2 + f[v[k]]
    return d


def edt(grid, w, h):
    for x in range(w):
        col = edt1d([grid[y][x] for y in range(h)], h)
        for y in range(h):
            grid[y][x] = col[y]
    for y in range(h):
        grid[y] = edt1d(grid[y], w)
    return grid


def sdf(alpha):
    """alpha: matriz (h, w) 0..1 já com a borda. Devolve bytes 0..255."""
    h, w = alpha.shape
    outer = [[0.0] * w for _ in range(h)]
    inner = [[0.0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            a = float(alpha[y, x])
            if a == 1:
                outer[y][x], inner[y][x] = 0.0, INF
            elif a == 0:
                outer[y][x], inner[y][x] = INF, 0.0
            else:
                outer[y][x] = max(0.0, 0.5 - a) ** 2
                inner[y][x] = max(0.0, a - 0.5) ** 2
    edt(outer, w, h)
    edt(inner, w, h)
    out = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            d = math.sqrt(outer[y][x]) - math.sqrt(inner[y][x])
            out[y * w + x] = max(0, min(255, round(255 - 255 * (d / RADIUS + CUTOFF))))
    return bytes(out)


# --- protobuf mínimo ---
def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def zigzag(n):
    return (n << 1) ^ (n >> 31)


def field(num, wire, payload):
    key = varint((num << 3) | wire)
    if wire == 0:
        return key + varint(payload)
    return key + varint(len(payload)) + payload


def glyph_msg(gid, bitmap, width, height, left, top, advance):
    m = field(1, 0, gid)
    if bitmap:
        m += field(2, 2, bitmap)
    m += field(3, 0, width) + field(4, 0, height)
    m += field(5, 0, zigzag(left)) + field(6, 0, zigzag(top)) + field(7, 0, advance)
    return m


def set_axes(face, axes):
    if not axes:
        return
    info = face.get_variation_info()
    coords = [axes.get(ax.tag, ax.default) for ax in info.axes]
    face.set_var_design_coords(coords)


def render_range(face, start, name):
    ascender = face.size.ascender // 64
    glyphs = b""
    for cp in range(start, start + 256):
        idx = face.get_char_index(cp)
        if idx == 0:
            continue
        face.load_glyph(idx, freetype.FT_LOAD_DEFAULT | freetype.FT_LOAD_NO_HINTING)
        face.glyph.render(freetype.FT_RENDER_MODE_NORMAL)
        bm = face.glyph.bitmap
        w, h = bm.width, bm.rows
        advance = round(face.glyph.advance.x / 64)
        left = face.glyph.bitmap_left
        top = face.glyph.bitmap_top - ascender
        bitmap = b""
        if w and h:
            pitch = bm.pitch
            raw = np.frombuffer(bytes(bm.buffer), dtype=np.uint8).reshape(h, pitch)[:, :w] / 255.0
            padded = np.zeros((h + 2 * BUFFER, w + 2 * BUFFER))
            padded[BUFFER:BUFFER + h, BUFFER:BUFFER + w] = raw
            bitmap = sdf(padded)
        glyphs += field(3, 2, glyph_msg(cp, bitmap, w, h, left, top, advance))
    stack = field(1, 2, name.encode()) + field(2, 2, f"{start}-{start + 255}".encode()) + glyphs
    return field(1, 2, stack)


def main():
    for name, file, axes in STACKS:
        face = freetype.Face(os.path.join(FONTS, file))
        set_axes(face, axes)
        face.set_char_size(SIZE * 64, 0, 72, 72)
        folder = os.path.join(OUT, name)
        os.makedirs(folder, exist_ok=True)
        for start in RANGES:
            data = render_range(face, start, name)
            with open(os.path.join(folder, f"{start}-{start + 255}.pbf"), "wb") as f:
                f.write(data)
        print(f"{name}: {len(RANGES)} faixas", file=sys.stderr)


if __name__ == "__main__":
    main()
