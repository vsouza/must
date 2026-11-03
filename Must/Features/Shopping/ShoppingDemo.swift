#if DEBUG
import Foundation
import SwiftData

/// `-debugScreen compras` e `compras-regras`: põe, uma vez, a lista de exemplo do QA (câmera usada, Portra comprado,
/// Kit Kat matcha, ramen tonkotsu instantâneo, 2 garrafas de saquê 720 ml, faca em Kappabashi, pomada da farmácia).
@MainActor
enum ShoppingDemo {
    static func ensure(context: ModelContext) {
        guard !context.shoppingItems().contains(where: { $0.id.hasPrefix("demo-") }) else { return }
        let samples: [(ShoppingItem, String)] = [
            (ShoppingItem(id: "demo-contax", name: "Contax T2 · usada", category: .cameras, storeName: "Map Camera",
                          area: "Shinjuku", estPrice: 95_000, status: .mustHave, taxFreeReceipt: true), ""),
            (ShoppingItem(id: "demo-portra", name: "Portra 400 · 10 rolos", category: .cameras, storeName: "Yodobashi",
                          area: "Shinjuku", estPrice: 28_000, paid: 28_000, status: .bought, taxFreeReceipt: true), ""),
            (ShoppingItem(id: "demo-bolsa", name: "Bolsa de câmera", category: .cameras, storeName: "Bic Camera",
                          area: "Shinjuku", estPrice: 6_000, status: .want), ""),
            (ShoppingItem(id: "demo-kitkat", name: "KitKat matcha", category: .food, storeName: "Don Quijote",
                          estPrice: 2_400, qty: 6, status: .want), "matcha, lacrado"),
            (ShoppingItem(id: "demo-ramen", name: "ramen tonkotsu instantâneo", category: .food, storeName: "Don Quijote",
                          estPrice: 900, status: .want), "caldo tonkotsu (porco), macarrão, tempero"),
            (ShoppingItem(id: "demo-saque", name: "Saquê 720 ml", category: .food, storeName: "Don Quijote",
                          estPrice: 6_000, qty: 2, status: .want, notes: "garrafa de 720 ml"), "arroz, água"),
            (ShoppingItem(id: "demo-faca", name: "Faca santoku", category: .home, storeName: "Kappabashi",
                          area: "Asakusa", estPrice: 18_000, status: .mustHave), ""),
            (ShoppingItem(id: "demo-pomada", name: "Pomada da farmácia", category: .pharmacy, storeName: "Matsumoto Kiyoshi",
                          estPrice: 1_800, paid: 1_800, status: .bought, taxFreeReceipt: false), ""),
        ]
        for (item, ingredients) in samples {
            item.currency = "JPY"
            item.ingredients = ingredients
            item.flags = ShoppingChecks.flags(name: item.name, ingredients: ingredients, food: item.category == .food)
            context.insert(item)
            ShoppingPurchase.sync(item, store: nil, context: context)
        }
        try? context.save()
    }
}
#endif
