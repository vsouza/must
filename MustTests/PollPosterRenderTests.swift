import Testing
import UIKit
@testable import Must

/// O cartaz "A ou B?" sai como PNG 1080×1920 (o tamanho de story do WhatsApp/Instagram), mesmo sem foto no disco.
@MainActor
@Suite("Cartaz A ou B: exportação")
struct PollPosterRenderTests {
    private let poster = PollPoster(
        a: .init(name: "% ARABICA Kyoto Arashiyama", area: "Arashiyama", minutes: "8 min", photoPath: nil),
        b: .init(name: "Weekenders Coffee Tominokoji, com um nome bem comprido pra quebrar", area: "Kawaramachi", minutes: "", photoPath: nil),
        city: "Kyoto", coverRGB: 0xD7000F)

    @Test("PNG em 1080×1920")
    func size() throws {
        let data = try #require(PollPosterRenderer.png(poster))
        let image = try #require(UIImage(data: data))
        #expect(image.size.width * image.scale == 1080)
        #expect(image.size.height * image.scale == 1920)
    }

    @Test("Arquivo pronto pro compartilhar, com o nome dos dois lugares")
    func file() throws {
        let url = try #require(PollPosterRenderer.url(poster))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.lastPathComponent.hasSuffix(".png"))
        #expect(url.lastPathComponent.contains("ARABICA"))
    }
}

@Suite("Cartaz A ou B: tempo até o lugar")
struct PollPosterMinutesTests {
    @Test("Perto mostra os minutos; outra cidade ou sem GPS, nada")
    func minutes() {
        #expect(PollSideInfo.minutesText(8) == "8 min")
        #expect(PollSideInfo.minutesText(90) == "90 min")
        #expect(PollSideInfo.minutesText(440) == "")
        #expect(PollSideInfo.minutesText(nil) == "")
    }
}
