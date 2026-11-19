import SwiftUI
import MapKit
import CoreMotion

// MARK: - Motion + heading (work underground, no GPS or signal needed)

@MainActor @Observable
final class WalkSensors: NSObject, CLLocationManagerDelegate {
    private(set) var metresWalked: Double = 0
    private(set) var heading: Double?          // degrees from north
    private(set) var pedometerAvailable = CMPedometer.isDistanceAvailable()
    private let pedometer = CMPedometer()
    private let compass = CLLocationManager()
    private var base: Double = 0
    private var raw: Double = 0

    override init() {
        super.init()
        compass.delegate = self
        compass.headingFilter = 5
    }

    func start() {
        if CLLocationManager.headingAvailable() { compass.startUpdatingHeading() }
        guard pedometerAvailable else { return }
        pedometer.startUpdates(from: .now) { [weak self] data, _ in
            guard let d = data?.distance?.doubleValue else { return }
            Task { @MainActor in
                guard let self else { return }
                self.raw = d
                self.metresWalked = max(0, d - self.base)
            }
        }
    }

    /// Restart the distance count (when moving on to the next step).
    func resetDistance() { base = raw; metresWalked = 0 }

    func stop() { pedometer.stopUpdates(); compass.stopUpdatingHeading() }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
        let v = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        Task { @MainActor in self.heading = v }
    }
}

// MARK: - PATH planner

struct PathPlannerView: View {
    @State private var from: PathNetwork.Landmark?
    @State private var to: PathNetwork.Landmark?
    @State private var stepFree = false
    @State private var picking: Pick?
    @State private var guiding = false
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(center: PathNetwork.center, latitudinalMeters: 1800, longitudinalMeters: 1800))
    private let net = PathNetwork.shared

    enum Pick: Identifiable { case from, to; var id: Int { self == .from ? 0 : 1 } }

    private var route: PathNetwork.Route? {
        guard let from, let to, from != to else { return nil }
        return net.route(from: from, to: to, stepFree: stepFree)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                intro
                endpoints
                Toggle(isOn: $stepFree) { Label("Step-free (avoid stairs)", systemImage: "figure.roll") }
                    .tint(Theme.signal)
                    .padding(.horizontal, 4)
                map
                if let route {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(route.minutes) min walk").font(.title3.weight(.bold))
                            Text("\(route.metres.shortDistance) indoors · \(route.steps.count - 1) steps").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { guiding = true } label: { Label("Start", systemImage: "figure.walk").font(.headline) }
                            .buttonStyle(.borderedProminent).tint(Theme.signal).foregroundStyle(.black)
                    }
                    .padding(14).card(radius: 18)
                    VStack(spacing: 0) {
                        ForEach(route.steps) { s in
                            PathStepRow(step: s)
                            if s.id != route.steps.last?.id { Divider().padding(.leading, 52) }
                        }
                    }
                    .card(radius: 18)
                } else if from != nil && to != nil {
                    EmptyState(symbol: "exclamationmark.triangle", title: "No indoor route",
                               message: stepFree ? "There's no step-free indoor route between these. Try turning off step-free." : "These aren't connected through the PATH.")
                }
                Text("Works offline and without GPS. \(net.attribution).").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
        .navigationTitle("PATH")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $picking) { p in
            PathPlacePicker(title: p == .from ? "I'm at" : "Going to") { l in
                if p == .from { from = l } else { to = l }
                picking = nil
            }
        }
        .fullScreenCover(isPresented: $guiding) {
            if let route, let to { PathGuideView(route: route, destination: to.name) }
        }
        .onChange(of: from) { _, _ in fit() }
        .onChange(of: to) { _, _ in fit() }
    }

    private var intro: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                .font(.title2.weight(.bold)).foregroundStyle(.black)
                .frame(width: 46, height: 46).background(Theme.signal, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Underground PATH").font(.headline)
                Text("Downtown Toronto's 30 km of indoor walkways. GPS doesn't work down here, so pick where you are from signs around you.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private var endpoints: some View {
        VStack(spacing: 0) {
            row(from?.name, placeholder: "I'm at… (station, entrance or shop)", dot: .blue, symbol: from?.symbol) { picking = .from }
            Divider().padding(.leading, 38)
            row(to?.name, placeholder: "Going to…", dot: Theme.signal, symbol: to?.symbol) { picking = .to }
        }
        .card(radius: 18)
    }

    private func row(_ title: String?, placeholder: String, dot: Color, symbol: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle().fill(dot).frame(width: 10, height: 10).padding(.leading, 4)
                Text(title ?? placeholder).font(.body.weight(title == nil ? .regular : .semibold))
                    .foregroundStyle(title == nil ? .secondary : .primary).lineLimit(1)
                Spacer()
                if let symbol { Image(systemName: symbol).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 12).frame(minHeight: 52).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var map: some View {
        Map(position: $camera) {
            ForEach(Array(net.lines.enumerated()), id: \.offset) { _, line in
                MapPolyline(coordinates: line).stroke(Theme.signal.opacity(route == nil ? 0.55 : 0.25), lineWidth: route == nil ? 3 : 2)
            }
            if let route {
                MapPolyline(coordinates: route.coordinates).stroke(.white, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: route.coordinates).stroke(Color(hex: "1F7AE0")!, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            if let from { Marker(from.name, systemImage: "figure.stand", coordinate: from.coordinate).tint(.blue) }
            if let to { Marker(to.name, systemImage: "flag.checkered", coordinate: to.coordinate).tint(.orange) }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func fit() {
        let pts = (route?.coordinates ?? []) + [from?.coordinate, to?.coordinate].compactMap { $0 }
        guard !pts.isEmpty else { return }
        let lats = pts.map(\.latitude), lons = pts.map(\.longitude)
        let c = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        withAnimation { camera = .region(MKCoordinateRegion(center: c, span: .init(latitudeDelta: max(0.004, (lats.max()! - lats.min()!) * 1.5),
                                                                                    longitudeDelta: max(0.004, (lons.max()! - lons.min()!) * 1.5)))) }
    }
}

struct PathStepRow: View {
    let step: PathNetwork.Step
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.symbol).font(.system(size: 16, weight: .bold))
                .frame(width: 32, height: 32).background(Color(uiColor: .tertiarySystemFill), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(step.instruction).font(.subheadline.weight(.semibold))
                if let d = step.detail { Text(d).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if step.metres > 0 { Text(step.metres.shortDistance).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .padding(12)
    }
}

struct PathPlacePicker: View {
    let title: String
    let onPick: (PathNetwork.Landmark) -> Void
    @State private var query = ""
    @State private var searching = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(PathNetwork.shared.places(near: LocationService.shared.location?.coordinate, matching: query).prefix(80)) { l in
                Button { onPick(l) } label: {
                    Label { Text(l.name).foregroundStyle(.primary) } icon: { Image(systemName: l.symbol).foregroundStyle(Theme.accent) }
                }
                .tint(.primary)
            }
            .searchable(text: $query, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .always), prompt: "Station, entrance, shop…")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

// MARK: - Step-by-step PATH guide

struct PathGuideView: View {
    let route: PathNetwork.Route
    let destination: String
    @State private var index = 0
    @State private var sensors = WalkSensors()
    @Environment(\.dismiss) private var dismiss

    private var step: PathNetwork.Step { route.steps[min(index, route.steps.count - 1)] }
    private var isLast: Bool { index >= route.steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40).background(.thinMaterial, in: Circle()) }
                Spacer()
                VStack(spacing: 0) {
                    Text("To \(destination)").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("Step \(index + 1) of \(route.steps.count)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .tint(.primary)
            .padding(.horizontal, 16).padding(.top, 8)

            ProgressView(value: Double(index), total: Double(max(1, route.steps.count - 1)))
                .tint(Theme.signal).padding(.horizontal, 16).padding(.top, 10)

            Spacer()
            arrow
            VStack(spacing: 10) {
                Text(step.instruction).font(.system(size: 30, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
                if let d = step.detail { Text(d).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                if step.metres > 0 {
                    let left = max(0, step.metres - sensors.metresWalked)
                    Text(sensors.pedometerAvailable ? "\(left.shortDistance) to go" : "About \(step.metres.shortDistance)")
                        .font(.headline.monospacedDigit()).foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 24)
            Spacer()

            if !isLast {
                let next = route.steps[index + 1]
                HStack(spacing: 10) {
                    Image(systemName: next.symbol).foregroundStyle(.secondary)
                    Text("Then: \(next.instruction)").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                }
                .padding(14).card(radius: 16).padding(.horizontal, 16)
            }
            HStack(spacing: 12) {
                Button { go(-1) } label: { Label("Back", systemImage: "chevron.left").frame(maxWidth: .infinity).padding(.vertical, 14) }
                    .buttonStyle(.bordered).disabled(index == 0)
                Button { isLast ? dismiss() : go(1) } label: {
                    Label(isLast ? "Done" : "Next step", systemImage: isLast ? "checkmark" : "chevron.right")
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent).tint(Theme.signal).foregroundStyle(.black)
            }
            .font(.headline)
            .padding(16)
            Text("Works offline and without GPS — distance from your phone's motion sensors.")
                .font(.caption2).foregroundStyle(.tertiary).padding(.bottom, 8)
        }
        .onAppear { sensors.start(); UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { sensors.stop(); UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: sensors.metresWalked) { _, walked in
            // Auto-advance once you've walked (most of) this step.
            if !isLast && step.metres > 0 && walked >= step.metres * 0.9 { go(1) }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: index)
    }

    private var arrow: some View {
        let rotation = step.metres > 0 ? step.bearing - (sensors.heading ?? step.bearing) : 0
        return ZStack {
            Circle().fill(Theme.signal.opacity(0.15)).frame(width: 170, height: 170)
            Image(systemName: step.metres > 0 && sensors.heading != nil ? "location.north.fill" : step.symbol)
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(Theme.accent)
                .rotationEffect(.degrees(sensors.heading == nil ? 0 : rotation))
                .animation(.smooth, value: rotation)
        }
        .padding(.bottom, 28)
        .accessibilityHidden(true)
    }

    private func go(_ d: Int) {
        index = min(max(0, index + d), route.steps.count - 1)
        sensors.resetDistance()
    }
}
