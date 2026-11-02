import CoreLocation
import Foundation
import Testing
@testable import Must

/// Prompt 17 · A (fatia 8A): parsers do Places Autocomplete, das fotos do Places e do Street View (sem rede).
struct GoogleParsersTests {
    /// Exemplo real (prompt 17): "koffee mam" → "… 4 Chome−15−3 KOFFEE MAMEYA", casado nas posições 46…56.
    static let autocompleteJSON = """
    {"suggestions": [
      {"placePrediction": {
        "placeId": "ChIJ-koffee-mameya",
        "text": {"text": "Japan, Tokyo, Shibuya, Jingumae, 4 Chome\u{2212}15-3 KOFFEE MAMEYA",
                 "matches": [{"startOffset": 46, "endOffset": 56}]},
        "structuredFormat": {
          "mainText": {"text": "KOFFEE MAMEYA", "matches": [{"startOffset": 0, "endOffset": 10}]},
          "secondaryText": {"text": "Japan, Tokyo, Shibuya, Jingumae"}
        },
        "distanceMeters": 1240,
        "types": ["cafe", "establishment"]
      }},
      {"placePrediction": {
        "placeId": "ChIJ-kakeru",
        "text": {"text": "Japan, Tokyo, Koto City, Hirano, KOFFEE MAMEYA Kakeru",
                 "matches": [{"startOffset": 33, "endOffset": 43}]},
        "structuredFormat": {
          "mainText": {"text": "KOFFEE MAMEYA Kakeru", "matches": [{"startOffset": 0, "endOffset": 10}]},
          "secondaryText": {"text": "Japan, Tokyo, Koto City, Hirano"}
        },
        "types": ["cafe"]
      }},
      {"queryPrediction": {"text": {"text": "koffee mameya tokyo"}}},
      {"placePrediction": {
        "placeId": "ChIJ-victoria",
        "text": {"text": "KOFFEE MAMEYA, Victoria Dockside"},
        "types": ["cafe"]
      }}
    ]}
    """

    @Test func autocompleteParsesIdsNamesAndSkipsQueryPredictions() throws {
        let suggestions = try PlaceAutocomplete.parse(Data(Self.autocompleteJSON.utf8))
        #expect(suggestions.count == 3)
        #expect(suggestions[0].placeId == "ChIJ-koffee-mameya")
        #expect(suggestions[0].name == "KOFFEE MAMEYA")
        #expect(suggestions[0].secondary == "Japan, Tokyo, Shibuya, Jingumae")
        #expect(suggestions[0].primaryType == "cafe")
        #expect(suggestions[0].distanceMeters == 1240)
        #expect(suggestions[1].distanceMeters == nil)
        // Sem structuredFormat, o nome é o texto inteiro.
        #expect(suggestions[2].name == "KOFFEE MAMEYA, Victoria Dockside")
    }

    @Test func autocompleteHighlightsTheTypedPart() throws {
        let suggestions = try PlaceAutocomplete.parse(Data(Self.autocompleteJSON.utf8))
        // Os matches do texto completo (46…56) caem no nome "KOFFEE MAMEYA": o trecho "KOFFEE MAM" fica verde.
        #expect(suggestions[0].segments == [
            .init(text: "KOFFEE MAM", highlighted: true),
            .init(text: "EYA", highlighted: false),
        ])
        #expect(suggestions[1].segments.first == .init(text: "KOFFEE MAM", highlighted: true))
    }

    @Test func autocompleteFallsBackToMainTextMatches() {
        let segments = PlaceAutocomplete.segmentize(main: "Blue Bottle", full: "Other text", fullMatches: [],
                                                    mainMatches: [0..<4])
        #expect(segments == [.init(text: "Blue", highlighted: true), .init(text: " Bottle", highlighted: false)])
    }

    @Test func autocompleteEmptyAnswerIsEmptyList() throws {
        #expect(try PlaceAutocomplete.parse(Data("{}".utf8)).isEmpty)
    }

    @Test func placePhotoRefsKeepNameAndAuthor() {
        let json = """
        {"id": "ChIJ-x", "photos": [
          {"name": "places/ChIJ-x/photos/AAA", "authorAttributions": [{"displayName": "Maria Viaja", "uri": "https://maps.google.com/x"}]},
          {"name": "places/ChIJ-x/photos/BBB"}
        ]}
        """
        let refs = GooglePlacePhotos.parseRefs(Data(json.utf8))
        #expect(refs == [
            .init(name: "places/ChIJ-x/photos/AAA", author: "Maria Viaja"),
            .init(name: "places/ChIJ-x/photos/BBB", author: nil),
        ])
    }

    @Test func googlePhotoCreditSaysGoogleAndAuthor() {
        let photo = CCPhoto(id: "p", url: "file:///x.jpg", largeURL: nil, owner: "Maria Viaja", licenseName: "Google",
                            page: "https://maps.google.com", source: "Google")
        #expect(photo.credit == "foto · Google · @Maria Viaja")
        let commons = CCPhoto(id: "c", url: "https://u", largeURL: nil, owner: "Ana", licenseName: "CC BY 2.0", page: "https://p")
        #expect(commons.credit == "foto · Wikimedia CC BY 2.0 · @Ana")
    }

    // MARK: Street View

    /// Guarda os endereços pedidos (o teste confere que a imagem não é pedida sem `status == OK`).
    actor Requests {
        private(set) var urls: [String] = []
        func add(_ url: URL) { urls.append(url.absoluteString) }
    }

    @Test func streetViewAsksForImageOnlyWhenMetadataIsOK() async throws {
        let requests = Requests()
        let service = StreetViewService(apiKey: "test-key", fetch: { url, _ in
            await requests.add(url)
            return Data(#"{"status": "ZERO_RESULTS"}"#.utf8)
        })
        let card = try await service.card(for: CLLocationCoordinate2D(latitude: 35.6654, longitude: 139.7707), caption: nil)
        #expect(card == nil)
        let urls = await requests.urls
        #expect(urls.count == 1)
        #expect(urls.allSatisfy { $0.contains("/streetview/metadata") })
        #expect(urls.allSatisfy { !$0.contains("/maps/api/streetview?") })
    }

    @Test func streetViewMetadataParsesOKAndDate() throws {
        let meta = try StreetViewMeta.parse(Data("""
        {"status": "OK", "pano_id": "abc", "location": {"lat": 35.66, "lng": 139.77}, "date": "2025-03", "copyright": "© Google"}
        """.utf8))
        #expect(meta.status == "OK")
        #expect(meta.panoId == "abc")
        #expect(meta.lat == 35.66)
        #expect(StreetViewService.monthName("2025-03") == "mar 2025")
    }

    @Test func streetViewHeadingPointsFromPhotoToPlace() {
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let east = CLLocationCoordinate2D(latitude: 0, longitude: 0.001)
        let north = CLLocationCoordinate2D(latitude: 0.001, longitude: 0)
        #expect(abs(StreetViewService.bearing(from: origin, to: east) - 90) < 0.5)
        #expect(abs(StreetViewService.bearing(from: origin, to: north) - 0) < 0.5)
    }
}
