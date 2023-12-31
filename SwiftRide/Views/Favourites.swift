import SwiftUI
import CoreData
import MapKit

struct FavouritesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        entity: FavouriteBusStop.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \FavouriteBusStop.name, ascending: true)]
    ) var favourites: FetchedResults<FavouriteBusStop>

    @State private var selectedBusStop: BusStop?  // State for the selected bus stop

    var body: some View {
        NavigationView {
            List {
                ForEach(favourites, id: \.self) { favourite in
                    // Use a button or other view to set the selected bus stop
                    Button(action: {
                        self.selectedBusStop = BusStop(favourite: favourite)
                    }) {
                        ThumbnailView(favourite: favourite)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                            .padding([.top, .bottom], 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .onDelete(perform: deleteFavourite)
                .listRowSeparator(.hidden)
            }
            .sheet(item: $selectedBusStop) { stop in
                // Present the BusStopScheduleListView for the selected bus stop
                BusStopScheduleListView(selectedBusStop: stop)
            }
            .navigationTitle("Favourites")
            .listStyle(PlainListStyle())
            .listRowSeparator(.hidden)
        }
    }

    private func deleteFavourite(at offsets: IndexSet) {
        for index in offsets {
            let favourite = favourites[index]
            viewContext.delete(favourite)
        }

        do {
            try viewContext.save()
        } catch {
            print("Failed to delete favourite: \(error)")
        }
    }
}
    

class IdentifiableMKPointAnnotation: Identifiable {
    let id = UUID()
    let annotation: MKPointAnnotation

    init(_ annotation: MKPointAnnotation) {
        self.annotation = annotation
    }
}

struct ThumbnailView: View {
    var favourite: FavouriteBusStop  // The Core Data entity

    var body: some View {
        VStack {
            StaticMapView(coordinate: CLLocationCoordinate2D(latitude: favourite.latitude, longitude: favourite.longitude))
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .cornerRadius(8)

            VStack {
                Text("\(favourite.direction ?? "Unknown Direction") - \(favourite.name ?? "Unknown Name") @ \(favourite.crossStreet ?? "Unknown")")
                    .font(.headline)
                    .foregroundColor(Color.blue)
                Text("#\(String(favourite.stopNumber))")
                    .font(.headline)
                    .foregroundColor(Color.gray)
               
            }
        }
        .padding()
        
    }
}


