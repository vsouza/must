import SwiftData
import SwiftUI

/// Regras da volta (`design/screens/ComprasRegras.png`): as regras por seção, cada uma com o impacto na sua lista,
/// a cota e o reembolso que ainda falta, e as fontes com a data da conferência.
struct ShoppingRulesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store

    @Query private var items: [ShoppingItem]
    @Query private var settingsList: [Settings]

    @State private var editingRate = false
    @State private var rateText = ""

    private var pack: ShoppingRulePack { ShoppingRules.pack(for: store.region) }
    private var settings: Settings? { settingsList.first }

    /// TODO(v8:E): a conta do `ShoppingReport` (Must/Services/Shopping) é em ¥ e `ShoppingFX.brlPerUnit` não conhece EUR;
    /// em Roma o impacto das regras de cota e álcool sai em ¥ convertido como R$ até a conta aceitar a moeda da região.
    private var report: ShoppingReport {
        ShoppingReport(items: items, fxRate: settings?.fxRate ?? 0.036, brlPerUSD: settings?.brlPerUSD ?? 5.5,
                       rules: pack, timeZone: store.region.timeZone)
    }

    /// "Japão → Brasil" / "Itália → Brasil".
    private var routeLabel: String { "\(pack.from == "IT" ? "Itália" : "Japão") → Brasil" }

    var body: some View {
        let report = self.report
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    IconButton(.voltar, label: "Voltar") { dismiss() }
                    Spacer()
                    Micro("\(routeLabel) · conferido \(Self.shortDate(checkedAt))")
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Regras da volta").mustTitle()
                    Text("o que vale pra sua lista — com o que você já comprou").mustSerif(18).foregroundStyle(Color.must.secondary)
                }
                .padding(.top, 22)

                ForEach(ShoppingRuleSection.allCases, id: \.self) { section in
                    sectionCard(section, report: report).padding(.top, 16)
                }

                footer.padding(.top, 22)
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 22)
        }
        .scrollIndicators(.hidden)
        .background(Color.must.bg)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Taxa do dólar", isPresented: $editingRate) {
            TextField("5,50", text: $rateText).keyboardType(.decimalPad)
            Button("Salvar") { saveRate() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Quantos reais valem US$ 1. É ela que converte os \(store.region.currencySymbol) da lista em dólar pra cota do Brasil.")
        }
    }

    // MARK: Seções

    private func sectionCard(_ section: ShoppingRuleSection, report: ShoppingReport) -> some View {
        let rules = pack.rules(in: section)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(section.title(from: pack.from)).font(.must.archivo(16, .semibold)).foregroundStyle(Color.must.ink)
            }
            .padding(.bottom, 10)
            Rectangle().fill(Color.must.ink.opacity(0.08)).frame(height: 1)
            ForEach(rules) { rule in
                ruleRow(rule, impact: report.impact(for: rule.id))
                if rule.id != rules.last?.id { Rectangle().fill(Color.must.ink.opacity(0.07)).frame(height: 1) }
            }
            if section == .entering { rateRow(report) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(section.tint, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func ruleRow(_ rule: ShoppingRule, impact: ShoppingImpact?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            toneBadge(rule.tone)
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.attributed(rule.text))
                    .font(.must.archivo(15))
                    .foregroundStyle(Color.must.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let impact {
                    Text(impact.text).font(.must.archivo(13)).foregroundStyle(Self.color(impact.tone))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rateRow(_ report: ShoppingReport) -> some View {
        HStack(spacing: 8) {
            Text("taxa: US$ 1 = R$ \(report.brlPerUSD.formatted(.number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(2))))")
                .font(.must.mono(13)).foregroundStyle(Color.must.secondary)
            Spacer(minLength: 8)
            Button {
                rateText = report.brlPerUSD.formatted(.number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(2)))
                editingRate = true
            } label: {
                Text("mudar").font(.must.archivo(13, .semibold)).foregroundStyle(Color.must.blueText)
            }
            .buttonStyle(MustPressStyle())
        }
        .padding(.top, 10)
    }

    private func toneBadge(_ tone: ShoppingTone) -> some View {
        let (symbol, fill, text): (String, Color, Color) = switch tone {
        case .ok: ("✓", Color.must.green, Color.must.greenText)
        case .warn: ("!", Color(hex: 0xFFB020), Color(hex: 0x4A2E00))
        case .no: ("✕", Color(hex: 0xFF5A3C), .white)
        }
        return Text(symbol)
            .font(.must.archivo(11, .bold))
            .foregroundStyle(text)
            .frame(width: 20, height: 20)
            .background(Circle().fill(fill))
            .padding(.top, 2)
    }

    // MARK: Rodapé

    private var footer: some View {
        let sources = Self.sources(pack.rules)
        return VStack(alignment: .leading, spacing: 8) {
            Micro("fontes")
            ForEach(sources, id: \.url) { source in
                Link(destination: source.url) {
                    Text("\(source.label) ↗").font(.must.archivo(13)).foregroundStyle(Color.must.blueText)
                }
            }
            Text("Cada regra tem a data da conferência e o link oficial. Confira antes de embarcar: as regras mudam.")
                .mustMeta()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Ações

    private func saveRate() {
        let value = TicketMoney.parse(rateText)
        guard value > 0 else { return }
        let target = context.settings(for: store.region)
        target.brlPerUSD = value
        try? context.save()
    }

    // MARK: Textos e cores

    private var checkedAt: String { pack.rules.map(\.checkedAt).max() ?? "" }

    /// "2026-11-02" → "02/11".
    static func shortDate(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3 else { return iso }
        return "\(parts[2])/\(parts[1])"
    }

    /// `**negrito**` vira negrito; o resto é texto normal.
    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    static func color(_ tone: ShoppingTone) -> Color {
        switch tone {
        case .ok: Color.must.secondary
        case .warn: Color(hex: 0x8A5300)
        case .no: Color(hex: 0xB3261E)
        }
    }

    private struct Source: Hashable {
        var label: String
        var url: URL
    }

    /// Fontes únicas, com nome curto (MOF, Receita, MAPA).
    private static func sources(_ rules: [ShoppingRule]) -> [Source] {
        var out: [Source] = []
        for rule in rules {
            guard let url = URL(string: rule.sourceURL), !out.contains(where: { $0.url == url }) else { continue }
            let label: String = if rule.sourceURL.contains("mof.go.jp") { "MOF (Japão)" }
                else if rule.sourceURL.contains("globalblue") { "Global Blue" }
                else if rule.sourceURL.contains("adm.gov.it") { "Agenzia delle Dogane (Itália)" }
                else if rule.sourceURL.contains("anac") { "ANAC" }
                else if rule.sourceURL.contains("receitafederal") { "Receita Federal" }
                else if rule.sourceURL.contains("agricultura") { "MAPA · Vigiagro" }
                else { url.host() ?? rule.sourceURL }
            out.append(Source(label: label, url: url))
        }
        return out
    }
}

extension ShoppingRuleSection {
    /// Título da seção; o tax-free depende do país de onde se volta (`ShoppingRulePack.from`).
    func title(from country: String) -> String {
        if self == .taxFree, country == "IT" { return "Tax-free na UE · Global Blue" }
        return title
    }

    var title: String {
        switch self {
        case .taxFree: "免 Tax-free no Japão · mudou em 1º nov"
        case .carry: "Na mala"
        case .entering: "🇧🇷 Entrando no Brasil · Receita"
        case .food: "🌾 Comida · Vigiagro"
        }
    }

    var tint: Color {
        switch self {
        case .taxFree: Color(hex: 0xFFE8B8)
        case .carry: Color.must.surface2
        case .entering: Color(hex: 0xCFF7DF)
        case .food: Color(hex: 0xFFDCD2)
        }
    }
}
