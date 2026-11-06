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

/// Cartão de cor (verde, grafite, azul) com um pouco de rotação, como o design. Toque abre o item.
struct WalletCardView: View {
    let item: WalletItem
    let facts: WalletCardFacts
    var rotation: Double = 0
    var onTap: () -> Void
    var onWallet: () -> Void

    private static let amber = Color(hex: 0xFFB020)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.name).font(.must.archivo(18, .semibold)).lineLimit(1)
                        if let local = item.nameLocal {
                            Text(local).font(.must.archivo(13, .medium)).opacity(0.85)
                        }
                    }
                    Text(item.detail).font(.must.archivo(12)).opacity(0.8).lineLimit(2)
                }
                Spacer(minLength: 8)
                if item.opensWallet {
                    Button(action: onWallet) {
                        Text("Abrir no Wallet ↗").font(.must.archivo(13, .semibold))
                            .padding(.horizontal, 14).frame(minHeight: 34)
                            .background(Capsule().fill(Color.white.opacity(0.22)))
                    }
                    .buttonStyle(MustPressStyle())
                } else if item.attachmentName != nil {
                    Text("voucher no PDF").font(.must.archivo(13, .semibold))
                        .padding(.horizontal, 14).frame(minHeight: 34)
                        .background(Capsule().fill(Color.white.opacity(0.22)))
                }
            }
            Spacer(minLength: 10)
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(facts.label).font(.must.archivo(12)).opacity(0.8)
                    Text(facts.value)
                        .font(item.kind == .railPass ? .must.archivo(16, .semibold) : .must.mono(22, .semibold))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if let tag = facts.tag { tagPill(tag) }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(
            LinearGradient(colors: item.kind.tone.colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .shadow(color: Color(hex: 0x121316, opacity: 0.18), radius: 16, y: 14)
        .rotationEffect(.degrees(rotation))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private func tagPill(_ text: String) -> some View {
        let isRail = item.kind == .railPass
        Text(text)
            .font(.must.archivo(13, .semibold))
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(facts.alert || isRail ? Color.must.greenText : .white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                Capsule().fill(facts.alert ? Self.amber : (isRail ? Color.must.green : Color.white.opacity(0.2)))
            )
    }
}
