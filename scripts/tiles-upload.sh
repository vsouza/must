#!/bin/zsh
# Sobe dist/tiles/ (gerado por scripts/tiles.sh) pro bucket R2 público `must-tiles`. O manifest vai por último,
# pra que o app nunca veja um sha256 de um arquivo que ainda não subiu. Precisa de `npx wrangler login` uma vez.
# Uso: scripts/tiles-upload.sh [id ...]   (sem ids: todos os .pmtiles de dist/tiles)
set -e
cd "$(dirname "$0")/.."
BUCKET=${BUCKET:-must-tiles}
DIR=dist/tiles
[ -f $DIR/manifest.json ] || { echo "rode scripts/tiles.sh antes"; exit 1; }
ids=("$@")
[ ${#ids} -gt 0 ] || ids=(${(f)"$(cd $DIR && ls *.pmtiles | sed 's/\.pmtiles$//')"})
for id in $ids; do
  echo "→ $id ($(du -h $DIR/$id.pmtiles | cut -f1))"
  npx --yes wrangler r2 object put "$BUCKET/$id.pmtiles" --file "$DIR/$id.pmtiles" \
    --content-type application/octet-stream --cache-control "public, max-age=3600" --remote
done
npx --yes wrangler r2 object put "$BUCKET/manifest.json" --file $DIR/manifest.json \
  --content-type application/json --cache-control "no-cache" --remote
echo "pronto · confira: curl -sI \$MAP_TILES_URL/manifest.json"
