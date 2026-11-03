import SwiftUI

// MARK: - Feedback de toque

/// Encolhe um pouco ao pressionar. Usado por todos os botões do Must.
struct MustPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Pill

/// Pílula 13/600, padding 9×13. `isOn` vira escura.
struct Pill: View {
    enum Style: Sendable { case `default`, dark, green }

    var text: String
    var isOn: Bool = false
    var style: Style = .default
    var icon: MustIcon?

    init(_ text: String, isOn: Bool = false, style: Style = .default, icon: MustIcon? = nil) {
        self.text = text
        self.isOn = isOn
        self.style = style
        self.icon = icon
    }

    private var resolved: Style { isOn ? .dark : style }

    var body: some View {
        HStack(spacing: 6) {
            if let icon { MustIconView(icon, size: 14) }
            Text(text).lineLimit(1)
        }
        .font(.must.archivo(13, .semibold))
        .foregroundStyle(foreground)
        .padding(.vertical, 9)
        .padding(.horizontal, 13)
        .background(background, in: Capsule())
        .contentShape(Capsule())
    }

    private var foreground: Color {
        switch resolved {
        case .default: Color.must.ink
        case .dark: .white
        case .green: Color.must.greenText
        }
    }

    private var background: Color {
        switch resolved {
        case .default: Color.must.surface
        case .dark: Color.must.ink
        case .green: Color.must.green
        }
    }
}

// MARK: - Botões

/// Botão principal 52pt, raio 999, 15/700.
struct PrimaryButton: View {
    enum Style: Sendable { case green, dark }

    var title: String
    var icon: MustIcon?
    var iconTrailing = false
    var style: Style = .green
    var action: () -> Void

    init(_ title: String, icon: MustIcon? = nil, iconTrailing: Bool = false, style: Style = .green, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.iconTrailing = iconTrailing
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let icon, !iconTrailing { MustIconView(icon, size: 18) }
                Text(title)
                if let icon, iconTrailing { MustIconView(icon, size: 18) }
            }
            .font(.must.archivo(15, .bold))
            .foregroundStyle(style == .green ? Color.must.greenText : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(style == .green ? Color.must.green : Color.must.ink, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(MustPressStyle())
    }
}

/// Botão fantasma 48pt: fundo branco, borda #E4E6EA, 14/600.
struct GhostButton: View {
    var title: String
    var icon: MustIcon?
    var action: () -> Void

    init(_ title: String, icon: MustIcon? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { MustIconView(icon, size: 17) }
                Text(title)
            }
            .font(.must.archivo(14, .semibold))
            .foregroundStyle(Color.must.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.must.lineStrong, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(MustPressStyle())
    }
}

/// Botão redondo de ícone, 40pt.
struct IconButton: View {
    enum Style: Sendable { case gray, dark, glass }

    var symbol: MustIcon
    var style: Style = .gray
    var size: CGFloat = 40
    var label: String?
    var action: () -> Void

    init(_ symbol: MustIcon, style: Style = .gray, size: CGFloat = 40, label: String? = nil, action: @escaping () -> Void) {
        self.symbol = symbol
        self.style = style
        self.size = size
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            MustIconView(symbol, size: size * 0.45)
                .foregroundStyle(style == .dark ? .white : Color.must.ink)
                .frame(width: size, height: size)
                .background { background }
                .contentShape(Circle())
        }
        .buttonStyle(MustPressStyle())
        .accessibilityLabel(label ?? symbol.label)
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .gray: Circle().fill(Color.must.surface)
        case .dark: Circle().fill(Color.must.ink)
        case .glass: Color.clear.glass(cornerRadius: size / 2)
        }
    }
}

/// FAB preto 54pt (Assistente).
struct Fab: View {
    var symbol: MustIcon = .assistente
    var action: () -> Void

    init(_ symbol: MustIcon = .assistente, action: @escaping () -> Void) {
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            MustIconView(symbol, size: 22)
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Color.must.ink))
                .shadow(color: Color(hex: 0x121316, opacity: 0.25), radius: 15, x: 0, y: 12)
        }
        .buttonStyle(MustPressStyle())
        .accessibilityLabel(symbol.label)
    }
}

// MARK: - Rótulos

/// Tag 12pt sobre `surface`, com ponto colorido opcional.
struct Tag: View {
    var text: String
    var dot: Color?
    var style: Pill.Style = .default

    init(_ text: String, dot: Color? = nil, style: Pill.Style = .default) {
        self.text = text
        self.dot = dot
        self.style = style
    }

    var body: some View {
        HStack(spacing: 5) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            Text(text).lineLimit(1)
        }
        .font(.must.archivo(12))
        .foregroundStyle(style == .dark ? .white : (style == .green ? Color.must.greenText : Color.must.ink))
        .padding(.vertical, 5)
        .padding(.horizontal, 9)
        .background(style == .dark ? Color.must.ink : (style == .green ? Color.must.green : Color.must.surface), in: Capsule())
    }
}

/// Mono 11 caixa alta, tracking .1em.
struct Micro: View {
    var text: String
    var color: Color = Color.must.secondary

    init(_ text: String, color: Color = Color.must.secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.must.micro)
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(color)
    }
}

/// Número grande em Geist Mono (tabular), 600, tracking −.03em.
struct MonoNumber: View {
    var value: String
    var size: CGFloat = 44

    init(_ value: String, size: CGFloat = 44) {
        self.value = value
        self.size = size
    }

    var body: some View {
        Text(value)
            .font(.must.mono(size, .semibold))
            .tracking(-0.03 * size)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

// MARK: - Selo 済

/// 済 em círculo verde (feito) ou número em círculo preto (por fazer).
struct KanjiSeal: View {
    enum Look: Sendable {
        /// Verde forte (selo do app).
        case strong
        /// Verde claro, como as paradas feitas do Hoje.
        case soft
    }

    var done: Bool
    var number: Int?
    var size: CGFloat = 30
    var look: Look = .strong

    init(done: Bool, number: Int? = nil, size: CGFloat = 30, look: Look = .strong) {
        self.done = done
        self.number = number
        self.size = size
        self.look = look
    }

    var body: some View {
        ZStack {
            if done {
                Circle().fill(look == .strong ? Color.must.green : Color(hex: 0xB9F5CF))
                Text("済")
                    .font(.must.kanji(size * 0.5))
                    .foregroundStyle(look == .strong ? Color.must.greenText : Color(hex: 0x22B866))
            } else {
                Circle().fill(Color.must.ink)
                Text(number.map(String.init) ?? "")
                    .font(.must.archivo(size * 0.45, .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(done ? "feito" : "parada \(number ?? 0)")
    }
}

// MARK: - Fotos

/// Chip de crédito "foto · Wikimedia CC BY 2.0 · @autor". Com `url`, abre a página da foto.
struct Credit: View {
    var text: String
    var color: Color = Color.must.ink
    var url: URL?

    init(_ text: String, color: Color = Color.must.ink, url: URL? = nil) {
        self.text = text
        self.color = color
        self.url = url
    }

    var body: some View {
        if let url {
            Link(destination: url) { chip }
        } else {
            chip
        }
    }

    private var chip: some View {
        Text(text)
            .font(.must.mono(9))
            .textCase(.uppercase)
            .tracking(0.54)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 260)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(color)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(Color.white.opacity(0.55), in: Capsule())
    }
}

/// Foto (Wikimedia Commons) com saturação .7 e o gradiente da cor por cima a 82%.
/// Sem URL ou enquanto carrega: só o gradiente.
struct TintedPhoto: View {
    var url: URL?
    var color: MustColor
    var tintOpacity: Double = 0.82
    @State private var image: UIImage?

    init(url: URL?, color: MustColor, tintOpacity: Double = 0.82) {
        self.url = url
        self.color = color
        self.tintOpacity = tintOpacity
    }

    var body: some View {
        // A foto fica num overlay pra nunca mudar o tamanho proposto (scaledToFill passaria da largura).
        color.gradient
            .overlay {
                if let url {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill().saturation(0.7)
                    }
                    color.gradient.opacity(tintOpacity)
                }
            }
            .clipped()
            // Cache primeiro (prompt 18 · A.4): sem imagem e sem rede, fica o gradiente, sem spinner.
            .task(id: url) {
                guard let url else { image = nil; return }
                image = await PhotoLoader.load(url)
            }
    }
}

/// Foto de fundo: memória → disco (qualquer idade, na hora) → rede (só sem cópia ou com cópia de mais de 30 dias).
/// Nunca espera a rede pra mostrar uma foto que já está no aparelho. Sem rede, a chamada falha na hora (`HTTP`).
@MainActor
enum PhotoLoader {
    static let memory = NSCache<NSURL, UIImage>()
    static let freshFor: TimeInterval = 30 * 24 * 3600

    static func load(_ url: URL) async -> UIImage? {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        let key = "photo|\(url.absoluteString)"
        if let saved = await DiskCache.shared.stale(key), let image = UIImage(data: saved) {
            memory.setObject(image, forKey: url as NSURL)
            if await DiskCache.shared.isFresh(key, maxAge: freshFor) == false {
                Task { _ = await fetch(url, key: key) }   // velha: troca na próxima vez, sem atrasar a tela
            }
            return image
        }
        guard let data = await fetch(url, key: key), let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: url as NSURL)
        return image
    }

    /// Pré-download do dia (prompt 18 · A.5): garante a foto no disco. Não gasta dado do Modo de Pouco Dados
    /// (`HTTP(kind: .prefetch)`). `true` se já estava lá ou baixou.
    static func prefetch(_ url: URL) async -> Bool {
        let key = "photo|\(url.absoluteString)"
        if await DiskCache.shared.exists(key) { return true }
        guard let data = try? await HTTP(kind: .prefetch).get(url, headers: ["User-Agent": CommonsPhotoService.userAgent], service: "foto"),
              UIImage(data: data) != nil else { return false }
        await DiskCache.shared.store(data, for: key)
        return true
    }

    private static func fetch(_ url: URL, key: String) async -> Data? {
        guard let data = try? await HTTP().get(url, headers: ["User-Agent": CommonsPhotoService.userAgent], service: "foto") else {
            return nil
        }
        await DiskCache.shared.store(data, for: key)
        return data
    }
}

// MARK: - Navegação

enum MustTab: String, CaseIterable, Identifiable, Sendable {
    case inicio, hoje, mapa, musts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inicio: "Início"
        case .hoje: "Hoje"
        case .mapa: "Mapa"
        case .musts: "Musts"
        }
    }

    var icon: MustIcon {
        switch self {
        case .inicio: .inicio
        case .hoje: .hoje
        case .mapa: .mapa
        case .musts: .mustsLista
        }
    }
}

/// Tab bar flutuante: pílula branca 62pt com sombra, 22pt das bordas.
struct MustTabBar: View {
    @Binding var selected: MustTab
    @Environment(\.tripTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MustTab.allCases) { tab in
                Button {
                    selected = tab
                } label: {
                    VStack(spacing: 3) {
                        MustIconView(tab.icon, size: 22)
                        Text(tab.title)
                            .font(.must.archivo(11, selected == tab ? .semibold : .regular))
                        // Ponto da aba ativa na cor do país (prompt 20); sem tema, o verde do app. Reserva o espaço nas outras.
                        Circle()
                            .fill(theme.tripColor)
                            .frame(width: 4, height: 4)
                            .opacity(selected == tab ? 1 : 0)
                    }
                    .foregroundStyle(selected == tab ? Color.must.ink : Color.must.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 62)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().strokeBorder(Color.must.line, lineWidth: 1))
        .shadow(color: Color(hex: 0x121316, opacity: 0.14), radius: 18, x: 0, y: 12)
        .padding(.horizontal, 22)
    }
}

/// Alça de sheet.
struct SheetHandle: View {
    var body: some View {
        Capsule()
            .fill(Color(hex: 0xD9DCE1))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .accessibilityHidden(true)
    }
}

// MARK: - Toggle

/// Toggle 46×28, verde quando ligado.
struct MustToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Capsule()
                .fill(configuration.isOn ? Color.must.green : Color(hex: 0xDDE0E5))
                .frame(width: 46, height: 28)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: Color(hex: 0x121316, opacity: 0.15), radius: 2, x: 0, y: 1)
                        .frame(width: 22, height: 22)
                        .padding(3)
                }
                .animation(.snappy(duration: 0.2), value: configuration.isOn)
                .onTapGesture { configuration.isOn.toggle() }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(configuration.isOn ? "ligado" : "desligado")
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

extension ToggleStyle where Self == MustToggleStyle {
    static var must: MustToggleStyle { MustToggleStyle() }
}
