Leia `CLAUDE.md` e `prompts/00-leia-primeiro.md`. Vamos criar o projeto iOS do **Must**.

## Entregar
1. Projeto Xcode `Must` (SwiftUI, Swift 6, iOS 26.0 mínimo, iPhone only, retrato). Bundle id `dev.viniso.must` (troque se eu já tiver outro). Use `xcodegen` com um `project.yml` commitado se estiver disponível (`brew install xcodegen`); senão gere o `.xcodeproj` direto. Dois targets: `Must` (app) e `MustWidgets` (Widget Extension com Live Activity habilitada — `NSSupportsLiveActivities = YES` no Info.plist do app). App Group `group.dev.viniso.must` compartilhado entre os dois.
2. Estrutura de pastas conforme `CLAUDE.md` (App, DesignSystem, Models, Data, Services, Solver, Features, Widgets) com um arquivo placeholder em cada.
3. Fontes no bundle: baixe as famílias OFL **Archivo** (variable, Google Fonts), **Instrument Serif** (Regular + Italic), **Geist Mono** (Vercel, GitHub `vercel/geist-font`) e **Zen Kaku Gothic New** (Medium + Bold). Registre em `UIAppFonts`. Crie `DesignSystem/Fonts.swift` com `Font.must.title`, `.listName`, `.place`, `.body`, `.meta`, `.serif`, `.mono`, `.micro`, `.kanji` nos tamanhos do `CLAUDE.md`. Se o download não funcionar na sua rede, deixe os arquivos listados num `Fonts/README.md` e um fallback pro sistema (`.rounded` não; use `.default`) — eu baixo.
4. `Secrets.example.plist` com `GOOGLE_PLACES_KEY`, `FLICKR_KEY`, `ANTHROPIC_KEY` vazios; `Secrets.plist` no `.gitignore`; `Services/Secrets.swift` que lê o plist e devolve `nil` sem crashar se faltar.
5. Capacidades/Info.plist: `NSLocationWhenInUseUsageDescription` ("Pra mostrar o que está aberto perto de você"), `NSCameraUsageDescription` não precisa. Background modes: nenhum. Suporte a abrir URLs compartilhadas: adicione um **Share Extension** mínimo? Não — em vez disso registre o app pra receber URLs via `onOpenURL` com scheme `must://add?url=…` e deixe o Share Sheet pra depois (prompt 04 faz "colar link").
6. `git init`, `.gitignore` (Xcode, DerivedData, Secrets.plist, `*.store`), primeiro commit.
7. `App/MustApp.swift` com uma `ContentView` que mostra "Must" em Archivo 30/600 sobre fundo branco e o selo 済 em círculo verde — só pra validar fontes.

## Verificar
- `xcodebuild -scheme Must -destination 'generic/platform=iOS' build` passa.
- Rodando no iPhone, aparece "Must" em Archivo e o 済 em Zen Kaku (não em fallback do sistema).
