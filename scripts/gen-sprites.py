#!/usr/bin/env python3
"""Gera o sprite do mapa (must.png, must@2x.png, must.json) em Must/DesignSystem/MapStyle/sprites/.
dots-green: padrão 8×8 com ponto de 1,8 px #5FAE7E (parques). station: círculo branco, borda #121316 1,6."""
import json, os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "Must/DesignSystem/MapStyle/sprites")
os.makedirs(OUT, exist_ok=True)

def build(scale, suffix):
    ss = 8  # supersampling
    icons = {"dots-green": 8, "station": 12}
    width = sum(icons.values()) * scale
    height = max(icons.values()) * scale
    sheet = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    meta, x = {}, 0
    for name, size in icons.items():
        px = size * scale
        big = Image.new("RGBA", (px * ss, px * ss), (0, 0, 0, 0))
        d = ImageDraw.Draw(big)
        c = px * ss / 2
        if name == "dots-green":
            r = 0.9 * scale * ss
            d.ellipse([c - r, c - r, c + r, c + r], fill=(0x5F, 0xAE, 0x7E, 255))
        else:
            r = 5 * scale * ss
            d.ellipse([c - r, c - r, c + r, c + r], fill=(0x12, 0x13, 0x16, 255))
            r2 = (5 - 1.6) * scale * ss
            d.ellipse([c - r2, c - r2, c + r2, c + r2], fill=(255, 255, 255, 255))
        sheet.paste(big.resize((px, px), Image.LANCZOS), (x, 0))
        meta[name] = {"x": x, "y": 0, "width": px, "height": px, "pixelRatio": scale}
        x += px
    sheet.save(os.path.join(OUT, f"must{suffix}.png"))
    with open(os.path.join(OUT, f"must{suffix}.json"), "w") as f:
        json.dump(meta, f, indent=1)

build(1, "")
build(2, "@2x")
build(3, "@3x")
