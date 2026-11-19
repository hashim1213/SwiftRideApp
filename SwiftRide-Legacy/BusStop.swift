import Foundation

import Foundation

// MARK: - BusStop Model
struct BusStop: Identifiable, Codable, Hashable {
    let id = UUID()
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
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(number)
    }
    
    static func == (lhs: BusStop, rhs: BusStop) -> Bool {
        lhs.number == rhs.number
    }
    
    // Coding Keys
    enum CodingKeys: String, CodingKey {
        case key, name, number, direction, side
        case streetName = "street"
        case streetType = "type"
        case crossStreetName = "cross-street-name"
        case utmX = "utm-x"
        case utmY = "utm-y"
        case latitude, longitude, distances
    }
}
// MARK: - Scheduled Stop Model
struct ScheduledStop: Codable, Hashable, Identifiable {
    let id = UUID()
    let key: String
    let number: String
    let scheduledArrival: String
    let estimatedArrival: String
    let variantName: String
    let bikeRack: Bool
    let easyAccess: Bool
    let wifi: Bool
    let minutesToScheduledArrival: Int?  // Changed to Optional
    let minutesToEstimatedArrival: Int?  // Changed to Optional
    
    enum CodingKeys: String, CodingKey {
        case key, number
        case scheduledArrival = "scheduled"
        case estimatedArrival = "estimated"
        case variantName = "variant-name"
        case bikeRack = "bike-rack"
        case easyAccess = "easy-access"
        case wifi
        case minutesToScheduledArrival
        case minutesToEstimatedArrival
    }
}

// MARK: - Service Advisory Model
struct ServiceAdvisory: Codable, Hashable, Identifiable {
    let id: String
    let priority: Int
    let title: String
    let body: String
    let category: String
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "key"
        case priority, title, body, category
        case updatedAt = "updated-at"
    }
}

// MARK: - Bus Stop Feature Model
struct BusStopFeature: Codable, Hashable, Identifiable {
    let id = UUID()
    let name: String
    let count: Int
    
    enum CodingKeys: String, CodingKey {
        case name, count
    }
}

// MARK: - XML Parsing Extensions
extension BusStop {
    static func fromXMLDictionary(_ dict: [String: Any]) -> BusStop? {
        guard let number = dict["number"] as? String,
              let name = dict["name"] as? String else {
            return nil
        }
        
        return BusStop(
            key: dict["key"] as? String ?? "",
            name: name,
            number: Int(number) ?? 0,
            direction: dict["direction"] as? String ?? "",
            side: dict["side"] as? String ?? "",
            streetName: dict["street"] as? String ?? "",
            streetType: dict["type"] as? String ?? "",
            crossStreetName: dict["cross-street-name"] as? String ?? "",
            utmX: dict["utm-x"] as? String ?? "",
            utmY: dict["utm-y"] as? String ?? "",
            latitude: Double(dict["latitude"] as? String ?? "") ?? 0.0,
            longitude: Double(dict["longitude"] as? String ?? "") ?? 0.0,
            distances: Double(dict["distances"] as? String ?? "") ?? 0.0
        )
    }
}

extension ScheduledStop {
    static func fromXMLDictionary(_ dict: [String: Any]) -> ScheduledStop? {
        guard let key = dict["key"] as? String,
              let number = dict["number"] as? String else {
            return nil
        }
        
        let dateFormatter = ISO8601DateFormatter()
        let scheduledArrival = dict["scheduled"] as? String ?? ""
        let estimatedArrival = dict["estimated"] as? String ?? ""
        
        let minutesToScheduled: Int
        if let scheduledDate = dateFormatter.date(from: scheduledArrival) {
            minutesToScheduled = Calendar.current.dateComponents([.minute], from: Date(), to: scheduledDate).minute ?? -1
        } else {
            minutesToScheduled = -1
        }
        
        let minutesToEstimated: Int
        if let estimatedDate = dateFormatter.date(from: estimatedArrival) {
            minutesToEstimated = Calendar.current.dateComponents([.minute], from: Date(), to: estimatedDate).minute ?? -1
        } else {
            minutesToEstimated = -1
        }
        
        return ScheduledStop(
            key: key,
            number: number,
            scheduledArrival: scheduledArrival,
            estimatedArrival: estimatedArrival,
            variantName: dict["variant-name"] as? String ?? "",
            bikeRack: (dict["bike-rack"] as? String) == "true",
            easyAccess: (dict["easy-access"] as? String) == "true",
            wifi: (dict["wifi"] as? String) == "true",
            minutesToScheduledArrival: minutesToScheduled,
            minutesToEstimatedArrival: minutesToEstimated
        )
    }
}

extension ServiceAdvisory {
    static func fromXMLDictionary(_ dict: [String: Any]) -> ServiceAdvisory? {
        guard let id = dict["key"] as? String else {
            return nil
        }
        
        var updatedAt = Date()
        if let updatedAtString = dict["updated-at"] as? String {
            updatedAt = ISO8601DateFormatter().date(from: updatedAtString) ?? Date()
        }
        
        return ServiceAdvisory(
            id: id,
            priority: Int(dict["priority"] as? String ?? "0") ?? 0,
            title: dict["title"] as? String ?? "",
            body: dict["body"] as? String ?? "",
            category: dict["category"] as? String ?? "",
            updatedAt: updatedAt
        )
    }
}

extension BusStopFeature {
    static func fromXMLDictionary(_ dict: [String: Any]) -> BusStopFeature? {
        guard let name = dict["name"] as? String else {
            return nil
        }
        
        return BusStopFeature(
            name: name,
            count: Int(dict["count"] as? String ?? "0") ?? 0
        )
    }
}
