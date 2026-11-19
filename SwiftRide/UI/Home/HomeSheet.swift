import SwiftUI
import CoreLocation

struct HomeSheet: View {
    let model: NearbyModel
    let router: Router
    let location: LocationService
    @State private var favorites = FavoritesStore.shared
    @State private var trips = TripsStore.shared
    @State private var net = Connectivity.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                searchBar
                if !net.isOnline { OfflineBanner() }
                if !trips.trips.isEmpty { tripsStrip }
                if !favorites.stops.isEmpty { savedStrip }
                if !model.importantAlerts.isEmpty { alertBanner }
                if let c = model.center, PathNetwork.covers(c), PathNetwork.shared.isAvailable { pathCard }
                header
                filters
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .refreshable { model.reload() }
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(uiColor: .systemGroupedBackground).opacity(0.001))
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            Button { router.open(.planner(from: .currentLocation, to: nil)) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Where to?").font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Plan a trip")

            Button { router.open(.search) } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Search stops and stations")

            Button { router.open(.cities) } label: {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Choose a city")
        }
        .padding(.top, 18)
        .tint(.primary)
    }

    // MARK: Saved trips

    private var tripsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your trips").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(trips.trips) { trip in
                        Button { router.open(.planner(from: trip.from, to: trip.to)) } label: { SavedTripCard(trip: trip) }
                            .buttonStyle(PressableStyle())
                            .tint(.primary)
                            .contextMenu {
                                Button { router.open(.planner(from: trip.to, to: trip.from)) } label: {
                                    Label("Trip back", systemImage: "arrow.uturn.backward")
                                }
                                if !trips.isSaved(from: trip.to, to: trip.from) {
                                    Button { trips.saveReturn(of: trip) } label: { Label("Save trip back", systemImage: "bookmark") }
                                }
                                Button(role: .destructive) { trips.remove(trip) } label: { Label("Remove", systemImage: "trash") }
                            }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    // MARK: Saved

    private var savedStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Saved").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("See all") { router.open(.saved) }.font(.subheadline.weight(.semibold))
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(favorites.stops) { stop in
                        Button { router.open(.stop(stop)) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.signal)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(stop.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(Catalog.agency(stop.agencyID)?.shortName ?? "").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .frame(maxWidth: 220, alignment: .leading)
                            .card(radius: 14)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .tint(.primary)
    }

    // MARK: PATH

    private var pathCard: some View {
        Button { router.open(.path) } label: {
            HStack(spacing: 12) {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 40, height: 40).background(Theme.signal, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Underground PATH").font(.subheadline.weight(.semibold))
                    Text("Indoor walking directions — works with no GPS or signal").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(12).card(radius: 16)
        }
        .buttonStyle(PressableStyle())
        .tint(.primary)
    }

    // MARK: Alerts

    private var alertBanner: some View {
        Button { router.open(.alerts) } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.importantAlerts.count == 1 ? "1 service alert" : "\(model.importantAlerts.count) service alerts")
                        .font(.subheadline.weight(.semibold))
                    Text(model.importantAlerts.first?.title ?? "")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .card(radius: 16)
        }
        .buttonStyle(PressableStyle())
        .tint(.primary)
    }

    // MARK: Header + filters

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.bold))
                subtitle
            }
            Spacer()
            if model.phase == .loading && !model.lines.isEmpty { ProgressView().controlSize(.small) }
        }
    }

    private var title: String {
        switch model.origin {
        case .user: return "Nearby"
        case .map: return "This area"
        case .city: return model.areaName
        }
    }

    @ViewBuilder private var subtitle: some View {
        if let at = model.updatedAt {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                HStack(spacing: 4) {
                    if model.origin == .user { Text(model.areaName) ; Text("·") }
                    Text("Updated \(at, format: .relative(presentation: .named))")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text(model.areaName).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var filters: some View {
        let modes = model.modesInResults
        let agencies = model.agenciesInResults
        if modes.count > 1 || agencies.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", selected: model.filter == .all && model.agencyFilter == nil) {
                        model.filter = .all; model.agencyFilter = nil
                    }
                    if modes.count > 1 {
                        ForEach(ModeFilter.allCases.filter { modes.contains($0) }) { f in
                            FilterChip(title: f.title, symbol: f.symbol, selected: model.filter == f) {
                                model.filter = model.filter == f ? .all : f
                            }
                        }
                    }
                    if agencies.count > 1 {
                        ForEach(agencies) { a in
                            FilterChip(title: a.shortName, tint: Color(hex: a.brandHex) ?? Theme.signal, selected: model.agencyFilter == a.id) {
                                model.agencyFilter = model.agencyFilter == a.id ? nil : a.id
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle where !location.isAuthorized && model.center == nil:
            EmptyState(symbol: "location.circle", title: "Find stops around you",
                       message: "Allow location to see live departures nearby, or pick a city.",
                       actionTitle: "Allow location") { location.requestPermission() }
        case .idle, .loading where model.lines.isEmpty:
            LoadingCards()
        case .outOfArea:
            EmptyState(symbol: "map", title: "SwiftRide isn't here yet",
                       message: "We cover \(Catalog.cities.count) Canadian cities and regions. Pick one to explore.",
                       actionTitle: "Browse cities") { router.open(.cities) }
        case .empty:
            EmptyState(symbol: "mappin.slash", title: "No stops nearby",
                       message: "Try moving the map, or increase the search radius in Settings.")
        case .failed(let msg):
            EmptyState(symbol: "wifi.exclamationmark", title: "Couldn't load departures", message: msg,
                       actionTitle: "Try again") { model.reload(showSpinner: true) }
        default:
            lineList
        }
    }

    @ViewBuilder private var lineList: some View {
        let lines = model.visibleLines
        if lines.isEmpty {
            VStack(spacing: 10) {
                EmptyState(symbol: "moon.zzz", title: "No departures right now",
                           message: model.stops.isEmpty ? "No stops found." : "Service may have ended for the night. Tap a stop below for details.")
                ForEach(model.stops.prefix(6), id: \.stop.id) { item in
                    StopRow(stop: item.stop, distance: item.distance) { router.open(.stop(item.stop)) }
                }
            }
        } else {
            LazyVStack(spacing: 10) {
                ForEach(lines) { line in
                    Button {
                        router.open(.stop(line.stop))
                    } label: {
                        NearbyLineCard(line: line)
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu {
                        Button { FavoritesStore.shared.toggle(line.stop) } label: {
                            Label(FavoritesStore.shared.contains(line.stop) ? "Remove saved stop" : "Save stop", systemImage: "star")
                        }
                        Button { model.focusedStop = line.stop } label: { Label("Show on map", systemImage: "map") }
                    }
                }
            }
            .animation(.snappy, value: lines.map(\.id))

            if model.stops.count > 0 {
                Text("\(model.stops.count) stops within \(Int(UserDefaults.standard.double(forKey: Prefs.radius))) m")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Offline banner

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash").font(.headline).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("You're offline").font(.subheadline.weight(.semibold))
                Text("Showing scheduled times. Trip planning, saved trips and the PATH still work.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Stop row (search results, saved, fallbacks)

struct StopRow: View {
    let stop: TransitStop
    var distance: CLLocationDistance? = nil
    var trailing: AnyView? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: Catalog.agency(stop.agencyID)?.brandHex ?? "777777") ?? .gray)
                        .frame(width: 38, height: 38)
                    Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.name).font(.body.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        AgencyTag(agencyID: stop.agencyID)
                        Text("#\(stop.displayCode)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        if let distance { Text("· \(distance.shortDistance)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Spacer(minLength: 0)
                if let trailing { trailing }
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .card(radius: 16)
        }
        .buttonStyle(PressableStyle())
        .tint(.primary)
    }

    private var icon: String {
        if let m = stop.mode { return m.symbol }
        if Catalog.agency(stop.agencyID)?.source == .metrolinx || stop.agencyID == "up" { return "train.side.front.car" }
        return "bus.fill"
    }
}
