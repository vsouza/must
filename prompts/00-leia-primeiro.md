# Como usar este kit com o Claude Code

1. Crie uma pasta vazia (ex.: `~/Code/must`), copie `CLAUDE.md`, `design/`, `data/` e `prompts/` pra dentro dela e abra o Claude Code ali (`claude`).
2. Rode os prompts em ordem, um por vez: abra o arquivo e cole o conteúdo como mensagem. Cada prompt termina com um bloco **Verificar** — só passe pro próximo quando ele estiver verde.
3. O Claude Code cria o projeto Xcode via `xcodegen` ou direto; depois abra `Must.xcodeproj`, selecione seu iPhone e rode (⌘R). Pra rodar no aparelho sem Apple Developer Program: Xcode → Settings → Accounts → seu Apple ID (Personal Team); no iPhone, Ajustes → Geral → VPN e Gerenciamento de Dispositivo → confiar no desenvolvedor. Build gratuito expira em 7 dias; Live Activity e widgets funcionam, push não (não usamos).
4. Antes de rodar o prompt 07, crie `Secrets.plist` com as chaves (modelo em `Secrets.example.plist`, gerado no prompt 01).
5. O primeiro alvo é **Belo Horizonte**. Só troque pra Japão (menu escondido em Ajustes, 5 toques na versão) quando o fluxo inteiro rodar em BH com GPS real.

Ordem: 01 projeto → 02 design system → 03 dados e região → 04 musts e listas → 05 dia e solver → 06 mapa → 07 serviços → 08 assistente → 09 viagem, ajustes, importar, widgets → 10 QA no iPhone.

Dica: se o Claude Code se perder numa tela, mande ele reler o PNG correspondente em `design/screens/` e o HTML (os valores de espaçamento, tamanhos e cores estão lá literalmente).
