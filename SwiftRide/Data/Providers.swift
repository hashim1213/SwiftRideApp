import Foundation
import CoreLocation
import SwiftUI

// MARK: - Winnipeg Transit Open Data API (v3)

enum Winnipeg {
    static let agencyID = "wpg"
    private static let base = "https://api.winnipegtransit.com/v3"
    private static let tz = "America/Winnipeg"

    private static func url(_ path: String, _ items: [URLQueryItem] = []) -> URL {
        var c = URLComponents(string: base + path)!
        c.queryItems = items + [URLQueryItem(name: "api-key", value: Secrets.winnipegTransitKey)]
        return c.url!
    }

    private static func stop(from s: [String: Any]) -> TransitStop? {
        guard let number = J.str(s["number"] ?? s["key"]) else { return nil }
        let geo = J.dict(J.dict(s["centre"])["geographic"])
        guard let lat = J.dbl(geo["latitude"]), let lon = J.dbl(geo["longitude"]) else { return nil }
        let name = J.str(s["name"]) ?? "Stop \(number)"
        return TransitStop(agencyID: agencyID, stopID: number, code: "", name: name, latitude: lat, longitude: lon, routeIDs: [])
    }

    static func stops(near location: CLLocation, radius: CLLocationDistance) async throws -> [(TransitStop, CLLocationDistance)] {
        let u = url("/stops.json", [
            .init(name: "lat", value: String(location.coordinate.latitude)),
            .init(name: "lon", value: String(location.coordinate.longitude)),
            .init(name: "distance", value: String(Int(min(radius, 2500)))),
            .init(name: "walking", value: "false"),
            .init(name: "usage", value: "long"),
        ])
        let root = J.dict(try await Network.json(u))
        return J.list(root["stops"]).compactMap { s in
            guard let stop = stop(from: s) else { return nil }
            let d = J.dbl(J.dict(s["distances"])["direct"]) ?? stop.location.distance(from: location)
            return (stop, d)
        }
    }

    static func stop(number: Int) async throws -> TransitStop? {
        let root = J.dict(try await Network.json(url("/stops/\(number).json", [.init(name: "usage", value: "long")])))
        return stop(from: J.dict(root["stop"]))
    }

    private static func route(from r: [String: Any]) -> TransitRoute {
        let key = J.str(r["key"]) ?? J.str(r["number"]) ?? "?"
        let badge = J.dict(r["badge-style"])
        let bg = Color.tamedHex((J.str(badge["background-color"]) ?? "").replacingOccurrences(of: "#", with: ""))
        let fg = (J.str(badge["color"]) ?? "").replacingOccurrences(of: "#", with: "")
        let isWhite = bg.isEmpty
        return TransitRoute(agencyID: agencyID, routeID: key,
                            shortName: J.str(r["badge-label"]) ?? J.str(r["number"]) ?? key,
                            longName: J.str(r["name"]) ?? "",
                            colorHex: isWhite ? "0060A9" : bg, textColorHex: isWhite ? "FFFFFF" : fg, mode: .bus)
    }

    static func departures(stop: TransitStop) async throws -> [Departure] {
        let u = url("/stops/\(stop.stopID)/schedule.json", [.init(name: "max-results-per-route", value: "4"), .init(name: "usage", value: "long")])
        let root = J.dict(J.dict(try await Network.json(u))["stop-schedule"])
        var out: [Departure] = []
        for rs in J.list(root["route-schedules"]) {
            let route = route(from: J.dict(rs["route"]))
            for ss in J.list(rs["scheduled-stops"]) {
                let times = J.dict(ss["times"])
                let dep = J.dict(times["departure"]).isEmpty ? J.dict(times["arrival"]) : J.dict(times["departure"])
                let scheduled = TransitDates.local(J.str(dep["scheduled"]), timeZone: tz)
                let estimated = TransitDates.local(J.str(dep["estimated"]), timeZone: tz)
                guard let time = estimated ?? scheduled else { continue }
                let variant = J.dict(ss["variant"])
                let bus = J.dict(ss["bus"])
                out.append(Departure(id: J.str(ss["key"]) ?? UUID().uuidString, route: route,
                                     headsign: J.str(variant["name"]) ?? route.longName, time: time, scheduledTime: scheduled,
                                     isRealtime: estimated != nil && estimated != scheduled,
                                     vehicleID: J.str(bus["key"]), isCancelled: J.bool(ss["cancelled"])))
            }
        }
        return out
    }

    static func alerts() async throws -> [ServiceAlert] {
        let root = J.dict(try await Network.json(url("/service-advisories.json")))
        return J.list(root["service-advisories"]).compactMap { a in
            guard let title = J.str(a["title"]) else { return nil }
            let priority = J.int(a["priority"]) ?? 5
            return ServiceAlert(id: "wpg:\(J.str(a["key"]) ?? title)", agencyID: agencyID, title: title,
                                body: (J.str(a["body"]) ?? "").strippingHTML, routeIDs: [], stopIDs: [],
                                start: TransitDates.local(J.str(a["updated-at"]), timeZone: tz), end: nil, url: nil,
                                severity: priority <= 2 ? .severe : priority <= 3 ? .warning : .info,
                                category: J.str(a["category"]))
        }
    }
}

// MARK: - TTC (Umo / NextBus predictions keyed by the stop number on the pole)

enum TTC {
    static func departures(stop: TransitStop, data: AgencyData?) async throws -> [Departure] {
        var c = URLComponents(string: "https://retro.umoiq.com/service/publicJSONFeed")!
        c.queryItems = [.init(name: "command", value: "predictions"), .init(name: "a", value: "ttc"),
                        .init(name: "stopId", value: stop.displayCode)]
        let root = J.dict(try await Network.json(c.url!))
        var out: [Departure] = []
        for p in J.list(root["predictions"]) {
            let tag = J.str(p["routeTag"]) ?? ""
            let route = data?.routesByShortName[tag.uppercased()] ?? data?.routeByID[tag] ?? TransitRoute(
                agencyID: "ttc", routeID: tag, shortName: tag, longName: J.str(p["routeTitle"]) ?? "",
                colorHex: "DA251D", textColorHex: "FFFFFF", mode: .bus)
            for d in J.list(p["direction"]) {
                let headsign = headsign(from: J.str(d["title"]) ?? "") ?? route.longName
                for pr in J.list(d["prediction"]) {
                    guard let ms = J.dbl(pr["epochTime"]) else { continue }
                    out.append(Departure(id: "ttc:\(J.str(pr["tripTag"]) ?? UUID().uuidString)@\(stop.stopID)", route: route,
                                         headsign: headsign, time: Date(timeIntervalSince1970: ms / 1000),
                                         isRealtime: !J.bool(pr["affectedByLayover"]), vehicleID: J.str(pr["vehicle"])))
                }
            }
        }
        return out
    }

    /// "East - 108b Driftwood towards Sheppard West Station via Arleta" → "Sheppard West Station"
    static func headsign(from title: String) -> String? {
        guard let r = title.range(of: "towards ", options: .caseInsensitive) else {
            return title.components(separatedBy: " - ").last?.nilIfEmpty
        }
        var s = String(title[r.upperBound...])
        if let via = s.range(of: " via ") { s = String(s[..<via.lowerBound]) }
        return s.trimmingCharacters(in: .whitespaces).nilIfEmpty
    }
}

// MARK: - GO Transit (Metrolinx Open Data API)

enum GO {
    private static let tz = "America/Toronto"

    private static func url(_ path: String) -> URL {
        URL(string: "\(Catalog.metrolinxBase)/\(path)?key=\(Secrets.metrolinxKey)")!
    }

    private static func route(code: String, name: String?, isTrain: Bool, data: AgencyData?) -> TransitRoute {
        let key = code.trimmingCharacters(in: .whitespaces).uppercased()
        if let r = data?.routesByShortName[key.trimmingLeadingZeros] ?? data?.routesByShortName[key] { return r }
        return TransitRoute(agencyID: "go", routeID: key, shortName: key, longName: name ?? "", colorHex: "00853E",
                            textColorHex: "FFFFFF", mode: isTrain ? .rail : .bus)
    }

    private static func headsign(_ direction: String?) -> String? {
        guard let d = direction else { return nil }
        let parts = d.components(separatedBy: " - ")
        return (parts.count > 1 ? parts.dropFirst().joined(separator: " - ") : d).trimmingCharacters(in: .whitespaces).nilIfEmpty
    }

    static func departures(stop: TransitStop, data: AgencyData?) async throws -> [Departure] {
        let root = J.dict(try await Network.json(url("Stop/NextService/\(stop.stopID)")))
        let lines = J.list(J.dict(root["NextService"])["Lines"])
        return lines.compactMap { l in
            let scheduled = TransitDates.local(J.str(l["ScheduledDepartureTime"]), timeZone: tz)
            let computed = TransitDates.local(J.str(l["ComputedDepartureTime"]), timeZone: tz)
            guard let time = computed ?? scheduled else { return nil }
            let isTrain = J.str(l["ServiceType"]) == "T"
            let route = route(code: J.str(l["LineCode"]) ?? "", name: J.str(l["LineName"]), isTrain: isTrain, data: data)
            let platform = J.str(l["ActualPlatform"]) ?? J.str(l["ScheduledPlatform"])
            let tracked = (J.dbl(l["Latitude"]) ?? -1) > 0
            return Departure(id: "go:\(J.str(l["TripNumber"]) ?? UUID().uuidString)@\(stop.stopID)", route: route,
                             headsign: headsign(J.str(l["DirectionName"])) ?? route.longName, time: time, scheduledTime: scheduled,
                             isRealtime: tracked || (computed != nil && computed != scheduled),
                             platform: platform?.replacingOccurrences(of: " ", with: "").nilIfEmpty,
                             vehicleID: J.str(l["TripNumber"]))
        }
    }

    static func alerts(data: AgencyData?) async throws -> [ServiceAlert] {
        let root = J.dict(try await Network.json(url("ServiceUpdate/ServiceAlert/All")))
        return J.list(J.dict(root["Messages"])["Message"]).compactMap { m in
            guard let title = J.str(m["SubjectEnglish"]) else { return nil }
            let lineCodes = J.list(m["Lines"]).compactMap { J.str($0["Code"]) }
            let routeIDs = lineCodes.compactMap { data?.routesByShortName[$0.uppercased()]?.routeID }
            let stopIDs = J.list(m["Stops"]).compactMap { J.str($0["Code"]) }
            let category = J.str(m["Category"])
            let severity: ServiceAlert.Severity = {
                let c = (category ?? "") + " " + (J.str(m["SubCategory"]) ?? "")
                let text = title + " " + c
                if c.localizedCaseInsensitiveContains("Amenity") || c.localizedCaseInsensitiveContains("Elevator") { return .info }
                for word in ["cancel", "suspend", "no train", "no service", "disruption"] where text.localizedCaseInsensitiveContains(word) {
                    return .severe
                }
                if c.localizedCaseInsensitiveContains("Information") { return .info }
                return .warning
            }()
            return ServiceAlert(id: "go:\(J.str(m["Code"]) ?? title)", agencyID: "go", title: title,
                                body: (J.str(m["BodyEnglish"]) ?? "").strippingHTML, routeIDs: routeIDs, stopIDs: stopIDs,
                                start: TransitDates.local(J.str(m["PostedDateTime"]), timeZone: tz), end: nil, url: nil,
                                severity: severity, category: J.str(m["SubCategory"]) ?? category)
        }
    }

    static func liveTrains() async throws -> [LiveVehicle] {
        let root = J.dict(try await Network.json(url("ServiceataGlance/Trains/All")))
        return J.list(J.dict(root["Trips"])["Trip"]).compactMap { t in
            guard let lat = J.dbl(t["Latitude"]), let lon = J.dbl(t["Longitude"]), lat > 0 else { return nil }
            let line = (J.str(t["LineCode"]) ?? "").trimmingCharacters(in: .whitespaces)
            return LiveVehicle(id: "go:\(J.str(t["TripNumber"]) ?? UUID().uuidString)", agencyID: "go",
                               routeID: line, label: J.str(t["Display"]) ?? line,
                               coordinate: .init(latitude: lat, longitude: lon), bearing: J.dbl(t["Course"]),
                               delaySeconds: J.int(t["DelaySeconds"]))
        }
    }
}
