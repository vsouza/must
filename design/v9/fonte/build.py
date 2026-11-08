#!/usr/bin/env python3
"""Monta os HTML autossuficientes de design/v9 a partir de src/*.html (macros {{...}}) e renderiza os PNG."""
import math, random, re, subprocess, sys, pathlib

HERE = pathlib.Path(__file__).parent
SRC = HERE / "src"
OUT = pathlib.Path(sys.argv[1])
ONLY = sys.argv[2:]
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PH = "../v8/screens/photos/"

FONTS = ('<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
         '<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,600;12..96,700;12..96,800'
         '&family=Schibsted+Grotesk:wght@400;500;600;700;800&family=Martian+Mono:wght@400;500;700;800&display=block" rel="stylesheet">')

BASE = r"""
*{box-sizing:border-box;margin:0;padding:0}
:root{--ink:#121212;--paper:#F2F0EA;--bone:#E4E0D5;--or:#FF4A1C;--g1:#6B6B66;--g2:#A3A39C;--place:#D7000F;--jp:#D7000F;--br:#007A33;--it:#1F5FB4}
html,body{background:var(--paper);color:var(--ink);font-family:'Schibsted Grotesk',sans-serif;-webkit-font-smoothing:antialiased}
.scr{position:relative;width:390px;height:844px;overflow:hidden;display:flex;flex-direction:column;background:var(--paper)}
.mono{font-family:'Martian Mono',monospace;font-size:9px;font-weight:500;letter-spacing:.1em;text-transform:uppercase;line-height:1.55}
.disp{font-family:'Bricolage Grotesque',sans-serif;font-weight:800;letter-spacing:-.045em;line-height:.88}
.g1{color:var(--g1)}.g2{color:var(--g2)}.orc{color:var(--or)}
/* status bar */
.sb{height:47px;flex:none;display:flex;justify-content:space-between;align-items:flex-end;padding:0 26px 7px 34px;font-weight:700;font-size:15px;letter-spacing:-.01em;position:relative;z-index:6}
.sb.w{color:#fff}.sb svg{display:block}
/* bloco da foto (CutBand) */
.band{position:relative;flex:none;overflow:hidden;background:var(--place);color:#fff}
.band>.p{position:absolute;inset:0;background-size:cover;background-position:center 40%;filter:grayscale(1) contrast(1.6) brightness(1.05);mix-blend-mode:multiply}
.band::after{content:"";position:absolute;inset:0;background:radial-gradient(circle,#121212 0 .9px,transparent 1.3px) 0 0/4px 4px;opacity:.25;pointer-events:none;z-index:1}
.band>.arcs{position:absolute;inset:0;z-index:2;pointer-events:none}
.band>.in{position:relative;z-index:3;height:100%;display:flex;flex-direction:column;padding:0 20px 16px}
.top{display:flex;justify-content:space-between;align-items:flex-start;gap:10px}
/* régua */
.rule{height:12px;background:var(--ink);flex:none;position:relative;z-index:4}
.rule.pull{height:26px;display:flex;align-items:center;justify-content:center}
.rule.pull .grip{width:38px;height:6px;background:var(--or)}
.rule.pull .rl{position:absolute;right:16px;top:8px;color:var(--paper);font-family:'Martian Mono',monospace;font-size:8px;letter-spacing:.1em;text-transform:uppercase;line-height:1}
.rule.pull .ll{position:absolute;left:16px;top:8px;color:var(--g2);font-family:'Martian Mono',monospace;font-size:8px;letter-spacing:.1em;text-transform:uppercase;line-height:1}
/* botões quadrados */
.sq{width:40px;height:40px;flex:none;border:2px solid currentColor;display:flex;align-items:center;justify-content:center;font-family:'Martian Mono',monospace;font-size:15px;font-weight:700}
.sq.f{background:var(--ink);color:var(--paper);border-color:var(--ink)}
.act{font-family:'Martian Mono',monospace;font-size:9px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;border:2px solid currentColor;padding:7px 8px;flex:none;line-height:1;white-space:nowrap}
.act.f{background:var(--ink);color:var(--paper);border-color:var(--ink)}
/* faixas de seção */
.sec{display:flex;justify-content:space-between;align-items:baseline;gap:10px;padding:9px 18px;font-family:'Martian Mono',monospace;font-size:9px;font-weight:500;letter-spacing:.1em;text-transform:uppercase;line-height:1.3;flex:none}
.sec.or{background:var(--or)}.sec.ink{background:var(--ink);color:var(--paper)}.sec.ln{border-top:2px solid var(--ink)}
/* índice */
.ix{display:flex;align-items:center;gap:12px;padding:11px 18px;border-top:2px solid var(--ink);flex:none}
.ix .n{font-family:'Bricolage Grotesque',sans-serif;font-weight:800;font-size:30px;letter-spacing:-.04em;line-height:.9;width:70px;flex:none}
.ix .n small{display:block;font-family:'Martian Mono',monospace;font-size:7.5px;font-weight:500;letter-spacing:.08em;text-transform:uppercase;margin-top:4px;line-height:1.3}
.ix .d{font-family:'Martian Mono',monospace;font-weight:700;font-size:16px;letter-spacing:-.02em;width:66px;flex:none;line-height:1}
.ix .d small{display:block;font-weight:400;font-size:7.5px;letter-spacing:.08em;text-transform:uppercase;margin-top:4px;line-height:1.3;opacity:.75}
.ix .t{flex:1;min-width:0}
.ix .t b{display:block;font-size:15px;font-weight:700;line-height:1.2;letter-spacing:-.01em}
.ix .t span{display:block;font-size:11.5px;color:var(--g1);line-height:1.35;margin-top:2px}
.ix.or{background:var(--or)}.ix.or .t span{color:rgba(18,18,18,.72)}
.ix.ink{background:var(--ink);color:var(--paper);border-top-color:#3a3a38}.ix.ink .t span{color:var(--g2)}
.ix.ink+.ix:not(.ink){border-top-color:var(--ink)}
.thumb{width:54px;height:54px;flex:none;position:relative;overflow:hidden;background:var(--place)}
.thumb>.p{position:absolute;inset:0;background-size:cover;background-position:center;filter:grayscale(1) contrast(1.6) brightness(1.05);mix-blend-mode:multiply}
.thumb::after{content:"";position:absolute;inset:0;background:radial-gradient(circle,#121212 0 .7px,transparent 1.1px) 0 0/3px 3px;opacity:.25}
.thumb .pn{position:absolute;left:0;top:0;z-index:2;width:18px;height:18px;background:var(--ink);color:var(--paper);font-family:'Martian Mono',monospace;font-size:9px;font-weight:800;display:flex;align-items:center;justify-content:center}
.thumb .pn.k{background:var(--paper);color:var(--ink)}
/* chips quadrados */
.chips{display:flex;gap:6px;flex-wrap:wrap}
.chip{font-family:'Martian Mono',monospace;font-size:9px;font-weight:500;text-transform:uppercase;letter-spacing:.08em;padding:8px 10px;border:2px solid var(--ink);line-height:1;white-space:nowrap}
.chip.on{background:var(--ink);color:var(--paper)}
.chip.o{background:var(--or)}
/* barra v9: faixa de tinta, sem cápsula */
.bar{margin-top:auto;flex:none;background:var(--ink);color:var(--paper);position:relative;z-index:8}
.bar .cells{display:grid;grid-template-columns:repeat(4,1fr) 74px;height:58px}
.bar .c{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;font-family:'Martian Mono',monospace;font-size:7.5px;font-weight:500;letter-spacing:.1em;text-transform:uppercase;border-right:1px solid #2f2f2d}
.bar .c.on{background:var(--paper);color:var(--ink);font-weight:800;box-shadow:inset 0 3px 0 var(--or)}
.bar .plus{background:var(--or);color:var(--ink);display:flex;align-items:center;justify-content:center;font-family:'Bricolage Grotesque';font-weight:800;font-size:34px;line-height:1}
.bar .hm,.home{height:28px;display:flex;align-items:center;justify-content:center}
.bar .hm i,.home i{display:block;width:134px;height:5px;border-radius:3px;background:var(--paper)}
.home{flex:none}.home.k i{background:var(--ink)}
.cta{flex:none;display:grid;height:58px}
.cta>div{display:flex;align-items:center;justify-content:center;gap:8px;font-weight:800;font-size:16px;letter-spacing:-.01em}
.cta .o{background:var(--or);color:var(--ink)}.cta .k{background:var(--ink);color:var(--paper)}.cta .pp{background:var(--paper);color:var(--ink)}
.caret{display:inline-block;width:3px;background:var(--or);margin-left:3px;vertical-align:-3px}
.lbl{font-family:'Martian Mono',monospace;font-size:8px;font-weight:500;letter-spacing:.1em;text-transform:uppercase;line-height:1.4}
.flag{flex:none;border:2px solid var(--ink);display:block}
"""

SB_SVG = ('<span style="display:flex;gap:6px;align-items:center">'
          '<svg width="18" height="11" viewBox="0 0 18 11" fill="currentColor"><rect x="0" y="7" width="3" height="4"/><rect x="5" y="5" width="3" height="6"/><rect x="10" y="2.5" width="3" height="8.5"/><rect x="15" y="0" width="3" height="11"/></svg>'
          '<span style="font-size:12px;font-weight:800">5G</span>'
          '<svg width="27" height="12" viewBox="0 0 27 12"><rect x=".5" y=".5" width="23" height="11" fill="none" stroke="currentColor" opacity=".5"/><rect x="2" y="2" width="16" height="8" fill="currentColor"/><rect x="24.5" y="4" width="2" height="4" fill="currentColor" opacity=".5"/></svg>'
          '</span>')

ICONS = {
    "hoje": '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3.5" y="3.5" width="17" height="17"/><path d="M12 7.5v5l3.5 2"/></svg>',
    "explorar": '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M3.5 6.5l5.5-2.5 6 2.5 5.5-2.5v13.5l-5.5 2.5-6-2.5-5.5 2.5z"/><path d="M9 4v13.5M15 6.5V20"/></svg>',
    "musts": '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M3.5 6h17M3.5 12h17M3.5 18h11"/></svg>',
    "viagem": '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3.5" y="7.5" width="17" height="12"/><path d="M9 7.5V4.5h6v3"/></svg>',
}

def bar(active):
    cells = "".join(f'<div class="c{" on" if k == active else ""}">{ICONS[k]}<span>{k}</span></div>' for k in ["hoje", "explorar", "musts", "viagem"])
    return f'<div class="bar"><div class="cells">{cells}<div class="plus">+</div></div><div class="hm"><i></i></div></div>'

def sb(cls, time="18:10"):
    return f'<div class="sb {cls}"><span>{time}</span>{SB_SVG}</div>'

def arcs(w, h, specs, color="#fff", op=".5"):
    """specs: lista de (cx, cy, r)"""
    c = "".join(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{color}" stroke-opacity="{op}" stroke-width="1"/>' for cx, cy, r in specs)
    return f'<svg class="arcs" viewBox="0 0 {w} {h}" preserveAspectRatio="none" width="{w}" height="{h}">{c}</svg>'

def flag(kind, w=36, h=24):
    if kind == "jp":
        s = f'<rect width="36" height="24" fill="#fff"/><circle cx="18" cy="12" r="7.2" fill="#BC002D"/>'
    elif kind == "br":
        s = ('<rect width="36" height="24" fill="#009C3B"/><path d="M18 3L33 12 18 21 3 12z" fill="#FFDF00"/>'
             '<circle cx="18" cy="12" r="5.4" fill="#002776"/><path d="M12.8 11.2q5.4-1.6 10.4 1.4" stroke="#fff" stroke-width="1" fill="none"/>')
    elif kind == "it":
        s = '<rect width="12" height="24" fill="#009246"/><rect x="12" width="12" height="24" fill="#fff"/><rect x="24" width="12" height="24" fill="#CE2B37"/>'
    elif kind == "pt":
        s = '<rect width="14.4" height="24" fill="#006600"/><rect x="14.4" width="21.6" height="24" fill="#FF0000"/><circle cx="14.4" cy="12" r="4.6" fill="#FFCC00"/><circle cx="14.4" cy="12" r="2.6" fill="#fff" stroke="#FF0000" stroke-width="1.2"/>'
    return f'<svg class="flag" width="{w}" height="{h}" viewBox="0 0 36 24" preserveAspectRatio="none">{s}</svg>'

def streets(w, h, seed, park=None, rail=None, river=None, labels=()):
    """Mapa 'corte' (proposta de estilo MapLibre): ruas = papel, quadras = osso, avenidas = tinta, trilho = tinta tracejada,
    parque = quadra com trama de pontos, água = hachura."""
    rnd = random.Random(seed)
    w, h = int(w), int(h)
    out = [f'<defs><pattern id="pk{seed}" width="5" height="5" patternUnits="userSpaceOnUse"><circle cx="2.5" cy="2.5" r=".9" fill="#121212" fill-opacity=".45"/></pattern>'
           f'<pattern id="wt{seed}" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><path d="M0 0v6" stroke="#121212" stroke-opacity=".35" stroke-width="1.2"/></pattern></defs>',
           f'<rect width="{w}" height="{h}" fill="#F2F0EA"/>']
    ang = rnd.uniform(-16, -9)
    cx, cy = w / 2, h / 2
    g = [f'<g transform="rotate({ang:.1f} {cx} {cy})">']
    xs, x = [], -w
    while x < 2 * w:
        xs.append(x); x += rnd.uniform(34, 62)
    ys, y = [], -h
    while y < 2 * h:
        ys.append(y); y += rnd.uniform(30, 52)
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            gap = 5
            x0, x1, y0, y1 = xs[i] + gap, xs[i + 1] - gap, ys[j] + gap, ys[j + 1] - gap
            if rnd.random() < .12:
                mx = (x0 + x1) / 2
                g.append(f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{mx - x0 - 2:.1f}" height="{y1 - y0:.1f}" fill="#E4E0D5"/>')
                g.append(f'<rect x="{mx + 2:.1f}" y="{y0:.1f}" width="{x1 - mx - 2:.1f}" height="{y1 - y0:.1f}" fill="#E4E0D5"/>')
            else:
                g.append(f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{x1 - x0:.1f}" height="{y1 - y0:.1f}" fill="#E4E0D5"/>')
    # avenidas
    for k in rnd.sample(range(len(xs)), 3):
        g.append(f'<line x1="{xs[k]}" y1="{-h}" x2="{xs[k]}" y2="{2 * h}" stroke="#121212" stroke-width="2.4"/>')
    for k in rnd.sample(range(len(ys)), 2):
        g.append(f'<line x1="{-w}" y1="{ys[k]}" x2="{2 * w}" y2="{ys[k]}" stroke="#121212" stroke-width="2.4"/>')
    g.append('</g>')
    out += g
    if park:
        px, py, pw, ph_ = park[:4]
        out.append(f'<polygon points="{px},{py + 10} {px + pw * .55},{py} {px + pw},{py + 18} {px + pw - 8},{py + ph_} {px + 12},{py + ph_ - 6}" fill="#E4E0D5"/>')
        out.append(f'<polygon points="{px},{py + 10} {px + pw * .55},{py} {px + pw},{py + 18} {px + pw - 8},{py + ph_} {px + 12},{py + ph_ - 6}" fill="url(#pk{seed})"/>')
        if len(park) > 4:
            out.append(f'<text x="{px + pw / 2}" y="{py + ph_ / 2 + 3}" text-anchor="middle" font-family="Martian Mono" font-size="8" font-weight="700" letter-spacing=".8" fill="#121212">{park[4]}</text>')
    if river:
        d = river
        out.append(f'<path d="{d}" stroke="#F2F0EA" stroke-width="22" fill="none"/><path d="{d}" stroke="url(#wt{seed})" stroke-width="20" fill="none"/>')
    if rail:
        d = rail
        out.append(f'<path d="{d}" stroke="#121212" stroke-width="6" fill="none"/><path d="{d}" stroke="#F2F0EA" stroke-width="2" stroke-dasharray="7 7" fill="none"/>')
    for (lx, ly, txt) in labels:
        tw = len(txt) * 6.4 + 8
        out.append(f'<rect x="{lx - 4}" y="{ly - 9}" width="{tw}" height="13" fill="#F2F0EA"/><text x="{lx}" y="{ly}" font-family="Martian Mono" font-size="8" font-weight="500" letter-spacing=".8" fill="#121212">{txt}</text>')
    return "".join(out)

def pin(x, y, label, kind="or", size=24):
    x, y, s = float(x), float(y), float(size)
    fill, txt, stroke = {"or": ("#FF4A1C", "#121212", "#121212"), "ink": ("#121212", "#F2F0EA", "#121212"),
                         "plan": ("#F2F0EA", "#121212", "#121212"), "sel": ("#FF4A1C", "#121212", "#121212")}[kind]
    fs = 11 if s < 30 else 15
    extra = ""
    if kind == "sel":
        extra = f'<circle cx="{x}" cy="{y}" r="{s * .95:.1f}" fill="none" stroke="#121212" stroke-width="1"/><circle cx="{x}" cy="{y}" r="{s * 1.45:.1f}" fill="none" stroke="#121212" stroke-width="1" stroke-opacity=".5"/>'
    return (f'{extra}<rect x="{x - s / 2}" y="{y - s / 2}" width="{s}" height="{s}" fill="{fill}" stroke="{stroke}" stroke-width="2"/>'
            f'<text x="{x}" y="{y + fs * .36:.1f}" text-anchor="middle" font-family="Martian Mono" font-size="{fs}" font-weight="800" fill="{txt}">{label}</text>')

def me(x, y):
    x, y = float(x), float(y)
    return (f'<circle cx="{x}" cy="{y}" r="18" fill="none" stroke="#121212" stroke-width="1" stroke-opacity=".6"/>'
            f'<circle cx="{x}" cy="{y}" r="11" fill="none" stroke="#121212" stroke-width="1"/>'
            f'<circle cx="{x}" cy="{y}" r="6" fill="#FF4A1C" stroke="#121212" stroke-width="2"/>')

def dot(x, y, kind="or"):
    c = "#FF4A1C" if kind == "or" else "#121212"
    return f'<rect x="{float(x) - 4}" y="{float(y) - 4}" width="8" height="8" fill="{c}" stroke="#121212" stroke-width="1.5"/>'

def macro(m):
    name, _, args = m.group(1).partition(":")
    a = args.split("|") if args else []
    if name == "HEAD":
        return f'<meta charset="utf-8"><meta name="viewport" content="width=390">{FONTS}<style>{BASE}</style>'
    if name == "SB": return sb("w", *(a[:1]))
    if name == "SBI": return sb("", *(a[:1]))
    if name == "BAR": return bar(a[0])
    if name == "HOME": return '<div class="home"><i></i></div>'
    if name == "HOMEK": return '<div class="home k"><i></i></div>'
    if name == "PH": return PH + a[0]
    if name == "ARCS":
        w, h = a[0], a[1]
        specs = [tuple(s.split(",")) for s in a[2:]]
        return arcs(w, h, specs)
    if name == "ARCSK":
        w, h = a[0], a[1]
        specs = [tuple(s.split(",")) for s in a[2:]]
        return arcs(w, h, specs, "#121212", ".35")
    if name == "FLAG": return flag(a[0], *(int(v) for v in a[1:3])) if len(a) > 1 else flag(a[0])
    if name == "PIN": return pin(*a)
    if name == "ME": return me(*a)
    if name == "DOT": return dot(*a)
    if name == "MAP":
        w, h, seed = a[0], a[1], int(a[2])
        kw = {}
        for kv in a[3:]:
            k, _, v = kv.partition("=")
            if k == "park": kw["park"] = [float(t) if i < 4 else t for i, t in enumerate(v.split(","))]
            elif k in ("rail", "river"): kw[k] = v
            elif k == "label":
                kw.setdefault("labels", []); x, y, t = v.split(",", 2); kw["labels"].append((float(x), float(y), t))
        return streets(w, h, seed, **kw)
    raise SystemExit(f"macro desconhecida: {name}")

def build(path):
    html = path.read_text()
    for _ in range(3):
        html = re.sub(r"\{\{([A-Z]+(?::[^{}]*)?)\}\}", macro, html)
    return html

def shoot(html_path, png_path, w, h):
    subprocess.run([CHROME, "--headless=new", "--hide-scrollbars", "--disable-gpu", "--force-device-scale-factor=2",
                    "--virtual-time-budget=8000", f"--window-size={w},{h}", f"--screenshot={png_path}", f"file://{html_path}"],
                   check=True, capture_output=True)

for src in sorted(SRC.glob("*.html")):
    if ONLY and src.stem not in ONLY:
        continue
    html = build(src)
    m = re.search(r"<!--size:(\d+)x(\d+)-->", html)
    w, h = (int(m.group(1)), int(m.group(2))) if m else (390, 844)
    dst = OUT / src.name
    dst.write_text(html)
    shoot(dst.resolve(), (OUT / (src.stem + ".png")).resolve(), w, h)
    print("ok", src.stem, w, h)
