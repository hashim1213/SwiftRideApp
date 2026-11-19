//
//  CardViewBusStop.swift
//  SwiftRide
//
//  Created by Hashim Farooq on 2024-10-28.
//

import Foundation
import SwiftUI
import CoreData
import ActivityKit

struct CardView: View {
    var showEstimatedTime: Bool
    var showDate: Bool
    var scheduledStop: ScheduledStop
    @State private var isReminderSet = false
    // Function to determine text color based on time
    private func colorForTime(_ minutes: Int) -> Color {
        if minutes == 0 {
            return Color.blue
        } else if minutes < 10 {
            return Color.red
        } else if minutes < 30 {
            return Color.green
        } else {
            return Color.white
        }
    }
    func getTime(from dateString: String?) -> String? {
        guard let dateString = dateString else {
            print("Date string is nil")
            return nil
        }
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        isoFormatter.timeZone = TimeZone(abbreviation: "UTC")  // Set to UTC
        
        if let date = isoFormatter.date(from: dateString) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm:ss"
            
            // Manually adjust the time to Winnipeg time zone
            if let winnipegTimeZone = TimeZone(identifier: "America/Winnipeg") {
                let secondsFromGMT = winnipegTimeZone.secondsFromGMT(for: date)
                let adjustedDate = date.addingTimeInterval(TimeInterval(-secondsFromGMT))
                return timeFormatter.string(from: adjustedDate)
            } else {
                print("Failed to find Winnipeg time zone")
                return nil
            }
        } else {
            print("Failed to convert date string: \(dateString)")
            return nil
        }
    }
    
    
    func convertMinutesToHoursAndMinutes(minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours) hr \(remainingMinutes) mins"
        } else {
            return "\(minutes) mins"
        }
    }
    
    var body: some View {
        
        VStack {
            ZStack {
                VStack(alignment: .leading) {
                    HStack{
                        Image(systemName: "bus")
                            .foregroundColor(Color.blue)
                            .frame(width: 10, height: 10)
                        Text("\(scheduledStop.number)")
                        Text("\(scheduledStop.variantName)")
                            .fontWeight(.bold)
                        Spacer()
                        // Reminder Button with an Icon
                        Button(action: {
                            /*
                             scheduleNotification(for: scheduledStop)
                             isReminderSet = true // Set the state to true to show the alert
                             */
                            let attributes = BusArrivalAttributes()
                            let state = BusArrivalAttributes.ContentState(
                                busNumber: scheduledStop.number,
                                scheduledArrival: scheduledStop.scheduledArrival ,
                                estimatedArrival: scheduledStop.estimatedArrival
                            )
                            
                            do {
                                let activity = try Activity<BusArrivalAttributes>.request(
                                    attributes: attributes,
                                    contentState: state, pushType: nil)
                                
                                print("Live Activity started: \(activity.id)")
                            } catch {
                                print("Failed to start Live Activity: \(error)")
                            }
                            
                        }) {
                            Image(systemName: "bell")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .foregroundColor(Color.white)
                                .padding(10)
                                .cornerRadius(8)
                        }
                        .alert(isPresented: $isReminderSet) {
                            Alert(
                                title: Text("Reminder Set for 5 mins before arrival"),
                                message: Text("A reminder for Bus \(scheduledStop.number) has been set."),
                                dismissButton: .default(Text("OK"))
                            )
                        }
                        
                    }
                    if showEstimatedTime {
                        HStack {
                            Text("Scheduled Arrival:")
                            Spacer()
                            VStack(alignment: .trailing) {
                                if let minutesToScheduled = scheduledStop.minutesToScheduledArrival {
                                    if minutesToScheduled == -1 {
                                        Text("N/A")
                                            .fontWeight(.semibold)
                                            .foregroundColor(Color.gray)
                                    } else {
                                        Text(minutesToScheduled < 0 ? "Late" : (minutesToScheduled == 0 ? "Due" : convertMinutesToHoursAndMinutes(minutes: minutesToScheduled)))
                                            .fontWeight(.semibold)
                                            .foregroundColor(colorForTime(minutesToScheduled))
                                    }
                                    if showDate {
                                        if let timeString = getTime(from: scheduledStop.scheduledArrival) {
                                            Text(timeString)
                                                .font(.caption)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    HStack {
                        Text("Estimated Arrival:")
                        Spacer()
                        VStack(alignment: .trailing) {
                            if let minutesToEstimated = scheduledStop.minutesToEstimatedArrival {
                                if minutesToEstimated == -1 {
                                    Text("Late")
                                        .fontWeight(.semibold)
                                        .foregroundColor(Color.gray)
                                } else {
                                    Text(minutesToEstimated == 0 ? "Now" : convertMinutesToHoursAndMinutes(minutes: minutesToEstimated))
                                        .fontWeight(.semibold)
                                        .foregroundColor(colorForTime(minutesToEstimated))
                                }
                                if showDate {
                                    if let timeString = getTime(from: scheduledStop.estimatedArrival) {
                                        Text(timeString)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                    
                    
                    HStack(spacing: 20) {
                        Spacer()  // push the icons to the right
                        
                        Image(systemName: "figure.roll")
                            .foregroundColor(scheduledStop.easyAccess ? Color.green : Color.gray)
                            .frame(width: 5, height: 5)
                        
                        Image(systemName: "wifi.circle")
                            .foregroundColor(scheduledStop.wifi ? Color.green : Color.gray)
                            .frame(width: 5, height: 5)
                        
                        Image(systemName: "bicycle.circle")
                            .foregroundColor(scheduledStop.bikeRack ? Color.green : Color.gray)
                            .frame(width: 5, height: 5)
                    }
                    .padding(.horizontal, 8)  // Padding to move the icons away from the edge of the card
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding([.top, .bottom], 5)
            }
            
            
        }
    }
}
struct TimeRow: View {
    let label: String
    let minutes: Int
    let time: String
    let showDate: Bool
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text(formatTime(minutes))
                    .foregroundStyle(timeColor(minutes))
                    .fontWeight(.semibold)
                
                if showDate, let timeString = formatDate(time) {
                    Text(timeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func formatTime(_ minutes: Int) -> String {
        switch minutes {
        case -1: return "N/A"
        case 0: return "Now"
        case ..<0: return "Late"
        case 60...: return "\(minutes / 60)h \(minutes % 60)m"
        default: return "\(minutes)m"
        }
    }
    
    private func timeColor(_ minutes: Int) -> Color {
        switch minutes {
        case 0: return .blue
        case 1...10: return .red
        case 11...30: return .green
        default: return .primary
        }
    }
    
    private func formatDate(_ dateString: String) -> String? {
        // Your existing date formatting logic
        return nil // Implement your date formatting
    }
}
// MARK: - Supporting Views
struct FeatureIconsView: View {
    let features: [BusStopFeature]
    
    var body: some View {
        HStack(spacing: 20) {
            ForEach(features, id: \.name) { feature in
                FeatureIcon(
                    systemName: iconName(for: feature.name),
                    isActive: feature.count > 0,
                    activeColor: .blue
                )
            }
        }
    }
    
    private func iconName(for featureName: String) -> String {
        switch featureName {
        case "Heated Shelter": return "thermometer"
        case "Bench": return "chair"
        case "Bike Rack/Locker": return "bicycle"
        default: return "bus.fill"
        }
    }
}
struct BusFeatureIcon: View {
    let systemName: String
    let isEnabled: Bool
    
    var body: some View {
        Image(systemName: systemName)
            .font(.caption)
            .foregroundStyle(isEnabled ? .green : .gray.opacity(0.5))
    }
}


struct ArrivalInfoItem: View {
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
// MARK: - Supporting Views
struct StopFeaturesView: View {
    let features: Set<String>
    
    var body: some View {
        HStack(spacing: 12) {
            FeatureIcon(
                systemName: "thermometer",
                isActive: features.contains("Heated Shelter"),
                activeColor: .red
            )
            
            FeatureIcon(
                systemName: "bench",
                isActive: features.contains("Bench"),
                activeColor: .green
            )
            
            FeatureIcon(
                systemName: "bicycle",
                isActive: features.contains("Bike Rack/Locker"),
                activeColor: .blue
            )
        }
    }
}

struct FeatureIcon: View {
    let systemName: String
    let isActive: Bool
    let activeColor: Color
    
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16))
            .foregroundStyle(isActive ? activeColor : .gray.opacity(0.5))
    }
}
import SwiftUI

struct ArrivalCard: View {
    let stop: ScheduledStop
    let showEstimatedTime: Bool
    let showDate: Bool
    let onReminderTap: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Route Info
            routeInfoView
            
            // Times
            if showEstimatedTime {
                TimeRow(
                    label: "Scheduled:",
                    minutes: stop.minutesToScheduledArrival ?? 0,
                    time: stop.scheduledArrival,
                    showDate: showDate
                )
            }
            
            TimeRow(
                label: "Estimated:",
                minutes: stop.minutesToEstimatedArrival ?? 0,
                time: stop.estimatedArrival,
                showDate: showDate
            )
            
            // Features
            featuresView
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
        .contextMenu {
            Button(action: onReminderTap) {
                Label("Set Reminder", systemImage: "bell")
            }
        }
    }
    
    // MARK: - Subviews
    private var routeInfoView: some View {
        HStack {
            Label {
                Text("Route \(stop.number)")
                    .font(.headline)
            } icon: {
                Image(systemName: "bus.fill")
                    .foregroundStyle(.blue)
            }
            
            Spacer()
            
            Text(stop.variantName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private var featuresView: some View {
        HStack {
            Spacer()
            
            BusFeatureIcon(systemName: "figure.roll", isEnabled: stop.easyAccess)
            BusFeatureIcon(systemName: "wifi", isEnabled: stop.wifi)
            BusFeatureIcon(systemName: "bicycle", isEnabled: stop.bikeRack)
        }
    }
}
