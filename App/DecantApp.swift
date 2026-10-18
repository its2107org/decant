import SwiftData
import SwiftUI

@main
struct DecantApp: App {
    let container: ModelContainer

    init() {
        container = Demo.isOn ? Demo.container() : DecantApp.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task { await SelfTest.runIfRequested(container: container) }
        }
        .modelContainer(container)
    }

    private static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: Wine.self)
        } catch {
            // Never lose the app to a storage problem; fall back to a temporary store and say so in Settings.
            AppState.shared.storageProblem = error.localizedDescription
            return try! ModelContainer(for: Wine.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }
}

enum AppTab: Hashable {
    case cellar, tasted, scan, search
}

@MainActor
@Observable
final class AppState {
    static let shared = AppState()
    var tab: AppTab = Demo.startTab
    var showSettings = Demo.startWithSettings
    var storageProblem: String?
    private init() {}
}

struct RootView: View {
    @State private var app = AppState.shared

    var body: some View {
        TabView(selection: $app.tab) {
            Tab("Cellar", systemImage: "square.stack.3d.up.fill", value: AppTab.cellar) {
                WineListView(status: .cellar)
            }
            Tab("Tasted", systemImage: "wineglass.fill", value: AppTab.tasted) {
                WineListView(status: .tasted)
            }
            Tab("Scan", systemImage: "camera.viewfinder", value: AppTab.scan) {
                ScanView()
            }
            Tab("Vinous", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                VinousSearchView()
            }
        }
        .sheet(isPresented: $app.showSettings) {
            SettingsView()
        }
    }
}
