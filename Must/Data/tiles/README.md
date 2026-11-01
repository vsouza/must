# Tiles do mapa

Protomaps PMTiles (OpenStreetMap, schema v4), um arquivo por área. Ficam fora do git (dezenas de MB):
gere com `scripts/tiles.sh` (precisa de `brew install pmtiles`).

| arquivo | área | bbox |
|---|---|---|
| `bh.pmtiles` | Belo Horizonte | `-44.10,-20.05,-43.80,-19.75` |
| `jp-tokyo.pmtiles` | Tóquio | `139.55,35.55,139.95,35.80` |
| `jp-kansai.pmtiles` | Kyoto + Nara | `135.60,34.60,135.90,35.10` |
| `bh-inhotim.pmtiles` | Inhotim · Brumadinho (2,4 MB) | `-44.30,-20.20,-44.10,-20.05` |
| `jp-fuji.pmtiles` | Fuji · Kawaguchiko (4,5 MB) | `138.62,35.34,138.86,35.56` |

O build copia os que existirem pra `Must.app/tiles/`. O mapa usa o arquivo da área que contém o centro da câmera
(as cidades primeiro) e troca quando a câmera muda de área; fora de todas, usa o da área mais perto. Sem arquivo, cai no Protomaps hospedado (`PROTOMAPS_KEY` no `Secrets.plist`); sem chave
também, mostra só o fundo e as camadas do app (metrô, rota, pinos).
