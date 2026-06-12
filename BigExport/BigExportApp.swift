import SwiftUI

@main
struct BigExportApp: App {
    @State private var showWelcome = !UserDefaults.standard.bool(forKey: "hasLaunched")
    @State private var showAbout = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 820, minHeight: 520)
                .sheet(isPresented: $showWelcome) {
                    WelcomeView {
                        showWelcome = false
                        UserDefaults.standard.set(true, forKey: "hasLaunched")
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // Replace New with Open
            CommandGroup(replacing: .newItem) {
                Button("Open File…") {
                    NotificationCenter.default.post(name: .openFilePicker, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            // About under App menu
            CommandGroup(replacing: .appInfo) {
                Button("About BigExport") { showAbout = true }
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Link("BigExport Website",
                     destination: URL(string: "https://gotoapplemaps.com")!)
                Divider()
                Button("Show Welcome Screen") {
                    showWelcome = true
                }
            }
        }

        // Floating About window
        Window("About BigExport", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

extension Notification.Name {
    static let openFilePicker = Notification.Name("openFilePicker")
}
