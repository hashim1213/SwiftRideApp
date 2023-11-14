//
//  BusStopScheduleListView.swift
//  SwiftRide
//
//  Created by Hashim Farooq on 2023-10-29.
//

import Foundation
import SwiftUI
import CoreData

struct BusStopScheduleListView: View {
    var selectedBusStop: BusStop  // Injected
    @ObservedObject var scheduledStopProvider: ScheduledStopProvider
    @ObservedObject var busStopFeature: BusStopFeatures
    @State private var showingSheet = false
    @State private var selectedBus: ScheduledStop?

    init(selectedBusStop: BusStop) {
        self.selectedBusStop = selectedBusStop
        self.scheduledStopProvider = ScheduledStopProvider(stopId: Int(selectedBusStop.number))
        self.busStopFeature = BusStopFeatures(stopId: Int(selectedBusStop.number))
    }

    var body: some View {
        VStack {
            ScrollView {
                ForEach(sortedStops.prefix(30), id: \.self) { scheduledStop in
                    CardView(scheduledStop: scheduledStop)
                        .onTapGesture {
                            self.cardTapped(scheduledStop)
                        }
                }

            }
            .padding(.top, 8)
        }
        .sheet(isPresented: $showingSheet) {
            if let selectedBus = selectedBus {
                FullScheduleView(scheduledStop: selectedBus)
            }
        }
        .navigationTitle("\(selectedBusStop.name)")
        .navigationBarTitleDisplayMode(.inline)
        .padding()
    }

    private var sortedStops: [ScheduledStop] {
        scheduledStopProvider.scheduledStops.sorted { $0.scheduledArrival < $1.scheduledArrival }
    }

    private func cardTapped(_ stop: ScheduledStop) {
        self.selectedBus = stop
        self.showingSheet = true
    }
}

extension BusStop {
    init(favourite: FavouriteBusStop) {
        self.init(
            key: favourite.key ?? "",
            name: favourite.name ?? "",
            number: Int(favourite.stopNumber),
            direction: favourite.direction ?? "",
            side: favourite.side ?? "",
            streetName: favourite.streetName ?? "",
            streetType: favourite.streetType ?? "",
            crossStreetName: favourite.crossStreet ?? "",
            utmX: favourite.utmX ?? "",
            utmY: favourite.utmY ?? "",
            latitude: favourite.latitude,
            longitude: favourite.longitude,
            distances: favourite.distances 
            
        )
    }
}




struct FullScheduleView: View {
    var scheduledStop: ScheduledStop

    var body: some View {
        Text("Full Schedule for \(scheduledStop.number)")
            // Add more details and styling
    }
}
