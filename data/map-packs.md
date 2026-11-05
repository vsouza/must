# Mapas offline

Protomaps PMTiles (OpenStreetMap, schema v4), um arquivo por cidade. Os recortes estão em
[`map-packs.json`](map-packs.json): o script e o app leem o mesmo arquivo.

1. `scripts/tiles.sh [AAAAMMDD] [id …]` recorta o build diário do Protomaps em `dist/tiles/` (gitignored)
   e escreve `dist/tiles/manifest.json` (tamanho, sha256 e build de cada arquivo).
2. `scripts/tiles-upload.sh [id …]` sobe pro bucket R2 público `must-tiles` (manifest por último).
   Precisa de `npx wrangler login` uma vez.
3. O app lê a URL pública do bucket em `MAP_TILES_URL` (`Secrets.plist`).

No app (Ajustes › Mapas offline) cada cidade pode ser baixada, atualizada ou apagada; os arquivos ficam em
Application Support/tiles (fora do backup do iCloud). O mapa usa o arquivo da área que contém o centro da câmera
(as principais primeiro); fora de todas, o da área mais perto. Ordem das fontes:

1. arquivo baixado;
2. sem arquivo, o mesmo PMTiles lido do R2 pela internet (range requests);
3. sem `MAP_TILES_URL`, o Protomaps hospedado (`PROTOMAPS_KEY`);
4. sem nada, só o fundo e as camadas do app (metrô, rota, pinos).

## Roma (`it-roma`, prompt 24)

O recorte `it-roma` (bbox `12.40, 41.83, 12.56, 41.95`: centro, Vaticano, Appia e Ostiense) já está no catálogo e o app
mostra a seção "Itália" em Ajustes › Mapas offline. O arquivo **ainda não foi gerado nem subido** (download grande e
upload pro R2 são decisão do Vinicius). Pra publicar:

```sh
scripts/tiles.sh "" it-roma        # build mais recente; ou scripts/tiles.sh 20270301 it-roma
scripts/tiles-upload.sh it-roma    # sobe it-roma.pmtiles e o manifest.json atualizado
```

O `tiles.sh` reescreve o `manifest.json` com os `.pmtiles` de `dist/tiles/` e mantém as linhas do manifest anterior
pras cidades que não foram recortadas agora. Numa máquina sem o `dist/tiles/manifest.json` de antes, baixe o atual
primeiro (`curl -s $MAP_TILES_URL/manifest.json -o dist/tiles/manifest.json`), senão o manifest novo só terá Roma. Até subir,
Roma usa o PMTiles hospedado (`PROTOMAPS_KEY`) ou só o fundo, como qualquer cidade sem arquivo.
