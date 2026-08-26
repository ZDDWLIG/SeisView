public enum ByteOrderReader {
    @inlinable
    public static func u16(_ p: UnsafeRawPointer, _ o: ByteOrder) -> UInt16 {
        let v = p.loadUnaligned(as: UInt16.self)
        return o == .big ? UInt16(bigEndian: v) : UInt16(littleEndian: v)
    }
    @inlinable
    public static func u32(_ p: UnsafeRawPointer, _ o: ByteOrder) -> UInt32 {
        let v = p.loadUnaligned(as: UInt32.self)
        return o == .big ? UInt32(bigEndian: v) : UInt32(littleEndian: v)
    }
    @inlinable
    public static func i32(_ p: UnsafeRawPointer, _ o: ByteOrder) -> Int32 {
        let v = p.loadUnaligned(as: Int32.self)
        return o == .big ? Int32(bigEndian: v) : Int32(littleEndian: v)
    }
}
