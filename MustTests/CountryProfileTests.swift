import CoreLocation
import Foundation
import Testing
@testable import Must

/// Prompt 28 §3.4: o conteúdo por país saiu do código pra `data/countries/<cc>.json`. As três de fábrica têm que dar
/// exatamente os valores de antes; país sem arquivo cai no genérico (nunca erro).
struct CountryProfileTests {
    @Test func osQuatroPerfisEstaoNoBundle() {
        #expect(Set(CountryProfile.bundled.keys) == ["BR", "JP", "IT", "PT"])
    }

    @Test func japaoIgualAoCodigoAntigo() throws {
        let jp = try #require(CountryProfile.bundled["JP"])
        #expect(jp.name == "Japão")
        #expect(jp.currency == "JPY")
        #expect(jp.symbol == "¥")
        #expect(jp.tz.identifier == "Asia/Tokyo")
        #expect(jp.budget == 15_000)
        #expect(jp.presets == [8_000, 12_000, 20_000])
        #expect(jp.defaultFXRate == 0.036)
        #expect(jp.fxUnit == 100)
        #expect(jp.coverRGB == 0xD7000F)
        #expect(jp.meals == nil)
        #expect(jp.rules == [.passportReminder])
        #expect(jp.transit?.googleTransit == false)
        #expect(jp.curatedAreas == ["tokyo", "kyoto"])
        #expect(jp.sos?.hospitalCities == ["tokyo", "kyoto"])
        #expect(jp.shoppingPack == "jp-br")
        #expect(jp.inName == "no Japão")
    }

    @Test func brasilIgualAoCodigoAntigo() throws {
        let br = try #require(CountryProfile.bundled["BR"])
        #expect(br.currency == "BRL")
        #expect(br.symbol == "R$")
        #expect(br.tz.identifier == "America/Sao_Paulo")
        #expect(br.budget == 200)
        #expect(br.presets == [100, 200, 400])
        #expect(br.defaultFXRate == 1)
        #expect(br.coverRGB == 0x007A33)
        #expect(br.rules?.isEmpty == true)
        #expect(br.curatedAreas == ["bh"])
        #expect(br.inName == "no Brasil")
    }

    @Test func italiaIgualAoCodigoAntigo() throws {
        let it = try #require(CountryProfile.bundled["IT"])
        #expect(it.currency == "EUR")
        #expect(it.symbol == "€")
        #expect(it.tz.identifier == "Europe/Rome")
        #expect(it.budget == 120)
        #expect(it.defaultFXRate == 6.2)
        #expect(it.fxUnit == 1)
        #expect(it.coverRGB == 0x1F5FB4)
        // Janelas de Roma: almoço 12:30–15, jantar 19:30–23 (jantar nunca antes das 19:30).
        #expect(it.meals?.lunch == [750, 900])
        #expect(it.meals?.dinner == [1170, 1380])
        #expect(it.has(.middayClosures) && it.has(.stateMuseumsMonday) && it.has(.cityLastMetro))
        #expect(it.shoppingPack == "it-br")
        #expect(it.inName == "na Itália")
    }

    @Test func portugalNovo() throws {
        let pt = try #require(CountryProfile.bundled["PT"])
        #expect(pt.currency == "EUR")
        #expect(pt.tz.identifier == "Europe/Lisbon")
        #expect(pt.coverRGB == 0x0A5C48)
        #expect(pt.pocket?.cards.first?.kind == .exchange)
        #expect(pt.inName == "em Portugal")
        #expect(CountryProfile.detect(CLLocationCoordinate2D(latitude: 41.1579, longitude: -8.6291)) == "PT") // Porto
        #expect(CountryProfile.detect(CLLocationCoordinate2D(latitude: 38.7223, longitude: -9.1393)) == "PT") // Lisboa
    }

    @Test func regiaoLeDoPerfil() {
        for region in Region.allCases {
            let p = region.profile
            #expect(region.currency == p.currency)
            #expect(region.currencySymbol == p.symbol)
            #expect(region.defaultBudget == p.budget)
            #expect(region.defaultFXRate == p.defaultFXRate)
            #expect(TripTheme.forRegion(region).coverRGB == p.coverRGB)
        }
    }

    @Test(arguments: [("JP", PocketRules.jp), ("BR", PocketRules.br), ("IT", PocketRules.it)])
    func bolsoMigradoSemPerder(code: String, expected: PocketCountry) throws {
        let pocket = try #require(CountryProfile.bundled[code]?.pocket)
        #expect(pocket == expected)
    }

    @Test func paisSemPerfilUsaOGenerico() {
        let fr = CountryProfile.forCountry("fr", currency: "EUR", timeZone: "Europe/Paris")
        #expect(fr.code == "FR")
        #expect(fr.name == "França")
        #expect(fr.currency == "EUR")
        #expect(fr.symbol == "€")
        #expect(fr.tz.identifier == "Europe/Paris")
        #expect(fr.pocket == nil)
        #expect(fr.rules == nil)
        #expect(fr.meals == nil)
        #expect(fr.coverRGB == nil)
        #expect(fr.defaultFXRate == 1)
        #expect(fr.curatedAreas == nil)
        #expect(!fr.isCurated)
        // Sem moeda: a do país pelo Locale; sem nada, nunca quebra.
        #expect(CountryProfile.forCountry("US").currency == "USD")
        #expect(CountryProfile.forCountry("ZZ").name.isEmpty == false)
    }
}
