import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var injector = MapsInjector()
    @State private var jobs: [ImportJob] = []
    @State private var selectedJobID: UUID?
    @State private var isDragging = false
    @State private var errorMessage: String?
    @State private var isImportingAll = false

    private var selectedJob: ImportJob? {
        jobs.first { $0.id == selectedJobID }
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 320)
        } detail: {
            detailContent
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers)
        }
        .overlay(alignment: .topLeading) {
            if isDragging {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFilePicker)) { _ in
            openFilePicker()
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil },
                                             set: { _ in errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        if jobs.isEmpty {
            dropZone
        } else {
            VStack(spacing: 0) {
                List(selection: $selectedJobID) {
                    ForEach($jobs) { $job in
                        JobRow(job: $job)
                            .tag(job.id)
                    }
                    .onDelete { jobs.remove(atOffsets: $0) }
                }
                .listStyle(.sidebar)

                Divider()
                sidebarToolbar
            }
        }
    }

    private var sidebarToolbar: some View {
        HStack {
            Button(role: .destructive) {
                jobs.removeAll()
                selectedJobID = nil
            } label: {
                Label("Clear All", systemImage: "trash")
            }
            .foregroundStyle(.secondary)
            .labelStyle(.iconOnly)
            .disabled(isImportingAll)
            .help("Remove all files")

            Spacer()

            let pending = jobs.filter { $0.status == .ready }
            if !pending.isEmpty {
                Button {
                    runImportAll()
                } label: {
                    Label("Import All", systemImage: "arrow.down.circle.fill")
                    Text("Import All (\(pending.count))")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .disabled(isImportingAll)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle()
                    .fill(isDragging ? Color.red.opacity(0.1) : Color.secondary.opacity(0.08))
                    .frame(width: 90, height: 90)
                Image(systemName: isDragging ? "arrow.down.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(isDragging ? .red : .secondary)
            }
            .animation(.spring(duration: 0.2), value: isDragging)

            VStack(spacing: 4) {
                Text("Drop files here").font(.headline)
                Text("GeoJSON · CSV · KML")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Button("Choose Files…") { openFilePicker() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDragging ? Color.red.opacity(0.04) : Color.clear)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if let job = selectedJob {
            VStack(spacing: 0) {
                guideNameBar(job)
                Divider()
                PlacesMapView(places: job.places)
                Divider()
                statusFooter(job)
            }
        } else {
            emptyDetail
        }
    }

    private func guideNameBar(_ job: ImportJob) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "map")
                .foregroundStyle(.red)
            TextField("Guide name", text: Binding(
                get: { jobs.first(where: { $0.id == job.id })?.guideName ?? "" },
                set: { v in
                    if let i = jobs.firstIndex(where: { $0.id == job.id }) { jobs[i].guideName = v }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .disabled(job.isActive || job.isDone)

            Text("\(job.places.count) places")
                .font(.callout).foregroundStyle(.secondary)
                .layoutPriority(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func statusFooter(_ job: ImportJob) -> some View {
        HStack(spacing: 12) {
            switch job.status {
            case .ready:
                if job.places.count > ImportJob.maxPerCollection {
                    let n = Int(ceil(Double(job.places.count) / Double(ImportJob.maxPerCollection)))
                    Label("Will create \(n) guides (5,000 places each)", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.orange)
                }
                Spacer()
                Button("Add to Maps") { runImport(jobID: job.id) }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(job.guideName.isEmpty || isImportingAll)
                    .keyboardShortcut(.return, modifiers: .command)

            case .importing(let done, let total):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Importing \(done) of \(total) places…")
                        .font(.callout).foregroundStyle(.secondary)
                    ProgressView(value: Double(done), total: Double(total))
                        .progressViewStyle(.linear).tint(.red)
                        .frame(maxWidth: 240)
                }
                Spacer()
                ProgressView().controlSize(.small)

            case .done(let n):
                Label(
                    n == 1 ? "Guide added to Maps!" : "\(n) guides added to Maps!",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green).fontWeight(.medium)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Open Maps → Guides → Share → Copy Link")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Maps") {
                        NSWorkspace.shared.open(URL(string: "maps://")!)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }

            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red).font(.callout)
                Spacer()
                Button("Retry") { runImport(jobID: job.id) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 56)
    }

    private var emptyDetail: some View {
        ContentUnavailableView(
            "No File Selected",
            systemImage: "map",
            description: Text("Drop a GeoJSON, CSV, or KML file into the sidebar\nor choose one with ⌘O")
        )
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json, .commaSeparatedText, .xml,
                                      UTType(filenameExtension: "kml") ?? .xml,
                                      UTType(filenameExtension: "geojson") ?? .json]
        panel.begin { response in
            guard response == .OK else { return }
            panel.urls.forEach { loadFile($0) }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async { loadFile(url) }
            }
        }
        return true
    }

    private func loadFile(_ url: URL) {
        let stem = url.deletingPathExtension().lastPathComponent
        guard !jobs.contains(where: { $0.guideName == stem }) else { return }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "Could not read \(url.lastPathComponent)"; return
        }
        let ext = url.pathExtension.lowercased()
        do {
            let places: [Place]
            switch ext {
            case "json", "geojson": places = try GeoJSONParser.parse(data)
            case "csv":             places = try CSVParser.parse(data)
            case "kml":             places = try KMLParser.parse(data)
            default: throw ParseError.invalidFormat
            }
            guard !places.isEmpty else { throw ParseError.noPlacesFound }
            var job = ImportJob(guideName: stem, places: places)
            job.fileExtension = ext
            jobs.append(job)
            if selectedJobID == nil { selectedJobID = job.id }
        } catch {
            errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func runImport(jobID: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let job = jobs[idx]
        jobs[idx].status = .importing(0, job.places.count)
        Task {
            do {
                let n = try await injector.importJob(job) { done, total in
                    if let i = jobs.firstIndex(where: { $0.id == jobID }) {
                        jobs[i].status = .importing(done, total)
                    }
                }
                if let i = jobs.firstIndex(where: { $0.id == jobID }) {
                    jobs[i].status = .done(n)
                }
            } catch {
                if let i = jobs.firstIndex(where: { $0.id == jobID }) {
                    jobs[i].status = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func runImportAll() {
        isImportingAll = true
        let pendingIDs = jobs.filter { $0.status == .ready }.map(\.id)
        Task {
            for id in pendingIDs {
                runImport(jobID: id)
                // Wait for this job to finish before starting next (shared Maps DB)
                while let job = jobs.first(where: { $0.id == id }), job.isActive {
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
            isImportingAll = false
        }
    }
}

// MARK: - Sidebar row

struct JobRow: View {
    @Binding var job: ImportJob

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(formatColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Text(job.fileExtension.uppercased().prefix(3))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(formatColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(job.guideName).lineLimit(1)
                statusLabel
            }

            Spacer(minLength: 0)
            statusIcon
        }
        .padding(.vertical, 3)
    }

    private var formatColor: Color {
        switch job.fileExtension {
        case "csv": return .green
        case "kml": return .orange
        default:    return .blue
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch job.status {
        case .ready:
            Text("\(job.places.count) places")
                .font(.caption).foregroundStyle(.secondary)
        case .importing(let done, let total):
            Text("\(done) / \(total)")
                .font(.caption).foregroundStyle(.orange)
        case .done:
            Text("Added to Maps")
                .font(.caption).foregroundStyle(.green)
        case .failed:
            Text("Failed")
                .font(.caption).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .ready:    EmptyView()
        case .importing: ProgressView().controlSize(.mini)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        }
    }
}
