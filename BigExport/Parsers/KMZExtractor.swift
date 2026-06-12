import Foundation

// KMZ is a ZIP archive wrapping a KML document (usually doc.kml at the root).
enum KMZExtractor {
    static func extractKML(from kmzURL: URL) throws -> Data {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("bigexport-kmz-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", "-q", kmzURL.path, "-d", tmp.path]
        unzip.standardOutput = FileHandle.nullDevice
        unzip.standardError = FileHandle.nullDevice
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw ParseError.invalidFormat }

        // Prefer doc.kml; otherwise first .kml anywhere in the archive
        let docKML = tmp.appendingPathComponent("doc.kml")
        if let data = try? Data(contentsOf: docKML) { return data }
        let enumerator = FileManager.default.enumerator(at: tmp, includingPropertiesForKeys: nil)
        while let file = enumerator?.nextObject() as? URL {
            if file.pathExtension.lowercased() == "kml" {
                return try Data(contentsOf: file)
            }
        }
        throw ParseError.invalidFormat
    }
}
