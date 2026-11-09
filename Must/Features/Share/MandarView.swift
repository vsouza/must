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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let day {
                        top(day).padding(.top, 8)
                        rows(day).padding(.top, 20)
                        mainButton.padding(.top, 20)
                    } else if loaded {
                        empty.padding(.top, 20)
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, V9.gutter)
            }
            .navigationTitle(isTrip ? "Mandar a viagem" : "Mandar o dia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
            .v9Screen()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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

    private var specLine: String {
        if isTrip { return tripDays.count == 1 ? "a viagem · 1 dia" : "a viagem · \(tripDays.count) dias" }
        guard let day else { return DayText.dayLine(date ?? AppClock.now, region: region) }
        return "dia \(day.poster.numeral) · \(day.poster.area)"
    }

    private func top(_ day: DayShareBuilder.Day) -> some View {
        HStack(alignment: .top, spacing: 16) {
            preview(day)
            VStack(alignment: .leading, spacing: 8) {
                Text(specLine).font(.headline).lineLimit(2)
                Text("Quem tem o Must abre o roteiro no app. Quem não tem recebe o cartaz, bonito o bastante pro WhatsApp.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 0) {
                    check("com horários", $options.times)
                    check("com mapa do percurso", $options.map, enabled: day.poster.hasMap)
                    check("com preços", $options.prices)
                    check("com QR dos ingressos", $options.qr, enabled: !day.poster.qrs.isEmpty)
                }
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
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Prévia do cartaz: dia \(day.poster.numeral), \(day.poster.area), \(day.poster.stops.count) paradas")
    }

    private func check(_ title: String, _ value: Binding<Bool>, enabled: Bool = true) -> some View {
        Toggle(title, isOn: value)
            .font(.subheadline)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)
            .tint(V9.accent)
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

    private var divider: some View { Divider() }

    private func rowLabel(icon: String, filled: Bool, title: String, meta: String, trailing: String? = nil,
                          tag: String? = nil, busy: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(filled ? Color.white : Color.primary)
                .frame(width: 40, height: 40)
                .background(filled ? V9.accent : V9.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).lineLimit(2)
                Text(meta).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if busy {
                ProgressView().controlSize(.small)
            } else if let trailing {
                Text(trailing).font(.caption).foregroundStyle(.secondary)
            } else if let tag {
                J9Tag(text: tag, filled: true)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: Botão principal

    @ViewBuilder private var mainButton: some View {
        let url = isTrip ? pdfURL : posterURL
        let title = isTrip ? "Mandar o PDF da viagem" : (Self.hasWhatsApp ? "Mandar cartaz" : "Mandar o cartaz")
        if let url {
            // Share sheet do sistema: com o WhatsApp instalado ele aparece entre os primeiros (o iOS ordena pelo uso).
            ShareLink(item: url) {
                Label(title, systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .v9Primary()
        } else {
            J9Button(title, systemImage: "square.and.arrow.up") {}
                .disabled(true)
        }
    }

    /// WhatsApp instalado (`LSApplicationQueriesSchemes` tem `whatsapp`).
    static var hasWhatsApp: Bool {
        guard let url = URL(string: "whatsapp://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    // MARK: Vazio

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isTrip ? "Nenhum dia montado ainda." : "Nada montado pra este dia.").font(.title2.bold())
            Text("O cartaz sai do dia aceito: monte o dia e volte aqui pra mandar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            J9Button("Montar o dia") {
                let day = region.calendar.startOfDay(for: date ?? AppClock.now)
                dismiss()
                router.push(.montar(date: day), on: .hoje)
            }
        }
    }
}
