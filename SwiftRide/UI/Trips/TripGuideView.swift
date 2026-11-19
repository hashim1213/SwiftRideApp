import SwiftUI
import UserNotifications
import CoreLocation

/// Step-by-step guidance for a planned trip. Progress comes from the timetable/live times, refined by GPS
/// when there's a good fix — so it keeps working in tunnels and with no signal. Alerts are local notifications.
struct TripGuideView: View {
    let itinerary: Itinerary
    @Environment(\.dismiss) private var dismiss
    @State private var alertsOn = false
    @State private var location = LocationService.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { ctx in
            let state = GuideState(itinerary: itinerary, now: ctx.date, location: freshLocation)
            VStack(spacing: 0) {
                header(state, now: ctx.date)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        hero(state, now: ctx.date)
                        if let next = state.upcoming { upcomingCard(next) }
                        if let ride = state.currentRide { stopsList(ride, state: state, now: ctx.date) }
                        legsOverview(state)
                    }
                    .padding(16)
                }
                footer
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true; scheduleAlerts(); TripActivityManager.shared.start(itinerary) }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var freshLocation: CLLocation? {
        guard let l = location.location, l.horizontalAccuracy < 80, -l.timestamp.timeIntervalSinceNow < 90 else { return nil }
        return l
    }

    // MARK: Header (Waymo-style "21 min to arrival")

    private func header(_ s: GuideState, now: Date) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40).background(.thinMaterial, in: Circle())
                }
                .tint(.primary)
                Spacer()
                VStack(spacing: 0) {
                    let mins = max(0, Int(itinerary.arriveAt.timeIntervalSince(now) / 60))
                    Text(mins < 60 ? "\(mins) min to arrival" : TimeText.duration(itinerary.arriveAt.timeIntervalSince(now)) + " to arrival")
                        .font(.headline)
                    Text("Arriving \(TimeText.clock.string(from: itinerary.arriveAt))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: Connectivity.shared.isOnline ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(Connectivity.shared.isOnline ? .secondary : Color.orange)
                    .frame(width: 40, height: 40)
                    .accessibilityLabel(Connectivity.shared.isOnline ? "Online" : "Offline")
            }
            ProgressView(value: s.progress).tint(Theme.signal)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
        .background(.bar)
    }

    // MARK: Hero instruction (Transit-style "Get off in 3 stops")

    @ViewBuilder private func hero(_ s: GuideState, now: Date) -> some View {
        let tint = s.currentRide?.route.color ?? s.nextRide?.route.color ?? Theme.signal
        let fg = s.currentRide?.route.textColor ?? s.nextRide?.route.textColor ?? .black
        VStack(alignment: .leading, spacing: 10) {
            switch s.phase {
            case .walkToStop(let w, let ride):
                Label("Walk \(w.minutes) min", systemImage: "figure.walk").font(.subheadline.weight(.bold)).opacity(0.85)
                Text("to \(ride.from.name)").font(.system(size: 28, weight: .heavy, design: .rounded))
                Text(leaveText(ride.depart.addingTimeInterval(-w.seconds), now: now)).font(.headline)
            case .waiting(let ride):
                HStack(spacing: 8) { RouteBadge(route: ride.route, size: .large, inverted: true); Text("to \(ride.headsign)").font(.headline).lineLimit(2) }
                Text(boardText(ride, now: now)).font(.system(size: 28, weight: .heavy, design: .rounded))
                if let p = ride.platform { Label("Platform \(p)", systemImage: "signpost.right.fill").font(.headline) }
            case .riding(let ride, let remaining):
                HStack(spacing: 8) { RouteBadge(route: ride.route, size: .large, inverted: true); Text("to \(ride.headsign)").font(.headline).lineLimit(2) }
                Text(remaining <= 0 ? "Get off now" : remaining == 1 ? "Get off at the next stop" : "Get off in \(remaining) stops")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                Text("at \(ride.to.name) · \(TimeText.clock.string(from: ride.arrive))").font(.headline).opacity(0.9)
            case .walkToEnd(let w):
                Label("Last stretch", systemImage: "figure.walk").font(.subheadline.weight(.bold)).opacity(0.85)
                Text("Walk \(w.minutes) min to \(w.toName)").font(.system(size: 28, weight: .heavy, design: .rounded))
            case .arrived:
                Text("You've arrived 🎉").font(.system(size: 30, weight: .heavy, design: .rounded))
            }
            HStack(spacing: 6) {
                Image(systemName: s.usingGPS ? "location.fill" : "clock.fill")
                Text(s.usingGPS ? "Tracking with GPS" : "Estimated from the schedule — no GPS needed")
            }
            .font(.caption.weight(.semibold)).opacity(0.75)
        }
        .foregroundStyle(fg)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func leaveText(_ t: Date, now: Date) -> String {
        let m = Int(t.timeIntervalSince(now) / 60)
        return m <= 0 ? "Leave now" : "Leave in \(m) min (\(TimeText.clock.string(from: t)))"
    }

    private func boardText(_ r: RideLeg, now: Date) -> String {
        let m = Int(r.depart.timeIntervalSince(now) / 60)
        return m <= 0 ? "Board now" : "Arrives in \(m) min"
    }

    // MARK: Upcoming connection (Trainline-style)

    private func upcomingCard(_ u: GuideState.Upcoming) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.swap").font(.title3).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Upcoming connection").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("Change to \(u.next.route.badgeText) at \(u.next.from.name)").font(.subheadline.weight(.semibold))
                Text("\(u.transferMinutes) min to make it\(u.walk.map { " · \($0.minutes) min walk" } ?? "")").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            RouteBadge(route: u.next.route, size: .regular)
        }
        .padding(14).card(radius: 18)
    }

    // MARK: Stops on the current ride

    private func stopsList(_ ride: RideLeg, state: GuideState, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Stops").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.bottom, 8)
            ForEach(Array(ride.visits.enumerated()), id: \.offset) { i, v in
                let passed = i < state.stopIndex
                let isNext = i == state.stopIndex
                let isLast = i == ride.visits.count - 1
                HStack(spacing: 12) {
                    VStack(spacing: 0) {
                        Rectangle().fill(i == 0 ? .clear : ride.route.color.opacity(passed ? 0.35 : 1)).frame(width: 4, height: 12)
                        Circle().fill(isNext ? ride.route.color : Color(uiColor: .systemBackground))
                            .overlay(Circle().strokeBorder(ride.route.color.opacity(passed ? 0.35 : 1), lineWidth: 3))
                            .frame(width: isNext || isLast ? 18 : 12, height: isNext || isLast ? 18 : 12)
                        Rectangle().fill(isLast ? .clear : ride.route.color.opacity(passed ? 0.35 : 1)).frame(width: 4, height: 12)
                    }
                    .frame(width: 22)
                    Text(v.name).font(isNext || isLast ? .subheadline.weight(.bold) : .subheadline).foregroundStyle(passed ? .secondary : .primary)
                    Spacer()
                    Text(TimeText.clock.string(from: v.time)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14).card(radius: 18)
    }

    private func legsOverview(_ s: GuideState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your trip").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            LegStrip(itinerary: itinerary)
            Text("\(TimeText.clock.string(from: itinerary.leaveAt)) – \(TimeText.clock.string(from: itinerary.arriveAt)) · \(itinerary.transfers == 0 ? "Direct" : "\(itinerary.transfers) change\(itinerary.transfers > 1 ? "s" : "")")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).card(radius: 18)
    }

    private var footer: some View {
        HStack {
            Image(systemName: alertsOn ? "bell.badge.fill" : "bell.slash").foregroundStyle(alertsOn ? Theme.accent : .secondary)
            Text(alertsOn ? "Alerts and your Lock Screen will guide you, even offline. Close this and the trip keeps going." : "Turn on notifications to get board and get-off alerts.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("End") { cancelAlerts(); TripActivityManager.shared.end(); dismiss() }.font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: Alerts (local, so they fire with no signal)

    private var alertIDs: [String] { itinerary.rides.enumerated().flatMap { i, _ in ["guide.board.\(i)", "guide.off.\(i)"] } }

    private func scheduleAlerts() {
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            cancelAlerts()
            for (i, r) in itinerary.rides.enumerated() {
                add(center, id: "guide.board.\(i)", at: r.depart.addingTimeInterval(-180),
                    title: "\(r.route.badgeText) to \(r.headsign) in 3 min", body: "From \(r.from.name)\(r.platform.map { " · Platform \($0)" } ?? "")")
                add(center, id: "guide.off.\(i)", at: r.arrive.addingTimeInterval(-120),
                    title: "Get off at the next stop", body: "\(r.to.name) — about 2 minutes away")
            }
            alertsOn = true
        }
    }

    private func add(_ center: UNUserNotificationCenter, id: String, at: Date, title: String, body: String) {
        let wait = at.timeIntervalSinceNow
        guard wait > 5 else { return }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default; c.interruptionLevel = .timeSensitive
        center.add(UNNotificationRequest(identifier: id, content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)))
    }

    private func cancelAlerts() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: alertIDs)
    }
}

/// Where the rider is in the trip right now.
struct GuideState {
    enum Phase {
        case walkToStop(WalkLeg, RideLeg)
        case waiting(RideLeg)
        case riding(RideLeg, stopsRemaining: Int)
        case walkToEnd(WalkLeg)
        case arrived
    }
    struct Upcoming { let next: RideLeg; let transferMinutes: Int; let walk: WalkLeg? }

    let phase: Phase
    let currentRide: RideLeg?
    let nextRide: RideLeg?
    let stopIndex: Int
    let upcoming: Upcoming?
    let progress: Double
    let usingGPS: Bool

    init(itinerary: Itinerary, now: Date, location: CLLocation?) {
        let total = max(1, itinerary.arriveAt.timeIntervalSince(itinerary.leaveAt))
        progress = min(1, max(0, now.timeIntervalSince(itinerary.leaveAt) / total))
        let rides = itinerary.rides
        var phase: Phase = .arrived, current: RideLeg?, next: RideLeg?, idx = 0, gps = false, upcoming: Upcoming?

        if let rideIdx = rides.firstIndex(where: { now < $0.arrive }) {
            let r = rides[rideIdx]
            if now < r.depart {
                next = r
                // Before boarding: still walking if the walk hasn't started yet.
                let legIdx = itinerary.legs.firstIndex { if case .ride(let x) = $0 { return x == r } else { return false } } ?? 0
                if legIdx > 0, case .walk(let w) = itinerary.legs[legIdx - 1], now < r.depart.addingTimeInterval(-w.seconds + 60) {
                    phase = .walkToStop(w, r)
                } else {
                    phase = .waiting(r)
                }
            } else {
                current = r
                // Which stop are we at? GPS if we trust it, otherwise the stop times.
                if let loc = location, !r.visits.isEmpty {
                    let nearest = r.visits.enumerated().min { a, b in
                        loc.distance(from: stopLocation(a.element, ride: r)) < loc.distance(from: stopLocation(b.element, ride: r))
                    }
                    if let n = nearest, loc.distance(from: stopLocation(n.element, ride: r)) < 400 { idx = n.offset; gps = true }
                }
                var remaining: Int
                if gps {
                    remaining = max(0, r.visits.count - 1 - idx)          // at stop idx: stops still to reach
                } else {
                    idx = r.visits.firstIndex { $0.time >= now } ?? max(0, r.visits.count - 1)
                    remaining = max(0, r.visits.count - idx)              // heading to stop idx: it and the ones after
                }
                if r.visits.isEmpty { remaining = r.arrive.timeIntervalSince(now) < 120 ? 1 : 2 }
                if r.arrive.timeIntervalSince(now) < 45 { remaining = 0 }  // pulling in: get off now
                phase = .riding(r, stopsRemaining: remaining)
            }
            if rideIdx + 1 < rides.count {
                let n = rides[rideIdx + 1]
                let walk = itinerary.legs.compactMap { if case .walk(let w) = $0, w.fromName == r.to.name { return w } else { return nil } }.first
                upcoming = Upcoming(next: n, transferMinutes: max(0, Int(n.depart.timeIntervalSince(r.arrive) / 60)), walk: walk)
            }
        } else if case .walk(let w)? = itinerary.legs.last, now < itinerary.arriveAt {
            phase = .walkToEnd(w)
        }
        self.phase = phase; currentRide = current; nextRide = next; stopIndex = idx; self.upcoming = upcoming; usingGPS = gps
    }
}

private func stopLocation(_ v: StopVisit, ride: RideLeg) -> CLLocation {
    // Visits carry names and times; coordinates come from the bundled stop when we know it.
    if v.stopID == ride.from.stopID { return ride.from.location }
    if v.stopID == ride.to.stopID { return ride.to.location }
    if let s = StopLookup.shared.stop(agency: ride.route.agencyID, id: v.stopID) { return s.location }
    return ride.from.location
}
