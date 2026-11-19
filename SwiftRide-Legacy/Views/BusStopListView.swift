import SwiftUI
import CoreData
import ActivityKit

struct BusStopListView: View {
    let selectedBusStop: BusStop
    @StateObject private var viewModel: BusStopListViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingFavoriteAlert = false
    @AppStorage("showDate") private var showDate = true
    let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    
    init(selectedBusStop: BusStop) {
        self.selectedBusStop = selectedBusStop
        _viewModel = StateObject(wrappedValue: BusStopListViewModel(stopId: selectedBusStop.number, busStop: selectedBusStop))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    stopHeader
                    
                    Divider()
                        .padding(.horizontal)
                    
                    if viewModel.isLoading {
                        LoadingView()
                            .padding()
                    } else if viewModel.scheduledStops.isEmpty {
                        EmptyStateView(onRefresh: {
                            Task { await viewModel.refreshData() }
                        })
                        .padding()
                    } else {
                        arrivalsList
                    }
                }
            }
            .navigationBarItems(
                leading: Text(selectedBusStop.name)
                    .font(.headline),
                trailing: HStack(spacing: 16) {
                    favoriteButton
                    closeButton
                }
            )
            .refreshable { await viewModel.refreshData() }
        }
        .task { await viewModel.refreshData() }
        .onReceive(timer) { _ in
            Task { await viewModel.refreshData() }
        }
    }
    
    private var stopHeader: some View {
        VStack(spacing: 8) {
            // Stop info and direction
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("#\(selectedBusStop.number)")
                        .font(.title2.bold())
                    
                    Text(selectedBusStop.direction)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                StopFeaturesView(features: viewModel.stopFeatures)
            }
            
            // Next bus time and routes
            HStack(spacing: 24) {
                // Next bus
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next bus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(viewModel.nextBusTime)
                        .font(.system(size: 24, weight: .bold))
                }
                
                Divider()
                    .frame(height: 30)
                
                // Routes
                VStack(alignment: .leading, spacing: 2) {
                    Text("Routes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("\(viewModel.uniqueRoutes.count)")
                        .font(.title3.bold())
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
    }
    
    private var arrivalsList: some View {
        LazyVStack(spacing: 1) {
            ForEach(viewModel.scheduledStops) { stop in
                ArrivalRow(stop: stop, onReminderTap: {
                    viewModel.setReminder(for: stop)
                })
            }
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
    }
    
    private var favoriteButton: some View {
        Button(action: { showingFavoriteAlert = true }) {
            Image(systemName: "heart")
                .symbolVariant(viewModel.isFavorite ? .fill : .none)
                .foregroundStyle(viewModel.isFavorite ? .red : .gray)
        }
    }
    
    private var closeButton: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "xmark")
                .foregroundColor(.primary)
        }
    }
}

struct ArrivalRow: View {
    let stop: ScheduledStop
    let onReminderTap: () -> Void
    
    private var timeColor: Color {
        guard let minutes = stop.minutesToEstimatedArrival else { return .primary }
        switch minutes {
        case ..<0: return .red
        case 0...5: return .green
        case 6...10: return .orange
        default: return .primary
        }
    }
    
    private var backgroundColor: Color {
        guard let minutes = stop.minutesToEstimatedArrival else { return Color(UIColor.secondarySystemBackground) }
        switch minutes {
        case 0...5: return Color.green.opacity(0.15)
        case 6...10: return Color.orange.opacity(0.1)
        case ..<0: return Color.red.opacity(0.1)
        default: return Color(UIColor.secondarySystemBackground)
        }
    }
    
    private var timeDifference: Int? {
        guard let scheduled = stop.minutesToScheduledArrival,
              let estimated = stop.minutesToEstimatedArrival
        else { return nil }
        return estimated - scheduled
    }
    
    @ViewBuilder
    private func timeDisplay() -> some View {
        if let minutes = stop.minutesToEstimatedArrival {
            if minutes < 0 {
                Text("Due")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.red)
            } else if minutes == 0 {
                Text("Now")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.green)
            } else if minutes > 180 { // More than 3 hours
                VStack(alignment: .trailing, spacing: 2) {
                    Text(stop.scheduledArrival)
                        .font(.system(size: 24, weight: .heavy))
                    Text(formatDate(from: stop.scheduledArrival))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if minutes > 60 { // More than 1 hour
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(minutes / 60)h \(minutes % 60)m")
                            .font(.system(size: 24, weight: .heavy))
                    }
                    Text("(\(stop.scheduledArrival))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(minutes)")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(timeColor)
                    Text("min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .offset(y: 2)
                }
            }
        } else {
            Text("--")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.secondary)
        }
    }
    
    private func formatDate(from dateString: String) -> String {
        // Add your date formatting logic here based on your date string format
        return dateString
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Left side info
            VStack(alignment: .leading, spacing: 8) {
                Text(stop.number)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(UIColor.systemBackground))
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.variantName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if let difference = timeDifference, abs(difference) > 1 {
                        HStack(spacing: 4) {
                            Image(systemName: difference > 0 ? "arrow.up" : "arrow.down")
                            Text("\(abs(difference)) min \(difference > 0 ? "behind" : "ahead")")
                        }
                        .font(.caption2)
                        .foregroundStyle(difference > 0 ? .red : .green)
                    }
                }
            }
            
            Spacer(minLength: 16)
            
            // Right side - time display
            timeDisplay()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(backgroundColor)
        .cornerRadius(0)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
        .contextMenu {
            Button(action: onReminderTap) {
                Label("Set Reminder", systemImage: "bell")
            }
            
            if let minutes = stop.minutesToEstimatedArrival, minutes > 0 {
                Button(action: {
                    // Add to calendar functionality
                }) {
                    Label("Add to Calendar", systemImage: "calendar")
                }
            }
            
            Button(action: {
                // Share functionality
            }) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}
// Helper extension to format time strings
extension Date {
    func timeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: self)
    }
}
struct StopStatView: View {
    let icon: String
    let title: String
    let value: String
    let isLarge: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            
            Text(value)
                .font(isLarge ? .system(size: 36, weight: .bold) : .title3.bold())
                .foregroundColor(.primary)
        }
    }
}
import CoreData
import UserNotifications
import SwiftUI


class BusStopListViewModel: ObservableObject {
    @Published private(set) var scheduledStops: [ScheduledStop] = []
      @Published private(set) var stopFeatures: Set<String> = []
      @Published private(set) var isLoading = false
      @Published private(set) var error: Error?
      @Published private(set) var isFavorite = false
      
      private let stopId: Int
      private let busStop: BusStop
      private let scheduledStopProvider: ScheduledStopProvider
      private let featuresProvider: BusStopFeatures
      private let viewContext: NSManagedObjectContext
      
      init(stopId: Int, busStop: BusStop) {
          self.stopId = stopId
          self.busStop = busStop
          self.scheduledStopProvider = ScheduledStopProvider(stopId: stopId)
          self.featuresProvider = BusStopFeatures(stopId: stopId)
          self.viewContext = PersistenceController.shared.container.viewContext
          
          checkFavoriteStatus()
      }
      
      var uniqueRoutes: Set<String> {
          Set(scheduledStops.map { $0.number })
      }
      
      var nextBusTime: String {
          guard let nextBus = scheduledStops.first else { return "No buses" }
          return formatMinutes(nextBus.minutesToEstimatedArrival ?? 0)
      }
    @MainActor
    func refreshData() async {
        isLoading = true
        do {
            async let stops = fetchScheduledStops()
            async let features = fetchStopFeatures()
            
            let (fetchedStops, fetchedFeatures) = try await (stops, features)
            
            scheduledStops = fetchedStops.sorted { $0.scheduledArrival < $1.scheduledArrival }
            stopFeatures = Set(fetchedFeatures.map { $0.name })
        } catch {
            self.error = error
        }
        isLoading = false
    }
    
    func toggleFavorite() {
        if isFavorite {
            removeFavorite()
        } else {
            addFavorite()
        }
    }
    
    private func addFavorite() {
           let favorite = FavouriteBusStop(context: viewContext)
           
           // Set all properties from BusStop
           favorite.key = busStop.key
           favorite.name = busStop.name
           favorite.stopNumber = Int64(busStop.number)
           favorite.direction = busStop.direction
           favorite.side = busStop.side
           favorite.streetName = busStop.streetName
           favorite.streetType = busStop.streetType
           favorite.crossStreet = busStop.crossStreetName
           favorite.utmX = busStop.utmX
           favorite.utmY = busStop.utmY
           favorite.latitude = busStop.latitude
           favorite.longitude = busStop.longitude
           favorite.distances = busStop.distances
     
           
           do {
               try viewContext.save()
               withAnimation {
                   self.isFavorite = true
               }
           } catch {
               print("Error saving favorite: \(error)")
           }
       }
    
    private func removeFavorite() {
          let fetchRequest: NSFetchRequest<FavouriteBusStop> = FavouriteBusStop.fetchRequest()
          fetchRequest.predicate = NSPredicate(format: "stopNumber == %d", stopId)
          
          do {
              let results = try viewContext.fetch(fetchRequest)
              if let favorite = results.first {
                  viewContext.delete(favorite)
                  try viewContext.save()
                  withAnimation {
                      self.isFavorite = false
                  }
              }
          } catch {
              print("Error removing favorite: \(error)")
          }
      }
      
    
    private func checkFavoriteStatus() {
          let fetchRequest: NSFetchRequest<FavouriteBusStop> = FavouriteBusStop.fetchRequest()
          fetchRequest.predicate = NSPredicate(format: "stopNumber == %d", stopId)
          
          do {
              let count = try viewContext.count(for: fetchRequest)
              DispatchQueue.main.async {
                  self.isFavorite = count > 0
              }
          } catch {
              print("Error checking favorite status: \(error)")
          }
      }
      
    func setReminder(for stop: ScheduledStop) {
        requestNotificationPermission { granted in
            guard granted else {
                // Handle case where permission is not granted
                return
            }
            
            self.scheduleNotification(for: stop)
        }
    }
    
    private func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error requesting notification permission: \(error)")
                }
                completion(granted)
            }
        }
    }
    
    private func scheduleNotification(for stop: ScheduledStop) {
        guard let minutesToArrival = stop.minutesToEstimatedArrival else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Bus \(stop.number) Arriving Soon"
        content.body = "Arriving at \(busStop.name) in 2 minutes"
        content.sound = .default
        
        // Calculate notification time (5 minutes before arrival)
        let triggerDate = Calendar.current.date(
            byAdding: .minute,
            value: -(minutesToArrival - 2),
            to: Date()
        )
        
        guard let triggerDate = triggerDate else { return }
        
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: triggerDate
        )
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "busArrival-\(stop.key)-\(busStop.number)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            }
        }
    }

    private func fetchScheduledStops() async throws -> [ScheduledStop] {
        return try await scheduledStopProvider.fetchScheduledStops()
    }
    
    private func fetchStopFeatures() async throws -> [BusStopFeature] {
        return try await featuresProvider.fetchBusStopFeatures(stopId: stopId)
    }
    
    private func formatMinutes(_ minutes: Int) -> String {
        switch minutes {
        case -1: return "N/A"
        case 0: return "Now"
        case ..<0: return "Late"
        case 60...: return "\(minutes / 60)h \(minutes % 60)m"
        default: return "\(minutes)m"
        }
    }
}
