import CoreLocation
import Foundation
import MapKit
import Testing
@testable import Must

@MainActor
struct ExplorarPinTests {
    private func item(_ id: String, own: Bool = true, open: Bool = false, confirmed: Bool = true, inPlan: Bool = false, done: Bool = false,
                      planTime: String? = nil, lat: Double = 35.6938, lng: Double = 139.7034) -> ExplorarItem {
        var i = ExplorarItem(id: id, placeId: own ? id : nil, name: id, lat: lat, lng: lng, tone: own ? .own : .outside, isOpen: open,
                             done: done, inPlan: inPlan, meta: "", meters: 300)
        i.hoursConfirmed = confirmed
        i.planTime = planTime
        return i
    }

    private func env(hour: Int, minute: Int = 0) -> QueroEnv {
        let region = Region.jp
        let day = region.calendar.startOfDay(for: Date(timeIntervalSince1970: 1_794_000_000))
        let now = day.addingTimeInterval(Double(hour * 3600 + minute * 60))
        let origin = CLLocationCoordinate2D(latitude: 35.6900, longitude: 139.7000)
        return QueroEnv(region: region, now: now, plan: nil, center: origin, origin: origin, areaName: "Shinjuku", cityGroup: "tokyo",
                        cityId: "tokyo1", online: true, board: [], useModel: false, walkMaxKm: 1.5)
    }

    // MARK: + dia / no dia

    @Test func ownMustInTheDayShowsItsTime() {
        let day = ExplorarPinActions.day(for: item("a", inPlan: true, planTime: "15:30"), env: env(hour: 14))
        #expect(day == .inDay(time: "15:30"))
    }

    @Test func doneMustHasNoDayAction() {
        #expect(ExplorarPinActions.day(for: item("a", done: true), env: env(hour: 14)) == .none)
    }

    @Test func fitsInAnEmptyAfternoonAndNotAtNight() {
        if case .fit(let slot) = ExplorarPinActions.day(for: item("a"), env: env(hour: 14)) {
            #expect(slot.end.timeIntervalSince(slot.start) == 25 * 60)
        } else {
            Issue.record("devia caber às 14h")
        }
        #expect(ExplorarPinActions.day(for: item("a"), env: env(hour: 22, minute: 20)) == .noFit(reason: "já é tarde pra hoje"))
    }

    @Test func onlyOutsidePinsCanBeSaved() {
        #expect(ExplorarPinActions.canSave(item("a", own: false)))
        #expect(!ExplorarPinActions.canSave(item("a", own: true)))
    }

    @Test func rowCarriesTheGoogleIdAndTheSlot() {
        var out = item("out-1", own: false)
        out.googleId = "g123"
        let result = ExplorarPinActions.wantResult(out)
        #expect(result.origin == .places && result.googlePlaceId == "g123" && result.boardPlaceId == nil)
        let own = ExplorarPinActions.wantResult(item("p1"))
        #expect(own.origin == .board && own.boardPlaceId == "p1")
    }

    // MARK: aberto agora

    @Test func openLayerNeverShowsABareZero() {
        let items = [item("a"), item("b", confirmed: false), item("c", confirmed: false)]
        let s = ExplorarLayers.openSummary(items)
        #expect(s == ExplorarOpenSummary(confirmed: 0, estimated: 0, unknown: 2))
        #expect(s.label == "aberto agora · 2 sem horário")
        #expect(!s.label.hasSuffix("· 0"))
    }

    @Test func openLabelMixesConfirmedEstimatedAndUnknown() {
        let items = [item("a", open: true), item("b", open: true), item("c", open: true, confirmed: false)]
            + (0..<14).map { item("u\($0)", confirmed: false) }
        let s = ExplorarLayers.openSummary(items)
        #expect(s.label == "aberto agora · 2 · 1 estimado · 14 sem horário")
    }

    @Test func allConfirmedAndClosedSaysNone() {
        #expect(ExplorarLayers.openSummary([item("a"), item("b", own: false)]).label == "aberto agora · nenhum")
    }

    @Test func openFilterDropsOnlyWhatIsKnownClosed() {
        let items = [item("open", open: true), item("closed"), item("unknown", confirmed: false)]
        let kept = ExplorarLayers.filter(items, layers: [.own, .openNow]).map(\.id)
        #expect(kept.contains("open") && kept.contains("unknown") && !kept.contains("closed"))
    }

    // MARK: Fora do board: uma vez por bairro por sessão

    @Test func fetchesOncePerAreaPerSession() {
        var policy = ExplorarOutsidePolicy()
        #expect(policy.decide(area: "nakano", region: .jp, status: .online) == .fetch)
        #expect(policy.decide(area: "nakano", region: .jp, status: .online) == .alreadyThisSession)
        #expect(policy.decide(area: "ueno", region: .jp, status: .online) == .fetch)
        #expect(policy.decide(area: "nakano", region: .bh, status: .online) == .fetch)
    }

    @Test func offlineAndLowDataNeverFetchAndKeepTheTurn() {
        var policy = ExplorarOutsidePolicy()
        #expect(policy.decide(area: "nakano", region: .jp, status: .offline) == .offline)
        #expect(policy.decide(area: "nakano", region: .jp, status: .constrained) == .lowData)
        #expect(policy.decide(area: "nakano", region: .jp, status: .online) == .fetch)
    }

    @Test func offlineStateExplainsItself() {
        #expect(ExplorarOutsideState.offline.note == "sem internet · só o que já estava guardado")
        #expect(ExplorarOutsideState.lowData.note?.contains("pouco dado") == true)
        #expect(ExplorarOutsideState.loaded.note == nil)
    }

    @Test func modelTracksTheStateFromTheDecision() {
        let model = ExplorarModel()
        ExplorarModel.outsidePolicy = ExplorarOutsidePolicy()
        #expect(model.outsideDecision(area: "x", region: .jp, status: .offline) == .offline)
        #expect(model.outsideState == .offline)
        #expect(model.outsideDecision(area: "x", region: .jp, status: .online) == .fetch)
        #expect(model.outsideState == .loading)
        model.outsideFinished()
        #expect(model.outsideState == .loaded)
        ExplorarModel.outsidePolicy = ExplorarOutsidePolicy()
    }

    // MARK: Presentes › Local: região de busca

    @Test func giftSearchRegionUsesTheTripCityNotBrazilGPS() {
        let tokyo = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        let belo = CLLocationCoordinate2D(latitude: -19.9167, longitude: -43.9345)
        let region = GiftStoreSearch.searchRegion(gps: belo, cityCenter: tokyo, hasCurrentCity: true)
        #expect(abs(region.center.latitude - tokyo.latitude) < 0.0001)
        #expect(abs(region.center.longitude - tokyo.longitude) < 0.0001)
        #expect(region.span.latitudeDelta > 0.05 && region.span.latitudeDelta < 0.12)
    }

    @Test func giftSearchRegionFollowsTheGPSInsideTheCity() {
        let tokyo = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        let shibuya = CLLocationCoordinate2D(latitude: 35.6580, longitude: 139.7016)
        let region = GiftStoreSearch.searchRegion(gps: shibuya, cityCenter: tokyo, hasCurrentCity: true)
        #expect(abs(region.center.latitude - shibuya.latitude) < 0.0001)
    }

    @Test func giftOutsideResultsDropWhatIsAlreadyOnTheBoard() {
        let hits = [
            GiftStoreSearch.Hit(name: "Don Quijote Shinjuku", lat: 35.6950, lng: 139.7010, address: ""),
            GiftStoreSearch.Hit(name: "Daiso Harajuku", lat: 35.6700, lng: 139.7030, address: "Jingumae"),
            GiftStoreSearch.Hit(name: "Daiso Harajuku", lat: 35.6700, lng: 139.7030, address: "Jingumae"),
        ]
        let out = GiftStoreSearch.outside(hits, board: [("Don Quijote Shinjuku", 35.6950, 139.7010)])
        #expect(out.map(\.name) == ["Daiso Harajuku"])
    }

    @Test func giftOutsideResultsNeverShowJapanese() {
        let hits = [
            GiftStoreSearch.Hit(name: "ビックカメラ 渋谷東口店", lat: 35.6590, lng: 139.7030, address: "渋谷1-24-10"),
            GiftStoreSearch.Hit(name: "Bic Camera Shinjuku", lat: 35.6900, lng: 139.7000, address: "西新宿1丁目5番1号"),
            GiftStoreSearch.Hit(name: "Bic Camera", lat: 35.6910, lng: 139.7040, address: "Shinjuku 3-Chōme 26-10"),
        ]
        let out = GiftStoreSearch.outside(hits, board: [])
        #expect(out.map(\.name) == ["Bic Camera Shinjuku", "Bic Camera"])
        #expect(out.map(\.address) == ["", "Shinjuku 3-Chōme 26-10"])
    }
}
