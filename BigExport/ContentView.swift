import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var injector = MapsInjector()
    @State private var job: ImportJob?
    @State private var isDragging = false
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var importDone = false
    @State private var collectionsCreated = 0

    var body: some View {
        HStack(spacing: 0) {
            // Left panel
            VStack(spacing: 0) {
                headerSection
                Divider()
                if let job {
                    jobDetailSection(job)
                } else {
                    dropZone
                }
                Spacer()
                if job != nil { bottomBar }
            }
            .frame(width: 280)
            .background(.background)

            Divider()

            // Right panel — map preview
            mapPreview
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        HStack {
            Image(systemName: "map.fill")
                .foregroundStyle(.red)
                .font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text("BigExport").font(.headline)
                Text("for Apple Maps").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: isDragging ? "arrow.down.circle.fill" : "arrow.down.circle")
                .font(.system(size: 40))
                .foregroundStyle(isDragging ? .red : .secondary)
                .animation(.spring(duration: 0.2), value: isDragging)
            Text("Drop file here")
                .font(.title3).fontWeight(.medium)
            Text("GeoJSON · CSV · KML")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDragging ? Color.red.opacity(0.05) : Color.clear)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers)
        }
    }

    private func jobDetailSection(_ j: ImportJob) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Guide name").font(.caption).foregroundStyle(.secondary)
                TextField("Guide name", text: Binding(
                    get: { job?.guideName ?? "" },
                    set: { job?.guideName = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(isImporting || importDone)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Places").font(.caption).foregroundStyle(.secondary)
                Text("\(j.places.count)")
                    .font(.system(.title2, design: .rounded)).fontWeight(.bold)
                if j.places.count > ImportJob.maxPerCollection {
                    let n = Int(ceil(Double(j.places.count) / Double(ImportJob.maxPerCollection)))
                    Text("Will create \(n) guides")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            if isImporting {
                VStack(alignment: .leading, spacing: 6) {
                    Text(injector.statusMessage).font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: injector.progress)
                        .progressViewStyle(.linear)
                        .tint(.red)
                }
            }

            if importDone {
                Label(
                    collectionsCreated == 1 ? "Guide added to Maps!" : "\(collectionsCreated) guides added to Maps!",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
                .font(.subheadline)

                Text("Open Maps → find your guide → Share → Copy Link")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Maps") {
                    NSWorkspace.shared.open(URL(string: "maps://")!)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(16)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Divider()
            HStack {
                Button("Clear") {
                    job = nil
                    importDone = false
                    isImporting = false
                }
                .foregroundStyle(.secondary)
                .disabled(isImporting)
                Spacer()
                if !importDone {
                    Button("Add to Maps") { runImport() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(isImporting || (job?.guideName.isEmpty ?? true))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var mapPreview: some View {
        if let job, !job.places.isEmpty {
            PlacesMapView(places: job.places)
        } else {
            ZStack {
                Rectangle().fill(Color(nsColor: .windowBackgroundColor))
                VStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.system(size: 48))
                        .foregroundStyle(.quaternary)
                    Text("Map preview appears here")
                        .foregroundStyle(.quaternary)
                }
            }
        }
    }

    // MARK: - Actions

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async { loadFile(url) }
        }
        return true
    }

    private func loadFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "Could not read file."; return
        }
        let ext = url.pathExtension.lowercased()
        let stem = url.deletingPathExtension().lastPathComponent
        do {
            let places: [Place]
            switch ext {
            case "json": places = try GeoJSONParser.parse(data)
            case "csv":  places = try CSVParser.parse(data)
            default: throw ParseError.invalidFormat
            }
            guard !places.isEmpty else { throw ParseError.noPlacesFound }
            job = ImportJob(guideName: stem, places: places)
            importDone = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runImport() {
        guard let j = job else { return }
        isImporting = true
        injector.statusMessage = "Preparing \(j.places.count) places…"
        injector.progress = 0
        Task {
            do {
                let n = try await injector.importJob(j)
                collectionsCreated = n
                importDone = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
    }
}
