#if DEBUG
import Foundation
import SwiftData

/// `-debugScreen carteira`: põe, uma vez, itens de exemplo na Carteira (Suica com saldo anotado, JR Pass, cartão,
/// eSIM, Visit Japan Web com QR, seguro, passaporte) pra print do QA. Não toca nos itens que já existem.
@MainActor
enum WalletDemo {
    static func ensure(context: ModelContext, region: Region) {
        guard !context.walletItems().contains(where: { $0.id == "demo-suica" }) else { return }
        let now = AppClock.now
        let dates = BoardDates(timeZone: Region.jp.timeZone)
        let items: [WalletItem] = [
            WalletItem(id: "demo-suica", kind: .transitCard, name: "Suica", nameLocal: "スイカ",
                       detail: "Apple Wallet · Express Transit · metrô, JR, konbini",
                       balance: 3240, balanceNotedAt: now.addingTimeInterval(-86_400), lowBalance: 1000,
                       opensWallet: true, order: 0),
            WalletItem(id: "demo-jrpass", kind: .railPass, name: "JR Pass · 7 dias",
                       detail: "ativar 17 nov no balcão · Tokyo Station · voucher no PDF",
                       coverage: "Tóquio → Kyoto → Tóquio · Nara",
                       validFrom: dates.day(from: "2026-11-17"), validUntil: dates.day(from: "2026-11-23"), order: 1),
            WalletItem(id: "demo-nubank", kind: .creditCard, name: "Nubank · Mastercard",
                       detail: "Apple Pay · sem IOF extra · avisar banco: feito", opensWallet: true, order: 2),
            WalletItem(id: "demo-esim", kind: .esim, name: "Ubigi · 10 GB · ativa em JP",
                       detail: "QR instalado · ativar ao pousar",
                       notes: "Ajustes › Celular › Adicionar eSIM. Ativar em Tóquio, com dados em roaming desligado.", order: 3),
            WalletItem(id: "demo-vjw-imigracao", kind: .entryQR, name: "Visit Japan Web · imigração",
                       detail: "QR salvo · funciona offline", qrPayload: "VJW-DEMO-IMIGRACAO", order: 4),
            WalletItem(id: "demo-vjw-alfandega", kind: .entryQR, name: "Visit Japan Web · alfândega",
                       detail: "QR salvo · funciona offline", qrPayload: "VJW-DEMO-ALFANDEGA", order: 5),
            WalletItem(id: "demo-seguro", kind: .insurance, name: "Seguro viagem · apólice",
                       detail: "telefone 24h · nº 88213", validUntil: dates.day(from: "2026-12-01"), order: 6),
            WalletItem(id: "demo-passaporte", kind: .passport, name: "Passaporte · foto da página",
                       detail: "só no aparelho", validUntil: dates.day(from: "2031-06-10"), order: 7),
        ]
        items.forEach(context.insert)
        try? context.save()
    }
}
#endif
