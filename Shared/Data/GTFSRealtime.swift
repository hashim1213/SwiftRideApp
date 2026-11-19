import Foundation

/// A small, dependency-free decoder for the parts of GTFS-Realtime SwiftRide needs.
/// Field numbers follow https://gtfs.org/realtime/reference/ (gtfs-realtime.proto).
enum GTFSRT {

    struct StopTime {
        let stopID: String
        let time: Int64        // unix seconds
        let delay: Int32?
        let skipped: Bool
    }

    struct TripUpdate {
        let tripID: String
        let routeID: String?
        let vehicleID: String?
        let vehicleLabel: String?
        let cancelled: Bool
        let stopTimes: [StopTime]
    }

    struct Alert {
        let id: String
        let header: String
        let description: String
        let routeIDs: [String]
        let stopIDs: [String]
        let start: Int64?
        let end: Int64?
        let url: String?
        let effect: Int?
        let cause: Int?
    }

    struct Vehicle {
        let id: String
        let label: String?
        let tripID: String?
        let routeID: String?
        let lat: Double
        let lon: Double
        let bearing: Double?
    }

    struct Feed {
        var tripUpdates: [TripUpdate] = []
        var alerts: [Alert] = []
        var vehicles: [Vehicle] = []
    }

    // MARK: Protobuf wire reader

    private struct Reader {
        let bytes: UnsafeBufferPointer<UInt8>
        var pos: Int
        let end: Int

        init(_ bytes: UnsafeBufferPointer<UInt8>, start: Int = 0, end: Int? = nil) {
            self.bytes = bytes; pos = start; self.end = end ?? bytes.count
        }

        var atEnd: Bool { pos >= end }

        mutating func varint() throws -> UInt64 {
            var result: UInt64 = 0, shift: UInt64 = 0
            while pos < end {
                let b = bytes[pos]; pos += 1
                result |= UInt64(b & 0x7F) << shift
                if b < 0x80 { return result }
                shift += 7
                if shift > 63 { throw DecodeError.malformed }
            }
            throw DecodeError.truncated
        }

        enum Value { case varint(UInt64), fixed64(UInt64), bytes(Range<Int>), fixed32(UInt32) }

        mutating func next() throws -> (field: Int, value: Value)? {
            guard !atEnd else { return nil }
            let key = try varint()
            let field = Int(key >> 3)
            switch key & 7 {
            case 0: return (field, .varint(try varint()))
            case 1:
                guard pos + 8 <= end else { throw DecodeError.truncated }
                var v: UInt64 = 0
                for i in 0..<8 { v |= UInt64(bytes[pos + i]) << (8 * UInt64(i)) }
                pos += 8; return (field, .fixed64(v))
            case 2:
                let len = Int(try varint())
                guard len >= 0, pos + len <= end else { throw DecodeError.truncated }
                let r = pos..<(pos + len); pos += len; return (field, .bytes(r))
            case 5:
                guard pos + 4 <= end else { throw DecodeError.truncated }
                var v: UInt32 = 0
                for i in 0..<4 { v |= UInt32(bytes[pos + i]) << (8 * UInt32(i)) }
                pos += 4; return (field, .fixed32(v))
            default: throw DecodeError.malformed
            }
        }

        func sub(_ r: Range<Int>) -> Reader { Reader(bytes, start: r.lowerBound, end: r.upperBound) }
        func string(_ r: Range<Int>) -> String {
            String(decoding: UnsafeBufferPointer(rebasing: bytes[r]), as: UTF8.self)
        }
    }

    enum DecodeError: Error { case truncated, malformed }

    // MARK: Decoding

    static func decode(_ data: Data) throws -> Feed {
        try data.withUnsafeBytes { raw -> Feed in
            let buf = raw.bindMemory(to: UInt8.self)
            var r = Reader(buf)
            var feed = Feed()
            while case let (f, v)? = try r.next() {
                guard f == 2, case .bytes(let range) = v else { continue }
                try decodeEntity(r.sub(range), into: &feed)
            }
            return feed
        }
    }

    private static func decodeEntity(_ reader: Reader, into feed: inout Feed) throws {
        var r = reader
        var id = ""
        var tripRange: Range<Int>?, alertRange: Range<Int>?, vehicleRange: Range<Int>?
        var deleted = false
        while case let (f, v)? = try r.next() {
            switch (f, v) {
            case (1, .bytes(let x)): id = r.string(x)
            case (2, .varint(let x)): deleted = x != 0
            case (3, .bytes(let x)): tripRange = x
            case (4, .bytes(let x)): vehicleRange = x
            case (5, .bytes(let x)): alertRange = x
            default: break
            }
        }
        if deleted { return }
        if let tr = tripRange, let tu = try decodeTripUpdate(r.sub(tr)) { feed.tripUpdates.append(tu) }
        if let vr = vehicleRange, let ve = try decodeVehicle(r.sub(vr), entityID: id) { feed.vehicles.append(ve) }
        if let ar = alertRange { feed.alerts.append(try decodeAlert(r.sub(ar), id: id)) }
    }

    private static func decodeTrip(_ reader: Reader) throws -> (trip: String, route: String?, cancelled: Bool) {
        var r = reader; var trip = "", route: String?, rel: UInt64 = 0
        while case let (f, v)? = try r.next() {
            switch (f, v) {
            case (1, .bytes(let x)): trip = r.string(x)
            case (4, .varint(let x)): rel = x
            case (5, .bytes(let x)): route = r.string(x)
            default: break
            }
        }
        return (trip, route?.nilIfEmpty, rel == 3) // 3 = CANCELED
    }

    private static func decodeVehicleDescriptor(_ reader: Reader) throws -> (id: String?, label: String?) {
        var r = reader; var id: String?, label: String?
        while case let (f, v)? = try r.next() {
            switch (f, v) {
            case (1, .bytes(let x)): id = r.string(x)
            case (2, .bytes(let x)): label = r.string(x)
            default: break
            }
        }
        return (id, label)
    }

    private static func decodeTripUpdate(_ reader: Reader) throws -> TripUpdate? {
        var r = reader
        var trip = (trip: "", route: String?.none, cancelled: false)
        var veh: (id: String?, label: String?) = (nil, nil)
        var stops: [StopTime] = []
        while case let (f, v)? = try r.next() {
            guard case .bytes(let x) = v else { continue }
            switch f {
            case 1: trip = try decodeTrip(r.sub(x))
            case 3: veh = try decodeVehicleDescriptor(r.sub(x))
            case 2: if let s = try decodeStopTime(r.sub(x)) { stops.append(s) }
            default: break
            }
        }
        return TripUpdate(tripID: trip.trip, routeID: trip.route, vehicleID: veh.id, vehicleLabel: veh.label,
                          cancelled: trip.cancelled, stopTimes: stops)
    }

    private static func decodeEvent(_ reader: Reader) throws -> (time: Int64?, delay: Int32?) {
        var r = reader; var time: Int64?, delay: Int32?
        while case let (f, v)? = try r.next() {
            guard case .varint(let x) = v else { continue }
            if f == 2 { time = Int64(bitPattern: x) }
            if f == 1 { delay = Int32(truncatingIfNeeded: Int64(bitPattern: x)) }
        }
        return (time, delay)
    }

    private static func decodeStopTime(_ reader: Reader) throws -> StopTime? {
        var r = reader
        var stopID = "", arrival: (Int64?, Int32?) = (nil, nil), departure: (Int64?, Int32?) = (nil, nil), rel: UInt64 = 0
        while case let (f, v)? = try r.next() {
            switch (f, v) {
            case (2, .bytes(let x)): arrival = try decodeEvent(r.sub(x))
            case (3, .bytes(let x)): departure = try decodeEvent(r.sub(x))
            case (4, .bytes(let x)): stopID = r.string(x)
            case (5, .varint(let x)): rel = x
            default: break
            }
        }
        // Riders care when the vehicle leaves; fall back to arrival.
        guard !stopID.isEmpty, let t = departure.0 ?? arrival.0, t > 1_000_000_000, t < 4_000_000_000 else { return nil }
        return StopTime(stopID: stopID, time: t, delay: departure.1 ?? arrival.1, skipped: rel == 1)
    }

    private static func decodeTranslated(_ reader: Reader) throws -> String {
        var r = reader; var best: String?, fallback: String?
        while case let (f, v)? = try r.next() {
            guard f == 1, case .bytes(let x) = v else { continue }
            var t = r.sub(x); var text = "", lang = ""
            while case let (tf, tv)? = try t.next() {
                guard case .bytes(let y) = tv else { continue }
                if tf == 1 { text = t.string(y) }
                if tf == 2 { lang = t.string(y).lowercased() }
            }
            if lang.hasPrefix("en") { best = text }
            if fallback == nil || lang.isEmpty { fallback = text }
        }
        return best ?? fallback ?? ""
    }

    private static func decodeAlert(_ reader: Reader, id: String) throws -> Alert {
        var r = reader
        var header = "", desc = "", url: String?, routes: [String] = [], stops: [String] = []
        var start: Int64?, end: Int64?, effect: Int?, cause: Int?
        while case let (f, v)? = try r.next() {
            switch (f, v) {
            case (1, .bytes(let x)):
                var p = r.sub(x)
                while case let (pf, pv)? = try p.next() {
                    guard case .varint(let t) = pv else { continue }
                    if pf == 1 { start = min(start ?? .max, Int64(t)) }
                    if pf == 2 { end = max(end ?? 0, Int64(t)) }
                }
            case (5, .bytes(let x)):
                var e = r.sub(x)
                while case let (ef, ev)? = try e.next() {
                    guard case .bytes(let y) = ev else { continue }
                    if ef == 2 { routes.append(e.string(y)) }
                    if ef == 5 { stops.append(e.string(y)) }
                    if ef == 4, let route = try decodeTrip(e.sub(y)).route { routes.append(route) }
                }
            case (6, .varint(let x)): cause = Int(x)
            case (7, .varint(let x)): effect = Int(x)
            case (8, .bytes(let x)): url = try decodeTranslated(r.sub(x))
            case (10, .bytes(let x)): header = try decodeTranslated(r.sub(x))
            case (11, .bytes(let x)): desc = try decodeTranslated(r.sub(x))
            default: break
            }
        }
        return Alert(id: id, header: header, description: desc, routeIDs: Array(Set(routes)), stopIDs: Array(Set(stops)),
                     start: start, end: end, url: url?.nilIfEmpty, effect: effect, cause: cause)
    }

    private static func decodeVehicle(_ reader: Reader, entityID: String) throws -> Vehicle? {
        var r = reader
        var trip: (trip: String, route: String?, cancelled: Bool)?
        var veh: (id: String?, label: String?) = (nil, nil)
        var lat: Float?, lon: Float?, bearing: Float?
        while case let (f, v)? = try r.next() {
            guard case .bytes(let x) = v else { continue }
            switch f {
            case 1: trip = try decodeTrip(r.sub(x))
            case 8: veh = try decodeVehicleDescriptor(r.sub(x))
            case 2:
                var p = r.sub(x)
                while case let (pf, pv)? = try p.next() {
                    guard case .fixed32(let bits) = pv else { continue }
                    let fl = Float(bitPattern: bits)
                    if pf == 1 { lat = fl } else if pf == 2 { lon = fl } else if pf == 3 { bearing = fl }
                }
            default: break
            }
        }
        guard let lat, let lon, lat != 0, lon != 0 else { return nil }
        return Vehicle(id: veh.id ?? entityID, label: veh.label, tripID: trip?.trip.nilIfEmpty, routeID: trip?.route,
                       lat: Double(lat), lon: Double(lon), bearing: bearing.map(Double.init))
    }

    // MARK: JSON flavour (Metrolinx publishes GTFS-RT as JSON)

    static func decodeJSON(_ data: Data) throws -> Feed {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DecodeError.malformed }
        var feed = Feed()
        for e in root["entity"] as? [[String: Any]] ?? [] {
            if (e["is_deleted"] as? Bool) == true { continue }
            let id = string(e["id"]) ?? UUID().uuidString
            if let tu = e["trip_update"] as? [String: Any] {
                let trip = tu["trip"] as? [String: Any] ?? [:]
                let veh = tu["vehicle"] as? [String: Any] ?? [:]
                let stops: [StopTime] = (tu["stop_time_update"] as? [[String: Any]] ?? []).compactMap { s in
                    guard let sid = string(s["stop_id"]) else { return nil }
                    let dep = s["departure"] as? [String: Any], arr = s["arrival"] as? [String: Any]
                    guard let t = int64(dep?["time"]) ?? int64(arr?["time"]) else { return nil }
                    return StopTime(stopID: sid, time: t, delay: (int64(dep?["delay"]) ?? int64(arr?["delay"])).map { Int32(truncatingIfNeeded: $0) },
                                    skipped: string(s["schedule_relationship"]) == "SKIPPED")
                }
                feed.tripUpdates.append(TripUpdate(tripID: string(trip["trip_id"]) ?? id, routeID: string(trip["route_id"]),
                                                   vehicleID: string(veh["id"]), vehicleLabel: string(veh["label"]),
                                                   cancelled: string(trip["schedule_relationship"]) == "CANCELED", stopTimes: stops))
            }
            if let v = e["vehicle"] as? [String: Any], let pos = v["position"] as? [String: Any],
               let lat = double(pos["latitude"]), let lon = double(pos["longitude"]) {
                let trip = v["trip"] as? [String: Any] ?? [:]
                let veh = v["vehicle"] as? [String: Any] ?? [:]
                feed.vehicles.append(Vehicle(id: string(veh["id"]) ?? id, label: string(veh["label"]), tripID: string(trip["trip_id"]),
                                             routeID: string(trip["route_id"]), lat: lat, lon: lon, bearing: double(pos["bearing"])))
            }
        }
        return feed
    }

    private static func string(_ v: Any?) -> String? {
        if let s = v as? String { return s.nilIfEmpty }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }
    private static func int64(_ v: Any?) -> Int64? {
        if let n = v as? NSNumber { return n.int64Value }
        if let s = v as? String { return Int64(s) }
        return nil
    }
    private static func double(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }
}
