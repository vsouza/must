import Foundation

/// Um lugar salvo vindo do Google Maps (export KML do My Maps ou GeoJSON do Takeout).
struct SavedPlace: Hashable, Sendable, Identifiable {
    var name: String
    var lat: Double
    var lng: Double
    var note: String?
    var url: String?

    var id: String { "\(name)|\(lat)|\(lng)" }
}

/// Lê "Salvos no Maps": KML (`<Placemark><name>…<coordinates>lng,lat`) ou GeoJSON (Takeout).
enum SavedPlacesImporter {
    static func parse(_ data: Data) -> [SavedPlace] {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return parseGeoJSON(json)
        }
        return KMLParser(data: data).run()
    }

    private static func parseGeoJSON(_ json: [String: Any]) -> [SavedPlace] {
        let features = json["features"] as? [[String: Any]] ?? []
        return features.compactMap { feature in
            guard let geometry = feature["geometry"] as? [String: Any],
                  let coords = geometry["coordinates"] as? [Double], coords.count >= 2 else { return nil }
            let props = feature["properties"] as? [String: Any] ?? [:]
            let location = props["location"] as? [String: Any]
            let name = (location?["name"] as? String) ?? (props["Title"] as? String) ?? (props["name"] as? String)
            guard let name, !name.isEmpty, !(coords[0] == 0 && coords[1] == 0) else { return nil }
            return SavedPlace(name: name, lat: coords[1], lng: coords[0],
                              note: (location?["address"] as? String) ?? (props["Comment"] as? String),
                              url: props["google_maps_url"] as? String)
        }
    }

    private final class KMLParser: NSObject, XMLParserDelegate {
        private let parser: XMLParser
        private var results: [SavedPlace] = []
        private var inPlacemark = false
        private var element = ""
        private var name = ""
        private var descriptionText = ""
        private var coordinates = ""

        init(data: Data) {
            parser = XMLParser(data: data)
            super.init()
            parser.delegate = self
        }

        func run() -> [SavedPlace] {
            parser.parse()
            return results
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            element = elementName
            if elementName == "Placemark" {
                inPlacemark = true
                name = ""; descriptionText = ""; coordinates = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard inPlacemark else { return }
            switch element {
            case "name": name += string
            case "description": descriptionText += string
            case "coordinates": coordinates += string
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "Placemark" {
                inPlacemark = false
                let parts = coordinates.trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(whereSeparator: { $0 == " " || $0 == "\n" }).first?
                    .split(separator: ",").compactMap { Double($0) } ?? []
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if parts.count >= 2, !trimmed.isEmpty {
                    let note = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
                    results.append(SavedPlace(name: trimmed, lat: parts[1], lng: parts[0], note: note.isEmpty ? nil : note, url: nil))
                }
            }
            element = ""
        }
    }
}
