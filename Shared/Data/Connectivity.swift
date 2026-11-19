import Foundation
import Network
import Observation

/// Tracks whether the device can reach the internet, so the UI can say "showing scheduled times".
@MainActor @Observable
final class Connectivity {
    static let shared = Connectivity()
    private(set) var isOnline = true
    private(set) var isConstrained = false   // Low Data Mode or a weak/expensive link
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let constrained = path.isConstrained
            Network.isOffline = !online
            Task { @MainActor in
                self?.isOnline = online
                self?.isConstrained = constrained
            }
        }
        monitor.start(queue: DispatchQueue(label: "SwiftRide.connectivity"))
    }
}
