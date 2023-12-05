import Foundation
import SwiftUI

class ServiceAdvisoryProvider: ObservableObject {
    @Published var advisories: [ServiceAdvisory] = []
    private var urlSession = URLSession.shared
    
    func fetchServiceAdvisories() {
        guard let url = URL(string: "https://api.winnipegtransit.com/v3/service-advisories") else {
            print("Invalid URL")
            return
        }

        urlSession.dataTask(with: url) { [weak self] data, response, error in
               if let data = data {
                   print("Data received: \(data)")
                   let parsedAdvisories = self?.parseXML(data) ?? []
                   print("Parsed advisories: \(parsedAdvisories)")
                   DispatchQueue.main.async {
                       self?.advisories = parsedAdvisories
                   }
               } else if let error = error {
                   print("Error fetching service advisories: \(error)")
               }
           }.resume()
       
    }

    private func parseXML(_ data: Data) -> [ServiceAdvisory] {
        let parser = XMLParser(data: data)
        let delegate = ServiceAdvisoryXMLParserDelegate()
        parser.delegate = delegate
        if parser.parse() {
            return delegate.advisories
        } else {
            // Handle parsing error or return an empty array
            return []
        }
    }
}

class ServiceAdvisoryXMLParserDelegate: NSObject, XMLParserDelegate {
    var advisories: [ServiceAdvisory] = []
    private var currentElement: String = ""
    private var foundCharacters: String = ""
    private var currentAdvisoryData: [String: String] = [:]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        foundCharacters = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        foundCharacters += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "service-advisory" {
            // Assuming 'service-advisory' is the root element for each advisory
            let advisory = ServiceAdvisory(from: currentAdvisoryData)
            advisories.append(advisory)
            currentAdvisoryData.removeAll()
        } else {
            currentAdvisoryData[currentElement] = foundCharacters.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

extension ServiceAdvisory {
    init(from dict: [String: String]) {
        self.id = dict["key"] ?? ""
        self.priority = Int(dict["priority"] ?? "0") ?? 0
        self.title = dict["title"] ?? ""
        self.body = dict["body"] ?? ""
        self.category = dict["category"] ?? ""
        let updatedAtString = dict["updated-at"] ?? ""
        self.updatedAt = ISO8601DateFormatter().date(from: updatedAtString) ?? Date()
    }
}
