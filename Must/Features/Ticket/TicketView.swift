import CoreLocation
import PDFKit
import QuickLook
import SwiftData
import SwiftUI

/// Ingresso (prompt 14 · C · 11): card preto com recorte, QR, PDF, ponto de encontro e "Ir ao encontro" / "Ver o dia".
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
            VStack(spacing: 12) {
                Text("Esse ingresso saiu do board.").mustBody()
                GhostButton("Voltar") { dismiss() }.frame(width: 160)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func content(_ place: Place, _ ticket: Ticket) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                heading(place, ticket).padding(.top, 18)
                ticketCard(place, ticket).padding(.top, 26)
                meetingCard(place).padding(.top, 30)
                Color.clear.frame(height: 230)
            }
            .padding(.horizontal, 22)
        }
        .scrollIndicators(.hidden)
        .background {
            ZStack {
                Color.must.bg
                BlobBackground(style: .custom([
                    Blob(cx: 350, cy: 110, rx: 110, ry: 80, rotation: -18, fill: .blue, opacity: 0.85),
                    Blob(cx: 0, cy: 300, rx: 60, ry: 45, rotation: 10, fill: .green),
                ]))
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .bottom) { actionBar(place, ticket) }
        .toolbar(.hidden, for: .navigationBar)
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

    // MARK: Topo e cabeçalho

    private var topBar: some View {
        HStack {
            IconButton(.voltar, style: .glass, label: "Voltar") { dismiss() }
            Spacer()
            IconButton(.editar, style: .glass, label: "Editar ingresso") { editing = true }
        }
        .padding(.top, 8)
    }

    private func heading(_ place: Place, _ ticket: Ticket) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 6) {
                Tag("\(place.list?.displayName ?? "Must") · \(place.kind == .experience ? "Experiência" : "ingresso")", style: .dark)
                Tag(ticket.confirmation == nil ? "âncora do dia" : "confirmado · âncora de \(KindLines.weekdayDay(ticket.at, region: region))",
                    style: .green)
                if let supplier = place.extra?.experience?.supplier, supplier != .other { Tag(supplier.label) }
            }
            Text(place.name).mustTitle()
            if let local = place.nameLocal { Text(local).mustSerif(18).foregroundStyle(Color.must.secondary) }
            let meta = [
                place.extra?.experience?.durationMinutes.map(KindLines.duration),
                place.extra?.experience?.groupMax.map { "grupo até \($0)" },
                place.extra?.experience?.languages.isEmpty == false ? place.extra?.experience?.languages.joined(separator: ", ") : nil,
            ].compactMap { $0 }
            if !meta.isEmpty { Text(meta.joined(separator: " · ")).mustMeta() }
        }
    }

    // MARK: Ingresso

    private func ticketCard(_ place: Place, _ ticket: Ticket) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Micro("\(KindLines.weekdayDay(ticket.at, region: region)) · \(region.monthShort(ticket.at))", color: .white.opacity(0.6))
                    MonoNumber(region.timeString(ticket.at), size: 46).foregroundStyle(.white)
                    arriveLine(place, ticket)
                }
                Spacer(minLength: 8)
                qrBox(ticket)
            }
            dashedLine.padding(.vertical, 20)
            VStack(spacing: 14) {
                stubRow("Confirmação") {
                    Text(ticket.confirmation ?? "—").font(.must.mono(15, .semibold)).foregroundStyle(.white)
                }
                stubRow("Pago") { paidLine(place, ticket) }
                stubRow("Cancelamento") {
                    Text(ticket.cancelUntil.map { "grátis até \(region.shortDay($0)) · \(region.timeString($0))" } ?? "sem cancelamento grátis")
                        .font(.must.archivo(14, .semibold)).foregroundStyle(.white)
                }
            }
            HStack(spacing: 8) {
                if ticket.qrPayload != nil {
                    stubButton("Mostrar QR grande", filled: true) { bigQR = true }
                }
                if let name = ticket.pdfName, let url = try? TicketFiles.url(for: name) {
                    stubButton("Abrir PDF", filled: false) { pdfPreview = url }
                }
                if let wallet = ticket.walletPassURL {
                    Link(destination: wallet) {
                        Text("+ Wallet").font(.must.archivo(13, .semibold)).foregroundStyle(Color.must.ink)
                            .padding(.horizontal, 12).frame(height: 36).background(Capsule().fill(.white))
                    }
                }
            }
            .padding(.top, 22)
        }
        .padding(22)
        .background(Color.must.ink, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .leading) { notch.offset(x: -13) }
        .overlay(alignment: .trailing) { notch.offset(x: 13) }
        .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
        .rotationEffect(.degrees(-1.2))
    }

    /// Recorte lateral do ingresso (a cor da página).
    private var notch: some View {
        Circle().fill(Color.must.bg).frame(width: 26, height: 26)
    }

    private var dashedLine: some View {
        DashedLine()
            .stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(height: 1)
    }

    /// "chegar 09:45 · saia de Naka-Meguro 09:12" (15 min antes; saída pelo trajeto a pé/metrô do aparelho).
    private func arriveLine(_ place: Place, _ ticket: Ticket) -> some View {
        let arrive = ticket.at.addingTimeInterval(-15 * 60)
        var line = Text("chegar ").foregroundStyle(.white.opacity(0.75))
            + Text(region.timeString(arrive)).fontWeight(.semibold).foregroundStyle(.white)
        if let here = services.location.current?.coordinate {
            let meeting = place.extra?.experience?.meetingCoordinate.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? place.coordinate
            let walkMax = settingsList.first?.walkMaxKm ?? 1.5
            let leg = DaySolver.leg(here, meeting, walkMax: walkMax)
            let leave = RoutesService.leaveAt(arrive, travelMinutes: leg.minutes)
            let home = trips.first?.home ?? "aqui"
            line = line + Text(" · saia de \(home) ").foregroundStyle(.white.opacity(0.75))
                + Text(region.timeString(leave)).foregroundStyle(Color.must.green).fontWeight(.semibold)
        }
        return line.font(.must.archivo(13)).fixedSize(horizontal: false, vertical: true)
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
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(MustPressStyle())
            .accessibilityLabel(qrImage != nil ? "Mostrar QR grande" : "Abrir PDF")
        }
    }

    private func pdfPreviewOpen(_ ticket: Ticket) {
        if let name = ticket.pdfName { pdfPreview = try? TicketFiles.url(for: name) }
    }

    private func paidLine(_ place: Place, _ ticket: Ticket) -> Text {
        guard let paid = ticket.paid else { return Text("—").font(.must.mono(15, .semibold)).foregroundStyle(.white) }
        var t = Text(region.money(paid)).font(.must.mono(15, .semibold)).foregroundStyle(.white)
        if let people = ticket.people, people > 1 {
            t = t + Text(" · \(people) × \(region.money(paid / Double(people), symbol: false))")
                .font(.must.mono(13)).foregroundStyle(.white.opacity(0.75))
        }
        if place.allowBudgetException {
            t = t + Text(" · exceção aceita").font(.must.archivo(13, .semibold)).foregroundStyle(Color(hex: 0x9FD6FF))
        }
        return t
    }

    private func stubRow<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.must.archivo(13)).foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 8)
            value().multilineTextAlignment(.trailing)
        }
    }

    private func stubButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.must.archivo(13, .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).frame(height: 36)
                .background(Capsule().fill(filled ? Color.white.opacity(0.16) : Color.white.opacity(0.08)))
        }
        .buttonStyle(MustPressStyle())
    }

    // MARK: Ponto de encontro

    private func meetingCard(_ place: Place) -> some View {
        let info = place.extra?.experience
        let meeting = info?.meetingCoordinate.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? place.coordinate
        return VStack(spacing: 0) {
            FormRow("Ponto de encontro", subtitle: place.area) {
                Text(info?.meetingPoint ?? place.area ?? "—").font(.must.archivo(15, .semibold)).multilineTextAlignment(.trailing)
            }
            if let here = services.location.current?.coordinate {
                RowDivider()
                let leg = DaySolver.leg(here, meeting, walkMax: settingsList.first?.walkMaxKm ?? 1.5)
                FormRow("Como chegar") {
                    Text("\(leg.mode == .walk ? "a pé" : "metrô") · \(leg.minutes) min").font(.must.archivo(15, .semibold))
                }
            }
            if let url = info?.url {
                RowDivider()
                FormRow("Fornecedor") {
                    Link(destination: url) {
                        Text("\(info?.supplier.label ?? "Fornecedor") · ver reserva ↗")
                            .font(.must.archivo(15, .semibold)).foregroundStyle(Color.must.link)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .card(cornerRadius: 26)
    }

    // MARK: Ações

    private func actionBar(_ place: Place, _ ticket: Ticket) -> some View {
        let meeting = place.extra?.experience?.meetingCoordinate
        return HStack(spacing: 10) {
            PrimaryButton("Ir ao encontro", icon: .rota, style: .dark) {
                if let meeting {
                    MapsLinks.openApple(to: CLLocationCoordinate2D(latitude: meeting.lat, longitude: meeting.lng),
                                        name: place.extra?.experience?.meetingPoint ?? place.name, mode: .transit)
                } else {
                    MapsLinks.openApple(to: place.coordinate, name: place.name, mode: .transit)
                }
            }
            PrimaryButton("Ver o dia", style: .green) {
                router.push(.day(date: region.calendar.startOfDay(for: ticket.at)), on: router.tab)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 92)
        .background {
            LinearGradient(colors: [.white.opacity(0), .white.opacity(0.95), .white], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
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

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
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
                IconButton(.fechar, style: .glass, label: "Fechar") { dismiss() }
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
                Text(confirmation).font(.must.mono(20, .semibold)).foregroundStyle(Color.must.ink)
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
