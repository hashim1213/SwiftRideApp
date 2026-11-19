import SwiftUI
import CoreLocation
import MessageUI

// MARK: - Search

struct SearchView: View {
    let model: NearbyModel
    let router: Router
    @State private var query = ""
    @State private var results: [TransitStop] = []
    @State private var searching = false
    @State private var recents = RecentsStore.shared
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Stop name or number", text: $query)
                        .focused($focused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.bottom, 4)

                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    if !recents.stops.isEmpty {
                        HStack {
                            Text("Recent").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear") { recents.clear() }.font(.subheadline)
                        }
                        ForEach(recents.stops) { s in StopRow(stop: s, distance: distance(s)) { router.open(.stop(s)) } }
                    }
                    Button { router.open(.cities) } label: {
                        Label("Browse \(Catalog.cities.count) cities", systemImage: "globe.americas.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .card(radius: 16)
                    }
                    .buttonStyle(PressableStyle())
                    .tint(.primary)
                    .padding(.top, 6)
                    Text("Tip: type the stop number printed on the sign, like 1602 or UN for Union Station.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                } else if searching && results.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                } else if results.isEmpty {
                    EmptyState(symbol: "magnifyingglass", title: "No matching stops",
                               message: "Search covers \(model.areaName) and nearby agencies. Try another name, or pick a different city.")
                } else {
                    ForEach(results) { s in StopRow(stop: s, distance: distance(s)) { router.open(.stop(s)) } }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true; router.detent = .large }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            searching = true
            let c = model.center ?? Catalog.city("toronto")!.coordinate
            var cityIDs: [String] = []
            if case .city(let id) = model.origin { cityIDs = [id] }
            let r = await TransitService.shared.search(query, near: c, cityIDs: cityIDs)
            guard !Task.isCancelled else { return }
            results = r
            searching = false
        }
    }

    private func distance(_ s: TransitStop) -> CLLocationDistance? {
        guard let c = model.center else { return nil }
        return s.location.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
    }
}

// MARK: - Cities

struct CityPickerView: View {
    let onPick: (City) -> Void
    @Environment(\.dismiss) private var dismiss

    private var grouped: [(String, [City])] {
        let order = ["BC", "AB", "MB", "ON", "NS"]
        let g = Dictionary(grouping: Catalog.cities, by: \.province)
        return order.compactMap { p in g[p].map { (p, $0.sorted { $0.name < $1.name }) } }
    }

    var body: some View {
        List {
            Section {
                Text("Live departures from \(Catalog.agencies.count) transit agencies across Canada, including TTC, GO Transit and UP Express.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(grouped, id: \.0) { province, cities in
                Section(Catalog.provinceNames[province] ?? province) {
                    ForEach(cities) { city in
                        Button { onPick(city) } label: {
                            HStack(spacing: 12) {
                                Text(String(city.name.prefix(1)))
                                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                                    .frame(width: 36, height: 36)
                                    .foregroundStyle(.black)
                                    .background(Theme.signal, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(city.name).font(.body.weight(.semibold))
                                    Text(city.agencies.map(\.name).joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
        }
        .navigationTitle("Cities")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Alerts

struct AlertsView: View {
    let model: NearbyModel
    @State private var showAll = false

    var body: some View {
        let list = showAll ? model.alerts : model.nearbyAlerts
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Show", selection: $showAll) {
                    Text("Near you").tag(false)
                    Text("All (\(model.alerts.count))").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)
                if list.isEmpty {
                    EmptyState(symbol: "checkmark.seal.fill", title: "All clear",
                               message: showAll ? "No service alerts right now." : "Nothing affecting the lines and stops around you.")
                } else {
                    ForEach(list) { AlertCard(alert: $0) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .navigationTitle("Service alerts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Saved

struct SavedView: View {
    let model: NearbyModel
    let router: Router
    @State private var favorites = FavoritesStore.shared
    @State private var reminders = ReminderStore.shared

    var body: some View {
        List {
            if favorites.stops.isEmpty && TripsStore.shared.trips.isEmpty {
                EmptyState(symbol: "star", title: "No saved stops yet",
                           message: "Tap the star on any stop to keep it here for one-tap access.")
                    .listRowBackground(Color.clear)
            } else {
                Section("Stops") {
                    ForEach(favorites.stops) { stop in
                        SavedStopRow(stop: stop) { router.open(.stop(stop)) }
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { favorites.move(from: $0, to: $1) }
                    .onDelete { favorites.remove(at: $0) }
                }
            }
            let trips = TripsStore.shared
            if !trips.trips.isEmpty {
                Section("Trips") {
                    ForEach(trips.trips) { t in
                        Button { router.open(.planner(from: t.from, to: t.to)) } label: {
                            Label(t.title, systemImage: "bookmark.fill")
                        }
                        .tint(.primary)
                    }
                    .onMove { trips.move(from: $0, to: $1) }
                    .onDelete { idx in idx.map { trips.trips[$0] }.forEach(trips.remove) }
                }
            }
            if !reminders.reminders.isEmpty {
                Section("Reminders") {
                    ForEach(reminders.reminders.sorted { $0.departure < $1.departure }) { r in
                        HStack {
                            Image(systemName: "bell.fill").foregroundStyle(Theme.signal)
                            VStack(alignment: .leading) {
                                Text("\(r.routeBadge) to \(r.headsign)").font(.subheadline.weight(.semibold))
                                Text("\(r.stopName) · \(TimeText.clock.string(from: r.departure))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Cancel") { reminders.cancel(id: r.id) }.font(.caption.weight(.semibold))
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !favorites.stops.isEmpty { EditButton() } }
    }
}

struct SavedStopRow: View {
    let stop: TransitStop
    let action: () -> Void
    @State private var next: [Departure] = []

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "star.fill").foregroundStyle(Theme.signal)
                    Text(stop.name).font(.headline).lineLimit(1)
                    Spacer()
                    AgencyTag(agencyID: stop.agencyID)
                }
                if next.isEmpty {
                    Text("No departures in the next while").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(next) { d in
                        HStack(spacing: 8) {
                            RouteBadge(route: d.route, size: .small)
                            Text(d.headsign).font(.subheadline).lineLimit(1)
                            Spacer()
                            if d.isRealtime { LiveIndicator() }
                            Text(TimeText.short(d.time)).font(.subheadline.weight(.bold)).monospacedDigit()
                        }
                    }
                }
            }
            .padding(14)
            .card(radius: 18)
        }
        .buttonStyle(PressableStyle())
        .tint(.primary)
        .task {
            let all = (try? await TransitService.shared.departures(for: stop)) ?? []
            var seen = Set<String>()
            next = Array(all.filter { seen.insert($0.lineKey).inserted }.prefix(3))
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    let model: NearbyModel
    let onPickCity: (City) -> Void
    let onUseLocation: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(Prefs.radius) private var radius = 600.0
    @AppStorage(Prefs.clockTimes) private var clockTimes = false
    @AppStorage(Prefs.showVehicles) private var showVehicles = true
    @State private var location = LocationService.shared
    @State private var showMail = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label("Location", systemImage: "location.fill")
                        Spacer()
                        Text(locationStatus).foregroundStyle(.secondary)
                    }
                    if location.isDenied {
                        Button("Open iOS Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                    } else {
                        Button("Use my location") { onUseLocation(); dismiss() }
                    }
                    NavigationLink {
                        CityPickerView { onPickCity($0); dismiss() }
                    } label: {
                        Label("Choose a city", systemImage: "globe.americas.fill")
                    }
                } header: { Text("Where") }

                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Search radius")
                            Spacer()
                            Text("\(Int(radius)) m · \(CLLocationDistance(radius).walkingMinutes) min walk").foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: $radius, in: 250...1500, step: 50) { editing in if !editing { model.reload() } }
                    }
                    Toggle("Show clock times", isOn: $clockTimes)
                    Toggle("Live vehicles on map", isOn: $showVehicles)
                        .onChange(of: showVehicles) { _, _ in model.reload() }
                } header: { Text("Display") } footer: {
                    Text("Clock times show “8:42 PM” instead of “12 min”. Live vehicles include GO trains across the network.")
                }

                Section("Coverage") {
                    ForEach(Catalog.agencies) { a in
                        HStack {
                            Circle().fill(Color(hex: a.brandHex) ?? .gray).frame(width: 10, height: 10)
                            Text(a.name)
                            Spacer()
                            if let url = a.website {
                                Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                            }
                        }
                    }
                }

                Section {
                    Button { if MFMailComposeViewController.canSendMail() { showMail = true } else { openURL(URL(string: "mailto:Hello@bytesavvytech.com?subject=SwiftRide%20feedback")!) } } label: {
                        Label("Send feedback", systemImage: "envelope")
                    }
                    Link(destination: URL(string: "https://apps.apple.com/app/id6472630133?action=write-review")!) {
                        Label("Rate SwiftRide", systemImage: "star.bubble")
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SwiftRide \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        Text("Transit data is provided by each agency under its open-data licence, including Winnipeg Transit, the TTC, Metrolinx (GO Transit & UP Express), and the City of Calgary. Times are estimates — always check signage at the stop.")
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showMail) { MailComposer(recipient: "Hello@bytesavvytech.com", subject: "SwiftRide feedback") }
        }
        .presentationDetents([.large])
    }

    private var locationStatus: String {
        if location.isAuthorized { return "On" }
        if location.isDenied { return "Off" }
        return "Not set"
    }
}

struct MailComposer: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func mailComposeController(_ c: MFMailComposeViewController, didFinishWith r: MFMailComposeResult, error: Error?) { dismiss() }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var location = LocationService.shared
    @State private var pickingCity = false
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.signal).frame(width: 88, height: 88)
                Image(systemName: "bus.fill").font(.system(size: 40, weight: .bold)).foregroundStyle(.black)
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            .padding(.bottom, 28)

            Text("Every ride,\nlive.")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .padding(.bottom, 14)
            Text("Real-time departures for buses, streetcars, subways and trains across Canada.")
                .font(.title3).foregroundStyle(.secondary)
                .padding(.bottom, 32)

            VStack(alignment: .leading, spacing: 18) {
                feature("dot.radiowaves.up.forward", "Live countdowns", "\(Catalog.agencies.count) agencies in \(Catalog.cities.count) cities and regions")
                feature("train.side.front.car", "GO Train & UP Express", "Platforms, delays and live train positions")
                feature("bell.badge.fill", "Never miss your bus", "Save stops and get a heads-up before it leaves")
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)

            Spacer()

            Button("Use my location") {
                location.requestPermission()
                onFinish()
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Choose a city instead") { pickingCity = true }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .tint(.primary)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.1)) { appeared = true } }
        .sheet(isPresented: $pickingCity) {
            NavigationStack {
                CityPickerView { city in
                    UserDefaults.standard.set(city.id, forKey: Prefs.manualCityID)
                    pickingCity = false
                    onFinish()
                }
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 40, height: 40)
                .foregroundStyle(Theme.signal)
                .background(Theme.signal.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
