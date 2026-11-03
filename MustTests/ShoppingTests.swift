import Foundation
import SwiftData
import Testing
@testable import Must

/// Prompt 17 · B (fatia 8B): Compras da viagem. Checagem de item, previsto e cota, régua de álcool, regra dos iguais,
/// tax-free a receber, regras carregadas do bundle, checklist do voo de volta e o gasto de um item comprado.
@MainActor
struct ShoppingTests {
    static func container() throws -> ModelContainer {
        try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// Um instante no dia da compra (o mesmo dia pra todos os itens, salvo onde o teste diz).
    static let day = Date(timeIntervalSince1970: 1_793_000_000)

    /// Lista com o câmbio do QA: ¥1 = R$ 0,036 e US$ 1 = R$ 5,50.
    static func report(_ items: [ShoppingItem]) -> ShoppingReport {
        ShoppingReport(items: items, fxRate: 0.036, brlPerUSD: 5.5, timeZone: Region.jp.timeZone)
    }

    static func flight(_ legs: [FlightSegment]) -> Flight {
        Flight(pnr: "TEST01", legs: legs)
    }

    static let outbound = FlightSegment(number: "LA 8084", from: "GRU", to: "HND", departs: day)
    static let homeward = FlightSegment(number: "JL 5", from: "HND", to: "GRU", departs: day.addingTimeInterval(7 * 86_400))

    // MARK: 1. Checagem de item (item 9)

    @Test func tonkotsuRamenGeraAlertaDeSuino() {
        let flags = ShoppingChecks.flags(name: "ramen tonkotsu instantâneo", ingredients: "", food: true)
        #expect(flags == [.pork])

        let item = ShoppingItem(name: "ramen tonkotsu instantâneo", category: .food, estPrice: 900, flags: flags)
        let alerts = Self.report([item]).alerts
        #expect(alerts.contains { $0.ruleId == "food-pork" && $0.text.contains("porco") })
    }

    @Test func checagemDeComidaLeIngredientesEDistingueTermos() {
        #expect(ShoppingChecks.flags(name: "KitKat matcha", ingredients: "matcha, lacrado", food: true).isEmpty)
        #expect(ShoppingChecks.flags(name: "Caldo", ingredients: "extrato de porco", food: true) == [.pork])
        #expect(ShoppingChecks.flags(name: "Hamburguer de soja", ingredients: "", food: true).isEmpty)
        #expect(ShoppingChecks.flags(name: "Queijo", ingredients: "feito com leite cru", food: true) == [.rawMilk])
        #expect(ShoppingChecks.flags(name: "Frutas secas", ingredients: "", food: true) == [.fruitOrSeed])
        // Fora de comida, suíno não é checado (um tempero de cosmético não é a Vigiagro); álcool é.
        #expect(ShoppingChecks.flags(name: "Tonkotsu", ingredients: "", food: false).isEmpty)
        #expect(ShoppingChecks.flags(name: "Saquê 720 ml", ingredients: "", food: false) == [.alcohol])
    }

    @Test func volumeDaBebidaEmLitros() {
        #expect(ShoppingChecks.volumeLitres(in: "Saquê 720 ml") == 0.72)
        #expect(ShoppingChecks.volumeLitres(in: "Whisky 1,8 L") == 1.8)
        #expect(ShoppingChecks.volumeLitres(in: "Umeshu 1.8l") == 1.8)
        #expect(ShoppingChecks.volumeLitres(in: "garrafa 750ml") == 0.75)
        #expect(ShoppingChecks.volumeLitres(in: "2 lojas no Shinjuku") == nil)
    }

    // MARK: 2. Régua de 12 L (item 7)

    @Test func doisSakesDe720EUmLitroSomamNaReguaDe12L() {
        let sake = ShoppingItem(name: "Saquê 720 ml", category: .food, estPrice: 6_000, qty: 2,
                                flags: [.alcohol])
        let umeshu = ShoppingItem(name: "Umeshu 1 L", category: .food, estPrice: 3_000, qty: 1, flags: [.alcohol])
        let report = Self.report([sake, umeshu])
        #expect(abs(report.liquorLitres - 2.44) < 0.0001)
        #expect(report.alerts.allSatisfy { $0.ruleId != "entering-liquor" || !$0.text.contains("passa") })
        #expect(report.impact(for: "entering-liquor")?.tone == .ok)
    }

    @Test func passarDe12LViraAlerta() {
        let whisky = ShoppingItem(name: "Whisky 1 L", category: .gifts, estPrice: 40_000, qty: 13, flags: [.alcohol])
        let report = Self.report([whisky])
        #expect(report.liquorLitres == 13)
        #expect(report.alerts.contains { $0.ruleId == "entering-liquor" && $0.text.contains("passa de 12 L") })
    }

    // MARK: 3. Previsto e cota (item 7 e o "Verificar")

    @Test func previstoSomaEstimadoDosNaoCompradosEPagoDosComprados() {
        let want = ShoppingItem(name: "Bolsa", estPrice: 1_000, status: .want)
        let bought = ShoppingItem(name: "Portra", estPrice: 2_000, paid: 1_500, status: .bought)
        let mustHave = ShoppingItem(name: "Contax", estPrice: 500, status: .mustHave)
        let report = Self.report([want, bought, mustHave])
        #expect(report.planned == 3_000)
        #expect(report.spent == 1_500)
    }

    @Test func cotaAcimaDeUmMilAlertaEChecklistDoVooDeVolta() throws {
        let contax = ShoppingItem(name: "Contax T2 · usada", category: .cameras, estPrice: 95_000, status: .mustHave)
        let portra = ShoppingItem(name: "Portra 400", category: .cameras, storeName: "Yodobashi", estPrice: 28_000,
                                  paid: 28_000, status: .bought, taxFreeReceipt: true, boughtAt: Self.day)
        let kitkat = ShoppingItem(name: "KitKat matcha", category: .food, estPrice: 2_400, qty: 6, status: .want)
        let rest = ShoppingItem(name: "Bolsa de câmera", category: .cameras, estPrice: 35_600, status: .want)
        let items = [contax, portra, kitkat, rest]
        let report = Self.report(items)
        #expect(report.usedUSD > 1_000)
        #expect(report.needsEDBV)
        #expect(report.alerts.contains { $0.ruleId == "entering-allowance" })

        let trip = Self.flight([Self.outbound, Self.homeward])
        #expect(ShoppingFlightSync.returnFlight(in: [trip]) != nil)
        #expect(ShoppingFlightSync.apply(report, flights: [trip]))
        let ids = trip.checklist.map(\.id)
        #expect(ids.contains("shop-edbv"))
        #expect(ids.contains("shop-taxfree"))
        #expect(ids.contains("shop-declare"))
        let taxfree = try #require(trip.checklist.first { $0.id == "shop-taxfree" })
        #expect(taxfree.phase == .airport)
        #expect(taxfree.title.contains("1 recibo no quiosque antes do check-in"))
    }

    @Test func checklistNaoMudaNoVooDeIda() {
        let portra = ShoppingItem(name: "Portra", estPrice: 28_000, paid: 28_000, status: .bought, taxFreeReceipt: true, boughtAt: Self.day)
        let report = Self.report([portra])
        let outbound = Self.flight([Self.outbound])
        #expect(ShoppingFlightSync.returnFlight(in: [outbound]) == nil)
        #expect(!ShoppingFlightSync.apply(report, flights: [outbound]))
        #expect(outbound.checklist.isEmpty)
    }

    @Test func itensDoChecklistMantemOMarcadoEAbandonamSoOQueNaoSeAplica() {
        let contax = ShoppingItem(name: "Contax", estPrice: 160_000, status: .mustHave)
        let trip = Self.flight([Self.homeward])
        ShoppingFlightSync.apply(Self.report([contax]), flights: [trip])
        var list = trip.checklist
        if let index = list.firstIndex(where: { $0.id == "shop-edbv" }) { list[index].done = true }
        trip.checklist = list
        ShoppingFlightSync.apply(Self.report([contax]), flights: [trip])
        #expect(trip.checklist.first { $0.id == "shop-edbv" }?.done == true)

        // Sem excedente nem comida: só some o que deixou de valer; o marcado de quem ficou continua marcado.
        contax.estPrice = 10_000
        ShoppingFlightSync.apply(Self.report([contax]), flights: [trip])
        #expect(!trip.checklist.contains { $0.id == "shop-edbv" })

        contax.estPrice = 160_000
        ShoppingFlightSync.apply(Self.report([contax]), flights: [trip])
        #expect(trip.checklist.first { $0.id == "shop-edbv" }?.done == false)
    }

    // MARK: 4. Regra dos iguais (item 9)

    @Test func regraDosTresIguaisAcimaDeDezDolares() {
        // Câmera: ¥95.000 cada → bem acima de US$ 10: 4 iguais passam de 3.
        let contax = ShoppingItem(name: "Contax T2", category: .cameras, estPrice: 380_000, qty: 4, status: .want)
        #expect(Self.report([contax]).alerts.contains { $0.text.contains("Contax T2 × 4") })

        // Kit Kat: ¥600 cada → abaixo de US$ 10: até 10 iguais passam.
        let kit = ShoppingItem(name: "KitKat matcha", category: .food, estPrice: 2_400, qty: 4, status: .want)
        #expect(!Self.report([kit]).alerts.contains { $0.text.contains("KitKat") })

        let many = ShoppingItem(name: "Portra 400", category: .cameras, estPrice: 1_100, qty: 11, status: .want)
        #expect(Self.report([many]).alerts.contains { $0.text.contains("Portra 400 × 11") })
    }

    // MARK: 5. Tax-free a receber (item 8)

    @Test func taxFreeSoDeRecibosComMinimoDeYenPorLojaDia() {
        let camera = ShoppingItem(name: "Contax", storeName: "Map Camera", estPrice: 6_000, status: .bought, taxFreeReceipt: true, boughtAt: Self.day)
        let film = ShoppingItem(name: "Filme", storeName: "Map Camera", estPrice: 3_000, status: .bought, taxFreeReceipt: true, boughtAt: Self.day)
        let small = ShoppingItem(name: "Pomada", storeName: "Yodobashi", estPrice: 4_000, status: .bought, taxFreeReceipt: true, boughtAt: Self.day)
        let noReceipt = ShoppingItem(name: "Faca", storeName: "Kappabashi", estPrice: 20_000, status: .bought, taxFreeReceipt: false, boughtAt: Self.day)
        let notBought = ShoppingItem(name: "Bolsa", storeName: "Bic", estPrice: 30_000, status: .want, taxFreeReceipt: true)
        let report = Self.report([camera, film, small, noReceipt, notBought])
        let tax = report.taxFree

        #expect(tax.receipts == 2)
        #expect(tax.belowMinStores == 1)
        // 9.000 × 10 / 110 = 818,18 → 818 de volta.
        #expect(tax.refund == 818)
        #expect(report.impact(for: "taxfree-refund")?.text == "ainda falta: 2 recibos · ¥ 818 de volta")
        #expect(report.impact(for: "taxfree-min")?.tone == .no)
    }

    @Test func mesmaLojaEmDiasDiferentesNaoSomaParaOMinimo() {
        let monday = ShoppingItem(name: "A", storeName: "Loja", estPrice: 3_000, status: .bought, taxFreeReceipt: true, boughtAt: Self.day)
        let tuesday = ShoppingItem(name: "B", storeName: "Loja", estPrice: 3_000, status: .bought, taxFreeReceipt: true,
                                   boughtAt: Self.day.addingTimeInterval(86_400))
        let tax = Self.report([monday, tuesday]).taxFree
        #expect(tax.receipts == 0)
        #expect(tax.belowMinStores == 2)
    }

    // MARK: 6. Regras do bundle (item 6)

    @Test func regrasCarregamDoBundleComDataEFonte() {
        let pack = ShoppingRules.jpBR
        #expect(pack.pair == "JP-BR")
        #expect(pack.limits.taxFreeMinYen == 5_000)
        #expect(pack.limits.airAllowanceUSD == 1_000)
        #expect(pack.limits.liquorLitres == 12)
        #expect(pack.limits.identicalAboveMax == 3)
        #expect(pack.limits.identicalBelowMax == 10)
        #expect(!pack.rules.isEmpty)
        for rule in pack.rules {
            #expect(rule.checkedAt == "2026-11-02")
            #expect(rule.sourceURL.hasPrefix("https://"))
        }
        for section in ShoppingRuleSection.allCases {
            #expect(!pack.rules(in: section).isEmpty)
        }
        #expect(pack.rule("taxfree-refund")?.tone == .warn)
        #expect(ShoppingRules.load(named: "jp-br", bundle: nil) != nil)
    }

    @Test func estadoDaListaNaRegraDeComidaEDeNaMala() {
        let ramen = ShoppingItem(name: "ramen tonkotsu instantâneo", category: .food, estPrice: 900,
                                 flags: [.pork])
        let powerbank = ShoppingItem(name: "Power bank 20000", category: .tech, estPrice: 5_000)
        let report = Self.report([ramen, powerbank])
        #expect(report.impact(for: "food-pork")?.text == "na sua lista: ramen tonkotsu instantâneo · trocar por shoyu?")
        #expect(report.impact(for: "food-pork")?.tone == .no)
        #expect(report.impact(for: "carry-powerbank")?.text == "sua lista: Power bank 20000 · na mão")
    }

    // MARK: 7. Comprado vira gasto e loja visitada (item 7)

    @Test func comprarCriaGastoEMarcaALojaVisitada() throws {
        let container = try Self.container()
        let context = container.mainContext
        let shop = Place(id: "j95", name: "Yodobashi Camera Shinjuku West", cityId: "tokyo1")
        context.insert(shop)
        let item = ShoppingItem(name: "Portra 400 · 10 rolos", category: .cameras, storeId: "j95", estPrice: 28_000,
                                paid: 28_000, status: .bought)
        context.insert(item)

        ShoppingPurchase.sync(item, store: shop, context: context, now: Self.day)
        ShoppingPurchase.sync(item, store: shop, context: context, now: Self.day)  // de novo não duplica
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 1)
        #expect(expenses.first?.category == .shop)
        #expect(expenses.first?.amount == 28_000)
        #expect(shop.done != nil)

        item.status = .want
        ShoppingPurchase.sync(item, store: shop, context: context, now: Self.day)
        #expect(try context.fetch(FetchDescriptor<Expense>()).isEmpty)
        #expect(item.expenseId == nil)
    }
}

/// Câmbio por moeda e a cota do Brasil (US$ 1.000) da lista: cada item converte da própria moeda.
@MainActor
struct ShoppingCurrencyTests {
    static let fx = 0.036
    static let usd = 5.5

    static func report(_ items: [ShoppingItem], region: String = "JPY") -> ShoppingReport {
        ShoppingReport(items: items, fxRate: fx, brlPerUSD: usd, regionCurrency: region, timeZone: Region.jp.timeZone)
    }

    @Test func cotaDoBrasilConverteIeneEmDolarPeloCambio() {
        // ¥ 158.100 × R$ 0,036 = R$ 5.691,60 ÷ 5,50 = US$ 1.034,8 (não US$ 28.745).
        let item = ShoppingItem(name: "Contax", estPrice: 158_100)
        let report = Self.report([item])
        #expect(abs(report.usedUSD - 1_034.8) < 0.1)
        #expect(ShoppingReport.usdText(report.limits.airAllowanceUSD) == "US$ 1.000")
        #expect(report.needsEDBV)
    }

    @Test func itemEmRealConvertePraIeneEDolarSemCambioDeIene() {
        // R$ 550 = US$ 100 = ¥ 15.278 (550 ÷ 0,036): o item em BRL não passa pelo câmbio do iene como se fosse ¥.
        let item = ShoppingItem(name: "Mochila", estPrice: 550, currency: "BRL")
        let report = Self.report([item], region: "BRL")
        #expect(abs(report.usedUSD - 100) < 0.01)
        #expect(abs(report.planned - 550 / Self.fx) < 0.01)
        #expect(abs(report.regionAmount(yen: report.planned) - 550) < 0.01)
    }

    @Test func itemEmDolarUsaOCambioDoDolar() {
        let item = ShoppingItem(name: "Livro", estPrice: 40, currency: "USD")
        let report = Self.report([item])
        #expect(abs(report.usedUSD - 40) < 0.01)
        #expect(abs(report.planned - 40 * Self.usd / Self.fx) < 0.01)
    }

    @Test func totaisNaMoedaDaRegiaoEOutraMoedaParaAproximacao() {
        let yen = ShoppingItem(name: "Saquê", estPrice: 15_000, currency: "JPY")
        let real = ShoppingItem(name: "Chocolate", estPrice: 100, currency: "BRL")
        let report = Self.report([yen, real], region: "BRL")
        // ¥ 15.000 = R$ 540; mais R$ 100 = R$ 640.
        #expect(abs(report.regionAmount(yen: report.planned) - 640) < 0.01)
        #expect(abs(report.amount(yen: report.planned, in: "JPY") - 640 / Self.fx) < 0.5)
    }

    @Test func limiteDaCotaEmDolarNaoEmIene() {
        #expect(ShoppingReport.usdText(1_000) == "US$ 1.000")
        #expect(!ShoppingReport.usdText(1_000).contains("¥"))
    }

    @Test func voltaCompactaEmMilhares() {
        #expect(ShoppingReport.compact(15_400) == "15k")
        #expect(ShoppingReport.compact(11_182) == "11k")
        #expect(ShoppingReport.compact(740) == "740")
    }

    @Test func reembolsoEhCalculadoEmIeneMesmoComItemEmReal() {
        // R$ 360 ÷ 0,036 = ¥ 10.000: passa do mínimo de ¥ 5.000 e entra no reembolso.
        let item = ShoppingItem(name: "Loja", storeName: "Loja", estPrice: 360, status: .bought, taxFreeReceipt: true,
                                boughtAt: ShoppingTests.day, currency: "BRL")
        let report = Self.report([item], region: "BRL")
        #expect(report.taxFree.receipts == 1)
        #expect(report.taxFree.refund > 0)
        #expect(abs(report.spent - 10_000) < 0.5)
    }
}
