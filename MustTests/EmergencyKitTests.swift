import CoreLocation
import Foundation
import Testing
@testable import Must

/// Kit de emergência por país (prompt 25 · C.1): os números certos de cada país, a região troca os números, toda
/// entrada tem fonte, hospitais curados por cidade com coordenada no país certo.
@MainActor
struct EmergencyKitTests {
    private var kit: EmergencyKit { EmergencyKit.bundled }

    @Test func oKitVemNoApp() {
        #expect(kit.version >= 1)
        #expect(Set(kit.countries.keys).isSuperset(of: ["BR", "JP", "IT"]))
        #expect(HospitalCatalog.bundled.version >= 1)
    }

    @Test func brasil192190193() throws {
        let br = try #require(kit.kit(for: .bh))
        #expect(br.primary.map(\.number) == ["192", "190", "193"])
        #expect(br.primary.map(\.dial) == ["192", "190", "193"])
        #expect(br.primary[0].title.contains("SAMU"))
        #expect(br.consulates.isEmpty, "no Brasil não há consulado: é o país de casa")
        #expect(br.phrases.isEmpty)
        #expect(br.number("defesa-civil")?.number == "199")
    }

    @Test func japao119110EHotline() throws {
        let jp = try #require(kit.kit(for: .jp))
        #expect(jp.primary.count == 3)
        #expect(jp.primary[0].number == "119")
        #expect(jp.primary[1].number == "110")
        #expect(jp.primary[2].dial.filter(\.isNumber).hasSuffix("5038162787"), "Japan Visitor Hotline 050-3816-2787")
        #expect(!jp.consulates.isEmpty)
        #expect(!jp.phrases.isEmpty)
    }

    @Test func italia112() throws {
        let it = try #require(kit.kit(for: .it))
        #expect(it.primary.first?.number == "112")
        #expect(it.primary.count == 3)
        #expect(!it.consulates.isEmpty)
        #expect(it.consulate(cityId: "roma") != nil)
        #expect(!it.phrases.isEmpty)
    }

    @Test func trocarARegiaoTrocaOsNumeros() {
        let first = Region.allCases.map { kit.kit(for: $0)?.primary.first?.number }
        #expect(first == ["192", "119", "112"]) // bh, jp, it
        #expect(Set(first).count == 3)
    }

    @Test func todaEntradaTemFonte() {
        for (country, k) in kit.countries {
            for n in k.primary + k.more {
                #expect(n.source.hasPrefix("https://") || n.source.hasPrefix("http://"), "\(country) \(n.id) sem fonte")
                #expect(!n.title.isEmpty && !n.dial.isEmpty, "\(country) \(n.id)")
            }
            for c in k.consulates {
                #expect(c.source.hasPrefix("http"), "\(country) \(c.id) sem fonte")
            }
            #expect(Set((k.primary + k.more).map(\.id)).count == (k.primary + k.more).count, "ids repetidos em \(country)")
        }
    }

    @Test func numerosPrincipaisNaoSaoConferir() {
        // Os três botões grandes têm que estar confirmados em fonte oficial.
        for (country, k) in kit.countries {
            for n in k.primary { #expect(!n.verificar, "\(country) \(n.number) marcado conferir") }
        }
    }

    @Test func telSoAbreODiscadorENuncaComCerquilha() {
        #expect(EmergencyKit.telURL("192")?.absoluteString == "tel:192")
        #expect(EmergencyKit.telURL("+81 3-3404-5211")?.absoluteString == "tel:+81334045211")
        #expect(EmergencyKit.telURL("#7119") == nil) // o iOS não disca # vindo de link
        #expect(EmergencyKit.telURL("*123") == nil)
        #expect(EmergencyKit.telURL("") == nil)
        for k in kit.countries.values {
            for n in k.primary { #expect(n.telURL != nil, "\(n.number) tem que abrir o discador") }
        }
    }

    @Test func consuladoDaCidadeDeHoje() throws {
        let jp = try #require(kit.kit(for: .jp))
        let tokyo = jp.consulate(cityId: "tokyo1")
        #expect(tokyo != nil)
        #expect(jp.consulate(cityId: "tokyo2")?.id == tokyo?.id) // Tóquio 1 e 2 são a mesma cidade
        #expect(jp.consulate(cityId: nil) != nil)
    }

    // MARK: Hospitais

    @Test func hospitaisPorCidade() {
        let cat = HospitalCatalog.bundled
        for city in ["bh", "tokyo", "kyoto", "roma"] {
            #expect((cat.cities[city]?.count ?? 0) >= 3, "\(city)")
        }
        #expect(cat.cities["bh"]?.contains { $0.name.contains("João XXIII") } == true)
        for h in cat.cities.values.flatMap({ $0 }) {
            #expect(h.source.hasPrefix("http"), "\(h.id) sem fonte")
            #expect(h.er24h, "\(h.id): a lista é de pronto-socorro 24 h")
        }
    }

    @Test func hospitaisNoPaisCerto() {
        let cat = HospitalCatalog.bundled
        func inside(_ h: Hospital, lat: ClosedRange<Double>, lng: ClosedRange<Double>) -> Bool { lat.contains(h.lat) && lng.contains(h.lng) }
        for h in cat.cities["bh"] ?? [] { #expect(inside(h, lat: -20.1 ... -19.7, lng: -44.1 ... -43.8), "\(h.id)") }
        for h in cat.cities["tokyo"] ?? [] { #expect(inside(h, lat: 35.5 ... 35.9, lng: 139.5 ... 139.95), "\(h.id)") }
        for h in cat.cities["kyoto"] ?? [] { #expect(inside(h, lat: 34.9 ... 35.1, lng: 135.65 ... 135.85), "\(h.id)") }
        for h in cat.cities["roma"] ?? [] { #expect(inside(h, lat: 41.8 ... 42.0, lng: 12.35 ... 12.6), "\(h.id)") }
    }

    @Test func hospitalMaisPertoDoGPS() throws {
        let cat = HospitalCatalog.bundled
        // Praça da Estação (BH): o João XXIII fica a ~1,5 km, mais perto que os do Barro Preto/Lourdes? O mais perto
        // tem que ser o primeiro da lista, qualquer que seja.
        let here = CLLocation(latitude: -19.9165, longitude: -43.9345)
        let list = cat.nearest(region: .bh, to: here, cityId: "bh")
        #expect(list.count == cat.hospitals(for: .bh).count)
        let meters = list.compactMap(\.meters)
        #expect(meters == meters.sorted())
        // Sem GPS: Kyoto primeiro quando o dia é em Kyoto.
        let kyoto = cat.nearest(region: .jp, to: nil, cityId: "kyoto")
        #expect(cat.cities["kyoto"]?.contains { $0.id == kyoto.first?.hospital.id } == true)
        #expect(kyoto.allSatisfy { $0.meters == nil })
        #expect(cat.hospitals(for: .it).allSatisfy { h in cat.cities["roma"]?.contains(h) == true })
    }

    @Test func linhaDoHospital() throws {
        let h = Hospital(id: "x", name: "St. Luke's", er24h: true, english: true, address: "", lat: 0, lng: 0, source: "https://x")
        #expect(SOSText.hospitalLine(h, meters: 1_120, region: .jp) == "pronto-socorro 24 h · atende em inglês · 1,1 km")
        #expect(SOSText.hospitalLine(h, meters: 430, region: .bh) == "pronto-socorro 24 h · 430 m")
        var joao = h
        joao.note = "pronto-socorro de trauma do SUS · referência em MG"
        #expect(SOSText.hospitalLine(joao, meters: 1_480, region: .bh) == "pronto-socorro de trauma do SUS · 1,5 km")
    }
}
