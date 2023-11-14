//  BusStopFeatures.swift
//  SwiftRide
//
//  Created by Hashim Farooq on 2023-10-23.
//

import Foundation
import SwiftUI
import CoreLocation

class BusStopFeatures: ObservableObject {
    @Published var busStopFeatures: [BusStopFeature] = [] // Updated to hold features
    var stopId: Int
    private var isFetching = false
    
    // Cache to store fetched features
    private static var featuresCache = [Int: [BusStopFeature]]()
    
    // Added error state
    @Published var error: Error?
    
    init(stopId: Int) {
        self.stopId = stopId
        
        // Check if features for this stopId are already cached
        if let cachedFeatures = BusStopFeatures.featuresCache[stopId] {
            self.busStopFeatures = cachedFeatures
        } else {
            fetchBusStopFeatures(stopId: stopId)
        }
    }
    
    func fetchBusStopFeatures(stopId: Int) {
        // Prevent multiple fetch requests for the same stopId
        guard !isFetching else { return }
        
        // Check again if the features are already cached
        if let cachedFeatures = BusStopFeatures.featuresCache[stopId] {
            self.busStopFeatures = cachedFeatures
            return
        }
        
        isFetching = true
        
        let apiKey = "BfrWUj9_WlAd-YuTLN6v" // Consider fetching this securely
        let urlString = "https://api.winnipegtransit.com/v2/stops/\(stopId)/features?api-key=\(apiKey)"
        print("About to fetch features for stop ID: \(stopId)") //debugging

        guard let url = URL(string: urlString) else {
            self.error = NSError(domain: "", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            isFetching = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { (data, response, error) in
            DispatchQueue.main.async {
                self.isFetching = false
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.error = error
                    self.busStopFeatures = [] // Clear the array
                }
                return
            }
            
            if let data = data {
                let parser = XMLParser(data: data)
                let delegate = BusStopFeatureParser()
                parser.delegate = delegate
                
                if parser.parse() {
                    DispatchQueue.main.async {
                        BusStopFeatures.featuresCache[stopId] = delegate.currentFeatures // Cache the fetched features
                        self.busStopFeatures = delegate.currentFeatures // Update features
                    }
                } else {
                    DispatchQueue.main.async {
                        self.error = NSError(domain: "", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to parse XML"])
                    }
                }
            }
        }.resume()
    }
}


class BusStopFeatureParser: NSObject, XMLParserDelegate {
    var currentElement: String = ""
    var currentFeatureName: String = ""
    var currentFeatureCount: Int = 0
    var currentFeatures: [BusStopFeature] = []
    var isParsingFeature = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "stop-feature" {
            isParsingFeature = true
            currentFeatureName = ""  // Reset here
            currentFeatureCount = 0  // Reset here
           // print("Start parsing stop-feature") debugging
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let data = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if isParsingFeature {
            //print("Found feature data: \(data)") //debugging
            switch currentElement {
            case "name":
                currentFeatureName += data
            case "count":
                currentFeatureCount += Int(data) ?? 0
            default:
                break
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "stop-feature" {
            //print("Ending parsing for stop-feature: \(currentFeatureName), \(currentFeatureCount)")  // Debugging line
            isParsingFeature = false
            let feature = BusStopFeature(name: currentFeatureName, count: currentFeatureCount)
            currentFeatures.append(feature)
        }
    }
}
