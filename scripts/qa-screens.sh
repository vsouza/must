#!/bin/zsh
# Gera prints das telas principais no simulador (pra revisão rápida, sem tocar no app).
# Uso: scripts/qa-screens.sh [pasta de saída]   (padrão: ./qa-screens)
# Usa os atalhos de DEBUG (-debugScreen) e simula data/GPS pelo UserDefaults do app.
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

W="xcrun simctl spawn $UDID defaults write dev.viniso.must"
shot() {
  local name=$1; shift
  xcrun simctl terminate "$UDID" dev.viniso.must 2>/dev/null || true
  xcrun simctl launch "$UDID" dev.viniso.must "$@" >/dev/null
  sleep ${WAIT:-5}
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "  $OUT/$name.png"
}
epoch() { python3 -c "import datetime,sys;print(int(datetime.datetime.fromisoformat(sys.argv[1]).timestamp()))" "$1"; }

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
WAIT=10 shot jp-assistente -debugScreen assistente -debugAsk "tô cansado, troca o bar de hoje por algo perto do jantar e me diz quanto já fui"

echo "→ limpando simulações"
for k in dev.simDateOn dev.simDate dev.simSetAt dev.simGPSOn dev.simLat dev.simLng skipOnboarding; do
  xcrun simctl spawn "$UDID" defaults delete dev.viniso.must $k 2>/dev/null || true
done
${=W} region bh
echo "pronto: $OUT/"
