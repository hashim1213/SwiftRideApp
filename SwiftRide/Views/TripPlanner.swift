import SwiftUI

struct TripPlannerView: View {
    @StateObject var tripPlanProvider = TripPlanProvider()

    // States for user input
    @State private var origin: String = ""
    @State private var destination: String = ""
    @State private var date: Date = Date()
    @State private var time: Date = Date()
    @State private var walkSpeed: String = ""
    @State private var maxWalkTime: String = ""
    @State private var minTransferWait: String = ""
    @State private var maxTransferWait: String = ""
    @State private var maxTransfers: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                Group {
                    TextField("Origin", text: $origin)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Destination", text: $destination)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                DatePicker("Date", selection: $date, displayedComponents: .date)
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)

                Group {
                    TextField("Walk Speed (km/h)", text: $walkSpeed)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.decimalPad)
                    TextField("Max Walk Time (min)", text: $maxWalkTime)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                    TextField("Min Transfer Wait (min)", text: $minTransferWait)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                    TextField("Max Transfer Wait (min)", text: $maxTransferWait)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                    TextField("Max Transfers", text: $maxTransfers)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                }

                Button(action: planTrip) {
                    Text("Plan Trip")
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                }

                if tripPlanProvider.trips.isEmpty {
                    Text("No trips available.")
                        .padding()
                } else {
                    List(tripPlanProvider.trips) { trip in
                        TripView(trip: trip)
                    }
                }
            }
            .padding()
        }
    }

    private func planTrip() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        
        formatter.dateFormat = "HH:mm:ss"
        let timeString = formatter.string(from: time)

        let request = TripPlanRequest(
            origin: origin,
            destination: destination,
            date: dateString,
            time: timeString,
            mode: "depart-after", // Example mode
            walkSpeed: convertToFloat(walkSpeed),
            maxWalkTime: convertToInt(maxWalkTime),
            minTransferWait: convertToInt(minTransferWait),
            maxTransferWait: convertToInt(maxTransferWait),
            maxTransfers: convertToInt(maxTransfers)
        )
        tripPlanProvider.fetchTripPlans(request: request)
    }

    private func convertToInt(_ string: String) -> Int? {
        return Int(string)
    }

    private func convertToFloat(_ string: String) -> Float? {
        return Float(string)
    }
}

struct TripView: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("From: \(trip.origin)")
            Text("To: \(trip.destination)")
            Text("Departure: \(trip.departureTime)")
            Text("Arrival: \(trip.arrivalTime)")
            Text("Transfers: \(trip.numberOfTransfers)")
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}
