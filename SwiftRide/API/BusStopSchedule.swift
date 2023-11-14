import Foundation
import SwiftUI

// Create ScheduledStopProvider
class ScheduledStopProvider: ObservableObject {
    @Published var scheduledStops: [ScheduledStop] = []
    var stopId: Int
    var timer: Timer?
    
    init(stopId: Int) {
        self.stopId = stopId
        fetchScheduledStops()
        
        // Schedule a timer to refresh the data every 30 seconds
       // self.timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
           // self.fetchScheduledStops()
       // }
    }
    
   // deinit {
       //   self.timer?.invalidate()
     // }
    
    func fetchScheduledStops() {
        let apiKey = "BfrWUj9_WlAd-YuTLN6v"
        
        // Get current date and time
        let now = Date()
        
        // Format date and time
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        let startTime = dateFormatter.string(from: now)
        
        // Create the URL string
        let urlString = "https://api.winnipegtransit.com/v2/stops/\(stopId)/schedule?start=\(startTime)&end=&api-key=\(apiKey)"
        
        if let url = URL(string: urlString) {
            URLSession.shared.dataTask(with: url) { (data, response, error) in
                if let data = data {
                    //debug
                   // print(String(data: data, encoding: .utf8) ?? "Data is not utf8")
                    let parser = XMLParser(data: data)
                    let delegate = ScheduledStopParser()
                    parser.delegate = delegate
                    parser.parse()
                    DispatchQueue.main.async {
                        let uniqueStops = Array(Set(delegate.scheduledStops))
                                // Then sort the stops if needed
                self.scheduledStops = uniqueStops.sorted { $0.scheduledArrival < $1.scheduledArrival }
                      
                        //print("Scheduled Stops: \(self.scheduledStops)")
                    }
                }
            }
            .resume()
        }
    }
}

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
