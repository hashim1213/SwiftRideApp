import Foundation
import SwiftUI

struct SettingsView: View {
    @AppStorage("showEstimatedTime") private var showEstimatedTime = true
    @AppStorage("showDate") private var showDate = true
    @AppStorage("busStopSearchRadius") private var busStopSearchRadius: Double = 1000 // Default radius in meters

    // Additional state variables for new features
    @State private var isNetworkConnected: Bool = true // Example state, determine actual status dynamically
    @State private var showingFeedbackView = false

    var body: some View {
        NavigationView {
            Form {
                DisplayPreferencesSection()
                BusStopSearchRadiusSection() // Add the radius section
                ServiceAdvisorySection()
                CarbonTrackerSection()
                NetworkStatusSection()
                FeedbackSection()
                VersionHistorySection()
            }
            .navigationTitle("Settings")
        }
    }
    private func ServiceAdvisorySection() -> some View {
            Section(header: Text("Service Advisory")) {
                NavigationLink("View Service Advisories", destination: ServiceAdvisoryListView())
            }
        }
    private func DisplayPreferencesSection() -> some View {
        Section(header: Text("Display Preferences")) {
            Toggle("Show Scheduled Time", isOn: $showEstimatedTime)
            Toggle("Show 24hr Time", isOn: $showDate)
        }
    }
    private func BusStopSearchRadiusSection() -> some View {
        Section(header: Text("Bus Stop Search Radius")) {
            Slider(value: $busStopSearchRadius, in: 100...2000, step: 100)
            Text("Radius: \(busStopSearchRadius, specifier: "%.0f") meters")
        }
    }


    private func VersionHistorySection() -> some View {
        Section(header: Text("App Information")) {
            HStack {
                Text("Version")
                Spacer()
                // Replace with actual version number
                Text("2.0.1")
            }
            HStack {
                Text("Check for Updates")
                Spacer()
                // Replace with actual logic for checking updates
                Button("Up to date") {
                    // Action to check for new updates
                }
            }
        }
    }

    private func NetworkStatusSection() -> some View {
        Section(header: Text("Network")) {
            HStack {
                Text("Network Status")
                Spacer()
                Text(isNetworkConnected ? "Connected" : "Not Connected")
                    .foregroundColor(isNetworkConnected ? .green : .red)
            }
        }
    }
    private func CarbonTrackerSection() -> some View {
        Section(header: Text("Carbon Tracker")) {
            NavigationLink("Track Carbon Footprint", destination: EnvironmentImpactTrackerView(selectedBusStop: BusStop.placeholder))
        }
    }



    private func FeedbackSection() -> some View {
        Section(header: Text("Feedback")) {
            Button("Send Feedback") {
                showingFeedbackView = true
            }
            .sheet(isPresented: $showingFeedbackView) {
                MailView(subject: "SwiftRide: Winnipeg Transit Feedback",
                         recipients: ["Hello@bytesavvytech.com"],
                         messageBody: "Your feedback here...")
            }
        }
    }

}
extension BusStop {
    static var placeholder: BusStop {
        BusStop(key: "", name: "Select a Bus Stop", number: 0, direction: "", side: "", streetName: "", streetType: "", crossStreetName: "", utmX: "", utmY: "", latitude: 0.0, longitude: 0.0, distances: 0.0)
    }
}
