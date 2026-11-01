# Tiles do mapa

Protomaps PMTiles (OpenStreetMap, schema v4), um arquivo por área. Ficam fora do git (dezenas de MB):
gere com `scripts/tiles.sh` (precisa de `brew install pmtiles`).

| arquivo | área | bbox |
|---|---|---|
| `bh.pmtiles` | Belo Horizonte | `-44.10,-20.05,-43.80,-19.75` |
| `jp-tokyo.pmtiles` | Tóquio | `139.55,35.55,139.95,35.80` |
| `jp-kansai.pmtiles` | Kyoto + Nara | `135.60,34.60,135.90,35.10` |

O build copia os que existirem pra `Must.app/tiles/`. O mapa escolhe o arquivo pela região e, no Japão, pelo mais
perto do centro da câmera. Sem arquivo, cai no Protomaps hospedado (`PROTOMAPS_KEY` no `Secrets.plist`); sem chave
também, mostra só o fundo e as camadas do app (metrô, rota, pinos).
