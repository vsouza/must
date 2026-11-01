#!/usr/bin/env python3
"""Gera os image sets dos ícones e o enum MustIcon a partir de design/icons/.

Uso: python3 scripts/gen-icons.py   (rodar da raiz do repo)
- Must/Resources/Assets.xcassets/Icons/<nome>.imageset (SVG, template, vetor preservado)
- Must/DesignSystem/MustIcon.swift (gerado — não editar à mão)
"""
import json, os, re, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "design", "icons")
DST = os.path.join(ROOT, "Must", "Resources", "Assets.xcassets", "Icons")
SWIFT = os.path.join(ROOT, "Must", "DesignSystem", "MustIcon.swift")
# SVGs com <text> não renderizam no CoreSVG: ficam fora do catálogo e são desenhados em código.
TEXT_ONLY = {"feito"}

rows = {}
for line in open(os.path.join(SRC, "README.md"), encoding="utf-8"):
    m = re.match(r"\|\s*`([\w-]+)\.svg`\s*\|\s*([^|]+?)\s*\|\s*`([^`]+)`\s*\|", line)
    if m:
        rows[m.group(1)] = (m.group(2), m.group(3))

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
print(f"{len(files)} ícones · {len(files) - len(TEXT_ONLY)} no catálogo · enum em {os.path.relpath(SWIFT, ROOT)}")
