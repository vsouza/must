#!/usr/bin/env python3
"""Gera Must/Data/transit/tokyo-lines.geojson (a partir do N02 do MLIT), bh-lines.geojson e roma-lines.geojson.

Uso:
  python3 -I scripts/gen-transit.py <pasta com N02-24_RailroadSection.geojson e N02-24_Station.geojson>

N02 (国土数値情報 鉄道データ, MLIT) — https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2024.html
BH: linha 1 do metrô (CBTU) traçada à mão pelas estações — coordenadas aproximadas (approx: true).
Roma: metrô A, B/B1 e C (ATAC) traçados à mão pelas estações dentro do pacote it-roma — aproximados (approx: true).
Sem argumento, gera só BH e Roma (nada de rede).
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

# Metrô de Roma (ATAC), estações em ordem, coordenadas aproximadas (dentro do bbox do pacote it-roma).
# Último trem 23:30 (sex/sáb 01:30, ver PocketRulesIT); a cor é a da ATAC (o v8 mostra a linha como selo preto).
ROMA_LINES = [
    ("A", "Linha A", "Metro A · Battistini → Anagnina", "#F7931D", [
        ("Battistini", 41.9064, 12.4117), ("Cornelia", 41.9035, 12.4235), ("Baldo degli Ubaldi", 41.9030, 12.4330),
        ("Valle Aurelia", 41.9040, 12.4430), ("Cipro", 41.9073, 12.4475), ("Ottaviano", 41.9093, 12.4583),
        ("Lepanto", 41.9128, 12.4672), ("Flaminio", 41.9115, 12.4762), ("Spagna", 41.9065, 12.4825),
        ("Barberini", 41.9038, 12.4886), ("Repubblica", 41.9020, 12.4960), ("Termini", 41.9006, 12.5015),
        ("Vittorio Emanuele", 41.8950, 12.5045), ("Manzoni", 41.8905, 12.5090), ("San Giovanni", 41.8860, 12.5095),
        ("Re di Roma", 41.8820, 12.5155), ("Ponte Lungo", 41.8785, 12.5195), ("Furio Camillo", 41.8745, 12.5250),
        ("Colli Albani", 41.8705, 12.5310), ("Arco di Travertino", 41.8635, 12.5370), ("Porta Furba", 41.8580, 12.5425),
        ("Numidio Quadrato", 41.8530, 12.5520),
    ]),
    ("B", "Linha B", "Metro B · Laurentina → Rebibbia", "#0066B3", [
        ("Laurentina", 41.8270, 12.4810), ("EUR Fermi", 41.8290, 12.4700), ("EUR Palasport", 41.8330, 12.4660),
        ("EUR Magliana", 41.8380, 12.4650), ("Marconi", 41.8490, 12.4740), ("Basilica San Paolo", 41.8555, 12.4785),
        ("Garbatella", 41.8605, 12.4855), ("Piramide", 41.8755, 12.4810), ("Circo Massimo", 41.8835, 12.4880),
        ("Colosseo", 41.8910, 12.4925), ("Cavour", 41.8945, 12.4935), ("Termini", 41.9006, 12.5015),
        ("Castro Pretorio", 41.9050, 12.5055), ("Policlinico", 41.9080, 12.5120), ("Bologna", 41.9135, 12.5205),
        ("Tiburtina", 41.9105, 12.5310), ("Quintiliani", 41.9150, 12.5420), ("Monti Tiburtini", 41.9225, 12.5420),
        ("Pietralata", 41.9275, 12.5480), ("Santa Maria del Soccorso", 41.9305, 12.5560),
    ]),
    ("B1", "Linha B1", "Metro B1 · Bologna → Jonio", "#0066B3", [
        ("Bologna", 41.9135, 12.5205), ("Annibaliano", 41.9195, 12.5205), ("Libia", 41.9265, 12.5225),
        ("Conca d'Oro", 41.9355, 12.5265), ("Jonio", 41.9435, 12.5275),
    ]),
    ("C", "Linha C", "Metro C · Colosseo → Pantano", "#57B947", [
        ("Colosseo", 41.8910, 12.4925), ("Porta Metronia", 41.8800, 12.4995), ("San Giovanni", 41.8860, 12.5095),
        ("Lodi", 41.8820, 12.5205), ("Pigneto", 41.8885, 12.5285), ("Malatesta", 41.8875, 12.5380),
        ("Teano", 41.8880, 12.5460), ("Gardenie", 41.8855, 12.5560),
    ]),
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


def roma():
    features = []
    stations = {}
    for code, name, latin, color, stops in ROMA_LINES:
        features.append({"type": "Feature", "properties": {
            "kind": "line", "id": code, "name": name, "nameLatin": latin, "operator": "ATAC", "color": color,
            "approx": True, "firstTrain": "05:30", "lastTrain": "23:30",
        }, "geometry": {"type": "MultiLineString", "coordinates": [[[lng, lat] for _, lat, lng in stops]]}})
        for st, lat, lng in stops:
            stations.setdefault(st, {"lat": lat, "lng": lng, "lines": []})["lines"].append(code)
    for st, v in stations.items():
        features.append({"type": "Feature", "properties": {"kind": "station", "name": st, "lines": v["lines"], "approx": True},
                         "geometry": {"type": "Point", "coordinates": [v["lng"], v["lat"]]}})
    return {"type": "FeatureCollection", "name": "roma-lines", "attribution": "traçado aproximado à mão (ATAC)", "features": features}


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    if len(sys.argv) > 1:
        t = tokyo(sys.argv[1])
        json.dump(t, open(os.path.join(OUT, "tokyo-lines.geojson"), "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
        kinds = [f["properties"]["kind"] for f in t["features"]]
        print(f"tokyo: {kinds.count('line')} linhas, {kinds.count('station')} estações")
    json.dump(bh(), open(os.path.join(OUT, "bh-lines.geojson"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"bh: 1 linha, {len(BH_STATIONS)} estações")
    r = roma()
    json.dump(r, open(os.path.join(OUT, "roma-lines.geojson"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    kinds = [f["properties"]["kind"] for f in r["features"]]
    print(f"roma: {kinds.count('line')} linhas, {kinds.count('station')} estações")
