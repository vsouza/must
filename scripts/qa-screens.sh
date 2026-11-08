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

# `UDID=<id>` fixa o simulador (vários agentes dividem a máquina: o nome sozinho pode pegar o de outro).
UDID=${UDID:-$(xcrun simctl list devices available | grep -m1 "$DEVICE (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')}
echo "→ build ($DEVICE · $UDID)"
xcodebuild -project Must.xcodeproj -scheme Must -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" build >/dev/null
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
v8shots() { # $1 = prefixo (jp|bh|it), $2 = lugar de exemplo, $3 = museu de exemplo, $4 = lista de exemplo, $5 = bairro do dia,
            # $6 = epoch das 08:30 do dia (o dia é montado de manhã, como no uso real), $7 = vontade do Quero… (prompt 25)
  local r=$1
  # Dia do motor aceito antes de tudo (capa, Agora, Linha, Guia e Boa noite precisam de um dia; o Guia não refaz). (F)
  # Montado às 08:30 (`-dev.simDate` só nesta abertura), pra que às 14:20 a capa e o Agora estejam no meio do dia.
  WAIT=12 shot $r-v8-aceitar -debugScreen aceitar-dia:$5 -dev.simDate $6 -dev.simSetAt 0
  shot $r-v8-capa -debugScreen capa                 # 01 CapaJP/CapaBR/CapaIT          (C)
  WAIT=9 shot $r-v8-capa-foto -debugScreen capa -capaFoto  # 01b CapaFoto (força a foto; sem a flag, os prints usam a cor) (C)
  shot $r-v8-bom-dia -debugScreen bom-dia           # 02 Manha                         (C)
  shot $r-v8-agora -debugScreen agora               # 03 Agora                         (C)
  shot $r-v8-dia -debugScreen dia                   # 04 Dia / DiaIT                   (C)
  shot $r-v8-montar -debugScreen montar             # 05 Montar                        (C)
  WAIT=9 shot $r-v8-proposta -debugScreen proposta  # 05b Montar › Gerar (proposta)    (C)
  WAIT=11 shot $r-v8-outra -debugScreen outra        # 05c proposta › Outra: o que mudou (destaque + resumo)
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
  # prompt 25 · agente 25/1: Atalhos (painel sobre a capa) e Quero… (busca com o fake do Places, sem cota).
  shot $r-v8-atalhos -debugScreen atalhos           # 25 · Atalhos                     (25/1)
  WAIT=8 shot $r-v8-quero -debugScreen "quero:$7"   # 25 · Quero                       (25/1)
  shot $r-v8-xxxl-atalhos -debugScreen atalhos -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
  WAIT=8 shot $r-v8-off-quero -debugScreen "quero:$7" -debugNetwork offline
  # prompt 27 §2 · agente C (RODADA-23): card do pino (MapaPino.png) e busca "o melhor … agora" + filtro por Must (MapaFiltro.png).
  WAIT=9 shot $r-r23-mapa-pino -debugScreen mapa-pino            # MapaPino (próxima parada de hoje)
  WAIT=11 shot $r-r23-mapa-filtro -debugScreen mapa-filtro        # MapaFiltro (fake do Places, sem cota)
  WAIT=9 shot $r-r23-xxxl-mapa-pino -debugScreen mapa-pino -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
  WAIT=11 shot $r-r23-off-mapa-filtro -debugScreen mapa-filtro -debugNetwork offline  # offline · só o seu board
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
  # prompt 25 · agente 25/2: Mandar o dia (Compartilhar.png) e SOS (SOS.png); o SOS também em modo avião.
  WAIT=8 shot $r-p25-compartilhar -debugScreen compartilhar  # Compartilhar (cartaz desenhado no aparelho)
  shot $r-p25-sos -debugScreen sos                  # SOS
  shot $r-p25-off-sos -debugScreen sos ${=OFF}      # SOS sem internet (último endereço conhecido)
  # RODADA-23 · agente D: Coleção e o momento "novo colecionável" (Colecao.png, ColecionavelNovo.png).
  shot $r-r23-colecao -debugScreen colecao          # Coleção (marca alguns feitos no DEBUG)
  WAIT=6 shot $r-r23-colecionavel-novo -debugScreen colecionavel-novo:$2  # o momento, com o card girado
  shot $r-r23-xxxl-colecao -debugScreen colecao ${=XL}
  # RODADA-23 · agente B: Em cartaz, Lugar (em cartaz, amigos, filmes) e Filmes (BH cai no FilmesVazio). Só JP e BH.
  if [ "$r" != "it" ]; then
    shot $r-r23-emcartaz -debugScreen emcartaz                    # EmCartaz
    shot $r-r23-lugar-emcartaz -debugScreen lugar-emcartaz:$3     # LugarEmCartaz
    shot $r-r23-lugar-amigos -debugScreen lugar-amigos:$3 -dev.simSetAt 0   # LugarAmigos (amigos + filmes)
    shot $r-r23-filmes -debugScreen filmes:$3                     # Filmes / FilmesVazio (BH)
    shot $r-r23-xxxl-emcartaz -debugScreen emcartaz ${=XL}
    shot $r-r23-xxxl-filmes -debugScreen filmes:$3 ${=XL}
    shot $r-r23-off-emcartaz -debugScreen emcartaz ${=OFF}
    shot $r-r23-off-filmes -debugScreen filmes:$3 ${=OFF}
  fi
}

# prompt 30 · o corte (etapa 1): capa única, puxar a régua, quero… e resultado em duas faixas. `-capaFoto` baixa a foto do
# Commons uma vez pro bairro (só nos prints); `corte-capa-sem-foto` é o estado sem foto no disco.
corteshots() { # $1 = prefixo (jp|bh|it)
  local r=$1
  WAIT=10 shot $r-corte-capa -debugScreen corte-capa -capaFoto
  if [ "$r" = "jp" ]; then
    WAIT=10 shot $r-corte-capa-cartaz -debugScreen corte-capa-cartaz -capaFoto -debugEvents fake  # linha tinta "Em cartaz" no índice
    WAIT=8 shot $r-corte-capa-sem-foto -debugScreen corte-capa-sem-foto
    WAIT=10 shot $r-corte-puxando -debugScreen corte-puxando -capaFoto
    WAIT=10 shot $r-corte-quero -debugScreen corte-quero -capaFoto
    WAIT=12 shot $r-corte-cafe -debugScreen corte-cafe -capaFoto
    WAIT=12 shot $r-corte-cafe-offline -debugScreen corte-cafe-offline -capaFoto -debugNetwork offline
    WAIT=10 shot $r-corte-walk1 -debugScreen corte-walk1 -capaFoto
    WAIT=10 shot $r-corte-walk2 -debugScreen corte-walk2 -capaFoto
    WAIT=12 shot $r-corte-xxxl-cafe -debugScreen corte-cafe -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
    WAIT=10 shot $r-corte-xxxl-capa -debugScreen corte-capa -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
  fi
}
# prompt 30 · etapa 2 (Lugar, Lista, Board): o corte nas telas de lista. Lugar e Lista têm a régua puxável (o quero abre com
# origem no lugar / filtrado pela lista); o Board tem régua estática.
corte2shots() { # $1 = prefixo, $2 = lugar de exemplo, $3 = lista de exemplo
  local r=$1
  WAIT=10 shot $r-corte-lugar -debugScreen corte-lugar:$2
  WAIT=12 shot $r-corte-lugar-quero -debugScreen corte-lugar-quero:$2
  WAIT=10 shot $r-corte-board -debugScreen corte-board
  WAIT=10 shot $r-corte-board-filtro -debugScreen corte-board-filtro
  WAIT=10 shot $r-corte-montar -debugScreen corte-montar
  WAIT=10 shot $r-corte-lista -debugScreen corte-lista:$3
  WAIT=12 shot $r-corte-lista-quero -debugScreen corte-lista-quero:$3
}
# prompt 30 · etapa 2 · o corte no Dia e no Bolso (Linha, Agora, Bom dia, Boa noite, proposta com o "Outra", Bolso). A foto do
# bairro é a que já está no disco: o `corte-capa -capaFoto` da mesma região (logo acima) a guarda uma vez.
cortediashots() { # $1 = prefixo (jp|bh)
  local r=$1
  shot $r-corte-dia -debugScreen corte-dia
  shot $r-corte-agora -debugScreen corte-agora
  shot $r-corte-bomdia -debugScreen corte-bomdia
  shot $r-corte-boanoite -debugScreen corte-boanoite
  WAIT=11 shot $r-corte-proposta -debugScreen corte-proposta
  shot $r-corte-bolso -debugScreen corte-bolso
  if [ "$r" = "jp" ]; then
    shot $r-corte-xxxl-dia -debugScreen corte-dia -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
    shot $r-corte-xxxl-bolso -debugScreen corte-bolso -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
    WAIT=10 shot $r-corte-xxxl-board -debugScreen corte-board -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
    WAIT=10 shot $r-corte-xxxl-montar -debugScreen corte-montar -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
  fi
}
${=W} skipOnboarding -bool YES
${=W} dev.simDateOn -bool YES; ${=W} dev.simSetAt -float 0; ${=W} dev.simGPSOn -bool YES

# Relatório do viajante (08/11/2026): um relógio só e os dias-problema. `ONLY=viajante scripts/qa-screens.sh` tira só estas.
#  - viajante-1420-*: capa, Linha, Agora e Guia no MESMO instante (sáb 15 nov, 14:20, dia montado às 08:30, sem nada marcado).
#  - viajante-atrasou-*: o mesmo dia às 16:45 (passou da hora sem "feito": "Atrasou? Ajustei: faltam N paradas").
#  - dia-chegada-*, dia-trem-*, ultimo-dia-*: capa e Bom dia nos três dias estressantes (hospedagem e voos de exemplo).
viajanteshots() {
  echo "→ viajante · Japão · sáb 15 nov 14:20 (capa, Linha, Agora e Guia no mesmo instante)"
  ${=W} region jp
  ${=W} dev.simLat -float 35.6909; ${=W} dev.simLng -float 139.7003
  ${=W} dev.simDate -float $(epoch 2026-11-15T14:20:00+09:00)
  WAIT=12 shot viajante-aceitar -debugScreen aceitar-dia:shinjuku -dev.simDate $(epoch 2026-11-15T08:30:00+09:00) -dev.simSetAt 0
  shot viajante-1420-capa -debugScreen capa
  shot viajante-1420-linha -debugScreen dia
  shot viajante-1420-agora -debugScreen agora
  shot viajante-1420-guia -debugScreen guia
  ${=W} dev.simDate -float $(epoch 2026-11-15T16:45:00+09:00)
  shot viajante-atrasou-capa -debugScreen capa
  shot viajante-atrasou-linha -debugScreen dia
  shot viajante-atrasou-agora -debugScreen agora

  echo "→ viajante · dias-problema (-debugProblemDemo: hospedagem e voos de exemplo)"
  ${=W} dev.simLat -float 35.7720; ${=W} dev.simLng -float 140.3929   # Narita
  ${=W} dev.simDate -float $(epoch 2026-11-11T15:30:00+09:00)
  shot dia-chegada-capa -debugScreen capa -debugProblemDemo YES
  shot dia-chegada-bom-dia -debugScreen bom-dia -debugProblemDemo YES
  shot dia-chegada-voos -debugScreen voos -debugProblemDemo YES
  ${=W} dev.simLat -float 35.6812; ${=W} dev.simLng -float 139.7671   # Tokyo Station
  ${=W} dev.simDate -float $(epoch 2026-11-17T08:00:00+09:00)
  shot dia-trem-capa -debugScreen capa -debugProblemDemo YES
  shot dia-trem-bom-dia -debugScreen bom-dia -debugProblemDemo YES
  ${=W} dev.simLat -float 35.6909; ${=W} dev.simLng -float 139.7003
  ${=W} dev.simDate -float $(epoch 2026-11-24T08:00:00+09:00)
  shot ultimo-dia-capa -debugScreen capa -debugProblemDemo YES
  shot ultimo-dia-bom-dia -debugScreen bom-dia -debugProblemDemo YES
  ${=W} dev.simDate -float $(epoch 2026-11-24T15:10:00+09:00)
  shot ultimo-dia-boa-tarde -debugScreen bom-dia -debugProblemDemo YES
}
if [ "${ONLY:-}" = "viajante" ]; then
  viajanteshots
  for k in dev.simDateOn dev.simDate dev.simSetAt dev.simGPSOn dev.simLat dev.simLng dev.simCloud skipOnboarding \
           debugPlaces debugNearby debugFlight debugTips debugAsk debugRoutes debugAutocomplete; do
    xcrun simctl spawn "$UDID" defaults delete $PREFS $k 2>/dev/null || true
  done
  ${=W} region bh
  echo "pronto: $OUT/"
  exit 0
fi

echo "→ r23 · E · capa inteligente (sem dia aceito) e Minhas viagens; eventos de mentira (-debugEvents fake)"
${=W} region bh
${=W} dev.simDate -float $(epoch 2026-11-05T18:10:00-03:00)
${=W} dev.simLat -float -19.9340; ${=W} dev.simLng -float -43.9440
shot bh-r23e-capa-inteligente -debugScreen capa-inteligente -debugEvents fake  # capa-inteligente (BR) · CapaInteligente.png
shot bh-r23e-off-capa-inteligente -debugScreen capa-inteligente -debugNetwork offline  # modo avião: sem evento, sem vazio
${=W} region jp
${=W} dev.simDate -float $(epoch 2026-11-15T14:20:00+09:00)
${=W} dev.simLat -float 35.6909; ${=W} dev.simLng -float 139.7003
shot jp-r23e-capa-inteligente -debugScreen capa-inteligente -debugEvents fake  # capa-inteligente (JP)
shot jp-r23e-trocar-viagem -debugScreen trocar-viagem  # trocar-viagem · TrocarViagem.png
# prompt 28 · F3/F4: Nova viagem (NovaViagem1…9.png), rascunho de exemplo Portugal · Lisboa e Porto · 12–20 mar 2027.
for n in 1 2 3 4 5 6 7 8 9; do
  WAIT=6 shot v8-novaviagem$n -debugScreen novaviagem$n                                    # NovaViagem$n
  WAIT=6 shot v8-xxxl-novaviagem$n -debugScreen novaviagem$n -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
  WAIT=6 shot v8-off-novaviagem$n -debugScreen novaviagem$n -debugNetwork offline          # modo avião: tudo menos busca e câmbio
done

echo "→ v8 · Japão · sáb 15 nov 14:20 · Shinjuku (CapaJP, Agora, Dia)"
${=W} region jp
${=W} dev.simDate -float $(epoch 2026-11-15T14:20:00+09:00)
${=W} dev.simLat -float 35.6909; ${=W} dev.simLng -float 139.7003
v8shots jp j05 j28 eat shinjuku $(epoch 2026-11-15T08:30:00+09:00) "quero comprar um Seiko"
corteshots jp
corte2shots jp j01 eat
cortediashots jp

echo "→ v8 · BH · sáb 7 nov 14:35 · Savassi (CapaBR)"
${=W} region bh
${=W} dev.simDate -float $(epoch 2026-11-07T14:35:00-03:00)
${=W} dev.simLat -float -19.9385; ${=W} dev.simLng -float -43.9343
v8shots bh p01 p01 eat savassi $(epoch 2026-11-07T08:30:00-03:00) "quero comer um pão de queijo"
corteshots bh
cortediashots bh

echo "→ v8 · Roma · qui 15 abr 2027 11:40 · Trastevere (CapaIT); dia 4 em Monti pro DiaIT"
${=W} region it
${=W} dev.simDate -float $(epoch 2027-04-15T11:40:00+02:00)
${=W} dev.simLat -float 41.8897; ${=W} dev.simLng -float 12.4695
v8shots it r02 r46 eat trastevere $(epoch 2027-04-15T08:30:00+02:00) "quero comer uma carbonara"
corteshots it
${=W} dev.simDate -float $(epoch 2027-04-14T14:00:00+02:00)
${=W} dev.simLat -float 41.8955; ${=W} dev.simLng -float 12.4925
WAIT=12 shot it-v8-aceitar-monti -debugScreen aceitar-dia:monti -dev.simDate $(epoch 2027-04-14T08:30:00+02:00) -dev.simSetAt 0
shot it-v8-dia-monti -debugScreen dia

echo "→ corte · Portugal (viagem futura): Faltam N dias · Primeiro dia · Lisboa"
${=W} region bh
${=W} dev.simDate -float $(epoch 2026-11-07T14:35:00-03:00)
WAIT=12 shot pt-corte-capa -debugScreen corte-capa -debugTrip portugal
${=W} dev.simLat -float -19.9385; ${=W} dev.simLng -float -43.9343

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
