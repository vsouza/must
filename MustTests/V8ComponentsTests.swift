import SwiftUI
import Testing
import UIKit
@testable import Must

/// Identidade v8 (prompt 23 §1): três cores, o visual v5 redirecionado (sem lima/azul/verde, sem cor por lista, sem
/// cor de linha de trem, sem lavado) e os componentes v8.
@MainActor
struct V8ComponentsTests {
    private func hex(_ color: Color) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return UInt32((r * 255).rounded()) << 16 | UInt32((g * 255).rounded()) << 8 | UInt32((b * 255).rounded())
    }

    /// Tudo que a v8 permite: as três cores, os cinzas de texto, grafite, osso, filetes e branco.
    private var allowed: Set<UInt32> {
        [V8.Hex.ink, V8.Hex.paper, V8.Hex.orange, V8.Hex.orangeDeep, V8.Hex.mute, V8.Hex.muteDark, V8.Hex.graphite,
         V8.Hex.bone, V8.Hex.photo, V8.Hex.rule, V8.Hex.ruleStrong, 0xFFFFFF]
    }

    @Test func paletaTemOsHexDoPrompt() {
        #expect(hex(V8.ink) == 0x121212)
        #expect(hex(V8.paper) == 0xF2F0EA)
        #expect(hex(V8.orange) == 0xFF4A1C)
        #expect(hex(V8.orangeDeep) == 0xC8330A)
        #expect(hex(V8.mute) == 0x6B6B66)
        #expect(hex(V8.muteDark) == 0xA3A39C)
        #expect(hex(V8.graphite) == 0x2B2B2B)
        #expect(V8.Hex.identity == [0x121212, 0xF2F0EA, 0xFF4A1C])
    }

    @Test func tokensV5ViramIdentidadeV8() {
        let p = Color.must
        for token in [p.bg, p.ink, p.secondary, p.surface, p.surface2, p.line, p.lineStrong, p.green, p.greenText,
                      p.blue, p.blueText, p.greenTextSoft, p.link] {
            #expect(allowed.contains(hex(token)), "token v5 \(String(hex(token), radix: 16)) fora da v8")
        }
        // Lima, verde e azul da v5 sumiram.
        for old: UInt32 in [0x22DD7E, 0x2B7BFF, 0xD4FF3A, 0x1E73FF, 0x0F3B8C, 0x0B2A18] {
            #expect(![p.green, p.blue, p.link, p.blueText, p.greenText].map(hex).contains(old))
        }
        #expect(hex(p.bg) == V8.Hex.paper, "fundo padrão das telas = papel")
    }

    @Test func listasNaoTemMaisCor() {
        let lights = Set(MustColor.allCases.map { hex($0.light) })
        let strongs = Set(MustColor.allCases.map { hex($0.strong) })
        let texts = Set(MustColor.allCases.map { hex($0.text) })
        #expect(lights.count == 1 && strongs.count == 1 && texts.count == 1, "toda lista igual")
        for c in lights.union(strongs).union(texts) { #expect(allowed.contains(c)) }
        #expect(hex(MustColor.eat.text) == V8.Hex.ink)
    }

    @Test func gradientesV5ViramCorSolidaDaIdentidade() {
        for c in [MustGradient.goldLight, MustGradient.goldStrong, MustGradient.goldText, MustGradient.goldArc,
                  MustGradient.duskLight, MustGradient.duskStrong, MustGradient.duskText] {
            #expect(allowed.contains(hex(c)))
        }
        #expect(hex(MustGradient.goldStrong) == V8.Hex.orange)
    }

    @Test func linhaDeTremViraBadgePreto() {
        for rgb: UInt32 in [0x80C241, 0xF15A22, 0xFF9500, 0x000000] {
            #expect(hex(LineChip.codeColor(for: rgb)) == 0xFFFFFF)
        }
    }

    @Test func estadosDoIndexRow() {
        #expect(IndexRowState.now.label == "agora")
        #expect(IndexRowState.opensAt("17h").label == "abre 17h")
        #expect(IndexRowState.reservation("19:00").label == "reserva 19:00")
        #expect(IndexRowState.now.isLive && IndexRowState.open.isLive && IndexRowState.reservation("19:00").isLive)
        #expect(!IndexRowState.done.isLive && !IndexRowState.closed.isLive && !IndexRowState.opensAt("17h").isLive)
    }

    @Test func picoteDoBilheteCortaAsDuasLaterais() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 160)
        let path = TicketShape(notchY: 60, notch: 11, corner: 24).path(in: rect)
        #expect(!path.contains(CGPoint(x: 2, y: 60)), "picote da esquerda")
        #expect(!path.contains(CGPoint(x: 298, y: 60)), "picote da direita")
        #expect(path.contains(CGPoint(x: 2, y: 100)))
        #expect(path.contains(CGPoint(x: 150, y: 60)))
    }

    @Test func barraTemQuatroAbasNaOrdemDoDesign() {
        #expect(MustTab.allCases == [.hoje, .explorar, .musts, .viagem])
        #expect(MustTab.allCases.map(\.title) == ["Hoje", "Explorar", "Musts", "Viagem"])
        #expect(MustTab.allCases.map(\.glyph) == [.clock, .map, .lines, .briefcase])
    }

    @Test func aneisSeguemOPadraoDaCapa() {
        #expect(Rings.pattern.count == 3)
        #expect(Rings.pattern[0] == .zero)
    }

    @Test func iconeDoFeitoNaoTemJapones() {
        #expect(!StationStamp.usesKanji(MustIcon.feito.label))
        for icon in MustIcon.allCases { #expect(!StationStamp.usesKanji(icon.label), "\(icon.rawValue)") }
    }

    @Test func appUsaOIconeDoCatalogo() {
        // O PNG (1024, RGB sem alpha) é gerado por `scripts/gen-icons.py --app-icon`; aqui, que o app aponta pra ele.
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        #expect((primary?["CFBundleIconName"] as? String) == "AppIconV8")
    }
}
