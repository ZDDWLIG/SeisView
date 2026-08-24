// Minimal static stub for Task 3 tests. Task 4 will build out the full SegyFile.
public enum SegyFile {
    // 400-byte binary header, big-endian per SEG-Y rev 1.
    // Raw offset = 1-indexed file byte − 3201 (binary header starts at file byte 3201).
    // e.g. rev bytes 3501-3502 → raw[300..301].
    public static func parseBinaryHeader(_ bytes: [UInt8]) -> BinaryHeader {
        bytes.withUnsafeBytes { raw in
            let p = raw.baseAddress!
            return BinaryHeader(
                ns: Int(ByteOrderReader.u16(p + 20, .big)),
                dtMicros: Int(ByteOrderReader.u16(p + 16, .big)),
                formatCode: Int(ByteOrderReader.u16(p + 24, .big)),
                segyRevision: Int(raw[300]) << 8 | Int(raw[301]),
                fixedLengthFlag: Int(raw[302]) << 8 | Int(raw[303]),
                extTextHeaders: Int(raw[304]) << 8 | Int(raw[305])
            )
        }
    }
}
