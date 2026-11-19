import SwiftUI
import MapKit

// MARK: - Planner model

@MainActor @Observable
final class PlannerModel {
    var from: Place
    var to: Place?
    var leaveAt: Date? = nil          // nil = leave now
    var arriveBy: Date? = nil         // set instead of leaveAt for "arrive by" searches
    var isNow: Bool { leaveAt == nil && arriveBy == nil }
    private(set) var result = PlanResult()
    private(set) var loading = false
    private(set) var loadingMore = false
    private(set) var updatedAt: Date?
    private var task: Task<Void, Never>?

    init(from: Place = .currentLocation, to: Place? = nil) {
        self.from = from
        self.to = to
    }

    /// Fetches the next batch of options after the last one shown.
    func loadMore() {
        guard let to, !loadingMore else { return }
        if let arriveBy, let earliest = result.itineraries.filter({ !$0.isWalkOnly }).map(\.arriveAt).min() {
            // Arrive-by lists go backwards: fetch options arriving before the earliest one shown.
            loadingMore = true
            let from = from, here = LocationService.shared.location?.coordinate
            let target = min(arriveBy, earliest.addingTimeInterval(-60))
            Task {
                let more = await TripPlanner.shared.plan(from: from, to: to, current: here, arriveBy: target)
                let known = Set(result.itineraries.map(\.id))
                withAnimation(.snappy) { result.itineraries += more.itineraries.filter { !$0.isWalkOnly && !known.contains($0.id) } }
                loadingMore = false
            }
            return
        }
        guard let last = result.itineraries.last(where: { !$0.isWalkOnly }) else { return }
        loadingMore = true
        let from = from, after = last.leaveAt.addingTimeInterval(60)
        let here = LocationService.shared.location?.coordinate
        Task {
            let more = await TripPlanner.shared.plan(from: from, to: to, current: here, departAfter: after)
            let known = Set(result.itineraries.map(\.id))
            withAnimation(.snappy) {
                result.itineraries += more.itineraries.filter { !$0.isWalkOnly && !known.contains($0.id) && $0.leaveAt > last.leaveAt }
            }
            loadingMore = false
        }
    }

    func swap() {
        guard let t = to else { return }
        to = from
        from = t
        run()
    }

    func run() {
        guard let to else { return }
        task?.cancel()
        loading = true
        let from = from, at = leaveAt ?? .now, arriveBy = arriveBy
        let here = LocationService.shared.location?.coordinate
        task = Task {
            let r: PlanResult
            if let arriveBy {
                r = await TripPlanner.shared.plan(from: from, to: to, current: here, arriveBy: arriveBy)
            } else {
                r = await TripPlanner.shared.plan(from: from, to: to, current: here, departAfter: at)
            }
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { result = r }
            loading = false
            updatedAt = .now
            // Always show a few next departures, not just one (e.g. late at night).
            if arriveBy == nil, (1..<3).contains(r.itineraries.filter({ !$0.isWalkOnly }).count) { loadMore() }
        }
    }
}

// MARK: - Planner screen

struct TripPlannerView: View {
    @State var model: PlannerModel
    let router: Router
    @State private var picking: PickTarget?
    @State private var trips = TripsStore.shared
    @State private var showTimePicker = false
    @Environment(\.scenePhase) private var scenePhase

    enum PickTarget: Identifiable { case from, to; var id: Int { self == .from ? 0 : 1 } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                endpoints
                timeRow
                if !Connectivity.shared.isOnline { OfflineBanner() }
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable { model.run() }
        .navigationTitle("Plan a trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let to = model.to {
                ToolbarItem(placement: .topBarTrailing) {
                    let saved = trips.isSaved(from: model.from, to: to)
                    Button { trips.toggle(from: model.from, to: to) } label: {
                        Image(systemName: saved ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(saved ? Theme.signal : .primary)
                    }
                    .sensoryFeedback(.success, trigger: saved)
                    .accessibilityLabel(saved ? "Remove saved trip" : "Save trip")
                }
            }
        }
        .sheet(item: $picking) { target in
            PlacePickerView(title: target == .from ? "From" : "To", allowCurrent: true) { place in
                if target == .from { model.from = place } else { model.to = place }
                picking = nil
                model.run()
            }
        }
        .onAppear {
            router.detent = .large
            if model.to == nil { picking = .to } else if model.result.itineraries.isEmpty { model.run() }
        }
        .task {
            // Keep live times fresh while the planner is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                if scenePhase == .active && model.isNow && model.to != nil { model.run() }
            }
        }
    }

    // MARK: From / To

    private var endpoints: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                endpointRow(model.from, placeholder: "From", dot: .blue) { picking = .from }
                Divider().padding(.leading, 38)
                endpointRow(model.to, placeholder: "Where to?", dot: Theme.signal) { picking = .to }
            }
            .card(radius: 18)
            Button { withAnimation(.snappy) { model.swap() } } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(Color(uiColor: .tertiarySystemFill), in: Circle())
            }
            .buttonStyle(PressableStyle())
            .tint(.primary)
            .disabled(model.to == nil)
            .accessibilityLabel("Reverse trip")
        }
        .padding(.top, 6)
    }

    private func endpointRow(_ place: Place?, placeholder: String, dot: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle().fill(dot).frame(width: 10, height: 10).padding(.leading, 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(place?.title ?? placeholder)
                        .font(.body.weight(place == nil ? .regular : .semibold))
                        .foregroundStyle(place == nil ? .secondary : .primary)
                        .lineLimit(1)
                    if let sub = place?.subtitle { Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var timeRow: some View {
        HStack(spacing: 8) {
            FilterChip(title: "Leave now", symbol: "clock", selected: model.isNow) {
                model.leaveAt = nil; model.arriveBy = nil; model.run()
            }
            FilterChip(title: model.arriveBy.map { "Arrive by \(TimeText.dayTime($0))" } ?? model.leaveAt.map { TimeText.dayTime($0) } ?? "Plan ahead…",
                       symbol: model.arriveBy == nil ? "calendar" : "flag.checkered", selected: !model.isNow) { showTimePicker = true }
            Spacer()
            if model.loading { ProgressView().controlSize(.small) }
        }
        .sheet(isPresented: $showTimePicker) {
            LeaveAtPicker(date: model.arriveBy ?? model.leaveAt ?? .now.addingTimeInterval(30 * 60),
                          arriveBy: model.arriveBy != nil) { d, arrive in
                if arrive { model.arriveBy = d; model.leaveAt = nil } else { model.leaveAt = d; model.arriveBy = nil }
                showTimePicker = false; model.run()
            }
            .presentationDetents([.height(690)])
        }
    }

    // MARK: Results

    @ViewBuilder private var content: some View {
        if model.to == nil {
            EmptyState(symbol: "point.topleft.down.to.point.bottomright.curvepath.fill", title: "Where are you headed?",
                       message: "Pick a station, stop or address. Save a trip to see its next departure on the home screen and in widgets.",
                       actionTitle: "Choose destination") { picking = .to }
        } else if model.loading && model.result.itineraries.isEmpty {
            LoadingCards()
        } else if model.result.itineraries.isEmpty {
            VStack(spacing: 12) {
                EmptyState(symbol: "tram.circle", title: "No trips found", message: model.result.notes.first ?? "Try a different time or a nearby stop.")
                appleMapsButton
            }
        } else {
            if let by = model.arriveBy {
                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Arrive by \(TimeText.clock.string(from: by))").font(.headline)
                        Text("\(TimeText.longDay(by)) · latest departures first").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if Calendar.current.isDateInToday(by), let best = model.result.itineraries.first(where: { !$0.isWalkOnly }) {
                    NextUpBanner(itinerary: best)
                }
            } else if let at = model.leaveAt {
                HStack(spacing: 8) {
                    Image(systemName: "calendar").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(TimeText.longDay(at)).font(.headline)
                        Text("Leaving after \(TimeText.clock.string(from: at)) · scheduled times").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else if let next = model.result.itineraries.first(where: { !$0.isWalkOnly }) {
                if let first = model.result.nextServiceAt {
                    HStack(spacing: 10) {
                        Image(systemName: "moon.zzz.fill").font(.title3).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("No service right now").font(.headline)
                            Text("Next trips from \(TimeText.relativeDayTime(first))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14).card(radius: 18)
                }
                NextUpBanner(itinerary: next)
            }
            ForEach(model.result.itineraries) { it in
                NavigationLink(value: SheetRoute.itinerary(it)) {
                    ItineraryCard(itinerary: it, referenceDay: model.arriveBy ?? model.leaveAt ?? .now)
                }
                .buttonStyle(PressableStyle())
                .tint(.primary)
            }
            Button { model.loadMore() } label: {
                HStack(spacing: 6) {
                    if model.loadingMore { ProgressView().controlSize(.small) } else { Image(systemName: model.arriveBy == nil ? "chevron.down" : "chevron.up") }
                    Text(model.arriveBy == nil ? "Later trips" : "Earlier trips")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .tint(Theme.accent)
            .disabled(model.loadingMore)
            if let to = model.to, !trips.isSaved(from: model.from, to: to) {
                Button { trips.toggle(from: model.from, to: to) } label: {
                    Label("Save this trip for one-tap times and widgets", systemImage: "bookmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .card(radius: 16)
                }
                .buttonStyle(PressableStyle())
                .tint(.primary)
            } else if let to = model.to, let saved = trips.trips.first(where: { $0.from == model.from && $0.to == to }),
                      !trips.isSaved(from: to, to: model.from) {
                Button { trips.saveReturn(of: saved) } label: {
                    Label("Also save the trip back (\(to.shortTitle) → \(model.from.shortTitle))", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .card(radius: 16)
                }
                .buttonStyle(PressableStyle())
                .tint(.primary)
            }
            appleMapsButton
            if let note = model.result.notes.first {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
            Text(model.isNow
                 ? "Live predictions where available; GO adds live delays and platforms to its schedule."
                 : "Scheduled times from each agency's published timetable. Check live times closer to departure.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var appleMapsButton: some View {
        Button {
            guard let to = model.to, let dest = to.coordinate(current: LocationService.shared.location?.coordinate) else { return }
            let destItem = MKMapItem(placemark: MKPlacemark(coordinate: dest)); destItem.name = to.title
            var items = [destItem]
            if case .currentLocation = model.from {} else if let o = model.from.coordinate(current: nil) {
                let src = MKMapItem(placemark: MKPlacemark(coordinate: o)); src.name = model.from.title
                items.insert(src, at: 0)
            }
            MKMapItem.openMaps(with: items, launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit])
        } label: {
            Label("Compare in Apple Maps", systemImage: "map")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .tint(.secondary)
    }
}

/// Pick a day (Today, Tomorrow, Mon …) and a time — e.g. "Monday, 8:00 AM".
struct LeaveAtPicker: View {
    @State var date: Date
    @State var arriveBy = false
    var allowsArriveBy = true
    let onDone: (Date, Bool) -> Void

    init(date: Date, arriveBy: Bool = false, allowsArriveBy: Bool = true, onDone: @escaping (Date, Bool) -> Void) {
        _date = State(initialValue: date)
        _arriveBy = State(initialValue: arriveBy)
        self.allowsArriveBy = allowsArriveBy
        self.onDone = onDone
    }

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<8).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }
    private let quickTimes: [(String, Int, Int)] = [("6 AM", 6, 0), ("7 AM", 7, 0), ("8 AM", 8, 0), ("9 AM", 9, 0),
                                                     ("12 PM", 12, 0), ("5 PM", 17, 0), ("6 PM", 18, 0), ("10 PM", 22, 0)]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if allowsArriveBy {
                    Picker("Mode", selection: $arriveBy) {
                        Text("Leave at").tag(false)
                        Text("Arrive by").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                Text("Day").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(days, id: \.self) { d in
                            let selected = Calendar.current.isDate(d, inSameDayAs: date)
                            Button { setDay(d) } label: {
                                VStack(spacing: 2) {
                                    Text(dayTitle(d)).font(.subheadline.weight(.bold))
                                    Text(d, format: .dateTime.month(.abbreviated).day()).font(.caption2)
                                }
                                .frame(width: 74, height: 54)
                                .foregroundStyle(selected ? .black : .primary)
                                .background(selected ? AnyShapeStyle(Theme.signal) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .scrollIndicators(.hidden)

                Text("Time").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(quickTimes, id: \.0) { t in
                            FilterChip(title: t.0, selected: isTime(t.1, t.2)) { setTime(t.1, t.2) }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                // Full-height wheel: clipping it would leave its touch area overlapping the chips above.
                DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                Button("\(arriveBy ? "Arrive by" : "Leave") \(TimeText.longDay(date)), \(TimeText.clock.string(from: date))") {
                    onDone(arriveBy ? date : max(date, .now), arriveBy)
                }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .navigationTitle("Plan ahead")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func dayTitle(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        return d.formatted(.dateTime.weekday(.abbreviated))
    }

    private func setDay(_ d: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        date = Calendar.current.date(bySettingHour: c.hour ?? 8, minute: c.minute ?? 0, second: 0, of: d) ?? d
    }

    private func setTime(_ h: Int, _ m: Int) {
        date = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: date) ?? date
    }

    private func isTime(_ h: Int, _ m: Int) -> Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return c.hour == h && c.minute == m
    }
}

// MARK: - "Next up" banner (Trainline-style "Leaves in …")

struct NextUpBanner: View {
    let itinerary: Itinerary

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let mins = Int(itinerary.leaveAt.timeIntervalSince(ctx.date) / 60)
            HStack(spacing: 12) {
                Image(systemName: mins <= 2 ? "figure.run" : "figure.walk")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 46)
                    .background(Theme.signal, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(mins <= 0 ? "Leave now" : mins < 60 ? "Leave in \(mins) min" : "Leave \(TimeText.relativeDayTime(itinerary.leaveAt))")
                        .font(.title3.weight(.heavy))
                    if let r = itinerary.firstRide {
                        Text("\(r.route.badgeText) from \(r.from.name)\(r.platform.map { " · Platform \($0)" } ?? "")")
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Arrive").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(TimeText.clock.string(from: itinerary.arriveAt)).font(.headline.monospacedDigit())
                }
            }
            .padding(14)
            .card(radius: 20)
        }
    }
}

// MARK: - Itinerary card

struct ItineraryCard: View {
    let itinerary: Itinerary
    /// The day being planned; a day label appears only when an option falls on a different day (e.g. after midnight).
    var referenceDay: Date = .now

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !Calendar.current.isDate(itinerary.leaveAt, inSameDayAs: referenceDay) {
                Text(TimeText.longDay(itinerary.leaveAt)).font(.caption.weight(.bold)).foregroundStyle(Theme.accent).textCase(.uppercase)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(TimeText.clock.string(from: itinerary.leaveAt)).font(.title3.weight(.bold)).monospacedDigit()
                Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Text(TimeText.clock.string(from: itinerary.arriveAt)).font(.title3.weight(.bold)).monospacedDigit()
                Spacer()
                Text(TimeText.duration(itinerary.duration)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            LegStrip(itinerary: itinerary)
            HStack(spacing: 6) {
                if let r = itinerary.firstRide {
                    if r.isRealtime { LiveIndicator() }
                    Text(departureLine(r)).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                    if let p = r.platform { Text("· Platform \(p)").font(.caption.weight(.bold)) }
                    if let s = status(r) { Text("· \(s.0)").font(.caption.weight(.semibold)).foregroundStyle(s.1) }
                } else {
                    Text("Walk all the way · \(itinerary.walkMinutes) min").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(itinerary.transfers == 0 ? (itinerary.isWalkOnly ? "" : "Direct") : "\(itinerary.transfers) change\(itinerary.transfers > 1 ? "s" : "")")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .card(radius: 20)
    }

    private func departureLine(_ r: RideLeg) -> String {
        let when = r.depart.timeIntervalSinceNow < 3600 ? TimeText.short(r.depart) : TimeText.clock.string(from: r.depart)
        return "\(when) from \(r.from.name)"
    }

    private func status(_ r: RideLeg) -> (String, Color)? {
        guard let d = r.delaySeconds else { return nil }
        let m = Int((Double(d) / 60).rounded())
        if m >= 2 { return ("\(m) min late", Theme.late) }
        return r.isRealtime ? ("On time", Theme.live) : nil
    }
}

/// Walk 5 › [MI] › Walk 3 — the at-a-glance shape of a trip.
struct LegStrip: View {
    let itinerary: Itinerary

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(Array(itinerary.legs.enumerated()), id: \.offset) { i, leg in
                    if i > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary) }
                    switch leg {
                    case .walk(let w):
                        HStack(spacing: 2) {
                            Image(systemName: "figure.walk").font(.caption.weight(.bold))
                            Text("\(w.minutes)").font(.caption.weight(.bold)).monospacedDigit()
                        }
                        .foregroundStyle(.secondary)
                    case .ride(let r):
                        RouteBadge(route: r.route, size: .regular)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .allowsHitTesting(false)
    }
}

// MARK: - Itinerary detail (timeline)

struct ItineraryDetailView: View {
    let itinerary: Itinerary
    let router: Router
    @State private var guiding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(TimeText.clock.string(from: itinerary.leaveAt)) – \(TimeText.clock.string(from: itinerary.arriveAt))")
                        .font(.title2.weight(.bold)).monospacedDigit()
                    Text("\(TimeText.duration(itinerary.duration)) · \(itinerary.transfers == 0 ? "Direct" : "\(itinerary.transfers) change\(itinerary.transfers > 1 ? "s" : "")") · \(itinerary.walkMinutes) min walking")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.bottom, 18)

                ForEach(Array(itinerary.legs.enumerated()), id: \.offset) { _, leg in
                    switch leg {
                    case .walk(let w): WalkLegRow(leg: w)
                    case .ride(let r): RideLegRow(leg: r) { router.open(.stop(r.from)) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .navigationTitle("Trip details")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !itinerary.isWalkOnly {
                Button { guiding = true } label: { Label("Start trip", systemImage: "location.north.line.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.bar)
            }
        }
        .fullScreenCover(isPresented: $guiding) { TripGuideView(itinerary: itinerary) }
        .onAppear { if let r = itinerary.firstRide { router.focus(r.from) } }
    }
}

private struct WalkLegRow: View {
    let leg: WalkLeg
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { _ in Circle().fill(.secondary.opacity(0.5)).frame(width: 4, height: 4) }
            }
            .frame(width: 28)
            .padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 2) {
                Label("Walk \(leg.minutes) min", systemImage: "figure.walk").font(.subheadline.weight(.semibold))
                Text("\(leg.distance.shortDistance) to \(leg.toName)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            Spacer()
        }
    }
}

private struct RideLegRow: View {
    let leg: RideLeg
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle().strokeBorder(leg.route.color, lineWidth: 4).frame(width: 18, height: 18)
                Rectangle().fill(leg.route.color).frame(width: 6).frame(minHeight: 70)
                Circle().strokeBorder(leg.route.color, lineWidth: 4).frame(width: 18, height: 18)
            }
            .frame(width: 28)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Button(action: onStop) {
                        Text(leg.from.name).font(.headline).multilineTextAlignment(.leading)
                    }
                    .tint(.primary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(TimeText.clock.string(from: leg.depart)).font(.headline.monospacedDigit())
                        if let s = leg.scheduledDepart, abs(s.timeIntervalSince(leg.depart)) >= 60 {
                            Text(TimeText.clock.string(from: s)).font(.caption.monospacedDigit()).strikethrough().foregroundStyle(.secondary)
                        }
                    }
                }
                HStack(spacing: 8) {
                    RouteBadge(route: leg.route, size: .regular)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("to \(leg.headsign)").font(.subheadline.weight(.semibold)).lineLimit(1)
                        HStack(spacing: 4) {
                            if leg.isRealtime { LiveIndicator() }
                            if let n = leg.stopCount { Text("\(n) stop\(n == 1 ? "" : "s")") }
                            if let p = leg.platform { Text("· Platform \(p)").fontWeight(.bold) }
                            Text("· \(TimeText.duration(leg.arrive.timeIntervalSince(leg.depart)))")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(leg.to.name).font(.headline)
                    Spacer()
                    Text(TimeText.clock.string(from: leg.arrive)).font(.headline.monospacedDigit())
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Place picker

struct PlacePickerView: View {
    let title: String
    var allowCurrent = true
    let onPick: (Place) -> Void

    @State private var query = ""
    @State private var stops: [TransitStop] = []
    @State private var completer = PlaceCompleter()
    @State private var favorites = FavoritesStore.shared
    @State private var recents = RecentsStore.shared
    @State private var searching = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if query.count < 2 {
                    if allowCurrent {
                        row(.currentLocation)
                    }
                    if !favorites.stops.isEmpty {
                        Section("Saved stops") { ForEach(favorites.stops) { row(.stop($0)) } }
                    }
                    if !recents.stops.isEmpty {
                        Section("Recent") { ForEach(recents.stops.prefix(5)) { row(.stop($0)) } }
                    }
                } else {
                    if !stops.isEmpty {
                        Section("Stations & stops") { ForEach(stops.prefix(12)) { row(.stop($0)) } }
                    }
                    if !completer.results.isEmpty {
                        Section("Places") {
                            ForEach(completer.results, id: \.self) { c in
                                Button {
                                    Task { if let p = await completer.resolve(c) { onPick(p) } }
                                } label: {
                                    Label {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(c.title).foregroundStyle(.primary)
                                            if !c.subtitle.isEmpty { Text(c.subtitle).font(.caption).foregroundStyle(.secondary) }
                                        }
                                    } icon: { Image(systemName: "mappin.circle.fill").foregroundStyle(.red) }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .always), prompt: "Station, stop or address")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { searching = true }
            .task(id: query) {
                completer.update(query)
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let c = LocationService.shared.location?.coordinate ?? Catalog.city("toronto")!.coordinate
                let r = await TransitService.shared.search(query, near: c, cityIDs: [])
                guard !Task.isCancelled else { return }
                // Stations first: trains and subways rank above bus stops with similar names.
                stops = r.sorted { ($0.mode == .rail || $0.mode == .subway ? 0 : 1) < ($1.mode == .rail || $1.mode == .subway ? 0 : 1) }
            }
        }
    }

    private func row(_ place: Place) -> some View {
        Button { onPick(place) } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.title).foregroundStyle(.primary)
                    if let s = place.subtitle { Text(s).font(.caption).foregroundStyle(.secondary) }
                }
            } icon: {
                Image(systemName: place.symbol).foregroundStyle(place == .currentLocation ? .blue : Theme.accent)
            }
        }
        .tint(.primary)
    }
}

/// Address / point-of-interest autocomplete via MapKit.
@MainActor @Observable
final class PlaceCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        if let here = LocationService.shared.location?.coordinate {
            completer.region = MKCoordinateRegion(center: here, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
        }
    }

    func update(_ q: String) {
        if q.count < 2 { results = []; return }
        completer.queryFragment = q
    }

    nonisolated func completerDidUpdateResults(_ c: MKLocalSearchCompleter) {
        let r = Array(c.results.prefix(8))
        Task { @MainActor in self.results = r }
    }
    nonisolated func completer(_ c: MKLocalSearchCompleter, didFailWithError error: Error) {}

    func resolve(_ c: MKLocalSearchCompletion) async -> Place? {
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: c)).start().mapItems.first else { return nil }
        let coord = item.placemark.coordinate
        return .point(name: c.title, subtitle: c.subtitle.nilIfEmpty, latitude: coord.latitude, longitude: coord.longitude)
    }
}

// MARK: - Saved trip card (home sheet)

struct SavedTripCard: View {
    let trip: SavedTrip
    @State private var next: Itinerary?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(Theme.signal)
                Text(trip.title).font(.subheadline.weight(.bold)).lineLimit(1)
            }
            if let next, let r = next.firstRide {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    RouteBadge(route: r.route, size: .small)
                    TimelineView(.periodic(from: .now, by: 15)) { ctx in
                        let c = TimeText.countdown(r.depart, now: ctx.date)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(c.value).font(.system(size: 24, weight: .heavy, design: .rounded)).monospacedDigit()
                            Text(c.unit).font(.caption.weight(.bold))
                        }
                    }
                    if r.isRealtime { LiveIndicator() }
                }
                Text("\(r.platform.map { "Platform \($0) · " } ?? "")arrive \(TimeText.clock.string(from: next.arriveAt))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(loaded ? "No trips soon" : "Checking times…").font(.caption).foregroundStyle(.secondary)
                    .frame(height: 44, alignment: .leading)
            }
        }
        .padding(12)
        .frame(width: 210, alignment: .leading)
        .card(radius: 16)
        .task(id: trip.id) {
            while !Task.isCancelled {
                let r = await TripPlanner.shared.plan(from: trip.from, to: trip.to, current: LocationService.shared.location?.coordinate)
                next = r.itineraries.first { !$0.isWalkOnly }
                loaded = true
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}

// MARK: - Time helpers

extension TimeText {
    static func duration(_ t: TimeInterval) -> String {
        let m = max(1, Int((t / 60).rounded()))
        return m < 60 ? "\(m) min" : "\(m / 60) h \(String(format: "%02d", m % 60)) min"
    }

    /// "Today", "Tomorrow", or "Monday, Nov 23"
    static func longDay(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        return d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// "5:12 AM", "tomorrow at 5:12 AM" or "Monday at 5:12 AM".
    static func relativeDayTime(_ d: Date) -> String {
        let t = clock.string(from: d)
        if Calendar.current.isDateInToday(d) { return t }
        if Calendar.current.isDateInTomorrow(d) { return "tomorrow at \(t)" }
        return "\(d.formatted(.dateTime.weekday(.wide))) at \(t)"
    }

    static func dayTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(d) ? "h:mm a" : "EEE h:mm a"
        return f.string(from: d)
    }
}
