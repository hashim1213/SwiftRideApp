import Foundation
import ActivityKit
import SwiftUI

/// Live Activity (Lock Screen + Dynamic Island) for a trip in progress. Shared by the app, which starts and
/// updates it, and the widget extension, which draws it. Countdowns use system timers, so they keep ticking
/// even when the app can't send an update (no signal, underground).
struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable { case walk, wait, ride, walkEnd, arrived }

        var phase: Phase
        /// Big instruction: "Walk to Union Station", "Get off in 3 stops".
        var title: String
        /// Supporting line: "21 departs 12:20 AM · Platform 4".
        var subtitle: String
        /// What the countdown counts to, and what to call it ("Leave in", "Departs in", "Off in").
        var target: Date
        var targetLabel: String
        /// The route this step is about (the next one while walking or waiting).
        var route: TransitRoute?
        var stopsRemaining: Int?
        /// Next step after this one: "Then change to 21 at Kipling".
        var then: String?
        var arriveAt: Date
        var usingGPS: Bool
    }

    let fromName: String
    let toName: String
    let leaveAt: Date
}

extension TripActivityAttributes.ContentState {
    var symbol: String {
        switch phase {
        case .walk, .walkEnd: return "figure.walk"
        case .wait: return route?.mode.symbol ?? "bus.fill"
        case .ride: return "arrow.down.to.line"
        case .arrived: return "flag.checkered"
        }
    }

    /// Short countdown for tight spots (compact Dynamic Island) when the timer isn't wanted.
    var shortTarget: String { TimeText.clock.string(from: target) }

    /// Timer range that's always valid (lower ≤ upper).
    var timerRange: ClosedRange<Date> { let now = Date(); return now...max(now, target) }
}
