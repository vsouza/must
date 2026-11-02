import Foundation
import PDFKit
import Testing
import UIKit
@testable import Must

/// Prompt 15 · A (fatia 3): leitura no aparelho — PDF (texto + QR), .pkpass (stored e deflate), link, página.
/// Sem rede: o .pkpass deflate é um zip real (gerado com `zip -X -9`) embutido em base64.
@MainActor
struct TicketReaderTests {
    /// Zip só com entradas *stored* (método 0): o caminho mais simples do leitor.
    static func storedZip(_ files: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        for file in files {
            let offset = out.count
            let name = Data(file.name.utf8)
            out += le32(0x0403_4b50) + le16(10) + le16(0) + le16(0) + le16(0) + le16(0)
            out += le32(0) + le32(UInt32(file.data.count)) + le32(UInt32(file.data.count))
            out += le16(UInt16(name.count)) + le16(0) + name + file.data
            central += le32(0x0201_4b50) + le16(20) + le16(10) + le16(0) + le16(0) + le16(0) + le16(0)
            central += le32(0) + le32(UInt32(file.data.count)) + le32(UInt32(file.data.count))
            central += le16(UInt16(name.count)) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(UInt32(offset)) + name
        }
        out += central
        out += le32(0x0605_4b50) + le16(0) + le16(0) + le16(UInt16(files.count)) + le16(UInt16(files.count))
        out += le32(UInt32(central.count)) + le32(UInt32(out.count - central.count - 12)) + le16(0)
        return out
    }

    static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    static let passJSON = Data("""
    {"formatVersion":1,"organizationName":"Viator","description":"Sushi Making Class with a Chef in Tsukiji",
     "relevantDate":"2026-11-15T10:00:00+09:00","locations":[{"latitude":35.6654,"longitude":139.7707,"relevantText":"Tsukiji Outer Market, Gate 1"}],
     "barcodes":[{"format":"PKBarcodeFormatQR","message":"BR-7K2M-9931","messageEncoding":"iso-8859-1"}],
     "eventTicket":{"primaryFields":[{"key":"title","label":"Experiência","value":"Sushi Making Class"}],
                    "secondaryFields":[{"key":"people","label":"Pessoas","value":2}]}}
    """.utf8)

    /// Um .pkpass com `pass.json` deflate, gerado pelo `zip` do macOS (não pelo leitor).
    static let deflatePass = Data(base64Encoded: "UEsDBBQAAgAIAKlcYl32TIbdegEAAE8CAAAJAAAAcGFzcy5qc29ubZHbTsMwDIbveYoot6xVu7FDe8dZCHGuuEFceK23maVJlaSFMe2FeA1eDLdFmpCQoir97d+f7WzlwtgS/DNaR0bLNB7ICpzLNhVeFag9LQitTDsxLLAJG9LkTOjReTmQDi2Buq3LeZf1fHWc3T0G0+vhDQeNXYKmT/Bc+RZKbBMIvLEcK9DllirfQeVT7VYkbmBNeilOFbPEO/mVAHG6woUgLTJXr+mN2GlRYQPan4FvKw6j4SSI4yAeZ3GURu05jBL+cqoyeQd3Mn3ZSsV3XxdsGo3DyWR81Cbo5a8Wj5JwOo2me0CGH54Bv2RxV3u03KNdox+IS6aLWO5eB3IONjc8Twfp18m2++uTXr/olIdH7qdE52DZdn3SLylIklG8D5xrNvAKOIF3HMxm4yToGdjwW2SUM1umW1lZKsFuLghV0XPXuGEXD6iwHRzmqPj//KPiB/r+0jkByw2oGv9ddwdxmBtd/Fe3QlP9KXzPDRtw+5rD3etud/ADUEsBAh4DFAACAAgAqVxiXfZMht16AQAATwIAAAkAAAAAAAAAAQAAAKSBAAAAAHBhc3MuanNvblBLBQYAAAAAAQABADcAAAChAQAAAAA=")!

    @Test func storedPassIsReadWithoutSignature() throws {
        let pass = Self.storedZip([("pass.json", Self.passJSON), ("icon.png", Data([0x89, 0x50]))])
        let info = try #require(try PKPassReader.read(pass))
        #expect(info.organization == "Viator")
        #expect(info.barcode == "BR-7K2M-9931")
        #expect(info.barcodeFormat == "PKBarcodeFormatQR")
        #expect(info.locationTexts == ["Tsukiji Outer Market, Gate 1"])
        #expect(info.fields.contains("Experiência: Sushi Making Class"))
        #expect(info.fields.contains("Pessoas: 2"))
        #expect(info.relevantDate != nil)
    }

    @Test func deflatePassFromTheZipToolIsInflated() throws {
        let entries = try ZipReader.entries(in: Self.deflatePass)
        #expect(entries.map(\.name) == ["pass.json"])
        #expect(entries.first?.method == 8)
        let reading = try TicketReader.readPass(Self.deflatePass)
        #expect(reading.codes == ["BR-7K2M-9931"])
        #expect(reading.pass?.description == "Sushi Making Class with a Chef in Tsukiji")
        #expect(reading.text.contains("Tsukiji Outer Market, Gate 1"))
    }

    @Test func zipWithoutPassJSONOrNotAZipIsRejected() {
        #expect(throws: ZipReader.Failure.notAZip) { try ZipReader.entries(in: Data("isto não é zip".utf8)) }
        let noPass = Self.storedZip([("logo.png", Data([1, 2, 3]))])
        #expect(throws: TicketReaderError.unreadablePass) { try TicketReader.readPass(noPass) }
    }

    /// Foto de ingresso: QR com margem branca (Vision lê; o QR cru do CoreImage não tem zona silenciosa).
    @Test func photoOfAQRIsDecodedByVision() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400))
        let photo = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            TicketQR.image(for: "BR-7K2M-9931", points: 300)?.draw(in: CGRect(x: 50, y: 50, width: 300, height: 300))
        }
        let png = try #require(photo.pngData())
        let reading = try await TicketReader.readImage(png)
        #expect(reading.codes == ["BR-7K2M-9931"])
        #expect(reading.sourceLabel == "Foto")
    }

    @Test func pdfTextAndQRAreReadFromThePage() async throws {
        let pdf = Self.makePDF(lines: ["Viator · Confirmação de reserva", "Reference BR-7K2M-9931", "Sat 15 Nov 2026 · 10:00 AM"],
                               qr: "BR-7K2M-9931")
        let reading = try await TicketReader.readPDF(pdf)
        #expect(reading.pages == 1)
        #expect(reading.text.contains("Reference BR-7K2M-9931"))
        #expect(reading.text.contains("Sat 15 Nov 2026"))
        #expect(reading.codes == ["BR-7K2M-9931"])
        #expect(reading.codePages == [1])
        #expect(reading.sourceLabel == "PDF · 1 página")
    }

    @Test func pastedTextAndLinksAreToldApart() {
        let link = TicketReader.readText("  https://www.viator.com/tours/Tsukiji/sushi  ")
        #expect(link.url?.host() == "www.viator.com")
        #expect(link.text.isEmpty)
        let code = TicketReader.readText("BR-7K2M-9931")
        #expect(code.url == nil)
        #expect(code.text == "BR-7K2M-9931")
        // Só http(s): um esquema de app não vira link lido.
        #expect(TicketReader.readText("must://import?id=x").url == nil)
    }

    @Test func pageTextKeepsOpenGraphAndVisibleTextOnly() {
        let html = """
        <html><head><meta property="og:title" content="Sushi &amp; Tsukiji"><script>var x = "Lixo";</script>
        <style>.a{}</style></head><body><h1>Aula de sushi</h1><p>Ponto de encontro: Gate 1</p></body></html>
        """
        let text = TicketReader.pageText(html)
        #expect(text.contains("Sushi & Tsukiji"))
        #expect(text.contains("Aula de sushi"))
        #expect(text.contains("Ponto de encontro: Gate 1"))
        #expect(!text.contains("Lixo"))
    }

    @Test func imageTypeComesFromTheHeader() {
        #expect(TicketReader.imageExtension(for: Data([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0, 0, 0, 0, 0])) == "png")
        #expect(TicketReader.imageExtension(for: Data([0xFF, 0xD8, 0xFF, 0xE0])) == "jpg")
        #expect(TicketReader.imageExtension(for: Data([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0, 0, 0, 0])) == "heic")
    }

    /// PDF de uma página: texto de verdade (camada de texto) e um QR desenhado pelo CoreImage.
    @MainActor
    static func makePDF(lines: [String], qr: String) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 60
            for line in lines {
                (line as NSString).draw(at: CGPoint(x: 48, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
                y += 24
            }
            // Zona silenciosa branca em volta do QR (o CoreImage não desenha margem; ingresso impresso tem).
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 370, y: 410, width: 200, height: 200))
            TicketQR.image(for: qr, points: 180)?.draw(in: CGRect(x: 380, y: 420, width: 180, height: 180))
        }
    }
}
