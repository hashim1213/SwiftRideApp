//
//  SwiftRideTests.swift
//  SwiftRideTests
//
//  Unit tests run offline; the live-feed checks hit real agency servers and are
//  skipped unless SWIFTRIDE_LIVE_TESTS=1 is set in the scheme's environment.
//

import XCTest
import CoreLocation
@testable import SwiftRide

final class SwiftRideTests: XCTestCase {

    // MARK: Offline

    func testEveryAgencyWithBundledStopsLoads() async throws {
        for agency in Catalog.agencies where agency.hasBundledStops {
            let data = await StaticStore.shared.data(for: agency)
            XCTAssertNotNil(data, "\(agency.id) failed to load")
            XCTAssertGreaterThan(data?.stops.count ?? 0, 4, "\(agency.id) has no stops")
            XCTAssertGreaterThan(data?.routes.count ?? 0, 0, "\(agency.id) has no routes")
        }
    }

    func testEveryCityResolvesItsAgencies() {
        for city in Catalog.cities {
            XCTAssertEqual(city.agencies.count, city.agencyIDs.count, "\(city.id) references an unknown agency")
            XCTAssertTrue(Catalog.cities(near: city.coordinate).contains(city))
        }
    }

    func testTTCHeadsignParsing() {
        XCTAssertEqual(TTC.headsign(from: "East - 108b Driftwood towards Sheppard West Station via Arleta"), "Sheppard West Station")
        XCTAssertEqual(TTC.headsign(from: "North - 35a Jane towards Steeles"), "Steeles")
    }

    func testAgencyLocalTimes() {
        let d = TransitDates.local("2026-11-18 20:17:00", timeZone: "America/Toronto")
        XCTAssertEqual(d?.timeIntervalSince1970, 1_795_051_020)
        // Winnipeg follows whatever offset the device's time-zone database says, so derive the expectation from it.
        let wpg = TransitDates.local("2026-11-18T20:17:00", timeZone: "America/Winnipeg")!
        let offset = TimeZone(identifier: "America/Winnipeg")!.secondsFromGMT(for: wpg) - TimeZone(identifier: "America/Toronto")!.secondsFromGMT(for: wpg)
        XCTAssertEqual(wpg.timeIntervalSince(d!), TimeInterval(-offset))
    }

    func testProtobufVarintAndStrings() throws {
        // FeedMessage { entity { id: "a" trip_update { trip { trip_id: "t" route_id: "r" }
        //   stop_time_update { departure { time: 2000000000 } stop_id: "s" } } } }
        let trip: [UInt8] = [0x0A, 0x01, 0x74, 0x2A, 0x01, 0x72]
        let event: [UInt8] = [0x10] + varint(2_000_000_000)
        let stu: [UInt8] = [0x1A, UInt8(event.count)] + event + [0x22, 0x01, 0x73]
        let tu: [UInt8] = [0x0A, UInt8(trip.count)] + trip + [0x12, UInt8(stu.count)] + stu
        let entity: [UInt8] = [0x0A, 0x01, 0x61, 0x1A, UInt8(tu.count)] + tu
        let feed: [UInt8] = [0x12, UInt8(entity.count)] + entity
        let decoded = try GTFSRT.decode(Data(feed))
        XCTAssertEqual(decoded.tripUpdates.count, 1)
        XCTAssertEqual(decoded.tripUpdates[0].routeID, "r")
        XCTAssertEqual(decoded.tripUpdates[0].stopTimes.first?.stopID, "s")
        XCTAssertEqual(decoded.tripUpdates[0].stopTimes.first?.time, 2_000_000_000)
    }

    private func varint(_ v: UInt64) -> [UInt8] {
        var v = v, out: [UInt8] = []
        repeat { var b = UInt8(v & 0x7F); v >>= 7; if v != 0 { b |= 0x80 }; out.append(b) } while v != 0
        return out
    }

    // MARK: Live (network)

    /// For each city, find departures around the centre. Prints a coverage report.
    func testLiveDeparturesInEveryCity() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SWIFTRIDE_LIVE_TESTS"] == "1", "Set SWIFTRIDE_LIVE_TESTS=1 to hit live feeds")
        var report: [String] = []
        for agency in Catalog.agencies {
            let city = Catalog.cities.first { $0.agencyIDs.first == agency.id } ?? Catalog.cities.first { $0.agencyIDs.contains(agency.id) }!
            let center = CLLocation(latitude: city.lat, longitude: city.lon)
            let stops = await TransitService.shared.stops(near: center, radius: 30_000, agencies: [agency])
            var found = 0, checked = 0
            for (stop, _) in stops.prefix(agency.source == .gtfsRealtime ? 60 : 12) {
                checked += 1
                if let d = try? await TransitService.shared.departures(for: stop), !d.isEmpty { found += 1 }
                if found >= 3 { break }
            }
            report.append("\(agency.id.padding(toLength: 9, withPad: " ", startingAt: 0)) stops=\(stops.count) withDepartures=\(found)/\(checked)")
        }
        let text = "LIVE COVERAGE\n" + report.joined(separator: "\n")
        print(text)
        try? text.write(toFile: "/tmp/swiftride-live-coverage.txt", atomically: true, encoding: .utf8)
    }

    /// Plans a few real trips and writes a readable report (live network).
    func testLivePlanner() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SWIFTRIDE_LIVE_TESTS"] == "1", "Set SWIFTRIDE_LIVE_TESTS=1 to hit live feeds")
        let go = try XCTUnwrap(Catalog.agency("go"))
        let goData = await StaticStore.shared.data(for: go)
        let ml = try XCTUnwrap(goData?.stopByID["ML"]), un = try XCTUnwrap(goData?.stopByID["UN"])
        let f = DateFormatter(); f.dateFormat = "EEE HH:mm"
        var report = ""
        func describe(_ title: String, _ r: PlanResult) {
            report += "== \(title): \(r.itineraries.count) options \(r.notes)\n"
            for it in r.itineraries.prefix(4) {
                let legs = it.legs.map { leg -> String in
                    switch leg {
                    case .walk(let w): return "walk\(w.minutes)"
                    case .ride(let r): return "\(r.route.badgeText)[\(r.from.displayCode)→\(r.to.displayCode)\(r.platform.map { " P" + $0 } ?? "")\(r.isRealtime ? " live" : "")]"
                    }
                }.joined(separator: " > ")
                report += "  \(f.string(from: it.leaveAt))→\(f.string(from: it.arriveAt)) \(legs)\n"
            }
        }
        describe("Milton GO → Union", await TripPlanner.shared.plan(from: .stop(ml), to: .stop(un), current: nil))
        describe("Union → Milton GO", await TripPlanner.shared.plan(from: .stop(un), to: .stop(ml), current: nil))
        describe("Toronto: King&Bay → Spadina&Dundas", await TripPlanner.shared.plan(
            from: .point(name: "King & Bay", subtitle: nil, latitude: 43.6487, longitude: -79.3800),
            to: .point(name: "Spadina & Dundas", subtitle: nil, latitude: 43.6527, longitude: -79.3977), current: nil))
        describe("Calgary: downtown → Chinook", await TripPlanner.shared.plan(
            from: .point(name: "Downtown", subtitle: nil, latitude: 51.0458, longitude: -114.0631),
            to: .point(name: "Chinook Centre", subtitle: nil, latitude: 50.9980, longitude: -114.0735), current: nil))
        describe("Winnipeg: Portage&Main → U of M", await TripPlanner.shared.plan(
            from: .point(name: "Portage & Main", subtitle: nil, latitude: 49.8951, longitude: -97.1384),
            to: .point(name: "University of Manitoba", subtitle: nil, latitude: 49.8075, longitude: -97.1366), current: nil))
        // Plan ahead: next Monday 8:00 AM Toronto time.
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/Toronto")!
        let monday = cal.nextDate(after: .now, matching: DateComponents(hour: 8, minute: 0, weekday: 2), matchingPolicy: .nextTime)!
        let clock = Date()
        describe("PLAN AHEAD Mon 8am Milton GO → Union", await TripPlanner.shared.plan(from: .stop(ml), to: .stop(un), current: nil, departAfter: monday))
        describe("PLAN AHEAD Mon 8am Toronto King&Bay → Spadina&Dundas", await TripPlanner.shared.plan(
            from: .point(name: "King & Bay", subtitle: nil, latitude: 43.6487, longitude: -79.3800),
            to: .point(name: "Spadina & Dundas", subtitle: nil, latitude: 43.6527, longitude: -79.3977), current: nil, departAfter: monday))
        var calC = Calendar(identifier: .gregorian); calC.timeZone = TimeZone(identifier: "America/Edmonton")!
        let mondayC = calC.nextDate(after: .now, matching: DateComponents(hour: 8, minute: 0, weekday: 2), matchingPolicy: .nextTime)!
        describe("PLAN AHEAD Mon 8am Calgary downtown → Chinook", await TripPlanner.shared.plan(
            from: .point(name: "Downtown", subtitle: nil, latitude: 51.0458, longitude: -114.0631),
            to: .point(name: "Chinook Centre", subtitle: nil, latitude: 50.9980, longitude: -114.0735), current: nil, departAfter: mondayC))
        describe("PLAN AHEAD Mon 5pm Union → Milton GO", await TripPlanner.shared.plan(from: .stop(un), to: .stop(ml), current: nil,
            departAfter: monday.addingTimeInterval(9 * 3600)))
        report += "plan-ahead took \(String(format: "%.1f", Date().timeIntervalSince(clock)))s (4 plans)\n"
        print(report)
        try? report.write(toFile: "/tmp/swiftride-planner.txt", atomically: true, encoding: .utf8)
    }

    // MARK: Offline, arrive-by and PATH

    func testPathRoutingUnionToEatonCentre() throws {
        let net = PathNetwork.shared
        XCTAssertTrue(net.isAvailable)
        let union = try XCTUnwrap(net.places(near: nil, matching: "Union").first)
        let eaton = try XCTUnwrap(net.places(near: nil, matching: "Eaton").first)
        let route = try XCTUnwrap(net.route(from: union, to: eaton, stepFree: false), "no PATH route \(union.name) → \(eaton.name)")
        XCTAssertGreaterThan(route.metres, 300)
        XCTAssertLessThan(route.metres, 3000)
        var report = "PATH \(union.name) → \(eaton.name): \(Int(route.metres)) m, \(route.minutes) min, \(route.steps.count) steps\n"
        for st in route.steps { report += "  • \(st.instruction)\(st.detail.map { " — " + $0 } ?? "") (\(Int(st.metres)) m)\n" }
        if let sf = net.route(from: union, to: eaton, stepFree: true) { report += "step-free: \(Int(sf.metres)) m\n" } else { report += "step-free: none\n" }
        try? report.write(toFile: "/tmp/swiftride-path.txt", atomically: true, encoding: .utf8)
    }

    func testOfflinePlanningAndDepartures() async throws {
        Network.isOffline = true
        defer { Network.isOffline = false }
        let go = try XCTUnwrap(Catalog.agency("go"))
        let loaded = await StaticStore.shared.data(for: go)
        let goData = try XCTUnwrap(loaded)
        let ml = try XCTUnwrap(goData.stopByID["ML"]), un = try XCTUnwrap(goData.stopByID["UN"])
        // Tomorrow 8 AM so there's GO service regardless of when the test runs.
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/Toronto")!
        let morning = cal.date(bySettingHour: 8, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: .now)!)!
        let goPlan = await TripPlanner.shared.plan(from: .stop(ml), to: .stop(un), current: nil, departAfter: morning)
        XCTAssertFalse(goPlan.itineraries.isEmpty, "offline GO planning failed: \(goPlan.notes)")
        let ttcPlan = await TripPlanner.shared.plan(
            from: .point(name: "King & Bay", subtitle: nil, latitude: 43.6487, longitude: -79.3800),
            to: .point(name: "Spadina & Dundas", subtitle: nil, latitude: 43.6527, longitude: -79.3977), current: nil, departAfter: morning)
        XCTAssertFalse(ttcPlan.itineraries.isEmpty, "offline TTC planning failed")
        let unDeps = try await TransitService.shared.departures(for: un, at: morning)
        XCTAssertFalse(unDeps.isEmpty, "offline GO departures empty")
        XCTAssertTrue(unDeps.allSatisfy { !$0.isRealtime })
        let byArrival = await TripPlanner.shared.plan(from: .stop(ml), to: .stop(un), current: nil, arriveBy: morning.addingTimeInterval(3600))
        XCTAssertFalse(byArrival.itineraries.isEmpty, "arrive-by found nothing")
        XCTAssertTrue(byArrival.itineraries.allSatisfy { $0.arriveAt <= morning.addingTimeInterval(3660) })
        let f = DateFormatter(); f.dateFormat = "EEE HH:mm"
        var report = "OFFLINE GO Milton→Union 8am: " + goPlan.itineraries.prefix(3).map { "\(f.string(from: $0.leaveAt))→\(f.string(from: $0.arriveAt))" }.joined(separator: ", ")
        report += "\nOFFLINE TTC: " + ttcPlan.itineraries.prefix(3).map { "\(f.string(from: $0.leaveAt)) \($0.rides.map(\.route.badgeText).joined(separator: ">"))" }.joined(separator: ", ")
        report += "\nOFFLINE Union departures: \(unDeps.count), first \(unDeps.first.map { "\($0.route.badgeText) \(f.string(from: $0.time))" } ?? "-")"
        report += "\nARRIVE BY 9am Milton→Union: " + byArrival.itineraries.prefix(4).map { "\(f.string(from: $0.leaveAt))→\(f.string(from: $0.arriveAt))" }.joined(separator: ", ")
        try? report.write(toFile: "/tmp/swiftride-offline.txt", atomically: true, encoding: .utf8)
    }

    // MARK: Live Activity

    @MainActor func testLiveActivityStepsFollowTheTimetable() {
        let route = TransitRoute(agencyID: "ttc", routeID: "1", shortName: "1", longName: "Yonge-University", colorHex: "FFC21A", textColorHex: "000000", mode: .subway)
        func stop(_ id: String, _ name: String, _ lat: Double) -> TransitStop {
            TransitStop(agencyID: "ttc", stopID: id, code: id, name: name, latitude: lat, longitude: -79.38, routeIDs: ["1"])
        }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let a = stop("a", "Union", 43.645), b = stop("b", "King", 43.649), c = stop("c", "Queen", 43.652), d = stop("d", "Dundas", 43.656)
        let visits = [StopVisit(stopID: "a", name: "Union", time: t0.addingTimeInterval(600)),
                      StopVisit(stopID: "b", name: "King", time: t0.addingTimeInterval(720)),
                      StopVisit(stopID: "c", name: "Queen", time: t0.addingTimeInterval(840)),
                      StopVisit(stopID: "d", name: "Dundas", time: t0.addingTimeInterval(960))]
        let ride = RideLeg(route: route, headsign: "Finch", from: a, to: d, depart: t0.addingTimeInterval(600), arrive: t0.addingTimeInterval(960),
                           isRealtime: false, visits: visits)
        let walk = WalkLeg(fromName: "Here", toName: "Union", distance: 300)
        let trip = Itinerary(legs: [.walk(walk), .ride(ride)])

        let walking = TripActivityManager.content(for: trip, now: t0)
        XCTAssertEqual(walking?.phase, .walk)
        XCTAssertEqual(walking?.target, t0.addingTimeInterval(600 - walk.seconds))
        XCTAssertEqual(TripActivityManager.content(for: trip, now: t0.addingTimeInterval(560))?.phase, .wait)
        let riding = TripActivityManager.content(for: trip, now: t0.addingTimeInterval(650))
        XCTAssertEqual(riding?.phase, .ride)
        XCTAssertEqual(riding?.stopsRemaining, 3)                       // King, Queen, Dundas
        XCTAssertEqual(riding?.title, "Get off in 3 stops")
        XCTAssertEqual(riding?.subtitle, "Next: King")
        XCTAssertEqual(TripActivityManager.content(for: trip, now: t0.addingTimeInterval(850))?.title, "Get off at the next stop")
        XCTAssertEqual(TripActivityManager.content(for: trip, now: t0.addingTimeInterval(930))?.title, "Get off now")
        XCTAssertEqual(TripActivityManager.content(for: trip, now: t0.addingTimeInterval(2000))?.phase, .arrived)
    }
}
