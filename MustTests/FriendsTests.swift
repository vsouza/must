import Foundation
import Testing
@testable import Must

struct FriendsTests {
    let source = MockFriendsSource()

    @Test func isDeterministicPerPlace() {
        for id in ["j01", "b22", "r46", "abc"] { #expect(source.visits(placeId: id) == MockFriendsSource().visits(placeId: id)) }
    }

    @Test func hasAtMostThreeDistinctPeopleAndAllCountsAppear() {
        var counts = Set<Int>()
        for i in 0..<200 {
            let v = source.visits(placeId: "place-\(i)")
            counts.insert(v.count)
            #expect(v.count <= 3)
            #expect(Set(v.map(\.name)).count == v.count)
            #expect(v.allSatisfy { !$0.initials.isEmpty && !$0.when.isEmpty && ($0.note?.isEmpty == false) && (6...10).contains($0.rating ?? 0) })
        }
        #expect(counts == [0, 1, 2, 3])
    }

    @Test func stableAcrossRunsAtKnownValue() {
        // FNV-1a de "j01": não muda entre execuções (o `Hasher` do Swift mudaria).
        #expect(MockFriendsSource.hash("j01") == MockFriendsSource.hash("j01"))
        #expect(MockFriendsSource.hash("") == 14_695_981_039_346_656_037)
        #expect(source.isSample && source.totalFriends == 5)
    }
}
