import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(.rect(cornerRadius: 20))

            VStack(spacing: 4) {
                Text("BigExport")
                    .font(.largeTitle).fontWeight(.bold)
                Text("for Apple Maps")
                    .font(.title3).foregroundStyle(.secondary)
            }

            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.caption).foregroundStyle(.tertiary)

            Divider().padding(.horizontal, 40)

            VStack(spacing: 6) {
                Text("Import thousands of places from Google Maps,")
                Text("GeoJSON, CSV, or KML into Apple Maps guides.")
            }
            .font(.callout)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)

            Divider().padding(.horizontal, 40)

            HStack(spacing: 20) {
                Link("gotoapplemaps.app", destination: URL(string: "https://gotoapplemaps.app")!)
                Text("·").foregroundStyle(.tertiary)
                Link("GoToAppleMaps", destination: URL(string: "https://apps.apple.com/app/id6756026967")!)
            }
            .font(.callout)
        }
        .padding(40)
        .frame(width: 380)
    }
}
