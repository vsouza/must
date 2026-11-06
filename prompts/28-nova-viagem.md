# Prompt 28 · Nova viagem: criar uma viagem do zero e "Minhas viagens" (05/11/2026)

Pedido do Vinicius: desenhar o fluxo como se ele fosse criar uma viagem nova do zero. Telas: `design/v8/screens/TrocarViagem.png` (Minhas viagens) e `NovaViagem1.png` … `NovaViagem9.png`. O exemplo do desenho é **Portugal (Lisboa e Porto), 12–20 mar 2027**, uma viagem que não existe nos seeds. **Aprovado pelo Vinicius em 06/11/2026** ("pode fazer a migração do prompt 28, aprovado"): migração `Region` → `Trip` como na seção 3, com as recomendações em cada **[DECISÃO]**: áreas geradas dos Musts (§3.5), mapa offline opção (a) (§3.6), `MKLocalSearchCompleter` (§3.7) e a regra de 3 passos do GPS (§3.10). Depende do prompt 27 (item 7, o botão de trocar viagem e a folha).

## 1. O fluxo (9 telas)
Cada tela é uma pergunta; Voltar e Continuar sempre no pé; barra de progresso de 8 segmentos; qualquer passo pode ser pulado e completado depois (Viagem › editar). O que cada passo grava está na seção 4.

| # | Tela | Pergunta | O que acontece |
|---|---|---|---|
| 1 | `NovaViagem1` | Pra onde? | Busca de país/cidade; mostra moeda e fuso; **cor da capa** vem do país (tabela) e pode ser trocada (6 amostras). Destino que já é uma viagem aparece apagado ("você já tem uma viagem aqui"). |
| 2 | `NovaViagem2` | Quando? | Calendário de intervalo; numeral grande com **dias até embarcar** (127); datas opcionais ("ainda não sei" = viagem em plano, como Roma hoje). |
| 3 | `NovaViagem3` | Quais cidades? | Lista ordenável (arrastar) com **noites** por cidade (− / +); conferência "8 noites de 8"; a mesma cidade pode aparecer duas vezes (Tóquio 1 e 2). |
| 4 | `NovaViagem4` | Onde fica? | **Hospedagem por cidade**: nome, endereço, entrada/saída; "Colar reserva" lê o e-mail/PDF (extrator do ingresso/voo); "Só o bairro" como alternativa. Vira o ponto de partida do dia e entra no Boa noite. |
| 5 | `NovaViagem5` | Como vai? | **Voos** de ida e volta: colar e-mail, foto do cartão de embarque ou à mão. Gera o checklist (72 h, malas, aeroporto, pouso). |
| 6 | `NovaViagem6` | O que não pode faltar? | **Colar texto de uma IA ou lista**, colar links, importar salvos do Google Maps (Takeout) ou começar vazio; mostra "12 lugares lidos · 9 em Lisboa · 3 no Porto · conferir antes de salvar". Reaproveita `PlaceExtractor`/`ColarTexto`/`SavedPlacesImporter`. |
| 7 | `NovaViagem7` | Quanto gastar? | Moeda (do país), orçamento **por dia por pessoa** (numeral gigante), total e conversão pro real com o câmbio do dia. |
| 8 | `NovaViagem8` | Leve pro bolso. | **Baixar o mapa offline** das cidades (tamanho, progresso), fotos dos lugares, "só no Wi-Fi" ligado; pode pular e baixar depois. |
| 9 | `NovaViagem9` | Pronto | Cai na **capa da viagem nova**: contagem regressiva em numeral, "Primeiro dia", bandeira/cor, card "Voo · 11 mar". No dia 1 vira a capa do dia normal. |

"Minhas viagens" (`TrocarViagem`) é a folha aberta pelo botão do canto da capa: BH (casa, GPS), Japão (agora), Roma (plano) e a linha **Nova viagem**. Deslizar uma linha: **Arquivar** (some da lista, dados ficam) e **Apagar** (confirma, apaga o `.store`).

## 2. Como é hoje (conferido no código)
- `enum Region: bh | jp | it` (`Must/Data/Region.swift`), `CaseIterable`, com `switch` em ~146 arquivos: nome, país, moeda, fuso, orçamento padrão, `TripTheme.forRegion`, áreas (`Must/Services/Areas/`), `Settings(region:)` (`fxRate` do iene), Bolso (`PocketRules`), kit do SOS por país, regras do solver (jantar ≥ 19:30 na Itália), `map-packs.json` (`region`), seeds (`data/seed-<região>.json`), schema (`region` é enum `bh|jp|it`).
- `RegionStore` (`Must/Data/RegionStore.swift`) guarda a região atual e **um `ModelContainer` por região** em `must-<id>.store` (`Region.storeFileName`, App Group). Trocar região = trocar container; nada é apagado.
- Cidades vivem no container (`City`), vindas do seed (`trip.cities`).

## 3. Proposta de migração: `Region` fixa → `Trip` dinâmica **[DECISÃO do Vinicius: sim/não e o escopo]**
Mantém o padrão que já funciona (**um container por viagem**) e troca o que é fixo por dados.

1. **Ids antigos viram ids de viagem.** `TripID` é uma `String`; as três viagens de hoje ficam com os ids `bh`, `jp`, `it`, então **os arquivos `must-bh.store`, `must-jp.store`, `must-it.store` não mudam de nome nem de conteúdo: migração de dados = nenhuma.** Viagens novas: `must-<slug>-<4 letras>.store` (ex.: `must-portugal-k3f9.store`).
2. **Registro de viagens** (`TripRegistry`): um `trips.json` no App Group (não é SwiftData; some o risco de migração de schema). Cada `Trip`: `id`, `name`, `countryCode` (ISO), `currency`, `timeZone` (padrão do país; cada cidade pode ter o seu), `colorHex`, `kind` (`home | trip`), `start?`, `end?`, `cities [{id,name,lat,lng,from?,to?,tz}]`, `home?` (hospedagem/bairro), `createdAt`, `archived`, `seedId?` (`bh|jp|it` pras três de fábrica). Na primeira abertura depois do update o registro é **semeado** com as três de hoje a partir de `Region.allCases`.
3. **`RegionStore` → `TripStore`** (mesmo arquivo/ideia, renomear por último): `current: Trip`, `container`, `switch(to:)`, `create(_:)`, `archive`, `delete`. `Region` continua existindo **só como o catálogo de seeds de fábrica** (`BuiltInTrip`), sem `switch` espalhado.
4. **Conteúdo por país vira dado**: `CountryProfile` em `data/countries/<cc>.json` (`JP`, `BR`, `IT` migrados do código; `PT` novo): moeda, fuso padrão, **janelas de refeição**, números de emergência (kit do SOS), tomada, regras de volta/tax-free, gorjeta, cor e bandeira (`TripTheme`), estações/áreas curadas. País sem perfil = **perfil genérico** (bandeira, cor escolhida, moeda, sem Bolso curado) em vez de erro. Isso tira `switch region` do solver, `PocketRules`, SOS e `TripTheme` (substituir por `trip.profile`).
5. **Áreas de cidade nova [DECISÃO]**: o `Area` curado (JP/BR/IT) não existe pra Porto. Proposta: gerar áreas **dos próprios Musts** (agrupamento por geohash de ~1,5 km, nome pelo `subLocality` do geocoder do aparelho, sigla = 3 letras do nome, vizinhos por distância) e deixar o catálogo curado só pras três de fábrica. Alternativa: sem bairros, só "centro + raio".
6. **Mapas offline [DECISÃO]**: o catálogo `data/map-packs.json` tem só `jp-*`, `bh`, `it-roma`; packs vêm de `scripts/tiles.sh` + R2. Cidade nova = pack novo. Opções: (a) o passo 8 consulta o catálogo (em cache) e, se não houver pack, mostra "mapa offline de Porto ainda não existe" com um botão que **copia o comando `scripts/tiles.sh "" <id>`** pro Vinicius gerar e subir (app pessoal, sem backend); (b) pré-gerar packs de países inteiros; (c) sem offline, só o R2 pela rede. Recomendação: (a). Nada de tiles no bundle.
7. **Busca do destino [DECISÃO]**: recomendado **`MKLocalSearchCompleter`** (MapKit, sem chave nem cota) pra país/cidade; Google Autocomplete (`ApiBudget.autocomplete`) só pra resolver os Musts, como hoje.
8. **Seeds das viagens novas**: nenhum. O board nasce vazio e entra pelo passo 6. `Settings.seenSeedIds` e `mergeSeed` só valem pras de fábrica.
9. **Export/import**: `data/board.schema.json` troca `region` (enum) por `tripId` (string) + `countryCode`; o importador **continua aceitando** arquivos antigos com `region: bh|jp|it`. Subir a versão do schema.
10. **Região automática (GPS)**: com N viagens, a regra passa a ser: (1) a viagem cujas datas incluem hoje; (2) senão, a mais recente cujo `countryCode` bate com o país do GPS; (3) senão a de `kind = home`. **[DECISÃO]** se concorda, ou se o automático só olha as três de hoje.

Riscos e ordem segura: **F0** introduzir `TripID`/`Trip`/`TripRegistry`/`CountryProfile` **sem mudar nenhuma tela** (as três de fábrica reproduzem o comportamento exato; toda a suíte atual verde, `RegionTests` adaptados); **F1** trocar os `switch region` por `profile` por área (solver, Bolso, SOS, tema, áreas), um commit por área; **F2** "Minhas viagens" com as viagens do registro; **F3** o wizard; **F4** offline/pronto + QA. Cada fase é um merge que deixa o app funcionando.

## 4. O que cada passo grava
| Passo | Onde |
|---|---|
| 1 | `Trip.name/countryCode/currency/timeZone/colorHex` (registro) |
| 2 | `Trip.start/end` e `Settings` no container novo |
| 3 | `City` no container (mesmo formato de `trip.cities` do seed) |
| 4 | hospedagem da cidade (`City.lodging`, JSON aditivo) e `Trip.home` |
| 5 | `Flight` (já existe, `Must/Models/Flight.swift`) e checklist de `Must/Data/checklists/` |
| 6 | `Place` e listas via `PlaceExtractor` → conferência → container |
| 7 | `Settings.perDayBudget`, `fxRate` (câmbio do dia, cache) |
| 8 | `OfflineMaps` (`Must/Services/OfflineMaps.swift`) e `PhotoBatch` só no Wi-Fi |
| 9 | `TripStore.create` abre o container, marca como atual e vai pra capa |

## 5. Arquivos prováveis
`Must/Data/Trip.swift`, `TripRegistry.swift`, `CountryProfile.swift`, `data/countries/*.json` (novos); `Must/Data/RegionStore.swift` (vira `TripStore`), `Region.swift`; `Must/Features/NewTrip/` (as 9 telas + `NewTripModel`, `@Observable`); `Must/Features/Home/TripSwitcherSheet.swift` (do prompt 27); `Must/Features/Settings/RegionSheet.swift`, `RegionPicker.swift`, `OfflineMapsView.swift`; `Must/Services/Areas/`; `Must/DesignSystem/V8/V8TripTheme.swift`; `Must/Features/Pocket/`; `Must/Features/SOS/`; `Must/Solver/`; `data/board.schema.json`, `data/map-packs.json`.

## 6. Premissas
Cache primeiro; offline é normal (o fluxo inteiro funciona sem rede, menos busca de destino e câmbio, que caem em "digite à mão"/último câmbio); Modo de Pouco Dados: o passo 8 não baixa sozinho; só campos usados; nada de conta nem backend; tudo em pt-BR; nada em japonês na interface (um país como Japão mostra "Japão"). A cor da capa não muda tinta, papel e laranja.

## 7. Testes
`TripRegistryTests` (semeia bh/jp/it com os mesmos nomes de arquivo; criar/arquivar/apagar não toca nas outras), `TripMigrationTests` (container antigo abre igual), `CountryProfileTests` (JP/BR/IT iguais ao comportamento atual; país sem perfil usa o genérico), `NewTripModelTests` (noites somam os dias; datas opcionais; passo pulado não quebra), `BoardCodecTests` (arquivo antigo com `region` e novo com `tripId`), `RegionAutoTests` (regra do GPS com várias viagens).

## Verificar
- F0: nada muda na tela; abrir BH, Japão e Roma e conferir que os dados estão lá.
- Criar a viagem de Portugal pelo fluxo de `NovaViagem1…9` comparando com os PNGs; a capa final bate com `NovaViagem9.png`; modo avião no meio do fluxo não trava.
- "Minhas viagens" lista as quatro; trocar entre elas mantém os dados de cada uma; arquivar some da lista e Apagar remove só o `.store` dela.
- Suíte verde; `qa-screens.sh` com `trocar-viagem` e `novaviagem1…9`.
