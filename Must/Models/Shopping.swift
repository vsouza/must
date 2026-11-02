import Foundation
import SwiftData

// Compras da viagem (prompt 17 · B): o que trazer, com o que a volta exige (tax-free, cota, Vigiagro).
// Por região, como a Carteira. Fica fora do export do board (decisão da fatia 8B, ver QA.md): o JSON de board
// não muda; as compras que viraram gasto já saem no export como `expenses`.

/// Categoria da vitrine (a fileira de cima filtra por ela).
enum ShoppingCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case cameras, food, tech, gifts, pharmacy, home, clothes, other

    var id: String { rawValue }

    /// Nome da categoria na fileira e na seção.
    var label: String {
        switch self {
        case .cameras: "Câmeras e filme"
        case .food: "Comidinhas pra levar"
        case .tech: "Tecnologia"
        case .gifts: "Presentes"
        case .pharmacy: "Farmácia e beleza"
        case .home: "Casa"
        case .clothes: "Roupas"
        case .other: "Outros"
        }
    }
}

/// Situação do item: quero, quero muito (âmbar/preto na tela), já comprei.
enum ShoppingStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case want
    case mustHave = "must-have"
    case bought

    var id: String { rawValue }

    var label: String {
        switch self {
        case .want: "quero"
        case .mustHave: "quero muito"
        case .bought: "comprado"
        }
    }
}

/// Marca que a checagem põe no item (`ShoppingChecks`): cada uma tem um efeito na volta.
enum RuleFlag: String, Codable, CaseIterable, Sendable, Identifiable {
    case pork
    case rawMilk = "raw-milk"
    case fruitOrSeed = "fruit-seed"
    case alcohol

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pork: "porco"
        case .rawMilk: "leite cru"
        case .fruitOrSeed: "fruta/semente"
        case .alcohol: "álcool"
        }
    }
}

@Model
final class ShoppingItem {
    @Attribute(.unique) var id: String = UUID().uuidString
    var name: String = ""
    var categoryRaw: String = ShoppingCategory.other.rawValue
    /// `Place.id` de uma loja da lista shop (Must shop do board). Nil = loja digitada em `storeName`.
    var storeId: String?
    /// Loja que não está no board ("Map Camera").
    var storeName: String = ""
    var area: String?
    /// Preço estimado da linha (todas as unidades), na moeda da região.
    var estPrice: Double = 0
    /// Quanto pagou de fato (só depois de comprado).
    var paid: Double?
    var qty: Int = 1
    var statusRaw: String = ShoppingStatus.want.rawValue
    /// `RuleFlag` marcadas pela checagem (ao salvar).
    var flagsRaw: [String] = []
    /// Tem recibo tax-free (entra no reembolso da saída).
    var taxFreeReceipt: Bool = false
    /// Ingredientes digitados (a checagem de porco e leite cru lê daqui).
    var ingredients: String = ""
    var notes: String = ""
    /// Quando virou "comprado" (dia do recibo e do gasto).
    var boughtAt: Date?
    /// Gasto criado quando o item foi comprado (`Expense`, categoria shop).
    var expenseId: UUID?
    var createdAt: Date = AppClock.now

    init(id: String = UUID().uuidString, name: String, category: ShoppingCategory = .other, storeId: String? = nil,
         storeName: String = "", area: String? = nil, estPrice: Double = 0, paid: Double? = nil, qty: Int = 1,
         status: ShoppingStatus = .want, flags: [RuleFlag] = [], taxFreeReceipt: Bool = false, ingredients: String = "",
         notes: String = "", boughtAt: Date? = nil, createdAt: Date = AppClock.now) {
        self.id = id
        self.name = name
        self.categoryRaw = category.rawValue
        self.storeId = storeId
        self.storeName = storeName
        self.area = area
        self.estPrice = estPrice
        self.paid = paid
        self.qty = max(1, qty)
        self.statusRaw = status.rawValue
        self.flagsRaw = flags.map(\.rawValue)
        self.taxFreeReceipt = taxFreeReceipt
        self.ingredients = ingredients
        self.notes = notes
        self.boughtAt = boughtAt
        self.createdAt = createdAt
    }

    var category: ShoppingCategory {
        get { ShoppingCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var status: ShoppingStatus {
        get { ShoppingStatus(rawValue: statusRaw) ?? .want }
        set { statusRaw = newValue.rawValue }
    }

    var flags: [RuleFlag] {
        get { flagsRaw.compactMap(RuleFlag.init(rawValue:)) }
        set { flagsRaw = newValue.map(\.rawValue) }
    }

    var isBought: Bool { status == .bought }

    /// Quanto este item conta no previsto: `paid` se já comprou (ou o estimado, se não anotou o pago), senão o estimado.
    var committedYen: Double {
        isBought ? (paid ?? estPrice) : estPrice
    }

    /// Loja pra mostrar: o nome do board, ou o que você digitou.
    func storeLabel(board places: [Place]) -> String {
        if let storeId, let place = places.first(where: { $0.id == storeId }) { return place.name }
        return storeName
    }
}

extension ModelContext {
    /// Itens de compra da região, na ordem em que foram criados.
    func shoppingItems() -> [ShoppingItem] {
        let items = (try? fetch(FetchDescriptor<ShoppingItem>())) ?? []
        return items.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }
}
