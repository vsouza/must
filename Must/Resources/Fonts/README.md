# Fontes (OFL 1.1) — identidade v8

Baixadas de [google/fonts](https://github.com/google/fonts) (pasta `ofl/`) e registradas em `UIAppFonts` (app e widgets,
via `project.yml`). Licenças em `licenses/`. Substituem Archivo, Geist Mono, Instrument Serif e Zen Kaku (v5–v7).

| Arquivo | Família | Eixos | PostScript (padrão) | Uso |
|---|---|---|---|---|
| `BricolageGrotesque.ttf` | Bricolage Grotesque | opsz 12–96, wght 200–800, wdth 75–100 | `BricolageGrotesque-96ptExtraBold` | display (wdth 92 / 700), numeral gigante e índices (wdth 78 / 800) |
| `SchibstedGrotesk.ttf` | Schibsted Grotesk | wght 400–900 | `SchibstedGrotesk-Regular` | texto 400–700, números tabulares |
| `MartianMono.ttf` | Martian Mono | wght 100–800, wdth 75–112,5 | `MartianMono-SemiExpandedRegular` | ficha técnica, horários, códigos (wdth 100 / 500) |

Os eixos são aplicados em `DesignSystem/V8/V8Type.swift` com `kCTFontVariationAttribute` (tags `wght`, `wdth`, `opsz`):
o padrão do arquivo da Bricolage é wdth 100 e o da Martian Mono é 112,5 (mais largo que o design).
