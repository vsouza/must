#!/bin/zsh
# Gera os mapas offline (Protomaps PMTiles, OpenStreetMap) por cidade em dist/tiles/, a partir do build diário.
# Os recortes vêm de data/map-packs.json (o app lê o mesmo arquivo). Depois, scripts/tiles-upload.sh sobe pro R2.
# Precisa da CLI `pmtiles` (brew install pmtiles).
# Uso: scripts/tiles.sh [AAAAMMDD] [id ...]   (sem ids: todos)
set -e
cd "$(dirname "$0")/.."
DAY=${1:-$(curl -s https://build-metadata.protomaps.dev/builds.json | python3 -I -c "import json,sys;print(json.load(sys.stdin)[-1]['key'].split('.')[0])")}
shift 2>/dev/null || true
SRC="https://build.protomaps.com/$DAY.pmtiles"
OUT=dist/tiles
MAXZ=${MAXZ:-15}   # acima disso o MapLibre aumenta o z15 (overzoom)
mkdir -p $OUT
echo "→ build $DAY (maxzoom $MAXZ)"
python3 -I -c '
import json, sys
only = set(sys.argv[2:])
for p in json.load(open(sys.argv[1]))["packs"]:
    if not only or p["id"] in only:
        print(p["id"], ",".join(str(v) for v in p["bbox"]))
' data/map-packs.json "$@" | while read id bbox; do
  echo "→ $id ($bbox)"
  pmtiles extract $SRC $OUT/$id.pmtiles --bbox=$bbox --maxzoom=$MAXZ
done
# manifest.json: tamanho e sha256 de cada arquivo (o app confere o download e vê quando há versão nova).
python3 -I -c '
import hashlib, json, os, sys
out, day, catalog = sys.argv[1], sys.argv[2], sys.argv[3]
old = {}
try: old = {p["id"]: p for p in json.load(open(os.path.join(out, "manifest.json")))["packs"]}
except Exception: pass
packs = []
for p in json.load(open(catalog))["packs"]:
    f = os.path.join(out, p["id"] + ".pmtiles")
    if not os.path.exists(f): continue
    h = hashlib.sha256()
    with open(f, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 22), b""): h.update(chunk)
    sha = h.hexdigest()
    build = old.get(p["id"], {}).get("build") if old.get(p["id"], {}).get("sha256") == sha else day
    packs.append({"id": p["id"], "bytes": os.path.getsize(f), "sha256": sha, "build": build or day})
json.dump({"packs": packs}, open(os.path.join(out, "manifest.json"), "w"), indent=1)
' $OUT $DAY data/map-packs.json
ls -lh $OUT
