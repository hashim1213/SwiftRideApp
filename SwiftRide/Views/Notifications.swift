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
    content.body = "Bus \(stop.number) is arriving in \(minutesToArrival) minutes."

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


/*
func scheduleNotification(for stop: ScheduledStop) {
    let content = UNMutableNotificationContent()
    content.title = "Bus Arrival Reminder"
    content.body = "Bus \(stop.number) is arriving soon."

    guard let minutesToEstimatedArrival = stop.minutesToEstimatedArrival else {
        print("Invalid estimated arrival time.")
        return
    }

    // Calculate the time interval in seconds
    let timeInterval = TimeInterval(minutesToEstimatedArrival * 60)

    // Check if the bus has already arrived or is about to arrive
    if timeInterval <= 0 {
        print("The bus has already arrived or is about to arrive.")
        return
    }

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)

    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

    UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
            print("Error scheduling notification: \(error)")
        } else {
            print("Notification scheduled for Bus \(stop.number) in \(minutesToEstimatedArrival) minutes.")
        }
    }
}
*/
