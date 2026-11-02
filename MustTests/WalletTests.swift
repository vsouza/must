import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Must

/// Prompt 15 · B (fatia 5): Carteira. Trem (.pkpass) vira passe de trem, QR do Visit Japan Web vira entryQR,
/// documentos com proteção completa, saldo anotado à mão, validade e a consulta "a carteira tem entryQR?".
@MainActor
struct WalletTests {
    /// Sem rede: o Places nunca é chamado (`isConfigured` falso).
    private struct NoPlaces: PlacesProviding {
        var isConfigured: Bool { false }
        func searchText(_ query: String, near: CLLocationCoordinate2D, radius: Double, languageCode: String) async throws -> [PlaceCandidate] { [] }
        func details(_ placeId: String, languageCode: String) async throws -> PlaceDetails { throw URLError(.notConnectedToInternet) }
    }

    static func container() throws -> ModelContainer {
        try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// Sábado 2 nov 2026, 12:00 no Japão: o "agora" de todos os testes.
    static func now() throws -> Date {
        let dates = BoardDates(timeZone: Region.jp.timeZone)
        let day = try #require(dates.day(from: "2026-11-02"))
        return try #require(dates.time("12:00", on: day))
    }

    static func day(_ text: String) throws -> Date {
        try #require(BoardDates(timeZone: Region.jp.timeZone).day(from: text))
    }

    static let railPassJSON = Data("""
    {"formatVersion":1,"organizationName":"JR East","description":"Shinkansen Nozomi 17 · Tóquio → Kyoto",
     "relevantDate":"2026-11-17T09:12:00+09:00",
     "barcodes":[{"format":"PKBarcodeFormatQR","message":"JR-7K2M-NZ17","messageEncoding":"iso-8859-1"}],
     "boardingPass":{"primaryFields":[{"key":"train","label":"Trem","value":"Nozomi 17"}]}}
    """.utf8)

    // MARK: Entrada pelo Trazer ingresso

    @Test func trainPassBecomesARailPassWithItsQR() async throws {
        let now = try Self.now()
        let pass = TicketReaderTests.storedZip([("pass.json", Self.railPassJSON)])
        let reading = try await TicketReader.read(.pkpass(pass))
        let extracted = TicketExtractor.extract(reading, region: .jp)
        #expect(extracted.kind == .rail)

        let kind = try #require(WalletFromTicket.kind(for: extracted.kind))
        #expect(kind == .railPass)
        let draft = TicketDraft(extracted, region: .jp, now: now, sourceLabel: reading.sourceLabel)
        let item = WalletFromTicket.item(from: draft, kind: kind, attachmentName: nil, order: 0, now: now)
        #expect(item.kind == .railPass)
        #expect(item.qrPayload == "JR-7K2M-NZ17")
        #expect(item.validFrom == draft.at)
        #expect(item.name == "Shinkansen Nozomi 17 · Tóquio → Kyoto")
    }

    @Test func visitJapanWebQRBecomesAnEntryQR() throws {
        let reading = TicketReading(text: "Visit Japan Web\nImmigration\nEntry procedure",
                                    codes: ["https://vjw-lp.digital.go.jp/entry/abc123"], codePages: [1], pages: 1, sourceLabel: "Foto")
        let extracted = TicketExtractor.extract(reading, region: .jp)
        #expect(extracted.kind == .entry)
        #expect(extracted.title?.value == "Visit Japan Web · imigração")
        #expect(WalletFromTicket.kind(for: extracted.kind) == .entryQR)

        let draft = TicketDraft(extracted, region: .jp, now: try Self.now(), sourceLabel: reading.sourceLabel)
        let item = WalletFromTicket.item(from: draft, kind: .entryQR, attachmentName: nil, order: 0, now: try Self.now())
        #expect(item.qrPayload == "https://vjw-lp.digital.go.jp/entry/abc123")
    }

    @Test func entryNameFollowsTheQRThatWasRead() {
        #expect(TicketExtractor.entryName(text: "Visit Japan Web · Customs declaration") == "Visit Japan Web · alfândega")
        #expect(TicketExtractor.entryName(text: "Visit Japan Web") == "Visit Japan Web")
        // Uma leitura com as duas palavras não escolhe: fica o nome geral.
        #expect(TicketExtractor.entryName(text: "Immigration and Customs") == "Visit Japan Web")
    }

    @Test func aPlaceTicketIsNotAWalletKind() {
        #expect(WalletFromTicket.kind(for: .experience) == nil)
        #expect(WalletFromTicket.kind(for: .event) == nil)
        #expect(WalletFromTicket.kind(for: .other) == nil)
        #expect(WalletFromTicket.kind(for: .flight) == nil)
    }

    @Test func savingATrainTicketWritesTheWalletNotTheBoard() throws {
        let container = try Self.container()
        let now = try Self.now()
        let model = TicketImportModel()
        model.configure(context: container.mainContext, region: .jp, provider: NoPlaces())
        let reading = TicketReading(text: "Shinkansen Nozomi 17 · Tóquio → Kyoto\n17 nov 2026 09:12\nPessoas: 2",
                                    codes: ["JR-7K2M-NZ17"], codePages: [1], pages: 1, sourceLabel: "PDF · 1 página")
        let extracted = TicketExtractor.extract(reading, region: .jp)
        model.draft = TicketDraft(extracted, region: .jp, now: now, sourceLabel: reading.sourceLabel)

        #expect(model.canSave)
        #expect(model.isWalletKind)
        try model.save()

        #expect(model.saved)
        let items = container.mainContext.walletItems()
        #expect(items.count == 1)
        #expect(items.first?.kind == .railPass)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Place>()) == 0)
    }

    @Test func aTrainPassFileIsNotKeptOnlyItsCode() throws {
        let container = try Self.container()
        let now = try Self.now()
        let model = TicketImportModel()
        model.configure(context: container.mainContext, region: .jp, provider: NoPlaces())
        var draft = TicketDraft(at: now)
        draft.kind = .rail
        draft.title = "Nozomi 17"
        draft.qrPayload = "JR-7K2M-NZ17"
        draft.attachment = .pending(Data("pkpass".utf8), ext: "pkpass")
        model.draft = draft
        try model.save()

        let item = try #require(container.mainContext.walletItems().first)
        #expect(item.attachmentName == nil)
        #expect(item.qrPayload == "JR-7K2M-NZ17")
    }

    @Test func flightStillWaitsForTheVoosScreen() throws {
        let container = try Self.container()
        let model = TicketImportModel()
        model.configure(context: container.mainContext, region: .jp, provider: NoPlaces())
        var draft = TicketDraft(at: try Self.now())
        draft.kind = .flight
        draft.title = "LA 8084"
        model.draft = draft
        #expect(model.canSave == false)
        #expect(model.notYetMessage != nil)
        #expect(throws: TicketImportError.incomplete) { try model.save() }
        #expect(container.mainContext.walletItems().isEmpty)
    }

    // MARK: Consultas e regras

    @Test func walletHasEntryQROnlyWhenThereIsOne() throws {
        // O container precisa ficar vivo enquanto o contexto for usado.
        let container = try Self.container()
        let context = container.mainContext
        context.insert(WalletItem(kind: .transitCard, name: "Suica"))
        try context.save()
        #expect(context.walletHasEntryQR() == false)

        context.insert(WalletItem(kind: .entryQR, name: "Visit Japan Web", qrPayload: "VJW"))
        try context.save()
        #expect(context.walletHasEntryQR())
    }

    @Test func lowBalanceWarnsOnlyBelowTheLimit() {
        let item = WalletItem(kind: .transitCard, name: "Suica", balance: 800, lowBalance: 1000)
        #expect(WalletRules.isLowBalance(item))
        item.balance = 3240
        #expect(WalletRules.isLowBalance(item) == false)
        item.balance = nil
        #expect(WalletRules.isLowBalance(item) == false)
    }

    @Test func balanceNoteSaysWhenItWasAnnotated() throws {
        let now = try Self.now()
        #expect(WalletRules.balanceNote(noted: now, now: now, region: .jp) == "você anotou hoje")
        #expect(WalletRules.balanceNote(noted: now.addingTimeInterval(-86_400), now: now, region: .jp) == "você anotou ontem")
        #expect(WalletRules.balanceNote(noted: now.addingTimeInterval(-3 * 86_400), now: now, region: .jp) == "você anotou em 30 out")
    }

    @Test func validityReadsAsAPhrase() throws {
        let now = try Self.now()
        let from = try Self.day("2026-11-17")
        let until = try Self.day("2026-11-23")
        #expect(WalletRules.validity(from: from, until: until, now: now, region: .jp) == "vale 17–23 nov")
        #expect(WalletRules.validity(from: nil, until: try Self.day("2031-06-10"), now: now, region: .jp) == "válido até 2031")
        #expect(WalletRules.validity(from: nil, until: try Self.day("2026-11-10"), now: now, region: .jp) == "vence em 8 dias")
        #expect(WalletRules.validity(from: nil, until: try Self.day("2026-10-30"), now: now, region: .jp) == "venceu 30 out")
        #expect(WalletRules.validity(from: from, until: nil, now: now, region: .jp) == "a partir de 17 nov")
        #expect(WalletRules.validity(from: nil, until: nil, now: now, region: .jp) == nil)
        #expect(WalletRules.isExpiringSoon(until: try Self.day("2026-11-10"), now: now, region: .jp))
        #expect(WalletRules.isExpiringSoon(until: try Self.day("2031-06-10"), now: now, region: .jp) == false)
    }

    @Test func cardFactsAlertWhenTheBalanceIsLow() throws {
        let now = try Self.now()
        let suica = WalletItem(kind: .transitCard, name: "Suica", balance: 800, balanceNotedAt: now, lowBalance: 1000)
        let low = WalletCardFacts.make(suica, region: .jp, now: now)
        #expect(low.alert)
        #expect(low.tag?.hasPrefix("recarregar abaixo de") == true)
        #expect(low.label == "saldo (você anotou hoje)")

        suica.balance = 3240
        #expect(WalletCardFacts.make(suica, region: .jp, now: now).alert == false)

        let blank = WalletItem(kind: .transitCard, name: "Suica")
        #expect(WalletCardFacts.make(blank, region: .jp, now: now).value == "sem saldo anotado")
    }

    @Test func cardSpendShowsTheBRLConversionInJapan() throws {
        let card = WalletItem(kind: .creditCard, name: "Nubank · Mastercard")
        let facts = WalletCardFacts.make(card, region: .jp, now: try Self.now(), cardSpend: 100, fxRate: 0.036)
        #expect(facts.label == "gasto na viagem")
        #expect(facts.tag?.hasPrefix("câmbio ¥100") == true)
        #expect(facts.value.isEmpty == false)
    }

    @Test func documentRowsSayWhatIsReady() throws {
        let now = try Self.now()
        let ready = WalletItem(kind: .entryQR, name: "Visit Japan Web · imigração", qrPayload: "VJW")
        #expect(WalletDocumentFacts.make(ready, region: .jp, now: now).emphasis == .ready)
        let missing = WalletItem(kind: .entryQR, name: "Visit Japan Web")
        #expect(WalletDocumentFacts.make(missing, region: .jp, now: now).tag == "sem QR")

        let passport = WalletItem(kind: .passport, name: "Passaporte", detail: "só no aparelho",
                                  validUntil: try Self.day("2031-06-10"), attachmentName: "foto.jpg")
        let facts = WalletDocumentFacts.make(passport, region: .jp, now: now)
        #expect(facts.subtitle == "só no aparelho · válido até 2031")
        #expect(facts.badge == "IMG")
        #expect(facts.emphasis == nil)
    }

    // MARK: Documentos protegidos

    @Test func walletDocumentsAreWrittenWithCompleteProtection() throws {
        // Toda gravação de documento usa a opção de proteção completa.
        #expect(TicketFiles.writeOptions.contains(.completeFileProtection))
        let name = try TicketFiles.save(Data("passaporte".utf8), ext: "pdf")
        defer { TicketFiles.remove(name) }
        let path = try TicketFiles.url(for: name).path(percentEncoded: false)
        #expect(FileManager.default.fileExists(atPath: path))
        // No simulador (APFS do Mac) o sistema não reporta a classe de proteção: só checa quando reporta.
        if let protection = try FileManager.default.attributesOfItem(atPath: path)[.protectionKey] as? FileProtectionType {
            #expect(protection == .complete)
        }
    }
}
