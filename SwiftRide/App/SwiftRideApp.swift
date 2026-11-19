import SwiftUI

@main
struct SwiftRideApp: App {
    init() {
        Prefs.register()
        _ = Connectivity.shared // start watching the network early
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
