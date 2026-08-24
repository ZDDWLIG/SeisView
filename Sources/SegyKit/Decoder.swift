public enum Decoder {
    public static func decode(bytes: UnsafeRawPointer, count: Int,
                              format: SampleFormat, order: ByteOrder,
                              into out: UnsafeMutablePointer<Float>) {
        switch format {
        case .ibm32:
            let tab = IBM.expTable()
            for i in 0..<count {
                let raw = ByteOrderReader.u32(bytes + i * 4, order)
                out[i] = IBM.toFloat(raw, tab)
            }
        case .ieee32:
            for i in 0..<count {
                let raw = ByteOrderReader.u32(bytes + i * 4, order)
                out[i] = Float(bitPattern: raw)
            }
        case .int32:
            for i in 0..<count {
                let raw = ByteOrderReader.u32(bytes + i * 4, order)
                out[i] = Float(Int32(bitPattern: raw))
            }
        case .int16:
            for i in 0..<count {
                let raw = ByteOrderReader.u16(bytes + i * 2, order)
                out[i] = Float(Int16(bitPattern: raw))
            }
        case .int8:
            for i in 0..<count {
                out[i] = Float(Int8(bitPattern: bytes.loadUnaligned(fromByteOffset: i, as: UInt8.self)))
            }
        }
    }
}
