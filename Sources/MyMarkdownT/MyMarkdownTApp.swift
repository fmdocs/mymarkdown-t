import SwiftUI

// MARK: - File menu commands

struct AppCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("另存为…") { appState.saveAs() }
                .keyboardShortcut("S", modifiers: [.command, .shift])
            Divider()
            Button("导出 HTML…") { appState.exportHTML() }
            Button("导出 PDF…") { appState.exportPDF() }
        }
    }
}

// MARK: - App

@main
struct MyMarkdownTApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(state: appState)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    appDelegate.attach(appState)
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                EmptyView()
            }
            AppCommands(appState: appState)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var appState: AppState?
    private var pendingURLs: [URL] = []

    func attach(_ appState: AppState) {
        self.appState = appState

        guard !pendingURLs.isEmpty else { return }
        let queued = pendingURLs
        pendingURLs.removeAll()
        _ = appState.handleIncomingItems(queued)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0).standardizedFileURL }
        guard !urls.isEmpty else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        if let appState {
            let handled = appState.handleIncomingItems(urls)
            sender.reply(toOpenOrPrint: handled ? .success : .failure)
            return
        }

        pendingURLs.append(contentsOf: urls)
        sender.reply(toOpenOrPrint: .success)
    }
}
