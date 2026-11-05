import Foundation
import PDFKit
import Testing
import UIKit
@testable import Must

/// Cartaz do dia (prompt 25 · B.1, `Compartilhar.png`): 1080×1920, cor do lugar, "Dia N · bairro", paradas com horário,
/// mini-mapa só com coordenada, numeral; PDF com um dia por página.
@MainActor
struct PosterTests {
    private func poster(region: Region = .jp) -> DayPoster {
        DayPoster.make(plan: DayEngineStub.qaDay, region: region, areaName: "Shinjuku", cityName: "Tóquio",
                       coordinates: ["j05": (35.6896, 139.6995), "j104": (35.6852, 139.7101), "j01": (35.6440, 139.6990)],
                       qrs: [DayPoster.QR(label: "Aula de sushi", payload: "BR-7K2M-9931")])
    }

    @Test func renderiza1080Por1920() throws {
        let image = try #require(DayPosterRenderer.image(poster(), options: PosterOptions()))
        #expect(image.size.width * image.scale == 1080)
        #expect(image.size.height * image.scale == 1920)
        let png = try #require(DayPosterRenderer.png(poster(), options: PosterOptions(times: false, map: false, prices: true, qr: true)))
        let back = try #require(UIImage(data: png))
        #expect(back.size.width * back.scale == 1080)
    }

    @Test func fundoNaCorDoLugar() throws {
        // Canto de baixo à esquerda, abaixo do rodapé: só a cor do lugar.
        for (region, hex) in [(Region.jp, UInt32(0xD7000F)), (.bh, 0x007A33), (.it, 0x1F5FB4)] {
            let image = try #require(DayPosterRenderer.image(poster(region: region), options: PosterOptions(map: false)))
            let pixel = try #require(Self.pixel(image, x: 6, y: 1914))
            #expect(Self.close(pixel, hex), "\(region): \(String(pixel, radix: 16))")
        }
    }

    @Test func textoDoCartaz() {
        let p = poster()
        #expect(p.numeral == "3")
        #expect(p.area == "Shinjuku")
        #expect(p.city == "Tóquio")
        #expect(p.dayLine == "Dom · 15 nov") // 15/11/2026 é domingo (o design arredonda pra "Sáb")
        #expect(p.stops.first?.time == "08:30")
        #expect(p.stops.map(\.label).contains("Udatsu Sushi"))
        #expect(p.stops.first { $0.label.hasPrefix("Fuunji") }?.price == "¥ 1.250")
        #expect(p.coverRGB == TripTheme.japan.coverRGB)
    }

    @Test func miniMapaSoComDuasCoordenadas() {
        #expect(poster().hasMap)
        let none = DayPoster.make(plan: DayEngineStub.qaDay, region: .jp, areaName: nil, cityName: nil)
        #expect(!none.hasMap)
        #expect(none.area == "Shinjuku") // sem bairro: o primeiro pedaço do título
    }

    @Test func projecaoCabeNoQuadro() {
        let rect = CGRect(x: 12, y: 12, width: 152, height: 108)
        let points = PosterRouteSketch.project(poster().route, in: rect)
        #expect(points.count == 3)
        for p in points { #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(p)) }
        // Norte em cima: Gyoen (35.6852) fica acima de Udatsu (35.6440).
        #expect(points[1].y < points[2].y)
    }

    @Test func cartazDoLinkRecebido() throws {
        let shared = SharedDay(plan: DayEngineStub.qaDay, region: .jp, areaName: "Shinjuku", cityName: "Tóquio")
        let p = try #require(DayPoster.make(shared: shared))
        #expect(p.numeral == "3")
        #expect(p.stops.count == 9)
        #expect(p.stops.allSatisfy { $0.price == nil })
    }

    @Test func pdfUmDiaPorPagina() throws {
        let days = Array(repeating: poster(), count: 14)
        let data = DayPosterRenderer.pdf(days, options: PosterOptions())
        let doc = try #require(PDFDocument(data: data))
        #expect(doc.pageCount == 14)
        let box = try #require(doc.page(at: 0)?.bounds(for: .mediaBox))
        #expect(box.width == 360)
        #expect(box.height == 640)
    }

    // MARK: Pixels

    static func pixel(_ image: UIImage, x: Int, y: Int) -> UInt32? {
        guard let cg = image.cgImage else { return nil }
        var data = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: -x, y: y - cg.height + 1, width: cg.width, height: cg.height))
        return UInt32(data[0]) << 16 | UInt32(data[1]) << 8 | UInt32(data[2])
    }

    static func close(_ a: UInt32, _ b: UInt32, tolerance: Int = 6) -> Bool {
        [16, 8, 0].allSatisfy { abs(Int((a >> $0) & 0xFF) - Int((b >> $0) & 0xFF)) <= tolerance }
    }
}
