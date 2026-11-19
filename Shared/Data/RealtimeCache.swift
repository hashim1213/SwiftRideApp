import Foundation

/// Fetches whole-network GTFS-RT feeds once and shares them across every stop that needs them.
actor RealtimeCache {
    static let shared = RealtimeCache()

    struct Arrival {
        let tripID: String
        let routeID: String?
        let vehicleID: String?
        let vehicleLabel: String?
        let time: Int64
        let lastStopID: String?
        let cancelled: Bool
    }

    /// One live trip with its remaining stops in order (used by the trip planner).
    struct LiveTrip {
        let tripID: String
        let routeID: String?
        let vehicleLabel: String?
        let stops: [(stopID: String, time: Int64)]
        /// Set for timetable trips (live trips get theirs from the static data).
        var headsign: String? = nil
    }

    struct TripIndex {
        let fetchedAt: Date
        let byStop: [String: [Arrival]]
        let trips: [String: LiveTrip]
    }

    private struct Entry<T> { let at: Date; let value: T }

    private var trips: [String: Entry<TripIndex>] = [:]
    private var alerts: [String: Entry<[GTFSRT.Alert]>] = [:]
    private var vehicles: [String: Entry<[GTFSRT.Vehicle]>] = [:]
    private var inflight: [String: Task<GTFSRT.Feed, Error>] = [:]

    private func feed(_ url: URL, format: Agency.FeedFormat) async throws -> GTFSRT.Feed {
        let key = url.absoluteString
        if let t = inflight[key] { return try await t.value }
        let task = Task.detached(priority: .userInitiated) { () throws -> GTFSRT.Feed in
            // Some agency servers hiccup (redirects, truncated downloads) — one retry smooths that over.
            var lastError: Error = TransitError.decoding
            for attempt in 0..<2 {
                if attempt > 0 { try? await Task.sleep(for: .milliseconds(600)) }
                do {
                    let data = try await Network.data(url)
                    return format == .json ? try GTFSRT.decodeJSON(data) : try GTFSRT.decode(data)
                } catch let e as TransitError where e == .offline {
                    throw e
                } catch {
                    lastError = error is GTFSRT.DecodeError ? TransitError.decoding : error
                }
            }
            throw lastError
        }
        inflight[key] = task
        defer { inflight[key] = nil }
        return try await task.value
    }

    func tripIndex(for agency: Agency, maxAge: TimeInterval = 30) async throws -> TripIndex {
        if let e = trips[agency.id], Date().timeIntervalSince(e.at) < maxAge { return e.value }
        guard let url = agency.tripUpdates else { throw TransitError.unavailable }
        var f: GTFSRT.Feed
        do {
            f = try await feed(url, format: agency.feedFormat)
        } catch {
            // Serve slightly stale data rather than nothing.
            if let e = trips[agency.id], Date().timeIntervalSince(e.at) < 300 { return e.value }
            throw error
        }
        for extra in agency.extraTripUpdates {
            if let more = try? await feed(extra, format: agency.feedFormat) { f.tripUpdates += more.tripUpdates }
        }
        let now = Int64(Date().timeIntervalSince1970)
        let index = await Task.detached(priority: .userInitiated) { () -> TripIndex in
            var byStop: [String: [Arrival]] = [:]
            var liveTrips: [String: LiveTrip] = [:]
            for tu in f.tripUpdates {
                let last = tu.stopTimes.last?.stopID
                var seq: [(stopID: String, time: Int64)] = []
                for st in tu.stopTimes where !st.skipped && st.time >= now - 60 && st.time <= now + 4 * 3600 {
                    byStop[st.stopID, default: []].append(Arrival(tripID: tu.tripID, routeID: tu.routeID, vehicleID: tu.vehicleID,
                                                                  vehicleLabel: tu.vehicleLabel, time: st.time, lastStopID: last,
                                                                  cancelled: tu.cancelled))
                    seq.append((st.stopID, st.time))
                }
                if !tu.cancelled && seq.count > 1 {
                    liveTrips[tu.tripID] = LiveTrip(tripID: tu.tripID, routeID: tu.routeID, vehicleLabel: tu.vehicleLabel, stops: seq)
                }
            }
            return TripIndex(fetchedAt: Date(), byStop: byStop, trips: liveTrips)
        }.value
        trips[agency.id] = Entry(at: Date(), value: index)
        return index
    }

    func alerts(for agency: Agency, maxAge: TimeInterval = 180) async throws -> [GTFSRT.Alert] {
        if let e = alerts[agency.id], Date().timeIntervalSince(e.at) < maxAge { return e.value }
        guard let url = agency.alerts else { return [] }
        let a = try await feed(url, format: agency.feedFormat).alerts
        alerts[agency.id] = Entry(at: Date(), value: a)
        return a
    }

    func vehicles(for agency: Agency, maxAge: TimeInterval = 15) async throws -> [GTFSRT.Vehicle] {
        if let e = vehicles[agency.id], Date().timeIntervalSince(e.at) < maxAge { return e.value }
        guard let url = agency.vehicles else { return [] }
        let v = try await feed(url, format: agency.feedFormat).vehicles
        vehicles[agency.id] = Entry(at: Date(), value: v)
        return v
    }
}
