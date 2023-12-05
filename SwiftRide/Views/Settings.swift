import Foundation
import SwiftUI

struct SettingsView: View {
    @AppStorage("showEstimatedTime") private var showEstimatedTime = true
    @AppStorage("showDate") private var showDate = true
    // Additional state variables for new features
    @State private var isNetworkConnected: Bool = true // Example state, determine actual status dynamically
    @State private var showingFeedbackView = false

    var body: some View {
        NavigationView {
            Form {
                DisplayPreferencesSection()
                VersionHistorySection()
                NetworkStatusSection()
                FeedbackSection()
            }
            .navigationTitle("Settings")
        }
    }

    private func DisplayPreferencesSection() -> some View {
        Section(header: Text("Display Preferences")) {
            Toggle("Show Scheduled Time", isOn: $showEstimatedTime)
            Toggle("Show 24hr Time", isOn: $showDate)
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
