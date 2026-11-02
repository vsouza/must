import CoreLocation
import Foundation
import SwiftData

/// Campos da conferência, na ordem da tela. A confiança e a origem de cada um vêm do extrator.
enum TicketField: String, CaseIterable, Sendable {
    case supplier, title, when, people, price, confirmation, meeting, cancel
}

/// Confiança (0–1) e de onde veio o valor. Editar à mão põe 1 e "à mão".
struct FieldMeta: Equatable, Sendable {
    var confidence: Double
    var origin: String
    var needsReview: Bool { confidence < ExtractedTicket.reviewBelow }
}

/// O ingresso em conferência: sai da leitura (ou de "À mão") e vira `Ticket` + sessão só no "Salvar".
struct TicketDraft: Equatable, Sendable {
    enum Attachment: Equatable, Sendable {
        /// Bytes ainda fora de `TicketFiles`: só entram no "Salvar".
        case pending(Data, ext: String)
        /// Já guardado (anexado à mão no `TicketEditor`).
        case stored(String)
    }

    var kind: TicketKind = .other
    var title = ""
    var supplier = ""
    var at: Date
    var people = 1
    var price: Double?
    var currency: String?
    var confirmation = ""
    var qrPayload = ""
    var meetingPoint = ""
    var cancelUntil: Date?
    var legs: [FlightLeg] = []
    var attachment: Attachment?
    var meta: [TicketField: FieldMeta] = [:]
    var sourceLabel = ""
    var budgetException = false

    init(at: Date) { self.at = at }

    /// Rascunho a partir do que o extrator leu. Campo que não veio fica vazio, com confiança zero (pede conferência).
    init(_ e: ExtractedTicket, region: Region, now: Date, sourceLabel: String) {
        self.init(at: e.at?.value ?? Self.nextHour(region: region, now: now))
        kind = e.kind
        self.sourceLabel = sourceLabel
        legs = e.legs
        if let title = e.title { self.title = title.value; meta[.title] = FieldMeta(confidence: title.confidence, origin: title.origin) }
        if let supplier = e.supplier { self.supplier = supplier.value; meta[.supplier] = FieldMeta(confidence: supplier.confidence, origin: supplier.origin) }
        if let at = e.at { meta[.when] = FieldMeta(confidence: at.confidence, origin: at.origin) }
        if let people = e.people { self.people = people.value; meta[.people] = FieldMeta(confidence: people.confidence, origin: people.origin) }
        if let price = e.price { self.price = price.value; meta[.price] = FieldMeta(confidence: price.confidence, origin: price.origin) }
        currency = e.currency?.value
        if let code = e.confirmation { confirmation = code.value; meta[.confirmation] = FieldMeta(confidence: code.confidence, origin: code.origin) }
        if let qr = e.qrPayload { qrPayload = qr.value }
        if let meeting = e.meetingPoint { meetingPoint = meeting.value; meta[.meeting] = FieldMeta(confidence: meeting.confidence, origin: meeting.origin) }
        if let cancel = e.cancelUntil { cancelUntil = cancel.value; meta[.cancel] = FieldMeta(confidence: cancel.confidence, origin: cancel.origin) }
    }

    /// Ingresso à mão: tudo que o usuário digitou é 100% (origem "à mão").
    init(manual ticket: Ticket, region: Region, now: Date) {
        self.init(at: ticket.at)
        confirmation = ticket.confirmation ?? ""
        qrPayload = ticket.qrPayload ?? ""
        people = ticket.people ?? 1
        price = ticket.paid
        currency = region.currency
        cancelUntil = ticket.cancelUntil
        if let name = ticket.pdfName { attachment = .stored(name) }
        kind = .experience
        for field in [TicketField.when, .people, .price, .confirmation, .cancel] {
            meta[field] = FieldMeta(confidence: 1, origin: "à mão")
        }
    }

    static func nextHour(region: Region, now: Date) -> Date {
        let parts = region.calendar.dateComponents([.year, .month, .day, .hour], from: now)
        return (region.calendar.date(from: parts) ?? now).addingTimeInterval(3600)
    }
}

/// Lugar escolhido em "Vincular a": um que já está no board, ou um novo (lista Must do).
enum TicketTarget: Equatable, Sendable {
    case place(String)
    case new
}

@MainActor
@Observable
final class TicketImportModel {
    enum Step: Equatable { case entrada, scan, revisar }

    /// Uma linha do card "lendo" (texto lido · QR · campos · combinando com o board · conferir).
    struct ReadLine: Equatable, Sendable, Identifiable {
        var id: Int
        var done: Bool
        var text: String
    }

    /// O que o scanner viu (payloads e texto), em dados.
    struct ScanSnapshot: Equatable, Sendable {
        var codes: [String]
        var text: String
    }

    var step: Step = .entrada
    var draft: TicketDraft?
    var matches: [TicketMatch] = []
    var target: TicketTarget = .new
    var progress: [ReadLine] = []
    var isReading = false
    var error: String?
    /// Link recebido (ou colado) que só é lido quando o usuário pede.
    var pendingURL: URL?
    /// Preview do que o scanner encontrou ("Encontrei: …").
    var scanPreview: String?
    var scanned: ScanSnapshot?
    /// Item da caixa do Share Extension que está aberto (apagado ao salvar ou ao descartar).
    private(set) var inboxId: String?
    private(set) var saved = false

    private var context: ModelContext?
    private var region: Region = .bh
    private var provider: (any PlacesProviding)?
    /// Coordenada e id do Places do ingresso (quando a busca conferiu o ponto de encontro).
    private var candidate: TicketCandidate?

    /// Liga o modelo ao container e ao Places (a tela chama uma vez).
    func configure(context: ModelContext, region: Region, provider: any PlacesProviding) {
        self.context = context
        self.region = region
        self.provider = provider
    }

    // MARK: Entradas

    /// Item da caixa do Share Extension (`must://import?id=`).
    func loadInbox(id: String) async {
        guard inboxId == nil, let item = ShareInbox.item(id: id) else {
            if inboxId == nil { error = "Esse item já saiu da caixa." }
            return
        }
        inboxId = id
        if item.kind == .url {
            useLink(TicketReader.readText(item.text ?? ""))
            return
        }
        do {
            let source = try TicketReader.source(for: item)
            await read(source)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Foto, PDF, .pkpass (Fotos, Arquivo, colar um arquivo).
    func read(_ source: TicketSource) async {
        error = nil
        await withReadingCard {
            let reading = try await TicketReader.read(source)
            await self.finish(reading, source: source)
        }
    }

    /// Texto colado: link (guardado pra ler depois) ou código/texto.
    func readPasted(_ text: String) async {
        error = nil
        let reading = TicketReader.readText(text)
        if reading.url != nil {
            useLink(reading)
            return
        }
        await finish(reading, source: .text(text))
    }

    /// O usuário mandou ler a página do link.
    func readLink() async {
        guard let url = pendingURL else { return }
        error = nil
        await withReadingCard {
            let reading = try await TicketReader.readPage(url)
            await self.finish(reading, source: nil)
        }
    }

    /// Scanner: payloads e texto do que a câmera reconheceu.
    func scanUpdated(_ snapshot: ScanSnapshot) {
        scanned = snapshot
        let reading = TicketReading(text: snapshot.text, codes: snapshot.codes, codePages: snapshot.codes.map { _ in 1 },
                                    pages: 1, sourceLabel: "Câmera")
        let e = TicketExtractor.extract(reading, region: region)
        let parts = [e.title?.value ?? e.supplier?.value ?? snapshot.codes.first,
                     e.at.map { region.shortDayTime($0.value) }, e.people.map { "\($0.value) pessoas" }].compactMap { $0 }
        scanPreview = parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Conferir e salvar" no scanner.
    func scannedConfirm() async {
        guard let scanned else { return }
        error = nil
        await finish(TicketReading(text: scanned.text, codes: scanned.codes, codePages: scanned.codes.map { _ in 1 }, pages: 1,
                                   sourceLabel: "Câmera"), source: nil)
    }

    /// "À mão" (TicketEditor): já vem como `Ticket` com o arquivo guardado.
    func manual(_ ticket: Ticket) {
        draft = TicketDraft(manual: ticket, region: region, now: AppClock.now)
        progress = []
        pendingURL = nil
        error = nil
        step = .revisar
        Task { await refreshMatches() }
    }

    // MARK: Leitura

    private func useLink(_ reading: TicketReading) {
        pendingURL = reading.url
        progress = [ReadLine(id: 0, done: true, text: "Link recebido · \(reading.url?.host() ?? "")"),
                    ReadLine(id: 1, done: false, text: "Ler a página (só se você mandar)")]
    }

    /// Roda a leitura mostrando o card "lendo" e trata o erro como mensagem.
    private func withReadingCard(_ work: () async throws -> Void) async {
        isReading = true
        progress = []
        defer { isReading = false }
        do {
            try await work()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Texto → extrator → confere no Places → casa com o board → vai pra conferência.
    private func finish(_ reading: TicketReading, source: TicketSource?) async {
        progress = [ReadLine(id: 0, done: true, text: "Texto lido · \(reading.sourceLabel)")]
        if !reading.codes.isEmpty {
            let pages = reading.codePages.first.map { "na página \($0)" } ?? ""
            progress.append(ReadLine(id: 1, done: true, text: "QR encontrado \(pages)".trimmingCharacters(in: .whitespaces)))
        }
        var extracted = TicketExtractor.extract(reading, region: region)
        progress.append(ReadLine(id: 2, done: true, text: "Data, hora, pessoas e preço · no aparelho"))
        extracted = await TicketModelExtractor.enrich(extracted, text: reading.text)
        progress.append(ReadLine(id: 3, done: false, text: "Combinando com o board…"))

        candidate = await candidate(for: extracted)
        var next = TicketDraft(extracted, region: region, now: AppClock.now, sourceLabel: reading.sourceLabel)
        if let source, let ext = source.fileExtension, let data = source.fileData {
            next.attachment = .pending(data, ext: ext)
        }
        draft = next
        pendingURL = reading.url
        await refreshMatches()
        progress = progress.map { var line = $0; line.done = true; return line }
        progress.append(ReadLine(id: 4, done: false, text: "Conferir e salvar"))
        step = .revisar
    }

    /// Ingresso com o que se sabe pra casar: título, ponto de encontro e, se o Places conferir, placeId e coordenada.
    private func candidate(for e: ExtractedTicket) async -> TicketCandidate {
        let title = e.title?.value ?? e.supplier?.value ?? ""
        let address = e.meetingPoint?.value
        var out = TicketCandidate(title: title, placeId: nil, lat: nil, lng: nil, address: address)
        let query = address ?? (title.isEmpty ? nil : title)
        guard let provider, provider.isConfigured, DevOverrides.liveData, let query else { return out }
        let center = region.defaultCenter
        if let results = try? await provider.searchText(query, near: center, radius: 5_000, languageCode: "pt-BR"),
           let hit = PlaceResolver.pick(results, for: query) ?? results.first {
            out.placeId = hit.id
            out.lat = hit.lat
            out.lng = hit.lng
            out.address = address ?? hit.address
        }
        return out
    }

    /// Recalcula os lugares do board que podem ser este ingresso e escolhe o de maior confiança (≥ 0,8).
    func refreshMatches() async {
        guard let context, let candidate else {
            matches = []
            target = .new
            return
        }
        let places = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        matches = TicketMatcher.rank(candidate, places: places)
        if let best = matches.first(where: { $0.score >= TicketMatcher.autoLinkScore }) {
            target = .place(best.placeId)
        } else {
            target = .new
        }
    }

    // MARK: Conferência

    /// Campo editado à mão: vale 100%.
    func edit(_ field: TicketField, _ change: (inout TicketDraft) -> Void) {
        guard draft != nil else { return }
        change(&draft!)
        draft!.meta[field] = FieldMeta(confidence: 1, origin: "à mão")
    }

    /// Pode salvar? Lugar precisa de título; trem e QR de entrada vão pra Carteira (título opcional).
    var canSave: Bool {
        guard let draft, !isNotYetSupported else { return false }
        if isWalletKind { return true }
        return !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Voo fica pra fatia 6 (Voos): nada é salvo daqui ainda.
    var isNotYetSupported: Bool {
        draft?.kind == .flight
    }

    /// Trem e QR de entrada não viram lugar do board: vão pra Carteira (`WalletItem`).
    var isWalletKind: Bool {
        WalletFromTicket.kind(for: draft?.kind ?? .other) != nil
    }

    var notYetMessage: String? {
        switch draft?.kind {
        case .flight: "Voo: a tela Voos entra na fatia 6 (TODO). Nada foi salvo."
        default: nil
        }
    }

    /// Lugar escolhido agora (nil = lugar novo).
    var chosenMatch: TicketMatch? {
        guard case .place(let id) = target else { return nil }
        return matches.first { $0.placeId == id }
    }

    /// Grava: arquivo em `TicketFiles`, sessão no lugar (ou lugar novo em "Must do") e o `Ticket`. Nada antes disso.
    /// Trem e QR de entrada gravam um `WalletItem` (Carteira) no lugar disso.
    func save() throws {
        guard let context, let draft, canSave else { throw TicketImportError.incomplete }
        if let kind = WalletFromTicket.kind(for: draft.kind) {
            try saveToWallet(draft, kind: kind, context: context)
            return
        }
        let pdfName = try storeAttachment(draft.attachment, keepPasses: true)
        do {
            let place = try resolvePlace(context: context, draft: draft)
            let sameCurrency = draft.currency.map { $0 == region.currency } ?? true
            let paid = sameCurrency ? draft.price : nil
            let session = EventSession(at: draft.at, title: draft.title, price: paid, bought: true,
                                       note: draft.confirmation.isEmpty ? nil : draft.confirmation)
            Self.attach(session, to: place, draft: draft)
            let ticket = Ticket(at: draft.at, sessionId: session.id,
                                confirmation: draft.confirmation.isEmpty ? nil : draft.confirmation,
                                qrPayload: draft.qrPayload.isEmpty ? nil : draft.qrPayload,
                                pdfName: pdfName, paid: paid, people: draft.people, cancelUntil: draft.cancelUntil)
            place.tickets = place.tickets + [ticket]
            place.syncBoughtSessions()
            if draft.budgetException { place.allowBudgetException = true }
            try context.save()
        } catch {
            // Se o banco não gravou, o arquivo novo não fica órfão.
            if case .pending = draft.attachment { TicketFiles.remove(pdfName) }
            throw error
        }
        saved = true
        if let inboxId { ShareInbox.remove(id: inboxId) }
    }

    /// O anexo entra em `TicketFiles` (PDF, foto). `.pkpass` não é guardado na Carteira: o QR já vai como texto.
    private func storeAttachment(_ attachment: TicketDraft.Attachment?, keepPasses: Bool) throws -> String? {
        switch attachment {
        case .pending(_, let ext) where ext == "pkpass" && !keepPasses: return nil
        case .pending(let data, let ext): return try TicketFiles.save(data, ext: ext)
        case .stored(let name): return name
        case nil: return nil
        }
    }

    /// Trem ou QR de entrada: um `WalletItem` no container da região. Nada vai pro board.
    private func saveToWallet(_ draft: TicketDraft, kind: WalletKind, context: ModelContext) throws {
        let attachment = try storeAttachment(draft.attachment, keepPasses: false)
        do {
            let order = (try? context.fetchCount(FetchDescriptor<WalletItem>())) ?? 0
            context.insert(WalletFromTicket.item(from: draft, kind: kind, attachmentName: attachment, order: order, now: AppClock.now))
            try context.save()
        } catch {
            // Se o banco não gravou, o arquivo novo não fica órfão.
            TicketFiles.remove(attachment)
            throw error
        }
        saved = true
        if let inboxId { ShareInbox.remove(id: inboxId) }
    }

    /// Fechar a tela sem salvar: o item da caixa sai (o usuário viu e recusou).
    func discard() {
        guard !saved, let inboxId else { return }
        ShareInbox.remove(id: inboxId)
    }

    private func resolvePlace(context: ModelContext, draft: TicketDraft) throws -> Place {
        if case .place(let id) = target {
            let descriptor = FetchDescriptor<Place>(predicate: #Predicate { $0.id == id })
            if let existing = try context.fetch(descriptor).first { return existing }
        }
        let lists = try context.fetch(FetchDescriptor<MustList>(sortBy: [SortDescriptor(\.order)]))
        let list: MustList
        if let experience = lists.first(where: { $0.kind == .experience }) {
            list = experience
        } else {
            list = MustList(id: "exp", name: "do", icon: .mustsLista, color: .night, order: (lists.map(\.order).max() ?? 0) + 1, kind: .experience)
            context.insert(list)
        }
        let trip = try context.fetch(FetchDescriptor<TripInfo>()).first
        let cityId = trip?.city(on: draft.at, calendar: region.calendar)?.id ?? trip?.cities.first?.id ?? (region == .jp ? "tokyo1" : "bh")
        let center = region.defaultCenter
        let coordinate: CLLocationCoordinate2D? = {
            guard let lat = candidate?.lat, let lng = candidate?.lng else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }()
        let place = Place(id: "t-\(UUID().uuidString.prefix(8).lowercased())", name: draft.title, cityId: cityId,
                          lat: coordinate?.latitude ?? center.latitude, lng: coordinate?.longitude ?? center.longitude)
        place.approx = coordinate == nil
        place.placeId = candidate?.placeId
        place.list = list
        place.order = (list.places.map(\.order).max() ?? 0) + 1
        context.insert(place)
        return place
    }

    /// A sessão vai pro painel do tipo do lugar (experiência por padrão). Mesma sessão não entra duas vezes.
    private static func attach(_ session: EventSession, to place: Place, draft: TicketDraft) {
        var extra = place.extra ?? PlaceExtra()
        switch place.kind {
        case .art:
            var art = extra.art ?? ArtEvent()
            if !art.sessions.contains(where: { $0.id == session.id }) { art.sessions.append(session) }
            extra.art = art
        case .sport:
            var sport = extra.sport ?? SportSpot()
            if !sport.sessions.contains(where: { $0.id == session.id }) { sport.sessions.append(session) }
            extra.sport = sport
        default:
            var experience = extra.experience ?? ExperienceInfo(supplier: supplier(draft.supplier),
                                                                 meetingPoint: draft.meetingPoint.isEmpty ? nil : draft.meetingPoint)
            if !experience.sessions.contains(where: { $0.id == session.id }) { experience.sessions.append(session) }
            extra.experience = experience
        }
        place.extra = extra
    }

    private static func supplier(_ name: String) -> ExperienceSupplier {
        switch name.lowercased() {
        case "viator": .viator
        case "getyourguide": .getYourGuide
        case "klook": .klook
        case "airbnb": .airbnb
        default: .other
        }
    }
}

enum TicketImportError: LocalizedError, Equatable {
    case incomplete

    var errorDescription: String? {
        switch self {
        case .incomplete: "Falta o título do ingresso."
        }
    }
}
