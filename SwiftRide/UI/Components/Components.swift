import SwiftUI
import CoreLocation

// MARK: - Route badge

struct RouteBadge: View {
    let route: TransitRoute
    var size: Size = .regular
    var inverted = false

    enum Size { case small, regular, large }

    var body: some View {
        HStack(spacing: 3) {
            if size != .small && [.subway, .rail, .ferry].contains(route.mode) {
                Image(systemName: route.mode.symbol).font(font.weight(.semibold)).imageScale(.small)
            }
            Text(route.badgeText)
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, hPad)
        .frame(minWidth: minWidth, minHeight: height)
        .foregroundStyle(inverted ? route.color : route.textColor)
        .background(inverted ? route.textColor : route.color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityLabel("\(route.mode.label) \(route.badgeText)")
    }

    private var font: Font {
        switch size {
        case .small: .system(size: 12, weight: .heavy, design: .rounded)
        case .regular: .system(size: 15, weight: .heavy, design: .rounded)
        case .large: .system(size: 22, weight: .black, design: .rounded)
        }
    }
    private var hPad: CGFloat { size == .small ? 5 : size == .regular ? 7 : 10 }
    private var minWidth: CGFloat { size == .small ? 22 : size == .regular ? 34 : 48 }
    private var height: CGFloat { size == .small ? 20 : size == .regular ? 26 : 36 }
    private var radius: CGFloat { size == .small ? 5 : size == .regular ? 7 : 10 }
}

// MARK: - Live indicator (the little "signal" next to real-time predictions)

struct LiveIndicator: View {
    var color: Color = Theme.live
    @State private var on = false

    var body: some View {
        Image(systemName: "dot.radiowaves.up.forward")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .symbolEffect(.variableColor.iterative, options: .repeating, value: on)
            .onAppear { on = true }
            .accessibilityLabel("Live")
    }
}

// MARK: - Time formatting

enum TimeText {
    static let clock: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    /// ("4", "min"), ("Now", ""), ("8:42", "PM")
    static func countdown(_ date: Date, clockTimes: Bool = false, now: Date = .now) -> (value: String, unit: String) {
        let mins = Int((date.timeIntervalSince(now) / 60).rounded(.down))
        if !clockTimes {
            if mins <= 0 { return ("Now", "") }
            if mins < 60 { return ("\(mins)", "min") }
        }
        let s = clock.string(from: date)
        let parts = s.split(separator: " ")
        if parts.count == 2 { return (String(parts[0]), String(parts[1])) }
        return (s, "")
    }

    static func short(_ date: Date, clockTimes: Bool = false, now: Date = .now) -> String {
        let c = countdown(date, clockTimes: clockTimes, now: now)
        return c.unit.isEmpty ? c.value : (c.unit == "min" ? "\(c.value) min" : "\(c.value) \(c.unit)")
    }

    static func status(_ d: Departure) -> (String, Color)? {
        guard let delay = d.delaySeconds else { return d.isRealtime ? nil : ("Scheduled", .secondary) }
        let m = Int((Double(delay) / 60).rounded())
        if d.isCancelled { return ("Cancelled", Theme.late) }
        if m >= 2 { return ("\(m) min late", Theme.late) }
        if m <= -2 { return ("\(-m) min early", Theme.early) }
        return d.isRealtime ? ("On time", Theme.live) : ("Scheduled", .secondary)
    }
}

// MARK: - Big countdown

struct Countdown: View {
    let departure: Departure
    var tint: Color = .primary
    var large = true
    @AppStorage(Prefs.clockTimes) private var clockTimes = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let c = TimeText.countdown(departure.time, clockTimes: clockTimes, now: ctx.date)
            VStack(alignment: .trailing, spacing: -2) {
                Text(c.value)
                    .font(.system(size: large ? (c.value.count > 3 ? 26 : 34) : 20, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1)
                HStack(spacing: 3) {
                    if departure.isRealtime { LiveIndicator(color: tint == .primary ? Theme.live : tint) }
                    if !c.unit.isEmpty {
                        Text(c.unit).font(.system(size: large ? 13 : 11, weight: .bold, design: .rounded))
                    }
                }
                .opacity(0.9)
            }
            .foregroundStyle(tint)
            .animation(.snappy, value: c.value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TimeText.short(departure.time, clockTimes: clockTimes) + (departure.isRealtime ? ", live" : ", scheduled"))
    }
}

// MARK: - Nearby line card (Transit-style, filled with the route colour)

struct NearbyLineCard: View {
    let line: NearbyLine
    @AppStorage(Prefs.clockTimes) private var clockTimes = false

    var body: some View {
        let fg = line.route.textColor
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    RouteBadge(route: line.route, size: .large, inverted: true)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right").font(.caption.weight(.heavy))
                            Text(line.headsign)
                                .font(.headline.weight(.bold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                        }
                        if let agency = Catalog.agency(line.route.agencyID), Catalog.agencies(near: line.stop.coordinate).count > 1 {
                            Text(agency.shortName).font(.caption2.weight(.bold)).textCase(.uppercase).opacity(0.75)
                        }
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "figure.walk").font(.caption2.weight(.bold))
                    Text(stopLine).font(.footnote.weight(.medium)).lineLimit(1)
                }
                .opacity(0.85)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                if let next = line.next { Countdown(departure: next, tint: fg) }
                if line.departures.count > 1 {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text(line.departures.dropFirst().prefix(2).map { TimeText.short($0.time, clockTimes: clockTimes, now: ctx.date) }.joined(separator: " · "))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .opacity(0.8)
                    }
                }
            }
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(line.route.color.gradient)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
    }

    private var stopLine: String {
        var s = line.stop.name
        if let d = line.distance { s += " · \(d.walkingMinutes) min" }
        return s
    }
}

// MARK: - Chips

struct FilterChip: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = Theme.signal
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.caption.weight(.bold)) }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(selected ? Color.black : Color.primary)
            .background(selected ? AnyShapeStyle(tint) : AnyShapeStyle(.thinMaterial), in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? .clear : Color.primary.opacity(0.08)))
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.selection, trigger: selected)
    }
}

struct AgencyTag: View {
    let agencyID: String
    var body: some View {
        if let a = Catalog.agency(agencyID) {
            Text(a.shortName)
                .font(.caption2.weight(.heavy))
                .textCase(.uppercase)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .foregroundStyle(.white)
                .background(Color(hex: a.brandHex) ?? .gray, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }
}

// MARK: - Alerts

struct AlertCard: View {
    let alert: ServiceAlert
    var compact = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        AgencyTag(agencyID: alert.agencyID)
                        if let c = alert.category { Text(c).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Text(alert.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    if !alert.body.isEmpty && !compact {
                        Text(alert.body)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(expanded ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let start = alert.start, !compact {
                        Text(start, format: .relative(presentation: .named)).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            if expanded, let url = alert.url {
                Link(destination: url) { Label("More info", systemImage: "safari") }.font(.footnote.weight(.semibold))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 18)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
    }

    private var icon: String {
        switch alert.severity {
        case .severe: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }
    private var color: Color {
        switch alert.severity { case .severe: Theme.late; case .warning: .orange; case .info: .blue }
    }
}

// MARK: - Empty / loading states

struct LoadingCards: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 86)
                    .opacity(1 - Double(i) * 0.18)
            }
        }
        .phaseAnimator([0.55, 1]) { v, p in v.opacity(p) } animation: { _ in .easeInOut(duration: 0.9) }
        .accessibilityLabel("Loading departures")
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.signal)
                    .foregroundStyle(.black)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Primary button

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.black)
            .background(Theme.signal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25), value: configuration.isPressed)
    }
}
