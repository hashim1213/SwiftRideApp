import Foundation

/// Storage shared between the app and its widgets.
enum AppGroup {
    static let id = "group.com.HashimFarooq.SwiftRide"
    static let defaults: UserDefaults = UserDefaults(suiteName: id) ?? .standard

    /// Reads a key from the shared store, falling back to (and migrating) the app's old standard defaults.
    static func data(forKey key: String) -> Data? {
        if let d = defaults.data(forKey: key) { return d }
        if let legacy = UserDefaults.standard.data(forKey: key) {
            defaults.set(legacy, forKey: key)
            return legacy
        }
        return nil
    }

    static let lastLatKey = "lastLocation.lat", lastLonKey = "lastLocation.lon"
}

extension Bundle {
    /// The main app bundle, even when running inside the widget extension
    /// (SwiftRide.app/PlugIns/BusHomeExtension.appex) — bundled transit data lives there.
    static let appMain: Bundle = {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "appex" else { return .main }
        return Bundle(url: url.deletingLastPathComponent().deletingLastPathComponent()) ?? .main
    }()
}
