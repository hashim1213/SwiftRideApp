import Foundation

/// An agency's full timetable, loaded from `TransitData/<id>.sched.json` (built by Tools/build_schedules.py).
/// Used to plan trips and show departures for any day and time, beyond the reach of live feeds.
final class AgencySchedule: @unchecked Sendable {
    struct Service {
        let days: Int          // bit 0 = Monday … bit 6 = Sunday
        let start: Int, end: Int // yyyymmdd
        let added: Set<Int>
        let removed: Set<Int>

        func runs(on ymd: Int, weekday: Int) -> Bool {
            if removed.contains(ymd) { return false }
            if added.contains(ymd) { return true }
            return ymd >= start && ymd <= end && (days >> weekday) & 1 == 1
        }
    }

    struct Trip {
        let route: Int32, service: Int32, headsign: Int32, pattern: Int32, profile: Int32
        let start: Int32 // minutes after midnight of the service day (can exceed 1440)
    }

    let timeZone: TimeZone
    let services: [Service]
    let headsigns: [String]
    let patterns: [[Int32]]
    let profiles: [[Int16]]
    let trips: [Trip]       // sorted by start
    let maxDuration: Int    // longest trip in minutes, to know how far back to look

    init?(json: [String: Any], timeZone: TimeZone) {
        guard let rawTrips = json["trips"] as? [[Int]] else { return nil }
        self.timeZone = timeZone
        services = (json["services"] as? [[Any]] ?? []).map { s in
            Service(days: s[1] as? Int ?? 0, start: s[2] as? Int ?? 0, end: s[3] as? Int ?? 0,
                    added: Set(s[4] as? [Int] ?? []), removed: Set(s[5] as? [Int] ?? []))
        }
        headsigns = json["headsigns"] as? [String] ?? []
        patterns = (json["patterns"] as? [[Int]] ?? []).map { $0.map(Int32.init) }
        let profiles = (json["profiles"] as? [[Int]] ?? []).map { $0.map { Int16(clamping: $0) } }
        self.profiles = profiles
        trips = rawTrips.compactMap { t in
            guard t.count == 6 else { return nil }
            return Trip(route: Int32(t[0]), service: Int32(t[1]), headsign: Int32(t[2]), pattern: Int32(t[3]), profile: Int32(t[4]), start: Int32(t[5]))
        }
        maxDuration = profiles.map { Int($0.last ?? 0) }.max() ?? 180
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = timeZone; return c
    }

    /// Every scheduled trip (as a "live trip" the planner understands) that is moving between `from` and `to`.
    func trips(from: Date, to: Date, data: AgencyData) -> [String: RealtimeCache.LiveTrip] {
        let cal = calendar
        var out: [String: RealtimeCache.LiveTrip] = [:]
        // Today's service day plus yesterday's (for trips running past midnight).
        let day0 = cal.startOfDay(for: from)
        for dayOffset in [-1, 0, 1] {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: day0) else { continue }
            let comps = cal.dateComponents([.year, .month, .day, .weekday], from: day)
            let ymd = (comps.year ?? 0) * 10_000 + (comps.month ?? 0) * 100 + (comps.day ?? 0)
            let weekday = ((comps.weekday ?? 1) + 5) % 7 // Calendar: 1 = Sunday → our 6
            let active = services.indices.filter { services[$0].runs(on: ymd, weekday: weekday) }
            guard !active.isEmpty else { continue }
            let activeSet = Set(active.map(Int32.init))
            // GTFS times are measured from "noon minus 12 h", i.e. local midnight except on DST days; close enough.
            let base = day.timeIntervalSince1970
            let fromMin = Int((from.timeIntervalSince1970 - base) / 60), toMin = Int((to.timeIntervalSince1970 - base) / 60)
            guard toMin >= 0, fromMin <= 48 * 60 else { continue }
            let lower = fromMin - maxDuration
            var i = firstIndex(startingAtOrAfter: lower)
            while i < trips.count, Int(trips[i].start) <= toMin {
                let t = trips[i]; i += 1
                guard activeSet.contains(t.service), Int(t.pattern) < patterns.count, Int(t.profile) < profiles.count else { continue }
                let pat = patterns[Int(t.pattern)], prof = profiles[Int(t.profile)]
                guard Int(t.start) + Int(prof.last ?? 0) >= fromMin else { continue }
                var stops: [(stopID: String, time: Int64)] = []
                stops.reserveCapacity(pat.count)
                for (k, sIdx) in pat.enumerated() where Int(sIdx) < data.stops.count && k < prof.count {
                    let m = Int(t.start) + Int(prof[k])
                    guard m >= fromMin - 1, m <= toMin + 240 else { continue }
                    stops.append((data.stops[Int(sIdx)].stopID, Int64(base) + Int64(m) * 60))
                }
                guard stops.count > 1, Int(t.route) < data.routes.count else { continue }
                let id = "s\(ymd):\(i)"
                out[id] = RealtimeCache.LiveTrip(tripID: id, routeID: data.routes[Int(t.route)].routeID,
                                                 vehicleLabel: nil, stops: stops, headsign: headsign(t))
            }
        }
        return out
    }

    private func headsign(_ t: Trip) -> String? {
        guard Int(t.headsign) < headsigns.count, let raw = headsigns[Int(t.headsign)].nilIfEmpty else { return nil }
        if raw.localizedCaseInsensitiveContains("towards ") { return TTC.headsign(from: raw) ?? raw }
        return raw.transitCased
    }

    private func firstIndex(startingAtOrAfter minute: Int) -> Int {
        var lo = 0, hi = trips.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if Int(trips[mid].start) < minute { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

actor ScheduleStore {
    static let shared = ScheduleStore()
    private var cache: [String: AgencySchedule] = [:]
    private var missing: Set<String> = []
    private var loading: [String: Task<AgencySchedule?, Never>] = [:]

    static let timeZones: [String: String] = [
        "calgary": "America/Edmonton", "edmonton": "America/Edmonton", "halifax": "America/Halifax",
        "victoria": "America/Vancouver", "kelowna": "America/Vancouver", "bct46": "America/Vancouver",
        "bct41": "America/Vancouver", "bct13": "America/Vancouver", "wpg": "America/Winnipeg",
    ]

    func schedule(for agency: Agency) async -> AgencySchedule? {
        if let s = cache[agency.id] { return s }
        if missing.contains(agency.id) { return nil }
        if let t = loading[agency.id] { return await t.value }
        let tz = TimeZone(identifier: Self.timeZones[agency.id] ?? "America/Toronto") ?? .current
        let task = Task.detached(priority: .userInitiated) { () -> AgencySchedule? in
            guard let url = Bundle.appMain.url(forResource: "\(agency.id).sched", withExtension: "json"),
                  let raw = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return nil }
            return AgencySchedule(json: json, timeZone: tz)
        }
        loading[agency.id] = task
        let s = await task.value
        loading[agency.id] = nil
        if let s { cache[agency.id] = s } else { missing.insert(agency.id) }
        return s
    }

    /// A trip index (same shape as the live one) built from the timetable for a time window.
    func index(for agency: Agency, from: Date, hours: Double = 3) async -> RealtimeCache.TripIndex? {
        guard let sched = await schedule(for: agency), let data = await StaticStore.shared.data(for: agency) else { return nil }
        let trips = sched.trips(from: from, to: from.addingTimeInterval(hours * 3600), data: data)
        var byStop: [String: [RealtimeCache.Arrival]] = [:]
        for t in trips.values {
            let last = t.stops.last?.stopID
            for s in t.stops {
                byStop[s.stopID, default: []].append(RealtimeCache.Arrival(tripID: t.tripID, routeID: t.routeID, vehicleID: nil,
                                                                           vehicleLabel: t.headsign, time: s.time, lastStopID: last, cancelled: false))
            }
        }
        return RealtimeCache.TripIndex(fetchedAt: .now, byStop: byStop, trips: trips)
    }
}
