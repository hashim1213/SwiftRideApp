import Foundation
import CoreLocation

// MARK: - Agency

struct Agency: Identifiable, Hashable {
    enum Source: Hashable {
        /// Winnipeg Transit Open Data API (stops + schedules come from the API).
        case winnipeg
        /// TTC: bundled stops, live predictions from Umo/NextBus, alerts and vehicles from GTFS-RT.
        case ttc
        /// GO Transit: bundled stops, Metrolinx Open Data API for next service, alerts and live trains.
        case metrolinx
        /// Any agency with bundled GTFS stops and open GTFS-Realtime feeds.
        case gtfsRealtime
    }

    enum FeedFormat: Hashable { case protobuf, json }

    let id: String
    let name: String
    let shortName: String
    let brandHex: String
    let source: Source
    let tripUpdates: URL?
    let alerts: URL?
    let vehicles: URL?
    var feedFormat: FeedFormat = .protobuf
    /// Some agencies publish garish primary colours; use the brand colour for every route instead.
    var ignoreRouteColors = false
    let website: URL?

    var hasBundledStops: Bool { source != .winnipeg }
}

enum Secrets {
    // Keys for open-data APIs. These are free developer keys issued to SwiftRide.
    static let winnipegTransitKey = "BfrWUj9_WlAd-YuTLN6v"
    static let metrolinxKey = "30027967"
}

private func u(_ s: String) -> URL? { URL(string: s) }
private func bct(_ op: Int) -> (URL?, URL?, URL?) {
    (u("https://bct.tmix.se/gtfs-realtime/tripupdates.pb?operatorIds=\(op)"),
     u("https://bct.tmix.se/gtfs-realtime/alerts.pb?operatorIds=\(op)"),
     u("https://bct.tmix.se/gtfs-realtime/vehicleupdates.pb?operatorIds=\(op)"))
}

enum Catalog {
    static let metrolinxBase = "https://api.openmetrolinx.com/OpenDataAPI/api/V1"

    static let agencies: [Agency] = {
        let mx = Secrets.metrolinxKey
        let vic = bct(48), kel = bct(47), kam = bct(46), nan = bct(41), fv = bct(13)
        return [
            Agency(id: "wpg", name: "Winnipeg Transit", shortName: "Winnipeg Transit", brandHex: "0060A9", source: .winnipeg,
                   tripUpdates: nil, alerts: nil, vehicles: nil, website: u("https://winnipegtransit.com")),
            Agency(id: "ttc", name: "Toronto Transit Commission", shortName: "TTC", brandHex: "DA251D", source: .ttc,
                   tripUpdates: nil, alerts: u("https://bustime.ttc.ca/gtfsrt/alerts"), vehicles: u("https://bustime.ttc.ca/gtfsrt/vehicles"),
                   website: u("https://www.ttc.ca")),
            Agency(id: "go", name: "GO Transit", shortName: "GO", brandHex: "00853E", source: .metrolinx,
                   tripUpdates: nil, alerts: nil, vehicles: nil, website: u("https://www.gotransit.com")),
            Agency(id: "up", name: "UP Express", shortName: "UP Express", brandHex: "0075D2", source: .gtfsRealtime,
                   tripUpdates: u("\(metrolinxBase)/UP/Gtfs/Feed/TripUpdates?key=\(mx)"), alerts: nil,
                   vehicles: u("\(metrolinxBase)/UP/Gtfs/Feed/VehiclePosition?key=\(mx)"), feedFormat: .json,
                   website: u("https://www.upexpress.com")),
            Agency(id: "yrt", name: "York Region Transit", shortName: "YRT / Viva", brandHex: "0058A9", source: .gtfsRealtime,
                   tripUpdates: u("https://rtu.york.ca/gtfsrealtime/TripUpdates"), alerts: u("https://rtu.york.ca/gtfsrealtime/ServiceAlerts"),
                   vehicles: u("https://rtu.york.ca/gtfsrealtime/VehiclePositions"), website: u("https://www.yrt.ca")),
            Agency(id: "miway", name: "MiWay", shortName: "MiWay", brandHex: "D33517", source: .gtfsRealtime,
                   tripUpdates: u("https://www.miapp.ca/GTFS_RT/TripUpdate/TripUpdates.pb"), alerts: u("https://www.miapp.ca/GTFS_RT/Alerts/Alerts.pb"),
                   vehicles: u("https://www.miapp.ca/GTFS_RT/Vehicle/VehiclePositions.pb"), website: u("https://www.mississauga.ca/miway-transit/")),
            Agency(id: "durham", name: "Durham Region Transit", shortName: "DRT", brandHex: "006633", source: .gtfsRealtime,
                   tripUpdates: u("https://drtonline.durhamregiontransit.com/gtfsrealtime/TripUpdates"), alerts: nil,
                   vehicles: u("https://drtonline.durhamregiontransit.com/gtfsrealtime/VehiclePositions"), website: u("https://www.durhamregiontransit.com")),
            Agency(id: "hsr", name: "Hamilton Street Railway", shortName: "HSR", brandHex: "0067B1", source: .gtfsRealtime,
                   tripUpdates: u("https://opendata.hamilton.ca/GTFS-RT/GTFS_TripUpdates.pb"), alerts: u("https://opendata.hamilton.ca/GTFS-RT/GTFS_ServiceAlerts.pb"),
                   vehicles: u("https://opendata.hamilton.ca/GTFS-RT/GTFS_VehiclePositions.pb"), website: u("https://www.hamilton.ca/hsr")),
            Agency(id: "barrie", name: "Barrie Transit", shortName: "Barrie Transit", brandHex: "006838", source: .gtfsRealtime,
                   tripUpdates: u("https://www.myridebarrie.ca/gtfs/GTFS_TripUpdates.pb"), alerts: u("https://www.myridebarrie.ca/gtfs/GTFS_ServiceAlerts.pb"),
                   vehicles: u("https://www.myridebarrie.ca/gtfs/GTFS_VehiclePositions.pb"), website: u("https://www.barrie.ca/transit")),
            Agency(id: "calgary", name: "Calgary Transit", shortName: "Calgary Transit", brandHex: "C8102E", source: .gtfsRealtime,
                   tripUpdates: u("https://data.calgary.ca/download/gs4m-mdc2/application%2Foctet-stream"),
                   alerts: u("https://data.calgary.ca/download/jhgn-ynqj/application%2Foctet-stream"),
                   vehicles: u("https://data.calgary.ca/download/am7c-qe3u/application%2Foctet-stream"), website: u("https://www.calgarytransit.com")),
            Agency(id: "edmonton", name: "Edmonton Transit Service", shortName: "ETS", brandHex: "005087", source: .gtfsRealtime,
                   tripUpdates: u("https://gtfs.edmonton.ca/TMGTFSRealTimeWebService/TripUpdate/TripUpdates.pb"),
                   alerts: u("https://gtfs.edmonton.ca/TMGTFSRealTimeWebService/Alert/Alerts.pb"),
                   vehicles: u("https://gtfs.edmonton.ca/TMGTFSRealTimeWebService/Vehicle/VehiclePositions.pb"), website: u("https://www.edmonton.ca/ets")),
            Agency(id: "halifax", name: "Halifax Transit", shortName: "Halifax Transit", brandHex: "1D4F91", source: .gtfsRealtime,
                   tripUpdates: u("https://gtfs.halifax.ca/realtime/TripUpdate/TripUpdates.pb"), alerts: u("https://gtfs.halifax.ca/realtime/Alert/Alerts.pb"),
                   vehicles: u("https://gtfs.halifax.ca/realtime/Vehicle/VehiclePositions.pb"), ignoreRouteColors: true, website: u("https://www.halifax.ca/transportation/halifax-transit")),
            Agency(id: "victoria", name: "BC Transit – Victoria", shortName: "BC Transit", brandHex: "0067A5", source: .gtfsRealtime,
                   tripUpdates: vic.0, alerts: vic.1, vehicles: vic.2, website: u("https://www.bctransit.com/victoria")),
            Agency(id: "kelowna", name: "BC Transit – Kelowna", shortName: "BC Transit", brandHex: "0067A5", source: .gtfsRealtime,
                   tripUpdates: kel.0, alerts: kel.1, vehicles: kel.2, website: u("https://www.bctransit.com/kelowna")),
            Agency(id: "bct46", name: "BC Transit – Kamloops", shortName: "BC Transit", brandHex: "0067A5", source: .gtfsRealtime,
                   tripUpdates: kam.0, alerts: kam.1, vehicles: kam.2, website: u("https://www.bctransit.com/kamloops")),
            Agency(id: "bct41", name: "BC Transit – Nanaimo", shortName: "BC Transit", brandHex: "0067A5", source: .gtfsRealtime,
                   tripUpdates: nan.0, alerts: nan.1, vehicles: nan.2, website: u("https://www.bctransit.com/nanaimo")),
            Agency(id: "bct13", name: "BC Transit – Fraser Valley", shortName: "BC Transit", brandHex: "0067A5", source: .gtfsRealtime,
                   tripUpdates: fv.0, alerts: fv.1, vehicles: fv.2, website: u("https://www.bctransit.com/fraser-valley")),
            Agency(id: "ltc", name: "London Transit Commission", shortName: "LTC", brandHex: "00539B", source: .gtfsRealtime,
                   tripUpdates: u("http://gtfs.ltconline.ca/TripUpdate/TripUpdates.pb"), alerts: u("http://gtfs.ltconline.ca/Alert/Alerts.pb"),
                   vehicles: u("http://gtfs.ltconline.ca/Vehicle/VehiclePositions.pb"), website: u("https://www.londontransit.ca")),
            Agency(id: "kingston", name: "Kingston Transit", shortName: "Kingston Transit", brandHex: "BE202E", source: .gtfsRealtime,
                   tripUpdates: u("https://api.cityofkingston.ca/gtfs-realtime/tripupdates.pb"), alerts: u("https://api.cityofkingston.ca/gtfs-realtime/alerts.pb"),
                   vehicles: u("https://api.cityofkingston.ca/gtfs-realtime/vehicleupdates.pb"), website: u("https://www.kingstontransit.ca")),
            Agency(id: "windsor", name: "Transit Windsor", shortName: "Transit Windsor", brandHex: "1799D3", source: .gtfsRealtime,
                   tripUpdates: u("https://windsor.mapstrat.com/current/gtfrealtime_TripUpdates.bin"),
                   alerts: u("https://windsor.mapstrat.com/current/gtfrealtime_ServiceAlerts.bin"),
                   vehicles: u("https://windsor.mapstrat.com/current/gtfrealtime_VehiclePositions.bin"), website: u("https://www.citywindsor.ca/residents/transit-windsor")),
        ]
    }()

    static let agencyByID: [String: Agency] = Dictionary(uniqueKeysWithValues: agencies.map { ($0.id, $0) })
    static func agency(_ id: String) -> Agency? { agencyByID[id] }

    static let cities: [City] = [
        City(id: "winnipeg", name: "Winnipeg", province: "MB", lat: 49.8951, lon: -97.1384, radiusKm: 30, agencyIDs: ["wpg"]),
        City(id: "toronto", name: "Toronto", province: "ON", lat: 43.6532, lon: -79.3832, radiusKm: 28, agencyIDs: ["ttc", "go", "up", "yrt", "miway", "durham"]),
        City(id: "york", name: "York Region", province: "ON", lat: 43.8561, lon: -79.3370, radiusKm: 30, agencyIDs: ["yrt", "go", "ttc"]),
        City(id: "mississauga", name: "Mississauga", province: "ON", lat: 43.5890, lon: -79.6441, radiusKm: 22, agencyIDs: ["miway", "go", "up", "ttc"]),
        City(id: "durham", name: "Durham Region", province: "ON", lat: 43.8971, lon: -78.8658, radiusKm: 35, agencyIDs: ["durham", "go"]),
        City(id: "hamilton", name: "Hamilton", province: "ON", lat: 43.2557, lon: -79.8711, radiusKm: 25, agencyIDs: ["hsr", "go"]),
        City(id: "barrie", name: "Barrie", province: "ON", lat: 44.3894, lon: -79.6903, radiusKm: 15, agencyIDs: ["barrie", "go"]),
        City(id: "london", name: "London", province: "ON", lat: 42.9849, lon: -81.2453, radiusKm: 18, agencyIDs: ["ltc"]),
        City(id: "kingston", name: "Kingston", province: "ON", lat: 44.2312, lon: -76.4860, radiusKm: 15, agencyIDs: ["kingston"]),
        City(id: "windsor", name: "Windsor", province: "ON", lat: 42.3149, lon: -83.0364, radiusKm: 18, agencyIDs: ["windsor"]),
        City(id: "calgary", name: "Calgary", province: "AB", lat: 51.0447, lon: -114.0719, radiusKm: 30, agencyIDs: ["calgary"]),
        City(id: "edmonton", name: "Edmonton", province: "AB", lat: 53.5461, lon: -113.4938, radiusKm: 30, agencyIDs: ["edmonton"]),
        City(id: "victoria", name: "Victoria", province: "BC", lat: 48.4284, lon: -123.3656, radiusKm: 30, agencyIDs: ["victoria"]),
        City(id: "kelowna", name: "Kelowna", province: "BC", lat: 49.8880, lon: -119.4960, radiusKm: 30, agencyIDs: ["kelowna"]),
        City(id: "kamloops", name: "Kamloops", province: "BC", lat: 50.6745, lon: -120.3273, radiusKm: 20, agencyIDs: ["bct46"]),
        City(id: "nanaimo", name: "Nanaimo", province: "BC", lat: 49.1659, lon: -123.9401, radiusKm: 20, agencyIDs: ["bct41"]),
        City(id: "fraservalley", name: "Abbotsford & Chilliwack", province: "BC", lat: 49.0800, lon: -122.1500, radiusKm: 35, agencyIDs: ["bct13"]),
        City(id: "halifax", name: "Halifax", province: "NS", lat: 44.6488, lon: -63.5752, radiusKm: 30, agencyIDs: ["halifax"]),
    ]

    static func city(_ id: String) -> City? { cities.first { $0.id == id } }

    /// Every city whose service area covers this point, closest first.
    static func cities(near coordinate: CLLocationCoordinate2D) -> [City] {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return cities
            .map { ($0, $0.location.distance(from: here)) }
            .filter { $0.1 <= $0.0.radiusKm * 1000 }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    static func nearestCity(to coordinate: CLLocationCoordinate2D) -> (City, CLLocationDistance) {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return cities.map { ($0, $0.location.distance(from: here)) }.min { $0.1 < $1.1 }!
    }

    /// Agencies that could have stops around this point.
    static func agencies(near coordinate: CLLocationCoordinate2D) -> [Agency] {
        var seen = Set<String>()
        return cities(near: coordinate).flatMap(\.agencyIDs).filter { seen.insert($0).inserted }.compactMap { agencyByID[$0] }
    }

    static let provinceNames: [String: String] = [
        "BC": "British Columbia", "AB": "Alberta", "MB": "Manitoba", "ON": "Ontario", "NS": "Nova Scotia",
    ]
}

// MARK: - City

struct City: Identifiable, Hashable {
    let id: String
    let name: String
    let province: String
    let lat: Double
    let lon: Double
    let radiusKm: Double
    let agencyIDs: [String]

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lon) }
    var agencies: [Agency] { agencyIDs.compactMap(Catalog.agency) }
}
