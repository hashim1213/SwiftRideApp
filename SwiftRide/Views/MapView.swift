import Foundation
import SwiftUI
import MapKit

struct MapView: View {
    @Binding var busStops: [BusStop]
    @Binding var selectedBusStop: BusStop?
    @Binding var isLoading: Bool  // Add this to observe loading state
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.8943, longitude: -97.1388), // Winnipeg coordinates
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    // Initialize a Map.Position with user location
   // @State private var userLocation: CLLocationCoordinate2D?
    // Initialize a Map.Position with user location
        @State private var userLocation: CLLocationCoordinate2D? = CLLocationCoordinate2D(latitude: 49.8093, longitude: -97.1344) // Debugging location in Winnipeg
    
    var body: some View {
        Map(coordinateRegion: $region, showsUserLocation: true, /*userTrackingMode: .constant(.follow),*/ annotationItems: busStops) { stop in
            MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)) {
                Image(systemName: "bus.fill")
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .font(.footnote)  // Makes the font smaller
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.8))
                    .clipShape(Capsule())
                
                    .onTapGesture {
                        selectedBusStop = stop  // Set the selected bus stop when tapped
                    }
            }
            
        }
        .onAppear {
            if let location = userLocation {
                region.center = location
            }
            if isLoading {
                ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.5, anchor: .center)
            }
        }
    }
}
