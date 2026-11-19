import SwiftUI
import CoreLocation
import MapKit
import Combine

// MARK: - Main View
struct NearbyBusStopsView: View {
    // MARK: - Properties
    @StateObject private var viewModel = NearbyBusStopsViewModel()
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // Search Bar
                    searchBar
                        .padding()
                    
                    // Content
                    if viewModel.isLoading {
                        loadingView
                    } else if viewModel.busStops.isEmpty {
                        emptyStateView
                    } else {
                        stopsList
                    }
                }
                
                // Location Permission Overlay
                if viewModel.locationManager.authorizationStatus == .denied ||
                                 viewModel.locationManager.authorizationStatus == .restricted {
                                  locationPermissionOverlay
                              }

                
            }
            .navigationTitle("Nearby Stops")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    toolbarButtons
                }
            }
        }
        .task {
            await viewModel.fetchBusStops()
              }
        .alert("Location Access Required",
                    isPresented: $viewModel.showLocationPermissionAlert) {
                 Button("Open Settings") {
                     if let url = URL(string: UIApplication.openSettingsURLString) {
                         UIApplication.shared.open(url)
                     }
                 }
                 Button("Cancel", role: .cancel) { }
             } message: {
                 Text("Please enable location access to find nearby bus stops")
             }
         
    }
    
    // MARK: - Subviews
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search stops", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(10)
        }
    }
    
    private var stopsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.filteredBusStops) { stop in
                    BusStopCard(
                        stop: stop,
                        onTap: { viewModel.selectedBusStop = stop }
                    )
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.fetchBusStops()
        }
        .sheet(item: $viewModel.selectedBusStop) { stop in
            BusStopScheduleListView(selectedBusStop: stop)
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Finding nearby stops...")
                .foregroundColor(.secondary)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bus.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Stops Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(viewModel.searchText.isEmpty ?
                 "Try moving closer to a bus stop" :
                    "Try a different search term")
                .foregroundColor(.secondary)
            
            Button(action: {
                Task {
                    await viewModel.fetchBusStops()
                }
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var toolbarButtons: some View {
        HStack(spacing: 16) {
            Button(action: {
                Task {
                    await viewModel.fetchBusStops()
                }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            
            Button(action: viewModel.centerOnUserLocation) {
                Image(systemName: "location.fill")
            }
        }
    }
    
    private var locationPermissionOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 50))
            
            Text("Location Access Required")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Please enable location access to find nearby bus stops")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(radius: 20)
        .padding()
    }
}

// MARK: - Bus Stop Card
struct BusStopCard: View {
    let stop: BusStop
    let onTap: () -> Void
    @State private var region: MKCoordinateRegion
    
    init(stop: BusStop, onTap: @escaping () -> Void) {
        self.stop = stop
        self.onTap = onTap
        self._region = State(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: stop.latitude,
                longitude: stop.longitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: 0.005,
                longitudeDelta: 0.005
            )
        ))
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Map Preview
                Map(coordinateRegion: .constant(region),
                    interactionModes: [])
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        Image(systemName: "bus.fill")
                            .foregroundColor(.blue)
                            .background(
                                Circle()
                                    .fill(.white)
                                    .frame(width: 30, height: 30)
                            )
                    )
                
                // Stop Information
                VStack(alignment: .leading, spacing: 8) {
                    Text(stop.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(stop.direction)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("#\(stop.number)")
                            .font(.caption)
                            .padding(4)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(4)
                        
                        Text(stop.crossStreetName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(uiColor: .systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(BusStopCardButtonStyle())
    }
}


class NearbyBusStopsViewModel: ObservableObject {
    // Published properties to track state changes
    @Published var busStops: [BusStop] = []
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var selectedBusStop: BusStop?
    @Published var showLocationPermissionAlert = false
    @Published var error: Error?
    
    // Dependencies
    let locationManager = LocationManager.shared
    private let busStopProvider = BusStopProvider.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Initialize with a fetch to ensure we have data
        Task {
            await fetchBusStops()
        }
    }
    
    var filteredBusStops: [BusStop] {
        if searchText.isEmpty {
            return busStops
        }
        return busStops.filter { stop in
            stop.name.localizedCaseInsensitiveContains(searchText) ||
            String(stop.number).contains(searchText) ||
            stop.direction.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    @MainActor
    func fetchBusStops() async {
        // Set loading state
        isLoading = true
        error = nil
        
        // Create a safe completion handler that checks for self
        let completion = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Get the stops from the provider
                let stops = self.busStopProvider.busStops
                
                // If we have stops, sort them by distance
                if !stops.isEmpty {
                    if let userLocation = self.locationManager.currentLocation {
                        self.busStops = stops.sorted { firstStop, secondStop in
                            let location1 = CLLocation(
                                latitude: firstStop.latitude,
                                longitude: firstStop.longitude
                            )
                            let location2 = CLLocation(
                                latitude: secondStop.latitude,
                                longitude: secondStop.longitude
                            )
                            return userLocation.distance(from: location1) < userLocation.distance(from: location2)
                        }
                    } else {
                        // If no location, just use the stops as-is
                        self.busStops = stops
                    }
                } else {
                    // Clear the stops if none were returned
                    self.busStops = []
                }
                
                // Update UI state
                self.isLoading = false
            }
        }
        
        // Call the provider with our safe completion handler
        busStopProvider.fetchBusStops(completion: completion)
    }
    
    func centerOnUserLocation() {
        // Since we're using a fixed downtown location, this is mainly for UI feedback
        if let location = locationManager.currentLocation {
            print("Centered on location: \(location.coordinate)")
        }
    }
}


// MARK: - Custom Location Errors
enum LocationError: LocalizedError {
    case servicesDisabled
    case permissionDenied
    case locationUnavailable
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .servicesDisabled:
            return "Location services are disabled on your device"
        case .permissionDenied:
            return "Location access was denied. Please enable it in Settings"
        case .locationUnavailable:
            return "Unable to determine your location"
        case .unknown:
            return "An unknown location error occurred"
        }
    }
}

// MARK: - Supporting Views and Styles
struct BusStopCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}
