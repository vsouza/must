import Compression
import Foundation

/// Leitura mínima de ZIP (prompt 15 · A, `.pkpass`): sem dependência externa.
/// Lê o diretório central (EOCD → entradas), aceita entradas *stored* (0) e *deflate* (8) e recusa o resto.
/// Deflate usa o `Compression` do sistema (`COMPRESSION_ZLIB` é deflate cru, sem cabeçalho zlib).
/// Sem ZIP64, sem criptografia, sem verificar CRC (o `.pkpass` não é conferido, só lido).
enum ZipReader {
    struct Entry: Equatable, Sendable {
        let name: String
        let method: Int
        let compressedSize: Int
        let size: Int
        let localHeaderOffset: Int
    }

    enum Failure: Error, Equatable {
        case notAZip
        case corrupt
        case unsupportedMethod(Int)
        /// Limite de segurança: entrada grande demais (zip bomb) ou arquivo grande demais.
        case tooLarge
    }

    /// Teto por entrada (um `pass.json` tem poucos KB; imagens de passe ficam bem abaixo disso).
    static let maxEntrySize = 4 * 1024 * 1024
    static let maxEntries = 256

    static func entries(in data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        guard let eocd = endOfCentralDirectory(in: bytes) else { throw Failure.notAZip }
        let count = try uint16(bytes, eocd + 10)
        let directoryOffset = try uint32(bytes, eocd + 16)
        guard count <= maxEntries else { throw Failure.tooLarge }

        var entries: [Entry] = []
        var position = directoryOffset
        for _ in 0..<count {
            guard try uint32(bytes, position) == 0x0201_4b50 else { throw Failure.corrupt }
            let method = try uint16(bytes, position + 10)
            let compressed = try uint32(bytes, position + 20)
            let size = try uint32(bytes, position + 24)
            let nameLength = try uint16(bytes, position + 28)
            let extraLength = try uint16(bytes, position + 30)
            let commentLength = try uint16(bytes, position + 32)
            let offset = try uint32(bytes, position + 42)
            let nameStart = position + 46
            guard nameStart + nameLength <= bytes.count else { throw Failure.corrupt }
            let name = String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            entries.append(Entry(name: name, method: method, compressedSize: compressed, size: size, localHeaderOffset: offset))
            position = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// Bytes de uma entrada. Confere o tamanho descomprimido com o do diretório.
    static func read(_ entry: Entry, in data: Data) throws -> Data {
        guard entry.size <= maxEntrySize else { throw Failure.tooLarge }
        let bytes = [UInt8](data)
        let header = entry.localHeaderOffset
        guard try uint32(bytes, header) == 0x0403_4b50 else { throw Failure.corrupt }
        let nameLength = try uint16(bytes, header + 26)
        let extraLength = try uint16(bytes, header + 28)
        let start = header + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= bytes.count else { throw Failure.corrupt }
        let packed = Array(bytes[start..<(start + entry.compressedSize)])

        switch entry.method {
        case 0:
            guard packed.count == entry.size else { throw Failure.corrupt }
            return Data(packed)
        case 8:
            return try inflate(packed, size: entry.size)
        default:
            throw Failure.unsupportedMethod(entry.method)
        }
    }

    /// Primeira entrada com esse nome (ex.: "pass.json"), ou nil.
    static func file(named name: String, in data: Data) throws -> Data? {
        guard let entry = try entries(in: data).first(where: { $0.name == name }) else { return nil }
        return try read(entry, in: data)
    }

    // MARK: Interno

    /// O EOCD fica no fim do arquivo (depois de um comentário de até 64 KB).
    private static func endOfCentralDirectory(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        var index = bytes.count - 22
        while index >= lowest {
            if bytes[index] == 0x50, bytes[index + 1] == 0x4b, bytes[index + 2] == 0x05, bytes[index + 3] == 0x06 {
                return index
            }
            index -= 1
        }
        return nil
    }

    private static func inflate(_ packed: [UInt8], size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var output = [UInt8](repeating: 0, count: size)
        let written = packed.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compression_decode_buffer(destination.baseAddress!, destination.count, source.baseAddress!, source.count, nil,
                                          COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw Failure.corrupt }
        return Data(output)
    }

    private static func uint16(_ bytes: [UInt8], _ index: Int) throws -> Int {
        guard index >= 0, index + 2 <= bytes.count else { throw Failure.corrupt }
        return Int(bytes[index]) | Int(bytes[index + 1]) << 8
    }

    private static func uint32(_ bytes: [UInt8], _ index: Int) throws -> Int {
        guard index >= 0, index + 4 <= bytes.count else { throw Failure.corrupt }
        return Int(bytes[index]) | Int(bytes[index + 1]) << 8 | Int(bytes[index + 2]) << 16 | Int(bytes[index + 3]) << 24
    }
}
