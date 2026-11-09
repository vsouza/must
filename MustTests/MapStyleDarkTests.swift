import Foundation
import Testing
@testable import Must

@Suite("Mapa · style escuro")
struct MapStyleDarkTests {
    private func template() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Must/DesignSystem/MapStyle/must-relief.style.json")
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func layers(_ style: [String: Any]) -> [[String: Any]] { style["layers"] as? [[String: Any]] ?? [] }

    private func paint(_ style: [String: Any], _ id: String) throws -> [String: Any] {
        try #require(layers(style).first { $0["id"] as? String == id }?["paint"] as? [String: Any])
    }

    @Test("o escuro tem as mesmas camadas, fontes, sprite e glyphs do claro")
    func sameStructure() throws {
        let base = try template()
        let tiles = MapTiles.hosted(key: "x")
        let light = MapStyleLoader.customize(base, region: .bh, tiles: tiles, dark: false)
        let dark = MapStyleLoader.customize(base, region: .bh, tiles: tiles, dark: true)
        #expect(layers(light).map { $0["id"] as? String } == layers(dark).map { $0["id"] as? String })
        #expect(layers(light).map { $0["type"] as? String } == layers(dark).map { $0["type"] as? String })
        let fonts: ([[String: Any]]) -> [String] = { $0.compactMap { ($0["layout"] as? [String: Any])?["text-font"] }.map { "\($0)" } }
        #expect(fonts(layers(light)) == fonts(layers(dark)))
        #expect(light["glyphs"] as? String == dark["glyphs"] as? String)
        #expect(light["sprite"] as? String == dark["sprite"] as? String)
        let text: ([[String: Any]]) -> [String] = { $0.compactMap { ($0["layout"] as? [String: Any])?["text-field"] }.map { "\($0)" } }
        #expect(text(layers(light)) == text(layers(dark)))
    }

    @Test("o escuro troca as cores e serializa em JSON válido")
    func darkColors() throws {
        let base = try template()
        let dark = MapStyleLoader.customize(base, region: .jp, tiles: .hosted(key: "x"), dark: true)
        _ = try JSONSerialization.data(withJSONObject: dark)
        #expect(try paint(dark, "bg")["background-color"] as? String == "#1B1D22")
        #expect(try paint(dark, "city-labels")["text-color"] as? String == "#F2F3F5")
        #expect(try paint(dark, "water")["fill-color"] as? String != "#D9E4EF")
    }

    @Test("o claro continua igual")
    func lightUntouched() throws {
        let base = try template()
        let light = MapStyleLoader.customize(base, region: .bh, tiles: .hosted(key: "x"))
        #expect(try paint(light, "bg")["background-color"] as? String == "#E9EBEF")
    }

    @Test("o arquivo do style escuro fica separado do claro")
    func separateFile() {
        let light = MapStyleLoader.styleURL(region: .bh, tiles: .none, dark: false)
        let dark = MapStyleLoader.styleURL(region: .bh, tiles: .none, dark: true)
        #expect(light != nil && dark != nil && light != dark)
    }
}
