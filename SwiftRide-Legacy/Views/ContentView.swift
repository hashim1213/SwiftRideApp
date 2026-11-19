import SwiftUI
import MapKit
import UserNotifications

struct ContentView: View {
    @StateObject var locationManager = LocationManager.shared
    @StateObject var busStopProvider = BusStopProvider.shared
    @State private var selectedBusStop: BusStop? = nil
    @State private var selectedTab = 0
    @State private var isLoading = false
    @State private var isExploreModeActive = false
    @State private var busStopSearchRadius: Double = 1000
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.8943, longitude: -97.1388),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    init() {
        requestNotificationPermission()
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color(red: 0.15, green: 0.15, blue: 0.15).opacity(0.8))
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor.white
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        UITabBar.appearance().layer.masksToBounds = true
        UITabBar.appearance().layer.cornerRadius = 50
        UITabBar.appearance().layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // First Tab
            ZStack {
                VStack {
                    MapView(
                        busStops: $busStopProvider.busStops,
                        selectedBusStop: $selectedBusStop,
                        isLoading: $isLoading,
                        isExploreModeActive: $isExploreModeActive,
                        currentLocation: $locationManager.currentLocation,
                        busStopSearchRadius: $busStopSearchRadius
                    )
                    .frame(maxHeight: .infinity)
                    .edgesIgnoringSafeArea(.top)
                }
                .sheet(item: $selectedBusStop) { stop in
                    BusStopListView(selectedBusStop: stop)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
                .onAppear {
                    busStopProvider.fetchBusStops()
                }
                
                floatingButtons
            }
            .tabItem {
                Image(systemName: "map.fill")
                Text("Map")
            }
            .tag(0)
            
            // Second Tab for Nearby
            NearbyBusStopsView()
                .tabItem {
                    Image(systemName: "location.fill")
                    Text("Nearby")
                }
                .tag(1)
            
            // Third Tab for Favourites
            FavoritesView()
                .tabItem {
                    Image(systemName: "heart.fill")
                    Text("Favourites")
                }
                .tag(2)
            
            // Fourth Tab for Settings
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(3)
            
        }
        .onAppear {
            busStopProvider.fetchBusStops()
        }
    }
    
    private func fetchBusStops() {
        isLoading = true
        busStopProvider.fetchBusStops {
            isLoading = false
        }
    }
    
    private var floatingButtons: some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    VStack(spacing: 10) {
                        Button(action: {
                            busStopProvider.fetchBusStops()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(Color.gray)
                        }
                        
                        Button(action: {
                            if let location = busStopProvider.locationManager.currentLocation {
                                print("Button pressed. Current Latitude: \(location.coordinate.latitude), Longitude: \(location.coordinate.longitude)")
                            } else {
                                print("Button pressed but current location is nil")
                            }
                        }) {
                            Image(systemName: "location.fill")
                                .foregroundColor(Color.gray)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.15, green: 0.15, blue: 0.15).opacity(0.99)))
                    
                    Button(action: {
                        isExploreModeActive.toggle()
                        if isExploreModeActive {
                            busStopProvider.fetchBusStopsForRegion(lat: mapRegion.center.latitude, lon: mapRegion.center.longitude, radius: 200) {
                                isLoading = false
                            }
                        }
                    }) {
                        Image(systemName: "network")
                            .foregroundColor(isExploreModeActive ? Color.blue : Color.gray)
                    }
                    .frame(width: 50, height: 50)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.15, green: 0.15, blue: 0.15).opacity(0.99)))
                }
                .padding()
            }
            Spacer()
        }
        .padding()
    }
}

private func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        if granted {
            print("Notification permission granted.")
        } else if let error = error {
            print("Notification permission error: \(error)")
        }
    }
}
