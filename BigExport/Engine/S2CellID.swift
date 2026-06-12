import Foundation

// Decodes a Google S2 Cell ID (the hex in a Maps `data=!1s0x<cellId>:0x<placeId>`
// URL) into approximate lat/lon. Google Maps Takeout `maps/place/Name/data=…`
// links carry no @lat,lng but DO embed the location as an S2 cell ID, so these
// places can be resolved exactly and offline — no geocoding, no network, no
// mislocation. Ported from the gotoapplemaps web worker (S2 geometry library).
enum S2CellID {
    private static let lookupBits = 4
    private static let maxLevel = 30
    private static let swapMask = 0x01
    private static let invertMask = 0x02
    private static let posToIJ: [[Int]] = [[0, 1, 3, 2], [0, 2, 3, 1], [3, 2, 0, 1], [3, 1, 0, 2]]
    private static let posToOrientation: [Int] = [swapMask, 0, 0, swapMask | invertMask]

    // Hilbert-curve lookup table, built once, immutably (concurrency-safe).
    private static let lookupIJ: [Int] = {
        var table = [Int](repeating: 0, count: 1024)
        func build(_ level: Int, _ i: Int, _ j: Int, _ origOri: Int, _ pos: Int, _ ori: Int) {
            if level == lookupBits {
                let ij = (i << lookupBits) | j
                table[(pos << 2) | origOri] = (ij << 2) | ori
                return
            }
            let r = posToIJ[ori]
            for d in 0..<4 {
                build(level + 1, (i << 1) + (r[d] >> 1), (j << 1) + (r[d] & 1),
                      origOri, (pos << 2) | d, ori ^ posToOrientation[d])
            }
        }
        for o in 0..<4 { build(0, 0, 0, o, 0, o) }
        return table
    }()

    static func toLatLon(_ hex: String) -> (lat: Double, lon: Double)? {
        let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard let cellId = UInt64(clean, radix: 16), cellId > 0 else { return nil }

        let face = Int((cellId >> 61) & 7)
        guard face <= 5 else { return nil }

        var i = 0, j = 0
        var bits = face & swapMask
        var k = 7
        while k >= 0 {
            let nbits = k == 7 ? (maxLevel - 7 * lookupBits) : lookupBits
            let shift = UInt64(k * 2 * lookupBits + 1)
            let mask = (UInt64(1) << UInt64(2 * nbits)) - 1
            let extracted = Int((cellId >> shift) & mask)
            bits += extracted << 2
            bits = lookupIJ[bits]
            i = (i << nbits) + (bits >> (lookupBits + 2))
            j = (j << nbits) + ((bits >> 2) & ((1 << lookupBits) - 1))
            bits &= (swapMask | invertMask)
            k -= 1
        }

        let s = (2.0 * Double(i) + 1) / 2147483648.0
        let t = (2.0 * Double(j) + 1) / 2147483648.0
        let u = s >= 0.5 ? (1.0 / 3.0) * (4 * s * s - 1) : (1.0 / 3.0) * (1 - 4 * (1 - s) * (1 - s))
        let v = t >= 0.5 ? (1.0 / 3.0) * (4 * t * t - 1) : (1.0 / 3.0) * (1 - 4 * (1 - t) * (1 - t))

        let x, y, z: Double
        switch face {
        case 0: x = 1;  y = u;  z = v
        case 1: x = -u; y = 1;  z = v
        case 2: x = -u; y = -v; z = 1
        case 3: x = -1; y = -v; z = -u
        case 4: x = v;  y = -1; z = -u
        case 5: x = v;  y = u;  z = -1
        default: return nil
        }

        let lat = atan2(z, (x * x + y * y).squareRoot()) * 180 / .pi
        let lon = atan2(y, x) * 180 / .pi
        guard !lat.isNaN, !lon.isNaN, (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return (lat, lon)
    }

}
