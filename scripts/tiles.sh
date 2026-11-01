#!/bin/zsh
# Gera os tiles do mapa (Protomaps PMTiles) em Must/Data/tiles/ a partir do build diário.
# Precisa da CLI `pmtiles` (brew install pmtiles). Uso: scripts/tiles.sh [AAAAMMDD]
set -e
cd "$(dirname "$0")/.."
DAY=${1:-$(curl -s https://build-metadata.protomaps.dev/builds.json | python3 -c "import json,sys;print(json.load(sys.stdin)[-1]['key'].split('.')[0])")}
SRC="https://build.protomaps.com/$DAY.pmtiles"
OUT=Must/Data/tiles
MAXZ=${MAXZ:-15}   # acima disso o MapLibre aumenta o z15 (overzoom)
mkdir -p $OUT
echo "→ build $DAY (maxzoom $MAXZ)"
pmtiles extract $SRC $OUT/bh.pmtiles        --bbox=-44.10,-20.05,-43.80,-19.75 --maxzoom=$MAXZ
pmtiles extract $SRC $OUT/jp-tokyo.pmtiles  --bbox=139.55,35.55,139.95,35.80   --maxzoom=$MAXZ
pmtiles extract $SRC $OUT/jp-kansai.pmtiles --bbox=135.60,34.60,135.90,35.10   --maxzoom=$MAXZ
ls -lh $OUT/*.pmtiles
