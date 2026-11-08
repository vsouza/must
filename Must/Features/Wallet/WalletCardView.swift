import SwiftUI

/// O que um cartão empilhado mostra (puro, testável): rótulo, valor e a etiqueta de baixo.
struct WalletCardFacts: Equatable {
    var label: String
    var value: String
    var tag: String?
    /// Saldo abaixo do limite ou validade acabando: a etiqueta vira âmbar.
    var alert: Bool

    static func make(_ item: WalletItem, region: Region, now: Date, cardSpend: Double = 0, fxRate: Double = 0) -> WalletCardFacts {
        switch item.kind {
        case .transitCard:
            let label = item.balanceNotedAt.map { "saldo (\(WalletRules.balanceNote(noted: $0, now: now, region: region)))" } ?? "saldo"
            return WalletCardFacts(label: label,
                                   value: item.balance.map { region.money($0) } ?? "sem saldo anotado",
                                   tag: item.lowBalance.map { "recarregar abaixo de \(region.money($0))" },
                                   alert: WalletRules.isLowBalance(item))
        case .railPass:
            return WalletCardFacts(label: "cobre",
                                   value: item.coverage ?? item.detail,
                                   tag: WalletRules.validity(from: item.validFrom, until: item.validUntil, now: now, region: region),
                                   alert: false)
        case .creditCard:
            // Japão: o cartão cobra em reais, então o gasto (em ienes) vem convertido, com o câmbio da região.
            if region.profile.money?.showsBRL == true, fxRate > 0 {
                return WalletCardFacts(label: "gasto na viagem",
                                       value: (cardSpend * fxRate).formatted(.money("BRL")),
                                       tag: "câmbio \(region.fxUnitLabel) = \((region.fxUnit * fxRate).formatted(.money("BRL")))",
                                       alert: false)
            }
            return WalletCardFacts(label: "gasto na viagem", value: region.money(cardSpend), tag: nil, alert: false)
        case .esim, .entryQR, .insurance, .passport, .other:
            return WalletCardFacts(label: "", value: item.detail, tag: nil, alert: false)
        }
    }
}

/// Uma linha da lista de documentos (puro, testável): selo, subtítulo e a etiqueta da direita.
struct WalletDocumentFacts: Equatable {
    var badge: String
    var subtitle: String
    var tag: String
    /// Etiqueta de "pronto" (verde) ou de alerta (âmbar); nil = neutra.
    var emphasis: Emphasis?

    enum Emphasis: Equatable { case ready, alert }

    static func make(_ item: WalletItem, region: Region, now: Date) -> WalletDocumentFacts {
        let badge = item.attachmentName == nil ? item.kind.badge : (item.attachmentIsPDF ? "PDF" : "IMG")
        let validity = WalletRules.validity(from: item.validFrom, until: item.validUntil, now: now, region: region)
        let detail = item.detail.isEmpty && item.kind == .entryQR ? WalletFromTicket.fallbackDetail(.entryQR) : item.detail
        let subtitle = [detail, validity].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")

        if WalletRules.isExpiringSoon(until: item.validUntil, now: now, region: region) {
            return WalletDocumentFacts(badge: badge, subtitle: subtitle, tag: validity ?? "vence logo", emphasis: .alert)
        }
        switch item.kind {
        case .entryQR:
            let ready = item.qrPayload != nil
            return WalletDocumentFacts(badge: badge, subtitle: subtitle, tag: ready ? "pronto" : "sem QR", emphasis: ready ? .ready : nil)
        case .esim:
            return WalletDocumentFacts(badge: badge, subtitle: subtitle, tag: "instruções", emphasis: nil)
        default:
            return WalletDocumentFacts(badge: badge, subtitle: subtitle, tag: item.attachmentName == nil ? "ver" : "abrir", emphasis: nil)
        }
    }
}

/// Cartão da Carteira no corte: faixa inteira de tinta (laranja se o saldo/validade pede atenção), nome, detalhe, o valor em
/// numeral e a etiqueta. Sem degradê, rotação ou sombra. Toque abre o item.
struct WalletCardView: View {
    let item: WalletItem
    let facts: WalletCardFacts
    var rotation: Double = 0
    var onTap: () -> Void
    var onWallet: () -> Void

    var body: some View {
        let fill = facts.alert ? V8.orange : V8.ink
        let text = facts.alert ? V8.ink : V8.white
        let soft = facts.alert ? V8.ink.opacity(0.75) : V8.muteDark
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(V8Font.text(18, weight: .bold)).foregroundStyle(text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.detail).font(V8Font.text(13)).foregroundStyle(soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if item.attachmentName != nil, !item.opensWallet {
                    Text("VOUCHER NO PDF").font(V8Font.mono(10, weight: .semibold)).tracking(0.8).foregroundStyle(text)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .overlay(Rectangle().stroke(text, lineWidth: 1.5))
                }
            }
            if !facts.label.isEmpty || !facts.value.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel(facts.label, size: 10, color: soft)
                    Text(facts.value)
                        .font(item.kind == .railPass ? V8Font.text(18, weight: .bold) : V8Font.numeral(40))
                        .foregroundStyle(text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }
                .padding(.top, 18)
            }
            HStack(alignment: .center, spacing: 12) {
                if let tag = facts.tag {
                    Text(tag.uppercased())
                        .font(V8Font.mono(10, weight: .semibold)).tracking(0.8)
                        .foregroundStyle(facts.alert ? V8.orange : text)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(facts.alert ? V8.ink : Color.clear)
                        .overlay(Rectangle().stroke(text, lineWidth: facts.alert ? 0 : 1.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if item.opensWallet {
                    Button(action: onWallet) {
                        Text("ABRIR NO WALLET ↗")
                            .font(V8Font.mono(11, weight: .semibold)).tracking(0.8)
                            .foregroundStyle(text)
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .overlay(Rectangle().stroke(text, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(fill)
        .overlay(alignment: .bottom) { Rectangle().fill(V8.paper).frame(height: 2) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
    }
}
