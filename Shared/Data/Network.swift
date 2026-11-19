import Foundation

enum TransitError: LocalizedError, Equatable {
    case offline, badResponse(Int), decoding, unavailable

    var errorDescription: String? {
        switch self {
        case .offline: return "You appear to be offline."
        case .badResponse(let code): return "The transit agency's server returned an error (\(code))."
        case .decoding: return "We couldn't read the agency's data."
        case .unavailable: return "Live info isn't available for this stop right now."
        }
    }
}

enum Network {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 45
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpAdditionalHeaders = ["User-Agent": "SwiftRide/4.0 (iOS; transit app)", "Accept-Encoding": "gzip, deflate, br"]
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    static func data(_ url: URL) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw TransitError.badResponse(http.statusCode)
            }
            return data
        } catch let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(e.code) {
            throw TransitError.offline
        }
    }

    static func json(_ url: URL) async throws -> Any {
        let d = try await data(url)
        guard let obj = try? JSONSerialization.jsonObject(with: d) else { throw TransitError.decoding }
        return obj
    }
}

/// Lenient accessors for the loosely-typed JSON several agencies publish
/// (numbers as strings, single objects where arrays are expected, and so on).
enum J {
    static func str(_ v: Any?) -> String? {
        switch v {
        case let s as String: return s.nilIfEmpty
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }
    static func int(_ v: Any?) -> Int? { str(v).flatMap { Int($0) ?? Double($0).map { Int($0) } } }
    static func dbl(_ v: Any?) -> Double? { str(v).flatMap(Double.init) }
    static func bool(_ v: Any?) -> Bool { (v as? Bool) ?? (str(v)?.lowercased() == "true") }
    static func dict(_ v: Any?) -> [String: Any] { v as? [String: Any] ?? [:] }
    /// Accepts a single object or an array of objects.
    static func list(_ v: Any?) -> [[String: Any]] {
        if let a = v as? [[String: Any]] { return a }
        if let d = v as? [String: Any] { return [d] }
        return []
    }
}

enum TransitDates {
    private static var cache: [String: DateFormatter] = [:]
    private static let lock = NSLock()

    /// Parses agency-local timestamps such as "2026-11-18 20:17:00" or "2026-11-18T20:17:00".
    static func local(_ s: String?, timeZone: String) -> Date? {
        guard var s, !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: "T", with: " ")
        if let dot = s.firstIndex(of: ".") { s = String(s[..<dot]) }
        lock.lock(); defer { lock.unlock() }
        let f: DateFormatter
        if let c = cache[timeZone] { f = c } else {
            f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f.timeZone = TimeZone(identifier: timeZone)
            cache[timeZone] = f
        }
        return f.date(from: String(s.prefix(19)))
    }
}

extension String {
    /// Removes HTML tags/entities some agencies embed in alert text.
    var strippingHTML: String {
        guard contains("<") || contains("&") else { return trimmingCharacters(in: .whitespacesAndNewlines) }
        var s = replacingOccurrences(of: "<br\\s*/?>|</p>|</li>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (k, v) in ["&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&rsquo;": "’", "&lt;": "<", "&gt;": ">"] {
            s = s.replacingOccurrences(of: k, with: v)
        }
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
