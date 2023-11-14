import Foundation
//data model for busStop
struct BusStop: Identifiable,Hashable {
   // var id: String { key } 
    var id: String { // Ensure this produces a unique identifier
         "\(key)-\(name)-\(number)"
     }// Make sure `key` is unique for each BusStop
    let key: String
    let name: String
    let number: Int
    let direction: String
    let side: String
    let streetName: String
    let streetType: String
    let crossStreetName: String
    let utmX: String
    let utmY: String
    let latitude: Double
    let longitude: Double
    let distances: Double
}
// Data model for a route
struct Route {
    let key: String
    let number: String
    let name: String
    let variants: [RouteVariant]
}
// Data model for a route variant
struct RouteVariant {
    let key: String
    let stops: [BusStop] // You will need to define the BusStop model if not already done
}
//data model for Route Schedule
struct RouteSchedule: Identifiable {
    var id: String {routeKey}
    let routeKey: String
    let routeName: String
    let scheduledStops: [ScheduledStop]
}
// data model for stop schedules
struct ScheduledStop: Identifiable,Hashable {
    var id: String {
        return "\(key)-\(scheduledArrival)"
    }
    let key: String
    let number: String 
    let scheduledArrival: String
    let estimatedArrival: String
    let variantName: String
    let bikeRack: Bool
    let easyAccess: Bool
    let wifi: Bool
    var minutesToScheduledArrival: Int?
    var minutesToEstimatedArrival: Int?
}
//data model for bustop features
struct BusStopFeature {
    let id = UUID()  // Add this line
    let name: String
    let count: Int
}
// data model for tranist status
struct Status: Identifiable {
    var id: String { key }  // Make sure `key` is unique for each BusStop
    let key: String
    let value: String
    let name: String
    let message: String 

  
}
  
//unused model for trip planner feature to be implimented in the future
/*
struct Trip: Identifiable {
    let id: String
    let origin: String
    let destination: String
    let departureTime: String
    let arrivalTime: String
    let numberOfTransfers: Int
}

struct TripPlanRequest {
    let origin: String
    let destination: String
    let date: String?
    let time: String?
    let mode: String
    let walkSpeed: Float?
    let maxWalkTime: Int?
    let minTransferWait: Int?
    let maxTransferWait: Int?
    let maxTransfers: Int?
}
*/

