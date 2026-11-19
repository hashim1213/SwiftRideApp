import Foundation
import SwiftUI

class ScheduledStopParser: NSObject, XMLParserDelegate {
    var scheduledStops: [ScheduledStop] = []
    var currentElement: String = ""
    var currentKey: String = ""
    var currentNumber: String = ""
    var currentScheduledArrival: String = ""
    var currentEstimatedArrival: String = ""
    var currentVariantName: String = ""
    var currentBikeRack: Bool = false
    var currentEasyAccess: Bool = false
    var currentWifi: Bool = false
    var minutesToScheduledArrival: Int?
    var minutesToEstimatedArrival: Int?
    var isWithinArrivalTag: Bool = false
    
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "arrival" {
            isWithinArrivalTag = true
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let data = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !data.isEmpty {
            switch currentElement {
            case "key":
                currentKey = data
            case "number":
                currentNumber = data
            case "scheduled":
                if isWithinArrivalTag {
                    currentScheduledArrival = data
                }
            case "estimated":
                if isWithinArrivalTag {
                    currentEstimatedArrival = data
                }
            case "name":
                currentVariantName = data  // assuming this is within a "variant" tag
            case "bike-rack":
                currentBikeRack = (data == "true")
            case "easy-access":
                currentEasyAccess = (data == "true")
            case "wifi":
                currentWifi = (data == "true")
            default:
                break
            }
        }
    }
    
    // Inside ScheduledStopParser class
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "arrival" {
            isWithinArrivalTag = false
        }
        
        if elementName == "scheduled-stop" {
            
            let currentDate = Date()
            let timeZone = TimeZone(identifier: "America/Winnipeg")!
            let secondsFromGMT = timeZone.secondsFromGMT(for: currentDate)
            let localCurrentDate = currentDate.addingTimeInterval(TimeInterval(secondsFromGMT))
            
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime]
            
            let scheduledDate: Date? = dateFormatter.date(from: currentScheduledArrival + "Z")
            let estimatedDate: Date? = dateFormatter.date(from: currentEstimatedArrival + "Z")
            
            var minutesToScheduled: Int? = nil
            var minutesToEstimated: Int? = nil
            
            if let scheduledDate = scheduledDate {
                minutesToScheduled = Calendar.current.dateComponents([.minute], from: localCurrentDate, to: scheduledDate).minute
            }
            
            if let estimatedDate = estimatedDate {
                minutesToEstimated = Calendar.current.dateComponents([.minute], from: localCurrentDate, to: estimatedDate).minute
            }
            
            let scheduledStop = ScheduledStop(
                key: currentKey,
                number: currentNumber,
                scheduledArrival: scheduledDate != nil ? currentScheduledArrival : "N/A",
                estimatedArrival: estimatedDate != nil ? currentEstimatedArrival : "N/A",
                variantName: currentVariantName,
                bikeRack: currentBikeRack,
                easyAccess: currentEasyAccess,
                wifi: currentWifi,
                minutesToScheduledArrival: minutesToScheduled ?? -1,  // Use -1 to indicate N/A
                minutesToEstimatedArrival: minutesToEstimated ?? -1
            )
            
            scheduledStops.append(scheduledStop)
        }
    }
}

import Foundation
import SwiftUI

class ScheduledStopProvider: ObservableObject {
    @Published var scheduledStops: [ScheduledStop] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let stopId: Int
    private let apiKey = "BfrWUj9_WlAd-YuTLN6v"
    private var timer: Timer?
    
    init(stopId: Int) {
        self.stopId = stopId
        fetchScheduledStops()
        startAutoRefresh()
    }
    
    deinit {
        stopAutoRefresh()
    }
    
    private func startAutoRefresh() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.fetchScheduledStops()
        }
    }
    
    private func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "America/Winnipeg")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }
    
    func fetchScheduledStops() {
        isLoading = true
        error = nil
        
        let startTime = formatDate(Date())
        
        var components = URLComponents(string: "https://api.winnipegtransit.com/v2/stops/\(stopId)/schedule")
        components?.queryItems = [
            URLQueryItem(name: "api-key", value: apiKey),
            URLQueryItem(name: "start", value: startTime)
        ]
        
        guard let url = components?.url else {
            self.error = "Invalid URL"
            self.isLoading = false
            return
        }
        
        print("Fetching schedule from: \(url.absoluteString)")
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.error = error.localizedDescription
                    self?.isLoading = false
                    return
                }
                
                guard let data = data else {
                    self?.error = "No data received"
                    self?.isLoading = false
                    return
                }
                
                if let responseString = String(data: data, encoding: .utf8) {
                    print("API Response: \(responseString)")
                }
                
                let parser = XMLParser(data: data)
                let delegate = ScheduledStopParser()
                parser.delegate = delegate
                
                if parser.parse() {
                    self?.scheduledStops = delegate.scheduledStops
                        .sorted { $0.scheduledArrival < $1.scheduledArrival }
                    print("Parsed \(delegate.scheduledStops.count) scheduled stops")
                } else {
                    self?.error = "Failed to parse schedule data"
                }
                
                self?.isLoading = false
            }
        }.resume()
    }
}
