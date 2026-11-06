import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Must

@MainActor
struct CollectibleTests {
    func world() throws -> (ModelContext, [Place]) {
        let c = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(c)
        let eat = MustList(id: "eat", name: "eat", icon: .ramen, color: .eat)
        let photo = MustList(id: "photo", name: "photo", icon: .cameraFoto, color: .photo, kind: .photo)
        let see = MustList(id: "see", name: "see", icon: .temploTorii, color: .temple)
        ctx.insert(eat); ctx.insert(photo); ctx.insert(see)
        func place(_ id: String, _ name: String, _ list: MustList, _ area: String, city: String = "tokyo1") -> Place {
            let p = Place(id: id, name: name, cityId: city)
            p.list = list; p.area = area; p.sub = "tsukemen"
            ctx.insert(p)
            return p
        }
        let ps = [place("a", "Fuunji", eat, "Shinjuku"), place("b", "Gyoen", photo, "Shinjuku"), place("c", "Udatsu", eat, "Naka-Meguro"),
                  place("d", "Meiji", see, "Harajuku"), place("e", "Kyomizu", see, "Gion", city: "kyoto")]
        return (ctx, ps)
    }

    func at(_ h: Int) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(h) * 3600) }

    @Test func orderFollowsDoneDate() throws {
        let (_, ps) = try world()
        ps[2].done = DoneMark(at: at(1))
        ps[0].done = DoneMark(at: at(5))
        let c = Collectible.make(from: ps[0], in: ps, region: .jp)
        #expect(c?.order == 2)
        #expect(c?.total == 5)
        #expect(Collectible.make(from: ps[2], in: ps, region: .jp)?.order == 1)
        #expect(Collectible.make(from: ps[1], in: ps, region: .jp) == nil)
    }

    @Test func undoRecalculatesOrder() throws {
        let (_, ps) = try world()
        ps[2].done = DoneMark(at: at(1))
        ps[0].done = DoneMark(at: at(5))
        ps[2].done = nil
        #expect(Collectible.make(from: ps[0], in: ps, region: .jp)?.order == 1)
        #expect(Collectible.make(from: ps[2], in: ps, region: .jp) == nil)
    }

    @Test func variants() throws {
        let (_, ps) = try world()
        for (i, p) in ps.enumerated() { p.done = DoneMark(at: at(i)) }
        ps[2].reservation = Reservation(at: at(40), party: 2)
        #expect(Collectible.make(from: ps[0], in: ps, region: .jp)?.variant == .trip)
        #expect(Collectible.make(from: ps[1], in: ps, region: .jp)?.variant == .outdoor) // photo
        #expect(Collectible.make(from: ps[2], in: ps, region: .jp)?.variant == .anchor) // reserva
        #expect(Collectible.make(from: ps[3], in: ps, region: .jp)?.variant == .outdoor) // see
        #expect(Collectible.make(from: ps[2], in: ps, region: .jp)?.isRare == true)
    }

    @Test func stampAndLine() throws {
        let (_, ps) = try world()
        ps[0].done = DoneMark(at: at(1))
        let c = try #require(Collectible.make(from: ps[0], in: ps, region: .jp))
        #expect(c.stampCode == "SJK")
        #expect(c.cityName == "Tóquio")
        #expect(c.subLine == "tsukemen · Must eat")
    }

    @Test func latinOnlyDropsJapanese() {
        #expect(CollectibleText.latinOnly("Fuunji 風雲児") == "Fuunji")
        #expect(CollectibleText.latinOnly("ラーメン Nakajima") == "Nakajima")
    }

    @Test func fileName() throws {
        let (_, ps) = try world()
        ps[0].done = DoneMark(at: at(1))
        let c = try #require(Collectible.make(from: ps[0], in: ps, region: .jp))
        #expect(CollectibleRenderer.fileName(c, format: .stories) == "must-001-fuunji.png")
        #expect(CollectibleRenderer.fileName(c, format: .feed) == "must-001-fuunji-feed.png")
    }

    @Test func prefsPinMaxThreeAndHide() {
        let d = UserDefaults(suiteName: "collection-test-\(UUID().uuidString)")!
        let prefs = CollectionPrefs(regionId: "jp", defaults: d)
        for id in ["a", "b", "c", "d"] { prefs.togglePin(id) }
        #expect(prefs.pinned == ["b", "c", "d"])
        prefs.togglePin("c")
        #expect(prefs.pinned == ["b", "d"])
        prefs.toggleHidden("b")
        #expect(prefs.hidden == ["b"])
        #expect(prefs.pinned == ["d"])
        #expect(prefs.group == .city)
        prefs.group = .date
        #expect(prefs.group == .date)
    }
}

@MainActor
struct CollectibleRendererTests {
    func item(_ variant: CollectibleVariant = .trip) -> Collectible {
        Collectible(placeId: "a", order: 14, total: 105, variant: variant, title: "Fuunji 風雲児", area: "Shinjuku sul 新宿",
                    listId: "eat", doneAt: Date(timeIntervalSince1970: 1_700_000_000), stampCode: "SJK", cityId: "tokyo1",
                    cityName: "Tóquio", listName: "Must eat", subLine: "tsukemen · Must eat", doneCount: 38,
                    timeZoneId: "Asia/Tokyo", spent: 1250)
    }

    @Test func storiesAndFeedSizes() throws {
        for variant in CollectibleVariant.allCases {
            let stories = try #require(CollectibleRenderer.image(item(variant), format: .stories, tint: .red))
            #expect(Int(stories.size.width * stories.scale) == 1080)
            #expect(Int(stories.size.height * stories.scale) == 1920)
            let feed = try #require(CollectibleRenderer.image(item(variant), format: .feed, tint: .red))
            #expect(Int(feed.size.width * feed.scale) == 1080)
            #expect(Int(feed.size.height * feed.scale) == 1080)
        }
    }

    @Test func writesPNG() throws {
        let url = try #require(CollectibleRenderer.write(item(), format: .feed, tint: .red))
        defer { CollectibleRenderer.cleanup(url) }
        #expect(url.lastPathComponent == "must-014-fuunji-feed.png")
        let data = try Data(contentsOf: url)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
}

@MainActor
struct CollectionGroupingTests {
    func slot(_ id: String, city: String, cityName: String, list: String, done: Int?) -> CollectionSlot {
        let c = done.map {
            Collectible(placeId: id, order: $0, total: 10, variant: .trip, title: id, area: nil, listId: list,
                        doneAt: Date(timeIntervalSince1970: 1_700_000_000 + Double($0) * 40_000), cityId: city, cityName: cityName)
        }
        return CollectionSlot(placeId: id, name: id, cityId: city, cityName: cityName, listId: list, listName: "Must \(list)", collectible: c)
    }

    var slots: [CollectionSlot] {
        [slot("a", city: "tokyo1", cityName: "Tóquio", list: "eat", done: 1),
         slot("b", city: "tokyo2", cityName: "Tóquio", list: "eat", done: 3),
         slot("c", city: "tokyo1", cityName: "Tóquio", list: "see", done: nil),
         slot("d", city: "tokyo1", cityName: "Tóquio", list: "see", done: nil),
         slot("e", city: "tokyo1", cityName: "Tóquio", list: "see", done: nil),
         slot("f", city: "kyoto", cityName: "Kyoto", list: "see", done: 2)]
    }

    @Test func byCityMergesTokyo() {
        let s = CollectionGrouping.sections(slots, by: .city)
        #expect(s.map(\.title) == ["Tóquio", "Kyoto"])
        #expect(s[0].done.map(\.order) == [3, 1])
        #expect(s[0].total == 5)
        #expect(s[0].todo.count == CollectionGrouping.todoPerSection)
        #expect(s[1].total == 1)
    }

    @Test func byList() {
        let s = CollectionGrouping.sections(slots, by: .list)
        #expect(Set(s.map(\.id)) == ["eat", "see"])
        #expect(s.first { $0.id == "eat" }?.done.count == 2)
        #expect(s.first { $0.id == "see" }?.total == 4)
    }

    @Test func byDateNoTodoNoTotal() {
        let s = CollectionGrouping.sections(slots, by: .date, timeZone: TimeZone(identifier: "UTC")!)
        #expect(s.allSatisfy { $0.total == nil && $0.todo.isEmpty })
        #expect(s.flatMap(\.done).count == 3)
    }

    @Test func hiddenAndShowcase() {
        let s = CollectionGrouping.sections(slots, by: .city, hidden: ["a"])
        #expect(s[0].done.map(\.placeId) == ["b"])
        let show = CollectionGrouping.showcase(slots, pinned: ["f", "a", "c", "b"], hidden: ["a"])
        #expect(show.map(\.placeId) == ["f", "b"]) // "c" não é feito, "a" escondido
    }
}
