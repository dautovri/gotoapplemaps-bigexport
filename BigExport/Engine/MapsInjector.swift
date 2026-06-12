import Foundation
import CoreData

@MainActor
final class MapsInjector: ObservableObject {

    private let modelURL = URL(fileURLWithPath:
        "/System/Library/PrivateFrameworks/MapsSync.framework/Versions/A/Resources/DataModel_0_0_1.momd")
    private let storeURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.apple.Maps/Data/Maps/MapsSync_0.0.1")

    // Progress callback: (saved, total)
    typealias ProgressHandler = @Sendable (Int, Int) -> Void

    func importJob(_ job: ImportJob, onProgress: @escaping ProgressHandler) async throws -> Int {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            throw InjectorError.mapsNotInstalled
        }
        guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw InjectorError.modelLoadFailed
        }

        // Quit Maps so we get exclusive write access
        if MapsProcessManager.isMapsRunning {
            await MapsProcessManager.quitMaps()
        }

        let container = NSPersistentContainer(name: "MapsSync_0_0_1", managedObjectModel: model)
        let desc = NSPersistentStoreDescription(url: storeURL)
        desc.type = NSSQLiteStoreType
        desc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        desc.setOption(true as NSNumber, forKey: "NSPersistentStoreRemoteChangeNotificationOptionKey")
        container.persistentStoreDescriptions = [desc]

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let e = error { cont.resume(throwing: e) } else { cont.resume() }
            }
        }

        let chunks = job.places.chunked(by: ImportJob.maxPerCollection)
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        let total = job.places.count
        let batchSize = 250
        nonisolated(unsafe) var saved = 0

        try await ctx.perform {
            let now = Date()

            for (chunkIndex, chunk) in chunks.enumerated() {
                let title: String = chunks.count == 1
                    ? job.guideName
                    : "\(job.guideName) (\(chunkIndex + 1)/\(chunks.count))"

                let coll = NSEntityDescription.insertNewObject(forEntityName: "Collection", into: ctx)
                coll.setValue(UUID(), forKey: "identifier")
                coll.setValue(title, forKey: "title")
                coll.setValue(now, forKey: "createTime")
                coll.setValue(now, forKey: "modificationTime")
                coll.setValue(Int32(chunkIndex), forKey: "positionIndex")

                var allItems: [NSManagedObject] = []

                for batchStart in stride(from: 0, to: chunk.count, by: batchSize) {
                    let batchEnd = min(batchStart + batchSize, chunk.count)
                    let batch = chunk[batchStart..<batchEnd]

                    for (localIdx, place) in batch.enumerated() {
                        let globalIdx = chunkIndex * ImportJob.maxPerCollection + batchStart + localIdx
                        let pid = 2_000_000 + globalIdx
                        let localID = UInt64(bitPattern: Int64(place.name.hashValue ^ globalIdx))
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
                        it.setValue(Int32(batchStart + localIdx), forKey: "positionIndex")
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

                        allItems.append(it)
                    }

                    // Save each batch so progress is real
                    coll.setValue(NSSet(array: allItems), forKey: "places")
                    coll.setValue(Int32(allItems.count), forKey: "placesCount")
                    try ctx.save()

                    saved += batch.count
                    let snapshot = saved
                    Task { await MainActor.run { onProgress(snapshot, total) } }
                }
            }
        }

        // Relaunch Maps so CloudKit picks up the new records
        await MapsProcessManager.launchMaps()

        return chunks.count
    }
}

enum InjectorError: LocalizedError {
    case mapsNotInstalled
    case modelLoadFailed

    var errorDescription: String? {
        switch self {
        case .mapsNotInstalled:
            return "Apple Maps database not found. Open Maps at least once first."
        case .modelLoadFailed:
            return "Could not load MapsSync data model. macOS 15+ required."
        }
    }
}

extension Array {
    func chunked(by size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size)
            .map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
