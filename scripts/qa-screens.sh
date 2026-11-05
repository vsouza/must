#!/bin/zsh
# Gera prints das telas principais no simulador (pra revisão rápida, sem tocar no app).
# Uso: scripts/qa-screens.sh [pasta de saída]   (padrão: ./qa-screens)
# Usa os atalhos de DEBUG (-debugScreen) e simula data/GPS pelo UserDefaults do app.
# Nenhuma tela chama API paga: Places (debugPlaces), Nearby (debugNearby), AeroDataBox (debugFlight)
# e tips de pessoas (debugTips) ficam com fakes durante o script inteiro. Só o Open-Meteo/MapKit/Wikimedia rodam de verdade.
set -e
cd "$(dirname "$0")/.."
OUT=${1:-qa-screens}
DEVICE=${DEVICE:-"iPhone 17"}
DD=${DD:-build/qa-dd}
mkdir -p "$OUT"

echo "→ build ($DEVICE)"
xcodebuild -project Must.xcodeproj -scheme Must -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$DD" build >/dev/null
UDID=$(xcrun simctl list devices available | grep -m1 "$DEVICE (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$DD/Build/Products/Debug-iphonesimulator/Must.app"

# Preferências do app ficam no container dele (gravar no domínio global do simulador não chega no app).
PREFS="$(xcrun simctl get_app_container "$UDID" dev.viniso.must data)/Library/Preferences/dev.viniso.must"
GROUP="$(xcrun simctl get_app_container "$UDID" dev.viniso.must group.dev.viniso.must 2>/dev/null || true)"
W="xcrun simctl spawn $UDID defaults write $PREFS"
shot() {
  local name=$1; shift
  xcrun simctl terminate "$UDID" dev.viniso.must 2>/dev/null || true
  # A caixa do App Group (Share Extension) abre por cima se tiver item antigo: esvazia antes de cada tela.
  if [ -n "$GROUP" ]; then rm -rf "$GROUP/Inbox"; fi
  xcrun simctl launch "$UDID" dev.viniso.must "$@" >/dev/null
  sleep ${WAIT:-5}
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "  $OUT/$name.png"
}
epoch() { python3 -c "import datetime,sys;print(int(datetime.datetime.fromisoformat(sys.argv[1]).timestamp()))" "$1"; }

# Fakes globais: nenhuma chamada paga durante o script (Places, Nearby, AeroDataBox, tips de pessoas).
${=W} debugPlaces -string fake; ${=W} debugNearby -string fake; ${=W} debugFlight -string fake; ${=W} debugTips -string fake

# ── v8 (prompt 23 e 24, rodada 22) ─────────────────────────────────────────────────────────────────
# `ONLY=v8 scripts/qa-screens.sh` tira só estas (20 telas por região, comparar com design/v8/screens/*.png).
# Cada agente da rodada 22 só mexe nas linhas das suas telas (C: capa…noite; D: guia…proximos; E: região it).
v8shots() { # $1 = prefixo (jp|bh|it), $2 = lugar de exemplo, $3 = museu de exemplo, $4 = lista de exemplo, $5 = bairro do dia
  local r=$1
  # Dia do motor aceito antes de tudo (capa, Agora, Linha, Guia e Boa noite precisam de um dia; o Guia não refaz). (F)
  WAIT=12 shot $r-v8-aceitar -debugScreen aceitar-dia:$5
  shot $r-v8-capa -debugScreen capa                 # 01 CapaJP/CapaBR/CapaIT          (C)
  WAIT=9 shot $r-v8-capa-foto -debugScreen capa -capaFoto  # 01b CapaFoto (força a foto; sem a flag, os prints usam a cor) (C)
  shot $r-v8-bom-dia -debugScreen bom-dia           # 02 Manha                         (C)
  shot $r-v8-agora -debugScreen agora               # 03 Agora                         (C)
  shot $r-v8-dia -debugScreen dia                   # 04 Dia / DiaIT                   (C)
  shot $r-v8-montar -debugScreen montar             # 05 Montar                        (C)
  WAIT=9 shot $r-v8-proposta -debugScreen proposta  # 05b Montar › Gerar (proposta)    (C)
  shot $r-v8-guia -debugScreen guia                 # 06 Guia                          (D)
  shot $r-v8-dicas -debugScreen dicas               # 07 Dicas                         (D)
  shot $r-v8-bolso -debugScreen bolso               # 08 Utilidades / BolsoIT          (D)
  shot $r-v8-lugar -debugScreen lugar:$2            # 09 LugarFoto / LugarIT           (D)
  shot $r-v8-lugar-sem-foto -debugScreen lugar:$2 -debugNoPhotos YES  # 09 Lugar (sem foto no disco) (D)
  shot $r-v8-museu -debugScreen museu:$3            # 09 MuseuFoto / MuseuIT           (D)
  shot $r-v8-musts -debugScreen musts               # 10 Musts                         (D)
  shot $r-v8-lista -debugScreen lista:$4            # 11 Lista                         (D)
  shot $r-v8-proximos -debugScreen proximos         # 12 Proximos                      (D)
  shot $r-v8-ir -debugScreen ir:$2                  # 13 Transporte                    (C)
  shot $r-v8-noite -debugScreen noite               # 14 Noite                         (C)
  shot $r-v8-ajustes -debugScreen ajustes           # Ajustes › Região                 (E)
  shot $r-v8-xxxl-capa -debugScreen capa -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
  shot $r-v8-xxxl-agora -debugScreen agora -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
  # QA (F): as outras 4 principais em xxxLarge (o app limita em .xxxLarge) e o modo avião (`-debugNetwork offline`).
  local XL="-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL"
  shot $r-v8-xxxl-dia -debugScreen dia ${=XL}
  shot $r-v8-xxxl-lugar -debugScreen lugar:$2 ${=XL}
  shot $r-v8-xxxl-bolso -debugScreen bolso ${=XL}
  shot $r-v8-xxxl-dicas -debugScreen dicas ${=XL}
  local OFF="-debugNetwork offline"
  shot $r-v8-off-capa -debugScreen capa ${=OFF}
  shot $r-v8-off-agora -debugScreen agora ${=OFF}
  shot $r-v8-off-dia -debugScreen dia ${=OFF}
  shot $r-v8-off-lugar -debugScreen lugar:$2 ${=OFF}
  shot $r-v8-off-bolso -debugScreen bolso ${=OFF}
  shot $r-v8-off-dicas -debugScreen dicas ${=OFF}
}
${=W} skipOnboarding -bool YES
${=W} dev.simDateOn -bool YES; ${=W} dev.simSetAt -float 0; ${=W} dev.simGPSOn -bool YES

echo "→ v8 · Japão · sáb 15 nov 14:20 · Shinjuku (CapaJP, Agora, Dia)"
${=W} region jp
${=W} dev.simDate -float $(epoch 2026-11-15T14:20:00+09:00)
${=W} dev.simLat -float 35.6909; ${=W} dev.simLng -float 139.7003
v8shots jp j05 j28 eat shinjuku

echo "→ v8 · BH · sáb 7 nov 14:35 · Savassi (CapaBR)"
${=W} region bh
${=W} dev.simDate -float $(epoch 2026-11-07T14:35:00-03:00)
${=W} dev.simLat -float -19.9385; ${=W} dev.simLng -float -43.9343
v8shots bh p01 p01 eat savassi

echo "→ v8 · Roma · qui 15 abr 2027 11:40 · Trastevere (CapaIT); dia 4 em Monti pro DiaIT"
${=W} region it
${=W} dev.simDate -float $(epoch 2027-04-15T11:40:00+02:00)
${=W} dev.simLat -float 41.8897; ${=W} dev.simLng -float 12.4695
v8shots it r02 r46 eat trastevere
${=W} dev.simDate -float $(epoch 2027-04-14T14:00:00+02:00)
${=W} dev.simLat -float 41.8955; ${=W} dev.simLng -float 12.4925
WAIT=12 shot it-v8-aceitar-monti -debugScreen aceitar-dia:monti
shot it-v8-dia-monti -debugScreen dia

if [ "${ONLY:-}" != "v8" ]; then
echo "→ BH · sábado 31 out 09:30 · Savassi"
${=W} skipOnboarding -bool YES; ${=W} region bh
${=W} dev.simDateOn -bool YES; ${=W} dev.simDate -float $(epoch 2026-10-31T09:30:00-03:00); ${=W} dev.simSetAt -float 0
${=W} dev.simGPSOn -bool YES; ${=W} dev.simLat -float -19.9385; ${=W} dev.simLng -float -43.9343
shot bh-inicio
shot bh-musts -debugScreen musts
shot bh-lista -debugScreen lista:eat
shot bh-montar -debugScreen montar
shot bh-proposta -debugScreen proposta
shot bh-trocar -debugScreen trocar
shot bh-hoje -debugScreen aceitar
shot bh-mapa -debugScreen mapa
shot bh-gasto -debugScreen gasto
shot bh-viagem -debugScreen viagem
shot bh-ajustes -debugScreen ajustes
shot bh-regiao -debugScreen regiao

echo "→ Japão · 15 nov 18:42 · Naka-Meguro"
${=W} region jp
${=W} dev.simDate -float $(epoch 2026-11-15T18:42:00+09:00)
${=W} dev.simLat -float 35.6442; ${=W} dev.simLng -float 139.6985
shot jp-inicio
shot jp-hoje -debugScreen aceitar
shot jp-lugar -debugScreen lugar:j01
shot jp-viagem -debugScreen viagem
shot jp-reservas -debugScreen reservas
shot jp-mapa -debugScreen mapa
shot jp-compras -debugScreen compras
shot jp-compras-regras -debugScreen compras-regras
WAIT=10 shot jp-assistente -debugScreen assistente -debugAsk "tô cansado, troca o bar de hoje por algo perto do jantar e me diz quanto já fui"

echo "→ Japão · photo/art (prompt 13) · Yanaka 15 nov 15:20, nuvens 20%"
${=W} dev.simDate -float $(epoch 2026-11-15T15:20:00+09:00)
${=W} dev.simLat -float 35.7270; ${=W} dev.simLng -float 139.7700
${=W} dev.simCloud -int 20
shot jp-foto -debugScreen lugar:j18
shot jp-foto-painel -debugScreen painel:j18
shot jp-luz -debugScreen luz
WAIT=10 shot jp-3d -debugScreen 3d:j18
${=W} dev.simCloud -int 80
shot jp-foto-nublado -debugScreen painel:j18
${=W} dev.simCloud -int -1
${=W} dev.simDate -float $(epoch 2026-11-26T11:00:00+09:00)
shot jp-arte -debugScreen lugar:j20
shot jp-arte-painel -debugScreen painel:j20
shot jp-musts -debugScreen musts
shot jp-ingresso-entrada -debugScreen ingresso-entrada
shot jp-ingresso-revisar -debugScreen ingresso-revisar

echo "→ BH · sport · Pampulha dom 1 nov 07:40"
${=W} region bh
${=W} dev.simDate -float $(epoch 2026-11-01T07:40:00-03:00)
${=W} dev.simLat -float -19.8517; ${=W} dev.simLng -float -43.9733
shot bh-esporte -debugScreen lugar:p28
shot bh-esporte-painel -debugScreen painel:p28

echo "→ Japão · ingresso e experiência (prompt 14 · C) · Naka-Meguro 15 nov 09:00"
${=W} region jp
${=W} dev.simDate -float $(epoch 2026-11-15T09:00:00+09:00)
${=W} dev.simLat -float 35.6442; ${=W} dev.simLng -float 139.6985
shot jp-ingresso -debugScreen ingresso
shot jp-experiencia -debugScreen painel:demo-sushi-tsukiji
shot jp-reservas-ingresso -debugScreen reservas

echo "→ Japão · Carteira (prompt 15 · B) · Naka-Meguro 15 nov 09:00"
shot jp-carteira -debugScreen carteira

echo "→ Japão · Voos (prompt 15 · C) · 10 nov 2026 20:00 −03:00 (data simulada), status de mentira"
${=W} dev.simDate -float $(epoch 2026-11-10T20:00:00-03:00)
${=W} dev.simLat -float 35.6442; ${=W} dev.simLng -float 139.6985
shot jp-voos -debugScreen voos
shot jp-viagem-voos -debugScreen viagem-voos
shot jp-viagem-reservas -debugScreen viagem-reservas

echo "→ Board completo (fatia 1 · prompt 14 A) · BH"
${=W} region bh
shot bh-board -debugScreen board
shot bh-board-editar -debugScreen board:editar
shot bh-editar-lista -debugScreen editar-lista:eat
shot bh-nova-lista -debugScreen nova-lista

echo "→ Adicionar por link com mapa (prompt 16) · BH: link do Maps · Japão: legenda com 3 lugares e 'November' (Places de mentira)"
shot bh-adicionar-mapa -debugScreen "adicionar:https://www.google.com/maps/place/Xapuri/@-19.8517,-43.9733,17z"
${=W} region jp
shot jp-adicionar-mapa -debugScreen "adicionar:📍 Tsukiji Outer Market | 📍 Maguroya Kurogin | 📍 Uogashi Senryo | November 2026 | Part 2"

echo "→ Experiências e Por perto (fatia 4 · prompt 14 B/C) · Japão · fakes de Nearby"
${=W} region jp
shot jp-experiencias -debugScreen experiencias
${=W} dev.simDate -float $(epoch 2026-11-15T18:42:00+09:00)
${=W} dev.simLat -float 35.6442; ${=W} dev.simLng -float 139.6985
shot jp-descobrir -debugScreen descobrir

echo "→ Google Maps (fatia 8A · prompt 17 · A) · Japão · Routes e Autocomplete de mentira (sem cota) · GPS Naka-Meguro 18:42"
${=W} debugRoutes -string fake; ${=W} debugAutocomplete -string fake
${=W} region jp
${=W} dev.simDate -float $(epoch 2026-11-15T18:42:00+09:00)
${=W} dev.simLat -float 35.6442; ${=W} dev.simLng -float 139.6985
shot jp-como-chegar -debugScreen como-chegar:j01
shot jp-buscar-nome -debugScreen "buscar-nome:koffee mam"
shot jp-buscar-nome-card -debugScreen "buscar-nome:koffee mam:escolher"
shot jp-uso-google -debugScreen uso-google

echo "→ Início novo (prompt 18 · B): Japão com e sem dia, BH com e sem dia"
${=W} region jp
${=W} dev.simDate -float $(epoch 2026-11-15T18:42:00+09:00)
${=W} dev.simLat -float 35.6909; ${=W} dev.simLng -float 139.7003
shot jp-inicio-sem-dia -debugScreen inicio
shot jp-inicio-aceito -debugScreen inicio-aceito
${=W} region bh
${=W} dev.simDate -float $(epoch 2026-10-31T09:30:00-03:00)
${=W} dev.simLat -float -19.9385; ${=W} dev.simLng -float -43.9343
shot bh-inicio-sem-dia -debugScreen inicio
shot bh-inicio-aceito -debugScreen inicio-aceito

echo "→ Tema da viagem (prompt 20) · Japão 15 nov 14:20 Shinjuku, BH 31 out 09:30 Savassi: Início, Hoje, Musts, Viagem"
${=W} region jp
${=W} dev.simDate -float $(epoch 2026-11-15T14:20:00+09:00)
${=W} dev.simLat -float 35.6909; ${=W} dev.simLng -float 139.7003
shot tema-jp-inicio -debugScreen inicio-aceito
shot tema-jp-hoje -debugScreen aceitar
shot tema-jp-musts -debugScreen musts
shot tema-jp-viagem -debugScreen viagem
${=W} region bh
${=W} dev.simDate -float $(epoch 2026-10-31T09:30:00-03:00)
${=W} dev.simLat -float -19.9385; ${=W} dev.simLng -float -43.9343
shot tema-bh-inicio -debugScreen inicio-aceito
shot tema-bh-hoje -debugScreen aceitar
shot tema-bh-musts -debugScreen musts
shot tema-bh-viagem -debugScreen viagem

echo "→ Bairros e Guia (prompt 18 · C.14–16): mapa de bolhas, sheet de Shinjuku, Guia de Shinjuku+ (15 nov, Shinjuku)"
${=W} region jp
${=W} dev.simDate -float $(epoch 2026-11-15T12:00:00+09:00)
${=W} dev.simLat -float 35.6896; ${=W} dev.simLng -float 139.7006
shot bairros-mapa -debugScreen bairros
shot bairros-shinjuku -debugScreen "bairros:shinjuku"
shot guia-shinjuku -debugScreen guia
${=W} region bh
${=W} dev.simDate -float $(epoch 2026-10-31T09:30:00-03:00)
${=W} dev.simLat -float -19.9385; ${=W} dev.simLng -float -43.9343
shot bh-bairros -debugScreen bairros

fi # ONLY=v8

echo "→ limpando simulações e chaves de debug"
for k in dev.simDateOn dev.simDate dev.simSetAt dev.simGPSOn dev.simLat dev.simLng dev.simCloud skipOnboarding \
         debugPlaces debugNearby debugFlight debugTips debugAsk debugRoutes debugAutocomplete; do
  xcrun simctl spawn "$UDID" defaults delete $PREFS $k 2>/dev/null || true
done
${=W} region bh
echo "pronto: $OUT/"
