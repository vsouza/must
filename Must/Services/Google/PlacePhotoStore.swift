import CryptoKit
import Foundation
import ImageIO

/// Disco das fotos do Google Places (prompt 19 · item 3 e premissa de dados).
/// `Caches/must-place-photos`: a foto de 800 px (`<chave>.jpg`) e a miniatura de 240 px gerada no aparelho
/// (`<chave>-240.jpg`), sem segunda chamada. Validade: 30 dias sem uso. Teto: 300 MB, despejo LRU (menos usado primeiro).
/// As fotos do Commons que o `PhotoLoader` guarda em `must-cache` (prefixo `photo`) entram no mesmo teto.
enum PlacePhotoStore {
    static let directory = URL.cachesDirectory.appending(path: "must-place-photos", directoryHint: .isDirectory)
    static let maxAge: TimeInterval = 30 * 86_400
    static let capBytes: Int64 = 300 * 1_000_000
    static let thumbPixels = 240

    // MARK: Nomes

    /// Chave estável (SHA-256 do `name`): o nome do Google é longo e tem barras.
    static func key(_ ref: PlacePhotoRef) -> String {
        SHA256.hash(data: Data(ref.name.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func fullURL(_ ref: PlacePhotoRef) -> URL {
        directory.appending(path: "\(key(ref)).jpg")
    }

    static func thumbURL(_ ref: PlacePhotoRef) -> URL {
        directory.appending(path: "\(key(ref))-240.jpg")
    }

    // MARK: Leitura

    /// A foto de 800 px se estiver no disco (qualquer idade: o pedido já pagou). Marca o uso (LRU).
    static func existing(_ ref: PlacePhotoRef) -> URL? {
        let url = fullURL(ref)
        guard FileManager.default.fileExists(atPath: url.path()) else { return nil }
        touch(url)
        return url
    }

    /// A miniatura se já existe no disco.
    static func existingThumb(_ ref: PlacePhotoRef) -> URL? {
        let url = thumbURL(ref)
        guard FileManager.default.fileExists(atPath: url.path()) else { return nil }
        touch(url)
        return url
    }

    /// Miniatura 240 px: se não existe, gera a partir da foto de 800 px (nunca baixa). `nil` se não há foto no disco.
    /// Roda fora do main (decodificação de imagem).
    static func ensureThumb(_ ref: PlacePhotoRef) async -> URL? {
        if let thumb = existingThumb(ref) { return thumb }
        guard let full = existing(ref) else { return nil }
        let target = thumbURL(ref)
        return await Task.detached(priority: .utility) { () -> URL? in
            guard let data = try? Data(contentsOf: full), let small = makeThumbnail(data, maxPixel: thumbPixels) else { return nil }
            do {
                try small.write(to: target, options: .atomic)
                return target
            } catch {
                return nil
            }
        }.value
    }

    // MARK: Escrita

    /// Grava a foto de 800 px que veio do `photoUri`. Devolve o arquivo.
    @discardableResult
    static func save(_ data: Data, for ref: PlacePhotoRef) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fullURL(ref)
        try data.write(to: url, options: .atomic)
        trim()
        return url
    }

    /// A imagem chegou inteira (rodada 23 · G). O `ImageIO` aceita JPEG cortado no meio (desenha meio cinza), então JPEG
    /// precisa terminar no marcador EOI (FF D9) e PNG no IEND; o resto, o status do `ImageIO`.
    static func isCompleteImage(_ data: Data) -> Bool {
        guard data.count > 8, let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { return false }
        let bytes = [UInt8](data.prefix(8))
        if bytes[0] == 0xFF, bytes[1] == 0xD8 {
            // Alguns servidores põem bytes nulos depois do EOI: ignora o rabo de zeros.
            let tail = data.suffix(64).reversed().drop { $0 == 0 }
            return Array(tail.prefix(2)) == [0xD9, 0xFF]
        }
        if bytes == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
            return data.suffix(12).range(of: Data("IEND".utf8)) != nil
        }
        return CGImageSourceGetStatus(source) == .statusComplete
    }

    /// JPEG de `maxPixel` no lado maior, qualidade 0,7 (premissa: 240 px, JPEG).
    static func makeThumbnail(_ data: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }

    // MARK: Tamanho e limpeza

    /// Arquivo de foto (Google ou Commons) com tamanho, último uso e de quem é.
    struct Entry: Equatable {
        var url: URL
        var size: Int64
        var used: Date
        var google: Bool
    }

    static func entries(in folder: URL = directory, commons: URL = DiskCache.folder, fileManager fm: FileManager = .default) -> [Entry] {
        var out: [Entry] = []
        for url in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? [] {
            if let entry = entry(url, google: true) { out.append(entry) }
        }
        let others = (try? fm.contentsOfDirectory(at: commons, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        for url in others where url.lastPathComponent.hasPrefix("photo") {
            if let entry = entry(url, google: false) { out.append(entry) }
        }
        return out
    }

    private static func entry(_ url: URL, google: Bool) -> Entry? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, let used = values.contentModificationDate else { return nil }
        return Entry(url: url, size: Int64(size), used: used, google: google)
    }

    /// Bytes ocupados pelas fotos (o que Ajustes › Dados mostra).
    static func sizeBytes() -> Int64 { entries().reduce(0) { $0 + $1.size } }

    /// Aplica a validade (30 dias sem uso, só do Google) e o teto de 300 MB (LRU). Devolve quantos arquivos saíram.
    @discardableResult
    static func trim(now: Date = AppClock.now, cap: Int64 = capBytes, in folder: URL = directory,
                     commons: URL = DiskCache.folder, fm: FileManager = .default) -> Int {
        var all = entries(in: folder, commons: commons, fileManager: fm)
        var removed = 0
        let stale = all.filter { $0.google && now.timeIntervalSince($0.used) > maxAge }
        for entry in stale {
            try? fm.removeItem(at: entry.url)
            removed += 1
        }
        all.removeAll { entry in stale.contains(entry) }
        var total = all.reduce(0) { $0 + $1.size }
        for entry in all.sorted(by: { $0.used < $1.used }) where total > cap {
            try? fm.removeItem(at: entry.url)
            total -= entry.size
            removed += 1
        }
        if removed > 0 { Log.data.info("fotos: \(removed) arquivo(s) saíram do cache") }
        return removed
    }

    /// Apaga as fotos (Google e Commons). O board e as listas não mudam; a foto volta quando for pedida.
    static func clear(fm: FileManager = .default) {
        for entry in entries(fileManager: fm) { try? fm.removeItem(at: entry.url) }
    }

    /// Miniatura de teste/uso: a imagem de `maxPixel` no lado maior, a partir do JPEG de 800 px.
    static func thumbnailSize(_ data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }

    private static func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path())
    }
}
