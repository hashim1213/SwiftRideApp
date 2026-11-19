import Foundation
import CoreLocation
import SwiftUI

/// Stops and routes for one agency, loaded from the bundled `TransitData/<id>.json` file
/// produced by `Tools/build_transit_data.py` from the agency's public GTFS feed.
final class AgencyData: @unchecked Sendable {
    let agency: Agency
    let routes: [TransitRoute]
    let routeByID: [String: TransitRoute]
    let routesByShortName: [String: TransitRoute]
    let stops: [TransitStop]
    let stopByID: [String: TransitStop]
    let stopByCode: [String: TransitStop]
    /// trip_id → (route index, headsign index), only for feeds whose realtime trips lack route_id.
    let grid: StopGrid
    private let trips: [String: [Int]]
    private let routeIndex: [String: Int]
    /// "routeIndex|terminalStopID" → headsign, from the static schedule.
    private let terminals: [String: String]
    private let headsigns: [String]

    init(agency: Agency, json: [String: Any]) {
        self.agency = agency
        let rawRoutes = json["routes"] as? [[Any]] ?? []
        let routes: [TransitRoute] = rawRoutes.map { r in
            let color = agency.ignoreRouteColors ? agency.brandHex : (Color.tamedHex(r[3] as? String ?? "").nilIfEmpty ?? agency.brandHex)
            return TransitRoute(agencyID: agency.id, routeID: r[0] as? String ?? "", shortName: r[1] as? String ?? "",
                                longName: (r[2] as? String ?? "").transitCased, colorHex: color,
                                textColorHex: agency.ignoreRouteColors ? "FFFFFF" : (r[4] as? String ?? ""),
                                mode: TransitMode(gtfsType: r[5] as? Int ?? 3))
        }
        self.routes = routes
        routeByID = Dictionary(routes.map { ($0.routeID, $0) }, uniquingKeysWith: { a, _ in a })
        routesByShortName = Dictionary(routes.map { ($0.shortName.trimmingLeadingZeros.uppercased(), $0) }, uniquingKeysWith: { a, _ in a })

        let rawStops = json["stops"] as? [[Any]] ?? []
        let stops: [TransitStop] = rawStops.compactMap { s in
            guard let id = s[0] as? String, let lat = s[3] as? Double, let lon = s[4] as? Double else { return nil }
            let served = (s[5] as? [Int] ?? []).compactMap { $0 < routes.count ? routes[$0] : nil }
            let mode = served.map(\.mode).min { TransitRoute.modeRank($0) < TransitRoute.modeRank($1) }
            return TransitStop(agencyID: agency.id, stopID: id, code: s[1] as? String ?? "", name: (s[2] as? String ?? "").transitCased,
                               latitude: lat, longitude: lon, routeIDs: served.map(\.routeID),
                               mode: mode ?? (agency.source == .metrolinx || agency.id == "up" ? .rail : .bus))
        }
        self.stops = stops
        stopByID = Dictionary(stops.map { ($0.stopID, $0) }, uniquingKeysWith: { a, _ in a })
        stopByCode = Dictionary(stops.map { ($0.displayCode, $0) }, uniquingKeysWith: { a, _ in a })
        grid = StopGrid(stops)
        routeIndex = Dictionary(routes.enumerated().map { ($1.routeID, $0) }, uniquingKeysWith: { a, _ in a })
        terminals = json["terminals"] as? [String: String] ?? [:]
        trips = json["trips"] as? [String: [Int]] ?? [:]
        headsigns = json["headsigns"] as? [String] ?? []
    }

    func route(forTrip tripID: String) -> TransitRoute? {
        guard let t = trips[tripID], let i = t.first, i >= 0, i < routes.count else { return nil }
        return routes[i]
    }

    func headsign(forTrip tripID: String) -> String? {
        guard let t = trips[tripID], t.count > 1, t[1] < headsigns.count else { return nil }
        return headsigns[t[1]].nilIfEmpty?.transitCased
    }

    /// Headsign for a trip on `route` that ends at `lastStopID` ("Dufferin Gate" rather than the last stop's street name).
    func headsign(route: TransitRoute, lastStopID: String) -> String? {
        guard let i = routeIndex[route.routeID] else { return nil }
        guard let raw = terminals["\(i)|\(lastStopID)"]?.nilIfEmpty else { return nil }
        // TTC style: "West - 54 Lawrence East towards Don Valley Station" → "Don Valley Station"
        if raw.localizedCaseInsensitiveContains("towards ") { return TTC.headsign(from: raw) ?? raw }
        return raw.transitCased
    }

    func routes(for stop: TransitStop) -> [TransitRoute] {
        // Feeds like GO list the same line once per schedule period; show each badge once.
        var seen = Set<String>()
        return stop.routeIDs.compactMap { routeByID[$0] }
            .filter { seen.insert("\($0.badgeText)|\($0.mode)").inserted }
            .sorted(by: TransitRoute.naturalOrder)
    }

    func stops(near location: CLLocation, radius: CLLocationDistance) -> [(TransitStop, CLLocationDistance)] {
        // Cheap bounding-box prefilter before the real distance check.
        let dLat = radius / 111_000
        let dLon = radius / (111_000 * max(0.2, cos(location.coordinate.latitude * .pi / 180)))
        let lat = location.coordinate.latitude, lon = location.coordinate.longitude
        return stops.lazy
            .filter { abs($0.latitude - lat) <= dLat && abs($0.longitude - lon) <= dLon }
            .map { ($0, $0.location.distance(from: location)) }
            .filter { $0.1 <= radius }
            .sorted { $0.1 < $1.1 }
    }

    func stops(in region: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)) -> [TransitStop] {
        stops.filter { $0.latitude >= region.minLat && $0.latitude <= region.maxLat && $0.longitude >= region.minLon && $0.longitude <= region.maxLon }
    }
}

actor StaticStore {
    static let shared = StaticStore()
    private var cache: [String: AgencyData] = [:]
    private var loading: [String: Task<AgencyData?, Never>] = [:]

    func data(for agency: Agency) async -> AgencyData? {
        guard agency.hasBundledStops else { return nil }
        if let d = cache[agency.id] { return d }
        if let t = loading[agency.id] { return await t.value }
        let task = Task.detached(priority: .userInitiated) { () -> AgencyData? in
            guard let url = Bundle.appMain.url(forResource: agency.id, withExtension: "json"),
                  let raw = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return nil }
            return AgencyData(agency: agency, json: json)
        }
        loading[agency.id] = task
        let d = await task.value
        cache[agency.id] = d
        loading[agency.id] = nil
        return d
    }

    func cached(_ agencyID: String) -> AgencyData? { cache[agencyID] }
}

extension TransitRoute {
    static func modeRank(_ m: TransitMode) -> Int { [.subway: 0, .rail: 1, .tram: 2, .ferry: 3, .bus: 4][m] ?? 5 }

    /// Sorts "2" before "10" and letters after numbers, like a printed route map.
    static func naturalOrder(_ a: TransitRoute, _ b: TransitRoute) -> Bool {
        if a.mode != b.mode { return modeRank(a.mode) < modeRank(b.mode) }
        return a.badgeText.localizedStandardCompare(b.badgeText) == .orderedAscending
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
