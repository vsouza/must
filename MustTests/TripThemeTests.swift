import SwiftUI
import Testing
import UIKit
@testable import Must

/// Tema da viagem (prompt 20): tokens exatos por país, tabela aberta, lavado com "Reduzir transparência",
/// bandeira, e a regra de que a identidade (verde, azul, tinta, links) não muda com o país.
@MainActor
struct TripThemeTests {
    /// 0xRRGGBB de uma `Color` (pelo que o UIKit resolve), pra comparar com os hex do prompt.
    private func hex(_ color: Color) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = UInt32((r * 255).rounded()), gi = UInt32((g * 255).rounded()), bi = UInt32((b * 255).rounded())
        return ri << 16 | gi << 8 | bi
    }

    private func alpha(_ color: Color) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return a
    }

    // MARK: Tokens exatos (prompt 20 · regra 1)

    @Test func japaoTemOsTonsDoPrompt() {
        let jp = TripTheme.japan
        #expect(jp.country == "JP")
        #expect(jp.trip == 0xBC002D)
        #expect(jp.tripInk == 0x8A0021)
        #expect(jp.tripSoft == 0xFDECEF)
        #expect(jp.tripSoft2 == 0xFFF6F7)
        #expect(jp.stampInk == 0xC8102E)
    }

    @Test func brasilTemOsTonsDoPrompt() {
        let br = TripTheme.brazil
        #expect(br.country == "BR")
        #expect(br.trip == 0x009C3B)
        #expect(br.tripInk == 0x00692A)
        #expect(br.tripSoft == 0xE6F6EC)
        #expect(br.tripSoft2 == 0xFFF9DB)
        #expect(br.stampInk == 0x00692A)
    }

    @Test func tintasResolvemParaOMesmoHexNaView() {
        #expect(hex(TripTheme.japan.tripColor) == 0xBC002D)
        #expect(hex(TripTheme.japan.stampInkColor) == 0xC8102E)
        #expect(hex(TripTheme.brazil.tripInkColor) == 0x00692A)
        #expect(hex(StampPalette.ink(.japan)) == 0xC8102E)
        #expect(hex(StampPalette.ink(.brazil)) == 0x00692A)
    }

    // MARK: Região → país → tema

    @Test func cadaRegiaoTemOPaisDelaNoTema() {
        #expect(Region.bh.country == "BR")
        #expect(Region.jp.country == "JP")
        #expect(TripTheme.forRegion(.bh) == .brazil)
        #expect(TripTheme.forRegion(.jp) == .japan)
    }

    @Test func tabelaAbertaAceitaPaisNovoEPaisDesconhecidoCaiNoNeutro() {
        #expect(TripTheme.forCountry("jp") == .japan)
        #expect(TripTheme.forCountry("BR") == .brazil)
        #expect(TripTheme.forCountry("US") == .neutral)
        #expect(TripTheme.forCountry("") == .neutral)
        #expect(TripTheme.forCountry(nil) == .neutral)
    }

    @Test func chavesDaTabelaSaoISOEBatemComOPais() {
        for (iso, theme) in TripTheme.byCountry {
            #expect(iso.count == 2)
            #expect(iso == iso.uppercased())
            #expect(theme.country == iso)
        }
    }

    @Test func neutroNaoLavaOTopoNemTemPais() {
        #expect(TripTheme.neutral.washes == false)
        #expect(TripTheme.neutral.country.isEmpty)
        #expect(hex(TripTheme.neutral.labelColor) == 0x7A7F87)
        #expect(TripTheme.japan.washes)
        #expect(hex(TripTheme.japan.labelColor) == 0x8A0021)
    }

    // MARK: Identidade não muda (prompt 20 · item 3)

    /// Verde, verde-texto, azul, azul-texto, tinta, link e secundário: o que não pode mudar com o país.
    private let identity: Set<UInt32> = [0x22DD7E, 0x0B2A18, 0x2B7BFF, 0x0F3B8C, 0x121316, 0x1E73FF, 0x7A7F87]

    @Test func tomDoPaisNaoUsaCorDeIdentidade() {
        for theme in [TripTheme.japan, TripTheme.brazil] {
            let tokens: [UInt32] = [theme.trip, theme.tripInk, theme.tripSoft, theme.tripSoft2, theme.stampInk]
            for token in tokens {
                #expect(!identity.contains(token), "token \(String(token, radix: 16)) de \(theme.country) é cor de identidade")
            }
        }
    }

    @Test func tokensDeIdentidadeSaoOsMesmosQualquerQueSejaARegiao() {
        // A paleta é uma constante só: trocar de região não mexe nela.
        #expect(hex(Color.must.green) == 0x22DD7E)
        #expect(hex(Color.must.greenText) == 0x0B2A18)
        #expect(hex(Color.must.blue) == 0x2B7BFF)
        #expect(hex(Color.must.blueText) == 0x0F3B8C)
        #expect(hex(Color.must.ink) == 0x121316)
        #expect(hex(Color.must.link) == 0x1E73FF)
        #expect(hex(Color.must.secondary) == 0x7A7F87)
    }

    // MARK: Lavado (item 2 e regra 6)

    @Test func lavadoTemTrezentosPontosComGradienteECorSolidaComReduzirTransparencia() {
        #expect(TripWash.shape(for: .japan, reduceTransparency: false) == .gradient(height: 300))
        #expect(TripWash.shape(for: .brazil, reduceTransparency: false) == .gradient(height: 300))
        #expect(TripWash.shape(for: .japan, reduceTransparency: true) == .solid(color: 0xFFF6F7, height: 120))
        #expect(TripWash.shape(for: .brazil, reduceTransparency: true) == .solid(color: 0xFFF9DB, height: 120))
        #expect(TripWash.shape(for: .neutral, reduceTransparency: false) == .none)
        #expect(TripWash.shape(for: .neutral, reduceTransparency: true) == .none)
    }

    // MARK: Selos

    @Test func selosNoFundoDoPaisNaOpacidadePedida() {
        let fill = StampPalette.photoFill(.japan, opacity: 0.55)
        #expect(hex(fill) == 0xC8102E)
        #expect(abs(alpha(fill) - 0.55) < 0.01)
        #expect(hex(StampPalette.onPhoto) == 0xFFFFFF)
    }

    // MARK: Bandeira (item 4)

    @Test func bandeiraSoDesenhadaParaJaponEBrasil() {
        #expect(TripFlag.drawsFlag(for: "JP"))
        #expect(TripFlag.drawsFlag(for: "BR"))
        #expect(!TripFlag.drawsFlag(for: ""))
        #expect(!TripFlag.drawsFlag(for: "US"))
    }
}
