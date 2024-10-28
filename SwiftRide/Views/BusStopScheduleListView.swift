import Foundation
import SwiftUI
import CoreData

struct BusStopScheduleListView: View {
    var selectedBusStop: BusStop  // Injected
    @ObservedObject var scheduledStopProvider: ScheduledStopProvider
    @ObservedObject var busStopFeature: BusStopFeatures
    @State private var showingSheet = false
    @State private var selectedBus: ScheduledStop?
    @AppStorage("showEstimatedTime") var showEstimatedTime = true
    @AppStorage("showDate") var showDate = true
    
    init(selectedBusStop: BusStop) {
        self.selectedBusStop = selectedBusStop
        self.scheduledStopProvider = ScheduledStopProvider(stopId: Int(selectedBusStop.number))
        self.busStopFeature = BusStopFeatures(stopId: Int(selectedBusStop.number))
    }

    var body: some View {
        VStack {
            // Capsule shape as a pull-down indicator
              Capsule()
                  .frame(width: 60, height: 6)
                  .foregroundColor(.secondary)
                  .padding(5)
            
            ScrollView {
                ForEach(sortedStops.prefix(30), id: \.self) { scheduledStop in
                    CardView(showEstimatedTime: showEstimatedTime, showDate: showDate, scheduledStop: scheduledStop)
                        
                }

            }
            .padding(.top, 8)
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


