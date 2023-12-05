import SwiftUI
import CoreLocation

struct EnvironmentImpactTrackerView: View {
    var selectedBusStop: BusStop  // Injected
    @State private var carbonSavings: Double? = nil
    private let averageCarEmissionFactor = 120.0 // g/km
    private let averageBusEmissionFactor = 68.0 // g/km

    var body: some View {
        Form {
            Section(header: Text("Your Journey")) {
                Text("From: Current Location")
                Text("To: \(selectedBusStop.name)")
                Button("Calculate Impact") {
                    calculateImpact(for: selectedBusStop)
                }
            }

            if let savings = carbonSavings {
                Section(header: Text("Environmental Impact")) {
                    Text("Your carbon savings: \(savings, specifier: "%.2f") kg CO2")
                }
            }
        }
        .navigationTitle("Impact Tracker")
    }

    private func calculateImpact(for selectedBusStop: BusStop) {
        guard let currentLocation = LocationManager.shared.currentLocation else {
            print("Current location is not available.")
            return
        }

        let busStopLocation = CLLocation(latitude: selectedBusStop.latitude, longitude: selectedBusStop.longitude)
        let distance = currentLocation.distance(from: busStopLocation) / 1000 // Convert to km

        let carEmissions = distance * averageCarEmissionFactor
        let busEmissions = distance * averageBusEmissionFactor
        carbonSavings = carEmissions - busEmissions
    }
}
