import CoreLocation
import Foundation
import SwiftUI

// Contrato do prompt 28 (06/11/2026) entre a F0 (Trip/TripRegistry/TripStore, agente p28/f0) e o fluxo
// Nova viagem (telas NovaViagem1…9, agente p28/f3). O fluxo só preenche um `NewTripDraft` e chama
// `TripCreating.create(_:)`; quem grava o registro, abre o container e troca a viagem atual é a F0.

/// O que o fluxo Nova viagem juntou. Todo passo é opcional, menos o destino (passo 1).
struct NewTripDraft: Equatable, Sendable {
    // Passo 1 · Pra onde?
    var name: String = ""
    /// ISO 3166-1 alfa-2 ("PT").
    var countryCode: String = ""
    /// ISO 4217 ("EUR").
    var currency: String = ""
    /// Fuso padrão do país (cada cidade pode ter o seu).
    var timeZoneId: String = ""
    /// Cor da capa ("#1F5FB4"); a do país por padrão, trocável entre 6 amostras.
    var colorHex: String = ""

    // Passo 2 · Quando? (nil = "ainda não sei", viagem em plano)
    var start: Date?
    var end: Date?

    // Passo 3 · Quais cidades? (na ordem; a mesma cidade pode repetir)
    var cities: [City] = []

    // Passo 5 · Como vai?
    var flights: [FlightDraft] = []

    // Passo 6 · O que não pode faltar? Lugares já conferidos pelo usuário.
    var places: [PlaceDraft] = []

    // Passo 7 · Quanto gastar? (moeda da viagem, por dia por pessoa)
    var perDayBudget: Double?
    /// 1 unidade da moeda em R$ (câmbio do dia em cache, ou digitado).
    var fxRate: Double?

    // Passo 8 · Leve pro bolso.
    var downloadOfflineMaps = false
    var wifiOnly = true

    struct City: Equatable, Sendable, Identifiable {
        var id: String = UUID().uuidString
        var name: String
        var latitude: Double
        var longitude: Double
        var nights: Int = 1
        var timeZoneId: String?
        // Passo 4 · Onde fica? (hospedagem ou só o bairro)
        var lodgingName: String?
        var lodgingAddress: String?
        var lodgingLatitude: Double?
        var lodgingLongitude: Double?
        var neighborhoodOnly: String?
        var checkIn: Date?
        var checkOut: Date?
    }

    struct FlightDraft: Equatable, Sendable {
        var number: String
        var from: String
        var to: String
        var departure: Date?
        var arrival: Date?
        var isReturn: Bool
    }

    struct PlaceDraft: Equatable, Sendable {
        var name: String
        var cityId: String?
        /// `MustList.kind`/lista de destino ("eat", "drink", "see"…), como o extrator devolve.
        var listId: String?
        var latitude: Double?
        var longitude: Double?
        var googlePlaceId: String?
        var note: String?
    }

    /// Soma de noites das cidades = dias da viagem − 1 (conferência "8 noites de 8").
    var totalNights: Int { cities.reduce(0) { $0 + $1.nights } }
    var tripNights: Int? {
        guard let start, let end else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: start, to: end).day
    }
}

/// Cria a viagem a partir do rascunho e a deixa como atual (F0 implementa no `TripStore`).
@MainActor
protocol TripCreating {
    /// Retorna o id da viagem criada.
    func create(_ draft: NewTripDraft) async throws -> String
    /// Destinos que já são viagem (passo 1 mostra apagado "você já tem uma viagem aqui").
    func existingCountryCodes() -> Set<String>
}

/// Sem F0 ainda: não cria nada (os prints e o fluxo funcionam até o último passo).
struct NoTripCreator: TripCreating {
    struct NotYet: Error {}
    func create(_ draft: NewTripDraft) async throws -> String { throw NotYet() }
    func existingCountryCodes() -> Set<String> { ["BR", "JP", "IT"] }
}

private struct TripCreatorKey: EnvironmentKey {
    static var defaultValue: any TripCreating { MainActor.assumeIsolated { NoTripCreator() } }
}

extension EnvironmentValues {
    var tripCreator: any TripCreating {
        get { self[TripCreatorKey.self] }
        set { self[TripCreatorKey.self] = newValue }
    }
}
