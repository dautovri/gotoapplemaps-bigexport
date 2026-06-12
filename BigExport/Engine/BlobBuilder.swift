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
        let coord = float64Field(1, lat) + float64Field(2, lon)
        let inner = msgField(2, msgField(1, coord))
        return sectionWrapper(type: 2, inner: msgField(2, inner), country: country)
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
        var v = n; var out = Data()
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
}
