import SwiftUI

// Componentes v5–v7 mantidos pras telas que ainda não foram redesenhadas, **redesenhados na identidade v8**
// (tinta, papel, laranja; Schibsted/Martian/Bricolage; sem degradê, sem vidro, sem sombra colorida).
// Componentes novos da v8 ficam em `V8/V8Components.swift`.

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

/// Pílula 13/600, 34 pt, contorno de 1 pt (`.pill` do `v8.css`). `isOn` = tinta; `.green` (v5) = laranja.
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
        .font(V8Font.text(13, weight: .semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 13)
        .frame(minHeight: 34)
        .background(background, in: Capsule())
        .overlay(Capsule().strokeBorder(resolved == .default ? V8.ink : Color.clear, lineWidth: 1))
        .contentShape(Capsule())
    }

    private var foreground: Color {
        switch resolved {
        case .default: V8.ink
        case .dark: V8.white
        case .green: V8.ink
        }
    }

    private var background: Color {
        switch resolved {
        case .default: Color.clear
        case .dark: V8.ink
        case .green: V8.orange
        }
    }
}

// MARK: - Botões

/// Botão principal 56 pt, cápsula, 16/700 (`.btn` do `v8.css`). `.green` (v5) = laranja (ação); `.dark` = tinta.
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
            HStack(spacing: 10) {
                if let icon, !iconTrailing { MustIconView(icon, size: 18) }
                Text(title).lineLimit(1)
                if let icon, iconTrailing { MustIconView(icon, size: 18) }
            }
            .font(V8Font.text(16, weight: .bold))
            .foregroundStyle(style == .green ? V8.ink : V8.white)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(style == .green ? V8.orange : V8.ink, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(MustPressStyle())
    }
}

/// Botão fantasma 48 pt: só contorno de 1,5 pt em tinta (`.btn.line`), 15/600.
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
                Text(title).lineLimit(1)
            }
            .font(V8Font.text(15, weight: .semibold))
            .foregroundStyle(V8.ink)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .overlay(Capsule().strokeBorder(V8.ink, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(MustPressStyle())
    }
}

/// Botão redondo de ícone, 44 pt por padrão no design (`.ic`): `.gray` = contorno, `.dark` = tinta, `.glass` = papel.
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
                .foregroundStyle(style == .dark ? V8.white : V8.ink)
                .frame(width: size, height: size)
                .background { background }
                .contentShape(Circle())
        }
        .buttonStyle(MustPressStyle())
        .accessibilityLabel(label ?? symbol.label)
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .gray: Circle().strokeBorder(V8.ink, lineWidth: 1)
        case .dark: Circle().fill(V8.ink)
        case .glass: Circle().fill(V8.paper)
        }
    }
}

/// Botão redondo preto 54 pt (Assistente).
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
                .foregroundStyle(V8.white)
                .frame(width: 54, height: 54)
                .background(Circle().fill(V8.ink))
                .shadow(color: V8.ink.opacity(0.28), radius: 22, x: 0, y: 18)
        }
        .buttonStyle(MustPressStyle())
        .accessibilityLabel(symbol.label)
    }
}

// MARK: - Rótulos

/// Etiqueta (`.tag` do `v8.css`): Martian Mono 9/600 caixa alta, cantos de 6 pt, com ponto opcional.
/// `.default` = osso, `.dark` = tinta, `.green` (v5) = laranja.
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
            if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
            Text(text.uppercased()).lineLimit(1)
        }
        .font(V8Font.mono(9, weight: .semibold))
        .tracking(0.72)
        .foregroundStyle(style == .dark ? V8.white : V8.ink)
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(style == .dark ? V8.ink : (style == .green ? V8.orange : V8.bone),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Micro-rótulo: Martian Mono 10/500 caixa alta, tracking .08em, secundário (`.mono` do `v8.css`).
struct Micro: View {
    var text: String
    var color: Color = V8.mute

    init(_ text: String, color: Color = V8.mute) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.must.micro)
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(color)
    }
}

/// Número grande (horas, ¥/R$): Martian Mono 600 tabular, tracking −.03em.
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

// MARK: - Selo de feito

/// Feito (círculo laranja com ✓) ou número em círculo preto (por fazer). Era o 済 da v5 — sem japonês na v8.
struct KanjiSeal: View {
    enum Look: Sendable {
        /// Laranja (feito em destaque).
        case strong
        /// Osso, como as paradas feitas da Linha (50 %).
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
                Circle().fill(look == .strong ? V8.orange : V8.bone)
                CheckGlyph()
                    .stroke(look == .strong ? V8.ink : V8.mute,
                            style: StrokeStyle(lineWidth: max(1.6, size * 0.08), lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.5, height: size * 0.5)
            } else {
                Circle().fill(V8.ink)
                Text(number.map(String.init) ?? "")
                    .font(V8Font.numeral(size * 0.5))
                    .foregroundStyle(V8.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(done ? "feito" : "parada \(number ?? 0)")
    }
}

/// ✓ em vetor (viewBox 24): o "feito" da v8.
struct CheckGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * s, oy = rect.midY - 12 * s
        var p = Path()
        p.move(to: CGPoint(x: ox + 5 * s, y: oy + 12.5 * s))
        p.addLine(to: CGPoint(x: ox + 10 * s, y: oy + 17.5 * s))
        p.addLine(to: CGPoint(x: ox + 19 * s, y: oy + 7 * s))
        return p
    }
}

// MARK: - Fotos

/// Chip de crédito "foto · Wikimedia CC BY 2.0 · @autor" (`.credit`): Martian Mono 8 caixa alta, branco sobre tinta 55 %.
/// Com `url`, abre a página da foto. `color` (v5) fica na assinatura e é ignorado.
struct Credit: View {
    var text: String
    var color: Color = V8.white
    var url: URL?

    init(_ text: String, color: Color = V8.white, url: URL? = nil) {
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
            .font(V8Font.mono(8))
            .textCase(.uppercase)
            .tracking(0.8)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 260)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(V8.white.opacity(0.85))
            .padding(.vertical, 4)
            .padding(.horizontal, 7)
            .background(V8.ink.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Como as fotos aparecem. v8: foto inteira, em cor cheia, sempre (`vivid`). `classic` (v5) não existe mais;
/// o caso fica pra que `-photoStyle classic` não quebre nada.
enum PhotoStyle: Sendable {
    case vivid, classic

    static let current: PhotoStyle = .vivid
}

/// Foto de um lugar ou lista. v8: a foto inteira, sem saturar nem tingir. Sem URL ou enquanto carrega: placeholder de
/// cor (osso quando há texto por cima — `tintOpacity > 0` —, grafite quando é só a foto).
///
/// Telas v5–v7 escrevem texto **por cima** da foto com a tinta: pra continuarem legíveis até serem redesenhadas, com
/// `tintOpacity > 0` entra uma faixa de papel por baixo do texto (`ramp`). As telas v8 usam `tintOpacity: 0` e põem o
/// texto numa `InkBand` (faixa preta sólida).
struct TintedPhoto: View {
    var url: URL?
    var color: MustColor
    var tintOpacity: Double = 0.82
    /// v5. Ignorado: a foto fica como veio.
    var saturation: Double = 0.7
    /// Onde a faixa de papel começa e fica sólida (0 = topo, 1 = base). Só com `tintOpacity > 0`.
    var ramp: ClosedRange<Double> = 0.32...0.74
    /// Zoom lento (heroes grandes: Lugar).
    var motion = false
    @State private var image: UIImage?

    init(url: URL?, color: MustColor, tintOpacity: Double = 0.82, saturation: Double = 0.7, ramp: ClosedRange<Double> = 0.32...0.74,
         motion: Bool = false) {
        self.url = url
        self.color = color
        self.tintOpacity = tintOpacity
        self.saturation = saturation
        self.ramp = ramp
        self.motion = motion
    }

    private var carriesText: Bool { tintOpacity > 0 }

    var body: some View {
        // A foto fica num overlay pra nunca mudar o tamanho proposto (scaledToFill passaria da largura).
        (carriesText ? V8.bone : V8.photo)
            .overlay {
                if url != nil {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                            .modifier(MaybeKenBurns(on: motion))
                    }
                    if carriesText {
                        V8.paper
                            .mask(LinearGradient(stops: [.init(color: .clear, location: ramp.lowerBound),
                                                         .init(color: .black.opacity(0.94), location: ramp.upperBound),
                                                         .init(color: .black, location: 1)],
                                                 startPoint: .top, endPoint: .bottom))
                    }
                }
            }
            .clipped()
            // Cache primeiro (prompt 18 · A.4): sem imagem e sem rede, fica o placeholder, sem spinner.
            .task(id: url) {
                guard let url else { image = nil; return }
                image = await PhotoLoader.load(url)
            }
    }
}

/// Zoom lento na foto (Ken Burns) dos heroes: 1 → 1,07 em 22 s, vai e volta. Desligado com "Reduzir movimento".
struct KenBurns: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoomed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(zoomed ? 1.07 : 1, anchor: .center)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 22).repeatForever(autoreverses: true)) { zoomed = true }
            }
    }
}

extension View {
    func kenBurns() -> some View { modifier(KenBurns()) }
}

struct MaybeKenBurns: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View {
        if on { content.kenBurns() } else { content }
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
        // Foto do Google (prompt 19): já está no disco, em arquivo (800 px ou miniatura 240 px).
        if url.isFileURL {
            guard let image = await decoded(file: url) else { return nil }
            memory.setObject(image, forKey: url as NSURL)
            return image
        }
        let key = "photo|\(url.absoluteString)"
        if let saved = await DiskCache.shared.stale(key), let image = await decoded(saved) {
            memory.setObject(image, forKey: url as NSURL)
            if await DiskCache.shared.isFresh(key, maxAge: freshFor) == false {
                Task { _ = await fetch(url, key: key) }   // velha: troca na próxima vez, sem atrasar a tela
            }
            return image
        }
        guard let data = await fetch(url, key: key), let image = await decoded(data) else { return nil }
        memory.setObject(image, forKey: url as NSURL)
        return image
    }

    /// Lê e decodifica fora do main (rodada 23 · G): o `UIImage` de arquivo é preguiçoso e decodificava no primeiro
    /// desenho, no main, no meio da rolagem da Lista e dos Musts.
    nonisolated static func decoded(file url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path())?.preparingForDisplay()
        }.value
    }

    nonisolated static func decoded(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            UIImage(data: data)?.preparingForDisplay()
        }.value
    }

    /// Pré-download do dia (prompt 18 · A.5): garante a foto no disco. Não gasta dado do Modo de Pouco Dados
    /// (`HTTP(kind: .prefetch)`). `true` se já estava lá ou baixou.
    static func prefetch(_ url: URL) async -> Bool {
        if url.isFileURL { return FileManager.default.fileExists(atPath: url.path()) }
        let key = "photo|\(url.absoluteString)"
        if await DiskCache.shared.exists(key) { return true }
        guard let raw = try? await HTTP(kind: .prefetch).get(url, headers: ["User-Agent": CommonsPhotoService.userAgent], service: "foto"),
              PlacePhotoStore.isCompleteImage(raw) else { return false }
        let data = await compact(raw)
        await DiskCache.shared.store(data, for: key)
        trimInBackground()
        return true
    }

    private static func fetch(_ url: URL, key: String) async -> Data? {
        guard let raw = try? await HTTP().get(url, headers: ["User-Agent": CommonsPhotoService.userAgent], service: "foto") else {
            return nil
        }
        // Cortada no meio (rede caindo): não grava — no disco ela valeria 30 dias, meio cinza.
        guard PlacePhotoStore.isCompleteImage(raw) else { return nil }
        let data = await compact(raw)
        await DiskCache.shared.store(data, for: key)
        trimInBackground()
        return data
    }

    /// Lado maior da foto guardada no disco (premissa: 800 px, JPEG 0,7).
    nonisolated static let storedPixels = 800

    /// Foto maior que 800 px vira JPEG de 800 px, qualidade 0,7, fora do main. Menor (ou se não ficar menor), como veio.
    nonisolated static func compact(_ data: Data) async -> Data {
        await Task.detached(priority: .utility) {
            guard let size = PlacePhotoStore.thumbnailSize(data), max(size.width, size.height) > storedPixels,
                  let small = PlacePhotoStore.makeThumbnail(data, maxPixel: storedPixels), small.count < data.count else { return data }
            return small
        }.value
    }

    /// Teto de 300 MB (prompt 19 · item 3): as fotos do Commons entram no mesmo despejo LRU.
    private static func trimInBackground() {
        Task.detached(priority: .utility) { PlacePhotoStore.trim() }
    }
}


// MARK: - Navegação

enum MustTab: String, CaseIterable, Identifiable, Sendable {
    /// Abas v8 (prompt 23 §2, `Nav.png`): Hoje (capa), Guia, Musts, Viagem (Próximos) + `+`.
    case hoje, guia, musts, viagem

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hoje: "Hoje"
        case .guia: "Explorar"
        case .musts: "Musts"
        case .viagem: "Viagem"
        }
    }

    var icon: MustIcon {
        switch self {
        case .hoje: .hoje
        case .guia: .mapa
        case .musts: .mustsLista
        case .viagem: .calendario
        }
    }
}

/// Barra v5 (pílula branca). Na v8 a barra é a `V8NavBar` (cápsula preta, aba ativa laranja): esta virou um apelido
/// dela, pra que quem ainda usa `MustTabBar(selected:)` saia com a barra nova.
struct MustTabBar: View {
    @Binding var selected: MustTab

    var body: some View {
        V8NavBar(active: selected, onSelect: { selected = $0 })
    }
}

/// Alça de sheet.
struct SheetHandle: View {
    var body: some View {
        Capsule()
            .fill(V8.ink.opacity(0.2))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .accessibilityHidden(true)
    }
}

// MARK: - Toggle

/// Toggle 84×48 do design reduzido a 46×28: laranja com bolinha tinta quando ligado; filete com bolinha branca desligado.
struct MustToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Capsule()
                .fill(configuration.isOn ? V8.orange : Color(hex: V8.Hex.ruleStrong))
                .frame(width: 46, height: 28)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? V8.ink : V8.white)
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

// MARK: - Barra de status sobre mapa

/// Véu de papel sob a barra de status em telas de mapa em tela cheia: a hora e a bateria não ficam em cima dos nomes
/// do mapa. Não recebe toque.
struct StatusBarScrim: View {
    var body: some View {
        GeometryReader { geo in
            LinearGradient(stops: [.init(color: V8.paper.opacity(0.92), location: 0),
                                   .init(color: V8.paper.opacity(0.6), location: 0.55),
                                   .init(color: V8.paper.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: geo.safeAreaInsets.top + 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
