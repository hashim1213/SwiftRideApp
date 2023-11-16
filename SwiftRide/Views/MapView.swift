import Foundation
import SwiftUI
import MapKit

struct MapView: View {
    @Binding var busStops: [BusStop]
    @Binding var selectedBusStop: BusStop?
    @Binding var isLoading: Bool
    @Binding var isExploreModeActive: Bool
    @StateObject var busStopProvider = BusStopProvider.shared // Reference to BusStopProvider
    @Binding var region: MKCoordinateRegion
    
    @State private var equatableRegion = EquatableRegion(region: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 49.8943, longitude: -97.1388),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        ))

    private func fetchBusStopsForRegion(_ region: MKCoordinateRegion) {
        let center = region.center
        let lat = center.latitude
        let lon = center.longitude
        // Assuming radius is based on the span of the map region
        let radius = Int((region.span.latitudeDelta + region.span.longitudeDelta) * 5000) // Adjust this calculation as needed

        busStopProvider.fetchBusStopsForRegion(lat: lat, lon: lon, radius: radius) {
            isLoading = false
        }
    }

    var body: some View {
        Map(coordinateRegion: $equatableRegion.region, showsUserLocation: true, annotationItems: busStops) { stop in
            MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)) {
                Image(systemName: "bus.fill")
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.blue.opacity(0.8))
                    .clipShape(Capsule())
                    .onTapGesture {
                        selectedBusStop = stop
                    }
            }
        }
        .onChange(of: equatableRegion) { newRegionWrapper in
                   let newRegion = newRegionWrapper.region
                   if isExploreModeActive {
                       fetchBusStopsForRegion(newRegion)
                   }
               }
               .onAppear {
                   if isExploreModeActive {
                       fetchBusStopsForRegion(equatableRegion.region)
                   }
               }
        if isLoading {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.5, anchor: .center)
        }
    }
}

struct EquatableRegion: Equatable {
    var region: MKCoordinateRegion

    static func == (lhs: EquatableRegion, rhs: EquatableRegion) -> Bool {
        lhs.region.center.latitude == rhs.region.center.latitude &&
        lhs.region.center.longitude == rhs.region.center.longitude &&
        lhs.region.span.latitudeDelta == rhs.region.span.latitudeDelta &&
        lhs.region.span.longitudeDelta == rhs.region.span.longitudeDelta
    }
}
