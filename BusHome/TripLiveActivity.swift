import ActivityKit
import WidgetKit
import SwiftUI

/// Lock Screen banner and Dynamic Island for a trip in progress.
struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            TripLockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "swiftride://guide"))
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Group {
                        if let r = s.route, s.phase == .wait || s.phase == .ride { ActivityBadge(route: r, size: 17) }
                        else { PhaseIcon(state: s, size: 34) }
                    }
                    .padding(.leading, 4)
                    .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(s.targetLabel).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                        if s.phase == .arrived {
                            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Theme.live)
                        } else {
                            Text(timerInterval: s.timerRange, countsDown: true)
                                .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(Theme.signal)
                        }
                    }
                    .frame(minWidth: 84, alignment: .trailing)
                    .padding(.trailing, 4)
                    .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.title).font(.system(size: 18, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
                        Text(s.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        TripProgress(attributes: context.attributes, state: s)
                        if let then = s.then {
                            Label(then, systemImage: "arrow.turn.down.right").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                if let r = s.route, s.phase != .walk, s.phase != .walkEnd {
                    ActivityBadge(route: r, size: 13)
                } else {
                    Image(systemName: s.symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.signal)
                }
            } compactTrailing: {
                if s.phase == .ride, let n = s.stopsRemaining, n <= 9 {
                    Text(n == 0 ? "Off" : "\(n) stop\(n == 1 ? "" : "s")")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.signal)
                } else if s.phase == .arrived {
                    Image(systemName: "checkmark").foregroundStyle(Theme.live)
                } else {
                    Text(timerInterval: s.timerRange, countsDown: true)
                        .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 52)
                        .foregroundStyle(Theme.signal)
                }
            } minimal: {
                if let r = s.route, s.phase == .wait || s.phase == .ride {
                    ActivityBadge(route: r, size: 11)
                } else {
                    Image(systemName: s.symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.signal)
                }
            }
            .widgetURL(URL(string: "swiftride://guide"))
            .keylineTint(Theme.signal)
        }
    }
}

private struct TripLockScreenView: View {
    let attributes: TripActivityAttributes
    let state: TripActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                PhaseIcon(state: state, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title).font(.system(size: 19, weight: .heavy, design: .rounded)).lineLimit(2).minimumScaleFactor(0.8)
                    Text(state.subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(state.targetLabel).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                    if state.phase == .arrived {
                        Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(Theme.live)
                    } else if isStale {
                        // The app couldn't refresh (e.g. no signal): show the clock time instead of a stuck 0:00.
                        Text(state.shortTarget).font(.title3.weight(.heavy).monospacedDigit())
                    } else {
                        Text(timerInterval: state.timerRange, countsDown: true)
                            .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 96, alignment: .trailing)
                            .foregroundStyle(Theme.signal)
                    }
                }
            }
            TripProgress(attributes: attributes, state: state)
            HStack(spacing: 6) {
                if let then = state.then {
                    Image(systemName: "arrow.turn.down.right")
                    Text(then).lineLimit(1)
                } else {
                    Image(systemName: "flag.checkered")
                    Text(attributes.toName).lineLimit(1)
                }
                Spacer()
                Image(systemName: state.usingGPS ? "location.fill" : "clock.fill")
                Text("Arrive \(TimeText.clock.string(from: state.arriveAt))").monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

/// Whole-trip progress that advances on its own, from leave time to arrival.
private struct TripProgress: View {
    let attributes: TripActivityAttributes
    let state: TripActivityAttributes.ContentState
    var body: some View {
        let start = min(attributes.leaveAt, state.arriveAt.addingTimeInterval(-60))
        ProgressView(timerInterval: start...state.arriveAt, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            .tint(Theme.signal)
    }
}

private struct PhaseIcon: View {
    let state: TripActivityAttributes.ContentState
    let size: CGFloat
    var body: some View {
        let color = state.route.map { Color(hex: $0.colorHex) ?? Theme.signal } ?? Theme.signal
        Image(systemName: state.symbol)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(state.route.map { activityTextColor($0) } ?? .black)
            .frame(width: size, height: size)
            .background(state.phase == .walk || state.phase == .walkEnd || state.phase == .arrived ? Theme.signal : color,
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .environment(\.colorScheme, .light)
    }
}

private struct ActivityBadge: View {
    let route: TransitRoute
    let size: CGFloat
    var body: some View {
        Text(route.badgeText)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, size * 0.4)
            .frame(minWidth: size * 2, minHeight: size * 1.6)
            .foregroundStyle(activityTextColor(route))
            .background(Color(hex: route.colorHex) ?? .gray, in: RoundedRectangle(cornerRadius: size * 0.4, style: .continuous))
    }
}

private func activityTextColor(_ r: TransitRoute) -> Color {
    if let c = Color(hex: r.textColorHex), r.textColorHex.uppercased() != r.colorHex.uppercased() { return c }
    return (Color.luminance(hex: r.colorHex) ?? 0) > 0.6 ? .black : .white
}
