#if DEBUG
import SwiftUI

/// Vitrine do design system v8 (só DEBUG; `-gallery` ou toque longo na raiz). Mostra a identidade de
/// `design/v8/screens/Identidade.png`: três cores, três vozes, três texturas e os componentes v8.
/// `-gallerySection <id>` rola até a seção (colors, type, textures, nav, tickets, rows, buttons, stamps, legacy, icons).
struct Gallery: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab: MustTab = .hoje
    @State private var toggleOn = true
    @State private var toggleOff = false
    @State private var filter = "Perto"

    var body: some View {
        ZStack(alignment: .bottom) {
            V8.paper.ignoresSafeArea()
            Rings(color: V8.ink, count: 2, diameter: 520, opacity: 0.35, offset: CGSize(width: 150, height: -300))
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 36) {
                        header
                        colors.id("colors")
                        typography.id("type")
                        textures.id("textures")
                        nav.id("nav")
                        tickets.id("tickets")
                        rows.id("rows")
                        buttons.id("buttons")
                        stamps.id("stamps")
                        legacy.id("legacy")
                        icons.id("icons")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
                .onAppear {
                    if let id = UserDefaults.standard.string(forKey: "gallerySection") {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }

            V8NavBar(active: tab, onSelect: { tab = $0 })
                .padding(.bottom, 8)
        }
        .foregroundStyle(V8.ink)
    }

    // MARK: Seções

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Button { dismiss() } label: {
                    V8Glyph(.back).frame(width: 18, height: 18)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(V8.ink, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voltar")
                Spacer()
                SpecLabel("Design system\nv8 · guia de bolso").multilineTextAlignment(.trailing)
            }
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text("M").font(V8Font.numeral(96)).foregroundStyle(V8.orange).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Must").font(V8Font.display(34))
                    SpecLabel("Guia de bolso · v8")
                }
            }
        }
    }

    private var colors: some View {
        section("Fixo · a identidade") {
            HStack(spacing: 10) {
                swatch("Tinta", V8.Hex.ink, fg: V8.white)
                swatch("Papel", V8.Hex.paper, fg: V8.ink, border: true)
                swatch("Laranja", V8.Hex.orange, fg: V8.ink)
            }
            HStack(spacing: 10) {
                swatch("Laranja texto", V8.Hex.orangeDeep, fg: V8.white)
                swatch("Cinza", V8.Hex.mute, fg: V8.white)
                swatch("Grafite", V8.Hex.graphite, fg: V8.white)
            }
            Text("Varia com o lugar · só a capa, a Boa noite e o anel do selo")
                .font(V8Font.mono(10)).textCase(.uppercase).tracking(0.8).foregroundStyle(V8.orangeDeep)
            HStack(spacing: 10) {
                ForEach([("Japão", TripTheme.japan, "3"), ("Brasil", TripTheme.brazil, "7"), ("Itália", TripTheme.italy, "2"),
                         ("Sem viagem", TripTheme.neutral, "1")], id: \.0) { name, theme, n in
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack(alignment: .bottomTrailing) {
                            RoundedRectangle(cornerRadius: 14).fill(theme.cover)
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(V8.ink.opacity(theme.hasTrip ? 0 : 0.15)))
                            Text(n).font(V8Font.numeral(44)).foregroundStyle(theme.coverInk).offset(x: -6, y: 8)
                            theme.flag.padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .frame(height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        Text(name).font(V8Font.text(12, weight: .bold)).lineLimit(1)
                    }
                }
            }
        }
    }

    private var typography: some View {
        section("Tipografia · três vozes") {
            Text("14:35").font(V8Font.numeral(96)).tracking(-5.8).accessibilityHidden(true)
            caption("Bricolage Grotesque · 800 · largura 78")
            Divider()
            Text("Hoje é Shinjuku").font(V8Font.display(40)).tracking(-1.2)
            caption("Bricolage Grotesque · 700 · largura 92")
            HStack(spacing: 18) {
                Text("wdth 100").font(V8Font.display(26, width: 100))
                Text("wdth 92").font(V8Font.display(26, width: 92))
                Text("wdth 78").font(V8Font.display(26, width: 78))
            }
            Divider()
            Text("Tsukemen de fila: compre o ticket na máquina antes de entrar na fila. Só cash.")
                .font(V8Font.text(17))
            caption("Schibsted Grotesk · 400–700 · números tabulares")
            HStack(spacing: 12) {
                ForEach([Font.Weight.regular, .medium, .semibold, .bold], id: \.self) { w in
                    Text("¥ 4.250").font(V8Font.text(15, weight: w))
                }
            }
            Divider()
            Text("SÁB · 15 NOV · DIA 3 DE 14 · 18° SOL · ¥ 4.250").font(V8Font.mono(12)).tracking(1.2)
            caption("Martian Mono · 500–600 · caixa alta")
        }
    }

    private var textures: some View {
        section("Texturas · só três") {
            ZStack(alignment: .topLeading) {
                V8.ink
                Rings(color: V8.white, count: 2, diameter: 220, opacity: 0.5, offset: CGSize(width: -60, height: -110))
                SpecLabel("1 · arcos\n1 px · 25–55 %", color: V8.white).padding(14)
                SpecLabel("3 · ficha técnica\nnos cantos", color: V8.white)
                    .multilineTextAlignment(.trailing)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                SpecLabel("2 · numeral que sangra", color: V8.orange)
                    .padding(14)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                BigNumeral("2", size: 150, color: V8.orange, alignment: .trailing)
                    .offset(x: 6, y: 52)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            InkBand {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fuunji").font(V8Font.display(44))
                    Text("mostre ao atendente · tsukemen desde 2007").font(V8Font.text(14)).foregroundStyle(V8.muteDark)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private var nav: some View {
        section("Barra · 4 abas + adicionar") {
            ForEach(MustTab.allCases) { t in
                V8NavBar(active: t)
            }
            HStack(spacing: 8) {
                ForEach(["Perto", "Abertos", "Ramen", "Sushi"], id: \.self) { f in
                    Button { filter = f } label: { V8Pill(f, active: filter == f) }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                V8Pill("A pé · 9 min", active: true, onInk: true)
                V8Pill("Marunouchi · 6 min", onInk: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(V8.ink, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var tickets: some View {
        section("Bilhetes · Próximos") {
            VStack(spacing: 14) {
                ticket(.orange, tag: "Reserva · hoje", right: "Naka-Meguro", time: "19:00", title: "Udatsu Sushi · omakase",
                       meta: "2 pessoas · ¥ 22.000 · saia de Shinjuku 18:25")
                ticket(.paper, tag: "Ingresso · dom 16", right: "QR offline", time: "14:00", title: "teamLab Borderless",
                       meta: "Azabudai Hills · entrada 14:00–14:30")
                ticket(.ink, tag: "Trem · ter 17", right: "JR Pass", time: "09:12", title: "Shinkansen Nozomi 219",
                       meta: "carro 7 · assentos 12A–12B")
            }
            .padding(12)
            .background(V8.ink, in: RoundedRectangle(cornerRadius: 26))
        }
    }

    private var rows: some View {
        section("Lista · índice") {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("Eat").font(V8Font.display(48))
                Text("23").font(V8Font.numeral(64)).foregroundStyle(V8.orange)
                SpecLabel("por bairro")
            }
            VStack(spacing: 0) {
                IndexRow(index: "1", title: "Fuunji", meta: "tsukemen · fila ~20 min · ¥ 1.250", state: .now, trailing: "650 m")
                IndexRow(index: "2", title: "Omoide Yokocho", meta: "yakitori · vielas · ¥ 2.000", state: .open, trailing: "900 m")
                IndexRow(index: "3", title: "Tsunahachi", meta: "tempura desde 1923", state: .opensAt("17h"), trailing: "1,1 km")
                IndexRow(index: "4", title: "Nakajima", meta: "sardinha · almoço ¥ 900", state: .done, trailing: "1,3 km")
                IndexRow(index: "5", title: "Udatsu Sushi", meta: "omakase", state: .reservation("19:00"))
            }
        }
    }

    private var buttons: some View {
        section("Botões") {
            V8Button("Ir agora · 9 min", .orange, icon: .avancar) {}
            V8Button("Ver o dia", .ink) {}
            V8Button("Feito", .line) {}
            HStack(spacing: 10) {
                V8Button("Apple Maps", .line) {}
                V8Button("Cheguei", .orange) {}
            }
            .padding(12)
            .foregroundStyle(V8.white)
            .background(V8.ink, in: RoundedRectangle(cornerRadius: 26))
            Toggle("Micro-paradas", isOn: $toggleOn).toggleStyle(.must).font(V8Font.text(15))
            Toggle("Compras na volta", isOn: $toggleOff).toggleStyle(.must).font(V8Font.text(15))
        }
    }

    private var stamps: some View {
        section("Selos · sigla latina, anel na cor do lugar") {
            HStack(spacing: 18) {
                StationStamp("SJK", sub: "Shinjuku", size: 78, surface: .paper).environment(\.tripTheme, .japan)
                StationStamp("SAV", sub: "BH · 1897", size: 78, surface: .paper).environment(\.tripTheme, .brazil)
                StationStamp("TRV", sub: "Trastevere", size: 78, surface: .paper).environment(\.tripTheme, .italy)
                StationStamp("UEN", size: 40, surface: .paper, rotation: -6).environment(\.tripTheme, .japan)
            }
            HStack(spacing: 18) {
                StationStamp("SBY", sub: "Shibuya", size: 78).environment(\.tripTheme, .japan)
                StationStamp("新宿", sub: "Shinjuku", size: 78, surface: .paper) // kanji nunca aparece: vira sigla
                LineChip(code: "JY", name: "Yamanote · 6 min", color: 0x80C241)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(V8.photo, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    /// Componentes v5–v7 que telas antigas ainda usam, já redirecionados pra identidade v8.
    private var legacy: some View {
        section("v5–v7 redirecionados") {
            HStack(spacing: 8) {
                Pill("livre")
                Pill("ligado", isOn: true)
                Pill("ação", style: .green)
                Tag("aberto", dot: V8.orange)
            }
            PrimaryButton("Aceitar o dia", icon: .ok) {}
            GhostButton("Outra proposta", icon: .outraProposta) {}
            HStack(spacing: 12) {
                KanjiSeal(done: true)
                KanjiSeal(done: true, look: .soft)
                KanjiSeal(done: false, number: 3)
                IconButton(.voltar) {}
                IconButton(.mapa, style: .dark) {}
                Micro("must eat · tóquio")
            }
            Text("Título v5 em Bricolage").mustTitle()
            Text("Corpo v5 em Schibsted · meta 13").mustBody()
            Text("09:12 · ¥ 1.250").mustMono()
        }
    }

    private var icons: some View {
        section("Ícones") {
            HStack(spacing: 12) {
                ForEach([V8Glyph.Kind.clock, .map, .lines, .briefcase, .plus, .arrow, .check, .close, .back, .wallet, .sparkle],
                        id: \.self) { k in
                    V8Glyph(k).frame(width: 20, height: 20)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 14) {
                ForEach(MustIcon.allCases) { MustIconView($0, size: 22) }
            }
        }
    }

    // MARK: Peças

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased()).font(V8Font.mono(10)).tracking(0.8).foregroundStyle(V8.orangeDeep)
            content()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(V8Font.text(13, weight: .semibold)).foregroundStyle(V8.mute)
    }

    private func swatch(_ name: String, _ hex: UInt32, fg: Color, border: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 14).fill(Color(hex: hex))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(V8.ink.opacity(border ? 0.15 : 0)))
                .overlay(alignment: .bottomLeading) {
                    Text(String(format: "#%06X", hex)).font(V8Font.mono(9)).foregroundStyle(fg).padding(9)
                }
                .frame(height: 64)
            Text(name).font(V8Font.text(13, weight: .bold))
        }
        .frame(maxWidth: .infinity)
    }

    private func ticket(_ tone: TicketCard<AnyView, AnyView>.Tone, tag: String, right: String, time: String, title: String,
                        meta: String) -> some View {
        let ink: Color = tone == .ink ? V8.white : V8.ink
        return TicketCard(tone: tone) {
            AnyView(VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(tag.uppercased()).font(V8Font.mono(10, weight: .semibold)).tracking(0.8)
                        .foregroundStyle(V8.white)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(V8.ink, in: RoundedRectangle(cornerRadius: 6))
                    Spacer()
                    Text(right.uppercased()).font(V8Font.mono(10)).tracking(0.8).foregroundStyle(ink.opacity(0.7))
                }
                Text(time).font(V8Font.numeral(44)).tracking(-2)
            })
        } bottom: {
            AnyView(VStack(alignment: .leading, spacing: 4) {
                Text(title).font(V8Font.text(17, weight: .bold))
                Text(meta).font(V8Font.text(13)).foregroundStyle(ink.opacity(0.7))
            })
        }
    }
}

#Preview {
    Gallery()
}
#endif
