import SwiftUI
import MapKit

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
        HStack(spacing: 0) {
            // Left panel — job list
            VStack(spacing: 0) {
                headerSection
                Divider()
                if jobs.isEmpty {
                    dropZone
                } else {
                    jobList
                }
            }
            .frame(width: 300)
            .background(.background)

            Divider()

            // Right panel — detail + map
            if let job = selectedJob {
                jobDetailPanel(job)
            } else {
                emptyDetail
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers)
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "map.fill")
                .foregroundStyle(.red)
                .font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text("BigExport").font(.headline)
                Text("for Apple Maps").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !jobs.isEmpty {
                Button {
                    openFilePicker()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add more files")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Drop zone (empty state)

    private var dropZone: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: isDragging ? "arrow.down.circle.fill" : "arrow.down.circle")
                .font(.system(size: 44))
                .foregroundStyle(isDragging ? .red : .secondary)
                .animation(.spring(duration: 0.2), value: isDragging)
            Text("Drop files here")
                .font(.title3).fontWeight(.medium)
            Text("GeoJSON · CSV · KML\nDrop multiple files at once")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Choose Files…") { openFilePicker() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDragging ? Color.red.opacity(0.06) : Color.clear)
    }

    // MARK: - Job list

    private var jobList: some View {
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
            bottomBar
        }
    }

    private var bottomBar: some View {
        HStack {
            Button("Clear All") {
                jobs.removeAll()
                selectedJobID = nil
            }
            .foregroundStyle(.secondary)
            .disabled(isImportingAll)
            .controlSize(.small)

            Spacer()

            let pending = jobs.filter { if case .ready = $0.status { return true }; return false }
            if !pending.isEmpty {
                Button("Import All (\(pending.count))") { runImportAll() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isImportingAll)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Detail panel

    private func jobDetailPanel(_ job: ImportJob) -> some View {
        VStack(spacing: 0) {
            // Name editor
            VStack(alignment: .leading, spacing: 6) {
                Text("Guide name").font(.caption).foregroundStyle(.secondary)
                TextField("Guide name", text: Binding(
                    get: { jobs.first(where: { $0.id == job.id })?.guideName ?? "" },
                    set: { newVal in
                        if let i = jobs.firstIndex(where: { $0.id == job.id }) {
                            jobs[i].guideName = newVal
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(job.status != .ready)
            }
            .padding(16)

            Divider()

            // Map preview
            if !job.places.isEmpty {
                PlacesMapView(places: job.places)
            } else {
                emptyDetail
            }

            // Status footer
            statusFooter(job)
        }
    }

    @ViewBuilder
    private func statusFooter(_ job: ImportJob) -> some View {
        Divider()
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(job.places.count) places")
                    .fontWeight(.medium)
                if job.places.count > ImportJob.maxPerCollection {
                    let n = Int(ceil(Double(job.places.count) / Double(ImportJob.maxPerCollection)))
                    Text("→ \(n) guides").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            switch job.status {
            case .ready:
                Button("Add to Maps") { runImport(jobID: job.id) }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .disabled(isImportingAll || job.guideName.isEmpty)
            case .importing(let done, let total):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("\(done)/\(total)").font(.caption).foregroundStyle(.secondary)
                }
            case .done(let n):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(n == 1 ? "Added" : "\(n) guides added").foregroundStyle(.green)
                    Button("Open Maps") { NSWorkspace.shared.open(URL(string: "maps://")!) }
                        .controlSize(.small)
                }
            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red).font(.caption)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyDetail: some View {
        ZStack {
            Rectangle().fill(Color(nsColor: .windowBackgroundColor))
            VStack(spacing: 8) {
                Image(systemName: "map").font(.system(size: 52)).foregroundStyle(.quaternary)
                Text("Select a file to preview").foregroundStyle(.quaternary)
            }
        }
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json, .commaSeparatedText, .xml]
        panel.begin { response in
            if response == .OK {
                panel.urls.forEach { loadFile($0) }
            }
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
        // Skip duplicates
        let stem = url.deletingPathExtension().lastPathComponent
        guard !jobs.contains(where: { $0.guideName == stem }) else { return }

        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "Could not read \(url.lastPathComponent)"; return
        }
        do {
            let places: [Place]
            switch url.pathExtension.lowercased() {
            case "json": places = try GeoJSONParser.parse(data)
            case "csv":  places = try CSVParser.parse(data)
            default: throw ParseError.invalidFormat
            }
            guard !places.isEmpty else { throw ParseError.noPlacesFound }
            let job = ImportJob(guideName: stem, places: places)
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
                let n = try await injector.importJob(job)
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
        let pendingIDs = jobs.filter { if case .ready = $0.status { return true }; return false }.map(\.id)
        Task {
            for id in pendingIDs { runImport(jobID: id) }
            // Wait for all to finish
            while jobs.contains(where: { if case .importing = $0.status { return true }; return false }) {
                try? await Task.sleep(for: .milliseconds(300))
            }
            isImportingAll = false
        }
    }
}

// MARK: - Job row

struct JobRow: View {
    @Binding var job: ImportJob

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(job.guideName)
                    .lineLimit(1)
                    .font(.system(.body))
                Text("\(job.places.count) places")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .ready:
            Image(systemName: "doc.fill")
                .foregroundStyle(.secondary)
                .frame(width: 20)
        case .importing:
            ProgressView().controlSize(.mini).frame(width: 20)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 20)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .frame(width: 20)
        }
    }
}
