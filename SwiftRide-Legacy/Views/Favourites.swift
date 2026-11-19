import SwiftUI
import CoreData
import MapKit

// MARK: - Bus Stop Extension
extension BusStop {
    init(fromFavorite favorite: FavouriteBusStop) {
        self.init(
            key: favorite.key ?? "",
            name: favorite.name ?? "",
            number: Int(favorite.stopNumber),
            direction: favorite.direction ?? "",
            side: favorite.side ?? "",
            streetName: favorite.streetName ?? "",
            streetType: favorite.streetType ?? "",
            crossStreetName: favorite.crossStreet ?? "",
            utmX: favorite.utmX ?? "",
            utmY: favorite.utmY ?? "",
            latitude: favorite.latitude,
            longitude: favorite.longitude,
            distances: favorite.distances
        )
    }
}


struct FavoritesView: View {
    // MARK: - Properties
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        entity: FavouriteBusStop.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \FavouriteBusStop.name, ascending: true)]
    ) private var favourites: FetchedResults<FavouriteBusStop>
    
    @State private var selectedBusStop: BusStop?
    @State private var searchText = ""
    @State private var showingDeleteAlert = false
    @State private var stopToDelete: FavouriteBusStop?
    @State private var isRefreshing = false
    
    // MARK: - Computed Properties
    private var filteredFavorites: [FavouriteBusStop] {
        if searchText.isEmpty {
            return Array(favourites)
        }
        return favourites.filter { favorite in
            let name = favorite.name?.lowercased() ?? ""
            let number = String(favorite.stopNumber)
            let direction = favorite.direction?.lowercased() ?? ""
            let searchQuery = searchText.lowercased()
            return name.contains(searchQuery) ||
                   number.contains(searchQuery) ||
                   direction.contains(searchQuery)
        }
    }
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            ZStack {
                if favourites.isEmpty {
                    emptyStateView
                } else {
                    mainContentView
                }
            }
            .navigationTitle("Favorites")
            .searchable(text: $searchText, prompt: "Search stops")
            .refreshable {
                await refreshFavorites()
            }
        }
        .alert("Delete Favorite", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let stop = stopToDelete {
                    deleteFavorite(stop)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove this stop from your favorites?")
        }
    }
    
    // MARK: - Subviews
    private var mainContentView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(filteredFavorites, id: \.self) { favourite in
                    FavoriteStopCard(
                        favourite: favourite,
                        onTap: {
                            selectedBusStop = BusStop(fromFavorite: favourite)
                        },
                        onDelete: {
                            stopToDelete = favourite
                            showingDeleteAlert = true
                        }
                    )
                }
            }
            .padding()
        }
        .sheet(item: $selectedBusStop) { stop in
            BusStopScheduleListView(selectedBusStop: stop)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Favorite Stops")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add stops to your favorites for quick access to schedules")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            NavigationLink(destination: EmptyView()) {
                Label("Find Stops", systemImage: "map")
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - Methods
    private func deleteFavorite(_ favorite: FavouriteBusStop) {
        withAnimation {
            viewContext.delete(favorite)
            do {
                try viewContext.save()
            } catch {
                print("Failed to delete favorite: \(error)")
            }
        }
    }
    
    private func refreshFavorites() async {
        isRefreshing = true
        // Implement refresh logic here
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        isRefreshing = false
    }
}

// MARK: - Supporting Views
struct FavoriteStopCard: View {
    let favourite: FavouriteBusStop
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Map Thumbnail
                MapThumbnail(coordinate: CLLocationCoordinate2D(
                    latitude: favourite.latitude,
                    longitude: favourite.longitude
                ))
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                // Stop Information
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(favourite.name ?? "Unknown Stop")
                            .font(.headline)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text("#\(favourite.stopNumber)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text(favourite.direction ?? "Unknown Direction")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(favourite.crossStreet ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color(UIColor.secondarySystemBackground))
            }
        }
        .buttonStyle(FavoriteCardButtonStyle())
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Remove from Favorites", systemImage: "trash")
            }
        }
    }
}

struct FavoriteCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3), value: configuration.isPressed)
    }
}

struct MapThumbnail: View {
    let coordinate: CLLocationCoordinate2D
    
    var body: some View {
        Map(coordinateRegion: .constant(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        )))
        .overlay(
            Image(systemName: "bus.fill")
                .font(.system(size: 24))
                .foregroundColor(.blue)
                .background(
                    Circle()
                        .fill(.white)
                        .frame(width: 44, height: 44)
                )
                .shadow(radius: 2)
        )
        .allowsHitTesting(false)
    }
}
