# Ícones do Must

68 símbolos, traço 1.6 em viewBox 24. Importe como *custom SF Symbols* (Xcode → Asset Catalog → New Symbol Image Set) ou renderize o SVG direto. Coluna 3 é o SF Symbol da Apple a usar enquanto o custom não estiver no catálogo.

| arquivo | nome | fallback SF Symbol |
|---|---|---|
| `ramen.svg` | ramen | `fork.knife` |
| `sushi.svg` | sushi | `fish` |
| `izakaya.svg` | izakaya | `lamp` |
| `cafe.svg` | café | `cup.and.saucer` |
| `cha-matcha.svg` | chá · matcha | `mug` |
| `cerveja.svg` | cerveja | `mug.fill` |
| `coquetel.svg` | coquetel | `wineglass` |
| `sake-vinho.svg` | sake · vinho | `wineglass` |
| `doce-konbini.svg` | doce · konbini | `birthday.cake` |
| `museu.svg` | museu | `building.columns` |
| `arte-galeria.svg` | arte · galeria | `photo.artframe` |
| `templo-torii.svg` | templo · torii | `building` |
| `parque-natureza.svg` | parque · natureza | `leaf` |
| `fuji-mirante.svg` | Fuji · mirante | `mountain.2` |
| `listening-bar.svg` | listening bar | `opticaldisc` |
| `musica-ao-vivo.svg` | música ao vivo | `music.note` |
| `boate-noite.svg` | boate · noite | `moon.stars` |
| `karaoke.svg` | karaokê | `mic` |
| `compras.svg` | compras | `bag` |
| `camera-foto.svg` | câmera · foto | `camera` |
| `roupa.svg` | roupa | `tshirt` |
| `livros-discos.svg` | livros · discos | `books.vertical` |
| `mercado-depachika.svg` | mercado · depachika | `basket` |
| `metro.svg` | metrô | `tram.fill` |
| `shinkansen-trem.svg` | shinkansen · trem | `train.side.front.car` |
| `a-pe.svg` | a pé | `figure.walk` |
| `onibus.svg` | ônibus | `bus` |
| `taxi.svg` | táxi | `car` |
| `bicicleta.svg` | bicicleta | `bicycle` |
| `mapa.svg` | mapa | `map` |
| `pino.svg` | pino | `mappin` |
| `voce-gps.svg` | você · GPS | `location` |
| `rota.svg` | rota | `arrow.triangle.turn.up.right.diamond` |
| `relogio.svg` | relógio | `clock` |
| `calendario.svg` | calendário | `calendar` |
| `reserva-ancora.svg` | reserva · âncora | `lock` |
| `yen-gasto.svg` | yen · gasto | `yensign` |
| `orcamento.svg` | orçamento | `wallet.pass` |
| `fila-espera.svg` | fila · espera | `person.2` |
| `sol.svg` | sol | `sun.max` |
| `nuvem.svg` | nuvem | `cloud` |
| `chuva.svg` | chuva | `cloud.rain` |
| `temperatura.svg` | temperatura | `thermometer.medium` |
| `feito.svg` | feito · 済 | `checkmark.seal` |
| `fica-pro-fim.svg` | fica pro fim | `bookmark` |
| `inicio.svg` | início | `house` |
| `hoje.svg` | hoje | `clock` |
| `musts-lista.svg` | musts · lista | `list.bullet` |
| `montar-ajustar.svg` | montar · ajustar | `slider.horizontal.3` |
| `assistente.svg` | assistente | `sparkles` |
| `falar.svg` | falar | `waveform` |
| `colar-link.svg` | colar link | `link` |
| `adicionar.svg` | adicionar | `plus` |
| `buscar.svg` | buscar | `magnifyingglass` |
| `filtrar.svg` | filtrar | `line.3.horizontal.decrease` |
| `trocar.svg` | trocar | `arrow.up.arrow.down` |
| `outra-proposta.svg` | outra proposta | `arrow.clockwise` |
| `editar.svg` | editar | `pencil` |
| `remover.svg` | remover | `trash` |
| `compartilhar.svg` | compartilhar | `square.and.arrow.up` |
| `exportar.svg` | exportar | `arrow.down.to.line` |
| `camadas.svg` | camadas | `square.3.layers.3d` |
| `ajustes.svg` | ajustes | `gearshape` |
| `tema.svg` | tema | `circle.lefthalf.filled` |
| `avancar.svg` | avançar | `chevron.right` |
| `voltar.svg` | voltar | `chevron.left` |
| `ok.svg` | ok | `checkmark` |
| `fechar.svg` | fechar | `xmark` |

## Como estão no app

Os SVGs são de traço; o template de *custom SF Symbol* exige contornos expandidos (sem `stroke`), então **nenhum** entrou como Symbol Image Set. Todos estão em `Must/Resources/Assets.xcassets/Icons/` como **image sets SVG** com `template-rendering-intent: template` e vetor preservado — pegam `foregroundStyle` e escalam sem perder nitidez. Usar `MustIconView(.ramen, size: 20)` ou `Image(mustIcon:)`.

- `feito.svg` usa `<text>` (o CoreSVG não desenha texto): fica fora do catálogo e o `MustIconView` desenha 済 em Zen Kaku Gothic New.
- Ícone novo: salvar o SVG aqui, adicionar a linha na tabela acima e rodar `python3 scripts/gen-icons.py` (gera os image sets e `Must/DesignSystem/MustIcon.swift`).
