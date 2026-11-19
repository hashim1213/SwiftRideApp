import Foundation
import CoreLocation
import Observation
import SwiftUI

enum ModeFilter: String, CaseIterable, Identifiable {
    case all, bus, rail, rapid
    var id: String { rawValue }
    var title: String {
        switch self { case .all: "All"; case .bus: "Bus"; case .rail: "Train"; case .rapid: "Subway & LRT" }
    }
    var symbol: String {
        switch self { case .all: "square.grid.2x2.fill"; case .bus: "bus.fill"; case .rail: "train.side.front.car"; case .rapid: "tram.fill" }
    }
    func matches(_ m: TransitMode) -> Bool {
        switch self {
        case .all: true
        case .bus: m == .bus || m == .ferry
        case .rail: m == .rail
        case .rapid: m == .subway || m == .tram
        }
    }
}

@MainActor @Observable
final class NearbyModel {
    enum Phase: Equatable { case idle, loading, loaded, empty, outOfArea, failed(String) }
    enum Origin: Equatable { case user, map, city(String) }

    // Inputs
    private(set) var center: CLLocationCoordinate2D?
    private(set) var origin: Origin = .user
    var filter: ModeFilter = .all
    var agencyFilter: String? = nil

    // Outputs
    private(set) var phase: Phase = .idle
    private(set) var lines: [NearbyLine] = []
    private(set) var stops: [(stop: TransitStop, distance: CLLocationDistance)] = []
    private(set) var alerts: [ServiceAlert] = []
    private(set) var vehicles: [LiveVehicle] = []
    private(set) var updatedAt: Date?
    private(set) var areaName: String = "Nearby"
    var focusedStop: TransitStop?

    private let service = TransitService.shared
    private var loadTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    var agencies: [Agency] { center.map { Catalog.agencies(near: $0) } ?? [] }

    var visibleLines: [NearbyLine] {
        lines.filter { filter.matches($0.route.mode) && (agencyFilter == nil || $0.route.agencyID == agencyFilter) }
    }

    /// Agencies that actually have lines in the current results — drives the agency chips.
    var agenciesInResults: [Agency] {
        var seen = Set<String>()
        return lines.compactMap { seen.insert($0.route.agencyID).inserted ? Catalog.agency($0.route.agencyID) : nil }
    }

    var modesInResults: Set<ModeFilter> {
        Set(ModeFilter.allCases.filter { f in f != .all && lines.contains { f.matches($0.route.mode) } })
    }

    /// Alerts that touch a line or stop in the current results (network-wide ones only if severe).
    var nearbyAlerts: [ServiceAlert] {
        let routeKeys = Set(lines.map { "\($0.route.agencyID):\($0.route.routeID)" })
        let stopKeys = Set(stops.prefix(60).flatMap { [ "\($0.stop.agencyID):\($0.stop.stopID)", "\($0.stop.agencyID):\($0.stop.code)" ] })
        return alerts.filter { a in
            if a.routeIDs.isEmpty && a.stopIDs.isEmpty { return a.severity == .severe }
            return a.routeIDs.contains { routeKeys.contains("\(a.agencyID):\($0)") }
                || a.stopIDs.contains { stopKeys.contains("\(a.agencyID):\($0)") }
        }
    }

    var importantAlerts: [ServiceAlert] { nearbyAlerts.filter { $0.severity >= .warning } }

    // MARK: Updating the search centre

    func useUserLocation(_ location: CLLocation?, force: Bool = false) {
        guard let location else { return }
        if !force, origin == .user, let c = center,
           CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: location) < 75, phase == .loaded { return }
        origin = .user
        setCenter(location.coordinate)
    }

    func search(at coordinate: CLLocationCoordinate2D) {
        origin = .map
        setCenter(coordinate)
    }

    func show(city: City, remember: Bool = true) {
        origin = .city(city.id)
        if remember { UserDefaults.standard.set(city.id, forKey: Prefs.manualCityID) }
        setCenter(city.coordinate)
    }

    private func setCenter(_ c: CLLocationCoordinate2D) {
        center = c
        let cities = Catalog.cities(near: c)
        areaName = cities.first?.name ?? "Nearby"
        agencyFilter = nil
        reload(showSpinner: true)
    }

    // MARK: Loading

    func reload(showSpinner: Bool = false) {
        guard let center else { return }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.load(center: center, showSpinner: showSpinner)
        }
    }

    func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.reload()
            }
        }
    }

    func stopTicking() { tickTask?.cancel() }

    private func load(center: CLLocationCoordinate2D, showSpinner: Bool) async {
        let agencies = Catalog.agencies(near: center)
        guard !agencies.isEmpty else {
            lines = []; stops = []; alerts = []; vehicles = []
            phase = .outOfArea
            return
        }
        if showSpinner || lines.isEmpty { phase = .loading }
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let radius = UserDefaults.standard.double(forKey: Prefs.radius)

        async let alertsTask = service.alerts(for: agencies)
        var found = await service.stops(near: here, radius: radius, agencies: agencies)
        if found.isEmpty {
            // Nothing within the preferred radius — widen once so the sheet isn't empty in the suburbs.
            found = await service.stops(near: here, radius: max(radius * 2.5, 1500), agencies: agencies)
        }
        if Task.isCancelled { return }
        stops = found.map { (stop: $0.0, distance: $0.1) }

        let picked = Self.pickStopsToQuery(found)
        let results = await withTaskGroup(of: (TransitStop, CLLocationDistance, [Departure])?.self) { group in
            for (stop, d) in picked {
                group.addTask { [service] in
                    guard let deps = try? await service.departures(for: stop) else { return nil }
                    return (stop, d, deps)
                }
            }
            var out: [(TransitStop, CLLocationDistance, [Departure])] = []
            for await r in group { if let r { out.append(r) } }
            return out
        }
        if Task.isCancelled { return }

        lines = Self.group(results)
        alerts = await alertsTask
        updatedAt = Date()
        phase = lines.isEmpty ? (found.isEmpty ? .empty : .loaded) : .loaded
        if lines.isEmpty && found.isEmpty { phase = .empty }

        if UserDefaults.standard.bool(forKey: Prefs.showVehicles) { await loadVehicles(agencies: agencies) }
    }

    private func loadVehicles(agencies: [Agency]) async {
        let routeIDs = Set(lines.map(\.route.routeID))
        let list = await withTaskGroup(of: [LiveVehicle].self) { group in
            for a in agencies {
                group.addTask { [service] in
                    // GO trains are shown network-wide; other agencies only for routes near you.
                    await service.vehicles(for: a, routeIDs: a.source == .metrolinx ? nil : routeIDs)
                }
            }
            var all: [LiveVehicle] = []
            for await v in group { all += v }
            return all
        }
        vehicles = Array(list.prefix(400))
    }

    /// Feeds that cost a request per stop get fewer stops; whole-network feeds can afford many.
    private static func pickStopsToQuery(_ found: [(TransitStop, CLLocationDistance)]) -> [(TransitStop, CLLocationDistance)] {
        var counts: [String: Int] = [:]
        return found.filter { stop, _ in
            let limit: Int
            switch Catalog.agency(stop.agencyID)?.source {
            case .gtfsRealtime: limit = 30
            case .ttc: limit = 10
            case .winnipeg: limit = 10
            case .metrolinx: limit = 3
            case nil: limit = 0
            }
            counts[stop.agencyID, default: 0] += 1
            return counts[stop.agencyID]! <= limit
        }
    }

    /// One card per route + direction, attached to the closest stop that serves it.
    private static func group(_ results: [(TransitStop, CLLocationDistance, [Departure])]) -> [NearbyLine] {
        var best: [String: NearbyLine] = [:]
        for (stop, distance, deps) in results {
            let byLine = Dictionary(grouping: deps.filter { !$0.isCancelled }, by: \.lineKey)
            for (key, list) in byLine {
                guard let first = list.first else { continue }
                let line = NearbyLine(route: first.route, headsign: first.headsign, stop: stop, distance: distance,
                                      departures: Array(list.sorted { $0.time < $1.time }.prefix(4)))
                if let existing = best[key], (existing.distance ?? .infinity) <= distance { continue }
                best[key] = line
            }
        }
        let soon = Date().addingTimeInterval(45 * 60)
        return best.values.sorted { a, b in
            // Lines leaving in the next 45 min first, then walk distance in ~2 minute bands,
            // then route number, then soonest departure.
            let sa = (a.next?.time ?? .distantFuture) <= soon, sb = (b.next?.time ?? .distantFuture) <= soon
            if sa != sb { return sa }
            let da = Int((a.distance ?? 0) / 160), db = Int((b.distance ?? 0) / 160)
            if da != db { return da < db }
            if a.route.id != b.route.id { return TransitRoute.naturalOrder(a.route, b.route) }
            return (a.next?.time ?? .distantFuture) < (b.next?.time ?? .distantFuture)
        }
    }
}
