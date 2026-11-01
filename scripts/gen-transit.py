#!/usr/bin/env python3
"""Gera Must/Data/transit/tokyo-lines.geojson (a partir do N02 do MLIT) e bh-lines.geojson.

Uso:
  python3 -I scripts/gen-transit.py <pasta com N02-24_RailroadSection.geojson e N02-24_Station.geojson>

N02 (国土数値情報 鉄道データ, MLIT) — https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2024.html
BH: linha 1 do metrô (CBTU) traçada à mão pelas estações — coordenadas aproximadas (approx: true).
"""
import json, math, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Must", "Data", "transit")

# (operador, nome N02) → (código, nome latino, cor oficial)
LINES = {
    ("東京地下鉄", "3号線銀座線"): ("G", "Ginza", "#FF9500"),
    ("東京地下鉄", "4号線丸ノ内線"): ("M", "Marunouchi", "#F62E36"),
    ("東京地下鉄", "4号線丸ノ内線分岐線"): ("Mb", "Marunouchi (ramal)", "#F62E36"),
    ("東京地下鉄", "2号線日比谷線"): ("H", "Hibiya", "#B5B5AC"),
    ("東京地下鉄", "5号線東西線"): ("T", "Tōzai", "#009BBF"),
    ("東京地下鉄", "9号線千代田線"): ("C", "Chiyoda", "#00BB85"),
    ("東京地下鉄", "8号線有楽町線"): ("Y", "Yūrakuchō", "#C1A470"),
    ("東京地下鉄", "11号線半蔵門線"): ("Z", "Hanzōmon", "#8F76D6"),
    ("東京地下鉄", "7号線南北線"): ("N", "Namboku", "#00AC9B"),
    ("東京地下鉄", "13号線副都心線"): ("F", "Fukutoshin", "#9C5E31"),
    ("東京都", "1号線浅草線"): ("A", "Asakusa", "#E85298"),
    ("東京都", "6号線三田線"): ("I", "Mita", "#0079C2"),
    ("東京都", "10号線新宿線"): ("S", "Shinjuku", "#6CBB5A"),
    ("東京都", "12号線大江戸線"): ("E", "Ōedo", "#B6007A"),
    ("東日本旅客鉄道", "山手線"): ("JY", "JR Yamanote", "#9ACD32"),
    ("東急電鉄", "東横線"): ("TY", "Tōkyū Tōyoko", "#DA0442"),
    ("京都市", "烏丸線"): ("K", "Karasuma (Kyoto)", "#3BA559"),
    ("京都市", "東西線"): ("T-Kyoto", "Tōzai (Kyoto)", "#E9532D"),
}

# Linha 1 do metrô de BH, Eldorado → Vilarinho (aproximado).
BH_STATIONS = [
    ("Eldorado", -19.9339, -44.0283), ("Cidade Industrial", -19.9370, -44.0083), ("Vila Oeste", -19.9378, -43.9965),
    ("Gameleira", -19.9348, -43.9858), ("Calafate", -19.9265, -43.9720), ("Carlos Prates", -19.9165, -43.9575),
    ("Lagoinha", -19.9128, -43.9440), ("Central", -19.9175, -43.9345), ("Santa Efigênia", -19.9220, -43.9235),
    ("Santa Tereza", -19.9127, -43.9160), ("Horto", -19.9040, -43.9120), ("Santa Inês", -19.8945, -43.9100),
    ("José Cândido da Silveira", -19.8852, -43.9217), ("Minas Shopping", -19.8738, -43.9255),
    ("São Gabriel", -19.8605, -43.9278), ("Primeiro de Maio", -19.8480, -43.9335), ("Waldomiro Lobo", -19.8370, -43.9375),
    ("Floramar", -19.8270, -43.9410), ("Vilarinho", -19.8160, -43.9480),
]


def simplify(points, tol):
    """Douglas–Peucker em graus."""
    if len(points) < 3:
        return points
    (x1, y1), (x2, y2) = points[0], points[-1]
    dx, dy = x2 - x1, y2 - y1
    norm = math.hypot(dx, dy) or 1e-12
    best, index = 0.0, 0
    for i in range(1, len(points) - 1):
        px, py = points[i]
        d = abs(dy * px - dx * py + x2 * y1 - y2 * x1) / norm
        if d > best:
            best, index = d, i
    if best <= tol:
        return [points[0], points[-1]]
    return simplify(points[: index + 1], tol)[:-1] + simplify(points[index:], tol)


def rounded(points):
    return [[round(x, 5), round(y, 5)] for x, y in points]


def tokyo(n02):
    sections = json.load(open(os.path.join(n02, "N02-24_RailroadSection.geojson"), encoding="utf-8"))
    stations = json.load(open(os.path.join(n02, "N02-24_Station.geojson"), encoding="utf-8"))
    lines = {}
    for f in sections["features"]:
        key = (f["properties"]["N02_004"], f["properties"]["N02_003"])
        if key not in LINES:
            continue
        geom = f["geometry"]
        parts = [geom["coordinates"]] if geom["type"] == "LineString" else geom["coordinates"]
        lines.setdefault(key, []).extend(rounded(simplify([tuple(p) for p in part], 0.00006)) for part in parts)

    features = []
    for key, parts in lines.items():
        code, latin, color = LINES[key]
        features.append({"type": "Feature", "properties": {
            "kind": "line", "id": code, "name": key[1], "nameLatin": latin, "operator": key[0], "color": color, "approx": False,
        }, "geometry": {"type": "MultiLineString", "coordinates": parts}})

    merged = {}
    for f in stations["features"]:
        key = (f["properties"]["N02_004"], f["properties"]["N02_003"])
        if key not in LINES:
            continue
        coords = f["geometry"]["coordinates"]
        pts = coords if f["geometry"]["type"] == "LineString" else [c for part in coords for c in part]
        x = sum(p[0] for p in pts) / len(pts)
        y = sum(p[1] for p in pts) / len(pts)
        name = f["properties"]["N02_005"]
        code = LINES[key][0]
        # Mesma estação em linhas diferentes (≤ 350 m) vira uma só.
        found = None
        for (n, _), s in merged.items():
            if n == name and math.hypot((s["x"] - x) * 91, (s["y"] - y) * 111) < 0.35:
                found = s
                break
        if found:
            if code not in found["lines"]:
                found["lines"].append(code)
        else:
            merged[(name, len(merged))] = {"name": name, "x": x, "y": y, "lines": [code]}

    for s in merged.values():
        features.append({"type": "Feature", "properties": {"kind": "station", "name": s["name"], "lines": s["lines"]},
                         "geometry": {"type": "Point", "coordinates": [round(s["x"], 5), round(s["y"], 5)]}})
    return {"type": "FeatureCollection", "name": "tokyo-lines",
            "attribution": "国土数値情報（鉄道データ）N02-24, MLIT", "features": features}


def bh():
    line = [[lng, lat] for _, lat, lng in BH_STATIONS]
    features = [{"type": "Feature", "properties": {
        "kind": "line", "id": "L1", "name": "Linha 1", "nameLatin": "Metrô BH · Linha 1", "operator": "CBTU / Metrô BH",
        "color": "#0C6DB2", "approx": True, "firstTrain": "05:15", "lastTrain": "23:00",
    }, "geometry": {"type": "MultiLineString", "coordinates": [line]}}]
    for name, lat, lng in BH_STATIONS:
        features.append({"type": "Feature", "properties": {"kind": "station", "name": name, "lines": ["L1"], "approx": True},
                         "geometry": {"type": "Point", "coordinates": [lng, lat]}})
    return {"type": "FeatureCollection", "name": "bh-lines", "attribution": "traçado aproximado à mão", "features": features}


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    if len(sys.argv) > 1:
        t = tokyo(sys.argv[1])
        json.dump(t, open(os.path.join(OUT, "tokyo-lines.geojson"), "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
        kinds = [f["properties"]["kind"] for f in t["features"]]
        print(f"tokyo: {kinds.count('line')} linhas, {kinds.count('station')} estações")
    json.dump(bh(), open(os.path.join(OUT, "bh-lines.geojson"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"bh: 1 linha, {len(BH_STATIONS)} estações")
