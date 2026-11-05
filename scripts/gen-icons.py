#!/usr/bin/env python3
"""Gera os image sets dos ícones, o enum MustIcon e o ícone do app.

Uso: python3 scripts/gen-icons.py              (rodar da raiz do repo; tudo)
     python3 scripts/gen-icons.py --app-icon   (só o ícone do app; precisa de Pillow)
- Must/Resources/Assets.xcassets/Icons/<nome>.imageset (SVG, template, vetor preservado)
- Must/DesignSystem/MustIcon.swift (gerado — não editar à mão)
- Must/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024×1024, RGB sem alpha)

Ícone do app (v8, opção A de design/v8/screens/Icone.png, "Você está aqui"): fundo tinta #121212, dois arcos
brancos a 45 % e um ponto laranja #FF4A1C no centro. Nunca muda com a viagem.
"""
import json, os, re, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "design", "icons")
DST = os.path.join(ROOT, "Must", "Resources", "Assets.xcassets", "Icons")
SWIFT = os.path.join(ROOT, "Must", "DesignSystem", "MustIcon.swift")
# SVGs com <text> não renderizam no CoreSVG: ficam fora do catálogo e são desenhados em código.
TEXT_ONLY = {"feito"}

def app_icon():
    """Desenha o ícone a 4× e reduz (antialias). Geometria do Icone.html (ícone de 160 px → 1024)."""
    from PIL import Image, ImageDraw

    size, ss = 1024, 4
    k = size / 160 * ss                       # px do design → px do canvas
    ink, orange = (0x12, 0x12, 0x12), (0xFF, 0x4A, 0x1C)
    ring = tuple(round(0.45 * 255 + 0.55 * c) for c in ink)   # branco a 45 % sobre a tinta
    img = Image.new("RGB", (size * ss, size * ss), ink)
    d = ImageDraw.Draw(img)
    stroke = round(1.3 * k)                   # 1 px a 160 engrossado pra ler a 60 px
    for left, top in [(-70, -100), (20, 30)]:
        box = [left * k, top * k, (left + 210) * k, (top + 210) * k]
        d.ellipse(box, outline=ring, width=stroke)
    r = 23 * k
    c = size * ss / 2
    d.ellipse([c - r, c - r, c + r, c + r], fill=orange)
    img = img.resize((size, size), Image.LANCZOS).convert("RGB")
    out = os.path.join(ROOT, "Must", "Resources", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(out, exist_ok=True)
    img.save(os.path.join(out, "AppIcon.png"), optimize=True)
    json.dump({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(out, "Contents.json"), "w"))
    print(f"AppIcon.png {img.size[0]}×{img.size[1]} {img.mode} em {os.path.relpath(out, ROOT)}")


if "--app-icon" in sys.argv:
    app_icon()
    raise SystemExit(0)

# Nada de japonês na interface (v8): o rótulo do ícone perde o que vier em kanji/kana ("feito · 済" → "feito").
CJK = re.compile(r"\s*·?\s*[\u2E80-\u9FFF\uF900-\uFAFF\uFF00-\uFFEF]+")

rows = {}
for line in open(os.path.join(SRC, "README.md"), encoding="utf-8"):
    m = re.match(r"\|\s*`([\w-]+)\.svg`\s*\|\s*([^|]+?)\s*\|\s*`([^`]+)`\s*\|", line)
    if m:
        rows[m.group(1)] = (CJK.sub("", m.group(2)).strip(), m.group(3))

files = sorted(f[:-4] for f in os.listdir(SRC) if f.endswith(".svg"))
missing = [f for f in files if f not in rows]
if missing:
    raise SystemExit(f"sem linha no README: {missing}")

shutil.rmtree(DST, ignore_errors=True)
os.makedirs(DST)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(DST, "Contents.json"), "w"))
for name in files:
    if name in TEXT_ONLY:
        continue
    d = os.path.join(DST, f"{name}.imageset")
    os.makedirs(d)
    shutil.copy(os.path.join(SRC, f"{name}.svg"), d)
    json.dump({
        "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
    }, open(os.path.join(d, "Contents.json"), "w"), indent=1)

def case(name):
    parts = name.split("-")
    return parts[0] + "".join(p.capitalize() for p in parts[1:])

out = [
    "// GERADO por scripts/gen-icons.py a partir de design/icons — não editar à mão.",
    "",
    "/// Set próprio do Must (traço 1.6, viewBox 24). `rawValue` = nome do arquivo/asset.",
    "enum MustIcon: String, CaseIterable, Codable, Sendable, Identifiable {",
]
out += [f'    case {case(n)} = "{n}"' for n in files]
out += ["", "    var id: String { rawValue }", "", "    /// Nome em pt-BR (README dos ícones).", "    var label: String {", "        switch self {"]
out += [f'        case .{case(n)}: "{rows[n][0]}"' for n in files]
out += ["        }", "    }", "", "    /// SF Symbol da Apple usado como fallback.", "    var fallbackSymbol: String {", "        switch self {"]
out += [f'        case .{case(n)}: "{rows[n][1]}"' for n in files]
out += ["        }", "    }", "", "    /// Desenhado em código (o SVG tem `<text>`), sem asset no catálogo.",
        "    var isTextGlyph: Bool { " + " || ".join(f"self == .{case(n)}" for n in sorted(TEXT_ONLY)) + " }", "}", ""]
open(SWIFT, "w", encoding="utf-8").write("\n".join(out))
app_icon()
print(f"{len(files)} ícones · {len(files) - len(TEXT_ONLY)} no catálogo · enum em {os.path.relpath(SWIFT, ROOT)}")
