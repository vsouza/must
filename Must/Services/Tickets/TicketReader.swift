import CoreImage
import Foundation
import PDFKit
import UIKit
import Vision

/// O que o aparelho leu de um item do ingresso: texto, códigos (QR/barras), passe e link. Nada sai do iPhone,
/// exceto a página que o usuário colou e mandou ler (`readPage`).
struct TicketReading: Equatable, Sendable {
    /// Texto de todas as páginas (camada de texto do PDF, OCR da foto, campos do passe, página colada).
    var text: String = ""
    /// Payloads de QR e códigos de barras, na ordem em que apareceram.
    var codes: [String] = []
    /// Páginas com QR (1-based), pra mostrar "QR encontrado na página 1".
    var codePages: [Int] = []
    var pages: Int = 0
    var pass: PassInfo?
    /// Link colado ou recebido (lido só quando o usuário pede).
    var url: URL?
    /// "PDF · 2 páginas", "Foto", "Passe", "Texto colado", "Link".
    var sourceLabel: String = ""
}

/// Um item de entrada, já em bytes (Fotos, Arquivo, caixa do Share Extension, colar).
enum TicketSource: Sendable, Equatable {
    case pdf(Data)
    case image(Data)
    case pkpass(Data)
    case text(String)

    /// Extensão que o arquivo ganha ao ser guardado em `TicketFiles` (nil pra texto).
    var fileExtension: String? {
        switch self {
        case .pdf: "pdf"
        case .pkpass: "pkpass"
        case .image(let data): TicketReader.imageExtension(for: data)
        case .text: nil
        }
    }

    var fileData: Data? {
        switch self {
        case .pdf(let data), .image(let data), .pkpass(let data): data
        case .text: nil
        }
    }
}

enum TicketReaderError: LocalizedError, Equatable {
    case unreadablePass
    case unreadablePDF
    case unreadableImage
    case notAPage

    var errorDescription: String? {
        switch self {
        case .unreadablePass: "Esse .pkpass não tem um pass.json que eu consiga ler."
        case .unreadablePDF: "Não consegui abrir esse PDF."
        case .unreadableImage: "Não consegui ler essa imagem."
        case .notAPage: "O link não devolveu uma página de texto."
        }
    }
}

/// Leitura no aparelho (prompt 15 · A): PDFKit (texto e páginas), Vision (QR/barras e OCR em ja/en/pt) e `.pkpass`.
/// O trabalho pesado roda fora do main actor (`Task.detached`): PDFKit e Vision não bloqueiam a tela.
enum TicketReader {
    static func read(_ source: TicketSource) async throws -> TicketReading {
        switch source {
        case .pdf(let data): try await readPDF(data)
        case .image(let data): try await readImage(data)
        case .pkpass(let data): try readPass(data)
        case .text(let text): readText(text)
        }
    }

    /// Item da caixa do Share Extension, em bytes (o mesmo arquivo serve pra ler e pra guardar).
    static func source(for item: ShareInbox.Item) throws -> TicketSource {
        switch item.kind {
        case .pdf, .image, .pkpass:
            guard let url = ShareInbox.fileURL(for: item), let data = try? Data(contentsOf: url) else {
                throw TicketReaderError.unreadablePDF
            }
            switch item.kind {
            case .pdf: return .pdf(data)
            case .image: return .image(data)
            default: return .pkpass(data)
            }
        case .url, .text:
            return .text(item.text ?? "")
        case .video:
            // Vídeo não é ingresso: o Adicionar (prompt 29) é quem lê.
            throw TicketReaderError.unreadablePDF
        }
    }

    static func read(_ item: ShareInbox.Item) async throws -> TicketReading {
        try await read(try source(for: item))
    }

    // MARK: PDF

    /// Texto por página (PDFKit) e QR por página (página rasterizada a 2×, Vision). Página sem texto cai no OCR.
    static func readPDF(_ data: Data) async throws -> TicketReading {
        try await Task.detached(priority: .userInitiated) { () async throws -> TicketReading in
            guard let document = PDFDocument(data: data), document.pageCount > 0 else { throw TicketReaderError.unreadablePDF }
            var reading = TicketReading(pages: document.pageCount)
            var texts: [String] = []
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let pageText = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let box = page.bounds(for: .mediaBox)
                let scale: CGFloat = 2
                    // Camada de texto do PDF primeiro; só página sem texto (ou com quase nada) vai pro OCR, a 3×.
                let needsOCR = pageText.count < 30
                let renderScale: CGFloat = needsOCR ? 3 : scale
                let raster = page.thumbnail(of: CGSize(width: box.width * renderScale, height: box.height * renderScale), for: .mediaBox).cgImage
                var found = ScanResult()
                if let raster {
                    found = await scan(raster, recognizeText: needsOCR)
                }
                if !pageText.isEmpty { texts.append(pageText) }
                if !found.text.isEmpty { texts.append(found.text) }
                for code in found.codes {
                    reading.codes.append(code)
                    reading.codePages.append(index + 1)
                }
            }
            reading.text = texts.joined(separator: "\n")
            reading.sourceLabel = "PDF · \(document.pageCount) \(document.pageCount == 1 ? "página" : "páginas")"
            return reading
        }.value
    }

    // MARK: Imagem

    static func readImage(_ data: Data) async throws -> TicketReading {
        try await Task.detached(priority: .userInitiated) { () async throws -> TicketReading in
            guard let cgImage = UIImage(data: data)?.cgImage else { throw TicketReaderError.unreadableImage }
            let found = await scan(cgImage, recognizeText: true)
            return TicketReading(text: found.text, codes: found.codes, codePages: found.codes.map { _ in 1 }, pages: 1,
                                 sourceLabel: "Foto")
        }.value
    }

    /// Idiomas do OCR: pt, en, ja e it (ingressos do Brasil, do Japão e da Itália).
    static let ocrLanguages = ["pt-BR", "en-US", "ja-JP", "it-IT"]

    /// Códigos de barras de um `CGImage` (QR, Aztec, PDF417, Code 128) e, se pedido, o texto. OCR em duas passadas:
    /// original e, se saiu pouco texto (foto escura, torta, de pouco contraste), a imagem realçada; vale a que leu mais.
    static func scan(_ image: CGImage, recognizeText: Bool) async -> ScanResult {
        let barcodes = VNDetectBarcodesRequest()
        barcodes.symbologies = [.qr, .aztec, .pdf417, .code128]
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([barcodes])
        var codes = (barcodes.results ?? []).compactMap(\.payloadStringValue)
        if codes.isEmpty { codes = qrCodes(image) }
        guard recognizeText else { return ScanResult(codes: codes, text: "") }

        var text = await recognize(image)
        if text.count < 80 || codes.isEmpty, let better = enhanced(image) {
            let second = await recognize(better)
            if second.count > text.count { text = second }
            if codes.isEmpty { codes = qrCodes(better) }
        }
        return ScanResult(codes: codes, text: text)
    }

    /// OCR de um `CGImage`: `RecognizeDocumentsRequest` (iOS 26: lê o documento em linhas, com idioma automático) e, se falhar
    /// ou vier vazio, `VNRecognizeTextRequest` `.accurate` com correção de idioma.
    static func recognize(_ image: CGImage) async -> String {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = ocrLanguages.map { Locale.Language(identifier: $0) }
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.useLanguageCorrection = true
        request.barcodeDetectionOptions.enabled = false
        if let observations = try? await request.perform(on: image) {
            let lines = observations.flatMap { $0.document.text.lines.map(\.transcript) }
            let joined = lines.joined(separator: "\n")
            if joined.count >= 12 { return joined }
        }
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.recognitionLanguages = ocrLanguages
        text.usesLanguageCorrection = true
        text.automaticallyDetectsLanguage = true
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([text])
        return (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// Foto difícil: auto-ajuste (exposição/tom), cinza e contraste. Só pra uma segunda tentativa de leitura.
    static func enhanced(_ image: CGImage) -> CGImage? {
        var ci = CIImage(cgImage: image)
        for filter in ci.autoAdjustmentFilters(options: [.redEye: false]) {
            filter.setValue(ci, forKey: kCIInputImageKey)
            if let out = filter.outputImage { ci = out }
        }
        ci = ci.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.5, kCIInputBrightnessKey: 0.1])
        // Imagem pequena demais lê mal: sobe pra pelo menos 2000 px no maior lado.
        let longest = max(ci.extent.width, ci.extent.height)
        if longest < 2000 {
            let factor = 2000 / longest
            ci = ci.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: factor, kCIInputAspectRatioKey: 1])
        }
        return CIContext().createCGImage(ci, from: ci.extent)
    }

    /// Fallback de QR pelo CoreImage (`CIDetector`, offline). No simulador o Vision de código de barras
    /// não tem o modelo de inferência (erro "Could not create inference context") e devolve nada.
    static func qrCodes(_ image: CGImage) -> [String] {
        guard let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else {
            return []
        }
        return (detector.features(in: CIImage(cgImage: image)) as? [CIQRCodeFeature] ?? []).compactMap(\.messageString)
    }

    struct ScanResult: Equatable, Sendable {
        var codes: [String] = []
        var text: String = ""
    }

    // MARK: Passe

    static func readPass(_ data: Data) throws -> TicketReading {
        guard let info = try PKPassReader.read(data) else { throw TicketReaderError.unreadablePass }
        var lines = [info.organization, info.description].compactMap { $0 }
        lines += info.fields
        lines += info.locationTexts
        if let date = info.relevantDate {
            lines.append(date.formatted(.iso8601))
        }
        var reading = TicketReading(text: lines.joined(separator: "\n"), pass: info, sourceLabel: "Passe")
        if let barcode = info.barcode {
            reading.codes = [barcode]
            reading.codePages = [1]
        }
        return reading
    }

    // MARK: Texto e link

    /// Texto colado ou recebido. Se for um link, só guarda a URL: a página só é lida se o usuário mandar.
    static func readText(_ raw: String) -> TicketReading {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host() != nil {
            return TicketReading(text: "", url: url, sourceLabel: "Link")
        }
        return TicketReading(text: trimmed, sourceLabel: "Texto colado")
    }

    /// Lê a página de um link que o usuário colou e mandou ler. Uma requisição, sem seguir links nem executar script.
    static func readPage(_ url: URL) async throws -> TicketReading {
        let data = try await HTTP().get(url, headers: ["Accept-Language": "pt-BR,en;q=0.8,ja;q=0.6"], service: "ticket.page")
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let text = pageText(html)
        guard !text.isEmpty else { throw TicketReaderError.notAPage }
        return TicketReading(text: text, url: url, sourceLabel: "Link")
    }

    /// `og:title`, `og:description` e o texto visível (sem script, estilo nem tags), com teto de tamanho.
    static func pageText(_ html: String) -> String {
        var parts: [String] = []
        for property in ["og:title", "og:description"] {
            if let value = metaContent(html, property: property) { parts.append(value) }
        }
        var body = html.replacingOccurrences(of: #"(?is)<(script|style|noscript)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
        body = body.replacingOccurrences(of: #"(?s)<br\s*/?>|</(p|div|li|tr|h[1-6])>"#, with: "\n", options: .regularExpression)
        body = body.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        body = decodeEntities(body)
        let lines = body.split(whereSeparator: \.isNewline).map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        parts += lines.filter { !$0.isEmpty }
        return String(parts.joined(separator: "\n").prefix(20_000))
    }

    private static func metaContent(_ html: String, property: String) -> String? {
        let pattern = #"<meta[^>]+(?:property|name)=["']\#(property)["'][^>]*content=["']([^"']*)["']"#
        guard let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let tag = String(html[range])
        guard let content = tag.range(of: #"content=["']([^"']*)["']"#, options: .regularExpression) else { return nil }
        let value = tag[content].dropFirst(9).dropLast()
        return decodeEntities(String(value))
    }

    private static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    // MARK: Tipo do arquivo

    /// Extensão pelo cabeçalho do arquivo (Fotos entrega HEIC, PNG ou JPEG).
    static func imageExtension(for data: Data) -> String {
        let head = [UInt8](data.prefix(12))
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if head.count >= 12, head[4..<8].elementsEqual([0x66, 0x74, 0x79, 0x70]) { return "heic" }
        return "img"
    }
}
