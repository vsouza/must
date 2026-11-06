#!/bin/zsh
# UI tests do Must (rodada 23 · G): digitação dirigida, internet ruim e profiling, no simulador.
# Nenhuma chamada paga: o app abre com todos os fakes (Places, Nearby, AeroDataBox, dicas, Routes, Autocomplete,
# Em cartaz) e um board novo do seed numa pasta temporária (`-debugFreshStore`), sem tocar no board do simulador.
#
# Uso:
#   scripts/ui-tests.sh                         # tudo (digitação + navegação + profiling), matriz padrão
#   scripts/ui-tests.sh AddToListTypingTests    # uma classe (ou Classe/testMetodo)
#   MATRIX="bh:normal,jp:flaky,it:dropping" scripts/ui-tests.sh FieldsTypingTests
#   DEVICE="Must-R23g" scripts/ui-tests.sh      # simulador (padrão: iPhone 17)
#
# MATRIX: região (bh|jp|it) : rede (normal|wifi|slow|flaky|dropping|offline), separados por vírgula.
# Sem MATRIX, cada cenário roda em BH, JP e IT com a rede normal e em BH com slow e offline.
# No fim, procura "Fatal error" do processo Must no log do simulador (crash que o XCTest só vê como "app saiu").
set -e
cd "$(dirname "$0")/.."
DEVICE=${DEVICE:-"iPhone 17"}
DD=${DD:-build/ui-dd}
OUT=${OUT:-build/ui-tests.xcresult}
ONLY=()
for t in "$@"; do ONLY+=("-only-testing:MustUITests/$t"); done

echo "→ build ($DEVICE)"
xcodegen generate -q
xcodebuild -project Must.xcodeproj -scheme MustUITests -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath "$DD" build-for-testing 2>&1 | grep -E "error:|\*\* " || true

UDID=$(xcrun simctl list devices available | grep -m1 "$DEVICE (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
START=$(date "+%Y-%m-%d %H:%M:%S")

echo "→ testes ${MATRIX:+(matriz $MATRIX)}"
rm -rf "$OUT"
set +e
TEST_RUNNER_MUST_UI_MATRIX="${MATRIX:-}" xcodebuild -project Must.xcodeproj -scheme MustUITests \
  -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$DD" -resultBundlePath "$OUT" \
  test-without-building "${ONLY[@]}" 2>&1 | grep -E "Test Case .*(passed|failed)|error: |measured|\*\* "
STATUS=${pipestatus[1]}
set -e

echo "→ crashes do Must no log do simulador desde $START"
xcrun simctl spawn "$UDID" log show --start "$START" --style compact \
  --predicate 'process == "Must" AND eventMessage CONTAINS "Fatal error"' 2>/dev/null | grep "Fatal error" || echo "  nenhum"
echo "resultado: $OUT (abrir no Xcode pros prints e as métricas)"
exit $STATUS
