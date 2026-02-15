import SwiftUI

@main
struct ParseableViewerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutCommand()
            }

            CommandGroup(after: .newItem) {
                Button("New Connection...") {
                    appState.editingConnection = nil
                    appState.showConnectionSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Refresh Query") {
                    appState.queryRefreshToken = UUID()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!appState.isConnected)

                Button("Refresh Streams") {
                    Task {
                        await appState.refreshStreams()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!appState.isConnected)
            }

            CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)), with: nil
                    )
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }

        Window("About Parseable Viewer", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}

private struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Parseable Viewer") {
            openWindow(id: "about")
        }
    }
}
