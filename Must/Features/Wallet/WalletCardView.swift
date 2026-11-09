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

/// Cartão da Carteira (V9): linha de lista com nome, valor grande, etiqueta e, quando abre o Wallet, botão visível.
/// Saldo baixo ou validade acabando = etiqueta vermelha do sistema.
struct WalletCardView: View {
    let item: WalletItem
    let facts: WalletCardFacts
    var rotation: Double = 0
    var onTap: () -> Void
    var onWallet: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                            if !item.detail.isEmpty {
                                Text(item.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 8)
                        if item.attachmentName != nil, !item.opensWallet {
                            Label("Voucher", systemImage: "doc.text").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if !facts.label.isEmpty || !facts.value.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            if !facts.label.isEmpty { Text(facts.label).font(.footnote).foregroundStyle(.secondary) }
                            Text(facts.value)
                                .font(item.kind == .railPass ? .body.weight(.semibold) : .title.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let tag = facts.tag {
                        Text(tag).font(.footnote.weight(.semibold)).foregroundStyle(facts.alert ? Color.red : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if item.opensWallet {
                Button(action: onWallet) { Label("Abrir no Wallet", systemImage: "wallet.pass") }
                    .v9Secondary()
            }
        }
        .padding(.vertical, 4)
    }
}
