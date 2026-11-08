#!/bin/zsh
# Roda a suíte no simulador sem o travamento conhecido do test runner.
#
# Sintoma (investigado em 08/11/2026): depois de sessões de prints no mesmo simulador, a 1ª rodada de `xcodebuild test`
# às vezes falha com "The test runner hung before establishing connection" depois de ~6 min. O app abre normal (primeiro
# frame em ~0,7 s), mas o XCTest injetado nunca abre a conexão com o `testmanagerd` do simulador (no log do simulador a
# rodada boa mostra "Received new test session connection from process with PID …" ~0,4 s depois do "Registering for
# test daemon availability"; a ruim nunca mostra). É uma corrida do simulador/XCTest, não do código do app: fechar o app
# antes não resolve; reiniciar o simulador resolve.
#
# O que este script faz: fecha o app, roda a suíte e vigia o log. Se em 120 s depois do fim do build (a última fase do
# build imprime "Secrets.plist copiado"; o "Testing started" do xcodebuild só sai no fim, por buffer) a suíte não começou
# ("Test Suite 'All tests' started"), mata a rodada, reinicia o simulador e tenta de novo (até 2 tentativas).
#
# Uso: scripts/test.sh [nome-ou-UDID do simulador] [pasta do derivedData]
#   padrão: "iPhone 17" e build/dd-main. Saída completa em build/test-last.log.
set -u
cd "$(dirname "$0")/.."
DEVICE=${1:-"iPhone 17"}
DD=${2:-build/dd-main}
LOG=build/test-last.log
mkdir -p build

if [[ "$DEVICE" =~ ^[0-9A-F-]{36}$ ]]; then UDID=$DEVICE
else UDID=$(xcrun simctl list devices available | grep -m1 "$DEVICE (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'); fi
[ -z "$UDID" ] && { echo "simulador não encontrado: $DEVICE"; exit 2; }

run_once() {
  xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1
  xcrun simctl terminate "$UDID" dev.viniso.must 2>/dev/null
  : > "$LOG"
  xcodebuild -project Must.xcodeproj -scheme Must -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DD" test > "$LOG" 2>&1 &
  local pid=$! started_at=0
  while kill -0 $pid 2>/dev/null; do
    sleep 3
    if [ $started_at -eq 0 ] && grep -q "^Secrets.plist copiado" "$LOG"; then started_at=$(date +%s); fi
    if [ $started_at -gt 0 ] && ! grep -q "Test Suite 'All tests' started" "$LOG" \
       && [ $(( $(date +%s) - started_at )) -gt 120 ]; then
      echo "→ test runner não conectou em 120 s: reiniciando o simulador"
      kill $pid 2>/dev/null; pkill -P $pid 2>/dev/null; wait $pid 2>/dev/null
      xcrun simctl shutdown "$UDID" 2>/dev/null
      return 3
    fi
  done
  wait $pid; return $?
}

for attempt in 1 2 3; do
  run_once; rc=$?
  [ $rc -ne 3 ] && break
done
grep -E "✘|Test run with|TEST (SUCCEEDED|FAILED)|error:" "$LOG" | grep -v ModelCatalog | tail -15
exit $rc
