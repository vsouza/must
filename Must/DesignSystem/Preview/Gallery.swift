#if DEBUG
import SwiftUI

/// Vitrine do design system (só DEBUG). Abre com toque longo no 済 da ContentView.
struct Gallery: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab: MustTab = .musts
    @State private var toggleOn = true
    @State private var toggleOff = false
    @State private var selectedPill = "livre"

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.must.bg.ignoresSafeArea()
            BlobBackground(style: .musts)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        header
                        colors.id("colors")
                        typography.id("typography")
                        buttons.id("buttons")
                        pills.id("pills")
                        seals.id("seals")
                        stamps.id("stamps")
                        stackCards.id("stack")
                        tiles.id("tiles")
                        toggles.id("toggles")
                        icons.id("icons")
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
                .onAppear {
                    // `-gallerySection icons` (argumento de lançamento) rola até a seção.
                    if let id = UserDefaults.standard.string(forKey: "gallerySection") {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }

            MustTabBar(selected: $tab)
                .padding(.bottom, 8)
                .overlay(alignment: .topTrailing) {
                    Fab { }
                        .padding(.trailing, 22)
                        .offset(y: -70)
                }
        }
    }

    // MARK: Seções

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                IconButton(.voltar, style: .glass) { dismiss() }
                Spacer()
                Micro("\(MustIcon.allCases.count) ícones · 8 cores")
                Spacer()
                IconButton(.adicionar, style: .dark) { }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Gallery").mustTitle()
                Text("tudo que monta as telas").mustSerif(18).foregroundStyle(Color.must.secondary)
            }
        }
    }

    private var colors: some View {
        section("Cores") {
            let tokens: [(String, Color)] = [
                ("bg", Color.must.bg), ("ink", Color.must.ink), ("secondary", Color.must.secondary),
                ("surface", Color.must.surface), ("surface2", Color.must.surface2), ("line", Color.must.line),
                ("green", Color.must.green), ("greenText", Color.must.greenText),
                ("blue", Color.must.blue), ("blueText", Color.must.blueText),
            ]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                ForEach(tokens, id: \.0) { name, color in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(color)
                            .frame(height: 44)
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.must.line))
                        Text(name).font(.must.mono(9)).foregroundStyle(Color.must.secondary).lineLimit(1)
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(MustColor.allCases) { c in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(c.gradient)
                        .frame(height: 64)
                        .overlay(alignment: .bottomLeading) {
                            Text(c.label).font(.must.archivo(13, .semibold)).foregroundStyle(c.text).padding(10)
                        }
                }
            }
        }
    }

    private var typography: some View {
        section("Tipografia") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Olá, Vinicius!").mustTitle()
                Text("Must eat").mustListName()
                Text("Udatsu Sushi").mustPlace()
                Text("Pedir o uni extra. Sentar no balcão.").mustBody()
                Text("Asakusa · templo cedo, sem fila · ¥0").mustMeta()
                Text("o board, por vontade — não por bairro").mustSerif(19).foregroundStyle(Color.must.secondary)
                Text("19:00 · saia 18:50 · R$ 200").mustMono(13)
                Micro("reserva · âncora do dia")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    MonoNumber("29.410", size: 44)
                    Text("JPY").font(.must.archivo(17, .semibold))
                }
                Text("鮨 うだつ · 中目黒").mustKanji(17).foregroundStyle(Color.must.secondary)
            }
        }
    }

    private var buttons: some View {
        section("Botões") {
            VStack(spacing: 12) {
                PrimaryButton("Montar o dia", icon: .montarAjustar) { }
                PrimaryButton("Ir agora", icon: .rota, style: .dark) { }
                HStack(spacing: 10) {
                    GhostButton("Ajustar", icon: .montarAjustar) { }
                    PrimaryButton("Feito", icon: .feito) { }
                }
                HStack(spacing: 10) {
                    IconButton(.voltar) { }
                    IconButton(.ficaProFim) { }
                    IconButton(.editar) { }
                    IconButton(.adicionar, style: .dark) { }
                    IconButton(.buscar, style: .glass) { }
                    Spacer()
                }
            }
        }
    }

    private var pills: some View {
        section("Pílulas e tags") {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["livre", "compras", "noite", "fotografia", "templos", "descanso"], id: \.self) { kind in
                            Button { selectedPill = kind } label: { Pill(kind, isOn: selectedPill == kind) }
                                .buttonStyle(MustPressStyle())
                        }
                    }
                }
                HStack(spacing: 8) {
                    Pill("Perto", icon: .voceGps)
                    Pill("Abertos", style: .green)
                    Pill("¥¥", isOn: true)
                }
                HStack(spacing: 8) {
                    Tag("Must eat · Sushi", style: .dark)
                    Tag("abre 18:00", dot: Color.must.green)
                    Tag("reserva")
                }
            }
        }
    }

    /// Selo de bairro (D.18) e chip de linha (D.19): sobre papel e sobre foto escurecida.
    private var stamps: some View {
        section("Selos de bairro e linhas") {
            HStack(spacing: 14) {
                StationStamp("新宿", size: 74, ring: StampPalette.onPhotoFill == .clear ? .black : .white, fill: nil)
                StationStamp("SAV", sub: "BH · 1897", size: 74, ring: StampPalette.onPaper, fill: nil)
                StationStamp("上野", size: 44, ring: StampPalette.onPaper, fill: nil, rotation: -6)
                Spacer()
            }
            HStack(spacing: 8) {
                LineChip(code: "JY", name: "Yamanote", color: 0x80C241)
                LineChip(code: "H", name: "Hibiya", color: 0xB5B5AC)
                LineChip(code: "BUS", name: "ônibus", color: 0x7A7F87)
                Spacer()
            }
        }
    }

    private var seals: some View {
        section("Selos e créditos") {
            HStack(spacing: 14) {
                KanjiSeal(done: true)
                KanjiSeal(done: true, look: .soft)
                KanjiSeal(done: false, number: 4)
                KanjiSeal(done: false, number: 5, size: 30)
                KanjiSeal(done: true, size: 44)
                Spacer()
            }
            HStack {
                Credit("foto · Wikimedia CC BY 2.0 · @autor")
                Spacer()
                SheetHandle()
            }
        }
    }

    private var stackCards: some View {
        section("Cards empilhados") {
            ZStack(alignment: .topLeading) {
                stackRow(icon: .relogio, title: "Próxima · Udatsu", subtitle: "19:00 · saia 18:50 · 4 min a pé")
                    .frame(height: 118)
                    .stackCard(color: .drink, rotation: -2)
                    .padding(.leading, 78)
                    .padding(.trailing, -40)

                stackRow(icon: .montarAjustar, title: "Montar amanhã", subtitle: "templo cedo, ramen, café · 13° e sol",
                         subtitleColor: Color.must.greenTextSoft)
                    .frame(height: 118)
                    .stackCard(color: .eat, rotation: 1.5)
                    .padding(.leading, 38)
                    .padding(.trailing, -20)
                    .offset(y: 86)

                VStack(alignment: .leading) {
                    HStack(spacing: 14) {
                        iconCircle(.mapa)
                        Text("Perto de você").font(.must.archivo(19, .semibold)).foregroundStyle(Color.must.ink)
                    }
                    Spacer()
                    HStack(alignment: .bottom, spacing: 10) {
                        MonoNumber("6", size: 64).foregroundStyle(Color.must.ink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("musts abertos").font(.must.archivo(19, .semibold)).foregroundStyle(Color.must.ink)
                            Text("Savassi · 18:42 · 24°").font(.must.archivo(13))
                        }
                        .padding(.bottom, 6)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 250)
                .stackCard(tint: .sky)
                .offset(y: 172)
            }
            .frame(height: 430, alignment: .top)
            .background(alignment: .bottomTrailing) {
                BlobBackground(style: .custom([
                    Blob(cx: 330, cy: 160, rx: 90, ry: 70, rotation: -18, fill: .green),
                    Blob(cx: 300, cy: 300, rx: 110, ry: 80, rotation: 20, fill: .blue),
                ]))
                .frame(height: 430)
            }
        }
    }

    private var tiles: some View {
        section("Tiles do hub") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                tile(.eat, kanji: "食", icon: .ramen, count: 23, name: "Must eat", subs: "Mineiro 9 · Mercado 4 · 3 feitos",
                     url: URL(string: "https://picsum.photos/seed/must-ramen/400/300"))
                tile(.drink, kanji: "飲", icon: .coquetel, count: 14, name: "Must drink", subs: "café 6 · bar 8", url: nil)
                tile(.coffee, kanji: "喫", icon: .cafe, count: 4, name: "Must kissaten", subs: "0 feitos", url: nil)
                tile(.night, kanji: "夜", icon: .boateNoite, count: 7, name: "Must night", subs: "boates 3 · 1 feito", url: nil)
            }
        }
    }

    private var toggles: some View {
        section("Toggle") {
            VStack(spacing: 14) {
                Toggle("Uma refeição por janela", isOn: $toggleOn)
                Toggle("Reforço na nuvem", isOn: $toggleOff)
            }
            .toggleStyle(.must)
            .font(.must.body)
            .padding(18)
            .card()
        }
    }

    private var icons: some View {
        section("Ícones · \(MustIcon.allCases.count)") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 16) {
                ForEach(MustIcon.allCases) { icon in
                    VStack(spacing: 6) {
                        MustIconView(icon, size: 22)
                            .foregroundStyle(Color.must.ink)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.must.surface))
                        Text(icon.label)
                            .font(.must.archivo(11, .semibold))
                            .foregroundStyle(Color.must.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(icon.fallbackSymbol)
                            .font(.must.mono(8))
                            .foregroundStyle(Color.must.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
        }
    }

    // MARK: Peças

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Micro(title)
            Rectangle().fill(Color.must.line).frame(height: 1)
            content()
        }
    }

    private func iconCircle(_ icon: MustIcon, size: CGFloat = 48) -> some View {
        MustIconView(icon, size: 20)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(0.55)))
    }

    private func stackRow(icon: MustIcon, title: String, subtitle: String, subtitleColor: Color? = nil) -> some View {
        HStack(spacing: 14) {
            iconCircle(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.must.archivo(19, .semibold)).foregroundStyle(Color.must.ink)
                Text(subtitle).font(.must.archivo(13)).foregroundStyle(subtitleColor ?? Color.must.blueText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 22)
    }

    private func tile(_ color: MustColor, kanji: String, icon: MustIcon, count: Int, name: String, subs: String, url: URL?) -> some View {
        ZStack(alignment: .topLeading) {
            TintedPhoto(url: url, color: color)
            VStack(alignment: .leading, spacing: 0) {
                MustIconView(icon, size: 18)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.55)))
                Spacer(minLength: 0)
                MonoNumber("\(count)", size: 28)
                Text(name).font(.must.archivo(17, .semibold)).lineLimit(1)
                Text(subs).font(.must.archivo(11.5)).opacity(0.8).lineLimit(1)
            }
            .foregroundStyle(color.text)
            .padding(14)
        }
        .overlay(alignment: .topTrailing) {
            Text(kanji).font(.must.kanji(28)).foregroundStyle(color.text).opacity(0.3).padding(.top, 10).padding(.trailing, 14)
        }
        .overlay(alignment: .bottomTrailing) {
            if url != nil { Credit("CC", color: color.text).padding(.trailing, 8).padding(.bottom, 6) }
        }
        .frame(height: 136)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

#Preview {
    Gallery()
}
#endif
