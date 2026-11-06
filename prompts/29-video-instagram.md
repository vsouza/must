# Prompt 29 · Vídeo do Instagram → lugares, tudo no aparelho (05/11/2026)

Pedido do Vinicius: "Precisamos conseguir extrair do vídeo do Instagram o conteúdo. Premissa do app." Exemplo: um reel compartilhado por link (`instagram.com/reel/…`).

## O que dá e o que não dá
- **Só com o link**, o app consegue no máximo a legenda (og:description da página pública, best-effort; o Instagram costuma bloquear sem login). **Baixar o vídeo a partir do link exige scraping** (endpoints não oficiais) — proibido no projeto e nos termos do Instagram, e quebra toda semana. A API oficial da Meta (oEmbed) não entrega vídeo nem legenda de reels de terceiros.
- **Com o vídeo no aparelho**, dá pra ler tudo: o que é falado, o texto escrito na tela (nome do lugar, endereço, preço, "salva esse") e a legenda. É isso que este prompt faz, 100 % no aparelho.

## 1. Como o vídeo chega
1. **Share Extension (`MustShare`) aceita vídeo** (`public.movie`, `.mp4`/`.mov`) além de link/texto/PDF. Do Instagram: "Salvar"/baixar quando o autor permite; senão, **gravação de tela** do reel (Central de Controle) e "Compartilhar → Must" a partir de Fotos.
2. **No app**, na aba Link do Quero… (e no Adicionar): quando chega um link do Instagram/TikTok e a legenda vem vazia ou fraca, mostrar o cartão **"Ler o vídeo"** com o passo a passo em 3 linhas (gravar a tela por 10–20 s → voltar pro Must → tocar "Escolher a gravação") e um seletor (`PhotosPicker`, filtro vídeos, sem pedir acesso à biblioteca inteira) que já sugere a gravação mais recente.
3. O link original fica guardado junto (`source.url`), e a legenda, se veio, também entra na leitura.

## 2. Leitura no aparelho (`Must/Services/Ingest/Video/`)
- `VideoReader` (actor, fora do main, cancelável, com progresso):
  - **Fala → texto**: `SpeechAnalyzer` + `SpeechTranscriber` (iOS 26) no aparelho, idioma pela região/língua detectada (pt-BR, en, ja, it); o modelo de fala é baixado pelo `AssetInventory` **só no Wi-Fi** (no celular, pergunta). Sem modelo: `SFSpeechRecognizer` com `requiresOnDeviceRecognition`. Vídeo sem fala: pula.
  - **Texto na tela → OCR**: amostrar 1 quadro/s (no máx. 90 quadros; `AVAssetImageGenerator`), Vision `RecognizeTextRequest` (pt, en, ja, it), juntar linhas repetidas entre quadros, guardar o instante.
  - **Junta** legenda + transcrição + OCR num texto único com marcas de origem ("[tela 00:04] Udatsu Sushi", "[fala 00:07] …").
- Esse texto vai pro **extrator que já existe** (`AIPlaceExtractor`/`PlaceExtractor` com Foundation Models; fallback na nuvem só Haiku `claude-haiku-5-5`, effort low, sem thinking, e só se ligado em Ajustes) → candidatos → resolve no Places (Text Search, campos mínimos, `ApiBudget`) → a **mesma tela de conferência** do Adicionar (`AddLinkResults`), com cada lugar mostrando de onde veio ("visto na tela 00:04", "falado 00:07").
- Nunca inventa lugar: só o que aparece no vídeo/legenda e o Places confirma.
- Nada sai do aparelho além da busca do Places pelo nome. O vídeo não é guardado depois da leitura (só o link e o texto extraído).

## 3. Premissas
- Leitura de um reel de 30 s em < 15 s num iPhone recente; cancelar a qualquer momento; tela não trava (tudo fora do main).
- Offline: transcrição e OCR funcionam (com o modelo já no aparelho); a busca no Places espera a rede (fila de saída que já existe).
- Modo de Pouco Dados: nada de baixar modelo de fala.

## Testes
- `VideoReaderTests` com 2 vídeos curtos de fixture gerados no teste (texto desenhado em quadros com `AVAssetWriter`; um com fala sintetizada por `AVSpeechSynthesizer` gravada em arquivo): OCR acha o nome; junta repetidos; cancela.
- `VideoIngestTests`: texto juntado → extrator (fake) → candidatos com a origem ("tela"/"fala").
- Share Extension: aceita `public.movie`.

## Verificar
- Gravar a tela de um reel de comida em BH no simulador (vídeo de fixture), compartilhar pro Must → aparecem os lugares com "visto na tela".
- Link do Instagram sem legenda → cartão "Ler o vídeo" com o passo a passo.
