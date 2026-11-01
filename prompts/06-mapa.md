Leia `CLAUDE.md` e a tela `Mapa.png` (e `Mapa.html` — o SVG mostra exatamente a hierarquia visual). O mapa do Must é um MapKit **muito** customizado, não o mapa padrão.

## Entregar
1. `Features/Map/MapView.swift` com `Map` (MapKit SwiftUI, iOS 17+ API) usando `MapStyle.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)` — base clara e vazia. Ajuste adicional da aparência com um `MKMapView` via `UIViewRepresentable` só se precisar de `overrideUserInterfaceStyle = .light` e `mapView.showsBuildings = false`. Fundo da tela `#F6F7F9`.
2. **Overlays**: 
   - **Metrô** como `MKPolyline` finos (3pt) nas cores oficiais. Japão: linhas de Tokyo Metro/Toei/JR a partir de GeoJSON em `Data/transit/tokyo-lines.geojson` (gere um arquivo com as ~13 linhas principais a partir do N02 do MLIT ou do ODPT; se não conseguir baixar, deixe o loader pronto e um GeoJSON de exemplo com Hibiya/Ginza/Chiyoda/Tōyoko e cores: Hibiya `#B5B5AC`, Ginza `#FF9500`, Chiyoda `#00BB85`, Marunouchi `#F62E36`, Oedo `#B6007A`, Tōyoko `#DA0442`, JR Yamanote `#9ACD32`). BH: linha 1 do metrô (CBTU) em `#0C6DB2` a partir de `Data/transit/bh-lines.geojson` (trace as estações Eldorado → Vilarinho com coordenadas aproximadas; marque como aproximado). Estações como círculos brancos com borda preta 1,6pt e rótulo Archivo 11.
   - **Rota do dia**: `MKPolyline` azul `#2B7BFF` 4pt entre paradas na ordem (feitas → sólida; futuras → tracejada 2/9). Geometria: `MKDirections` a pé entre paradas < `walkMaxKm`, senão linha reta (metrô) — nunca bloquear a UI esperando rotas.
   - **Pinos**: `Annotation` custom: feitos = círculo verde 30pt com 済; próximo = preto com número; futuros = branco com borda e número; "você" = ponto azul com halo. Musts abertos agora fora do roteiro = anel azul 12pt (toque abre Lugar). Tudo com sombra `0 6 6 .18`.
   - **Escala**: barra "300 m" fixa no canto inferior esquerdo; o botão preto "300" trava o zoom em escala de bairro (`MapCameraBounds` com distância ~900 m) — é o modo padrão; pinch continua funcionando.
3. **UI por cima**: busca em vidro ("<bairro> · N musts abertos"), botão de camadas (toggle Roteiro / Abertos agora / Metrô), pílulas de modo, botões centralizar/zoom, **card inferior** de vidro com a próxima parada (número, nome + nameLocal, "reserva 19:00 · 4 min a pé · abre em 18 min", pílula "saia 18:50", botões Apple Maps / Google Maps / seta → Lugar). Deep links: `maps://?daddr=lat,lng&dirflg=r` e `comgooglemaps://?daddr=lat,lng&directionsmode=transit` (fallback web). Tab bar flutuante.
4. Home → card "Perto de você" abre o Mapa já em modo "Abertos agora".

## Verificar
- Em BH, com GPS real andando pela Savassi, o ponto azul se move, a escala "300 m" bate com a distância real, os pinos do dia aparecem numerados e o card inferior mostra a próxima parada com ETA.
- Trocando pra JP (GPS simulado em Naka-Meguro 35.6442,139.6985) as linhas de metrô aparecem nas cores certas.
