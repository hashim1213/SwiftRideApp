//
//  TripPlanner.swift
//  SwiftRide
//
//  Created by Hashim Farooq on 2023-10-12.
//

import Foundation
class TripPlanner: ObservableObject {
    @Published var trips: [Trip] = []  // Assume Trip is a model you define to hold trip data
    
    func fetchTripPlan(request: TripPlanRequest) {
        var components = URLComponents(string: "https://api.winnipegtransit.com/v2/trip-planner")!
        
        components.queryItems = [
            URLQueryItem(name: "origin", value: request.origin),
            URLQueryItem(name: "destination", value: request.destination),
            URLQueryItem(name: "date", value: request.date),
            URLQueryItem(name: "time", value: request.time),
            URLQueryItem(name: "mode", value: request.mode),
            URLQueryItem(name: "walk-speed", value: "\(request.walkSpeed ?? 0)"),
            URLQueryItem(name: "max-walk-time", value: "\(request.maxWalkTime ?? 0)"),
            URLQueryItem(name: "min-transfer-wait", value: "\(request.minTransferWait ?? 0)"),
            URLQueryItem(name: "max-transfer-wait", value: "\(request.maxTransferWait ?? 0)"),
            URLQueryItem(name: "max-transfers", value: "\(request.maxTransfers ?? 0)"),
            URLQueryItem(name: "api-key", value: "Your-Api-Key-Here")
        ]
        
        let url = components.url!
        
        URLSession.shared.dataTask(with: url) { (data, response, error) in
            if let data = data {
                // Parse JSON data here
                // Update self.trips
                DispatchQueue.main.async {
                    // self.trips = parsedTrips
                }
            }
        }
        .resume()
    }
}
