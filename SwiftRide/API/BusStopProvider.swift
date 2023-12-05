import Foundation
import SwiftUI
import CoreLocation

// LocationManager Singleton
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    static let shared = LocationManager()
    
    @Published var currentLocation: CLLocation?
    private var locationManager = CLLocationManager()
    
    private override init() {
        super.init()
        self.locationManager.delegate = self
        self.locationManager.requestWhenInUseAuthorization()
        self.locationManager.startUpdatingLocation()
        // Set the currentLocation to Winnipeg for debugging
       // self.currentLocation = CLLocation(latitude: 49.8943, longitude: -97.1388) // Winnipeg coordinates
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            currentLocation = location
        }
    }
}


// BusStopProvider Singleton
class BusStopProvider: ObservableObject {
    static let shared = BusStopProvider()
    @Published var isLoading = false
    @Published var busStops: [BusStop] = []
    var locationManager: LocationManager
    
    private init() {
        self.locationManager = LocationManager.shared
        fetchBusStops()
    }
    
    func fetchBusStops(completion: (() -> Void)? = nil) {
        isLoading = true // Start loading
        
        guard let location = locationManager.currentLocation else {
            print("Current location is not available.")
            isLoading = false
            completion?()
            return
        }
        
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        
        print("Fetching bus stops for Latitude: \(lat), Longitude: \(lon)")
        
        let urlString = "https://api.winnipegtransit.com/v3/stops?usage=long&lon=\(lon)&lat=\(lat)&distance=1000&api-key=BfrWUj9_WlAd-YuTLN6v"
        
        if let url = URL(string: urlString) {
            URLSession.shared.dataTask(with: url) { (data, response, error) in
                if let data = data {
                    let parser = XMLParser(data: data)
                    let delegate = BusStopParser()
                    parser.delegate = delegate
                    parser.parse()
                    DispatchQueue.main.async { [weak self] in
                        self?.busStops.removeAll()  // Clear the array
                        self?.busStops = delegate.busStops
                        self?.isLoading = false // Stop loading when data is fetched
                        completion?()
                    }
                } else if let error = error {
                    print("Error fetching bus stops: \(error)")
                    self.isLoading = false
                    completion?()
                }
            }
            .resume()
        }
    }
}

extension BusStopProvider {
    
    func fetchBusStopsForRegion(lat: Double, lon: Double, radius: Int, completion: (() -> Void)? = nil) {
      
        
        isLoading = true
        let urlString = "https://api.winnipegtransit.com/v3/stops?usage=long&lon=\(lon)&lat=\(lat)&distance=\(radius)&api-key=BfrWUj9_WlAd-YuTLN6v"

        if let url = URL(string: urlString) {
            URLSession.shared.dataTask(with: url) { (data, response, error) in
                if let data = data {
                    
                    let parser = XMLParser(data: data)
                    let delegate = BusStopParser()
                    parser.delegate = delegate
                    parser.parse()
                    DispatchQueue.main.async { [weak self] in
                        self?.busStops.removeAll()  // Clear the array
                        self?.busStops = delegate.busStops
                        self?.isLoading = false // Stop loading when data is fetched
                        completion?()
                    }
                }
            }
            .resume()
        }
    }
}


class BusStopParser: NSObject, XMLParserDelegate {
    var busStops: [BusStop] = []
    var currentElement: String = ""
    var currentKey: String = ""
    var currentName: String = ""
    var currentNumber: Int = 0
    var currentDistance: Double = 0.0
    var currentCrossStreetName: String = ""
    var currentCrossStreetKey: String = ""
    var currentDirection: String = ""
    var currentSide: String = ""
    var currentStreetName: String = ""
    var currentStreetType: String = ""
    var currentUTMX: String = ""
    var currentUTMY: String = ""
    var currentLatitude: Double = 0.0
    var currentLongitude: Double = 0.0
    var isParsingCrossStreet = false
    //bus stop features

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        
        if elementName == "cross-street" {
                  isParsingCrossStreet = true  // Set the flag to true
              }
          
        
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let data = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        
        if !data.isEmpty {
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
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "cross-street" {
            isParsingCrossStreet = false  // Set the flag to false
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
   
        }
    }
}
