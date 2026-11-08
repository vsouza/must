import SwiftData
import SwiftUI
import UIKit

/// Mandar o dia (prompt 25 · B, `Compartilhar.png`): o cartaz 9:16 (imagem pro WhatsApp), o link `must://d/…` que abre
/// o dia no app de quem tem (sem servidor: o dia vai dentro do link), o PDF da viagem (um dia por página) e o
/// "Viajar junto" (desabilitado: precisa de CloudKit). `date` nil = a viagem inteira (Viagem › Mandar a viagem).
/// Nada aqui chama rede; o cartaz é desenhado no aparelho.
struct MandarView: View {
    var date: Date?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(\.dayEngine) private var engine
    @Environment(\.modelContext) private var context

    @State private var options = PosterOptions()
    @State private var day: DayShareBuilder.Day?
    @State private var tripDays: [DayShareBuilder.Day] = []
    @State private var loaded = false
    @State private var posterURL: URL?
    @State private var pdfURL: URL?
    @State private var copied = false

    private let sharing: any TripSharing = UnavailableTripSharing()
    private var region: Region { store.region }
    private var isTrip: Bool { date == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.top, 8)
                if let day {
                    top(day).padding(.top, 22)
                    rows(day).padding(.top, 34)
                    mainButton.padding(.top, 30)
                } else if loaded {
                    empty.padding(.top, 34)
                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(V8.paper.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onAppear(perform: load)
        .task(id: RenderKey(options: options, day: day?.id, days: tripDays.count)) { await render() }
    }

    private struct RenderKey: Hashable {
        var options: PosterOptions
        var day: Date?
        var days: Int
    }

    private func load() {
        guard !loaded else { return }
        tripDays = DayShareBuilder.trip(region: region, context: context, engine: engine)
        if let date {
            day = DayShareBuilder.day(date, region: region, context: context, engine: engine)
        } else {
            // A viagem inteira: a prévia é o dia de hoje (se estiver na viagem) ou o primeiro.
            let today = region.calendar.startOfDay(for: AppClock.now)
            day = tripDays.first { $0.plan.date == today } ?? tripDays.first
        }
        loaded = true
    }

    /// Desenha o PNG e o PDF fora do `body` (o `ImageRenderer` roda no main, ~50 ms por dia).
    private func render() async {
        guard let day else { return }
        try? await Task.sleep(for: .milliseconds(120)) // toques seguidos nas opções viram um só desenho
        guard !Task.isCancelled else { return }
        if let png = DayPosterRenderer.png(day.poster, options: options) {
            posterURL = DayPosterRenderer.write(png, name: "Must · Dia \(day.poster.numeral) · \(day.poster.area).png")
        }
        await Task.yield()
        guard !Task.isCancelled else { return }
        let days = tripDays.isEmpty ? [day] : tripDays
        let pdf = DayPosterRenderer.pdf(days.map(\.poster), options: options)
        pdfURL = pdf.isEmpty ? nil : DayPosterRenderer.write(pdf, name: "Must · \(region.shortName) · \(days.count) dias.pdf")
    }

    // MARK: Topo

    private var header: some View {
        HStack(alignment: .top) {
            V8CornerButton(systemName: "xmark", label: "Fechar") { dismiss() }
            Spacer(minLength: 12)
            V8SpecStack(lines: ["Compartilhar", specLine], alignment: .trailing)
                .multilineTextAlignment(.trailing)
                .padding(.top, 6)
        }
    }

    private var specLine: String {
        if isTrip { return tripDays.count == 1 ? "a viagem · 1 dia" : "a viagem · \(tripDays.count) dias" }
        guard let day else { return DayText.dayLine(date ?? AppClock.now, region: region) }
        return "dia \(day.poster.numeral) · \(day.poster.area)"
    }

    private func top(_ day: DayShareBuilder.Day) -> some View {
        HStack(alignment: .top, spacing: 16) {
            preview(day)
            VStack(alignment: .leading, spacing: 8) {
                Text(isTrip ? "Mandar a viagem" : "Mandar o dia")
                    .font(V8Font.display(30))
                    .tracking(-0.6)
                    .foregroundStyle(V8.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Text("Quem tem o Must abre o roteiro no app. Quem não tem recebe o cartaz, bonito o bastante pro WhatsApp.")
                    .font(V8Font.text(13))
                    .foregroundStyle(V8.mute)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    check("com horários", $options.times)
                    check("com mapa do percurso", $options.map, enabled: day.poster.hasMap)
                    check("com preços", $options.prices)
                    check("com QR dos ingressos", $options.qr, enabled: !day.poster.qrs.isEmpty)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// O cartaz em miniatura (150 pt de largura), o mesmo desenho do PNG.
    private func preview(_ day: DayShareBuilder.Day) -> some View {
        let width: CGFloat = 150
        let k = width / DayPosterView.size.width
        return DayPosterView(poster: day.poster, options: options)
            .scaleEffect(k, anchor: .topLeading)
            .frame(width: width, height: DayPosterView.size.height * k, alignment: .topLeading)
            .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Prévia do cartaz: dia \(day.poster.numeral), \(day.poster.area), \(day.poster.stops.count) paradas")
    }

    private func check(_ title: String, _ value: Binding<Bool>, enabled: Bool = true) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            HStack(spacing: 8) {
                ZStack {
                    Rectangle().fill(value.wrappedValue && enabled ? V8.ink : .clear)
                    Rectangle().strokeBorder(V8.ink, lineWidth: 2)
                    if value.wrappedValue && enabled {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(V8.orange)
                    }
                }
                .frame(width: 22, height: 22)
                Text(title).font(V8Font.text(13)).foregroundStyle(V8.ink).lineLimit(2)
            }
            .frame(minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityAddTraits(value.wrappedValue && enabled ? .isSelected : [])
    }

    // MARK: Opções

    private func rows(_ day: DayShareBuilder.Day) -> some View {
        let link = try? DayLink.url(day.shared)
        return VStack(spacing: 0) {
            shareRow(icon: "photo", filled: true, title: "Cartaz · imagem",
                     meta: "1080×1920 · vai pro WhatsApp, Instagram, Fotos", trailing: "padrão", url: posterURL)
            if let link {
                ShareLink(item: link, subject: Text(shareTitle(day)), message: Text(shareTitle(day))) {
                    rowLabel(icon: "link", filled: false, title: copied ? "Link copiado" : "Link do Must",
                             meta: "\(linkPreview(link)) · abre o dia no app de quem tem; na web, mostra o cartaz")
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Copiar o link", systemImage: "doc.on.doc") {
                        UIPasteboard.general.url = link
                        copied = true
                    }
                }
                divider
            }
            shareRow(icon: "doc.text", filled: false, title: "PDF da viagem inteira",
                     meta: "\(tripDays.isEmpty ? 1 : tripDays.count) \(tripDays.count == 1 ? "dia" : "dias"), um por página · pra imprimir ou pro hotel",
                     url: pdfURL)
            rowLabel(icon: "person.2", filled: false, title: "Viajar junto",
                     meta: sharing.unavailableReason.map { "Ana entra no board e no dia · \($0)" }
                        ?? "Ana entra no board e no dia; mudanças aparecem pros dois (iCloud, sem servidor)",
                     tag: sharing.isAvailable ? "novo" : nil)
                .opacity(sharing.isAvailable ? 1 : 0.45)
                .accessibilityHint(sharing.unavailableReason ?? "")
        }
    }

    private func shareTitle(_ day: DayShareBuilder.Day) -> String {
        "Dia \(day.poster.numeral) · \(day.poster.area) · \(day.poster.dayLine)"
    }

    private func linkPreview(_ url: URL) -> String {
        let payload = DayLink.payload(from: url) ?? ""
        return "must://d/\(payload.prefix(5))…"
    }

    @ViewBuilder
    private func shareRow(icon: String, filled: Bool, title: String, meta: String, trailing: String? = nil, url: URL?) -> some View {
        if let url {
            ShareLink(item: url) {
                rowLabel(icon: icon, filled: filled, title: title, meta: meta, trailing: trailing)
            }
            .buttonStyle(.plain)
        } else {
            rowLabel(icon: icon, filled: filled, title: title, meta: meta, trailing: trailing, busy: true)
        }
        divider
    }

    private var divider: some View { Rectangle().fill(V8.rule).frame(height: 1) }

    private func rowLabel(icon: String, filled: Bool, title: String, meta: String, trailing: String? = nil,
                          tag: String? = nil, busy: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(filled ? V8.white : V8.ink)
                .frame(width: 40, height: 40)
                .background(Rectangle().fill(filled ? V8.ink : .clear))
                .overlay(Rectangle().strokeBorder(V8.ink, lineWidth: filled ? 0 : 2))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(V8Font.text(14.5, weight: .bold)).foregroundStyle(V8.ink).lineLimit(1)
                Text(meta).font(V8Font.text(12)).foregroundStyle(V8.mute).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if busy {
                ProgressView().controlSize(.small)
            } else if let trailing {
                MonoLabel(trailing, size: 9.5, color: V8.mute)
            } else if let tag {
                V8Tag(text: tag, style: .orange)
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    // MARK: Botão principal

    @ViewBuilder private var mainButton: some View {
        let url = isTrip ? pdfURL : posterURL
        let title = isTrip ? "Mandar o PDF da viagem" : (Self.hasWhatsApp ? "Mandar cartaz" : "Mandar o cartaz")
        if let url {
            // Share sheet do sistema: com o WhatsApp instalado ele aparece entre os primeiros (o iOS ordena pelo uso).
            ShareLink(item: url) {
                HStack(spacing: 10) {
                    Text(title).font(V8Font.text(16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                    Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(V8.white)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Rectangle().fill(V8.ink))
                .contentShape(Rectangle())
            }
            .buttonStyle(MustPressStyle())
        } else {
            BigButton(title: title, style: .ink, systemImage: "arrow.up.right") {}
                .disabled(true)
                .opacity(0.5)
        }
    }

    /// WhatsApp instalado (`LSApplicationQueriesSchemes` tem `whatsapp`).
    static var hasWhatsApp: Bool {
        guard let url = URL(string: "whatsapp://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    // MARK: Vazio

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isTrip ? "Nenhum dia montado ainda." : "Nada montado pra este dia.")
                .font(V8Font.display(28))
                .foregroundStyle(V8.ink)
            Text("O cartaz sai do dia aceito: monte o dia e volte aqui pra mandar.")
                .font(V8Font.text(15))
                .foregroundStyle(V8.mute)
                .fixedSize(horizontal: false, vertical: true)
            BigButton(title: "Montar o dia", style: .orange, systemImage: "arrow.up.right") {
                let day = region.calendar.startOfDay(for: date ?? AppClock.now)
                dismiss()
                router.push(.montar(date: day), on: .hoje)
            }
            .padding(.top, 8)
        }
    }
}
