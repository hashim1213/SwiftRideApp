//
//  Settings.swift
//  SwiftRide
//
//  Created by Hashim Farooq on 2023-12-05.

import Foundation
import SwiftUI

struct SettingsView: View {
    @AppStorage("showEstimatedTime") private var showEstimatedTime = true
    @AppStorage("showDate") private var showDate = true
    // Add more settings as needed

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Display Preferences")) {
                    Toggle("Show Scheduled Time", isOn: $showEstimatedTime)
                    Toggle("Show 24hr Time", isOn: $showDate)
                    // Add more toggles for other settings
                }
                // You can add more sections for different types of settings
            }
            .navigationTitle("Settings")
        }
    }
}
