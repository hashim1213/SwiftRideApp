import SwiftUI

@main
struct SwiftRideApp: App {
    init() { Prefs.register() }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
