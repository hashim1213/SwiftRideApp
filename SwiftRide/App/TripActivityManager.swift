import Foundation
import ActivityKit
import CoreLocation

/// Runs the Live Activity for the trip being guided. While a trip is active the app keeps a background
/// location session, so it can move the Lock Screen / Dynamic Island on to the next step (walk → board →
/// get off) without a push server. With no GPS or signal the steps still advance on the timetable.
@MainActor @Observable
final class TripActivityManager {
    static let shared = TripActivityManager()

    /// The trip being guided, so tapping the Live Activity can reopen the guide.
    private(set) var itinerary: Itinerary?
    private var activity: Activity<TripActivityAttributes>?
    private var lastState: TripActivityAttributes.ContentState?
    private var timer: Timer?
    private var backgroundSession: CLBackgroundActivitySession?

    var isRunning: Bool { itinerary != nil }

    private init() {}

    func start(_ itinerary: Itinerary) {
        if self.itinerary == itinerary, activity != nil { refresh(); return }
        end()
        self.itinerary = itinerary
        backgroundSession = CLBackgroundActivitySession()
        LocationService.shared.setTripTracking(true)

        if ActivityAuthorizationInfo().areActivitiesEnabled, let state = Self.content(for: itinerary, now: .now) {
            let attributes = TripActivityAttributes(fromName: Self.fromName(itinerary), toName: Self.toName(itinerary), leaveAt: itinerary.leaveAt)
            activity = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: Self.staleDate(state)))
            lastState = state
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor in TripActivityManager.shared.refresh() }
        }
    }

    /// Recomputes where the rider is and pushes it to the Live Activity if anything changed.
    func refresh() {
        guard let itinerary else { return }
        let now = Date()
        if now > itinerary.arriveAt.addingTimeInterval(10 * 60) { end(); return }
        guard let activity, let state = Self.content(for: itinerary, now: now, location: Self.trustedLocation) else { return }
        guard state != lastState else { return }
        // Buzz and expand the Dynamic Island when the step changes (time to board, get off, …).
        let alert: AlertConfiguration? = lastState.map { $0.phase != state.phase || ($0.stopsRemaining ?? 9) > 1 && state.stopsRemaining == 1 } == true
            ? AlertConfiguration(title: "\(state.title)", body: "\(state.subtitle)", sound: .default) : nil
        lastState = state
        Task { await activity.update(.init(state: state, staleDate: Self.staleDate(state)), alertConfiguration: alert) }
        if state.phase == .arrived {
            Task { await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(5 * 60))) }
            stopTracking()
            self.activity = nil
            self.itinerary = nil
        }
    }

    func end() {
        timer?.invalidate(); timer = nil
        stopTracking()
        if let activity { Task { await activity.end(nil, dismissalPolicy: .immediate) } }
        activity = nil
        itinerary = nil
        lastState = nil
    }

    /// Ends activities left over from a previous launch (the itinerary isn't kept across launches).
    func cleanUpStale() {
        guard itinerary == nil else { return }
        for a in Activity<TripActivityAttributes>.activities { Task { await a.end(nil, dismissalPolicy: .immediate) } }
    }

    private func stopTracking() {
        timer?.invalidate(); timer = nil
        backgroundSession?.invalidate(); backgroundSession = nil
        LocationService.shared.setTripTracking(false)
    }

    private static var trustedLocation: CLLocation? {
        guard let l = LocationService.shared.location, l.horizontalAccuracy < 80, -l.timestamp.timeIntervalSinceNow < 90 else { return nil }
        return l
    }

    /// Past this, the widget shows clock times instead of a timer stuck at 0:00.
    private static func staleDate(_ s: TripActivityAttributes.ContentState) -> Date {
        max(s.target, .now).addingTimeInterval(2 * 60)
    }

    private static func fromName(_ i: Itinerary) -> String {
        if case .walk(let w)? = i.legs.first { return w.fromName }
        return i.firstRide?.from.name ?? ""
    }

    private static func toName(_ i: Itinerary) -> String {
        if case .walk(let w)? = i.legs.last { return w.toName }
        return i.rides.last?.to.name ?? ""
    }

    // MARK: Mapping the guide's state to the Live Activity

    static func content(for i: Itinerary, now: Date, location: CLLocation? = nil) -> TripActivityAttributes.ContentState? {
        let g = GuideState(itinerary: i, now: now, location: location)
        let clock = TimeText.clock
        var then: String? = g.upcoming.map { "Then \($0.next.route.badgeText) at \($0.next.from.name) · \($0.transferMinutes) min to change" }
        typealias S = TripActivityAttributes.ContentState
        switch g.phase {
        case .walkToStop(let w, let r):
            let leave = r.depart.addingTimeInterval(-w.seconds)
            then = "Then \(r.route.badgeText) to \(r.headsign)"
            return S(phase: .walk, title: "Walk to \(r.from.name)",
                     subtitle: "\(r.route.badgeText) departs \(clock.string(from: r.depart))\(r.platform.map { " · Platform \($0)" } ?? "")",
                     target: leave, targetLabel: leave > now ? "Leave in" : "Leave now", route: r.route,
                     stopsRemaining: nil, then: then, arriveAt: i.arriveAt, usingGPS: g.usingGPS)
        case .waiting(let r):
            return S(phase: .wait, title: "\(r.route.badgeText) to \(r.headsign)",
                     subtitle: "From \(r.from.name)\(r.platform.map { " · Platform \($0)" } ?? "")",
                     target: r.depart, targetLabel: "Departs in", route: r.route,
                     stopsRemaining: nil, then: "Get off at \(r.to.name)", arriveAt: i.arriveAt, usingGPS: g.usingGPS)
        case .riding(let r, let remaining):
            let title = remaining <= 0 ? "Get off now" : remaining == 1 ? "Get off at the next stop" : "Get off in \(remaining) stops"
            let nextStop = r.visits.indices.contains(g.stopIndex) && remaining > 1 ? "Next: \(r.visits[g.stopIndex].name)" : nil
            return S(phase: .ride, title: title,
                     subtitle: nextStop ?? "At \(r.to.name) · \(clock.string(from: r.arrive))",
                     target: r.arrive, targetLabel: "Off in", route: r.route,
                     stopsRemaining: remaining, then: then ?? (nextStop != nil ? "Get off at \(r.to.name)" : nil),
                     arriveAt: i.arriveAt, usingGPS: g.usingGPS)
        case .walkToEnd(let w):
            return S(phase: .walkEnd, title: "Walk to \(w.toName)", subtitle: "About \(w.minutes) min",
                     target: i.arriveAt, targetLabel: "Arrive in", route: nil,
                     stopsRemaining: nil, then: nil, arriveAt: i.arriveAt, usingGPS: g.usingGPS)
        case .arrived:
            return S(phase: .arrived, title: "You've arrived", subtitle: toName(i),
                     target: now, targetLabel: "Arrived", route: nil,
                     stopsRemaining: nil, then: nil, arriveAt: i.arriveAt, usingGPS: false)
        }
    }
}
