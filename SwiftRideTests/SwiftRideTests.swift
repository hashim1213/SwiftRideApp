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
}
