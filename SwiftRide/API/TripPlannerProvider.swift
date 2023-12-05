//
//  TripPlannerProvider.swift
//  SwiftRide
//
//  Created by Hashim Farooq on 2023-12-05.
//

import Foundation
class TripPlanProvider: ObservableObject {
    @Published var trips: [Trip] = []

    func fetchTripPlans(request: TripPlanRequest) {
        let urlString = constructURLString(from: request)
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let data = data {
                let parsedTrips = self?.parseXML(data) ?? []
                DispatchQueue.main.async {
                    self?.trips = parsedTrips
                }
            } else if let error = error {
                print("Error fetching trip plans: \(error)")
            }
        }.resume()
    }
    private func constructURLString(from request: TripPlanRequest) -> String {
        var components = URLComponents(string: "https://api.winnipegtransit.com/v3/services/trip-planner")

        var queryItems = [URLQueryItem]()

        queryItems.append(URLQueryItem(name: "origin", value: request.origin))
        queryItems.append(URLQueryItem(name: "destination", value: request.destination))

        if let date = request.date {
            queryItems.append(URLQueryItem(name: "date", value: date))
        }
        
        if let time = request.time {
            queryItems.append(URLQueryItem(name: "time", value: time))
        }

        queryItems.append(URLQueryItem(name: "mode", value: request.mode))

        if let walkSpeed = request.walkSpeed {
            queryItems.append(URLQueryItem(name: "walk-speed", value: "\(walkSpeed)"))
        }

        if let maxWalkTime = request.maxWalkTime {
            queryItems.append(URLQueryItem(name: "max-walk-time", value: "\(maxWalkTime)"))
        }

        if let minTransferWait = request.minTransferWait {
            queryItems.append(URLQueryItem(name: "min-transfer-wait", value: "\(minTransferWait)"))
        }

        if let maxTransferWait = request.maxTransferWait {
            queryItems.append(URLQueryItem(name: "max-transfer-wait", value: "\(maxTransferWait)"))
        }

        if let maxTransfers = request.maxTransfers {
            queryItems.append(URLQueryItem(name: "max-transfers", value: "\(maxTransfers)"))
        }

        components?.queryItems = queryItems

        return components?.url?.absoluteString ?? ""
    }

    private func parseXML(_ data: Data) -> [Trip] {
        let parser = XMLParser(data: data)
        let delegate = TripXMLParserDelegate()
        parser.delegate = delegate
        parser.parse()
        return delegate.trips
    }

    class TripXMLParserDelegate: NSObject, XMLParserDelegate {
        var trips: [Trip] = []
        private var currentElement: String = ""
        private var currentTripData: [String: String] = [:]

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            currentElement = elementName
            if elementName == "plan" {
                currentTripData = [:]
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            currentTripData[currentElement] = (currentTripData[currentElement] ?? "") + string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "plan" {
                // Assuming the trip data is fully parsed, create a Trip object
                let trip = Trip(
                    id: currentTripData["id"] ?? UUID().uuidString,
                    origin: currentTripData["origin"] ?? "",
                    destination: currentTripData["destination"] ?? "",
                    departureTime: currentTripData["start"] ?? "",
                    arrivalTime: currentTripData["end"] ?? "",
                    numberOfTransfers: Int(currentTripData["numberOfTransfers"] ?? "0") ?? 0
                )
                trips.append(trip)
            }
        }
    }

}
