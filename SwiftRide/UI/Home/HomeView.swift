import SwiftUI
import MapKit

enum SheetRoute: Hashable {
    case stop(TransitStop)
    case search
    case alerts
    case saved
    case cities
    case planner(from: Place, to: Place?)
    case itinerary(Itinerary)
}

@MainActor @Observable
final class Router {
    var path: [SheetRoute] = []
    var detent: PresentationDetent = .fraction(0.45)
    var showSettings = false
    /// Ask the map to centre on a stop (e.g. from a trip timeline).
    var focusRequest: TransitStop?

    func focus(_ stop: TransitStop) { focusRequest = stop }

    func open(_ r: SheetRoute) {
        path.append(r)
        if detent == .height(SheetMetrics.peek) { detent = .fraction(0.45) }
    }
}

enum SheetMetrics {
    static let peek: CGFloat = 190
}

struct HomeView: View {
    @State private var model = NearbyModel()
    @State private var router = Router()
    @State private var location = LocationService.shared
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var showSearchHere = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Prefs.manualCityID) private var manualCityID = ""

    var body: some View {
        TransitMap(model: model, router: router, camera: $camera, onLocate: useMyLocation) { region in
            visibleRegion = region
            updateSearchHere(region)
        }
        .overlay(alignment: .top) { topOverlay }
        .sheet(isPresented: .constant(true)) {
            NavigationStack(path: $router.path) {
                HomeSheet(model: model, router: router, location: location)
                    .navigationDestination(for: SheetRoute.self) { route in
                        switch route {
                        case .stop(let s): StopDetailView(stop: s, model: model, router: router)
                        case .search: SearchView(model: model, router: router)
                        case .alerts: AlertsView(model: model)
                        case .saved: SavedView(model: model, router: router)
                        case .cities: CityPickerView { city in pick(city) }
                        case .planner(let from, let to): TripPlannerView(model: PlannerModel(from: from, to: to), router: router)
                        case .itinerary(let it): ItineraryDetailView(itinerary: it, router: router)
                        }
                    }
            }
            .presentationDetents([.height(SheetMetrics.peek), .fraction(0.45), .large], selection: $router.detent)
            .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
            .presentationContentInteraction(.scrolls)
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled()
            .sheet(isPresented: $router.showSettings) {
                SettingsView(model: model, onPickCity: { pick($0) }, onUseLocation: useMyLocation)
            }
        }
        .task {
            location.start()
            if let city = Catalog.city(manualCityID) {
                // The rider explicitly chose a city; respect it until they ask for their location.
                model.show(city: city)
                camera = .region(MKCoordinateRegion(center: city.coordinate, latitudinalMeters: 2500, longitudinalMeters: 2500))
            } else if let loc = location.location {
                model.useUserLocation(loc)
            } else if location.isDenied {
                fallbackCity()
            }
            model.startTicking()
        }
        .onChange(of: location.location) { _, new in
            guard manualCityID.isEmpty, model.origin != .map else { return }
            model.useUserLocation(new)
        }
        .onChange(of: location.status) { _, _ in
            if location.isDenied && model.center == nil { fallbackCity() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.reload(); model.startTicking(); location.start() }
            if phase == .background { model.stopTicking(); location.stop() }
        }
        .onChange(of: router.focusRequest) { _, stop in
            if let stop { model.focusedStop = stop }
        }
        .onOpenURL { url in handleDeepLink(url) }
        .onChange(of: model.focusedStop) { _, stop in
            guard let stop else { return }
            withAnimation(.smooth(duration: 0.6)) {
                camera = .camera(MapCamera(centerCoordinate: offsetForSheet(stop.coordinate), distance: 1600, heading: 0, pitch: 0))
            }
        }
    }

    // MARK: Top overlay

    @ViewBuilder private var topOverlay: some View {
        if showSearchHere {
            Button {
                if let c = visibleRegion?.center { model.search(at: c) }
                showSearchHere = false
            } label: {
                Label("Search this area", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .foregroundStyle(.black)
                    .background(Theme.signal, in: Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func updateSearchHere(_ region: MKCoordinateRegion) {
        guard let c = model.center else { return }
        let moved = CLLocation(latitude: c.latitude, longitude: c.longitude)
            .distance(from: CLLocation(latitude: region.center.latitude, longitude: region.center.longitude))
        let should = moved > 450 && region.span.latitudeDelta < 0.2 && model.focusedStop == nil
        if should != showSearchHere { withAnimation(.snappy) { showSearchHere = should } }
    }

    /// Nudges the camera so the stop sits in the visible area above the sheet.
    private func offsetForSheet(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        .init(latitude: c.latitude - 0.0030, longitude: c.longitude)
    }

    /// swiftride://trip/<id>  ·  swiftride://stop/<agency>/<stopID>  ·  swiftride://plan
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "swiftride" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.host {
        case "trip":
            if let id = parts.first, let trip = TripsStore.shared.trips.first(where: { $0.id == id }) {
                router.path = [.planner(from: trip.from, to: trip.to)]
            }
        case "stop":
            if parts.count >= 2, let stop = FavoritesStore.shared.stops.first(where: { $0.agencyID == parts[0] && $0.stopID == parts[1] }) {
                router.path = [.stop(stop)]
            }
        case "plan":
            router.path = [.planner(from: .currentLocation, to: nil)]
        default: break
        }
        if router.detent == .height(SheetMetrics.peek) { router.detent = .fraction(0.45) }
    }

    /// No location and no chosen city — show Toronto so the app isn't empty, without remembering it.
    private func fallbackCity() {
        let city = Catalog.city("toronto")!
        model.show(city: city, remember: false)
        camera = .region(MKCoordinateRegion(center: city.coordinate, latitudinalMeters: 2500, longitudinalMeters: 2500))
    }

    private func pick(_ city: City) {
        model.show(city: city)
        router.path.removeAll()
        withAnimation(.smooth(duration: 0.8)) {
            camera = .region(MKCoordinateRegion(center: city.coordinate, latitudinalMeters: 2500, longitudinalMeters: 2500))
        }
    }

    private func useMyLocation() {
        manualCityID = ""
        if location.isDenied { router.showSettings = true; return }
        if !location.isAuthorized { location.requestPermission() }
        location.start()
        if let l = location.location { model.useUserLocation(l, force: true) }
        showSearchHere = false
        withAnimation(.smooth) { camera = .userLocation(fallback: .automatic) }
    }
}

// MARK: - Map

struct TransitMap: View {
    let model: NearbyModel
    let router: Router
    @Binding var camera: MapCameraPosition
    var onLocate: () -> Void
    var onRegion: (MKCoordinateRegion) -> Void
    @State private var selection: String?
    @AppStorage(Prefs.showVehicles) private var showVehicles = true
    @Namespace private var mapScope

    var body: some View {
        Map(position: $camera, selection: $selection, scope: mapScope) {
            UserAnnotation()

            ForEach(mapStops, id: \.id) { stop in
                Annotation(stop.name, coordinate: stop.coordinate, anchor: .center) {
                    StopPin(stop: stop, highlighted: stop.id == model.focusedStop?.id)
                }
                .annotationTitles(stop.id == model.focusedStop?.id ? .visible : .hidden)
                .tag(stop.id)
            }

            if showVehicles {
                ForEach(model.vehicles) { v in
                    Annotation(v.label, coordinate: v.coordinate, anchor: .center) {
                        VehiclePin(vehicle: v, route: route(for: v))
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls {
            MapCompass(scope: mapScope)
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 10) {
                mapButton("location.fill", label: "Show my location", action: onLocate)
                mapButton("gearshape.fill", label: "Settings") { router.showSettings = true }
            }
            .buttonBorderShape(.roundedRectangle)
            .tint(.primary)
            .padding(.trailing, 12)
            .padding(.top, 56)
        }
        .tint(.blue)
        .mapScope(mapScope)
        .onMapCameraChange(frequency: .onEnd) { ctx in onRegion(ctx.region) }
        .onChange(of: selection) { _, id in
            guard let id, let stop = mapStops.first(where: { $0.id == id }) else { return }
            router.path = [.stop(stop)]
            if router.detent == .height(SheetMetrics.peek) { router.detent = .fraction(0.45) }
            selection = nil
        }
        .ignoresSafeArea()
    }

    private func mapButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    private var mapStops: [TransitStop] {
        var list = model.stops.prefix(150).map(\.stop)
        if let f = model.focusedStop, !list.contains(where: { $0.id == f.id }) { list.append(f) }
        return list
    }

    private func route(for v: LiveVehicle) -> TransitRoute? {
        guard let r = v.routeID else { return nil }
        if let line = model.lines.first(where: { $0.route.agencyID == v.agencyID && $0.route.routeID == r }) { return line.route }
        return nil
    }
}

struct StopPin: View {
    let stop: TransitStop
    let highlighted: Bool

    var body: some View {
        let color = Color(hex: Catalog.agency(stop.agencyID)?.brandHex ?? "888888") ?? .gray
        ZStack {
            Circle().fill(.white).frame(width: highlighted ? 30 : 14, height: highlighted ? 30 : 14)
            Circle().fill(color).frame(width: highlighted ? 24 : 10, height: highlighted ? 24 : 10)
            if highlighted {
                Image(systemName: (stop.mode ?? .bus).symbol)
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: highlighted)
    }
}

struct VehiclePin: View {
    let vehicle: LiveVehicle
    let route: TransitRoute?

    var body: some View {
        let isGO = vehicle.agencyID == "go"
        let color = route?.color ?? (isGO ? Color(hex: "00853E")! : Color(hex: Catalog.agency(vehicle.agencyID)?.brandHex ?? "444444")!)
        ZStack {
            if let b = vehicle.bearing {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(color)
                    .offset(y: -17)
                    .rotationEffect(.degrees(b))
            }
            Group {
                if isGO {
                    Image(systemName: "train.side.front.car").font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                } else {
                    Text(route?.badgeText ?? "•").font(.system(size: 10, weight: .heavy, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(minWidth: 24, minHeight: 24).padding(.horizontal, 2)
                }
            }
            .foregroundStyle(route?.textColor ?? .white)
            .background(color, in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        }
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}
