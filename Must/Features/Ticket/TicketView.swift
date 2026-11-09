import CoreLocation
import PDFKit
import QuickLook
import SwiftData
import SwiftUI

/// Ingresso (V9, prompt 32 Fase 2): lista nativa com data/hora, QR (abre grande), confirmação, pago, cancelamento, ponto de
/// encontro e "Ir ao encontro" / "Ver o dia". QR e PDF ficam no aparelho: abre sem internet.
struct TicketView: View {
    let placeId: String
    let ticketId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Query private var matches: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]

    @State private var bigQR = false
    @State private var editing = false
    @State private var pdfPreview: URL?
    @State private var qrImage: UIImage?
    @State private var pdfThumb: UIImage?

    init(placeId: String, ticketId: String) {
        self.placeId = placeId
        self.ticketId = ticketId
        _matches = Query(filter: #Predicate<Place> { $0.id == placeId })
    }

    private var region: Region { store.region }

    var body: some View {
        if let place = matches.first, let ticket = place.tickets.first(where: { $0.id == ticketId }) {
            content(place, ticket)
        } else {
            ContentUnavailableView {
                Label("Esse ingresso saiu do board", systemImage: "ticket")
            } actions: {
                Button("Voltar") { dismiss() }.v9Secondary()
            }
            .v9Screen(grouped: true)
        }
    }

    private func content(_ place: Place, _ ticket: Ticket) -> some View {
        List {
            Section { heading(place, ticket) }
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(KindLines.weekdayDay(ticket.at, region: region)) · \(region.monthShort(ticket.at))")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(region.timeString(ticket.at)).font(.system(.largeTitle, design: .default).weight(.bold)).monospacedDigit()
                            arriveLine(place, ticket)
                        }
                        Spacer(minLength: 8)
                        qrBox(ticket)
                    }
                }
                .padding(.vertical, 4)
                if ticket.qrPayload != nil {
                    Button { bigQR = true } label: { Label("Mostrar QR grande", systemImage: "qrcode") }
                }
                if let name = ticket.pdfName, let url = try? TicketFiles.url(for: name) {
                    Button { pdfPreview = url } label: { Label("Abrir PDF", systemImage: "doc.text") }
                }
                if let wallet = ticket.walletPassURL {
                    Link(destination: wallet) { Label("Adicionar ao Wallet", systemImage: "wallet.pass") }
                }
            }
            Section("Detalhes") {
                LabeledContent("Confirmação") { Text(ticket.confirmation ?? "—").font(.body.weight(.semibold)).monospacedDigit().textSelection(.enabled) }
                LabeledContent("Pago") { paidLine(place, ticket).multilineTextAlignment(.trailing) }
                LabeledContent("Cancelamento") {
                    Text(ticket.cancelUntil.map { "grátis até \(region.shortDay($0)) · \(region.timeString($0))" } ?? "sem cancelamento grátis")
                        .multilineTextAlignment(.trailing)
                }
            }
            meetingSection(place)
        }
        .navigationTitle("Ingresso")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { V9OfflineChip() }
            ToolbarItem(placement: .topBarTrailing) { Button("Editar") { editing = true } }
        }
        .safeAreaInset(edge: .bottom) { actionBar(place, ticket) }
        .v9Screen(grouped: true)
        .task(id: ticket) { loadImages(ticket) }
        .sheet(isPresented: $editing) {
            TicketEditor(ticket: ticket, sessions: place.extra?.sessions ?? [], region: region, placeName: place.name,
                         onSave: { update($0, on: place) },
                         onRemove: {
                             TicketFiles.remove(ticket.pdfName)
                             var list = place.tickets
                             list.removeAll { $0.id == ticket.id }
                             place.tickets = list
                             try? context.save()
                             dismiss()
                         })
        }
        .fullScreenCover(isPresented: $bigQR) {
            BigQRView(payload: ticket.qrPayload ?? "", confirmation: ticket.confirmation)
        }
        .quickLookPreview($pdfPreview)
    }

    // MARK: Cabeçalho

    private func heading(_ place: Place, _ ticket: Ticket) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(place.list?.displayName ?? "Must") · \(place.kind == .experience ? "Experiência" : "ingresso")")
                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            Text(place.name).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            if let local = place.nameLocal { Text("\(local) · mostre ao atendente").font(.subheadline).foregroundStyle(.secondary) }
            Text(ticket.confirmation == nil ? "Âncora do dia" : "Confirmado · âncora de \(KindLines.weekdayDay(ticket.at, region: region))")
                .font(.subheadline.weight(.semibold)).foregroundStyle(V9.accent)
            let meta = Self.metaParts(place)
            if !meta.isEmpty { Text(meta.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .combine)
    }

    private static func metaParts(_ place: Place) -> [String] {
        guard let info = place.extra?.experience else { return [] }
        var parts: [String] = []
        if info.supplier != .other { parts.append(info.supplier.label) }
        if let d = info.durationMinutes { parts.append(KindLines.duration(d)) }
        if let g = info.groupMax { parts.append("grupo até \(g)") }
        if !info.languages.isEmpty { parts.append(info.languages.joined(separator: ", ")) }
        return parts
    }

    /// "chegar 09:45 · saia de Naka-Meguro 09:12" (15 min antes; saída pelo trajeto a pé/metrô do aparelho).
    private func arriveLine(_ place: Place, _ ticket: Ticket) -> some View {
        let arrive = ticket.at.addingTimeInterval(-15 * 60)
        var line = Text("chegar ").foregroundStyle(.secondary) + Text(region.timeString(arrive)).fontWeight(.semibold).foregroundStyle(.primary)
        if let here = services.location.current?.coordinate {
            let meeting = place.extra?.experience?.meetingCoordinate.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? place.coordinate
            let walkMax = settingsList.first?.walkMaxKm ?? 1.5
            let leg = DaySolver.leg(here, meeting, walkMax: walkMax)
            let leave = RoutesService.leaveAt(arrive, travelMinutes: leg.minutes)
            let home = trips.first?.home ?? "aqui"
            line = line + Text(" · saia de \(home) ").foregroundStyle(.secondary)
                + Text(region.timeString(leave)).fontWeight(.semibold).foregroundStyle(V9.accent)
        }
        return line.font(.subheadline).monospacedDigit().fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func qrBox(_ ticket: Ticket) -> some View {
        if let image = qrImage ?? pdfThumb {
            Button { if qrImage != nil { bigQR = true } else { pdfPreviewOpen(ticket) } } label: {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .padding(8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(V9.separator))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(qrImage != nil ? "Mostrar QR grande" : "Abrir PDF")
        }
    }

    private func pdfPreviewOpen(_ ticket: Ticket) {
        if let name = ticket.pdfName { pdfPreview = try? TicketFiles.url(for: name) }
    }

    private func paidLine(_ place: Place, _ ticket: Ticket) -> Text {
        guard let paid = ticket.paid else { return Text("—") }
        var t = Text(region.money(paid)).fontWeight(.semibold)
        if let people = ticket.people, people > 1 {
            t = t + Text(" · \(people) × \(region.money(paid / Double(people), symbol: false))").foregroundStyle(.secondary)
        }
        if place.allowBudgetException {
            t = t + Text(" · exceção aceita").foregroundStyle(.secondary)
        }
        return t.monospacedDigit()
    }

    // MARK: Ponto de encontro

    private func meetingSection(_ place: Place) -> some View {
        let info = place.extra?.experience
        let meeting = info?.meetingCoordinate.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? place.coordinate
        return Section("Ponto de encontro") {
            LabeledContent(place.area ?? "Local") { Text(info?.meetingPoint ?? place.area ?? "—").multilineTextAlignment(.trailing) }
            if let here = services.location.current?.coordinate {
                let leg = DaySolver.leg(here, meeting, walkMax: settingsList.first?.walkMaxKm ?? 1.5)
                LabeledContent("Como chegar") { Text("\(leg.mode == .walk ? "a pé" : "metrô") · \(leg.minutes) min").monospacedDigit() }
            }
            if let url = info?.url {
                Link(destination: url) { Label("\(info?.supplier.label ?? "Fornecedor") · ver reserva", systemImage: "arrow.up.right.square") }
            }
        }
    }

    // MARK: Ações

    private func actionBar(_ place: Place, _ ticket: Ticket) -> some View {
        let meeting = place.extra?.experience?.meetingCoordinate
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { actionButtons(place, ticket, meeting: meeting != nil) }
            VStack(spacing: 10) { actionButtons(place, ticket, meeting: meeting != nil) }
        }
        .padding(.horizontal, V9.gutter)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    @ViewBuilder private func actionButtons(_ place: Place, _ ticket: Ticket, meeting: Bool) -> some View {
        Button {
            // Como chegar ao ponto de encontro (ou ao lugar, sem ponto marcado).
            router.push(.comoChegar(placeId: place.id, meeting: meeting), on: router.tab)
        } label: { Label("Ir ao encontro", systemImage: "figure.walk").frame(maxWidth: .infinity) }
            .v9Primary()
        Button {
            router.push(.day(date: region.calendar.startOfDay(for: ticket.at)), on: router.tab)
        } label: { Text("Ver o dia").frame(maxWidth: .infinity) }
            .v9Secondary()
    }

    // MARK: Imagens

    /// QR do texto; sem texto, a primeira página do PDF.
    private func loadImages(_ ticket: Ticket) {
        qrImage = ticket.qrPayload.flatMap { TicketQR.image(for: $0) }
        pdfThumb = nil
        if qrImage == nil, let name = ticket.pdfName, let url = try? TicketFiles.url(for: name),
           let page = PDFDocument(url: url)?.page(at: 0) {
            pdfThumb = page.thumbnail(of: CGSize(width: 220, height: 220), for: .mediaBox)
        }
    }

    private func update(_ updated: Ticket, on place: Place) {
        var list = place.tickets
        if let i = list.firstIndex(where: { $0.id == updated.id }) { list[i] = updated } else { list.append(updated) }
        place.tickets = list
        place.syncBoughtSessions()
        try? context.save()
    }
}

/// QR em tela cheia, com brilho no máximo enquanto está aberto (a leitora na porta).
/// Também usado pela Carteira (QR de entrada e passe).
struct BigQRView: View {
    let payload: String
    let confirmation: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 28) {
            HStack {
                Spacer()
                Button("Fechar") { dismiss() }.v9Secondary()
            }
            Spacer()
            if let image = TicketQR.image(for: payload, points: 320) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300, height: 300)
            }
            if let confirmation {
                Text(confirmation).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.black)
            }
            Spacer()
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .modifier(MaxBrightness())
    }
}

/// Brilho máximo enquanto a tela estiver aberta; volta ao valor de antes ao fechar.
private struct MaxBrightness: ViewModifier {
    @State private var saved: CGFloat?

    @MainActor private static var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                saved = Self.screen?.brightness
                Self.screen?.brightness = 1
            }
            .onDisappear {
                if let saved { Self.screen?.brightness = saved }
            }
    }
}
