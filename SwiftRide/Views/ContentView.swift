import SwiftUI

struct ContentView: View {
    @StateObject var busStopProvider = BusStopProvider.shared // Singleton instance
    @ObservedObject var tripPlanner = TripPlanner()
    @State private var selectedBusStop: BusStop? = nil
    @State private var selectedTab = 0 // State to track selected tab
    @State private var isLoading = false  // State to track loading
    
    init() {
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
                    // Map View
                    MapView(busStops: $busStopProvider.busStops, selectedBusStop: $selectedBusStop, isLoading: $isLoading)
                        .frame(maxHeight: .infinity)
                        .edgesIgnoringSafeArea(.top)
                    // If a bus stop is selected, show its details
                    if let stop = selectedBusStop {
                        BusStopListView(selectedBusStop: stop, onDismiss: {
                            self.selectedBusStop = nil  // Dismiss the BusStopListView
                        })
                        .animation(.spring())
                    }
                }
                .onAppear {
                    busStopProvider.fetchBusStops()
                }
                floatingButtons // Moved floating buttons to a separate function
            }
            .tabItem {
                Image(systemName: "map.fill")
                Text("Map")
            }
            .tag(0)
            
            // Second Tab for Nearby
            NearbyBusStopsView(busStops: $busStopProvider.busStops)
                .tabItem {
                    Image(systemName: "location.fill")
                    Text("Nearby")
                }
                .tag(1)
            
            // Third Tab for Favourites
            FavouritesView()
                .tabItem {
                    Image(systemName: "heart.fill")
                    Text("Favourites")
                }
                .tag(2)
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
    // Floating Buttons as a separate computed property
    private var floatingButtons: some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 20) {
                    // Refresh Button
                    Button(action: {
                        busStopProvider.fetchBusStops()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(Color.gray)
                    }
                    // Location Button
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

            }
            Spacer()
        }
        .padding()
    }
}

class RoundedCornerView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        if #available(iOS 13.0, *) {
            let path = UIBezierPath(roundedRect: bounds, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 10, height: 10))
            let mask = CAShapeLayer()
            mask.path = path.cgPath
            layer.mask = mask
        }
    }
}

extension UITabBar {
    func addRoundedTabBarBackground(color: UIColor, cornerRadius: CGFloat) {
        let roundedCornerView = RoundedCornerView(frame: .zero)
        roundedCornerView.backgroundColor = color
        roundedCornerView.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(roundedCornerView, at: 1)

        NSLayoutConstraint.activate([
            roundedCornerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            roundedCornerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            roundedCornerView.topAnchor.constraint(equalTo: topAnchor),
            roundedCornerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        roundedCornerView.layer.cornerRadius = cornerRadius
        roundedCornerView.layer.masksToBounds = true
        roundedCornerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner] // Top left and top right corners
    }
}
