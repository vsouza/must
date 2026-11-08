import CoreImage
import Foundation
import PDFKit
import UIKit
@testable import Must

/// Corpus sintético de ingressos (prompt 31 · 6): seis tipos, quatro formas cada (PDF com camada de texto, PDF só imagem,
/// foto limpa, foto torta e escura). Tudo desenhado aqui com CoreGraphics/PDFKit: nada baixado, nada de ingresso real.
/// Cada caso carrega o gabarito (`Truth`) pra medir acerto por campo.
struct TicketCase: Sendable {
    struct Line: Sendable {
        var text: String
        var size: CGFloat = 15
        var bold = false
    }

    /// Gabarito. `seat` é uma lista de pedaços que precisam aparecer no valor lido; nil = não se aplica.
    struct Truth: Sendable {
        var title: String
        var at: [Int]  // ano, mês, dia, hora, minuto
        var venue: String?
        var seat: [String]?
        var gate: String?
        var code: String
        var name: String
    }

    var id: String
    var label: String
    var region: Region
    var lines: [Line]
    var qr: String
    var truth: Truth
}

enum TicketForm: String, CaseIterable, Sendable {
    case textPDF = "PDF texto", imagePDF = "PDF imagem", photo = "foto", skewed = "foto torta/escura"
}

enum TicketCorpus {
    static let all: [TicketCase] = [museu, show, trem, coliseu, voo, restaurante]

    static let museu = TicketCase(
        id: "museu-jp", label: "Museu JP", region: .jp,
        lines: [
            .init(text: "teamLab Planets TOKYO", size: 30, bold: true),
            .init(text: "チームラボプラネッツ 入場券", size: 16),
            .init(text: "Admission Ticket · Date-time designated"),
            .init(text: "Visit date: 16 Nov 2026"),
            .init(text: "Entry time: 10:30 - 11:00"),
            .init(text: "Venue: 6-1-16 Toyosu, Koto City, Tokyo 135-0061"),
            .init(text: "Adult x 2 · ¥4,200 each"),
            .init(text: "Ticket No. TLP-8F3K-2291"),
            .init(text: "Name: SOUZA VINICIUS"),
        ],
        qr: "TLP-8F3K-2291",
        truth: .init(title: "teamLab Planets", at: [2026, 11, 16, 10, 30], venue: "Toyosu", seat: nil, gate: nil,
                     code: "TLP-8F3K-2291", name: "SOUZA"))

    static let show = TicketCase(
        id: "show-bh", label: "Show", region: .bh,
        lines: [
            .init(text: "Banda Cerrado Azul · Turnê Vento Sul", size: 26, bold: true),
            .init(text: "INGRESSO ELETRÔNICO · Inteira"),
            .init(text: "Data: sáb 21/11/2026"),
            .init(text: "Abertura dos portões: 19:00 · Início do show: 21:00"),
            .init(text: "Local: Teatro Bom Retiro — Av. Afonso Pena, 1050, Belo Horizonte"),
            .init(text: "Setor: Plateia A · Fila F · Poltrona 12"),
            .init(text: "Portão B"),
            .init(text: "Pedido nº 7741829-BH"),
            .init(text: "Titular: VINICIUS SOUZA"),
            .init(text: "Valor: R$ 180,00"),
        ],
        qr: "7741829-BH",
        truth: .init(title: "Banda Cerrado Azul", at: [2026, 11, 21, 21, 0], venue: "Teatro Bom Retiro", seat: ["F", "12"], gate: "B",
                     code: "7741829-BH", name: "VINICIUS"))

    static let trem = TicketCase(
        id: "trem-jp", label: "Trem", region: .jp,
        lines: [
            .init(text: "Shinkansen Nozomi 225", size: 28, bold: true),
            .init(text: "Tokyo → Kyoto", size: 20, bold: true),
            .init(text: "Date: 17 Nov 2026"),
            .init(text: "Departs 10:33 Tokyo · Platform 14"),
            .init(text: "Arrives 12:48 Kyoto"),
            .init(text: "Car 7 · Seat 12A · Reserved"),
            .init(text: "Fare ¥14,170"),
            .init(text: "Ticket No. 0412-5567-8890"),
        ],
        qr: "0412-5567-8890",
        truth: .init(title: "Shinkansen Nozomi 225", at: [2026, 11, 17, 10, 33], venue: nil, seat: ["7", "12A"], gate: "14",
                     code: "0412-5567-8890", name: ""))

    static let coliseu = TicketCase(
        id: "coliseu-it", label: "Coliseu/Vaticano", region: .it,
        lines: [
            .init(text: "Colosseo, Foro Romano e Palatino", size: 26, bold: true),
            .init(text: "Biglietto d'ingresso · Entry ticket"),
            .init(text: "Data visita: domenica 11 aprile 2027"),
            .init(text: "Turno di ingresso: ore 09:30"),
            .init(text: "Ingresso: Gate C"),
            .init(text: "Luogo: Piazza del Colosseo, 1, 00184 Roma RM"),
            .init(text: "Visitatori: 2"),
            .init(text: "Intestatario: VINICIUS SOUZA"),
            .init(text: "Codice prenotazione: CL-84K2-7731"),
        ],
        qr: "CL-84K2-7731",
        truth: .init(title: "Colosseo", at: [2027, 4, 11, 9, 30], venue: "Piazza del Colosseo", seat: nil, gate: "C",
                     code: "CL-84K2-7731", name: "VINICIUS"))

    static let voo = TicketCase(
        id: "voo", label: "Voo", region: .jp,
        lines: [
            .init(text: "CARTÃO DE EMBARQUE · BOARDING PASS", size: 20, bold: true),
            .init(text: "LATAM Airlines"),
            .init(text: "Passageiro: SOUZA/VINICIUS MR"),
            .init(text: "Voo LA 8084"),
            .init(text: "São Paulo (GRU) → Doha (DOH)", size: 18, bold: true),
            .init(text: "Data: 14 nov 2026"),
            .init(text: "Embarque: 22:35 · Partida: 23:10"),
            .init(text: "Portão: 14"),
            .init(text: "Assento: 12A"),
            .init(text: "Localizador: XKQ7MP"),
        ],
        qr: "M1SOUZA/VINICIUS XKQ7MP GRUDOHLA 8084",
        truth: .init(title: "LA 8084", at: [2026, 11, 14, 23, 10], venue: nil, seat: ["12A"], gate: "14",
                     code: "XKQ7MP", name: "SOUZA"))

    static let restaurante = TicketCase(
        id: "restaurante-jp", label: "Restaurante", region: .jp,
        lines: [
            .init(text: "Sushi Hanabi Ginza", size: 28, bold: true),
            .init(text: "Reservation confirmed"),
            .init(text: "Date: Sat, Nov 21, 2026"),
            .init(text: "Time: 19:30"),
            .init(text: "Party of 4"),
            .init(text: "Under the name: VINICIUS SOUZA"),
            .init(text: "Address: 4-2-8 Ginza, Chuo City, Tokyo 104-0061"),
            .init(text: "Confirmation: SH-4471-AB"),
            .init(text: "Free cancellation until Nov 19, 2026"),
        ],
        qr: "SH-4471-AB",
        truth: .init(title: "Sushi Hanabi Ginza", at: [2026, 11, 21, 19, 30], venue: "Ginza", seat: nil, gate: nil,
                     code: "SH-4471-AB", name: "VINICIUS"))

    // MARK: Renderização

    static let page = CGRect(x: 0, y: 0, width: 612, height: 792)

    /// Desenha o ingresso (texto e QR com zona silenciosa) no contexto atual.
    @MainActor
    static func draw(_ ticket: TicketCase) {
        UIColor.white.setFill()
        UIRectFill(page)
        UIColor(white: 0.92, alpha: 1).setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 612, height: 36))
        var y: CGFloat = 70
        for line in ticket.lines {
            let font = line.bold ? UIFont.boldSystemFont(ofSize: line.size) : UIFont.systemFont(ofSize: line.size)
            let rect = CGRect(x: 40, y: y, width: 532, height: line.size * 2.4)
            (line.text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin],
                                         attributes: [.font: font, .foregroundColor: UIColor.black], context: nil)
            y += line.size * 1.5 + 12
        }
        UIColor.white.setFill()
        UIRectFill(CGRect(x: 360, y: 500, width: 220, height: 220))
        TicketQR.image(for: ticket.qr, points: 190)?.draw(in: CGRect(x: 375, y: 515, width: 190, height: 190))
    }

    @MainActor
    static func textPDF(_ ticket: TicketCase) -> Data {
        UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            context.beginPage()
            draw(ticket)
        }
    }

    @MainActor
    static func pageImage(_ ticket: TicketCase, scale: CGFloat = 2) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: page.size, format: format).image { _ in draw(ticket) }
    }

    /// PDF sem camada de texto: só a imagem da página (ingresso escaneado).
    @MainActor
    static func imagePDF(_ ticket: TicketCase) -> Data {
        let image = pageImage(ticket)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            context.beginPage()
            image.draw(in: page)
        }
    }

    @MainActor
    static func photoPNG(_ ticket: TicketCase) -> Data { pageImage(ticket).pngData() ?? Data() }

    /// Foto de celular: página girada ~4° sobre mesa cinza, escura, levemente borrada, JPEG a 0,5.
    @MainActor
    static func skewedJPEG(_ ticket: TicketCase) -> Data {
        let flat = pageImage(ticket, scale: 1.0)
        let canvas = CGSize(width: flat.size.width * 1.25, height: flat.size.height * 1.12)
        let shot = UIGraphicsImageRenderer(size: canvas).image { context in
            UIColor(white: 0.32, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            context.cgContext.translateBy(x: canvas.width / 2, y: canvas.height / 2)
            context.cgContext.rotate(by: 5 * .pi / 180)
            flat.draw(in: CGRect(x: -flat.size.width / 2, y: -flat.size.height / 2, width: flat.size.width, height: flat.size.height))
        }
        guard let ci = CIImage(image: shot) else { return shot.jpegData(compressionQuality: 0.5) ?? Data() }
        let dark = ci.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.38, kCIInputContrastKey: 0.7])
            .applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 1.4, kCIInputRadiusKey: 1.6])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.1]).cropped(to: ci.extent)
        guard let cg = CIContext().createCGImage(dark, from: dark.extent) else { return shot.jpegData(compressionQuality: 0.5) ?? Data() }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.35) ?? Data()
    }

    @MainActor
    static func source(_ ticket: TicketCase, form: TicketForm) -> TicketSource {
        switch form {
        case .textPDF: .pdf(textPDF(ticket))
        case .imagePDF: .pdf(imagePDF(ticket))
        case .photo: .image(photoPNG(ticket))
        case .skewed: .image(skewedJPEG(ticket))
        }
    }

    /// Grava o corpus em disco (`TEST_RUNNER_TICKET_CORPUS_DIR`) pra inspeção e pra `MustTests/Fixtures/tickets/`.
    @MainActor
    static func export(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for ticket in all {
            for form in TicketForm.allCases {
                let ext: String, data: Data
                switch source(ticket, form: form) {
                case .pdf(let d): ext = "pdf"; data = d
                case .image(let d): ext = form == .skewed ? "jpg" : "png"; data = d
                default: continue
                }
                let slug = form.rawValue.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "/", with: "-")
                try? data.write(to: dir.appendingPathComponent("\(ticket.id)_\(slug).\(ext)"))
            }
        }
    }
}
