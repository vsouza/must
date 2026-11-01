Leia `CLAUDE.md`. Rodada final no iPhone, em Belo Horizonte, antes de eu começar a usar de verdade.

## Entregar
1. **Checklist executável** `QA.md` na raiz com os cenários abaixo; rode o que der por teste automatizado e me deixe os manuais marcados.
2. Cenários (BH, GPS real):
   - Primeira abertura: seed BH carregado, pedido de localização, Início com "Perto de você" correto.
   - Sincronizar Places em Ajustes: 23 lugares com horário; contador de chamadas coerente.
   - Sábado de manhã: Montar "livre" → Proposta → Trocar o almoço → Aceitar → Hoje → Mapa mostra rota e pinos → "Ir agora" abre Apple Maps → Registrar gasto marca 済 → Live Activity avança.
   - Domingo: Montar "compras" → Feira Hippie entra de manhã.
   - Orçamento R$ 100: Glouton/Trindade não entram; marcando "vale a exceção" e pedindo "jantar bom" no texto, entra fora da meta.
   - Nova lista "kissaten" com foto Flickr + 2 lugares pelo Places → aparece no hub com cor e foto.
   - Adicionar por link: um link do Google Maps e um Reel real (pode falhar a legenda → fluxo de colar texto funciona).
   - Assistente: 3 perguntas das sugestões respondem com dados reais; sem Apple Intelligence o app não quebra.
   - Menu escondido: trocar pra Japão e voltar sem perder gastos de BH; simular data 2026-11-15 10:00 e GPS Naka-Meguro → Início do Japão mostra a reserva do Udatsu como "Próxima".
   - Exportar → apagar app → reinstalar → Importar: tudo volta.
   - Sem rede: app abre, listas e Hoje funcionam, chip "sem dados ao vivo".
   - Consumo: uma tarde com o app aberto no mapa não passa de ~10% de bateria (checar `Energy Log` do Xcode); nenhum `MKDirections` em loop.
3. Correções do que falhar, com commits separados.
4. `README.md` curto na raiz: o que é, como rodar, como pôr as chaves, como trocar de região, como importar o board do Japão antes da viagem.

## Verificar
- Todos os itens da checklist marcados ou com nota do que falta e por quê.
