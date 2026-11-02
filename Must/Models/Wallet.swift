import Foundation
import SwiftData

// Carteira da viagem (prompt 15 · B): cartões, passes, eSIM, QR de entrada e documentos.
// Persistida no container da região (como o resto do board). Documentos (PDF, foto) ficam em `TicketFiles`
// com `FileProtectionType.complete`; o item guarda só o nome do arquivo. Nada disso entra no export do board.

/// Tipo de item. Cartões e passes (`isCard`) empilham no topo da tela; o resto vira lista de documentos.
enum WalletKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case transitCard = "transit-card"
    case railPass = "rail-pass"
    case creditCard = "credit-card"
    case esim
    case entryQR = "entry-qr"
    case insurance
    case passport
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .transitCard: "cartão de transporte"
        case .railPass: "passe de trem"
        case .creditCard: "cartão"
        case .esim: "eSIM"
        case .entryQR: "QR de entrada"
        case .insurance: "seguro"
        case .passport: "passaporte"
        case .other: "outro"
        }
    }

    /// Selo de 2–3 letras na lista de documentos (o PDF e a foto ganham o selo do arquivo, na tela).
    var badge: String {
        switch self {
        case .transitCard: "IC"
        case .railPass: "JR"
        case .creditCard: "CARD"
        case .esim: "eSIM"
        case .entryQR: "QR"
        case .insurance: "SEG"
        case .passport: "ID"
        case .other: "DOC"
        }
    }

    var isCard: Bool { self == .transitCard || self == .railPass || self == .creditCard }

    /// Cor do cartão empilhado (o tipo define; não há escolha manual).
    var tone: WalletTone {
        switch self {
        case .transitCard: .green
        case .creditCard: .blue
        default: .graphite
        }
    }
}

/// Gradiente do cartão empilhado (texto branco por cima).
enum WalletTone: String, Codable, CaseIterable, Sendable {
    case green, graphite, blue

    var colors: [UInt32] {
        switch self {
        case .green: [0x1FA37A, 0x0B5A33]
        case .graphite: [0x3B4150, 0x15171C]
        case .blue: [0x5B6CFF, 0x2B7BFF]
        }
    }
}

@Model
final class WalletItem {
    @Attribute(.unique) var id: String = UUID().uuidString
    var kindRaw: String = WalletKind.other.rawValue
    var name: String = ""
    /// Nome no idioma local ("スイカ").
    var nameLocal: String?
    /// Linha de apoio do cartão e da lista ("Apple Wallet · Express Transit · metrô, JR, konbini").
    var detail: String = ""
    /// Passe: o que cobre ("Tóquio → Kyoto → Tóquio · Nara").
    var coverage: String?
    /// Saldo ANOTADO À MÃO (não há API pública pra ler o saldo da Suica), na moeda da região.
    var balance: Double?
    var balanceNotedAt: Date?
    /// Aviso de recarga: saldo anotado abaixo deste valor fica destacado.
    var lowBalance: Double?
    var validFrom: Date?
    var validUntil: Date?
    /// PDF ou foto em `TicketFiles` (proteção completa). Nil se não há arquivo.
    var attachmentName: String?
    /// Texto do QR (QR de entrada, passe de trem). A tela desenha o QR offline, com CoreImage.
    var qrPayload: String?
    /// "Abrir no Wallet ↗": abre o app Wallet via `shoebox://`, sem passe específico.
    var opensWallet: Bool = false
    /// Link que você guardou (site, app do fornecedor). Abre no navegador.
    var link: String?
    /// Instruções (eSIM: como instalar e ativar), em texto livre.
    var notes: String = ""
    var order: Int = 0
    var createdAt: Date = Date()

    init(id: String = UUID().uuidString, kind: WalletKind, name: String, nameLocal: String? = nil, detail: String = "",
         coverage: String? = nil, balance: Double? = nil, balanceNotedAt: Date? = nil, lowBalance: Double? = nil,
         validFrom: Date? = nil, validUntil: Date? = nil, attachmentName: String? = nil, qrPayload: String? = nil,
         opensWallet: Bool = false, link: String? = nil, notes: String = "", order: Int = 0, createdAt: Date = AppClock.now) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.name = name
        self.nameLocal = nameLocal
        self.detail = detail
        self.coverage = coverage
        self.balance = balance
        self.balanceNotedAt = balanceNotedAt
        self.lowBalance = lowBalance
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.attachmentName = attachmentName
        self.qrPayload = qrPayload
        self.opensWallet = opensWallet
        self.link = link
        self.notes = notes
        self.order = order
        self.createdAt = createdAt
    }

    var kind: WalletKind {
        get { WalletKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    /// Arquivo é PDF (senão, foto).
    var attachmentIsPDF: Bool { attachmentName?.lowercased().hasSuffix(".pdf") ?? false }
}

/// Regras da Carteira (puras, testáveis): aviso de saldo, validade, texto de "anotou ontem", "tem entryQR?".
enum WalletRules {
    /// "Abrir no Wallet": abre o app Wallet. Não há deep link público pra um passe específico.
    static let walletURL = URL(string: "shoebox://")!

    /// Saldo anotado abaixo do limite que você definiu.
    static func isLowBalance(_ item: WalletItem) -> Bool {
        guard let balance = item.balance, let low = item.lowBalance else { return false }
        return balance < low
    }

    /// "a carteira tem entryQR?" (fatia 6: o item "Visit Japan Web" do checklist se marca sozinho).
    static func containsEntryQR(_ items: [WalletItem]) -> Bool {
        items.contains { $0.kind == .entryQR }
    }

    /// "você anotou hoje" · "ontem" · "em 3 nov".
    static func balanceNote(noted: Date, now: Date, region: Region) -> String {
        let days = daysBetween(noted, now, region: region)
        switch days {
        case ...0: return "você anotou hoje"
        case 1: return "você anotou ontem"
        default: return "você anotou em \(region.shortDay(noted))"
        }
    }

    /// Dias inteiros de `from` até `to` no fuso da região (negativo se `to` já passou).
    static func daysBetween(_ from: Date, _ to: Date, region: Region) -> Int {
        let cal = region.calendar
        return cal.dateComponents([.day], from: cal.startOfDay(for: from), to: cal.startOfDay(for: to)).day ?? 0
    }

    /// Validade em uma linha: "vale 17–23 nov", "vence em 8 dias", "válido até 2031", "a partir de 17 nov".
    static func validity(from: Date?, until: Date?, now: Date, region: Region) -> String? {
        switch (from, until) {
        case let (start?, end?):
            let sameMonth = region.calendar.component(.month, from: start) == region.calendar.component(.month, from: end)
            return sameMonth
                ? "vale \(region.dayNumber(start))–\(region.shortDay(end))"
                : "vale \(region.shortDay(start))–\(region.shortDay(end))"
        case let (nil, end?):
            let left = daysBetween(now, end, region: region)
            if left < 0 { return "venceu \(region.shortDay(end))" }
            if left == 0 { return "vence hoje" }
            if left <= 30 { return "vence em \(left) \(left == 1 ? "dia" : "dias")" }
            if left > 365 { return "válido até \(region.calendar.component(.year, from: end))" }
            return "válido até \(region.shortDay(end))"
        case let (start?, nil):
            return "a partir de \(region.shortDay(start))"
        case (nil, nil):
            return nil
        }
    }

    /// Validade a menos de 30 dias (a Carteira destaca em âmbar).
    static func isExpiringSoon(until: Date?, now: Date, region: Region) -> Bool {
        guard let until else { return false }
        let left = daysBetween(now, until, region: region)
        return left >= 0 && left <= 30
    }
}

extension ModelContext {
    /// Itens da Carteira da região, na ordem da tela.
    func walletItems() -> [WalletItem] {
        let items = (try? fetch(FetchDescriptor<WalletItem>())) ?? []
        return items.sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
    }

    /// "A carteira tem entryQR?" — consulta pra fatia 6 (checklist: Visit Japan Web).
    func walletHasEntryQR() -> Bool {
        WalletRules.containsEntryQR(walletItems())
    }
}
