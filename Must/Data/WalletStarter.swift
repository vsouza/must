import Foundation
import SwiftData

/// Itens que a Carteira do Japão já traz (Suica e JR Pass) pra você só anotar o saldo e as datas.
/// Entram uma vez, como os lugares do seed: se você apagar, eles não voltam (o id fica em `Settings.seenSeedIds`).
enum WalletStarter {
    /// Prefixo dos ids em `Settings.seenSeedIds` (não colide com os ids de lugar do seed).
    static let seenPrefix = "wallet-starter-"

    static func jpItems() -> [WalletItem] {
        [
            WalletItem(id: "starter-suica", kind: .transitCard, name: "Suica", nameLocal: "スイカ",
                       detail: "Apple Wallet · metrô, JR, konbini · saldo anotado à mão",
                       lowBalance: 1000, opensWallet: true, order: 0),
            WalletItem(id: "starter-jrpass", kind: .railPass, name: "JR Pass",
                       detail: "troca no guichê JR do aeroporto · vale a data de início",
                       coverage: "Tóquio → Kyoto → Tóquio · confira as datas no voucher", order: 1),
        ]
    }

    /// Insere o que ainda não recebeu. Só mexe na região do Japão; BH não tem Carteira de viagem por padrão.
    static func ensure(_ context: ModelContext, region: Region) {
        guard region == .jp else { return }
        let settings = context.settings(for: region)
        var seen = Set(settings.seenSeedIds)
        var changed = false
        for item in jpItems() where !seen.contains(seenPrefix + item.id) {
            seen.insert(seenPrefix + item.id)
            changed = true
            let id = item.id
            let exists = (try? context.fetchCount(FetchDescriptor<WalletItem>(predicate: #Predicate { $0.id == id }))) ?? 0
            if exists == 0 { context.insert(item) }
        }
        guard changed else { return }
        settings.seenSeedIds = Array(seen).sorted()
        try? context.save()
    }
}
