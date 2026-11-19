import Foundation
import SwiftUI
import CoreLocation
import Combine


class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    // Published properties for state management
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    @Published var locationError: Error?
    
    // Define downtown Winnipeg location (Portage and Main)
    private let winnipegLocation = CLLocation(
        latitude: 49.8951,
        longitude: -97.1384
    )
    
    // We'll keep these for future reference but won't actively use them
    private var locationManager = CLLocationManager()
    private let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyNearestTenMeters
    private let distanceFilter: CLLocationDistance = 10
    
    private override init() {
        super.init()
        // Simply set the downtown location immediately
        self.currentLocation = winnipegLocation
        
        // Set authorization status to authorized since we're bypassing actual location
        self.authorizationStatus = .authorizedWhenInUse
    }
    
    // Simplified setup that just ensures we're using downtown location
    private func setupLocationManager() {
        // No need for actual location manager setup since we're using fixed location
        currentLocation = winnipegLocation
    }
    
    // These methods now just maintain the downtown location
    func requestLocationPermission() {
        // Always grant permission in this testing mode
        authorizationStatus = .authorizedWhenInUse
        currentLocation = winnipegLocation
    }
    
    func startUpdatingLocation() {
        // Always use downtown location
        currentLocation = winnipegLocation
        locationError = nil
    }
    
    func stopUpdatingLocation() {
        // Location stays fixed even when stopped
        currentLocation = winnipegLocation
    }
    
    // CLLocationManagerDelegate methods simplified to maintain fixed location
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Always maintain authorized status
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.authorizationStatus = .authorizedWhenInUse
            self.currentLocation = self.winnipegLocation
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Override with downtown location
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentLocation = self.winnipegLocation
            self.locationError = nil
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Even on error, maintain downtown location
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentLocation = self.winnipegLocation
            self.locationError = nil
        }
    }
}
    
import Foundation
import CoreLocation
import Combine

class BusStopProvider: ObservableObject {
    static let shared = BusStopProvider()
    
    @Published var busStops: [BusStop] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private(set) var locationManager: LocationManager
    private var cancellables = Set<AnyCancellable>()
    private let apiKey = "BfrWUj9_WlAd-YuTLN6v"
    private let session: URLSession
    
    private init() {
        self.locationManager = LocationManager.shared
        
        // Configure URLSession with longer timeout
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: configuration)
        
        setupLocationObserver()
    }
    
    private func setupLocationObserver() {
        locationManager.$currentLocation
            .compactMap { $0 }
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetchBusStops()
            }
            .store(in: &cancellables)
    }
    
    func fetchBusStops(completion: (() -> Void)? = nil) {
        guard let location = locationManager.currentLocation else {
            self.error = "Location not available"
            completion?()
            return
        }
        
        isLoading = true
        error = nil
        
        let radius = UserDefaults.standard.double(forKey: "busStopSearchRadius")
        fetchBusStopsForRegion(lat: location.coordinate.latitude,
                              lon: location.coordinate.longitude,
                              radius: Int(radius),
                              completion: completion)
    }
    
    func fetchBusStopsForRegion(lat: Double, lon: Double, radius: Int, completion: (() -> Void)? = nil) {
        isLoading = true
        error = nil
        
        // Construct URL with v3 API
        var components = URLComponents(string: "https://api.winnipegtransit.com/v2/stops")
        components?.queryItems = [
            URLQueryItem(name: "api-key", value: apiKey),
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lon)),
            URLQueryItem(name: "distance", value: String(radius)),
            URLQueryItem(name: "usage", value: "long")
        ]
        
        guard let url = components?.url else {
            self.error = "Invalid URL"
            self.isLoading = false
            completion?()
            return
        }
        
        print("Fetching bus stops from: \(url.absoluteString)")
        
        let task = session.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.error = "Network error: \(error.localizedDescription)"
                    self?.busStops = []
                    completion?()
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self?.error = "Invalid response"
                    self?.busStops = []
                    completion?()
                    return
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    self?.error = "Server error: \(httpResponse.statusCode)"
                    self?.busStops = []
                    completion?()
                    return
                }
                
                guard let data = data else {
                    self?.error = "No data received"
                    self?.busStops = []
                    completion?()
                    return
                }
                
                
                let parser = XMLParser(data: data)
                let delegate = BusStopParser()
                parser.delegate = delegate
                
                if parser.parse() {
                    self?.busStops = delegate.busStops
                    print("Successfully parsed \(delegate.busStops.count) bus stops")
                } else {
                    self?.error = "Failed to parse response"
                    self?.busStops = []
                }
                
                completion?()
            }
        }
        task.resume()
    }
}

    
    // MARK: - BusStopFeatures Provider
    class BusStopFeatures: ObservableObject {
        @Published var busStopFeatures: [BusStopFeature] = []
        @Published var isLoading = false
        @Published var error: TransitError?
        
        private var stopId: Int
        
        init(stopId: Int) {
            self.stopId = stopId
            fetchBusStopFeatures(stopId: stopId)
        }
        
        func fetchBusStopFeatures(stopId: Int) {
            isLoading = true
            let cacheKey = "features-\(stopId)"
            
            TransitAPIClient.shared.fetch(
                endpoint: .features(stopId: stopId),
                cacheKey: cacheKey
            ) { [weak self] (result: Result<[BusStopFeature], TransitError>) in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    switch result {
                    case .success(let features):
                        self?.busStopFeatures = features
                    case .failure(let error):
                        self?.error = error
                    }
                }
            }
        }
    }
    
    // MARK: - Service Advisory Provider
    class ServiceAdvisoryProvider: ObservableObject {
        @Published var advisories: [ServiceAdvisory] = []
        @Published var isLoading = false
        @Published var error: TransitError?
        
        private var timer: Timer?
        private let refreshInterval: TimeInterval = 300.0 // 5 minutes
        
        init() {
            fetchServiceAdvisories()
            startAutoRefresh()
        }
        
        deinit {
            stopAutoRefresh()
        }
        
        private func startAutoRefresh() {
            timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
                self?.fetchServiceAdvisories()
            }
        }
        
        private func stopAutoRefresh() {
            timer?.invalidate()
            timer = nil
        }
        
        func fetchServiceAdvisories() {
            isLoading = true
            let cacheKey = "advisories-\(Int(Date().timeIntervalSince1970) / 300)" // Cache key changes every 5 minutes
            
            TransitAPIClient.shared.fetch(
                endpoint: .serviceAdvisories,
                cacheKey: cacheKey
            ) { [weak self] (result: Result<[ServiceAdvisory], TransitError>) in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    switch result {
                    case .success(let advisories):
                        self?.advisories = advisories
                    case .failure(let error):
                        self?.error = error
                    }
                }
            }
        }
    }
    
    
  

import Foundation

class BusStopParser: NSObject, XMLParserDelegate {
    var busStops: [BusStop] = []
    private var currentElement = ""
    private var currentKey = ""
    private var currentName = ""
    private var currentNumber = 0
    private var currentDistance = 0.0
    private var currentCrossStreetName = ""
    private var currentCrossStreetKey = ""
    private var currentDirection = ""
    private var currentSide = ""
    private var currentStreetName = ""
    private var currentStreetType = ""
    private var currentUTMX = ""
    private var currentUTMY = ""
    private var currentLatitude = 0.0
    private var currentLongitude = 0.0
    private var isParsingCrossStreet = false
    
    // MARK: - XMLParserDelegate Methods
    func parser(_ parser: XMLParser,
               didStartElement elementName: String,
               namespaceURI: String?,
               qualifiedName qName: String?,
               attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        
        if elementName == "cross-street" {
            isParsingCrossStreet = true
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let data = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !data.isEmpty else { return }
        
        switch currentElement {
        case "key":
            if isParsingCrossStreet {
                currentCrossStreetKey = data
            } else {
                currentKey = data
            }
        case "name":
            if isParsingCrossStreet {
                currentCrossStreetName = data
            } else {
                currentName = data
            }
        case "number":
            currentNumber = Int(data) ?? 0
        case "direction":
            currentDirection = data
        case "side":
            currentSide = data
        case "street":
            currentStreetName = data
        case "type":
            currentStreetType = data
        case "utm-x":
            currentUTMX = data
        case "utm-y":
            currentUTMY = data
        case "latitude":
            currentLatitude = Double(data) ?? 0.0
        case "longitude":
            currentLongitude = Double(data) ?? 0.0
        case "distances":
            currentDistance = Double(data) ?? 0.0
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser,
               didEndElement elementName: String,
               namespaceURI: String?,
               qualifiedName qName: String?) {
        if elementName == "cross-street" {
            isParsingCrossStreet = false
        }
        
        if elementName == "stop" {
            let busStop = BusStop(
                key: currentKey,
                name: currentName,
                number: currentNumber,
                direction: currentDirection,
                side: currentSide,
                streetName: currentStreetName,
                streetType: currentStreetType,
                crossStreetName: currentCrossStreetName,
                utmX: currentUTMX,
                utmY: currentUTMY,
                latitude: currentLatitude,
                longitude: currentLongitude,
                distances: currentDistance
            )
            
            busStops.append(busStop)
            
            // Reset values
            resetCurrentValues()
        }
    }
    
    // MARK: - Helper Methods
    private func resetCurrentValues() {
        currentKey = ""
        currentName = ""
        currentNumber = 0
        currentDirection = ""
        currentSide = ""
        currentStreetName = ""
        currentStreetType = ""
        currentCrossStreetName = ""
        currentCrossStreetKey = ""
        currentUTMX = ""
        currentUTMY = ""
        currentLatitude = 0.0
        currentLongitude = 0.0
        currentDistance = 0.0
        isParsingCrossStreet = false
    }
}




