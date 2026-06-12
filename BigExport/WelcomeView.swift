import SwiftUI

struct WelcomeView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Hero
            VStack(spacing: 16) {
                Image(systemName: "map.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.red)
                    .padding(.top, 40)

                Text("Welcome to BigExport")
                    .font(.largeTitle).fontWeight(.bold)

                Text("Import thousands of saved places into Apple Maps — in seconds.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.bottom, 36)

            // Feature rows
            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    icon: "arrow.down.doc.fill", color: .blue,
                    title: "Any format",
                    detail: "Google Maps Takeout (GeoJSON), CSV spreadsheets, KML files"
                )
                FeatureRow(
                    icon: "square.stack.3d.up.fill", color: .orange,
                    title: "Bulk imports",
                    detail: "Drop multiple files — up to 5,000 places per guide, auto-split if more"
                )
                FeatureRow(
                    icon: "icloud.fill", color: .purple,
                    title: "Real Apple Maps guides",
                    detail: "Share a single iCloud link anyone can open in Maps"
                )
            }
            .padding(.horizontal, 48)

            Spacer(minLength: 32)

            Button("Get Started") { onDismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .padding(.bottom, 40)
        }
        .frame(width: 500, height: 520)
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
