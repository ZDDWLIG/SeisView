// Minimal static stub for Task 3 tests. Task 4 will build out the full SegyFile.
public enum SegyFile {
    // 400-byte binary header, big-endian per SEG-Y rev 1. Raw offset = 1-indexed byte − 1.
    public static func parseBinaryHeader(_ bytes: [UInt8]) -> BinaryHeader {
        bytes.withUnsafeBytes { raw in
            let p = raw.baseAddress!
            return BinaryHeader(
                ns: Int(ByteOrderReader.u16(p + 20, .big)),
                dtMicros: Int(ByteOrderReader.u16(p + 16, .big)),
                formatCode: Int(ByteOrderReader.u16(p + 24, .big)),
                segyRevision: Int(ByteOrderReader.u16(p + 100, .big)),
                fixedLengthFlag: Int(ByteOrderReader.u16(p + 102, .big)),
                extTextHeaders: Int(ByteOrderReader.u16(p + 104, .big))
            )
        }
    }
}
