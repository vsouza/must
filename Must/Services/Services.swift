import Observation

/// Serviços compartilhados do app (o único "singleton" além do `RegionStore`).
/// Injetado no root com `.environment(services)`. Prompt 07 adiciona Places, Weather, Flickr, Routes.
@MainActor
@Observable
final class Services {
    let location = LocationService()
}
