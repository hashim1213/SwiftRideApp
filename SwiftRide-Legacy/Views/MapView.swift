import Foundation
import SwiftUI
import MapKit
import CoreLocation


struct MapView: View {
    // MARK: - Properties
    @Binding var busStops: [BusStop]
    @Binding var selectedBusStop: BusStop?
    @Binding var isLoading: Bool
    @Binding var isExploreModeActive: Bool
    @Binding var currentLocation: CLLocation?
    @Binding var busStopSearchRadius: Double
    
    @StateObject var busStopProvider = BusStopProvider.shared
    @State private var equatableRegion: EquatableRegion
    @State private var hasInitializedRegion = false
    
    // MARK: - Initialization
    init(busStops: Binding<[BusStop]>,
         selectedBusStop: Binding<BusStop?>,
         isLoading: Binding<Bool>,
         isExploreModeActive: Binding<Bool>,
         currentLocation: Binding<CLLocation?>,
         busStopSearchRadius: Binding<Double>) {
        
        self._busStops = busStops
        self._selectedBusStop = selectedBusStop
        self._isLoading = isLoading
        self._isExploreModeActive = isExploreModeActive
        self._currentLocation = currentLocation
        self._busStopSearchRadius = busStopSearchRadius
        
        // Initialize with downtown Winnipeg
        let initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 49.8951, longitude: -97.1384),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        self._equatableRegion = State(initialValue: EquatableRegion(region: initialRegion))
    }
    
    // MARK: - Methods
    private func fetchBusStopsForRegion(_ region: MKCoordinateRegion) {
        isLoading = true
        let center = region.center
        
        // Calculate radius based on the visible map area
        let metersPerDegree = 111_319.9 // approximate meters per degree at the equator
        let mapWidthMeters = region.span.longitudeDelta * metersPerDegree * cos(center.latitude * .pi / 180.0)
        let radius = Int(max(500, min(mapWidthMeters / 2, 2000))) // min 500m, max 2000m
        
        print("Fetching bus stops for region: lat=\(center.latitude), lon=\(center.longitude), radius=\(radius)")
        
        busStopProvider.fetchBusStopsForRegion(lat: center.latitude, lon: center.longitude, radius: radius) {
            isLoading = false
        }
    }
    
    private func updateRegionForLocation(_ location: CLLocation) {
        withAnimation {
            equatableRegion.region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            Map(coordinateRegion: $equatableRegion.region,
                showsUserLocation: true,
                annotationItems: busStops) { stop in
                MapAnnotation(coordinate: CLLocationCoordinate2D(
                    latitude: stop.latitude,
                    longitude: stop.longitude)
                ) {
                    BusStopAnnotation(
                        stop: stop,
                        isSelected: selectedBusStop?.number == stop.number,
                        action: { selectedBusStop = stop }
                    )
                }
            }
            .applyMapStyle()
            .ignoresSafeArea()
            
            if isLoading {
                LoadingOverlay()
            }
        }
        .onAppear {
            // Set initial location if available
            if let location = currentLocation {
                updateRegionForLocation(location)
                if !hasInitializedRegion {
                    hasInitializedRegion = true
                    fetchBusStopsForRegion(equatableRegion.region)
                }
            }
        }
        .onChange(of: currentLocation) { newLocation in
            if let location = newLocation {
                updateRegionForLocation(location)
                if isExploreModeActive {
                    fetchBusStopsForRegion(equatableRegion.region)
                }
            }
        }
        .onChange(of: equatableRegion) { newRegionWrapper in
            // Debounce region changes to prevent too many API calls
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if isExploreModeActive {
                    fetchBusStopsForRegion(newRegionWrapper.region)
                }
            }
        }
        .onChange(of: isExploreModeActive) { newValue in
            if newValue {
                fetchBusStopsForRegion(equatableRegion.region)
            }
        }
    }
}

// MARK: - Supporting Types
struct EquatableRegion: Equatable {
    var region: MKCoordinateRegion
    
    static func == (lhs: EquatableRegion, rhs: EquatableRegion) -> Bool {
        lhs.region.center.latitude == rhs.region.center.latitude &&
        lhs.region.center.longitude == rhs.region.center.longitude &&
        lhs.region.span.latitudeDelta == rhs.region.span.latitudeDelta &&
        lhs.region.span.longitudeDelta == rhs.region.span.longitudeDelta
    }
}

// MARK: - Supporting Views
struct BusStopAnnotation: View {
    let stop: BusStop
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Image(systemName: "bus.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(isSelected ? Color.blue : Color.blue.opacity(0.8))
                    .clipShape(Circle())
                    .shadow(radius: isSelected ? 4 : 2)
                
                if isSelected {
                    Text(stop.name)
                        .font(.caption)
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white)
                        .cornerRadius(8)
                        .shadow(radius: 2)
                }
            }
        }
        .scaleEffect(isSelected ? 1.2 : 1.0)
        .animation(.spring(), value: isSelected)
    }
}

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                
                Text("Loading bus stops...")
                    .foregroundColor(.white)
                    .padding(.top)
            }
            .padding()
            .background(Color(UIColor.systemBackground).opacity(0.8))
            .cornerRadius(12)
        }
    }
}

extension View {
    
    
    @ViewBuilder
    func applyMapStyle() -> some View {
        if #available(iOS 17.0, *) {
            self.mapStyle(.standard(elevation: .realistic))
            
        } else {
            self // Return the view unmodified for earlier iOS versions
        }
    }
}


