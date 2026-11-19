import Foundation
import CoreLocation
import SwiftUI
import WidgetKit

// MARK: - Places

/// Something a trip can start or end at.
enum Place: Hashable, Codable, Identifiable {
    case currentLocation
    case stop(TransitStop)
    case point(name: String, subtitle: String?, latitude: Double, longitude: Double)

    var id: String {
        switch self {
        case .currentLocation: return "here"
        case .stop(let s): return "stop:\(s.id)"
        case .point(let n, _, let lat, let lon): return "pt:\(n):\(lat),\(lon)"
        }
    }

    var title: String {
        switch self {
        case .currentLocation: return "Current location"
        case .stop(let s): return s.name
        case .point(let n, _, _, _): return n
        }
    }

    var shortTitle: String {
        switch self {
        case .currentLocation: return "Here"
        case .stop(let s):
            return s.name.replacingOccurrences(of: " GO Station", with: " GO").replacingOccurrences(of: " Station", with: "")
        case .point(let n, _, _, _): return n
        }
    }

    var subtitle: String? {
        switch self {
        case .currentLocation: return nil
        case .stop(let s): return "\(Catalog.agency(s.agencyID)?.shortName ?? "") · #\(s.displayCode)"
        case .point(_, let sub, _, _): return sub
        }
    }

    var symbol: String {
        switch self {
        case .currentLocation: return "location.fill"
        case .stop(let s): return (s.mode ?? .bus).symbol
        case .point: return "mappin.circle.fill"
        }
    }

    func coordinate(current: CLLocationCoordinate2D?) -> CLLocationCoordinate2D? {
        switch self {
        case .currentLocation: return current
        case .stop(let s): return s.coordinate
        case .point(_, _, let lat, let lon): return .init(latitude: lat, longitude: lon)
        }
    }
}

// MARK: - Itineraries

struct WalkLeg: Hashable {
    let fromName: String
    let toName: String
    let distance: CLLocationDistance
    var seconds: TimeInterval { max(60, distance * 1.3 / 1.35) } // street-grid detour ×1.3 at ~1.35 m/s
    var minutes: Int { Int((seconds / 60).rounded()) }
}

/// A stop the vehicle passes on a ride, with its (live or scheduled) time.
struct StopVisit: Hashable {
    let stopID: String
    let name: String
    let time: Date
}

struct RideLeg: Hashable {
    let route: TransitRoute
    let headsign: String
    let from: TransitStop
    let to: TransitStop
    let depart: Date
    let arrive: Date
    var scheduledDepart: Date? = nil
    var isRealtime: Bool
    var platform: String? = nil
    var stopCount: Int? = nil
    var tripID: String? = nil
    /// Every stop from boarding to alighting (inclusive), when the source provides them.
    var visits: [StopVisit] = []

    var delaySeconds: Int? { scheduledDepart.map { Int(depart.timeIntervalSince($0)) } }
}

enum Leg: Hashable {
    case walk(WalkLeg)
    case ride(RideLeg)
}

struct Itinerary: Identifiable, Hashable {
    let legs: [Leg]

    var rides: [RideLeg] { legs.compactMap { if case .ride(let r) = $0 { return r } else { return nil } } }
    var firstRide: RideLeg? { rides.first }
    var transfers: Int { max(0, rides.count - 1) }
    var walkMinutes: Int { legs.reduce(0) { if case .walk(let w) = $1 { return $0 + w.minutes } else { return $0 } } }

    /// When you need to leave (walk to the first stop counted in).
    var leaveAt: Date {
        guard let first = firstRide else { return .now }
        if case .walk(let w)? = legs.first { return first.depart.addingTimeInterval(-w.seconds) }
        return first.depart
    }

    var arriveAt: Date {
        guard let last = rides.last else {
            if case .walk(let w)? = legs.first { return Date().addingTimeInterval(w.seconds) }
            return .now
        }
        if case .walk(let w)? = legs.last { return last.arrive.addingTimeInterval(w.seconds) }
        return last.arrive
    }

    var duration: TimeInterval { arriveAt.timeIntervalSince(leaveAt) }
    var isWalkOnly: Bool { rides.isEmpty }

    var id: String {
        rides.map { "\($0.route.id)@\(Int($0.depart.timeIntervalSince1970 / 60))" }.joined(separator: ">") + (isWalkOnly ? "walk" : "")
    }

    static func == (a: Itinerary, b: Itinerary) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct PlanResult {
    var itineraries: [Itinerary] = []
    var notes: [String] = []
    /// Set when nothing runs soon and the options shown are the next service later on (e.g. first trains tomorrow).
    var nextServiceAt: Date? = nil
}

// MARK: - Saved trips

struct SavedTrip: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var from: Place
    var to: Place
    var createdAt: Date = .now

    var title: String { "\(from.shortTitle) → \(to.shortTitle)" }
    var reversed: SavedTrip { SavedTrip(from: to, to: from) }
}

@MainActor @Observable
final class TripsStore {
    static let shared = TripsStore()
    static let key = "savedTrips.v1"
    private(set) var trips: [SavedTrip] = TripsStore.load()

    nonisolated static func load() -> [SavedTrip] {
        guard let d = AppGroup.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SavedTrip].self, from: d)) ?? []
    }

    func isSaved(from: Place, to: Place) -> Bool { trips.contains { $0.from == from && $0.to == to } }

    func toggle(from: Place, to: Place) {
        if let i = trips.firstIndex(where: { $0.from == from && $0.to == to }) { trips.remove(at: i) }
        else { trips.insert(SavedTrip(from: from, to: to), at: 0) }
        persist()
    }

    /// Saves the reverse direction too (e.g. Milton → Union and Union → Milton).
    func saveReturn(of trip: SavedTrip) {
        guard !isSaved(from: trip.to, to: trip.from) else { return }
        if let i = trips.firstIndex(of: trip) { trips.insert(trip.reversed, at: i + 1) } else { trips.append(trip.reversed) }
        persist()
    }

    func remove(_ trip: SavedTrip) { trips.removeAll { $0.id == trip.id }; persist() }
    func move(from: IndexSet, to: Int) { trips.move(fromOffsets: from, toOffset: to); persist() }

    private func persist() {
        if let d = try? JSONEncoder().encode(trips) { AppGroup.defaults.set(d, forKey: Self.key) }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Planner

/// Plans trips with what each agency publishes:
/// GO via the Metrolinx Journey API (any time, with transfers), GTFS-Realtime agencies from live
/// trip updates (direct and one-transfer, next few hours), TTC direct trips from Umo predictions,
/// and Winnipeg via its own trip planner.
struct TripPlanner {
    static let shared = TripPlanner()
    private let store = StaticStore.shared
    private let rt = RealtimeCache.shared

    private struct Candidate { let stop: TransitStop; let walk: WalkLeg }

    /// "Get me there by 9:00": searches departures in the hours before and keeps the latest ones that arrive in time.
    func plan(from: Place, to: Place, current: CLLocationCoordinate2D?, arriveBy: Date) async -> PlanResult {
        var found: [Itinerary] = []
        var notes: [String] = []
        for hoursBefore in [1.25, 2.5] {
            let start = max(Date(), arriveBy.addingTimeInterval(-hoursBefore * 3600))
            let r = await plan(from: from, to: to, current: current, departAfter: start)
            notes = r.notes
            found += r.itineraries.filter { $0.arriveAt <= arriveBy.addingTimeInterval(60) && ($0.isWalkOnly || $0.leaveAt >= Date().addingTimeInterval(-60)) }
            if found.filter({ !$0.isWalkOnly }).count >= 3 || start <= Date() { break }
        }
        var seen = Set<String>()
        var list = found.filter { seen.insert($0.id).inserted }
            .sorted { a, b in a.leaveAt != b.leaveAt ? a.leaveAt > b.leaveAt : a.transfers < b.transfers }
        // Drop options that leave earlier but don't arrive any earlier than a later-leaving one.
        var kept: [Itinerary] = []
        for it in list where !kept.contains(where: { $0.leaveAt >= it.leaveAt && $0.arriveAt <= it.arriveAt && $0.transfers <= it.transfers && !it.isWalkOnly }) {
            kept.append(it)
        }
        list = Array(kept.prefix(8))
        return PlanResult(itineraries: list, notes: list.isEmpty ? (notes.isEmpty ? ["No trips arrive by then. Try a later time."] : notes) : [])
    }

    func plan(from: Place, to: Place, current: CLLocationCoordinate2D?, departAfter: Date = .now) async -> PlanResult {
        var result = PlanResult()
        guard let o = from.coordinate(current: current), let d = to.coordinate(current: current) else {
            result.notes.append("Turn on location or pick a starting point.")
            return result
        }
        let oLoc = CLLocation(latitude: o.latitude, longitude: o.longitude)
        let dLoc = CLLocation(latitude: d.latitude, longitude: d.longitude)
        let straight = oLoc.distance(from: dLoc)

        var itineraries: [Itinerary] = []
        if straight < 1300 {
            itineraries.append(Itinerary(legs: [.walk(WalkLeg(fromName: from.title, toName: to.title, distance: straight))]))
        }

        async let oCands = candidates(for: from, at: oLoc, name: from.title)
        async let dCands = candidates(for: to, at: dLoc, name: to.title)
        let (origin, dest) = await (oCands, dCands)
        let common = Set(origin.keys).intersection(dest.keys).compactMap(Catalog.agency)

        if common.isEmpty {
            result.notes.append(origin.isEmpty || dest.isEmpty
                ? "No stops near \(origin.isEmpty ? from.title : to.title)."
                : "These places are served by different agencies. SwiftRide plans trips within one agency for now — try Apple Maps for mixed trips.")
        }

        await withTaskGroup(of: [Itinerary].self) { group in
            for agency in common {
                let oc = origin[agency.id] ?? [], dc = dest[agency.id] ?? []
                group.addTask {
                    switch agency.source {
                    case .gtfsRealtime:
                        // Live predictions for the next hour or so; the timetable for later (or when nothing's live).
                        let future = departAfter.timeIntervalSinceNow > 75 * 60
                        if !future {
                            let live = await realtimePlans(agency: agency, origin: oc, dest: dc, after: departAfter, index: nil)
                            if !live.isEmpty { return live }
                            if agency.umoFallback {
                                let umo = await ttcPlans(origin: oc, dest: dc)
                                if !umo.isEmpty { return umo }
                            }
                        }
                        guard let idx = await ScheduleStore.shared.index(for: agency, from: departAfter, hours: 2.5) else { return [] }
                        return await realtimePlans(agency: agency, origin: oc, dest: dc, after: departAfter, index: idx, isRealtime: false)
                    case .metrolinx:
                        let live = await goPlans(origin: oc, dest: dc, after: departAfter)
                        if !live.isEmpty { return live }
                        // Offline (or the API is down): plan from the bundled GO timetable.
                        guard let idx = await ScheduleStore.shared.index(for: agency, from: departAfter, hours: 3) else { return [] }
                        return await realtimePlans(agency: agency, origin: oc, dest: dc, after: departAfter, index: idx, isRealtime: false)
                    case .ttc: return await ttcPlans(origin: oc, dest: dc)
                    case .winnipeg: return await winnipegPlans(from: o, to: d, fromName: from.title, toName: to.title, after: departAfter)
                    }
                }
            }
            for await list in group { itineraries += list }
        }

        // Nothing running in the next few hours (overnight, Sunday mornings…): look further ahead in the
        // timetable so there's always a "next train" to show.
        var laterService = false
        if !itineraries.contains(where: { !$0.isWalkOnly }) {
            let later = await nextServicePlans(agencies: common, origin: origin, dest: dest, after: departAfter)
            if !later.isEmpty { itineraries += later; laterService = true }
        }

        // Rank: soonest arrival, fewer transfers, less walking. Drop ones you can't catch any more.
        let cutoff = Date().addingTimeInterval(-60)
        var seen = Set<String>()
        result.itineraries = itineraries
            .filter { $0.isWalkOnly || $0.leaveAt >= cutoff }
            .sorted { a, b in
                if a.arriveAt != b.arriveAt { return a.arriveAt < b.arriveAt }
                if a.transfers != b.transfers { return a.transfers < b.transfers }
                return a.walkMinutes < b.walkMinutes
            }
            .filter { seen.insert($0.id).inserted }
        result.itineraries = Self.prune(result.itineraries)
        // Flag a long gap (overnight, or the extended search kicked in) so the UI can say nothing runs before then.
        if let first = result.itineraries.filter({ !$0.isWalkOnly }).map(\.leaveAt).min(),
           laterService || first.timeIntervalSince(max(departAfter, Date())) > 60 * 60 {
            result.nextServiceAt = first
        }
        if result.itineraries.isEmpty && result.notes.isEmpty {
            result.notes.append("No service found in the next 24 hours between these stops.")
        }
        return result
    }

    /// Steps through the timetable in 3-hour windows (up to a day ahead) until some trips turn up.
    private func nextServicePlans(agencies: [Agency], origin: [String: [Candidate]], dest: [String: [Candidate]], after: Date) async -> [Itinerary] {
        let window = 3.0
        var start = after.addingTimeInterval(2.5 * 3600)
        while start < after.addingTimeInterval(24 * 3600) {
            var found: [Itinerary] = []
            for agency in agencies where agency.source == .gtfsRealtime || agency.source == .metrolinx {
                let oc = origin[agency.id] ?? [], dc = dest[agency.id] ?? []
                guard let idx = await ScheduleStore.shared.index(for: agency, from: start, hours: window + 0.25) else { continue }
                found += await realtimePlans(agency: agency, origin: oc, dest: dc, after: start, index: idx, isRealtime: false)
            }
            if !found.isEmpty { return found }
            start = start.addingTimeInterval(window * 3600)
        }
        return []
    }

    /// Keeps a useful spread: drop options that leave earlier but arrive later than another option.
    private static func prune(_ list: [Itinerary]) -> [Itinerary] {
        var out: [Itinerary] = []
        for it in list {
            if out.contains(where: { $0.leaveAt >= it.leaveAt && $0.arriveAt <= it.arriveAt && $0.transfers <= it.transfers && !$0.isWalkOnly }) { continue }
            out.append(it)
            if out.count >= 10 { break }
        }
        return out
    }

    // MARK: Candidate stops

    private func candidates(for place: Place, at loc: CLLocation, name: String) async -> [String: [Candidate]] {
        var out: [String: [Candidate]] = [:]
        func add(_ s: TransitStop, _ dist: CLLocationDistance) {
            out[s.agencyID, default: []].append(Candidate(stop: s, walk: WalkLeg(fromName: name, toName: s.name, distance: dist)))
        }
        if case .stop(let s) = place {
            // The chosen stop, its sibling platforms, and other agencies' stops right next to it (e.g. Union GO ↔ UP Union).
            for (n, dist) in await TransitService.shared.stops(near: loc, radius: 250) where n.agencyID != s.agencyID || dist <= 120 {
                add(n, n.id == s.id ? 0 : dist)
            }
            // A station's own bus terminal can be a short walk away (Union Station → Union Station Bus Terminal,
            // Milton GO → Milton GO Bus). Count same-named stops of that agency as part of the station.
            var base = s.name.lowercased()
            for suffix in [" go station", " go", " station"] where base.hasSuffix(suffix) { base = String(base.dropLast(suffix.count)); break }
            if base.count >= 4 {
                for (n, dist) in await TransitService.shared.stops(near: loc, radius: 700)
                where n.agencyID == s.agencyID && dist > 120 && n.name.lowercased().hasPrefix(base + " ") {
                    add(n, dist)
                }
            }
            if out[s.agencyID]?.contains(where: { $0.stop.id == s.id }) != true { add(s, 0) }
        } else {
            for (s, dist) in await TransitService.shared.stops(near: loc, radius: 900) { add(s, dist) }
            // GO stations are worth a longer walk.
            if Catalog.agencies(near: loc.coordinate).contains(where: { $0.id == "go" }), let go = Catalog.agency("go"),
               let data = await store.data(for: go) {
                for (s, dist) in data.stops(near: loc, radius: 2500) where s.mode == .rail && dist > 900 { add(s, dist) }
            }
        }
        for k in out.keys { out[k] = Array(out[k]!.sorted { $0.walk.distance < $1.walk.distance }.prefix(120)) }
        return out
    }

    // MARK: GTFS-Realtime engine (direct + one transfer)

    private func realtimePlans(agency: Agency, origin: [Candidate], dest: [Candidate], after: Date,
                               index given: RealtimeCache.TripIndex?, isRealtime: Bool = true) async -> [Itinerary] {
        guard let data = await store.data(for: agency) else { return [] }
        var fetched: RealtimeCache.TripIndex?
        if given == nil { fetched = try? await rt.tripIndex(for: agency) }
        guard let index = given ?? fetched else { return [] }
        let start = Int64(max(after, .now).timeIntervalSince1970)
        let oWalk = Dictionary(origin.map { ($0.stop.stopID, $0) }, uniquingKeysWith: { a, b in a.walk.distance <= b.walk.distance ? a : b })
        let dWalk = Dictionary(dest.map { ($0.stop.stopID, $0) }, uniquingKeysWith: { a, b in a.walk.distance <= b.walk.distance ? a : b })

        func route(_ t: RealtimeCache.LiveTrip) -> TransitRoute? { t.routeID.flatMap { data.routeByID[$0] } ?? data.route(forTrip: t.tripID) }
        func headsign(_ t: RealtimeCache.LiveTrip, _ r: TransitRoute) -> String {
            t.headsign ?? data.headsign(forTrip: t.tripID) ?? data.headsign(route: r, lastStopID: t.stops.last!.stopID)
                ?? data.stopByID[t.stops.last!.stopID]?.name.asHeadsign ?? ""
        }
        func ride(_ t: RealtimeCache.LiveTrip, _ i: Int, _ j: Int) -> RideLeg? {
            guard let r = route(t), let a = data.stopByID[t.stops[i].stopID], let b = data.stopByID[t.stops[j].stopID] else { return nil }
            let visits = t.stops[i...j].compactMap { s in
                data.stopByID[s.stopID].map { StopVisit(stopID: s.stopID, name: $0.name, time: Date(timeIntervalSince1970: TimeInterval(s.time))) }
            }
            return RideLeg(route: r, headsign: headsign(t, r), from: a, to: b,
                           depart: Date(timeIntervalSince1970: TimeInterval(t.stops[i].time)),
                           arrive: Date(timeIntervalSince1970: TimeInterval(t.stops[j].time)),
                           isRealtime: isRealtime, stopCount: j - i, tripID: t.tripID, visits: visits)
        }

        var results: [Itinerary] = []
        // Leg-1 reach: stop → [(arrival, trip, boardIdx, alightIdx)]
        var reach: [String: [(arr: Int64, trip: RealtimeCache.LiveTrip, i: Int, k: Int)]] = [:]

        for t in index.trips.values {
            var bestDirect: (arr: Int64, i: Int, j: Int)?
            // Board at the reachable origin stop with the shortest walk.
            var boardIdx: Int?
            for (i, s) in t.stops.enumerated() where i < t.stops.count - 1 {
                guard let oc = oWalk[s.stopID], s.time >= start + Int64(oc.walk.seconds) else { continue }
                if boardIdx == nil || oc.walk.distance < oWalk[t.stops[boardIdx!].stopID]!.walk.distance { boardIdx = i }
            }
            if let i = boardIdx {
                for j in (i + 1)..<t.stops.count {
                    if let dc = dWalk[t.stops[j].stopID] {
                        let arr = t.stops[j].time + Int64(dc.walk.seconds)
                        if bestDirect == nil || arr < bestDirect!.arr { bestDirect = (arr, i, j) }
                    }
                    if reach[t.stops[j].stopID] == nil || reach[t.stops[j].stopID]!.count < 12 {
                        reach[t.stops[j].stopID, default: []].append((t.stops[j].time, t, i, j))
                    }
                }
            }
            if let b = bestDirect, let r = ride(t, b.i, b.j),
               let oc = oWalk[t.stops[b.i].stopID], let dc = dWalk[t.stops[b.j].stopID] {
                results.append(Itinerary(legs: walkWrap(oc.walk, [.ride(r)], dc.walk)))
            }
        }

        // One transfer (same stop, or a stop within a short walk), only when direct options are thin.
        if results.count < 4 || results.allSatisfy({ $0.walkMinutes > 12 }) {
            var bestByFirstTrip: [String: (arr: Int64, legs: [Leg])] = [:]
            for t2 in index.trips.values {
                for (m, s) in t2.stops.enumerated() where m < t2.stops.count - 1 {
                    let nearby = data.transferStops(from: s.stopID)
                    for (fromStop, transferDist) in nearby {
                        guard let entries = reach[fromStop] else { continue }
                        let transferWalk = Int64(transferDist * 1.3 / 1.35) + 90
                        for e in entries where e.trip.tripID != t2.tripID && e.arr + transferWalk <= s.time {
                            for n in (m + 1)..<t2.stops.count {
                                guard let dc = dWalk[t2.stops[n].stopID] else { continue }
                                let arr = t2.stops[n].time + Int64(dc.walk.seconds)
                                if let cur = bestByFirstTrip[e.trip.tripID], cur.arr <= arr { break }
                                guard let r1 = ride(e.trip, e.i, e.k), let r2 = ride(t2, m, n),
                                      let oc = oWalk[e.trip.stops[e.i].stopID] else { break }
                                var mid: [Leg] = [.ride(r1)]
                                if transferDist > 15 { mid.append(.walk(WalkLeg(fromName: r1.to.name, toName: r2.from.name, distance: transferDist))) }
                                mid.append(.ride(r2))
                                bestByFirstTrip[e.trip.tripID] = (arr, walkWrap(oc.walk, mid, dc.walk))
                                break
                            }
                        }
                    }
                }
            }
            results += bestByFirstTrip.values.map { Itinerary(legs: $0.legs) }
        }
        return results
    }

    private func walkWrap(_ first: WalkLeg, _ middle: [Leg], _ last: WalkLeg) -> [Leg] {
        var legs: [Leg] = []
        if first.distance > 40 { legs.append(.walk(first)) }
        legs += middle
        if last.distance > 40 { legs.append(.walk(last)) }
        return legs
    }

    // MARK: GO Transit engine (Metrolinx Journey API)

    private func goPlans(origin: [Candidate], dest: [Candidate], after: Date) async -> [Itinerary] {
        guard let go = Catalog.agency("go"), let data = await store.data(for: go) else { return [] }
        // Prefer train stations, then the closest bus stops.
        func pick(_ c: [Candidate]) -> [Candidate] {
            let rail = c.filter { $0.stop.mode == .rail }.prefix(2)
            let bus = c.filter { $0.stop.mode != .rail && $0.walk.distance <= 900 }.prefix(rail.isEmpty ? 2 : 1)
            return Array(rail) + Array(bus)
        }
        let os = pick(origin), ds = pick(dest)
        let tz = TimeZone(identifier: "America/Toronto")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let fmtDay = DateFormatter(); fmtDay.dateFormat = "yyyyMMdd"; fmtDay.timeZone = tz
        let fmtTime = DateFormatter(); fmtTime.dateFormat = "HHmm"; fmtTime.timeZone = tz

        var out: [Itinerary] = []
        await withTaskGroup(of: [Itinerary].self) { group in
            for oc in os {
                for dc in ds where oc.stop.stopID != dc.stop.stopID {
                    group.addTask {
                        // Leave time at the stop = request time + walk to it.
                        let at = max(after, .now).addingTimeInterval(oc.walk.distance > 40 ? oc.walk.seconds : 0)
                        let path = "Schedule/Journey/\(fmtDay.string(from: at))/\(oc.stop.stopID)/\(dc.stop.stopID)/\(fmtTime.string(from: at))/6"
                        guard let url = URL(string: "\(Catalog.metrolinxBase)/\(path)?key=\(Secrets.metrolinxKey)"),
                              let root = try? await Network.json(url) as? [String: Any] else { return [] }
                        let live = (try? await GO.departures(stop: oc.stop, data: data)) ?? []
                        let liveByTrip = Dictionary(live.compactMap { d in d.vehicleID.map { ($0, d) } }, uniquingKeysWith: { a, _ in a })
                        return J.list(root["SchJourneys"]).flatMap { j -> [Itinerary] in
                            let day = J.str(j["Date"]) ?? ""
                            return J.list(j["Services"]).compactMap { svc in
                                parseGOService(svc, day: day, tz: tz, data: data, live: liveByTrip, origin: oc, dest: dc, after: at)
                            }
                        }
                    }
                }
            }
            for await list in group { out += list }
        }
        return out
    }

    private func parseGOService(_ svc: [String: Any], day: String, tz: TimeZone, data: AgencyData,
                                live: [String: Departure], origin: Candidate, dest: Candidate, after: Date) -> Itinerary? {
        var legs: [Leg] = []
        var lastTime: Date?
        func time(_ hhmm: String?) -> Date? {
            guard let hhmm, var d = TransitDates.local("\(day) \(hhmm):00", timeZone: tz.identifier) else { return nil }
            // GO labels after-midnight trips with the previous service day: roll them forward.
            while d < after.addingTimeInterval(-6 * 3600) { d = d.addingTimeInterval(86_400) }
            if let lastTime, d < lastTime.addingTimeInterval(-3600) { d = d.addingTimeInterval(86_400) } // past midnight
            lastTime = d
            return d
        }
        let trips = J.list(J.dict(svc["Trips"])["Trip"])
        for (idx, t) in trips.enumerated() {
            let stops = J.list(J.dict(t["Stops"])["Stop"])
            guard let first = stops.first, let last = stops.last,
                  let fromCode = J.str(first["Code"]), let toCode = J.str(last["Code"]),
                  let from = data.stopByID[fromCode], let to = data.stopByID[toCode],
                  var dep = time(J.str(first["Time"])), var arr = time(J.str(last["Time"])) else { return nil }
            let isTrain = J.str(t["Type"]) == "T"
            let line = J.str(t["Line"]) ?? ""
            let route = data.routesByShortName[line.uppercased().trimmingLeadingZeros] ?? data.routesByShortName[line.uppercased()]
                ?? TransitRoute(agencyID: "go", routeID: line, shortName: line, longName: "", colorHex: "00853E", textColorHex: "FFFFFF",
                                mode: isTrain ? .rail : .bus)
            let display = J.str(t["Display"]) ?? ""
            let headsign = display.components(separatedBy: " - ").dropFirst().joined(separator: " - ").nilIfEmpty ?? to.name
            let number = J.str(t["Number"])
            let savedLast = lastTime
            lastTime = dep.addingTimeInterval(-60)
            let visits: [StopVisit] = stops.compactMap { s in
                guard let code = J.str(s["Code"]), let st = data.stopByID[code], let tm = time(J.str(s["Time"])) else { return nil }
                return StopVisit(stopID: code, name: st.name, time: tm)
            }
            lastTime = savedLast
            var leg = RideLeg(route: route, headsign: headsign, from: from, to: to, depart: dep, arrive: arr,
                              isRealtime: false, stopCount: max(1, stops.count - 1), tripID: number, visits: visits)
            // Overlay live departure time and platform for the first leg (only near-term: trip numbers repeat daily).
            if idx == 0, dep.timeIntervalSinceNow < 3 * 3600, let n = number, let l = live[n], abs(l.time.timeIntervalSince(dep)) < 3 * 3600 {
                let shift = l.time.timeIntervalSince(dep)
                leg.scheduledDepart = dep
                dep = l.time; arr = arr.addingTimeInterval(max(0, shift))
                leg = RideLeg(route: route, headsign: headsign, from: from, to: to, depart: dep, arrive: arr, scheduledDepart: leg.scheduledDepart,
                              isRealtime: l.isRealtime, platform: l.platform, stopCount: leg.stopCount, tripID: number,
                              visits: leg.visits.map { StopVisit(stopID: $0.stopID, name: $0.name, time: $0.time.addingTimeInterval(max(0, shift))) })
            }
            if idx > 0, case .ride(let prev)? = legs.last, prev.to.stopID != from.stopID,
               let a = data.stopByID[prev.to.stopID] {
                legs.append(.walk(WalkLeg(fromName: a.name, toName: from.name, distance: a.location.distance(from: from.location))))
            }
            legs.append(.ride(leg))
        }
        guard !legs.isEmpty, case .ride(let firstRide)? = legs.first, case .ride(let lastRide)? = legs.last else { return nil }
        // The journey may board at a bus bay next to the station you picked — walk there.
        let walkIn = WalkLeg(fromName: origin.walk.fromName, toName: firstRide.from.name,
                             distance: origin.walk.distance + (firstRide.from.stopID == origin.stop.stopID ? 0 : origin.stop.location.distance(from: firstRide.from.location)))
        let walkOut = WalkLeg(fromName: lastRide.to.name, toName: dest.walk.fromName,
                              distance: dest.walk.distance + (lastRide.to.stopID == dest.stop.stopID ? 0 : dest.stop.location.distance(from: lastRide.to.location)))
        return Itinerary(legs: walkWrap(walkIn, legs, walkOut))
    }

    // MARK: TTC engine (direct trips by matching Umo vehicles at both stops)

    private func ttcPlans(origin: [Candidate], dest: [Candidate]) async -> [Itinerary] {
        guard let ttc = Catalog.agency("ttc") else { return [] }
        let data = await store.data(for: ttc)
        // Only routes that serve both ends can give a direct trip. For each, take up to four of the
        // closest stops at each end so both directions (and both sides of a corner) are covered.
        let shared = Set(origin.flatMap(\.stop.routeIDs)).intersection(dest.flatMap(\.stop.routeIDs))
        func pick(_ c: [Candidate]) -> [Candidate] {
            var perRoute: [String: Int] = [:], out: [Candidate] = []
            for cand in c {
                let useful = cand.stop.routeIDs.filter { shared.contains($0) && perRoute[$0, default: 0] < 4 }
                guard !useful.isEmpty else { continue }
                useful.forEach { perRoute[$0, default: 0] += 1 }
                out.append(cand)
                if out.count == 14 { break }
            }
            return out
        }
        let os = pick(origin), ds = pick(dest)
        let all = os.map(\.stop) + ds.map(\.stop)
        var deps: [String: [Departure]] = [:]
        await withTaskGroup(of: (String, [Departure]).self) { group in
            for s in all { group.addTask { (s.id, (try? await TTC.departures(stop: s, data: data)) ?? []) } }
            for await (k, v) in group { deps[k] = v }
        }
        var out: [Itinerary] = []
        for oc in os {
            for o in deps[oc.stop.id] ?? [] where o.time >= Date().addingTimeInterval(oc.walk.seconds - 30) {
                guard let vid = o.vehicleID else { continue }
                for dc in ds {
                    guard let a = (deps[dc.stop.id] ?? []).first(where: { $0.vehicleID == vid && $0.route.id == o.route.id && $0.time > o.time }) else { continue }
                    let r = RideLeg(route: o.route, headsign: o.headsign, from: oc.stop, to: dc.stop, depart: o.time, arrive: a.time,
                                    isRealtime: o.isRealtime, tripID: o.id)
                    out.append(Itinerary(legs: walkWrap(oc.walk, [.ride(r)], dc.walk)))
                }
            }
        }
        return out
    }

    // MARK: Winnipeg engine (Winnipeg Transit trip planner)

    private func winnipegPlans(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, fromName: String, toName: String, after: Date) async -> [Itinerary] {
        await Winnipeg.plan(from: from, to: to, fromName: fromName, toName: toName, after: after)
    }
}

// MARK: - Transfer neighbours

extension AgencyData {
    /// The stop itself plus stops within a short walk — where you could change vehicles.
    func transferStops(from stopID: String, within metres: CLLocationDistance = 160) -> [(String, CLLocationDistance)] {
        guard let s = stopByID[stopID] else { return [(stopID, 0)] }
        var out: [(String, CLLocationDistance)] = [(stopID, 0)]
        for other in grid.neighbours(of: s.latitude, s.longitude) where other.stopID != stopID {
            let d = other.location.distance(from: s.location)
            if d <= metres { out.append((other.stopID, d)) }
        }
        return out
    }
}

/// A coarse spatial hash over an agency's stops (~200 m cells).
final class StopGrid: @unchecked Sendable {
    private var cells: [Int64: [TransitStop]] = [:]
    private static let size = 0.002

    init(_ stops: [TransitStop]) {
        for s in stops { cells[Self.key(s.latitude, s.longitude), default: []].append(s) }
    }

    private static func key(_ lat: Double, _ lon: Double) -> Int64 {
        (Int64((lat / size).rounded(.down)) << 32) ^ Int64(Int32(truncatingIfNeeded: Int64((lon / size).rounded(.down))))
    }

    func neighbours(of lat: Double, _ lon: Double) -> [TransitStop] {
        var out: [TransitStop] = []
        for dy in -1...1 { for dx in -1...1 {
            out += cells[Self.key(lat + Double(dy) * Self.size, lon + Double(dx) * Self.size)] ?? []
        } }
        return out
    }
}
