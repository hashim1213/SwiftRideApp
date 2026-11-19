import WidgetKit
import SwiftUI
import AppIntents
import CoreLocation

@main
struct SwiftRideWidgets: WidgetBundle {
    var body: some Widget {
        NextTripWidget()
        SavedStopWidget()
        TripLiveActivity()
    }
}

// MARK: - Configuration entities

struct TripEntity: AppEntity {
    let id: String
    let title: String
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Trip"
    static let defaultQuery = TripQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct TripQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TripEntity] {
        TripsStore.load().filter { identifiers.contains($0.id) }.map { TripEntity(id: $0.id, title: $0.title) }
    }
    func suggestedEntities() async throws -> [TripEntity] {
        TripsStore.load().map { TripEntity(id: $0.id, title: $0.title) }
    }
}

struct SelectTripIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose a trip"
    static let description = IntentDescription("Shows the next departures for one of your saved trips.")
    @Parameter(title: "Trip") var trip: TripEntity?
}

struct StopEntity: AppEntity {
    let id: String
    let title: String
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Stop"
    static let defaultQuery = StopQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct StopQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [StopEntity] {
        FavoritesStore.load().filter { identifiers.contains($0.id) }.map { StopEntity(id: $0.id, title: $0.name) }
    }
    func suggestedEntities() async throws -> [StopEntity] {
        FavoritesStore.load().map { StopEntity(id: $0.id, title: $0.name) }
    }
}

struct SelectStopIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose a stop"
    static let description = IntentDescription("Shows live departures from one of your saved stops.")
    @Parameter(title: "Stop") var stop: StopEntity?
}

// MARK: - Shared widget data

struct WidgetRide: Hashable {
    let badge: String
    let colorHex: String
    let textColorHex: String
    let symbol: String
    let headsign: String
    let depart: Date
    let arrive: Date?
    let platform: String?
    let live: Bool
    let delayMin: Int?

    var color: Color { Color(hex: colorHex) ?? .gray }
    var textColor: Color {
        if let c = Color(hex: textColorHex), textColorHex.uppercased() != colorHex.uppercased() { return c }
        return (Color.luminance(hex: colorHex) ?? 0) > 0.6 ? .black : .white
    }
}

private func lastLocation() -> CLLocationCoordinate2D? {
    let d = AppGroup.defaults
    guard d.object(forKey: AppGroup.lastLatKey) != nil else { return nil }
    return .init(latitude: d.double(forKey: AppGroup.lastLatKey), longitude: d.double(forKey: AppGroup.lastLonKey))
}

/// One entry per minute so countdowns stay right without waking the network.
private func minuteEntries<E>(from rides: [WidgetRide], make: (Date, [WidgetRide]) -> E) -> [E] {
    let now = Date()
    let start = Calendar.current.date(bySetting: .second, value: 0, of: now) ?? now
    return (0..<20).map { i in
        let t = i == 0 ? now : start.addingTimeInterval(TimeInterval(i * 60))
        return make(t, rides.filter { $0.depart >= t.addingTimeInterval(-30) })
    }
}

// MARK: - Next trip widget

struct TripEntry: TimelineEntry {
    let date: Date
    let tripID: String?
    let title: String
    let fromName: String
    let toName: String
    let rides: [WidgetRide]
    let message: String?
}

struct TripProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TripEntry {
        TripEntry(date: .now, tripID: nil, title: "Milton → Union", fromName: "Milton GO", toName: "Union Station",
                  rides: [WidgetRide(badge: "MI", colorHex: "F57F25", textColorHex: "FFFFFF", symbol: "train.side.front.car",
                                     headsign: "Union Station", depart: .now.addingTimeInterval(720), arrive: .now.addingTimeInterval(4500),
                                     platform: "2", live: true, delayMin: nil)], message: nil)
    }

    func snapshot(for configuration: SelectTripIntent, in context: Context) async -> TripEntry {
        context.isPreview ? placeholder(in: context) : await load(configuration).first ?? placeholder(in: context)
    }

    func timeline(for configuration: SelectTripIntent, in context: Context) async -> Timeline<TripEntry> {
        let entries = await load(configuration)
        return Timeline(entries: entries, policy: .after(.now.addingTimeInterval(10 * 60)))
    }

    private func load(_ config: SelectTripIntent) async -> [TripEntry] {
        let trips = TripsStore.load()
        guard let trip = trips.first(where: { $0.id == config.trip?.id }) ?? trips.first else {
            return [TripEntry(date: .now, tripID: nil, title: "No saved trips", fromName: "", toName: "", rides: [],
                              message: "Open SwiftRide, plan a trip and tap the bookmark.")]
        }
        let result = await TripPlanner.shared.plan(from: trip.from, to: trip.to, current: lastLocation())
        let rides: [WidgetRide] = result.itineraries.compactMap { it in
            guard let r = it.firstRide else { return nil }
            return WidgetRide(badge: r.route.badgeText, colorHex: r.route.colorHex, textColorHex: r.route.textColorHex,
                              symbol: r.route.mode.symbol, headsign: r.headsign, depart: r.depart, arrive: it.arriveAt,
                              platform: r.platform, live: r.isRealtime, delayMin: r.delaySeconds.map { Int((Double($0) / 60).rounded()) })
        }
        return minuteEntries(from: rides) { date, list in
            TripEntry(date: date, tripID: trip.id, title: trip.title, fromName: trip.from.shortTitle, toName: trip.to.shortTitle,
                      rides: list, message: list.isEmpty ? (result.notes.first ?? "No trips in the next few hours") : nil)
        }
    }
}

struct NextTripWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NextTrip", intent: SelectTripIntent.self, provider: TripProvider()) { entry in
            NextTripView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop() }
                .widgetURL(URL(string: entry.tripID.map { "swiftride://trip/\($0)" } ?? "swiftride://plan"))
        }
        .configurationDisplayName("Next trip")
        .description("When your next bus or train leaves for a saved trip.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct WidgetBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        scheme == .dark ? Color(white: 0.08) : Color(white: 0.98)
    }
}

struct NextTripView: View {
    let entry: TripEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "bookmark.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.signal)
            Text(entry.title).font(.system(size: 12, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let r = entry.rides.first {
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    WidgetBadge(ride: r)
                    if r.live { Image(systemName: "dot.radiowaves.up.forward").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.live) }
                }
                CountdownText(date: r.depart, now: entry.date, size: 34)
                Text(detail(r)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                if entry.rides.count > 1 {
                    Text("then \(entry.rides.dropFirst().prefix(2).map { minutes($0.depart) }.joined(separator: ", "))")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Spacer(minLength: 0)
                Text(entry.message ?? "").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                header
                Spacer()
                Text("Updated \(entry.date, style: .time)").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            if entry.rides.isEmpty {
                Spacer()
                Text(entry.message ?? "").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(entry.rides.prefix(3).enumerated()), id: \.offset) { i, r in
                    HStack(spacing: 8) {
                        WidgetBadge(ride: r)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(TimeText.clock.string(from: r.depart)) → \(r.arrive.map { TimeText.clock.string(from: $0) } ?? "")")
                                .font(.system(size: 14, weight: .bold)).monospacedDigit().lineLimit(1)
                            Text(rowDetail(r)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if r.live { Image(systemName: "dot.radiowaves.up.forward").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.live) }
                        CountdownText(date: r.depart, now: entry.date, size: i == 0 ? 22 : 17)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.title).font(.system(size: 13, weight: .bold)).lineLimit(1)
            if let r = entry.rides.first {
                Text("\(r.badge) in \(minutes(r.depart))\(r.platform.map { " · P\($0)" } ?? "")").font(.system(size: 15, weight: .heavy)).lineLimit(1)
                if let n = entry.rides.dropFirst().first { Text("then \(minutes(n.depart))").font(.system(size: 12)).lineLimit(1) }
            } else {
                Text("No trips soon").font(.system(size: 13))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        if let r = entry.rides.first {
            Label("\(r.badge) in \(minutes(r.depart)) to \(entry.toName)", systemImage: r.symbol)
        } else {
            Label(entry.title, systemImage: "tram.fill")
        }
    }

    private func minutes(_ d: Date) -> String {
        let m = Int(d.timeIntervalSince(entry.date) / 60)
        return m <= 0 ? "now" : m < 60 ? "\(m) min" : TimeText.clock.string(from: d)
    }

    /// Medium rows already show the times, so the second line is where it goes and how it's running.
    private func rowDetail(_ r: WidgetRide) -> String {
        var parts = ["to \(r.headsign)"]
        if let p = r.platform { parts.append("Platform \(p)") }
        if let d = r.delayMin, d >= 2 { parts.append("\(d) min late") }
        return parts.joined(separator: " · ")
    }

    private func detail(_ r: WidgetRide) -> String {
        var parts = [TimeText.clock.string(from: r.depart)]
        if let p = r.platform { parts.append("Platform \(p)") }
        if let d = r.delayMin, d >= 2 { parts.append("\(d) min late") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Saved stop widget

struct StopEntry: TimelineEntry {
    let date: Date
    let stopID: String?
    let agencyID: String?
    let title: String
    let rides: [WidgetRide]
    let message: String?
}

struct StopProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StopEntry {
        StopEntry(date: .now, stopID: nil, agencyID: nil, title: "King St West at Bay St", rides: [
            WidgetRide(badge: "504", colorHex: "ED1C24", textColorHex: "FFFFFF", symbol: "tram.fill", headsign: "Dundas West Station",
                       depart: .now.addingTimeInterval(180), arrive: nil, platform: nil, live: true, delayMin: nil),
            WidgetRide(badge: "503", colorHex: "ED1C24", textColorHex: "FFFFFF", symbol: "tram.fill", headsign: "Dufferin Gate",
                       depart: .now.addingTimeInterval(540), arrive: nil, platform: nil, live: true, delayMin: nil),
        ], message: nil)
    }

    func snapshot(for configuration: SelectStopIntent, in context: Context) async -> StopEntry {
        context.isPreview ? placeholder(in: context) : await load(configuration).first ?? placeholder(in: context)
    }

    func timeline(for configuration: SelectStopIntent, in context: Context) async -> Timeline<StopEntry> {
        Timeline(entries: await load(configuration), policy: .after(.now.addingTimeInterval(8 * 60)))
    }

    private func load(_ config: SelectStopIntent) async -> [StopEntry] {
        let stops = FavoritesStore.load()
        guard let stop = stops.first(where: { $0.id == config.stop?.id }) ?? stops.first else {
            return [StopEntry(date: .now, stopID: nil, agencyID: nil, title: "No saved stops", rides: [],
                              message: "Star a stop in SwiftRide to see it here.")]
        }
        let deps = (try? await TransitService.shared.departures(for: stop)) ?? []
        let rides = deps.prefix(12).map { d in
            WidgetRide(badge: d.route.badgeText, colorHex: d.route.colorHex, textColorHex: d.route.textColorHex, symbol: d.route.mode.symbol,
                       headsign: d.headsign, depart: d.time, arrive: nil, platform: d.platform, live: d.isRealtime,
                       delayMin: d.delaySeconds.map { Int((Double($0) / 60).rounded()) })
        }
        return minuteEntries(from: Array(rides)) { date, list in
            StopEntry(date: date, stopID: stop.stopID, agencyID: stop.agencyID, title: stop.name, rides: list,
                      message: list.isEmpty ? "No departures soon" : nil)
        }
    }
}

struct SavedStopWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SavedStop", intent: SelectStopIntent.self, provider: StopProvider()) { entry in
            SavedStopView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackdrop() }
                .widgetURL(URL(string: entry.stopID.map { "swiftride://stop/\(entry.agencyID ?? "")/\($0)" } ?? "swiftride://plan"))
        }
        .configurationDisplayName("Saved stop")
        .description("Live departures from a stop you've starred.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SavedStopView: View {
    let entry: StopEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.signal)
                Text(entry.title).font(.system(size: 12, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            if entry.rides.isEmpty {
                Spacer()
                Text(entry.message ?? "").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
            } else {
                // One row per line (route + direction), soonest first.
                let lines = uniqueLines(entry.rides).prefix(family == .systemMedium ? 3 : 2)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 7) {
                        WidgetBadge(ride: r)
                        if family == .systemMedium {
                            Text(r.headsign).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        }
                        Spacer(minLength: 2)
                        if r.live { Image(systemName: "dot.radiowaves.up.forward").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.live) }
                        CountdownText(date: r.depart, now: entry.date, size: family == .systemMedium ? 20 : 18)
                    }
                    if family == .systemSmall {
                        Text(r.headsign).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func uniqueLines(_ rides: [WidgetRide]) -> [WidgetRide] {
        var seen = Set<String>()
        return rides.filter { seen.insert("\($0.badge)|\($0.headsign)").inserted }
    }
}

// MARK: - Bits

struct WidgetBadge: View {
    let ride: WidgetRide
    var body: some View {
        Text(ride.badge)
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
            .frame(minWidth: 30, minHeight: 22)
            .foregroundStyle(ride.textColor)
            .background(ride.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct CountdownText: View {
    let date: Date
    let now: Date
    var size: CGFloat = 30

    var body: some View {
        let m = Int(date.timeIntervalSince(now) / 60)
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if m <= 0 {
                Text("Now").font(.system(size: size, weight: .heavy, design: .rounded))
            } else if m < 60 {
                Text("\(m)").font(.system(size: size, weight: .heavy, design: .rounded)).monospacedDigit()
                Text("min").font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            } else {
                Text(TimeText.clock.string(from: date)).font(.system(size: size * 0.7, weight: .heavy, design: .rounded)).monospacedDigit()
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// Widget-side twin of the app's TimeText (the app's version lives in its UI layer).
enum TimeText {
    static let clock: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()
}
