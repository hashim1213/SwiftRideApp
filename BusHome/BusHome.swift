//
//  BusHome.swift
//  BusHome
//
//  Created by Hashim Farooq on 2024-03-24.
//

import WidgetKit
import SwiftUI
struct SimpleEntry: TimelineEntry {
    let date: Date
    let busNumber: String
    let scheduledArrival: String
    let estimatedArrival: String
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), busNumber: "123", scheduledArrival: "10:00 AM", estimatedArrival: "10:05 AM")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), busNumber: "123", scheduledArrival: "10:00 AM", estimatedArrival: "10:05 AM")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        var entries: [SimpleEntry] = []

        // Generate a timeline with dummy data for demonstration.
        let currentDate = Date()
        for hourOffset in 0 ..< 5 {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
            let entry = SimpleEntry(date: entryDate, busNumber: "123", scheduledArrival: "\(10 + hourOffset):00 AM", estimatedArrival: "\(10 + hourOffset):05 AM")
            entries.append(entry)
        }

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}
struct BusHomeEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack {
            Text("Bus Number: \(entry.busNumber)")
                .bold()

            HStack {
                Text("Scheduled Arrival:")
                Spacer()
                Text(entry.scheduledArrival)
            }
            
            HStack {
                Text("Estimated Arrival:")
                Spacer()
                Text(entry.estimatedArrival)
            }
        }
        .padding()
        .background(.quaternary)
        .cornerRadius(8)
    }
}
struct BusHome: Widget {
    let kind: String = "BusHome"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            BusHomeEntryView(entry: entry)
        }
        .configurationDisplayName("Bus Arrival Widget")
        .description("Shows upcoming bus arrivals.")
    }
}
