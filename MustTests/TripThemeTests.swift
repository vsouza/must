import SwiftUI
import Testing
import UIKit
@testable import Must

/// Cor do lugar (v8, prompt 23 §1 e prompt 24 §1): tokens exatos por país, tabela aberta, bandeira, e a regra de que a
/// cor do lugar só entra na capa, na Boa noite e no anel do selo — a barra, os botões, as listas e os links nunca mudam
/// com a região.
@MainActor
struct TripThemeTests {
    /// 0xRRGGBB de uma `Color` (pelo que o UIKit resolve), pra comparar com os hex do prompt.
    private func hex(_ color: Color) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = UInt32((r * 255).rounded()), gi = UInt32((g * 255).rounded()), bi = UInt32((b * 255).rounded())
        return ri << 16 | gi << 8 | bi
    }

    // MARK: Tokens exatos

    @Test func corDoLugarDeCadaPais() {
        #expect(TripTheme.japan.coverRGB == 0xD7000F)
        #expect(TripTheme.brazil.coverRGB == 0x007A33)
        #expect(TripTheme.italy.coverRGB == 0x1F5FB4)
        #expect(hex(TripTheme.japan.cover) == 0xD7000F)
        #expect(hex(TripTheme.brazil.cover) == 0x007A33)
        #expect(hex(TripTheme.italy.cover) == 0x1F5FB4)
    }

    @Test func comViagemATintaDaCapaEBrancaSemViagemPapelETinta() {
        for theme in [TripTheme.japan, .brazil, .italy] {
            #expect(hex(theme.coverInk) == 0xFFFFFF, "\(theme.country)")
        }
        #expect(hex(TripTheme.neutral.cover) == V8.Hex.paper)
        #expect(hex(TripTheme.neutral.coverInk) == V8.Hex.ink)
        #expect(TripTheme.neutral.hasTrip == false)
    }

    @Test func coresDosPaisesNaoSeRepetemNemSaoDaIdentidade() {
        let covers = [TripTheme.japan, .brazil, .italy].map(\.coverRGB)
        #expect(Set(covers).count == covers.count)
        for c in covers { #expect(!V8.Hex.identity.contains(c)) }
    }

    // MARK: Região → país → tema

    @Test func cadaRegiaoTemOPaisDelaNoTema() {
        #expect(Region.bh.country == "BR")
        #expect(Region.jp.country == "JP")
        #expect(Region.it.country == "IT")
        #expect(TripTheme.forRegion(.bh) == .brazil)
        #expect(TripTheme.forRegion(.jp) == .japan)
        #expect(TripTheme.forRegion(.it) == .italy)
    }

    @Test func tabelaAbertaAceitaPaisNovoEPaisDesconhecidoCaiNoNeutro() {
        #expect(TripTheme.forCountry("jp") == .japan)
        #expect(TripTheme.forCountry("BR") == .brazil)
        #expect(TripTheme.forCountry("it") == .italy)
        #expect(TripTheme.forCountry("US") == .neutral)
        #expect(TripTheme.forCountry("") == .neutral)
        #expect(TripTheme.forCountry(nil) == .neutral)
        #expect(TripTheme.coverHex("JP") == 0xD7000F)
        #expect(TripTheme.coverHex("XX") == V8.Hex.paper)
    }

    @Test func chavesDaTabelaSaoISOEBatemComOPais() {
        for (iso, theme) in TripTheme.byCountry {
            #expect(iso.count == 2)
            #expect(iso == iso.uppercased())
            #expect(theme.country == iso)
        }
    }

    // MARK: A cor do lugar só na capa, na Boa noite e no anel do selo

    @Test func corDoLugarSoNoAnelDoSelo() {
        #expect(hex(StampPalette.ink(.japan)) == 0xD7000F)
        #expect(hex(StampPalette.ink(.brazil)) == 0x007A33)
        #expect(hex(StampPalette.ink(.italy)) == 0x1F5FB4)
        #expect(hex(StampPalette.ink(.neutral)) == V8.Hex.ink)
        // O miolo do selo é papel, nunca a cor do lugar.
        #expect(hex(StampPalette.photoFill(.japan, opacity: 0.55)) == V8.Hex.paper)
    }

    @Test func abaTituloERotuloNaoUsamACorDoLugar() {
        for theme in [TripTheme.japan, .brazil, .italy, .neutral] {
            #expect(hex(theme.tripColor) == V8.Hex.ink, "\(theme.country)")
            #expect(hex(theme.labelColor) == V8.Hex.mute, "\(theme.country)")
            #expect(theme.washes == false, "\(theme.country): sem lavado na v8")
        }
    }

    /// A barra e os botões são constantes: não leem o tema. A paleta é uma só, qualquer que seja a região.
    @Test func barraEBotoesNuncaMudamComARegiao() {
        #expect(hex(V8.orange) == 0xFF4A1C)
        #expect(hex(V8.ink) == 0x121212)
        #expect(hex(V8.paper) == 0xF2F0EA)
        #expect(hex(Color.must.green) == 0xFF4A1C, "ação = laranja")
        #expect(hex(Color.must.greenText) == 0x121212)
        #expect(hex(Color.must.link) == 0xC8330A)
        #expect(hex(Color.must.bg) == 0xF2F0EA)
        let covers = Set([TripTheme.japan, .brazil, .italy].map(\.coverRGB))
        for token in [Color.must.green, Color.must.blue, Color.must.link, Color.must.ink, Color.must.secondary, V8.orange, V8.ink] {
            #expect(!covers.contains(hex(token)))
        }
    }

    // MARK: Bandeira

    @Test func bandeiraDesenhadaParaJapaoBrasilEItalia() {
        #expect(TripFlag.drawsFlag(for: "JP"))
        #expect(TripFlag.drawsFlag(for: "BR"))
        #expect(TripFlag.drawsFlag(for: "IT"))
        #expect(TripFlag.drawsFlag(for: "it"))
        #expect(!TripFlag.drawsFlag(for: ""))
        #expect(!TripFlag.drawsFlag(for: "US"))
        #expect(TripFlag.label(for: "IT") == "Bandeira da Itália")
    }
}
