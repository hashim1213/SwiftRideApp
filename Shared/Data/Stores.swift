import Foundation
import CoreLocation
import CoreData
import UserNotifications
import Observation
import WidgetKit

// MARK: - Location

@MainActor @Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private(set) var location: CLLocation?
    private(set) var status: CLAuthorizationStatus
    private let manager = CLLocationManager()

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
        location = manager.location
    }

    var isAuthorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    var isDenied: Bool { status == .denied || status == .restricted }

    func requestPermission() { manager.requestWhenInUseAuthorization() }
    func start() { if isAuthorized { manager.startUpdatingLocation() } }
    func stop() { manager.stopUpdatingLocation() }

    /// During a guided trip: keep updating in the background (blue pill) so the Live Activity can advance.
    func setTripTracking(_ on: Bool) {
        let canBackground = (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("location") == true
        if canBackground { manager.allowsBackgroundLocationUpdates = on }
        manager.pausesLocationUpdatesAutomatically = !on
        manager.showsBackgroundLocationIndicator = on
        if on { start() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.status = s
            if self.isAuthorized { self.manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last, last.horizontalAccuracy >= 0, last.horizontalAccuracy < 500 else { return }
        Task { @MainActor in
            self.location = last
            AppGroup.defaults.set(last.coordinate.latitude, forKey: AppGroup.lastLatKey)
            AppGroup.defaults.set(last.coordinate.longitude, forKey: AppGroup.lastLonKey)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - Saved stops

@MainActor @Observable
final class FavoritesStore {
    static let shared = FavoritesStore()
    private(set) var stops: [TransitStop] = []
    private let key = "savedStops.v4"

    init() {
        if let d = AppGroup.data(forKey: key), let s = try? JSONDecoder().decode([TransitStop].self, from: d) {
            stops = s
        } else {
            stops = Self.migrateLegacyFavourites()
            persist()
        }
    }

    func contains(_ stop: TransitStop) -> Bool { stops.contains { $0.id == stop.id } }

    func toggle(_ stop: TransitStop) {
        if let i = stops.firstIndex(where: { $0.id == stop.id }) { stops.remove(at: i) } else { stops.insert(stop, at: 0) }
        persist()
    }

    func move(from: IndexSet, to: Int) { stops.move(fromOffsets: from, toOffset: to); persist() }
    func remove(at offsets: IndexSet) { stops.remove(atOffsets: offsets); persist() }

    private func persist() {
        if let d = try? JSONEncoder().encode(stops) { AppGroup.defaults.set(d, forKey: key) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Fresh copy straight from shared storage (used by widgets, which don't hold the store).
    nonisolated static func load() -> [TransitStop] {
        guard let d = AppGroup.data(forKey: "savedStops.v4") else { return [] }
        return (try? JSONDecoder().decode([TransitStop].self, from: d)) ?? []
    }

    /// SwiftRide 3 kept Winnipeg favourites in Core Data; carry them over once.
    private static func migrateLegacyFavourites() -> [TransitStop] {
        guard let modelURL = Bundle.main.url(forResource: "SwiftRide", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else { return [] }
        let container = NSPersistentContainer(name: "SwiftRide", managedObjectModel: model)
        let storeURL = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("SwiftRide.sqlite")
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return [] }
        var loaded = false
        container.loadPersistentStores { _, error in loaded = error == nil }
        guard loaded else { return [] }
        let request = NSFetchRequest<NSManagedObject>(entityName: "FavouriteBusStop")
        let rows = (try? container.viewContext.fetch(request)) ?? []
        return rows.compactMap { o in
            guard let number = o.value(forKey: "stopNumber") as? Int64, number > 0 else { return nil }
            return TransitStop(agencyID: Winnipeg.agencyID, stopID: String(number), code: "",
                               name: o.value(forKey: "name") as? String ?? "Stop \(number)",
                               latitude: o.value(forKey: "latitude") as? Double ?? 0,
                               longitude: o.value(forKey: "longitude") as? Double ?? 0, routeIDs: [])
        }
    }
}

// MARK: - Recent searches

@MainActor @Observable
final class RecentsStore {
    static let shared = RecentsStore()
    private(set) var stops: [TransitStop] = []
    private let key = "recentStops.v4"

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode([TransitStop].self, from: d) { stops = s }
    }

    func add(_ stop: TransitStop) {
        stops.removeAll { $0.id == stop.id }
        stops.insert(stop, at: 0)
        stops = Array(stops.prefix(8))
        if let d = try? JSONEncoder().encode(stops) { UserDefaults.standard.set(d, forKey: key) }
    }

    func clear() { stops = []; UserDefaults.standard.removeObject(forKey: key) }
}

// MARK: - Departure reminders

@MainActor @Observable
final class ReminderStore {
    static let shared = ReminderStore()

    struct Reminder: Codable, Identifiable, Hashable {
        let id: String
        let stopName: String
        let routeBadge: String
        let headsign: String
        let departure: Date
        let leadMinutes: Int
        var fireDate: Date { departure.addingTimeInterval(TimeInterval(-leadMinutes * 60)) }
    }

    private(set) var reminders: [Reminder] = []
    private let key = "reminders.v4"

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let r = try? JSONDecoder().decode([Reminder].self, from: d) {
            reminders = r.filter { $0.departure > Date() }
        }
    }

    func has(_ departure: Departure) -> Bool { reminders.contains { $0.id == departure.id } }

    /// Schedules a local notification `leadMinutes` before the departure. Returns false if notifications are off.
    @discardableResult
    func schedule(_ departure: Departure, at stop: TransitStop, leadMinutes: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }
        let r = Reminder(id: departure.id, stopName: stop.name, routeBadge: departure.route.badgeText,
                         headsign: departure.headsign, departure: departure.time, leadMinutes: leadMinutes)
        let content = UNMutableNotificationContent()
        content.title = "\(r.routeBadge) to \(r.headsign)"
        content.body = leadMinutes == 0 ? "Leaving \(r.stopName) now." : "Leaves \(r.stopName) in \(leadMinutes) min — time to head out."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let interval = max(5, r.fireDate.timeIntervalSinceNow)
        let request = UNNotificationRequest(identifier: r.id, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
        do { try await center.add(request) } catch { return false }
        reminders.removeAll { $0.id == r.id }
        reminders.append(r)
        persist()
        return true
    }

    func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        reminders.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(reminders) { UserDefaults.standard.set(d, forKey: key) }
    }
}

// MARK: - Preferences

enum Prefs {
    static let radius = "searchRadius"              // metres
    static let clockTimes = "showClockTimes"        // show 8:42 PM instead of "12 min"
    static let showVehicles = "showLiveVehicles"
    static let manualCityID = "manualCityID"
    static let onboarded = "onboarded.v4"
    static let reminderLead = "reminderLead"

    static func register() {
        UserDefaults.standard.register(defaults: [radius: 600.0, clockTimes: false, showVehicles: true, reminderLead: 5])
    }
}
