import SwiftUI
import CoreData

struct BusStopListView: View {
    var selectedBusStop: BusStop  // Injected
    @ObservedObject var scheduledStopProvider: ScheduledStopProvider
    @ObservedObject var busStopFeature: BusStopFeatures
    var onDismiss: () -> Void  //dismiss the busstoplistview
    @State private var showingSheet = false
    @State private var selectedBus: ScheduledStop?
    @State private var showingFavoriteAlert = false
    
    
    init(selectedBusStop: BusStop, onDismiss: @escaping () -> Void) {
        self.selectedBusStop = selectedBusStop
        self.onDismiss = onDismiss
        self.scheduledStopProvider = ScheduledStopProvider(stopId: Int(selectedBusStop.number))
        self.busStopFeature = BusStopFeatures(stopId: Int(selectedBusStop.number))  // Initialize here
    }
    var sortedStops: [ScheduledStop] {
          return scheduledStopProvider.scheduledStops.sorted(by: { $0.scheduledArrival < $1.scheduledArrival })
      }
    
    func cardTapped(_ stop: ScheduledStop) {
        self.selectedBus = stop
        self.showingSheet = true
    }

    var body: some View {
        NavigationView {
            VStack{
                // "X" Button to dismiss
                HStack {
                    Button(action: {
                        self.showingFavoriteAlert = true  // Show the favorite alert
                    }) {
                        Image(systemName: "heart")
                            .resizable()
                            .frame(width: 20, height: 18)
                            .foregroundColor(Color.gray)
                    } .alert(isPresented: $showingFavoriteAlert) {
                        Alert(title: Text("Favorite this Bus Stop"),
                              message: Text("add this bus stop to favorites"),
                              primaryButton: .default(Text("Save"), action: {
                                saveToCoreData(name: selectedBusStop.name,
                                               stopNumber: selectedBusStop.number,
                                               direction: selectedBusStop.direction,
                                               crossStreet: selectedBusStop.crossStreetName,
                                               latitude: selectedBusStop.latitude,
                                               longitude: selectedBusStop.longitude
                                               )
                                              
                              }),
                              secondaryButton: .cancel())
                    }
                    Spacer()
                    VStack{
                        // Header Text
                        Text("\(selectedBusStop.direction) - \(selectedBusStop.name)")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(Color.blue)
                        
                        // Sub-header with Cross Street
                        Text("@ \(selectedBusStop.crossStreetName)")
                            .font(.headline)
                            .foregroundColor(Color.gray)
                    }
                    Spacer()
                    Button(action: {
                        self.onDismiss()  // Call the dismiss closure
                    }) {
                        Image(systemName: "xmark")
                            .resizable()
                            .frame(width: 15, height: 15)
                            .foregroundColor(Color.gray)
                    }
                    
                }
                ScrollView {
                    VStack {
                        // Main Header Container
                        VStack {
                           
                            
                            // Stop Features and Stop Number
                            HStack(spacing: 20) {
                                // Stop Number
                                
                                Text("#\(String(selectedBusStop.number))")
                                    .font(.headline)
                                    .foregroundColor(Color.gray)
                                
                                Spacer()
                                
                                let features = busStopFeature.busStopFeatures
                                
                                // Feature Icons
                                HStack(spacing: 15) {
                                    // Heated
                                    Image(systemName: "thermometer")
                                        .resizable()
                                        .frame(width: 10, height: 15)
                                        .foregroundColor(features.contains { $0.name == "Heated Shelter" } ? .red : .gray)
                                    
                                    // Bench
                                    Image(features.contains { $0.name == "Bench" } ? "bench2_green" : "bench2_gray")
                                        .resizable()
                                        .frame(width: 15, height: 15)
                                    
                                    // Bike sign
                                    Image(features.contains { $0.name == "Bike Rack/Locker" } ? "rack_green" : "rack_grey")
                                        .resizable()
                                        .frame(width: 20, height: 15)
                                    
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        // Schedule
                        ForEach(scheduledStopProvider.scheduledStops.sorted(by: { $0.scheduledArrival < $1.scheduledArrival })) { scheduledStop in
                            CardView(scheduledStop: scheduledStop)
                             
                        }
                    }
                }
                .padding(.top, 20)
                .navigationBarHidden(true)
                
            }
        }
        .onAppear {
            self.scheduledStopProvider.fetchScheduledStops()
            self.busStopFeature.fetchBusStopFeatures(stopId: Int(self.selectedBusStop.number))
              }
    }
    // Fetch data when the view appears
    func favoriteBusStop() {
        self.showingFavoriteAlert = true
    }
    func saveToCoreData(name: String, stopNumber: Int, direction: String, crossStreet: String, latitude: Double, longitude: Double) {
        let context = CoreDataManager.shared.container.viewContext
        let newFavorite = FavouriteBusStop(context: context)
        newFavorite.name = name
        newFavorite.stopNumber = Int64(stopNumber)
        newFavorite.direction = direction
        newFavorite.crossStreet = crossStreet
        newFavorite.latitude = Double(latitude)
        newFavorite.longitude = Double(longitude)
        do {
            try context.save()
            print("Favorite saved.")
        } catch {
            print("Failed saving favorite: \(error)")
        }
    }

 }


struct CardView: View {
    var scheduledStop: ScheduledStop
    @State private var isReminderSet = false
    // Function to determine text color based on time
        private func colorForTime(_ minutes: Int) -> Color {
            if minutes == 0 {
                return Color.blue
            } else if minutes < 10 {
                return Color.red
            } else if minutes < 30 {
                return Color.green
            } else {
                return Color.white
            }
        }
    func getTime(from dateString: String?) -> String? {
        guard let dateString = dateString else {
            print("Date string is nil")
            return nil
        }
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        isoFormatter.timeZone = TimeZone(abbreviation: "UTC")  // Set to UTC
        
        if let date = isoFormatter.date(from: dateString) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm:ss"
            
            // Manually adjust the time to Winnipeg time zone
            if let winnipegTimeZone = TimeZone(identifier: "America/Winnipeg") {
                let secondsFromGMT = winnipegTimeZone.secondsFromGMT(for: date)
                let adjustedDate = date.addingTimeInterval(TimeInterval(-secondsFromGMT))
                return timeFormatter.string(from: adjustedDate)
            } else {
                print("Failed to find Winnipeg time zone")
                return nil
            }
        } else {
            print("Failed to convert date string: \(dateString)")
            return nil
        }
    }


    func convertMinutesToHoursAndMinutes(minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours) hr \(remainingMinutes) mins"
        } else {
            return "\(minutes) mins"
        }
    }
    var body: some View {
        
        VStack {
            ZStack {
                VStack(alignment: .leading) {
                    HStack{
                        Image(systemName: "bus")
                            .foregroundColor(Color.blue)
                            .frame(width: 10, height: 10)
                        Text("\(scheduledStop.number)")
                        Text("\(scheduledStop.variantName)")
                            .fontWeight(.bold)
                        Spacer()
                        // Reminder Button with an Icon
                          Button(action: {
                              scheduleNotification(for: scheduledStop)
                              isReminderSet = true // Set the state to true to show the alert
                            
                          }) {
                              Image(systemName: "bell")
                                  .resizable()
                                  .scaledToFit()
                                  .frame(width: 20, height: 20)
                                  .foregroundColor(Color.white)
                                  .padding(10)
                                  .cornerRadius(8)
                          }
                          .alert(isPresented: $isReminderSet) {
                                       Alert(
                                           title: Text("Reminder Set"),
                                           message: Text("A reminder for Bus \(scheduledStop.number) has been set."),
                                           dismissButton: .default(Text("OK"))
                                       )
                                   }
                      
                    }
                    HStack {
                        Text("Scheduled Arrival:")
                        Spacer()
                        VStack(alignment: .trailing) {
                            if let minutesToScheduled = scheduledStop.minutesToScheduledArrival {
                                if minutesToScheduled == -1 {
                                    Text("N/A")
                                        .fontWeight(.semibold)
                                        .foregroundColor(Color.gray)
                                } else {
                                    Text(minutesToScheduled < 0 ? "Late" : (minutesToScheduled == 0 ? "Due" : convertMinutesToHoursAndMinutes(minutes: minutesToScheduled)))
                                        .fontWeight(.semibold)
                                        .foregroundColor(colorForTime(minutesToScheduled))
                                }
                                if let timeString = getTime(from: scheduledStop.scheduledArrival) {
                                    Text(timeString)
                                        .font(.caption)
                                }
                            }
                        }
                    }

                    HStack {
                        Text("Estimated Arrival:")
                        Spacer()
                        VStack(alignment: .trailing) {
                            if let minutesToEstimated = scheduledStop.minutesToEstimatedArrival {
                                if minutesToEstimated == -1 {
                                    Text("Late")
                                        .fontWeight(.semibold)
                                        .foregroundColor(Color.gray)
                                } else {
                                    Text(minutesToEstimated == 0 ? "Now" : convertMinutesToHoursAndMinutes(minutes: minutesToEstimated))
                                        .fontWeight(.semibold)
                                        .foregroundColor(colorForTime(minutesToEstimated))
                                }
                                if let timeString = getTime(from: scheduledStop.estimatedArrival) {
                                    Text(timeString)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    
                    HStack(spacing: 20) {
                        Spacer()  // push the icons to the right
                        
                        Image(systemName: "figure.roll")
                            .foregroundColor(scheduledStop.easyAccess ? Color.green : Color.gray)
                            .frame(width: 5, height: 5)
                        
                        Image(systemName: "wifi.circle")
                            .foregroundColor(scheduledStop.wifi ? Color.green : Color.gray)
                            .frame(width: 5, height: 5)
                        
                        Image(systemName: "bicycle.circle")
                            .foregroundColor(scheduledStop.bikeRack ? Color.green : Color.gray)
                            .frame(width: 5, height: 5)
                    }
                    .padding(.horizontal, 8)  // Padding to move the icons away from the edge of the card
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding([.top, .bottom], 5)
            }
             
         
        }
    }
}
