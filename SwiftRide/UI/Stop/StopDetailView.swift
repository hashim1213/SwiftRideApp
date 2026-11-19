import SwiftUI
import MapKit

struct StopDetailView: View {
    let stop: TransitStop
    let model: NearbyModel
    let router: Router

    enum Layout: String, CaseIterable { case byLine = "By line", byTime = "By time" }

    @State private var departures: [Departure] = []
    @State private var routes: [TransitRoute] = []
    @State private var alerts: [ServiceAlert] = []
    @State private var loading = true
    @State private var error: String?
    @State private var layout: Layout = .byLine
    @State private var reminderTarget: Departure?
    @State private var toast: String?
    @State private var showAlerts = false
    @State private var at: Date?          // nil = live, otherwise show the timetable from this time
    @State private var pickingTime = false
    @State private var favorites = FavoritesStore.shared
    @State private var reminders = ReminderStore.shared
    @AppStorage(Prefs.clockTimes) private var clockTimes = false
    @Environment(\.scenePhase) private var scenePhase

    private var agency: Agency? { Catalog.agency(stop.agencyID) }
    private var distance: CLLocationDistance? { stop.distance(from: LocationService.shared.location) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                actions
                if !alerts.isEmpty { alertsSummary }
                timeChips
                if !departures.isEmpty {
                    Picker("Layout", selection: $layout) {
                        ForEach(Layout.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
                departuresSection(for: layout)
                footer
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable { await load() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(stop.name).font(.headline).lineLimit(1)
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { favorites.toggle(stop) } label: {
                    Image(systemName: favorites.contains(stop) ? "star.fill" : "star")
                        .foregroundStyle(favorites.contains(stop) ? Theme.signal : .primary)
                }
                .sensoryFeedback(.success, trigger: favorites.contains(stop))
                .accessibilityLabel(favorites.contains(stop) ? "Remove from saved" : "Save stop")
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .confirmationDialog(reminderTitle, isPresented: Binding(get: { reminderTarget != nil }, set: { if !$0 { reminderTarget = nil } }),
                            titleVisibility: .visible) {
            if let d = reminderTarget {
                if reminders.has(d) {
                    Button("Cancel reminder", role: .destructive) { reminders.cancel(id: d.id); show("Reminder cancelled") }
                } else {
                    ForEach([0, 2, 5, 10, 15].filter { d.time.timeIntervalSinceNow > Double($0 * 60 + 30) }, id: \.self) { m in
                        Button(m == 0 ? "When it leaves" : "\(m) min before") { remind(d, lead: m) }
                    }
                }
            }
        }
        .task(id: stop.id) {
            model.focusedStop = stop
            RecentsStore.shared.add(stop)
            routes = await TransitService.shared.routes(for: stop)
            await load()
            // Keep the board fresh while it's open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { break }
                if scenePhase == .active && at == nil { await load() }
            }
        }
        .onDisappear { if model.focusedStop?.id == stop.id { model.focusedStop = nil } }
    }

    // MARK: Plan ahead

    private var supportsTimetable: Bool { agency?.source == .gtfsRealtime || agency?.source == .metrolinx }

    @ViewBuilder private var timeChips: some View {
        HStack(spacing: 8) {
            FilterChip(title: "Now", symbol: "dot.radiowaves.up.forward", selected: at == nil) {
                at = nil; Task { await load() }
            }
            FilterChip(title: at.map { "\(TimeText.longDay($0)), \(TimeText.clock.string(from: $0))" } ?? "Plan ahead…",
                       symbol: "calendar", selected: at != nil) { pickingTime = true }
            Spacer()
        }
        .sheet(isPresented: $pickingTime) {
            LeaveAtPicker(date: at ?? Calendar.current.date(bySettingHour: 8, minute: 0, second: 0,
                                                            of: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)!,
                          allowsArriveBy: false) { d, _ in
                at = d; pickingTime = false
                Task { await load() }
            }
            .presentationDetents([.height(640)])
        }
        if at != nil && !supportsTimetable {
            Label(agency?.source == .metrolinx ? "For future GO times, use Trip from / Trip to — it searches GO's full schedule."
                                               : "Future times for this stop are available through trip planning.",
                  systemImage: "info.circle")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Alerts (compact, expandable)

    private var alertsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { showAlerts.toggle() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: alerts.contains { $0.severity == .severe } ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(alerts.contains { $0.severity == .severe } ? Theme.late : .orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(alerts.count == 1 ? "1 alert for this stop" : "\(alerts.count) alerts for this stop")
                            .font(.subheadline.weight(.semibold))
                        if !showAlerts {
                            Text(alerts[0].title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showAlerts ? 180 : 0))
                }
                .padding(12)
                .card(radius: 16)
            }
            .buttonStyle(PressableStyle())
            .tint(.primary)
            if showAlerts {
                ForEach(alerts) { AlertCard(alert: $0) }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stop.name).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                AgencyTag(agencyID: stop.agencyID)
                Text("Stop #\(stop.displayCode)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                if let distance {
                    Text("·").foregroundStyle(.secondary)
                    Label("\(distance.walkingMinutes) min", systemImage: "figure.walk").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            let shown = routes.isEmpty ? uniqueRoutes(departures) : routes
            if !shown.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) { ForEach(shown) { RouteBadge(route: $0, size: .regular) } }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.top, 4)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            actionButton(favorites.contains(stop) ? "Saved" : "Save", favorites.contains(stop) ? "star.fill" : "star") { favorites.toggle(stop) }
            actionButton("Trip from", "arrow.up.right.circle") { router.open(.planner(from: .stop(stop), to: nil)) }
            actionButton("Trip to", "arrow.down.right.circle") { router.open(.planner(from: .currentLocation, to: .stop(stop))) }
            actionButton("Walk", "figure.walk") {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: stop.coordinate))
                item.name = stop.name
                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
            }

        }
        .tint(.primary)
    }

    private func actionButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(title, symbol) }.buttonStyle(PressableStyle())
    }

    private func actionLabel(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
            Text(title).font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .card(radius: 14)
    }

    private var shareText: String {
        var s = "\(stop.name) (\(agency?.shortName ?? "") stop #\(stop.displayCode))"
        if let next = departures.first {
            s += " — next: \(next.route.badgeText) to \(next.headsign) \(TimeText.short(next.time))"
        }
        return s + "\nhttps://maps.apple.com/?ll=\(stop.latitude),\(stop.longitude)&q=\(stop.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
    }

    // MARK: Departures

    @ViewBuilder private func departuresSection(for layout: Layout) -> some View {
        if loading && departures.isEmpty {
            LoadingCards()
        } else if let error, departures.isEmpty {
            EmptyState(symbol: "wifi.exclamationmark", title: "Couldn't load departures", message: error,
                       actionTitle: "Try again") { Task { await load() } }
        } else if departures.isEmpty {
            EmptyState(symbol: "clock.badge.questionmark", title: "No departures soon", message: emptyMessage)
        } else if layout == .byLine {
            VStack(spacing: 10) {
                ForEach(groupedLines, id: \.0) { _, list in
                    LineBoardCard(departures: list, onRemind: { reminderTarget = $0 }, hasReminder: reminders.has)
                }
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(departures.prefix(40).enumerated()), id: \.element.id) { i, d in
                    DepartureRow(departure: d, hasReminder: reminders.has(d)) { reminderTarget = d }
                    if i < min(departures.count, 40) - 1 { Divider().padding(.leading, 64) }
                }
            }
            .card(radius: 18)
        }
    }

    private var emptyMessage: String {
        if routes.contains(where: { $0.mode == .subway }) && stop.agencyID == "ttc" {
            return "TTC subway trains usually run every 2–6 minutes. Live times will appear here when the TTC publishes them for this platform."
        }
        switch agency?.source {
        case .gtfsRealtime?, .ttc?: return "Live predictions appear about an hour before a trip starts. Service may have ended for the day."
        default: return "There's no scheduled service from this stop in the next few hours."
        }
    }

    private var groupedLines: [(String, [Departure])] {
        var order: [String] = []
        var map: [String: [Departure]] = [:]
        for d in departures {
            if map[d.lineKey] == nil { order.append(d.lineKey) }
            map[d.lineKey, default: []].append(d)
        }
        return order.map { ($0, map[$0]!) }
    }

    private func uniqueRoutes(_ deps: [Departure]) -> [TransitRoute] {
        var seen = Set<String>()
        return deps.map(\.route).filter { seen.insert($0.id).inserted }.sorted(by: TransitRoute.naturalOrder)
    }

    @ViewBuilder private var footer: some View {
        if let agency {
            VStack(alignment: .leading, spacing: 4) {
                if let updated = lastLoaded {
                    Text("Updated \(updated, format: .dateTime.hour().minute().second())")
                }
                Text(sourceNote(agency))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 6)
        }
    }

    @State private var lastLoaded: Date?

    private func sourceNote(_ a: Agency) -> String {
        switch a.source {
        case .winnipeg: return "Data: Winnipeg Transit Open Data. Live times shown with the signal icon."
        case .ttc: return "Data: TTC GTFS-Realtime and Umo. Times update every 20 seconds."
        case .metrolinx: return "Data: Metrolinx Open Data API (GO Transit). Platforms are confirmed shortly before departure."
        case .gtfsRealtime: return a.id == "ttc" ? "Data: TTC GTFS-Realtime (bus, streetcar & subway). Times update every 20 seconds." : "Data: \(a.name) GTFS-Realtime."
        }
    }

    // MARK: Actions

    private func load() async {
        do {
            let d = try await TransitService.shared.departures(for: stop, at: at)
            withAnimation(.snappy) { departures = d }
            error = nil
            lastLoaded = Date()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
        if let agency {
            let all = await TransitService.shared.alerts(for: [agency])
            let routeIDs = Set((routes.isEmpty ? uniqueRoutes(departures) : routes).map(\.routeID))
            alerts = all.filter { $0.affects(stop: stop) || !$0.routeIDs.filter(routeIDs.contains).isEmpty }
        }
    }

    private var reminderTitle: String {
        guard let d = reminderTarget else { return "" }
        return "\(d.route.badgeText) to \(d.headsign) · \(TimeText.short(d.time, clockTimes: true))"
    }

    private func remind(_ d: Departure, lead: Int) {
        Task {
            let ok = await reminders.schedule(d, at: stop, leadMinutes: lead)
            show(ok ? "We'll remind you \(lead == 0 ? "when it leaves" : "\(lead) min before")" : "Turn on notifications in Settings to get reminders")
        }
    }

    private func show(_ message: String) {
        withAnimation(.snappy) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.snappy) { toast = nil }
        }
    }
}

// MARK: - Line board card (By line)

struct LineBoardCard: View {
    let departures: [Departure]
    let onRemind: (Departure) -> Void
    let hasReminder: (Departure) -> Bool
    @AppStorage(Prefs.clockTimes) private var clockTimes = false

    var body: some View {
        let first = departures[0]
        let route = first.route
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                RouteBadge(route: route, size: .large, inverted: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(first.headsign).font(.headline.weight(.bold)).lineLimit(2)
                    if !route.longName.isEmpty && route.longName.lowercased() != first.headsign.lowercased() {
                        Text(route.longName).font(.caption.weight(.medium)).opacity(0.8).lineLimit(1)
                    }
                }
                Spacer()
                Button { onRemind(first) } label: {
                    Image(systemName: hasReminder(first) ? "bell.fill" : "bell")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(route.textColor.opacity(0.18), in: Circle())
                }
                .accessibilityLabel("Remind me")
            }
            HStack(spacing: 8) {
                ForEach(Array(departures.prefix(4).enumerated()), id: \.element.id) { i, d in
                    TimeChip(departure: d, emphasized: i == 0, tint: route.textColor)
                        .onTapGesture { onRemind(d) }
                }
                Spacer(minLength: 0)
            }
            if let p = first.platform ?? departures.first(where: { $0.platform != nil })?.platform {
                Label("Platform \(p)", systemImage: "signpost.right.fill").font(.caption.weight(.bold)).opacity(0.9)
            }
        }
        .foregroundStyle(route.textColor)
        .padding(16)
        .background(route.color.gradient, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

struct TimeChip: View {
    let departure: Departure
    let emphasized: Bool
    let tint: Color
    @AppStorage(Prefs.clockTimes) private var clockTimes = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let c = TimeText.countdown(departure.time, clockTimes: clockTimes, now: ctx.date)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(c.value).font(.system(size: emphasized ? 22 : 16, weight: .heavy, design: .rounded)).monospacedDigit()
                if !c.unit.isEmpty { Text(c.unit).font(.system(size: 11, weight: .bold, design: .rounded)) }
                if departure.isRealtime { LiveIndicator(color: tint).padding(.leading, 1) }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(tint.opacity(emphasized ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

// MARK: - Departure row (By time)

struct DepartureRow: View {
    let departure: Departure
    let hasReminder: Bool
    let onRemind: () -> Void
    @AppStorage(Prefs.clockTimes) private var clockTimes = false

    var body: some View {
        HStack(spacing: 12) {
            RouteBadge(route: departure.route, size: .regular)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(departure.headsign).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(TimeText.clock.string(from: departure.time)).monospacedDigit()
                    if let p = departure.platform { Text("· Platform \(p)").fontWeight(.semibold) }
                    if let s = TimeText.status(departure) { Text("· \(s.0)").foregroundStyle(s.1) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Countdown(departure: departure, large: false)
            Button(action: onRemind) {
                Image(systemName: hasReminder ? "bell.fill" : "bell")
                    .foregroundStyle(hasReminder ? Theme.signal : .secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remind me")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .opacity(departure.isCancelled ? 0.45 : 1)
    }
}
