import Foundation
import CoreLocation
import SwiftUI

// MARK: - Transit mode

enum TransitMode: Int, Codable, CaseIterable, Hashable {
    case tram = 0, subway = 1, rail = 2, bus = 3, ferry = 4

    init(gtfsType: Int) {
        switch gtfsType {
        case 0, 5, 12: self = .tram
        case 1: self = .subway
        case 2, 100...117: self = .rail
        case 4, 1200: self = .ferry
        default: self = .bus
        }
    }

    var symbol: String {
        switch self {
        case .tram: return "tram.fill"
        case .subway: return "tram.tunnel.fill"
        case .rail: return "train.side.front.car"
        case .bus: return "bus.fill"
        case .ferry: return "ferry.fill"
        }
    }

    var label: String {
        switch self {
        case .tram: return "Streetcar & LRT"
        case .subway: return "Subway"
        case .rail: return "Train"
        case .bus: return "Bus"
        case .ferry: return "Ferry"
        }
    }
}

// MARK: - Route

struct TransitRoute: Hashable, Codable, Identifiable {
    let agencyID: String
    let routeID: String
    let shortName: String
    let longName: String
    let colorHex: String
    let textColorHex: String
    let mode: TransitMode

    var id: String { "\(agencyID):\(routeID)" }

    /// What goes inside the badge, e.g. "504", "LW", "BLUE".
    var badgeText: String {
        if !shortName.isEmpty { return shortName.trimmingLeadingZeros }
        if let first = longName.split(separator: " ").first { return String(first.prefix(4)) }
        return routeID
    }

    var color: Color { Color(hex: colorHex) ?? .gray }
    var textColor: Color {
        if let c = Color(hex: textColorHex), textColorHex.uppercased() != colorHex.uppercased() { return c }
        return (Color.luminance(hex: colorHex) ?? 0) > 0.6 ? .black : .white
    }
}

// MARK: - Stop

struct TransitStop: Hashable, Codable, Identifiable {
    let agencyID: String
    let stopID: String
    let code: String
    let name: String
    let latitude: Double
    let longitude: Double
    var routeIDs: [String]
    /// Main mode served here (optional so stops saved by older versions still decode).
    var mode: TransitMode? = nil

    var id: String { "\(agencyID):\(stopID)" }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    /// The number riders see on the stop pole.
    var displayCode: String { code.isEmpty ? stopID : code }

    func distance(from location: CLLocation?) -> CLLocationDistance? {
        guard let location else { return nil }
        return self.location.distance(from: location)
    }
}

// MARK: - Departure

struct Departure: Identifiable, Hashable {
    let id: String
    let route: TransitRoute
    let headsign: String
    let time: Date
    let scheduledTime: Date?
    let isRealtime: Bool
    let platform: String?
    let vehicleID: String?
    let isCancelled: Bool

    init(id: String = UUID().uuidString, route: TransitRoute, headsign: String, time: Date,
         scheduledTime: Date? = nil, isRealtime: Bool, platform: String? = nil,
         vehicleID: String? = nil, isCancelled: Bool = false) {
        self.id = id
        self.route = route
        self.headsign = headsign
        self.time = time
        self.scheduledTime = scheduledTime
        self.isRealtime = isRealtime
        self.platform = platform
        self.vehicleID = vehicleID
        self.isCancelled = isCancelled
    }

    /// Seconds late (positive) or early (negative), when both times are known.
    var delaySeconds: Int? {
        guard let scheduledTime else { return nil }
        return Int(time.timeIntervalSince(scheduledTime))
    }

    var minutesAway: Int { max(0, Int((time.timeIntervalSinceNow / 60).rounded(.down))) }

    /// Groups departures that are "the same line going the same way".
    var lineKey: String { "\(route.id)|\(headsign.lowercased())" }
}

// MARK: - Alerts

struct ServiceAlert: Identifiable, Hashable {
    enum Severity: Int, Comparable { case info = 0, warning = 1, severe = 2
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    let id: String
    let agencyID: String
    let title: String
    let body: String
    let routeIDs: [String]
    let stopIDs: [String]
    let start: Date?
    let end: Date?
    let url: URL?
    let severity: Severity
    let category: String?

    func affects(stop: TransitStop) -> Bool {
        guard stop.agencyID == agencyID else { return false }
        if stopIDs.contains(stop.stopID) || stopIDs.contains(stop.code) { return true }
        return routeIDs.contains { stop.routeIDs.contains($0) }
    }
}

// MARK: - Live vehicles

struct LiveVehicle: Identifiable, Hashable {
    let id: String
    let agencyID: String
    let routeID: String?
    let label: String
    let coordinate: CLLocationCoordinate2D
    let bearing: Double?
    let delaySeconds: Int?

    static func == (a: LiveVehicle, b: LiveVehicle) -> Bool { a.id == b.id && a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude }
    func hash(into h: inout Hasher) { h.combine(id) }
}

// MARK: - Nearby line (one card on the home sheet)

struct NearbyLine: Identifiable, Hashable {
    let route: TransitRoute
    let headsign: String
    let stop: TransitStop
    let distance: CLLocationDistance?
    let departures: [Departure]

    var id: String { "\(route.id)|\(headsign.lowercased())" }
    var next: Departure? { departures.first }
}

// MARK: - Helpers

extension String {
    var trimmingLeadingZeros: String {
        let t = drop(while: { $0 == "0" })
        return t.isEmpty ? self : String(t)
    }

    /// "LAWRENCE AVE EAST" → "Lawrence Ave East" for agencies that publish in all caps.
    var transitCased: String {
        let letters = filter(\.isLetter)
        guard !letters.isEmpty, letters == letters.uppercased(), letters.count > 3 else { return self }
        return capitalized
            .replacingOccurrences(of: " At ", with: " at ")
            .replacingOccurrences(of: " And ", with: " & ")
            .replacingOccurrences(of: "Go ", with: "GO ")
    }
}

extension CLLocationDistance {
    var walkingMinutes: Int { Swift.max(1, Int((self * 1.3 / 80).rounded())) }

    var shortDistance: String {
        if self < 1000 { return "\(Int((self / 10).rounded() * 10)) m" }
        return String(format: "%.1f km", self / 1000)
    }
}
