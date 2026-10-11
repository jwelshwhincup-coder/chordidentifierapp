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
    }
}
