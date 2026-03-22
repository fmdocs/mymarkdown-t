import SwiftUI

// MARK: - Per-window focused value

private struct AppStateFocusedValueKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var appState: AppState? {
        get { self[AppStateFocusedValueKey.self] }
        set { self[AppStateFocusedValueKey.self] = newValue }
    }
}

// MARK: - File menu commands

struct AppCommands: Commands {
    @FocusedValue(\.appState) private var appState

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("另存为…") { appState?.saveAs() }
                .keyboardShortcut("S", modifiers: [.command, .shift])
                .disabled(appState == nil)
            Divider()
            Button("导出 HTML…") { appState?.exportHTML() }
                .disabled(appState == nil)
            Button("导出 PDF…") { appState?.exportPDF() }
                .disabled(appState == nil)
        }
    }
}

// MARK: - File open coordinator

@MainActor
final class FileOpenCoordinator {
    static let shared = FileOpenCoordinator()

    private var pendingURLs: [URL] = []
    private var openWindowAction: OpenWindowAction?
    private weak var emptyWindowState: AppState?

    var isReady: Bool { openWindowAction != nil }

    func registerWindow(_ state: AppState, openWindow action: OpenWindowAction) {
        openWindowAction = action
        if state.currentFileURL == nil {
            emptyWindowState = state
        }
    }

    func enqueue(_ url: URL) {
        pendingURLs.append(url)
    }

    func dequeue() -> URL? {
        pendingURLs.isEmpty ? nil : pendingURLs.removeFirst()
    }

    func openFile(_ url: URL) {
        // Reuse an existing empty window if available
        if let state = emptyWindowState, state.currentFileURL == nil {
            emptyWindowState = nil
            _ = state.handleIncomingItems([url])
            return
        }

        emptyWindowState = nil
        enqueue(url)
        openWindowAction?.callAsFunction(id: "document")
    }
}

// MARK: - Per-window document wrapper

private struct DocumentWindow: View {
    @StateObject private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView(state: appState)
            .focusedSceneValue(\.appState, appState)
            .onAppear {
                let coordinator = FileOpenCoordinator.shared
                coordinator.registerWindow(appState, openWindow: openWindow)
                if let url = coordinator.dequeue() {
                    _ = appState.handleIncomingItems([url])
                }
            }
    }
}

// MARK: - App

@main
struct MyMarkdownTApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "document") {
            DocumentWindow()
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                EmptyView()
            }
            AppCommands()
        }
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0).standardizedFileURL }
        guard !urls.isEmpty else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        routeURLs(urls)
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        routeURLs(urls.map(\.standardizedFileURL))
    }

    private func routeURLs(_ urls: [URL]) {
        let coordinator = FileOpenCoordinator.shared
        for url in urls {
            if coordinator.isReady {
                coordinator.openFile(url)
            } else {
                coordinator.enqueue(url)
            }
        }
    }
}
