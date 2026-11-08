import CoreImage
import CoreImage.CIFilterBuiltins
import CryptoKit
import SwiftUI
import UIKit

// O corte (prompt 30): toda tela principal é foto em cima, papel embaixo, separados por uma régua preta.
// Dois componentes pra todas as telas:
//
//   CutBand(photo: url, height: …) { texto do bloco }      // foto tratada (ou só a cor do lugar) + trama + arcos
//   CutRule()                                              // régua estática, 12 pt
//   CutRule(pullLabel: "↓ puxe · quero…")                  // régua puxável, 26 pt (+ `.cutPull(pull) { … }`)
//
// A foto **nunca é baixada** por causa do corte: o chamador passa a URL de uma foto que o app já tem (arquivo do Google,
// cópia do Commons no `DiskCache`). O tratamento roda fora do main e fica em disco por `foto + cor`.

// MARK: - Tratamento (Core Image, fora do main)

/// P&B de contraste alto multiplicado sobre a cor do lugar, mais a trama de pontos de tinta. Puro: `Data` → `UIImage`.
enum CutTreatment {
    /// Muda quando o tratamento muda (invalida o cache de disco).
    static let version = 1
    /// Largura de saída em pixels (402 pt × 3, a largura de um iPhone Pro).
    static let pixelWidth = 1206
    static let contrast: Float = 1.6
    /// Trama: ponto de 0,9 pt a cada 4 pt, tinta a 25 %.
    static let dotPitch: CGFloat = 4
    static let dotDiameter: CGFloat = 0.9
    static let dotAlpha: CGFloat = 0.25

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Chave do cache: foto + cor + versão. Sem foto, `source` é "plain".
    static func key(source: String, tint: UInt32) -> String {
        let raw = "cut\(version)|\(source)|\(String(tint, radix: 16))"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32).description
    }

    /// `data` = a foto como está no disco. `nil` = só a cor do lugar com a trama (estado normal, sem foto).
    static func render(photo data: Data?, tint: UInt32) -> UIImage? {
        let width = CGFloat(pixelWidth)
        let color = CIColor(red: CGFloat((tint >> 16) & 0xFF) / 255, green: CGFloat((tint >> 8) & 0xFF) / 255,
                            blue: CGFloat(tint & 0xFF) / 255)
        var base: CIImage
        var size: CGSize
        if let data, let photo = CIImage(data: data, options: [.applyOrientationProperty: true]), photo.extent.width > 1 {
            let scale = width / photo.extent.width
            let scaled = photo.transformed(by: CGAffineTransform(scaleX: scale, y: scale), highQualityDownsample: true)
            size = CGSize(width: width, height: scaled.extent.height.rounded())
            let gray = scaled.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: contrast,
                                                                             kCIInputBrightnessKey: -0.03])
            let solid = CIImage(color: color).cropped(to: gray.extent)
            base = gray.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: solid])
            base = base.transformed(by: CGAffineTransform(translationX: -base.extent.minX, y: -base.extent.minY))
        } else {
            size = CGSize(width: width, height: width)
            base = CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size))
        }
        guard let cg = context.createCGImage(base, from: CGRect(origin: .zero, size: size)) else { return nil }
        return withDots(cg, size: size)
    }

    /// Trama de pontos por cima (halftone: linhas alternadas deslocadas meio passo).
    private static func withDots(_ image: CGImage, size: CGSize) -> UIImage? {
        let scale: CGFloat = 3
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let out = renderer.image { ctx in
            let g = ctx.cgContext
            // CGImage vem de baixo pra cima: vira o contexto antes de desenhar.
            g.saveGState()
            g.translateBy(x: 0, y: size.height)
            g.scaleBy(x: 1, y: -1)
            g.draw(image, in: CGRect(origin: .zero, size: size))
            g.restoreGState()
            g.setFillColor(UIColor(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255, alpha: dotAlpha).cgColor)
            let pitch = dotPitch * scale, d = dotDiameter * scale
            var row = 0
            var y: CGFloat = pitch / 2
            while y < size.height {
                var x = (row % 2 == 0 ? pitch / 2 : pitch)
                while x < size.width {
                    g.fillEllipse(in: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d))
                    x += pitch
                }
                y += pitch
                row += 1
            }
        }
        return UIImage(cgImage: out.cgImage ?? image, scale: scale, orientation: .up)
    }
}

// MARK: - Cache de disco

/// Uma imagem tratada por chave (`CutTreatment.key`): na memória e em `Caches/must-cut/` (JPEG 0,82). A mesma chave nunca
/// é processada duas vezes; duas telas pedindo a mesma chave ao mesmo tempo esperam o mesmo processamento.
actor CutImageCache {
    static let shared = CutImageCache()

    private let directory: URL
    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    /// Quantas vezes o tratamento rodou de verdade (testes).
    private(set) var renders = 0

    init(directory: URL = URL.cachesDirectory.appending(path: "must-cut", directoryHint: .isDirectory)) {
        self.directory = directory
        memory.countLimit = 12
    }

    func image(key: String, make: @escaping @Sendable () async -> UIImage?) async -> UIImage? {
        if let hit = memory.object(forKey: key as NSString) { return hit }
        let file = directory.appending(path: "\(key).jpg")
        if let disk = UIImage(contentsOfFile: file.path())?.preparingForDisplay() {
            memory.setObject(disk, forKey: key as NSString)
            return disk
        }
        if let running = inFlight[key] { return await running.value }
        renders += 1
        let task = Task.detached(priority: .userInitiated) { await make() }
        inFlight[key] = task
        let made = await task.value
        inFlight[key] = nil
        if let made {
            memory.setObject(made, forKey: key as NSString)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? made.jpegData(compressionQuality: 0.82)?.write(to: file, options: .atomic)
        }
        return made
    }
}

enum CutImages {
    /// A foto tratada. Lê só o que já está no aparelho (arquivo, ou a cópia da foto no `DiskCache`); nunca baixa.
    static func treated(photo: URL?, tint: UInt32, cache: CutImageCache = .shared) async -> UIImage? {
        let key = CutTreatment.key(source: photo?.absoluteString ?? "plain", tint: tint)
        return await cache.image(key: key) {
            let data = await onDisk(photo)
            return CutTreatment.render(photo: data, tint: tint)
        }
    }

    static func onDisk(_ url: URL?) async -> Data? {
        guard let url else { return nil }
        if url.isFileURL { return try? Data(contentsOf: url) }
        return await DiskCache.shared.stale("photo|\(url.absoluteString)")
    }
}

// MARK: - Bloco da foto

/// Bloco da foto (`CutBand`): foto em P&B de contraste alto multiplicada sobre a cor do lugar (`TripTheme`), trama de pontos
/// e arcos de 1 pt; texto em branco (em tinta quando não há viagem). Sem foto: a cor do lugar com a trama e os arcos.
///
/// O tamanho é do chamador (`.frame(height:)`); o fundo sangra por cima, até a borda de cima da tela. O tratamento roda
/// fora do main e vem do cache; enquanto isso (ou sem foto) aparece a cor do lugar, nunca um branco.
/// `photo` é uma foto que o app **já tem**: arquivo local ou URL já guardada no `DiskCache` (`CCPhoto.largeURL ?? url`).
struct CutBand<Content: View>: View {
    var photo: URL?
    /// Muda a cor do bloco (padrão: a cor do lugar do `TripTheme`).
    var tint: UInt32?
    var arcs = true
    var alignment: Alignment = .bottomLeading
    @ViewBuilder var content: Content

    @Environment(\.tripTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?

    private var rgb: UInt32 { tint ?? theme.coverRGB }
    private var ink: Color { theme.hasTrip || tint != nil ? V8.white : V8.ink }

    var body: some View {
        content
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .background { backdrop.ignoresSafeArea(edges: .top) }
            .task(id: CutTreatment.key(source: photo?.absoluteString ?? "plain", tint: rgb)) {
                let made = await CutImages.treated(photo: photo, tint: rgb)
                if reduceMotion { image = made } else { withAnimation(.easeOut(duration: 0.25)) { image = made } }
            }
    }

    private var backdrop: some View {
        Color(hex: rgb)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
                }
            }
            .overlay(alignment: .topLeading) {
                if arcs { Rings(color: ink, count: 2, diameter: 380, opacity: 0.5, offset: CGSize(width: 150, height: 20)) }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

// MARK: - Régua

/// Régua preta de largura total. **Estática** (12 pt): só estrutura, sem pegador e sem texto. **Puxável** (26 pt): pegador
/// laranja no centro e o micro-rótulo ("↓ puxe · quero…", depois "↓ quero"). Regra de ouro: só se puxa a régua que tem
/// pegador e texto. O gesto vem de `.cutPull(_:)`.
struct CutRule: View {
    static let fixedHeight: CGFloat = 12
    static let pullHeight: CGFloat = 26

    /// `nil` = estática.
    var label: String?

    /// Estática (12 pt).
    init() { label = nil }

    /// Puxável (26 pt).
    init(pullLabel: String) { label = pullLabel }

    var body: some View {
        if let label {
            VStack(spacing: 3) {
                Capsule().fill(V8.orange).frame(width: 34, height: 4)
                Text(label.uppercased())
                    .font(V8Font.mono(8.5))
                    .tracking(0.9)
                    .foregroundStyle(V8.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: Self.pullHeight)
            .padding(.vertical, 2)
            .background(V8.ink)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Quero…")
            .accessibilityHint("abre a busca do que tem perto")
            .accessibilityAddTraits(.isButton)
        } else {
            V8.ink.frame(height: Self.fixedHeight).accessibilityHidden(true)
        }
    }
}

// MARK: - Puxar a régua

/// O arrasto da régua (puro e testável). 1:1 com o dedo até o limite (~110 pt); passou do limite, **trava aberta** na hora
/// (háptico); soltou antes, volta com mola. Só pra baixo.
@MainActor
@Observable
final class CutPull {
    nonisolated static let limit: CGFloat = 110
    /// A partir daqui o rótulo diz "mais um pouco".
    nonisolated static let almost: CGFloat = 40
    /// Depois de tantas puxadas com resultado, o texto encurta pra "↓ quero" e o cutucão para.
    nonisolated static let usesBeforeShort = 3

    enum Phase: Equatable { case closed, pulling, open }

    private(set) var phase: Phase = .closed
    /// Quanto a régua desceu (0…limite).
    private(set) var offset: CGFloat = 0
    /// Sobe a cada travada (gatilho do `.sensoryFeedback`).
    private(set) var openedTicks = 0

    var progress: CGFloat { min(offset / Self.limit, 1) }
    var isOpen: Bool { phase == .open }

    func drag(translation: CGFloat) {
        guard phase != .open else { return }
        offset = min(max(translation, 0), Self.limit)
        phase = offset > 0 ? .pulling : .closed
        if offset >= Self.limit { lock() }
    }

    /// Soltou: antes do limite, volta.
    func release() {
        guard phase == .pulling else { return }
        phase = .closed
        offset = 0
    }

    /// Abre sem gesto (toque no nome do bairro, VoiceOver, passo a passo).
    func lock() {
        guard phase != .open else { return }
        phase = .open
        offset = Self.limit
        openedTicks += 1
    }

    func close() {
        phase = .closed
        offset = 0
    }

    /// O rótulo da régua: "↓ puxe · quero…" → "↓ mais um pouco" (no meio do gesto) → "↑ fechar" (aberta); depois de 3 usos "↓ quero".
    static func label(phase: Phase, offset: CGFloat, uses: Int, noun: String = "quero") -> String {
        switch phase {
        case .open: return "↑ fechar"
        case .pulling where offset >= almost: return "↓ mais um pouco"
        default: return uses >= usesBeforeShort ? "↓ \(noun)" : "↓ puxe · \(noun)…"
        }
    }
}

extension View {
    /// Liga o arrasto da régua ao `CutPull`: começa na régua (prioridade sobre os gestos da tela), só pra baixo, com mola
    /// ao soltar. `onOpen` roda uma vez quando trava; toque = abre (ou fecha, se já aberta).
    func cutPull(_ pull: CutPull, reduceMotion: Bool = false, onOpen: @escaping () -> Void, onClose: @escaping () -> Void = {}) -> some View {
        modifier(CutPullModifier(pull: pull, reduceMotion: reduceMotion, onOpen: onOpen, onClose: onClose))
    }
}

private struct CutPullModifier: ViewModifier {
    var pull: CutPull
    var reduceMotion: Bool
    var onOpen: () -> Void
    var onClose: () -> Void

    func body(content: Content) -> some View {
        content
            // Área de toque de 44 pt (a régua tem 26): aumenta e devolve o tamanho de layout.
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .padding(.vertical, -9)
            .highPriorityGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { value in
                        guard !pull.isOpen, value.translation.height > 0 else { return }
                        let wasOpen = pull.isOpen
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) { pull.drag(translation: value.translation.height) }
                        if pull.isOpen, !wasOpen { onOpen() }
                    }
                    .onEnded { value in
                        if pull.isOpen {
                            // Subir a régua aberta fecha.
                            if value.translation.height < -30 { onClose() }
                            return
                        }
                        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.72)) { pull.release() }
                    }
            )
            .onTapGesture { if pull.isOpen { onClose() } else { pull.lock(); onOpen() } }
            .sensoryFeedback(.impact(weight: .medium), trigger: pull.openedTicks)
    }
}
