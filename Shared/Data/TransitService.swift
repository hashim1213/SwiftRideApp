import Foundation
import CoreLocation

/// One façade over every data source. Views and view models only talk to this.
struct TransitService {
    static let shared = TransitService()
    private let store = StaticStore.shared
    private let rt = RealtimeCache.shared

    // MARK: Stops

    func stops(near location: CLLocation, radius: CLLocationDistance, agencies: [Agency]? = nil) async -> [(TransitStop, CLLocationDistance)] {
        let list = agencies ?? Catalog.agencies(near: location.coordinate)
        return await withTaskGroup(of: [(TransitStop, CLLocationDistance)].self) { group in
            for agency in list {
                group.addTask {
                    if agency.source == .winnipeg {
                        return (try? await Winnipeg.stops(near: location, radius: radius)) ?? []
                    }
                    guard let data = await store.data(for: agency) else { return [] }
                    return data.stops(near: location, radius: radius)
                }
            }
            var all: [(TransitStop, CLLocationDistance)] = []
            for await part in group { all += part }
            return all.sorted { $0.1 < $1.1 }
        }
    }

    func search(_ query: String, near coordinate: CLLocationCoordinate2D, cityIDs: [String]) async -> [TransitStop] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        var agencyIDs = Set(Catalog.agencies(near: coordinate).map(\.id))
        for id in cityIDs { Catalog.city(id)?.agencyIDs.forEach { agencyIDs.insert($0) } }
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let terms = q.lowercased().split(separator: " ").map(String.init)
        var results: [TransitStop] = []
        for id in agencyIDs {
            guard let agency = Catalog.agency(id) else { continue }
            if agency.source == .winnipeg {
                if let n = Int(q), let s = try? await Winnipeg.stop(number: n) { results.append(s) }
                continue
            }
            guard let data = await store.data(for: agency) else { continue }
            if let exact = data.stopByCode[q] ?? data.stopByID[q] { results.append(exact) }
            results += data.stops.filter { s in
                let n = s.name.lowercased()
                return terms.allSatisfy { n.contains($0) }
            }.prefix(300)
        }
        var seen = Set<String>()
        return results.filter { seen.insert($0.id).inserted }
            .sorted { ($0.location.distance(from: here)) < ($1.location.distance(from: here)) }
            .prefix(60).map { $0 }
    }

    func routes(for stop: TransitStop) async -> [TransitRoute] {
        guard let agency = Catalog.agency(stop.agencyID), let data = await store.data(for: agency) else { return [] }
        return data.routes(for: stop)
    }

    // MARK: Departures

    func departures(for stop: TransitStop) async throws -> [Departure] {
        guard let agency = Catalog.agency(stop.agencyID) else { return [] }
        let list: [Departure]
        switch agency.source {
        case .winnipeg: list = try await Winnipeg.departures(stop: stop)
        case .ttc: list = try await TTC.departures(stop: stop, data: await store.data(for: agency))
        case .metrolinx: list = try await GO.departures(stop: stop, data: await store.data(for: agency))
        case .gtfsRealtime:
            let live = (try? await gtfsDepartures(stop: stop, agency: agency)) ?? []
            if live.isEmpty && agency.umoFallback {
                list = (try? await TTC.departures(stop: stop, data: await store.data(for: agency))) ?? []
            } else {
                list = live
            }
        }
        let cutoff = Date().addingTimeInterval(-45)
        return list.filter { $0.time >= cutoff }.sorted { $0.time < $1.time }
    }

    private func gtfsDepartures(stop: TransitStop, agency: Agency) async throws -> [Departure] {
        guard let data = await store.data(for: agency) else { throw TransitError.unavailable }
        let index = try await rt.tripIndex(for: agency)
        let arrivals = index.byStop[stop.stopID] ?? []
        return arrivals.compactMap { a -> Departure? in
            // A trip that ends at this stop isn't something you can board here.
            if a.lastStopID == stop.stopID { return nil }
            guard let route = a.routeID.flatMap({ data.routeByID[$0] }) ?? data.route(forTrip: a.tripID) else { return nil }
            let headsign = data.headsign(forTrip: a.tripID)
                ?? a.lastStopID.flatMap { data.headsign(route: route, lastStopID: $0) }
                ?? a.vehicleLabel.flatMap(Self.cleanLabel)
                ?? a.lastStopID.flatMap { data.stopByID[$0]?.name.asHeadsign }
                ?? route.longName
            return Departure(id: "\(a.tripID)@\(stop.stopID)", route: route, headsign: headsign,
                             time: Date(timeIntervalSince1970: TimeInterval(a.time)), isRealtime: true,
                             vehicleID: a.vehicleID, isCancelled: a.cancelled)
        }
    }

    /// "UP - Pearson Airport" → "Pearson Airport"
    private static func cleanLabel(_ s: String) -> String? {
        let parts = s.components(separatedBy: " - ")
        let out = (parts.count > 1 ? parts.dropFirst().joined(separator: " - ") : s).trimmingCharacters(in: .whitespaces)
        return out.count > 2 && Int(out) == nil ? out : nil
    }

    // MARK: Alerts

    func alerts(for agencies: [Agency]) async -> [ServiceAlert] {
        await withTaskGroup(of: [ServiceAlert].self) { group in
            for agency in agencies {
                group.addTask {
                    switch agency.source {
                    case .winnipeg: return (try? await Winnipeg.alerts()) ?? []
                    case .metrolinx: return (try? await GO.alerts(data: await store.data(for: agency))) ?? []
                    case .ttc, .gtfsRealtime:
                        let raw = (try? await rt.alerts(for: agency)) ?? []
                        return raw.compactMap { Self.convert($0, agency: agency) }
                    }
                }
            }
            var all: [ServiceAlert] = []
            for await part in group { all += part }
            return all.sorted { ($0.severity, $0.start ?? .distantPast) > ($1.severity, $1.start ?? .distantPast) }
        }
    }

    private static func convert(_ a: GTFSRT.Alert, agency: Agency) -> ServiceAlert? {
        let now = Int64(Date().timeIntervalSince1970)
        if let end = a.end, end > 0, end < now { return nil }
        if let start = a.start, start > now + 3 * 86_400 { return nil }
        let title = a.header.strippingHTML
        let body = a.description.strippingHTML
        guard !(title.isEmpty && body.isEmpty) else { return nil }
        let severity: ServiceAlert.Severity
        switch a.effect ?? 0 {
        case 1, 3: severity = .severe
        case 2, 4, 6, 9: severity = .warning
        default: severity = .info
        }
        return ServiceAlert(id: "\(agency.id):\(a.id)", agencyID: agency.id,
                            title: title.isEmpty ? String(body.prefix(90)) : title, body: body == title ? "" : body,
                            routeIDs: a.routeIDs, stopIDs: a.stopIDs,
                            start: a.start.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                            end: a.end.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil },
                            url: a.url.flatMap(URL.init(string:)), severity: severity, category: nil)
    }

    // MARK: Live vehicles

    func vehicles(for agency: Agency, routeIDs: Set<String>? = nil) async -> [LiveVehicle] {
        if agency.source == .metrolinx { return (try? await GO.liveTrains()) ?? [] }
        guard agency.source != .winnipeg else { return [] }
        let raw = (try? await rt.vehicles(for: agency)) ?? []
        let data = await store.data(for: agency)
        return raw.compactMap { v in
            let route = v.routeID ?? v.tripID.flatMap { data?.route(forTrip: $0)?.routeID }
            if let routeIDs, let route, !routeIDs.contains(route) { return nil }
            if routeIDs != nil && route == nil { return nil }
            return LiveVehicle(id: "\(agency.id):\(v.id)", agencyID: agency.id, routeID: route, label: v.label ?? v.id,
                               coordinate: .init(latitude: v.lat, longitude: v.lon), bearing: v.bearing, delaySeconds: nil)
        }
    }
}
