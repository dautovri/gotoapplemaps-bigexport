import Foundation

// Builds a minimal Apple Maps place-card protobuf blob from name + coordinate.
// This matches the "apple/fwdgeo" format Maps uses for address-geocoded pins.
enum BlobBuilder {
    static func build(name: String, lat: Double, lon: Double,
                      placeID: Int, localID: UInt64, country: String = "US") -> Data {
        let nameSection = makeNameSection(name: name, country: country)
        let coordSection = makeCoordSection(lat: lat, lon: lon, country: country)
        let ref = makeRef(lat: lat, lon: lon, placeID: placeID, localID: localID)
        let inner = varint(field: 2, value: 0)
            + msgField(4, nameSection)
            + msgField(4, coordSection)
            + varint(field: 5, value: placeID)
            + msgField(7, ref)
            + varint(field: 200, value: 1)
        return msgField(1, inner)
    }

    // MARK: - Sections

    private static func makeNameSection(name: String, country: String) -> Data {
        let nameLoc = strField(1, "en-US") + strField(3, name)
        let payload = varint(field: 1, value: 57)
            + varint(field: 9, value: 0)
            + msgField(10, nameLoc)
            + varint(field: 19, value: 3)
        return sectionWrapper(type: 1, inner: msgField(1, payload), country: country)
    }

    private static func makeCoordSection(lat: Double, lon: Double, country: String) -> Data {
        // Real fwdgeo blobs put the coordinate at field8 → field2 → field1 →
        // {1:lat, 2:lon}. We previously had an extra field-2 wrapper (8.2.2.1),
        // so Maps read a sub-message instead of the lat/lon doubles when it
        // published the guide to iCloud → exported coordinate became -180.
        let coord = float64Field(1, lat) + float64Field(2, lon)
        let inner = msgField(1, coord)                 // field1 { lat, lon }
        return sectionWrapper(type: 2, inner: msgField(2, inner), country: country)  // field8 { field2 { field1 { … } } }
    }

    private static func makeRef(lat: Double, lon: Double, placeID: Int, localID: UInt64) -> Data {
        let coord = float64Field(1, lat) + float64Field(2, lon)
        let inner = msgField(2, coord)
            + varint(field: 3, value: placeID)
            + varint(field: 4, value: Int(bitPattern: UInt(localID)))
            + varint(field: 50, value: 1)
        return msgField(1, inner)
    }

    private static func sectionWrapper(type: Int, inner: Data, country: String) -> Data {
        var d = Data()
        d += varint(field: 1, value: type)
        d += varint(field: 2, value: 0)
        d += varint(field: 4, value: 2_592_000)
        d += varint(field: 6, value: 1)
        d += msgField(8, inner)
        d += strField(9, "apple")
        d += strField(9, "fwdgeo")
        d += strField(9, country)
        d += varint(field: 10, value: 1)
        d += varint(field: 12, value: 2)
        d += float64Field(2000, 0.0)
        return d
    }

    // MARK: - Protobuf primitives

    static func encodeVarint(_ n: Int) -> Data {
        // Reinterpret as unsigned 64-bit so the shift is logical (zero-fill).
        // A signed `>>=` on a negative value sign-extends and never reaches 0 →
        // infinite loop. This also matches protobuf, which encodes a negative
        // int64 as a full 10-byte varint of its two's-complement bit pattern.
        var v = UInt64(bitPattern: Int64(n)); var out = Data()
        repeat {
            var b = UInt8(v & 0x7F); v >>= 7
            if v != 0 { b |= 0x80 }
            out.append(b)
        } while v != 0
        return out
    }

    private static func varint(field: Int, value: Int) -> Data {
        encodeVarint((field << 3) | 0) + encodeVarint(value)
    }

    private static func strField(_ field: Int, _ s: String) -> Data {
        let d = Data(s.utf8)
        return encodeVarint((field << 3) | 2) + encodeVarint(d.count) + d
    }

    private static func msgField(_ field: Int, _ d: Data) -> Data {
        encodeVarint((field << 3) | 2) + encodeVarint(d.count) + d
    }

    private static func float64Field(_ field: Int, _ v: Double) -> Data {
        encodeVarint((field << 3) | 1) + withUnsafeBytes(of: v.bitPattern.littleEndian) { Data($0) }
    }

    // MARK: - Self-verification
    //
    // Read the coordinate back out of a blob the same way Maps does — from the
    // coordinate section (field 4 with type == 2) → field 8 → field 2 → field 1
    // → {1: lat, 2: lon}. This is the exact path that was wrong before (nested
    // one level too deep), which made Maps show every place at 0,0/-180. Reading
    // it back lets the app prove a blob is actually readable before writing it.
    static func readCoordinate(from blob: Data) -> (lat: Double, lon: Double)? {
        var top = Reader(blob)
        guard let (f, w) = top.tag(), f == 1, w == 2, let inner = top.bytes() else { return nil }
        var r = Reader(inner)
        while let (field, wire) = r.tag() {
            if field == 4, wire == 2, let section = r.bytes() {
                if sectionType(section) == 2, let c = coordInSection(section) { return c }
            } else {
                r.skip(wire)
            }
        }
        return nil
    }

    // Build a blob for a known coordinate and confirm it reads back correctly.
    // Catches any structural regression in the blob format before import.
    static func selfTest() -> Bool {
        let lat = 12.3456789, lon = -98.7654321
        let blob = build(name: "SelfTest", lat: lat, lon: lon,
                         placeID: 2_000_000, localID: 0xF0F0F0F0F0F0F0F0, country: "US")
        guard let c = readCoordinate(from: blob) else { return false }
        return abs(c.lat - lat) < 1e-6 && abs(c.lon - lon) < 1e-6
    }

    private static func sectionType(_ section: Data) -> Int? {
        var r = Reader(section)
        while let (f, w) = r.tag() {
            if f == 1, w == 0 { return r.varint().map(Int.init) }
            r.skip(w)
        }
        return nil
    }

    private static func coordInSection(_ section: Data) -> (lat: Double, lon: Double)? {
        // field8 → field2 → field1 → {1: lat (f64), 2: lon (f64)}
        func descend(_ data: Data, _ field: Int) -> Data? {
            var r = Reader(data)
            while let (f, w) = r.tag() {
                if f == field, w == 2 { return r.bytes() }
                r.skip(w)
            }
            return nil
        }
        guard let f8 = descend(section, 8), let f2 = descend(f8, 2), let f1 = descend(f2, 1) else { return nil }
        var r = Reader(f1); var lat: Double?, lon: Double?
        while let (f, w) = r.tag() {
            if w == 1 {
                let d = r.fixed64()
                if f == 1 { lat = d } else if f == 2 { lon = d }
            } else { r.skip(w) }
        }
        if let lat, let lon { return (lat, lon) }
        return nil
    }

    // Minimal protobuf reader (handles Data slices with non-zero start index).
    private struct Reader {
        let d: Data; var i: Int
        init(_ data: Data) { d = data; i = data.startIndex }
        mutating func varint() -> UInt64? {
            var v: UInt64 = 0, s = 0
            while i < d.endIndex {
                let b = d[i]; i += 1
                v |= UInt64(b & 0x7f) << s
                if b & 0x80 == 0 { return v }
                s += 7
            }
            return nil
        }
        mutating func tag() -> (Int, Int)? {
            guard i < d.endIndex, let t = varint() else { return nil }
            return (Int(t >> 3), Int(t & 7))
        }
        mutating func bytes() -> Data? {
            guard let len = varint() else { return nil }
            let end = d.index(i, offsetBy: Int(len), limitedBy: d.endIndex) ?? d.endIndex
            defer { i = end }
            return Data(d[i..<end])
        }
        mutating func fixed64() -> Double? {
            guard d.distance(from: i, to: d.endIndex) >= 8 else { return nil }
            var bits: UInt64 = 0
            for k in 0..<8 { bits |= UInt64(d[d.index(i, offsetBy: k)]) << (8 * k) }
            i = d.index(i, offsetBy: 8)
            return Double(bitPattern: bits)
        }
        mutating func skip(_ wire: Int) {
            switch wire {
            case 0: _ = varint()
            case 1: i = d.index(i, offsetBy: 8, limitedBy: d.endIndex) ?? d.endIndex
            case 2: _ = bytes()
            case 5: i = d.index(i, offsetBy: 4, limitedBy: d.endIndex) ?? d.endIndex
            default: i = d.endIndex
            }
        }
    }
}
