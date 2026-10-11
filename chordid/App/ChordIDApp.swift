import SwiftData
import SwiftUI

@main
struct ChordIDApp: App {
    init() {
        BrandFont.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: SavedChord.self)
    }
}
