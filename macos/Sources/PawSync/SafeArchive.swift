import Foundation
import zlib

/// Bounded ZIP reader. Only stored/deflated, unencrypted, single-disk archives.
/// Entries are returned in memory; callers validate the complete package before
/// writing a staging directory. ZIP64 and ambiguous layouts fail closed.
enum SafeArchive {
    struct Limits {
        var archive = 50 * 1024 * 1024
        var extracted = 200 * 1024 * 1024
        var file = 100 * 1024 * 1024
        var entries = 500
    }
    static func unpack(_ data: Data, limits: Limits = Limits()) throws -> [String: Data] {
        func invalid(_ detail: String) -> PawError { .message("Unsafe ZIP: \(detail)") }
        guard data.count >= 22, data.count <= limits.archive else { throw invalid("archive size") }
        func u16(_ offset: Int) throws -> Int {
            guard offset >= 0, offset + 2 <= data.count else { throw invalid("truncated header") }
            return Int(data[offset]) | Int(data[offset+1]) << 8
        }
        func u32(_ offset: Int) throws -> Int {
            guard offset >= 0, offset + 4 <= data.count else { throw invalid("truncated header") }
            return Int(data[offset]) | Int(data[offset+1]) << 8 | Int(data[offset+2]) << 16 | Int(data[offset+3]) << 24
        }
        var end: Int?
        for offset in stride(from: data.count-22, through: max(0,data.count-65557), by: -1) {
            if try u32(offset) == 0x06054b50, offset+22+(try u16(offset+20)) == data.count { end = offset; break }
        }
        guard let end, try u16(end+4) == 0, try u16(end+6) == 0 else { throw invalid("multi-disk or missing directory") }
        let count = try u16(end+10), start = try u32(end+16), length = try u32(end+12)
        guard count == (try u16(end+8)), count > 0, count <= limits.entries, count < 65535,
              start >= 0, length > 0, start+length == end else { throw invalid("directory bounds or ZIP64") }
        var cursor = start, bytes = 0, result: [String: Data] = [:], names = Set<String>(), regions: [Range<Int>] = []
        for _ in 0..<count {
            guard try u32(cursor) == 0x02014b50 else { throw invalid("directory signature") }
            let flags=try u16(cursor+8), method=try u16(cursor+10), checksum=try u32(cursor+16)
            let packed=try u32(cursor+20), size=try u32(cursor+24), nameLength=try u16(cursor+28)
            let extra=try u16(cursor+30), comment=try u16(cursor+32), disk=try u16(cursor+34)
            let attributes=try u32(cursor+38), local=try u32(cursor+42)
            let next=cursor+46+nameLength+extra+comment
            guard next <= end, nameLength > 0, nameLength <= 512, disk == 0,
                  flags & 1 == 0, flags & 0x40 == 0, [0,8].contains(method),
                  packed < 0xffffffff, size < 0xffffffff, local < 0xffffffff,
                  size <= limits.file, bytes+size <= limits.extracted else { throw invalid("entry limits/encryption") }
            let mode=(attributes >> 16) & 0xf000
            guard mode == 0 || mode == 0x8000 || mode == 0x4000 else { throw invalid("link or special file") }
            guard let path=String(data:data.subdata(in:cursor+46..<cursor+46+nameLength),encoding:.utf8),
                  !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"), !path.contains("\0") else { throw invalid("entry path") }
            let components=path.split(separator:"/",omittingEmptySubsequences:false)
            let directory=path.hasSuffix("/")
            let clean=directory ? Array(components.dropLast()) : components
            guard !clean.isEmpty, clean.count <= 8, clean.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  names.insert(path.lowercased()).inserted else { throw invalid("traversal or case collision") }
            guard local+30 <= start, try u32(local) == 0x04034b50,
                  try u16(local+6) == flags, try u16(local+8) == method else { throw invalid("local header mismatch") }
            let localName=try u16(local+26), localExtra=try u16(local+28)
            let payload=local+30+localName+localExtra
            guard localName == nameLength, payload+packed <= start,
                  data.subdata(in:local+30..<local+30+localName) == data.subdata(in:cursor+46..<cursor+46+nameLength) else { throw invalid("entry bounds/name mismatch") }
            let region=local..<payload+packed
            guard regions.allSatisfy({ !$0.overlaps(region) }) else { throw invalid("overlapping entries") }
            regions.append(region)
            if directory { guard size == 0, packed == 0 else { throw invalid("directory payload") } }
            else {
                let compressed=data.subdata(in:payload..<payload+packed)
                let output: Data
                if method == 0 { guard packed == size else { throw invalid("stored size mismatch") }; output=compressed }
                else { output=try inflateRaw(compressed, size:size) }
                let actual=output.withUnsafeBytes { pointer -> UInt32 in
                    UInt32(crc32(0, pointer.bindMemory(to:Bytef.self).baseAddress, uInt(output.count)))
                }
                guard actual == UInt32(checksum) else { throw invalid("CRC mismatch") }
                result[path]=output; bytes+=size
            }
            cursor=next
        }
        guard cursor == end else { throw invalid("unexpected directory data") }
        return result
    }
    private static func inflateRaw(_ data: Data, size: Int) throws -> Data {
        var stream=z_stream()
        guard inflateInit2_(&stream,-MAX_WBITS,ZLIB_VERSION,Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw PawError.message("Could not initialize ZIP decoder.") }
        defer { inflateEnd(&stream) }
        var result=Data(count:max(1,size))
        let status=data.withUnsafeBytes { input in result.withUnsafeMutableBytes { output -> Int32 in
            stream.next_in=UnsafeMutablePointer(mutating:input.bindMemory(to:Bytef.self).baseAddress)
            stream.avail_in=uInt(data.count); stream.next_out=output.bindMemory(to:Bytef.self).baseAddress; stream.avail_out=uInt(max(1,size))
            return inflate(&stream,Z_FINISH)
        }}
        guard status == Z_STREAM_END, stream.total_out == size, stream.total_in == data.count else { throw PawError.message("Unsafe ZIP: invalid deflate stream or size.") }
        result.count=size; return result
    }
}
