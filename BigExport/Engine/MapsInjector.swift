import Foundation
import CoreData

@MainActor
final class MapsInjector: ObservableObject {
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""

    private let modelURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MapsSync.framework/Versions/A/Resources/DataModel_0_0_1.momd")
    private let storeURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.apple.Maps/Data/Maps/MapsSync_0.0.1")

    // Returns number of collections created
    func importJob(_ job: ImportJob) async throws -> Int {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            throw InjectorError.mapsNotInstalled
        }
        guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw InjectorError.modelLoadFailed
        }

        let container = NSPersistentContainer(name: "MapsSync_0_0_1", managedObjectModel: model)
        let desc = NSPersistentStoreDescription(url: storeURL)
        desc.type = NSSQLiteStoreType
        desc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        desc.setOption(true as NSNumber, forKey: "NSPersistentStoreRemoteChangeNotificationOptionKey")
        container.persistentStoreDescriptions = [desc]

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let e = error { cont.resume(throwing: e) }
                else { cont.resume() }
            }
        }

        let chunks = job.places.chunked(by: ImportJob.maxPerCollection)
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        try await ctx.perform {
            let now = Date()
            for (chunkIndex, chunk) in chunks.enumerated() {
                let title: String
                if chunks.count == 1 {
                    title = job.guideName
                } else {
                    title = "\(job.guideName) (\(chunkIndex + 1)/\(chunks.count))"
                }

                let coll = NSEntityDescription.insertNewObject(forEntityName: "Collection", into: ctx)
                coll.setValue(UUID(), forKey: "identifier")
                coll.setValue(title, forKey: "title")
                coll.setValue(now, forKey: "createTime")
                coll.setValue(now, forKey: "modificationTime")
                coll.setValue(Int32(chunkIndex), forKey: "positionIndex")

                var items: [NSManagedObject] = []
                for (i, place) in chunk.enumerated() {
                    let pid = 2_000_000 + chunkIndex * ImportJob.maxPerCollection + i
                    let localID = UInt64(bitPattern: Int64(place.name.hashValue ^ i))
                    let blob = BlobBuilder.build(
                        name: place.name, lat: place.latitude, lon: place.longitude,
                        placeID: pid, localID: localID, country: place.countryCode
                    )

                    let it = NSEntityDescription.insertNewObject(forEntityName: "CollectionPlaceItem", into: ctx)
                    it.setValue(UUID(), forKey: "identifier")
                    it.setValue(place.latitude, forKey: "latitude")
                    it.setValue(place.longitude, forKey: "longitude")
                    it.setValue(place.name, forKey: "mapItemName")
                    it.setValue(place.name, forKey: "customName")
                    it.setValue(place.address, forKey: "mapItemAddress")
                    it.setValue(now, forKey: "createTime")
                    it.setValue(now, forKey: "modificationTime")
                    it.setValue(Int32(i), forKey: "positionIndex")
                    it.setValue(Int16(0), forKey: "origin")
                    it.setValue(Int16(0), forKey: "type")
                    it.setValue(NSNumber(value: pid), forKey: "muid")

                    let mi = NSEntityDescription.insertNewObject(forEntityName: "MixinMapItem", into: ctx)
                    mi.setValue(place.latitude, forKey: "latitude")
                    mi.setValue(place.longitude, forKey: "longitude")
                    mi.setValue(now, forKey: "createTime")
                    mi.setValue(now, forKey: "modificationTime")
                    mi.setValue(blob, forKey: "mapItemStorage")
                    mi.setValue(it, forKey: "collectionPlaceItem")

                    items.append(it)
                }

                coll.setValue(NSSet(array: items), forKey: "places")
                coll.setValue(Int32(items.count), forKey: "placesCount")
            }
            try ctx.save()
        }

        return chunks.count
    }
}

enum InjectorError: LocalizedError {
    case mapsNotInstalled
    case modelLoadFailed

    var errorDescription: String? {
        switch self {
        case .mapsNotInstalled: return "Apple Maps database not found. Make sure Maps has been opened at least once."
        case .modelLoadFailed: return "Could not load MapsSync data model. Ensure macOS 15+ is installed."
        }
    }
}

extension Array {
    func chunked(by size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
