//
//  LiveActivityView.swift
//  SwiftRide
//
//  Created by Hashim Farooq on 2024-03-24.
//

import Foundation
import SwiftUI
import CoreData
import CoreLocation
import ActivityKit
import WidgetKit

struct BusArrivalAttributes: ActivityAttributes {
    public typealias Bus = ContentState
    
    struct ContentState: Codable, Hashable {
        var busNumber: String
        var scheduledArrival: String
        var estimatedArrival: String
    }
    
}



@available(iOSApplicationExtension 16.2, *)
struct BusArrivalActivityWidget: Widget {
    let kind: String = "BusArrivalActivityWidget"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BusArrivalAttributes.self) { context in
            // Lock Screen and Home Screen Widget View
            BusArrivalLiveActivityView(context: context)
                .padding(.horizontal)
        } dynamicIsland: { context in
            // Dynamic Island Configuration
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    BusArrivalLiveActivityView(context: context)
                }
            } compactLeading: {
                Image(systemName: "bus")
                    .foregroundColor(.blue)
            } compactTrailing: {
                Text(context.state.estimatedArrival)
                    .foregroundColor(.blue)
            } minimal: {
                Image(systemName: "bus")
                    .foregroundColor(.blue)
            }
        }
    }
}




struct BusArrivalLiveActivityView: View {
    let context: ActivityViewContext<BusArrivalAttributes>
    
    var body: some View {
        VStack {
            Text("Bus \(context.state.busNumber)")
               .font(.headline)
            
            Text("Scheduled: \(context.state.scheduledArrival)")
                .font(.subheadline)
            
            Text("Estimated: \(context.state.estimatedArrival)")
                .font(.subheadline)
        }
    }
}
