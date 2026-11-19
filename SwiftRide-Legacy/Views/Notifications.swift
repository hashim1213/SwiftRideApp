import Foundation
import UserNotifications


//only for debugging
func scheduleNotification(for stop: ScheduledStop) {
    let content = UNMutableNotificationContent()
    
    // Use the existing minutesToEstimatedArrival
    guard let minutesToArrival = stop.minutesToEstimatedArrival, minutesToArrival > 0 else {
        print("The bus has already arrived or the arrival time is invalid.")
        return
    }

    content.title = "Bus Arrival Reminder"
    content.body = "Bus \(stop.number) is arriving in 5 minutes."

    // Set the notification to trigger when the bus is a few minutes away
    let timeIntervalBeforeArrival: TimeInterval = max(1, Double(minutesToArrival - 5)) * 60 // Trigger 5 minutes before arrival
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeIntervalBeforeArrival, repeats: false)

    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

    UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
            print("Error scheduling notification: \(error)")
        } else {
            print("Notification scheduled to remind about Bus \(stop.number) in \(minutesToArrival - 5) minutes.")
        }
    }
}


func userNotificationCenter(_ center: UNUserNotificationCenter,
                            willPresent notification: UNNotification,
                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    // Choose how to present the notification when the app is in the foreground
    completionHandler([.banner, .sound])
}


import UserNotifications
import SwiftUI

// MARK: - Notification Manager
class NotificationManager {
    static let shared = NotificationManager()
    
    private init() {}
    
    func scheduleNotification(for stop: ScheduledStop) {
        let content = UNMutableNotificationContent()
        
        // Check if the arrival time is valid
        guard let minutesToArrival = stop.minutesToEstimatedArrival,
              minutesToArrival > 0 else {
            print("The bus has already arrived or the arrival time is invalid.")
            return
        }
        
        // Configure notification content
        content.title = "Bus Arriving Soon"
        content.body = "Route \(stop.number) (\(stop.variantName)) will arrive in 5 minutes"
        content.sound = .default
        content.userInfo = [
            "stopNumber": stop.number,
            "routeName": stop.variantName
        ]
        
        // Calculate trigger time (5 minutes before arrival)
        let triggerMinutes = max(0, minutesToArrival - 5)
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(triggerMinutes * 60),
            repeats: false
        )
        
        // Create request
        let request = UNNotificationRequest(
            identifier: "busArrival-\(stop.number)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        
        // Schedule notification
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("Error scheduling notification: \(error)")
                    } else {
                        print("Notification scheduled successfully for \(stop.number) in \(triggerMinutes) minutes")
                        
                        // Post notification for UI update
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: .notificationScheduled,
                                object: nil,
                                userInfo: ["stopNumber": stop.number]
                            )
                        }
                    }
                }
            } else if let error = error {
                print("Notification authorization error: \(error)")
            }
        }
    }
    func cancelNotification(for stopNumber: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["busArrival-\(stopNumber)"]
        )
    }
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    func checkNotificationStatus(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .authorized)
            }
        }
    }
}

// MARK: - Notification Name Extension
extension Notification.Name {
    static let notificationScheduled = Notification.Name("busArrivalNotificationScheduled")
}

// MARK: - View Extension for Notifications
extension View {
    func busArrivalNotification(for stop: ScheduledStop) -> some View {
        self.modifier(BusArrivalNotificationModifier(stop: stop))
    }
}
// MARK: - Notification Modifier
struct BusArrivalNotificationModifier: ViewModifier {
    let stop: ScheduledStop
    @State private var showingNotificationAlert = false
    @State private var notificationError: String?
    
    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button(action: {
                    NotificationManager.shared.checkNotificationStatus { granted in
                        if granted {
                            NotificationManager.shared.scheduleNotification(for: stop)
                        } else {
                            notificationError = "Please enable notifications in Settings"
                            showingNotificationAlert = true
                        }
                    }
                }) {
                    Label("Set Reminder", systemImage: "bell")
                }
            }
            .alert("Notification Error", isPresented: $showingNotificationAlert, presenting: notificationError) { _ in
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { error in
                Text(error)
            }
    }
}
