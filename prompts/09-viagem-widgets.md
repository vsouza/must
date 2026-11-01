Leia `CLAUDE.md` e as telas `Viagem.png`, `Reservas.png`, `Widgets.png`.

## Entregar
1. **Viagem** (`Viagem.png`): gasto total da viagem em mono 40 (com ≈ R$ via `fxRate`), média/dia vs meta, botão preto de calendário → Reservas; fileira de dias (verde = feito, preto com anel = hoje, azul claro = outra cidade, cinza = futuro) — toque abre o dia (Hoje daquele dia, se aceito; senão Montar com a data); três stackCards por trecho de cidade ("Tóquio · 13–17 · agora", "Kyoto · 17–20", "Tóquio de novo · 20–24" com o número grande de "ficaram pro fim"); tags de progresso por lista. **Em BH** (sem `trip`): a tela vira "Belo Horizonte" com gasto do mês, dias do mês com 済 nos dias com paradas feitas, e os mesmos cards por semana — sem inventar viagem.
2. **Reservas** (`Reservas.png`): card azul "Próxima", lista cronológica com dia grande em mono, nome, meta (hora, pessoas, nota), tag (hoje / viagem / cidade / dia / tempo / voo). Inclui `reservation` dos lugares **e** "eventos" sem lugar (Shinkansen, voo, "Nara · dia inteiro") — modelo `TripEvent { at, title, kind, note, weatherDependent }`. "+" cria evento. Tocar abre Lugar ou edita o evento.
3. **Live Activity + widgets** (`Widgets.png`), target `MustWidgets`:
   - `NextStopActivity` (ActivityKit): começa quando o dia é aceito e há parada futura; atualiza a cada mudança de parada/ETA (foreground; sem push). Lock screen: "Must · próxima parada", nome + nameLocal, hora de sair em verde mono 22, barra de progresso azul, "350 m · reserva 19:00". Dynamic Island compacta: número da parada em círculo verde + nome + "4 min"; expandida: igual ao lock screen.
   - Widget médio "Hoje": gasto do dia mono 28 + meta + "3 de 5 feitos" + fileira de selos 済/números + bloco azul "Próxima".
   - Widget pequeno "Perto de você": número grande + "musts abertos" + bairro + temperatura (dados do último sync via App Group; sem GPS no widget — usa a última localização salva pelo app).
   - Widget pequeno escuro "Montar o dia": previsão de amanhã + botão (deep link `must://montar?date=`).
   - Timeline a cada 30 min; dados via `UserDefaults(suiteName: App Group)` escritos pelo `SyncCoordinator`.
4. Deep links: `must://hoje`, `must://montar?date=`, `must://lugar/<id>`, `must://add?url=`.

## Verificar
- Aceitar um dia em BH inicia a Live Activity com a 1ª parada; marcar 済 avança pra próxima; no fim do dia encerra.
- Widgets aparecem na galeria com os nomes certos e dados reais após abrir o app uma vez.
