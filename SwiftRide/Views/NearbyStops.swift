import Foundation
import SwiftUI
import CoreLocation
import MapKit

struct NearbyBusStopsView: View {
    @Binding var busStops: [BusStop]
    @StateObject var locationManager = LocationManager.shared
    @StateObject var busStopProvider = BusStopProvider.shared
    @State private var searchText: String = ""
    @State private var isLoading = false // Loading state
    @State private var selectedBusStop: BusStop?

    var filteredBusStops: [BusStop] {
        busStops.filter {
            searchText.isEmpty ? true : $0.name.lowercased().contains(searchText.lowercased())
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                searchBar
                if isLoading {
                    ProgressView()
                } else {
                    busStopList
                }
            }
            .onAppear {
                // Asynchronous fetch that won't cause immediate state changes
                 busStopProvider.fetchBusStops()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 20) {
                        refreshButton
                        locationButton
                    }
                }
            }
            .navigationBarTitle("Nearby", displayMode: .inline)
        }
    }

    private func fetchBusStops() {
        DispatchQueue.main.async {
            self.isLoading = true
        }
        busStopProvider.fetchBusStops {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }
}

// MARK: - UI Components
private extension NearbyBusStopsView {
    var searchBar: some View {
        TextField("Search for bus stops", text: $searchText)
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .padding([.leading, .trailing], 10)
    }

    var busStopList: some View {
           List(filteredBusStops.unique(), id: \.id) { stop in
               Button(action: {
                   self.selectedBusStop = stop // Set the selected bus stop when tapped
               }) {
                   BusStopRow(stop: stop)
                       .background(Color.gray.opacity(0.1))
                       .cornerRadius(20)
                       .padding([.top, .bottom], 5)
               }
               .listRowSeparator(.hidden)
           }
           .listRowSeparator(.hidden)
           .listStyle(PlainListStyle())
           .sheet(item: $selectedBusStop) { stop in
               // Present the BusStopScheduleListView for the selected bus stop
               BusStopScheduleListView(selectedBusStop: stop)
           }
       }

    var refreshButton: some View {
        Button(action: {
            isLoading = true // Start loading
            busStopProvider.fetchBusStops {
                isLoading = false // Stop loading when data is fetched
            }
        }) {
            Image(systemName: "arrow.clockwise")
                .foregroundColor(Color.blue)
        }
    }

    var locationButton: some View {
        Button(action: printLocation) {
            Image(systemName: "location.fill")
                .foregroundColor(Color.blue)
        }
    }
}

private extension NearbyBusStopsView {
    func printLocation() {
        if let location = locationManager.currentLocation {
            print("Current Latitude: \(location.coordinate.latitude), Longitude: \(location.coordinate.longitude)")
        } else {
            print("Current location is nil")
        }
    }
}


extension Array where Element: Hashable {
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

struct BusStopRow: View {
    var stop: BusStop
   
    @State private var annotations: [IdentifiableMKPointAnnotation] = []
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.8951, longitude: -97.1384), // Default to Winnipeg; replace with actual coordinates
        span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
    )
    var body: some View {
        HStack {
            StaticMapView(coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude))
                 .frame(width: 100)
                 .frame(height: 100)
                 .cornerRadius(8)
            
            VStack(alignment: .leading) {
                       Text("\(stop.direction) - \(stop.name) @ \(stop.crossStreetName)")
                           .font(.headline)
                           .foregroundColor(Color.blue)
                       Text("#\(String(stop.number))")
                           .font(.headline)
                           .foregroundColor(Color.gray)
                   }
                   .frame(maxWidth: .infinity, alignment: .leading) // Ensures the VStack takes all available width
               }
        
        .padding()
        .onAppear {
            // Create an annotation
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)
            annotations.append(IdentifiableMKPointAnnotation(annotation))
            
            // Update the map region when the view appears
            region.center = annotation.coordinate
        }
    }
    
    
}
