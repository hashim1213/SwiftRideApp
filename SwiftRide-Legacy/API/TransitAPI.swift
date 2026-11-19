//
//  TransitAPI.swift
//  SwiftRide
//
//  Created by Hashim Farooq on 2024-10-28.
//

import Foundation
import Foundation
import CoreData

// MARK: - API Configuration
enum TransitAPI {
    static let baseURL = "https://api.winnipegtransit.com"
    static let version = "v2"
    static let apiKey = "BfrWUj9_WlAd-YuTLN6v"
    
    enum Endpoint {
        case stops(lat: Double, lon: Double, radius: Int)
        case schedule(stopId: Int)
        case features(stopId: Int)
        case serviceAdvisories
        
        var path: String {
            switch self {
            case .stops:
                return "/stops"
            case .schedule(let stopId):
                return "/stops/\(stopId)/schedule"
            case .features(let stopId):
                return "/stops/\(stopId)/features"
            case .serviceAdvisories:
                return "/service-advisories"
            }
        }
        
        var queryItems: [URLQueryItem] {
            var items = [URLQueryItem(name: "api-key", value: TransitAPI.apiKey)]
            
            switch self {
            case .stops(let lat, let lon, let radius):
                items += [
                    URLQueryItem(name: "lat", value: String(lat)),
                    URLQueryItem(name: "lon", value: String(lon)),
                    URLQueryItem(name: "distance", value: String(radius)),
                    URLQueryItem(name: "usage", value: "long")
                ]
            case .schedule:
                let formatter = ISO8601DateFormatter()
                items += [
                    URLQueryItem(name: "start", value: formatter.string(from: Date()))
                ]
            default:
                break
            }
            
            return items
        }
    }
}

// MARK: - API Error Types
enum TransitError: Error {
    case networkError(Error)
    case invalidResponse
    case invalidData
    case parsingError
    case offline
    case serverError(Int)
    
    var localizedDescription: String {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidData:
            return "Invalid data received"
        case .parsingError:
            return "Error parsing response"
        case .offline:
            return "No internet connection"
        case .serverError(let code):
            return "Server error: \(code)"
        }
    }
}

// MARK: - Network Reachability
class NetworkMonitor {
    static let shared = NetworkMonitor()
    private var reachability: NetworkReachability?
    
    @Published private(set) var isConnected = true
    
    init() {
        setupReachability()
    }
    
    private func setupReachability() {
        do {
            reachability = try NetworkReachability()
            try reachability?.startNotifier()
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(reachabilityChanged),
                name: .reachabilityChanged,
                object: reachability
            )
        } catch {
            print("Could not start reachability monitor")
        }
    }
    
    @objc private func reachabilityChanged() {
        isConnected = reachability?.connection != .unavailable
    }
}

// MARK: - API Client
class TransitAPIClient {
    static let shared = TransitAPIClient()
    
    private let session: URLSession
    private let cache: TransitDataCache
    private let networkMonitor: NetworkMonitor
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 30
        
        self.session = URLSession(configuration: configuration)
        self.cache = TransitDataCache()
        self.networkMonitor = .shared
    }
    
    func fetch<T: Codable>(
        endpoint: TransitAPI.Endpoint,
        cacheKey: String? = nil,
        completion: @escaping (Result<T, TransitError>) -> Void
    ) {
        // Check cache first
        if let key = cacheKey, let cachedData: T = cache.retrieve(forKey: key) {
            completion(.success(cachedData))
            
            // If offline, return cached data only
            guard networkMonitor.isConnected else {
                return
            }
        }
        
        // Construct URL
        var components = URLComponents(string: TransitAPI.baseURL + "/" + TransitAPI.version + endpoint.path)
        components?.queryItems = endpoint.queryItems
        
        guard let url = components?.url else {
            completion(.failure(.invalidResponse))
            return
        }
        
        let task = session.dataTask(with: url) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(.serverError(httpResponse.statusCode)))
                return
            }
            
            guard let data = data else {
                completion(.failure(.invalidData))
                return
            }
            
            // Parse XML or JSON based on response type
            if httpResponse.mimeType == "application/xml" {
                self?.parseXMLResponse(data, cacheKey: cacheKey, completion: completion)
            } else {
                self?.parseJSONResponse(data, cacheKey: cacheKey, completion: completion)
            }
        }
        task.resume()
    }
    
    private func parseXMLResponse<T: Codable>(
        _ data: Data,
        cacheKey: String?,
        completion: @escaping (Result<T, TransitError>) -> Void
    ) {
        let parser = XMLParser(data: data)
        let delegate = TransitXMLParserDelegate<T>()
        parser.delegate = delegate
        
        if parser.parse(), let result = delegate.result as? T {
            if let key = cacheKey {
                cache.store(result, forKey: key)
            }
            completion(.success(result))
        } else {
            completion(.failure(.parsingError))
        }
    }
    
    private func parseJSONResponse<T: Codable>(
        _ data: Data,
        cacheKey: String?,
        completion: @escaping (Result<T, TransitError>) -> Void
    ) {
        do {
            let decoder = JSONDecoder()
            let result = try decoder.decode(T.self, from: data)
            if let key = cacheKey {
                cache.store(result, forKey: key)
            }
            completion(.success(result))
        } catch {
            completion(.failure(.parsingError))
        }
    }
}

// MARK: - Cache Manager
class TransitDataCache {
    private let cache = NSCache<NSString, AnyObject>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    init() {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = urls[0].appendingPathComponent("TransitCache")
        
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func store<T: Encodable>(_ object: T, forKey key: String) {
        // Memory Cache
        cache.setObject(object as AnyObject, forKey: key as NSString)
        
        // Disk Cache
        let url = cacheDirectory.appendingPathComponent(key)
        do {
            let data = try JSONEncoder().encode(object)
            try data.write(to: url)
        } catch {
            print("Failed to cache data: \(error)")
        }
    }
    
    func retrieve<T: Codable>(forKey key: String) -> T? {
        // Check Memory Cache
        if let object = cache.object(forKey: key as NSString) as? T {
            return object
        }
        
        // Check Disk Cache
        let url = cacheDirectory.appendingPathComponent(key)
        do {
            let data = try Data(contentsOf: url)
            let object = try JSONDecoder().decode(T.self, from: data)
            cache.setObject(object as AnyObject, forKey: key as NSString)
            return object
        } catch {
            return nil
        }
    }
    
    func clearCache() {
        cache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}

import Foundation
import Network

// MARK: - Network Reachability
extension Notification.Name {
    static let reachabilityChanged = Notification.Name("ReachabilityChanged")
}

class NetworkReachability {
    enum Connection {
        case wifi
        case cellular
        case ethernet
        case unavailable
    }
    
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "NetworkReachability")
    
    var connection: Connection {
        guard let currentPath = currentPath else {
            return .unavailable
        }
        
        if currentPath.usesInterfaceType(.wifi) {
            return .wifi
        } else if currentPath.usesInterfaceType(.cellular) {
            return .cellular
        } else if currentPath.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else {
            return .unavailable
        }
    }
    
    private var currentPath: NWPath?
    
    init() throws {
        monitor = NWPathMonitor()
        
        monitor.pathUpdateHandler = { [weak self] path in
            self?.currentPath = path
            NotificationCenter.default.post(name: .reachabilityChanged, object: nil)
        }
        monitor.start(queue: queue)
    }
    
    func startNotifier() throws {
        // Already started in init
    }
}

import Foundation

class TransitXMLParserDelegate<T>: NSObject, XMLParserDelegate {
    var result: Any?
    private var currentElement = ""
    private var elementStack: [String] = []
    private var buffer = ""
    private var currentItem: [String: Any] = [:]
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        elementStack.append(elementName)
        currentElement = elementName
        buffer = ""
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmedBuffer = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !trimmedBuffer.isEmpty {
            currentItem[elementName] = trimmedBuffer
        }
        
        if elementName == getRootElementName() {
            handleCompletedItem()
        }
        
        if let lastElement = elementStack.last, lastElement == elementName {
            elementStack.removeLast()
        }
        
        buffer = ""
    }
    
    private func getRootElementName() -> String {
        switch T.self {
        case is [BusStop].Type:
            return "stop"
        case is [ScheduledStop].Type:
            return "scheduled-stop"
        case is [ServiceAdvisory].Type:
            return "service-advisory"
        case is [BusStopFeature].Type:
            return "stop-feature"
        default:
            return ""
        }
    }
    
    private func handleCompletedItem() {
        switch T.self {
        case is [BusStop].Type:
            if let stop = BusStop.fromXMLDictionary(currentItem) {
                var stops = (result as? [BusStop]) ?? []
                stops.append(stop)
                result = stops
            }
        case is [ScheduledStop].Type:
            if let stop = ScheduledStop.fromXMLDictionary(currentItem) {
                var stops = (result as? [ScheduledStop]) ?? []
                stops.append(stop)
                result = stops
            }
        case is [ServiceAdvisory].Type:
            if let advisory = ServiceAdvisory.fromXMLDictionary(currentItem) {
                var advisories = (result as? [ServiceAdvisory]) ?? []
                advisories.append(advisory)
                result = advisories
            }
        case is [BusStopFeature].Type:
            if let feature = BusStopFeature.fromXMLDictionary(currentItem) {
                var features = (result as? [BusStopFeature]) ?? []
                features.append(feature)
                result = features
            }
        default:
            break
        }
        
        currentItem.removeAll()
    }
}


// Model Initializers
extension BusStop {
    init?(from dict: [String: Any]) {
        guard let number = dict["number"] as? String,
              let name = dict["name"] as? String else {
            return nil
        }
        
        self.key = dict["key"] as? String ?? ""
        self.name = name
        self.number = Int(number) ?? 0
        self.direction = dict["direction"] as? String ?? ""
        self.side = dict["side"] as? String ?? ""
        self.streetName = dict["street"] as? String ?? ""
        self.streetType = dict["type"] as? String ?? ""
        self.crossStreetName = dict["cross-street-name"] as? String ?? ""
        self.utmX = dict["utm-x"] as? String ?? ""
        self.utmY = dict["utm-y"] as? String ?? ""
        self.latitude = Double(dict["latitude"] as? String ?? "") ?? 0.0
        self.longitude = Double(dict["longitude"] as? String ?? "") ?? 0.0
        self.distances = Double(dict["distances"] as? String ?? "") ?? 0.0
    }
}

extension ScheduledStop {
    init?(from dict: [String: Any]) {
        guard let key = dict["key"] as? String,
              let number = dict["number"] as? String else {
            return nil
        }
        
        self.key = key
        self.number = number
        self.scheduledArrival = dict["scheduled"] as? String ?? ""
        self.estimatedArrival = dict["estimated"] as? String ?? ""
        self.variantName = dict["variant-name"] as? String ?? ""
        self.bikeRack = (dict["bike-rack"] as? String) == "true"
        self.easyAccess = (dict["easy-access"] as? String) == "true"
        self.wifi = (dict["wifi"] as? String) == "true"
        
        // Calculate minutes to arrival
        let dateFormatter = ISO8601DateFormatter()
        if let scheduledDate = dateFormatter.date(from: self.scheduledArrival) {
            self.minutesToScheduledArrival = Calendar.current.dateComponents([.minute], from: Date(), to: scheduledDate).minute ?? 0
        } else {
            self.minutesToScheduledArrival = -1
        }
        
        if let estimatedDate = dateFormatter.date(from: self.estimatedArrival) {
            self.minutesToEstimatedArrival = Calendar.current.dateComponents([.minute], from: Date(), to: estimatedDate).minute ?? 0
        } else {
            self.minutesToEstimatedArrival = -1
        }
    }
}

extension ServiceAdvisory {
    init?(from dict: [String: Any]) {
        guard let id = dict["key"] as? String else {
            return nil
        }
        
        self.id = id
        self.priority = Int(dict["priority"] as? String ?? "0") ?? 0
        self.title = dict["title"] as? String ?? ""
        self.body = dict["body"] as? String ?? ""
        self.category = dict["category"] as? String ?? ""
        
        if let updatedAtString = dict["updated-at"] as? String {
            self.updatedAt = ISO8601DateFormatter().date(from: updatedAtString) ?? Date()
        } else {
            self.updatedAt = Date()
        }
    }
}

extension BusStopFeature {
    init?(from dict: [String: Any]) {
        guard let name = dict["name"] as? String else {
            return nil
        }
        
        self.name = name
        self.count = Int(dict["count"] as? String ?? "0") ?? 0
    }
}
