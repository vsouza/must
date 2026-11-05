import Foundation
import SwiftData

/// Capa da lista (05/11, pedido do Vinicius: fotos "sem vida"). A foto escolhida à mão vale sempre; senão, a foto do
/// Google de um lugar da lista **que já está no disco** (Lugar aberto, dia baixado, lote de fotos) ganha da foto do
/// Commons que a sincronização achou por palavra-chave. Nunca baixa nada: sem foto do Google no disco, fica a de antes.
@MainActor
enum ListCover {
    /// Listas cuja foto foi escolhida à mão (Nova lista, Editar lista). Por board (o arquivo do container), sem mexer
    /// no esquema do SwiftData.
    static let manualKey = "listPhoto.manual"

    /// Foto escolhida à mão: marcada aqui, ou lista criada por você (não veio do seed) que tem foto.
    static func isManual(_ list: MustList, defaults: UserDefaults = .standard) -> Bool {
        guard let context = list.modelContext else { return list.photo != nil }
        if Set(defaults.stringArray(forKey: manualKey) ?? []).contains(scoped(list.id, context)) { return true }
        let seedLists = Set((try? context.fetch(FetchDescriptor<Settings>()))?.first?.seedListOrder ?? [])
        return list.photo != nil && !seedLists.contains(list.id)
    }

    /// Chamado ao salvar uma foto escolhida (ou tirar a foto: `chosen` falso volta pro automático).
    static func mark(_ list: MustList, chosen: Bool, context: ModelContext, defaults: UserDefaults = .standard) {
        var set = Set(defaults.stringArray(forKey: manualKey) ?? [])
        let key = scoped(list.id, context)
        if chosen { set.insert(key) } else { set.remove(key) }
        defaults.set(set.sorted(), forKey: manualKey)
    }

    /// Foto do Google de um lugar da lista já no disco, na ordem do board (até 16 lugares). `nil` se não há.
    static func google(for list: MustList) -> CCPhoto? {
        let places = list.places.sorted { $0.order < $1.order }.prefix(16)
        for place in places {
            guard let ref = place.photoRefs.first, let file = PlacePhotoStore.existing(ref) else { continue }
            return PlacePhotoResolver.photo(ref, file: file, placeId: place.placeId ?? "")
        }
        return nil
    }

    /// A capa: à mão › Google no disco (estilo vivo) › a do Commons. `nil` = gradiente da cor.
    static func photo(for list: MustList) -> CCPhoto? {
        if PhotoStyle.current == .vivid, !isManual(list), let google = google(for: list) { return google }
        return list.photo.map(ccPhoto)
    }

    static func ccPhoto(_ photo: ListPhoto) -> CCPhoto {
        CCPhoto(id: photo.flickrId ?? "", url: photo.url ?? "", largeURL: photo.url, owner: "", licenseName: photo.license ?? "",
                page: photo.page ?? "")
    }

    private static func scoped(_ listId: String, _ context: ModelContext) -> String {
        let store = context.container.configurations.first?.url.lastPathComponent ?? "board"
        return "\(store)|\(listId)"
    }
}
